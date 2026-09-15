param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$Fixture,
    [Parameter(Mandatory = $true)][string]$Templates,
    [ValidateSet('debug', 'release')][string[]]$Modes = @('release', 'debug')
)
$ErrorActionPreference = 'Stop'
$fixturePath = (Resolve-Path -LiteralPath $Fixture).Path
$temporaryPath = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (-not $fixturePath.StartsWith($temporaryPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'This runner only mutates an existing isolated temporary fixture.'
}
$deckSource = Get-Content -LiteralPath (Join-Path $fixturePath 'scripts/autoload/DeckManager.gd') -Raw
if (-not $deckSource.Contains('res://test-user/')) { throw 'Fixture save paths are not isolated.' }
$config = Get-Content -LiteralPath (Join-Path $fixturePath 'project.godot') -Raw
if (-not $config.Contains('res://tests/match_features_network.gd')) { throw 'Fixture autoload is not isolated.' }
if ($config.Contains('initialize_on_startup=true')) { throw 'Steam automatic initialization must be disabled.' }

$presetsPath = Join-Path $fixturePath 'export_presets.cfg'
$presets = Get-Content -LiteralPath $presetsPath -Raw
foreach ($mode in @('debug', 'release')) {
    $templatePath = (Resolve-Path -LiteralPath (Join-Path $Templates ('windows_' + $mode + '_x86_64.exe'))).Path.Replace('\', '/')
    $presets = [regex]::Replace($presets, '(?m)^custom_template/' + $mode + '=.*$', 'custom_template/' + $mode + '="' + $templatePath + '"')
}
Set-Content -LiteralPath $presetsPath -Value $presets -Encoding utf8
$matrixRoot = Join-Path $fixturePath ('native-export-matrix-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $matrixRoot | Out-Null
$results = @()
foreach ($mode in $Modes) {
    $modeRoot = Join-Path $matrixRoot $mode
    New-Item -ItemType Directory -Path $modeRoot,(Join-Path $modeRoot 'test-user') | Out-Null
    $exe = Join-Path $modeRoot 'DarkestCards.exe'
    $exportLog = Join-Path $matrixRoot ($mode + '-export.log')
    $exportProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless','--path',$fixturePath,'--log-file',$exportLog,('--export-' + $mode),'"Windows Desktop"',$exe) -WindowStyle Hidden -Wait -PassThru
    Write-Output ($mode + ' export exit: ' + $exportProcess.ExitCode)
    if ($exportProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw ($mode + ' export failed; inspect ' + $exportLog) }
    if (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR:|SHADER ERROR:' -Quiet) {
        throw ($mode + ' export contains script or shader errors; inspect ' + $exportLog)
    }
    foreach ($library in @(('libgodotsteam.windows.template_' + $mode + '.x86_64.dll'),'steam_api64.dll')) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $fixturePath ('addons/godotsteam/win64/' + $library))).Hash
        $exportHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $modeRoot $library)).Hash
        if ($sourceHash -ne $exportHash) { throw ('Exported library hash mismatch: ' + $library) }
        Write-Output ($library + ' SHA256 ' + $exportHash)
    }
    foreach ($test in @(
        @{Name='native'; Scene='res://tests/native_peer_probe.tscn'; Marker='NATIVE_PEER_PROBE: PASS'},
        @{Name='lifecycle'; Scene='res://tests/network_lifecycle_test.tscn'; Marker='NETWORK_LIFECYCLE_TESTS: PASS'},
        @{Name='exit'; Scene='res://tests/multiplayer_exit_test.tscn'; Marker='MULTIPLAYER_EXIT_TESTS: PASS'},
        @{Name='replacement'; Scene='res://tests/replacement_network_test.tscn'; Marker='REPLACEMENT_NETWORK_TESTS: PASS'}
    )) {
        $log = Join-Path $modeRoot ($test.Name + '.log')
        $process = Start-Process -FilePath $exe -ArgumentList @('--headless','--rendering-method','gl_compatibility','--log-file',$log,'--max-fps','120','--quit-after','7200',$test.Scene) -WorkingDirectory $modeRoot -WindowStyle Hidden -Wait -PassThru
        $text = Get-Content -LiteralPath $log -Raw
        $passed = $process.ExitCode -eq 0 -and $text.Contains($test.Marker) -and $text -notmatch 'SCRIPT ERROR:|SHADER ERROR:|ERROR: Error calling from signal'
        $results += [pscustomobject]@{mode=$mode; test=$test.Name; exit_code=$process.ExitCode; passed=$passed; log=$log}
        Write-Output ($mode + ' ' + $test.Name + ' exit=' + $process.ExitCode + ' passed=' + $passed)
        if (-not $passed) { Get-Content -LiteralPath $log -Tail 30 }
        $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $matrixRoot 'results.json') -Encoding utf8
    }
}
Write-Output ('NATIVE_EXPORT_MATRIX_OUTPUT: ' + $matrixRoot)
if (@($results | Where-Object { -not $_.passed }).Count -gt 0) { exit 1 }
Write-Output 'NATIVE_EXPORT_MATRIX: PASS'
exit 0
