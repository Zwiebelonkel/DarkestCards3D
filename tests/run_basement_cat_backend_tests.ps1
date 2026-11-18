param([Parameter(Mandatory = $true)][string]$Godot)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('darkestcards-basement-cat-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot, (Join-Path $testRoot 'test-user') -Force | Out-Null
$sourcePaths = @(
    'scripts/autoload/Localization.gd', 'scripts/autoload/CardDatabase.gd',
    'scripts/autoload/SaveManager.gd', 'scripts/autoload/CollectionManager.gd',
    'scripts/autoload/EffectDatabase.gd', 'scripts/autoload/DeckManager.gd',
    'scripts/GameCurrency.gd', 'scripts/CardUpgradeManager.gd', 'scripts/match/OfflineMatchRules.gd',
    'scripts/card/CardData.gd', 'scripts/events/EventDeck.gd',
    'tests/basement_cat_collection_fixture.gd', 'tests/basement_cat_currency_fixture.gd',
    'tests/basement_cat_backend_test.gd', 'tests/basement_cat_backend_test.tscn',
    'data/cards.json', 'data/effects.json', 'fonts/VCR_OSD_MONO_1.001.ttf'
)
foreach ($relative in $sourcePaths) {
    $destination = Join-Path $testRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    if ($relative.EndsWith('.gd')) {
        $source = Get-Content -LiteralPath (Join-Path $projectRoot $relative) -Raw
        Set-Content -LiteralPath $destination -Value $source.Replace('user://', 'res://test-user/') -Encoding utf8
    } else {
        Copy-Item -LiteralPath (Join-Path $projectRoot $relative) -Destination $destination
    }
}
@'
config_version=5
[application]
config/name="BasementCatBackendTests"
run/main_scene="res://tests/basement_cat_backend_test.tscn"
[autoload]
Localization="*res://scripts/autoload/Localization.gd"
CardDatabase="*res://scripts/autoload/CardDatabase.gd"
SaveSlots="*res://scripts/autoload/SaveManager.gd"
CollectionManager="*res://tests/basement_cat_collection_fixture.gd"
GameCurrency="*res://tests/basement_cat_currency_fixture.gd"
DeckManager="*res://scripts/autoload/DeckManager.gd"
CardUpgradeManager="*res://scripts/CardUpgradeManager.gd"
EffectDatabase="*res://scripts/autoload/EffectDatabase.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'project.godot') -Encoding utf8
$importLog = Join-Path $testRoot 'import.log'
$importProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--editor', '--import', '--path', $testRoot, '--quit', '--log-file', $importLog) -WindowStyle Hidden -Wait -PassThru
# A fresh Godot directory scans autoload preloads before its first font import.
# Validate once more after assets exist; all final parser errors still fail.
if ($importProcess.ExitCode -eq 0) {
    $importProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--editor', '--import', '--path', $testRoot, '--quit', '--log-file', $importLog) -WindowStyle Hidden -Wait -PassThru
}
if ($importProcess.ExitCode -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|Parse Error:' -Quiet)) {
    Get-Content -LiteralPath $importLog
    throw "Basement cat test import failed: $testRoot"
}
$testLog = Join-Path $testRoot 'test.log'
$testProcess = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', $testRoot, '--log-file', $testLog, '--quit-after', '600', '--max-fps', '120') -WindowStyle Hidden -Wait -PassThru
Get-Content -LiteralPath $testLog
Write-Output "Isolated test output: $testRoot"
if ($testProcess.ExitCode -ne 0 -or -not (Select-String -LiteralPath $testLog -SimpleMatch 'BASEMENT_CAT_BACKEND_TESTS: PASS' -Quiet) -or (Select-String -LiteralPath $testLog -Pattern 'SCRIPT ERROR:|Parse Error:' -Quiet)) {
    exit 1
}
exit 0

