param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('darkestcards-character-export-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $probeRoot, (Join-Path $probeRoot 'scripts/ui'), (Join-Path $probeRoot 'assets/characters/player') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts/ui/CharacterAppearance.gd') -Destination (Join-Path $probeRoot 'scripts/ui/CharacterAppearance.gd')
foreach ($folder in @('faces', 'hats', 'mouths')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot "assets/characters/player/$folder") -Destination (Join-Path $probeRoot "assets/characters/player/$folder") -Recurse
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'character_catalogue_export_probe.gd') -Destination (Join-Path $probeRoot 'probe.gd')
$expected = @{}
foreach ($folder in @('faces', 'hats', 'mouths')) {
    $expected[$folder] = @(Get-ChildItem -LiteralPath (Join-Path $probeRoot "assets/characters/player/$folder") -File | Where-Object { $_.Extension.ToLowerInvariant() -in @('.png', '.webp', '.jpg', '.jpeg', '.svg', '.bmp', '.tga', '.res', '.tres') } | ForEach-Object { $_.BaseName })
}
[IO.File]::WriteAllText((Join-Path $probeRoot 'expected.json'), ($expected | ConvertTo-Json))
[IO.File]::WriteAllText((Join-Path $probeRoot 'project.godot'), @'
config_version=5
[application]
config/name="Character catalogue export probe"
run/main_scene="res://probe.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
'@)
[IO.File]::WriteAllText((Join-Path $probeRoot 'probe.tscn'), @'
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="CatalogueProbe" type="Node"]
script = ExtResource("1")
'@)
[IO.File]::WriteAllText((Join-Path $probeRoot 'export_presets.cfg'), @'
[preset.0]
name="Probe"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.json"
script_export_mode=2
[preset.0.options]
binary_format/architecture="x86_64"
'@)
$import = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--editor', '--path', $probeRoot, '--import', '--log-file', (Join-Path $probeRoot 'import.log')) -WindowStyle Hidden -Wait -PassThru
if ($import.ExitCode -ne 0) { throw "Catalogue import failed: $probeRoot" }
$pack = Join-Path $probeRoot 'catalogue.pck'
$export = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', $probeRoot, '--export-pack', 'Probe', $pack, '--log-file', (Join-Path $probeRoot 'export.log')) -WindowStyle Hidden -Wait -PassThru
if ($export.ExitCode -ne 0) { throw "Catalogue PCK export failed: $probeRoot" }
$log = Join-Path $probeRoot 'packed-run.log'
$run = Start-Process -FilePath $Godot -WorkingDirectory ([IO.Path]::GetTempPath()) -ArgumentList @('--headless', '--main-pack', $pack, '--log-file', $log, '--quit-after', '300') -WindowStyle Hidden -Wait -PassThru
Get-Content -LiteralPath $log
Write-Output "Export probe: $probeRoot"
if ($run.ExitCode -ne 0 -or -not (Select-String -LiteralPath $log -SimpleMatch 'CHARACTER_CATALOGUE_EXPORT: PASS' -Quiet)) { throw 'Packed catalogue discovery failed.' }
