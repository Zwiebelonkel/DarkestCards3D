param([Parameter(Mandatory = $true)][string]$Suite)
$ErrorActionPreference = 'Stop'
if ($Suite -notmatch '^[a-z0-9_]+$') { throw 'Invalid suite name' }
$auditSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$auditRoot = Join-Path ([IO.Path]::GetTempPath()) ('darkestcards-documentation-' + $Suite + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $auditRoot, (Join-Path $auditRoot 'test-user'), (Join-Path $auditRoot '.godot') -Force | Out-Null
foreach ($folder in @('scripts', 'scenes', 'tests', 'data', 'localization')) {
    Copy-Item -LiteralPath (Join-Path $auditSource $folder) -Destination (Join-Path $auditRoot $folder) -Recurse
}
foreach ($folder in @('assets', 'fonts', 'fx', 'addons')) {
    New-Item -ItemType Junction -Path (Join-Path $auditRoot $folder) -Target (Join-Path $auditSource $folder) | Out-Null
}
New-Item -ItemType Junction -Path (Join-Path $auditRoot '.godot/imported') -Target (Join-Path $auditSource '.godot/imported') | Out-Null
foreach ($file in @('global_script_class_cache.cfg', 'uid_cache.bin', 'extension_list.cfg')) {
    $auditCache = Join-Path $auditSource ".godot/$file"
    if (Test-Path -LiteralPath $auditCache) { Copy-Item -LiteralPath $auditCache -Destination (Join-Path $auditRoot ".godot/$file") }
}
foreach ($folder in @('scripts', 'scenes')) {
    Get-ChildItem -LiteralPath (Join-Path $auditRoot $folder) -Recurse -Filter '*.gd' | ForEach-Object {
        $auditText = [IO.File]::ReadAllText($_.FullName)
        [IO.File]::WriteAllText($_.FullName, $auditText.Replace('user://', 'res://test-user/'))
    }
}
$auditConfig = [IO.File]::ReadAllText((Join-Path $auditSource 'project.godot'))
$auditConfig = $auditConfig.Replace('*res://scripts/autoload/NetworkManager.gd', '*res://tests/match_features_network.gd')
if ($Suite -eq 'collection_performance_test') {
    $auditConfig = $auditConfig.Replace('*res://scripts/autoload/CollectionManager.gd', '*res://tests/collection_performance_manager.gd')
}
$auditConfig = $auditConfig.Replace('initialization/processes/initialize_on_startup=true', 'initialization/processes/initialize_on_startup=false')
$auditConfig = $auditConfig.Replace('window/size/mode=3', "window/size/mode=0`nwindow/size/viewport_width=1280`nwindow/size/viewport_height=720")
[IO.File]::WriteAllText((Join-Path $auditRoot 'project.godot'), $auditConfig)
$auditMain = Join-Path $auditRoot 'scenes/main/Main.tscn'
$auditText = [IO.File]::ReadAllText($auditMain)
[IO.File]::WriteAllText($auditMain, $auditText.Replace('script = ExtResource("1_main")', "script = ExtResource(`"1_main`")`ngreeting_enabled = false"))
Copy-Item -LiteralPath (Join-Path $auditSource 'default_bus_layout.tres') -Destination $auditRoot
Write-Output $auditRoot
