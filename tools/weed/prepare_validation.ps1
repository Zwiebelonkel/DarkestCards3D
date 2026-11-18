$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('darkestcards-weed-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot, (Join-Path $testRoot 'test-user'), (Join-Path $testRoot '.godot') -Force | Out-Null
foreach ($directory in @('scripts', 'scenes', 'data', 'tests', 'localization', 'tools')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination (Join-Path $testRoot $directory) -Recurse
}
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
$project = $project.Replace('*res://scripts/autoload/NetworkManager.gd', '*res://tests/match_features_network.gd')
$project = $project.Replace('window/size/mode=3', "window/size/mode=0`nwindow/size/viewport_width=1280`nwindow/size/viewport_height=720")
[System.IO.File]::WriteAllText((Join-Path $testRoot 'project.godot'), $project)
Copy-Item -LiteralPath (Join-Path $projectRoot 'default_bus_layout.tres') -Destination $testRoot
Write-Output $testRoot
