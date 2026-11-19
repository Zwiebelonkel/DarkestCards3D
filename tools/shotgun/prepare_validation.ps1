$ErrorActionPreference = 'Stop'
$fixtureRoot = & (Join-Path $PSScriptRoot '../weed/prepare_validation.ps1')
# These integration fixtures start in an already-entered hub.
$mainPath = Join-Path $fixtureRoot 'scenes/main/Main.tscn'
$mainText = [System.IO.File]::ReadAllText($mainPath).Replace('script = ExtResource("1_main")', "script = ExtResource(`"1_main`")`ngreeting_enabled = false")
[System.IO.File]::WriteAllText($mainPath, $mainText)
$settingsPath = Join-Path $fixtureRoot 'scripts/autoload/SettingsManager.gd'
$settingsText = [System.IO.File]::ReadAllText($settingsPath).Replace('const DEFAULT_FULLSCREEN := true', 'const DEFAULT_FULLSCREEN := false')
[System.IO.File]::WriteAllText($settingsPath, $settingsText)
Write-Output $fixtureRoot
