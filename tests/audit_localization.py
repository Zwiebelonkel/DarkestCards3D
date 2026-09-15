"""Validate CSV localization and list untranslated authored text candidates."""
from pathlib import Path
import csv
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ("en", "de", "es", "fr", "pl")
STRING = re.compile(r'"(?:\\.|[^"\\])*"', re.S)
PLACEHOLDER = re.compile(r'%(?:[-+0#]*\d*(?:\.\d+)?[sdifuxXo])|%%')
SCENE_TEXT = re.compile(
    r'^[ \t]*(?P<property>(?:popup/item_\d+/)?(?:text|label_text|tooltip_text|'
    r'placeholder_text|title|dialog_text|ok_button_text|cancel_button_text|suffix|prefix))'
    r'\s*=\s*(?P<value>"(?:\\.|[^"\\])*")', re.M
)
# These are scene-editor samples, never the text shown by their live controller.
# Keep exemptions scoped to the exact scene and source value: a new caption is
# still audited even when added to a scene that contains runtime placeholders.
SCENE_PLACEHOLDERS = {
    "scenes/table/Card3D.tscn": {
        "Effects: -": "EffectsLabel is hidden; effect icons provide the live UI",
        "CARD NAME": "Card3D.setup supplies the localized catalog name",
        "Description...": "Card3D.setup supplies the localized catalog description",
    },
    "scenes/CardEffectOverview.tscn": {
        "CARD NAME": "the initially hidden overview is populated before opening",
        "EFFECT NAME": "the initially hidden overview is populated before opening",
        "Effect description": "the initially hidden overview is populated before opening",
        "2 EFFEKTE": "the initially hidden overview computes the current effect count",
    },
    "scenes/ui/LevelProgress.tscn": {
        "LEVEL 1": "LevelProgress._update_labels uses the live LEVEL %d template",
        "0 / 100 XP": "LevelProgress._update_labels uses the live %d / %d XP template",
        "Nächstes Level: +25 Soul Coins": "LevelProgress._update_labels uses the live bonus template",
        "20,00 Soul Coins": "LevelProgress._update_coin_label uses the live balance template",
        "+0,02 Münzen": "LevelProgress._refresh_clicker_state uses the live click-reward template",
    },
    "scenes/Table3DButton.tscn": {
        "Start": "Table3DButton._ready replaces this sample with its exported label_text",
    },
    "scenes/PackPreviewViewport.tscn": {
        "5 KARTEN": "PackPreviewViewport._refresh_labels uses the current %d KARTEN template",
        "5 COINS": "PackPreviewViewport._refresh_labels uses the current %d COINS template",
    },
    "scenes/UpgradeUI.tscn": {
        "0 SOUL COINS": "UpgradeUI.refresh_balance replaces this initial balance",
        "0 KARTEN": "UpgradeUI.set_cards computes the current card-type count",
        "0 / 2 BELEGT": "UpgradeUI._refresh_effect_slots computes the current effect count",
        "ANGRIFF +1\n5 SOUL COINS": "UpgradeUI._ready updates each cost from the economy",
        "LEBEN +1\n5 SOUL COINS": "UpgradeUI._ready updates each cost from the economy",
        "EFFEKT WÜRFELN\n12 SOUL COINS": "UpgradeUI._ready updates each cost from the economy",
    },
}
NEUTRAL_TEXT = re.compile(r'^[\s\d.,+\-−—<>/%◆]*$|^[<>\s−—\-\d.,]+dB$')


def scene_coverage(entries):
    """Audit text properties only, excluding IDs, comments and numeric UI values."""
    missing = []
    checked = 0
    placeholders = 0
    paths = sorted((ROOT / "scenes").rglob("*.tscn"))
    for path in paths:
        relative = path.relative_to(ROOT).as_posix()
        source = path.read_text(encoding="utf-8-sig")
        for match in SCENE_TEXT.finditer(source):
            try:
                value = json.loads(match["value"].replace("\n", "\\n").replace("\r", "\\r"))
            except ValueError as error:
                missing.append(f"{relative}: invalid text literal: {error}")
                continue
            if not value.strip() or NEUTRAL_TEXT.fullmatch(value):
                continue
            checked += 1
            if value in entries:
                continue
            if value in SCENE_PLACEHOLDERS.get(relative, {}):
                placeholders += 1
                continue
            line = source.count("\n", 0, match.start()) + 1
            missing.append(f"{relative}:{line} {match['property']}={json.dumps(value, ensure_ascii=False)}")
    for item in missing:
        print("MISSING_SCENE_TEXT: " + item)
    print(f"LOCALIZATION_SCENES: {'FAIL' if missing else 'PASS'} "
          f"({len(paths)} scenes, {checked} text values, {placeholders} runtime placeholders, {len(missing)} missing)")
    return missing

def strings(path):
    source = path.read_text(encoding="utf-8-sig")
    for match in STRING.finditer(source):
        before = source[source.rfind("\n", 0, match.start()) + 1:match.start()]
        if before.lstrip().startswith("#"):
            continue
        try:
            value = json.loads(match.group().replace("\n", "\\n").replace("\r", "\\r"))
        except ValueError:
            continue
        yield value, source.count("\n", 0, match.start()) + 1, before

def catalogs():
    entries = {}
    failures = []
    for path in sorted((ROOT / "localization").glob("*.csv")):
        with path.open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            if reader.fieldnames != ["keys", *LOCALES]:
                failures.append(f"{path.name}: expected keys,en,de,es,fr,pl header")
            for row in reader:
                key = row.get("keys", "")
                if not key:
                    failures.append(f"{path.name}:{reader.line_num}: empty source key")
                    continue
                if key in entries and entries[key] != row:
                    failures.append(f"{path.name}:{reader.line_num}: conflicting duplicate {key!r}")
                entries[key] = row
                placeholders = PLACEHOLDER.findall(key)
                for locale in LOCALES:
                    value = row.get(locale)
                    if not value:
                        failures.append(f"{path.name}:{reader.line_num}: missing {locale}: {key!r}")
                    elif PLACEHOLDER.findall(value) != placeholders:
                        failures.append(f"{path.name}:{reader.line_num}: {locale} placeholders differ: {key!r}")
                if None in row:
                    failures.append(f"{path.name}:{reader.line_num}: malformed CSV column count")
    return entries, failures

def main():
    entries, failures = catalogs()
    missing_scenes = scene_coverage(entries) if "--scenes" in sys.argv else []
    if "--candidates" in sys.argv:
        paths = [ROOT / p for p in sys.argv[sys.argv.index("--candidates") + 1:]]
        seen = set()
        for path in paths:
            for value, line, before in strings(path):
                if value in entries or value in seen or not re.search(r'[A-Za-zÀ-ž]', value):
                    continue
                if any(part in value for part in ("res://", "user://", "http", "shader_", "global_", "font_")):
                    continue
                if " " not in value and not value.isupper() and value.isascii():
                    continue
                seen.add(value)
                print(f"{path.relative_to(ROOT)}:{line}\t{json.dumps(value, ensure_ascii=False)}")
        return
    for failure in failures:
        print(failure)
    print(f"LOCALIZATION_CSV: {'FAIL' if failures else 'PASS'} ({len(entries)} messages, {len(LOCALES)} languages)")
    raise SystemExit(bool(failures or missing_scenes))

if __name__ == "__main__":
    main()
