param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [switch]$Visual,
    [switch]$ImportAssets,
    [string]$TestScene = 'res://tests/match_features_test.tscn',
    [string]$SuccessMarker = 'MATCH_FEATURE_TESTS: PASS',
    [int]$QuitAfterFrames = 3600
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('darkestcards-match-features-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot, (Join-Path $testRoot 'test-user') -Force | Out-Null
foreach ($folder in @('scripts', 'scenes', 'tests', 'assets', 'fonts', 'fx', 'data', 'localization', 'addons', '.godot')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination (Join-Path $testRoot $folder) -Recurse
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'default_bus_layout.tres') -Destination $testRoot
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$config = $config.Replace('res://scripts/autoload/NetworkManager.gd', 'res://tests/match_features_network.gd')
$config = $config.Replace('res://scenes/main/MainMenu.tscn', $TestScene)
$config = $config.Replace('initialization/processes/initialize_on_startup=true', 'initialization/processes/initialize_on_startup=false')
$config = $config.Replace('window/size/mode=3', "window/size/mode=0`nwindow/size/viewport_width=1280`nwindow/size/viewport_height=720")
Set-Content -LiteralPath (Join-Path $testRoot 'project.godot') -Value $config -Encoding utf8
# Redirect all persistence before any autoload starts; real player saves are untouched.
Get-ChildItem -LiteralPath (Join-Path $testRoot 'scripts') -Recurse -Filter '*.gd' | ForEach-Object {
    $source = Get-Content -LiteralPath $_.FullName -Raw
    if ($source.Contains('user://')) {
        Set-Content -LiteralPath $_.FullName -Value $source.Replace('user://', 'res://test-user/') -Encoding utf8
    }
}
if ($ImportAssets) {
    $importProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--import', '--path', $testRoot, '--log-file', (Join-Path $testRoot 'import.log'), '--rendering-method', 'gl_compatibility') -WindowStyle Hidden -Wait -PassThru
    if ($importProcess.ExitCode -ne 0) {
        throw 'Match test asset import failed.'
    }
}
if ($Visual) {
    $testProcess = Start-Process -FilePath $Godot -ArgumentList @('--path', $testRoot, '--log-file', (Join-Path $testRoot 'test.log'), '--rendering-method', 'gl_compatibility', '--quit-after', "$QuitAfterFrames", '--max-fps', '120') -WindowStyle Hidden -Wait -PassThru
    $testExitCode = $testProcess.ExitCode
    Get-Content -LiteralPath (Join-Path $testRoot 'test.log')
} else {
    # The Windows GUI executable can return to PowerShell before its process
    # exits, even with --headless. Wait before inspecting its exit code/log.
    $testProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', $testRoot, '--log-file', (Join-Path $testRoot 'test.log'), '--quit-after', "$QuitAfterFrames", '--max-fps', '120') -WindowStyle Hidden -Wait -PassThru
    $testExitCode = $testProcess.ExitCode
    Get-Content -LiteralPath (Join-Path $testRoot 'test.log')
}
if (-not (Select-String -LiteralPath (Join-Path $testRoot 'test.log') -SimpleMatch $SuccessMarker -Quiet)) {
    $testExitCode = 1
}
if (Select-String -LiteralPath (Join-Path $testRoot 'test.log') -Pattern 'SCRIPT ERROR:|SHADER ERROR:|ERROR: Error calling from signal' -Quiet) {
    $testExitCode = 1
}
if ($TestScene -eq 'res://tests/match_features_test.tscn') {
    $networkProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', $testRoot, '--log-file', (Join-Path $testRoot 'network-roles.log'), '--script', 'res://tests/network_roles_test.gd') -WindowStyle Hidden -Wait -PassThru
    Get-Content -LiteralPath (Join-Path $testRoot 'network-roles.log')
    if ($networkProcess.ExitCode -ne 0 -or -not (Select-String -LiteralPath (Join-Path $testRoot 'network-roles.log') -SimpleMatch 'Network role tests passed:' -Quiet)) {
        $testExitCode = 1
    }
}
Write-Output "Isolated test output: $testRoot"
exit $testExitCode
