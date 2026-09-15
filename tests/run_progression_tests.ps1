param([Parameter(Mandatory = $true)][string]$Godot)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('darkestcards-progression-tests-' + [guid]::NewGuid().ToString('N'))
$testExitCode = 1
try {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'scripts/ui'), (Join-Path $testRoot 'scenes/ui'), (Join-Path $testRoot 'tests'), (Join-Path $testRoot 'assets/sounds/SFX') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts/ui/LevelProgress.gd') -Destination (Join-Path $testRoot 'scripts/ui/LevelProgress.gd')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'scenes/ui/LevelProgress.tscn') -Destination (Join-Path $testRoot 'scenes/ui/LevelProgress.tscn')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'fonts') -Destination (Join-Path $testRoot 'fonts') -Recurse
    Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/sounds/SFX/button.mp3') -Destination (Join-Path $testRoot 'assets/sounds/SFX/button.mp3')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'progression_test.gd') -Destination (Join-Path $testRoot 'tests/progression_test.gd')
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'scripts/autoload'), (Join-Path $testRoot 'scripts/card'), (Join-Path $testRoot 'test-user') -Force | Out-Null
    foreach ($sourcePath in @('scripts/GameCurrency.gd', 'scripts/autoload/Localization.gd', 'scripts/autoload/CardDatabase.gd', 'scripts/autoload/CollectionManager.gd', 'scripts/autoload/EffectDatabase.gd', 'scripts/card/CardData.gd')) {
        $source = Get-Content -LiteralPath (Join-Path $projectRoot $sourcePath) -Raw
        Set-Content -LiteralPath (Join-Path $testRoot $sourcePath) -Value $source.Replace('user://', 'res://test-user/') -Encoding utf8
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'data') -Destination (Join-Path $testRoot 'data') -Recurse
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'localization') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'localization/game.csv') -Destination (Join-Path $testRoot 'localization/game.csv')
    @'
config_version=5
[application]
config/name="DarkestCardsProgressionTests"
run/main_scene="res://tests/ProgressionTest.tscn"
[autoload]
Localization="*res://scripts/autoload/Localization.gd"
CardDatabase="*res://scripts/autoload/CardDatabase.gd"
EffectDatabase="*res://scripts/autoload/EffectDatabase.gd"
CollectionManager="*res://scripts/autoload/CollectionManager.gd"
GameCurrency="*res://scripts/GameCurrency.gd"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
[internationalization]
locale/translations=PackedStringArray("res://localization/game.en.translation", "res://localization/game.de.translation", "res://localization/game.es.translation", "res://localization/game.fr.translation", "res://localization/game.pl.translation")
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'project.godot') -Encoding utf8
    @'
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/progression_test.gd" id="1"]
[node name="ProgressionTest" type="Node"]
script = ExtResource("1")
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'tests/ProgressionTest.tscn') -Encoding utf8
    $importProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--editor', '--import', '--path', $testRoot, '--quit', '--log-file', (Join-Path $testRoot 'import.log')) -WindowStyle Hidden -Wait -PassThru
    if ($importProcess.ExitCode -ne 0) {
        throw 'Progression test asset import failed.'
    }
    # The Windows GUI executable may return to its shell before Godot exits.
    # Wait on the process before reading the marker or checking its exit code.
    $testProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--log-file', (Join-Path $testRoot 'godot.log'), '--path', $testRoot, '--quit-after', '600', '--max-fps', '120') -WindowStyle Hidden -Wait -PassThru
    $testExitCode = $testProcess.ExitCode
    Get-Content -LiteralPath (Join-Path $testRoot 'godot.log')
    if (-not (Select-String -LiteralPath (Join-Path $testRoot 'godot.log') -SimpleMatch 'PASS: progression boundaries' -Quiet)) {
        $testExitCode = 1
    }
    if (Select-String -LiteralPath (Join-Path $testRoot 'godot.log') -Pattern 'SCRIPT ERROR:|SHADER ERROR:|ERROR: Error calling from signal' -Quiet) {
        $testExitCode = 1
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
        $expectedPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\darkestcards-progression-tests-'
        if (-not $resolvedTestRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected test path: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
exit $testExitCode
