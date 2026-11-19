$ErrorActionPreference = 'Stop'
$fixtureRoot = & (Join-Path $PSScriptRoot '../weed/prepare_validation.ps1')
# Match the existing match-feature fixture's already-entered hub; the greeting
# owns input until it finishes and is unrelated to a block presentation test.
$mainPath = Join-Path $fixtureRoot 'scenes/main/Main.tscn'
$mainText = [System.IO.File]::ReadAllText($mainPath)
$mainText = $mainText.Replace('script = ExtResource("1_main")', "script = ExtResource(`"1_main`")`ngreeting_enabled = false")
[System.IO.File]::WriteAllText($mainPath, $mainText)
# The owned renderer must stay windowed/off-desktop even with fresh settings.
$settingsPath = Join-Path $fixtureRoot 'scripts/autoload/SettingsManager.gd'
$settingsText = [System.IO.File]::ReadAllText($settingsPath).Replace('const DEFAULT_FULLSCREEN := true', 'const DEFAULT_FULLSCREEN := false')
[System.IO.File]::WriteAllText($settingsPath, $settingsText)
Write-Output $fixtureRoot
