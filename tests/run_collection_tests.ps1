param(
    [string]$Godot = 'C:\Users\Luca\Desktop\Godot_v4.4.1-stable_win64.exe',
    [string[]]$Scenes = @('collection_performance_test'),
    [switch]$Baseline
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('darkestcards-collection-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot, (Join-Path $testRoot 'test-user'), (Join-Path $testRoot '.godot') -Force | Out-Null
foreach ($directory in @('scripts', 'scenes', 'data', 'tests', 'localization')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination (Join-Path $testRoot $directory) -Recurse
}
# Share immutable imported resources; copy all code and redirect every save.
foreach ($directory in @('assets', 'fonts', 'fx', 'addons')) {
    New-Item -ItemType Junction -Path (Join-Path $testRoot $directory) -Target (Join-Path $projectRoot $directory) | Out-Null
}
New-Item -ItemType Junction -Path (Join-Path $testRoot '.godot/imported') -Target (Join-Path $projectRoot '.godot/imported') | Out-Null
foreach ($file in @('global_script_class_cache.cfg', 'uid_cache.bin', 'extension_list.cfg')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ".godot/$file") -Destination (Join-Path $testRoot ".godot/$file")
}
Get-ChildItem -LiteralPath (Join-Path $testRoot 'scripts'), (Join-Path $testRoot 'scenes') -Filter '*.gd' -Recurse | ForEach-Object {
    $source = [System.IO.File]::ReadAllText($_.FullName)
    [System.IO.File]::WriteAllText($_.FullName, $source.Replace('user://', 'res://test-user/'))
}
$project = [System.IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
$project = $project.Replace('initialization/processes/initialize_on_startup=true', 'initialization/processes/initialize_on_startup=false')
$project = $project.Replace('*res://scripts/autoload/CollectionManager.gd', '*res://tests/collection_performance_manager.gd')
$project = $project.Replace('*res://scripts/autoload/NetworkManager.gd', '*res://tests/match_features_network.gd')
$project = $project.Replace('window/size/mode=3', "window/size/mode=0`nwindow/size/viewport_width=1280`nwindow/size/viewport_height=720")
[System.IO.File]::WriteAllText((Join-Path $testRoot 'project.godot'), $project)
# Room tests start in the already-entered hub; its greeting has a separate suite.
$mainPath = Join-Path $testRoot 'scenes/main/Main.tscn'
$mainScene = [System.IO.File]::ReadAllText($mainPath)
$mainScene = $mainScene.Replace('script = ExtResource("1_main")', "script = ExtResource(`"1_main`")`ngreeting_enabled = false")
[System.IO.File]::WriteAllText($mainPath, $mainScene)
Copy-Item -LiteralPath (Join-Path $projectRoot 'default_bus_layout.tres') -Destination $testRoot
Write-Output "Isolated test project: $testRoot"
$failed = $false
foreach ($scene in $Scenes) {
    $logPath = Join-Path $testRoot "$scene.log"
    $arguments = @('--headless', '--path', ('"' + $testRoot + '"'), '--log-file', ('"' + $logPath + '"'), '--quit-after', '2400', '--max-fps', '120', "res://tests/$scene.tscn")
    if ($Baseline) { $arguments += @('--', '--baseline') }
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(90000)) {
        $process.Kill()
        $failed = $true
    }
    Get-Content -LiteralPath $logPath
    $log = Get-Content -LiteralPath $logPath -Raw
    if ($process.ExitCode -ne 0 -or $log -match '(?m)^FAIL\b|_TESTS: FAIL\b|SCRIPT ERROR:|SHADER ERROR:' -or $log -notmatch '_TESTS: PASS') { $failed = $true }
}
if ($failed) { exit 1 }
