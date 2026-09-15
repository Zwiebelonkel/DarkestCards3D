param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [ValidateSet('release', 'debug')][string]$Mode = 'release',
    [string]$ExportTemplate
)

$ErrorActionPreference = 'Stop'
$enginePath = (Resolve-Path -LiteralPath $Godot).Path
$lockPath = Join-Path $PSScriptRoot 'addons/godotsteam/dependency-lock.json'
$dependency = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
foreach ($entry in $dependency.windows_x86_64) {
    $dependencyPath = Join-Path $PSScriptRoot ('addons/godotsteam/win64/' + $entry.file)
    if ((Get-FileHash -LiteralPath $dependencyPath -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw "GodotSteam dependency changed: $($entry.file). Restore the tested bundle or validate native release teardown before updating dependency-lock.json."
    }
}
$buildId = Get-Date -Format 'yyyyMMdd-HHmmss'
$buildRoot = Join-Path $PSScriptRoot 'builds'
$outputRoot = Join-Path $buildRoot ('windows-online-' + $Mode + '-' + $buildId)
$snapshotRoot = Join-Path ([IO.Path]::GetTempPath()) ('darkestcards-online-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputRoot, $snapshotRoot | Out-Null

# Export a snapshot so existing exports, editor imports and player saves stay intact.
foreach ($folder in @('scripts', 'scenes', 'assets', 'fonts', 'fx', 'data', 'localization', 'addons', '.godot')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $folder) -Destination (Join-Path $snapshotRoot $folder) -Recurse
}
foreach ($file in @('project.godot', 'export_presets.cfg', 'default_bus_layout.tres', 'icon.svg', 'icon.svg.import')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $snapshotRoot
}

# A custom template is optional; it must match the selected mode and editor.
# Keep it in the snapshot so the user's regular export preset stays intact.
if ($ExportTemplate) {
    $templatePath = (Resolve-Path -LiteralPath $ExportTemplate).Path.Replace('\', '/')
    $presetPath = Join-Path $snapshotRoot 'export_presets.cfg'
    $preset = Get-Content -LiteralPath $presetPath -Raw
    $pattern = '(?m)^custom_template/' + $Mode + '="[^"]*"'
    $preset = [regex]::Replace($preset, $pattern, ('custom_template/' + $Mode + '="' + $templatePath + '"'))
    [IO.File]::WriteAllText($presetPath, $preset)
}

$exePath = Join-Path $outputRoot 'DarkestCards.exe'
$exportLog = Join-Path $outputRoot 'export.log'
$engineArgs = @('--headless', '--path', ('"' + $snapshotRoot + '"'), '--log-file', ('"' + $exportLog + '"'), ('--export-' + $Mode), '"Windows Desktop"', ('"' + $exePath + '"'))
$process = Start-Process -FilePath $enginePath -ArgumentList $engineArgs -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
    throw "Windows $Mode export failed. See $exportLog"
}
if (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR:|SHADER ERROR:|ERROR:' -Quiet) {
    throw "The export reported errors. See $exportLog"
}

$libraryName = 'libgodotsteam.windows.template_' + $Mode + '.x86_64.dll'
$packageNames = @('DarkestCards.exe', $libraryName, 'steam_api64.dll')
$hashes = foreach ($name in $packageNames) {
    $path = Join-Path $outputRoot $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing exported file: $name" }
    [ordered]@{ file = $name; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$expectedLibrary = Join-Path $PSScriptRoot ('addons/godotsteam/win64/' + $libraryName)
if ($hashes[1].sha256 -ne (Get-FileHash -LiteralPath $expectedLibrary -Algorithm SHA256).Hash) {
    throw "Exported Steam library does not match the $Mode library in the project."
}
$expectedSteamApi = Join-Path $PSScriptRoot 'addons/godotsteam/win64/steam_api64.dll'
if ($hashes[2].sha256 -ne (Get-FileHash -LiteralPath $expectedSteamApi -Algorithm SHA256).Hash) {
    throw 'Exported Steam API library does not match the pinned bundle.'
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs/online-crash-diagnostics.md') -Destination (Join-Path $outputRoot 'README-Online-Test.md')
[ordered]@{
    built_at = (Get-Date).ToString('o')
    export_mode = $Mode
    intended_engine = 'Godot 4.4.1 stable Windows x86_64'
    godotsteam_release = $dependency.release
    godotsteam_archive_sha256 = $dependency.archive_sha256
    purpose = 'Online session teardown fix: pinned GodotSteam bundle without the destructor callback regression.'
    files = @($hashes)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputRoot 'build-info.json') -Encoding utf8

$packageNames += @('README-Online-Test.md', 'build-info.json')
$slotNotes = Join-Path $PSScriptRoot 'docs/slot-machine.md'
if (Test-Path -LiteralPath $slotNotes) {
    Copy-Item -LiteralPath $slotNotes -Destination (Join-Path $outputRoot 'Soul-Slots.md')
    $packageNames += 'Soul-Slots.md'
}
$updateNotes = Join-Path $PSScriptRoot 'docs/card-economy-update.md'
if (Test-Path -LiteralPath $updateNotes) {
    Copy-Item -LiteralPath $updateNotes -Destination (Join-Path $outputRoot 'Karten-Update.md')
    $packageNames += 'Karten-Update.md'
}
$packageFiles = @($packageNames | ForEach-Object { Join-Path $outputRoot $_ })
$zipPath = Join-Path $buildRoot ('DarkestCards-Online-' + $Mode + '-' + $buildId + '.zip')
Compress-Archive -LiteralPath $packageFiles -DestinationPath $zipPath -CompressionLevel Optimal
Write-Output "Standalone $Mode export: $exePath"
Write-Output "Package: $zipPath"
Write-Output "Build snapshot: $snapshotRoot"
