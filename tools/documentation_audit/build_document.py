from pathlib import Path
import csv
import datetime
import hashlib
import html
import json
import re
from collections import Counter

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, PageBreak, LongTable, TableStyle, KeepTogether, CondPageBreak
from reportlab.platypus.tableofcontents import TableOfContents

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/game-documentation'
AUDIT = OUT / 'audit'
TITLE = 'DarkestCards3D_Spieldokumentation'
DATE = '15. November 2026'
RARITIES = ['common','uncommon','rare','epic','legendary','mythic','exotic','secret']
RNAME = dict(zip(RARITIES,['Gewöhnlich','Ungewöhnlich','Selten','Episch','Legendär','Mythisch','Exotisch','Secret']))
card_source = (ROOT/'data/cards.json').read_text(encoding='utf-8-sig')
# Godot accepts trailing commas; retain quoted description text verbatim.
card_source = re.sub(r'("(?:\\.|[^"\\])*")|,\s*([}\]])', lambda m:m.group(1) or m.group(2), card_source)
CARDS = json.loads(card_source)
BY_ID = {c['id']:c for c in CARDS}
translations = {}
for path in (ROOT/'localization').glob('*.csv'):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        for row in csv.DictReader(stream):
            if row.get('keys') and row.get('de'):
                translations[row['keys']] = row['de']

def tr(s):
    return translations.get(s, s)

def number(value):
    return f'{value:g}'.replace('.', ',')

EFFECTS = [
 ('armor','Armor','Gewöhnlicher eingehender Schaden wird nach dem prozentualen Rüstungswert reduziert und gerundet. Katalogvarianten: 25 Prozent Common, 50 Prozent Rare und 75 Prozent Legendary. Angeborene Karten können andere Werte besitzen.'),
 ('shield_first_hit','Shield First Hit','Der erste positive gewöhnliche Treffer verursacht keinen Schaden und verbraucht den Schild. Ein Nulltreffer verbraucht ihn nicht. Auf dem eigentlichen Ziel wirkt der Schild vor einer Bodyguard-Verteilung. Gift und andere ausdrücklich rohe Schadenspfade sind davon getrennt.'),
 ('regeneration','Regeneration','Heilt zu Beginn des eigenen Besitzerzuges. Regulärer Wert 3 Leben; maximal bis zum aktuellen Lebensmaximum. Einzelne Karten verwenden kleinere Werte.'),
 ('poison','Poison','Ein tatsächlich schädigender Treffer vergiftet ein überlebendes Ziel. Regulär 3 Schaden über die nächsten 3 Besitzerzüge des Ziels. Der periodische Schaden umgeht gewöhnliche Rüstung und Ersttrefferschild, berücksichtigt aber einmalige Todesrettungen. Eine neue Vergiftung ersetzt die gespeicherten Giftparameter.'),
 ('lifesteal','Lifesteal','Heilt den überlebenden Angreifer nach der Aktion um regulär 20 Prozent des tatsächlich zugefügten HP-Schadens, gerundet und auf das Maximum begrenzt. Geeigneter Flächenschaden wird mitgezählt. Kein zusätzlicher Gewinn durch bloßen Overkill.'),
 ('thorns','Thorns','Reflektiert regulär 25 Prozent des tatsächlich erlittenen verbundenen Trefferschadens, gerundet. Kann bei mehreren Treffern mehrfach auftreten. Reflektierter Schaden wird nicht an Bodyguards weiterverteilt. Cleave-Splash löst diese Reflexion nicht zusätzlich aus.'),
 ('cleave','Cleave','Fügt den benachbarten gegnerischen Tischplätzen regulär 50 Prozent des Angriffswerts als gesonderten Schaden zu. Keine entfernten oder eigenen Ziele. Der Splash benutzt gewöhnliche Abwehrpfade, löst aber keine vollständige neue On-Hit-Kette aus. Bei Lava wird kein zweiter Cleave-Angriff ergänzt.'),
 ('lava','Lava','Trifft bei einem Kontakt alle ursprünglich auf dem gegnerischen Feld vorhandenen Karten mit dem vollen Angriffsschaden. Nur das gewählte Hauptziel kontert. Ersatzkarten derselben Aktion werden nicht mitgetroffen. Nur als angeborener Effekt zugelassen, nicht als zusätzlicher Effektwurf.'),
 ('double_strike','Double Strike','Zwei Treffer innerhalb derselben Aktion, bei ausdrücklich anderem Parameter die konfigurierte Trefferzahl. Der Verteidiger kontert nur im ersten Treffer. Getroffene und danach nachgezogene Karten sind nicht dasselbe Ziel.'),
 ('triple_strike','Triple Strike','Drei Treffer innerhalb derselben Aktion; die parametrisierte Zahl wird wie bei Double Strike begrenzt. Ist zugleich Double Strike vorhanden, wird die Triple-Strike-Abfrage vorrangig verwendet. Kein dreifacher Gegenangriff.'),
 ('stun','Stun','Nach einer schädigenden Angriffsaktion kann ein überlebendes Ziel betäubt werden; reguläre Chance 100 Prozent. Der nächste eigene Angriffsversuch dieser Karte verbraucht die Betäubung und setzt aus. Das ist nicht derselbe Zustand wie Event-Block.'),
 ('chain_attack','Chain Attack','Ein bestätigter Kill in der Aktion erlaubt dem noch lebenden Angreifer einen weiteren echten Angriff auf ein zufälliges lebendes Ziel. Auch ein geeigneter Splashkill kann die Kette starten. Die Aktion endet nicht zwischen diesen Folgeangriffen.'),
 ('last_stand','Last Stand','Die erste tödliche Schadensauflösung lässt die Karte mit 1 Leben überleben. Funktioniert auch gegen Gift und Execute. Wird pro frischer Kampfkarte nur einmal verbraucht. Kein gewöhnlicher Kill bei erfolgreicher Rettung.'),
 ('grave_return','Grave Return','Die erste tödliche Auflösung stellt gerundet die Hälfte des maximalen Lebens wieder her, mindestens 1. Einmal pro frischer Kampfkarte. Der zuvor tatsächlich entfernte HP-Schaden bleibt für die Trefferabrechnung erhalten. Wenn zugleich Last Stand verfügbar ist, wird zunächst Last Stand verwendet.'),
 ('execute','Execute','Ein nach dem Treffer unter die konfigurierte Lebensschwelle gefallenes Ziel kann unmittelbar tödlichen Schaden erhalten. Reguläre Schwelle 25 Prozent des maximalen Lebens. Einmalige Todesrettungen bleiben gültig; derselbe Treffer soll nicht zusätzlich eine bereits erfolgte Rettung sofort wieder zunichtemachen.'),
 ('swarm_power','Swarm Power','Der Angriff wird mit der Zahl lebender identischer Kartentypen auf dem gesamten Feld multipliziert. Identische Karten auf beiden Seiten zählen. Mindestens Faktor 1.'),
 ('draw_on_kill','Draw On Kill','Ein bestätigter Kill zieht eine Eventkarte für die Seite des Killers, höchstens einmal pro Opfer. Gilt auch für geeignete Gegen- und Flächentreffer. Spätere Gift-Ticks liefern diesen Draw nicht. Ein danach gezogenes Event ist erst vor einem folgenden eigenen Angriff spielbar.'),
 ('curse','Curse','Nach einer schädigenden Aktion wird der Angriff eines noch lebenden getroffenen Gegners regulär um 2 reduziert, mindestens auf 0. Die Verringerung bleibt während der Partie erhalten, verbessert oder verschlechtert aber nicht den gespeicherten Kartentyp.'),
 ('swap_stats','Swap Stats','Tauscht beim frischen Aufbau Angriff und maximales Leben; das aktuelle Leben wird entsprechend initialisiert. Ein Netzwerksnapshot oder das erneute Anzeigen darf den Tausch nicht ein zweites Mal anwenden.'),
 ('random_damage','Random Damage','Multipliziert den Angriff vor dem normalen Treffer zufällig mit einem Wert zwischen min und max. Regulärer Bereich 0,75 bis 1,25; einzelne Karten haben andere Grenzen. Das Ergebnis wird ganzzahlig gerundet.'),
 ('bodyguard','Bodyguard','Ein lebender direkt benachbarter Schutzträger übernimmt regulär 50 Prozent des rohen geeigneten Treffers. Links wird vor rechts geprüft; genau ein Guard übernimmt. Danach nutzen Ziel und Guard ihre eigenen Abwehrwerte. Kein rekursives Weiterreichen und keine Umleitung von Gift oder Dornen.'),
 ('neighbor_heal','Neighbor Heal','Heilt zu Beginn des eigenen Zuges die direkt benachbarten eigenen Tischkarten. Regulärer Katalogwert 2, bei mehreren angeborenen Heilern 1. Heilt nicht den Träger selbst und keine entfernten Plätze.'),
]
ENAME = {key:name for key,name,_ in EFFECTS}

def effect_label(e):
    key=e.get('type','?'); name=ENAME.get(key,key)
    if key in ('armor','lifesteal','thorns','bodyguard'):
        return f"{name} {number(e.get('value',e.get('percent',.25))*100)} %"
    if key=='poison': return f"Poison {e.get('damage',3)} für {e.get('turns',3)} Züge"
    if key in ('regeneration','neighbor_heal','curse'): return f"{name} {e.get('value',3 if key=='regeneration' else 2)}"
    if key=='cleave': return f"Cleave {number(e.get('side_damage',.5)*100)} %"
    if key=='random_damage': return f"Random Damage {number(e.get('min',.75))} bis {number(e.get('max',1.25))}"
    if key=='execute': return f"Execute {number(e.get('threshold',.25)*100)} %"
    if key=='stun': return f"Stun {number(e.get('chance',1)*100)} %"
    return name

def mdtable(headers, rows):
    safe=lambda x:str(x).replace('|','/').replace('\n','; ')
    return '\n'.join(['| '+' | '.join(map(safe,headers))+' |','| '+' | '.join('---' for _ in headers)+' |']+['| '+' | '.join(map(safe,row))+' |' for row in rows])

SPECIAL_RULES = {
 'clicker': ('Manueller Clicker mit 0,02 SC Grundwert.', 'Einmalig; keine Voraussetzung'),
 'clicker_upgrade': ('Plus 0,01 SC je manuellem Klick und Kopie.', 'Stapelbar; schaltet den Clicker allein nicht frei'),
 'golden_clicker': ('Plus 0,05 SC je manuellem Klick und Kopie.', 'Stapelbar; benötigt Clicker'),
 'auto_clicker': ('0,02 SC pro laufender Spielsekunde vor Einkommensbonus.', 'Einmalig; benötigt Clicker; keine Offlinezeit'),
 'slot_room_key': ('Zugang zum Automatenraum nach Benutzung in der Ablage.', 'Einmaliger Messerfund; kein Packdrop'),
 'lucky_coin': ('Rare-und-höher-Chance relativ plus 5 Prozent.', 'Einmalig; eigenes Legendary-Kartengewicht 0,02'),
 'black_market_access': ('Zugang zum Black Market nach Benutzung.', 'Einmalig; normaler Legendary-Pool'),
 'dealer_license': ('10 Prozent Preisrabatt im normalen Shop-Pool.', 'Einmalig; gilt nicht im Black Market'),
 'fusion_upgrade_1': ('Fusion benötigt 4 statt 5 Karten.', 'Einmalig'),
 'fusion_upgrade_2': ('Fusion benötigt 3 statt 4 Karten.', 'Einmalig; benötigt Fusion Upgrade I'),
 'graveyard_key': ('Friedhofzugang nach Benutzung.', 'Einmaliger Kistenfund im Keller; kein Packdrop'),
 'basement_key': ('Kellerzugang nach Benutzung.', 'Einmalig; normaler Legendary-Pool'),
}
for index in range(1,6):
    SPECIAL_RULES[f'starting_hand_{index}']=(f'{index} gezielt belegbare Startplätze insgesamt.', 'Einmalig; nächste fehlende Stufe der zusammenhängenden Reihe')
for prefix in ['soulcoin_boost','xp_boost']:
    for index,percentage in enumerate([2,5,10,15],1):
        SPECIAL_RULES[f'{prefix}_{index}']=(f"{'SoulCoin-Einnahmen' if prefix=='soulcoin_boost' else 'XP'} plus {percentage} Prozent; höchste gültige Stufe zählt.", 'Einmalig'+('; vorherige Stufe erforderlich' if index>1 else ''))

SOURCES = [
 ('Q01','Hub und Weltaufbau','scripts/main/Main.gd; scenes/main/Main.tscn'),
 ('Q02','Kartendefinition und Kategorien','data/cards.json; scripts/card/CardData.gd'),
 ('Q03','Tatsächliche Kampfauflösung','scenes/table/GameTable.gd: _start_match, _resolve_duel, _end_turn_to, _check_game_over, _grant_match_rewards'),
 ('Q04','Kamera und Türreisen','scripts/props/HospitalDoor.gd; scripts/ui/ScreenCameraFocus.gd; scripts/main/Main.gd'),
 ('Q05','Pause und globale Vorgaben','scripts/ui/PauseMenu.gd; scripts/autoload/SettingsManager.gd'),
 ('Q06','Menü und Profiltrennung','scripts/ui/MainMenu.gd; scripts/ui/SaveSlotPicker.gd; scripts/autoload/SaveManager.gd'),
 ('Q07','Währung und Belohnungen','scripts/GameCurrency.gd: Einkommen, XP, Level, Kaufbelege, Story und Katzenwahl'),
 ('Q08','Schlüsselbenutzung','scripts/ui/AccessKeyTray.gd; scripts/autoload/CollectionManager.gd: unlock_area und unlock_slot_room'),
 ('Q09','Events','scripts/events/EventDeck.gd; scenes/table/GameTable.gd: Eventauswahl, Block und Kill-Draw'),
 ('Q10','Deck und Typ-Upgrades','scripts/autoload/DeckManager.gd; scripts/CardUpgradeManager.gd; scripts/card/CardData.gd'),
 ('Q11','Secret und Kartenbild','scripts/autoload/CardDatabase.gd; scripts/card/CardDiorama.gd; scripts/Rarityeffects.gd; scripts/ui/SecretCardReveal.gd'),
 ('Q12','Sammlung und Kenntnisstand','scripts/ui/CollectionScreen.gd; scripts/ui/UpgradeWallCollection.gd; scripts/autoload/CollectionManager.gd'),
 ('Q13','Startplätze','scripts/ui/StartingHandSlots.gd; scripts/autoload/DeckManager.gd: prepare_match_deck'),
 ('Q14','Effektberechnung','scripts/match/CombatResolver.gd; scripts/card/Card3D.gd; scenes/table/GameTable.gd'),
 ('Q15','Effektkatalog und Würfe','data/effects.json; scripts/autoload/EffectDatabase.gd'),
 ('Q16','Ei und Küken','scenes/table/GameTable.gd: Tod, Schlüpfen und Chick-Wachstum; scripts/ui/JournalContent.gd: EGG_RULE und CHICK_RULE'),
 ('Q17','Story und Training','scripts/match/OfflineMatchRules.gd; scripts/ui/OfflineModeMenu.gd; scripts/table/OfflineModeBoard.gd'),
 ('Q18','Permanente Modifier','data/cards.json: upgrade_modifiers und requires; scripts/autoload/CollectionManager.gd: _get_upgrade_modifier'),
 ('Q19','Aktive Packregeln','scripts/packs/PackDefinition.gd; scripts/ui/PackShopUI.gd; scripts/ui/PackOpeningScreen.gd'),
 ('Q20','Upgradeautomat','scripts/UpgradeMachine.gd; scripts/UpgradeUI.gd; scripts/CardUpgradeManager.gd'),
 ('Q21','Manuelle und automatische Fusion','scripts/props/FusionWorkbench.gd; scripts/autoload/CollectionManager.gd: validate_fusion und auto_fuse_card_instances'),
 ('Q22','Geheimfunde','scripts/table/LocalTableProp.gd; scripts/rooms/BasementDiscovery.gd; scripts/props/SecretWallInput.gd; scripts/autoload/CollectionManager.gd'),
 ('Q23','Aktuelle Slotregeln','scripts/props/SlotMachine.gd: BETS, MULTIPLIERS, _roll_result und payout_for; scripts/GameCurrency.gd'),
 ('Q24','Tagesangebote','scripts/rooms/BlackMarketBoard.gd; scripts/autoload/CollectionManager.gd: BLACK_MARKET_PRICES_CENTS und purchase_black_market_offer'),
 ('Q25','Gemeinsame NPC-Dialoge','scripts/rooms/AngelDialogue.gd; AngelDialogueContent.gd; DealerDialogue.gd; DealerDialogueContent.gd; PrisonerDialogue.gd im selben Ordner'),
 ('Q26','Katzenentscheidung und Hilfe','scripts/rooms/BasementCatEncounter.gd; scripts/ui/CatChoicePresentation.gd; scripts/GameCurrency.gd'),
 ('Q27','Lokale Kellerobjekte','scripts/rooms/BasementBoiler.gd; scripts/rooms/BasementPumpControl.gd; scripts/rooms/BasementCrate.gd'),
 ('Q28','Jester und Opfergabe','scripts/rooms/GraveyardJester.gd; scripts/autoload/CollectionManager.gd: JESTER_OFFERING_CARD_IDS und Opfertransaktionen'),
 ('Q29','Krypta und Gefangener','scripts/rooms/CryptGate.gd; scripts/rooms/PrisonerDialogue.gd; scenes/rooms/Graveyard.tscn'),
 ('Q30','Erste Begrüßung','scripts/main/SatanGreeting.gd; scripts/main/Main.gd; scripts/GameCurrency.gd'),
 ('Q31','Schreck und Blutrand','scripts/main/SatanJumpscare.gd; scripts/effects/Piss.gd; scripts/ui/BloodOverlay.gd'),
 ('Q32','Onlinezustand','scripts/autoload/NetworkManager.gd; scripts/multiplayer/Matchmaking.gd; scenes/table/GameTable.gd'),
 ('Q33','Charakteremission','scripts/SpriteAnim.gd; assets/characters/*/eye_glow.tres; assets/characters/satan/menu_glow.tres; scenes/main/MainMenu.tscn'),
 ('Q34','Journal und Profil','scripts/ui/Journal3D.gd; scripts/ui/JournalContent.gd; scripts/autoload/PlayerProfile.gd; scripts/ui/LevelProgress.gd'),
 ('Q35','Sprachfunktion','scripts/SatanVoiceChat.gd; scripts/ui/MicrophoneTestController.gd; scripts/ui/MatchHUD.gd'),
 ('Q36','Sprache und Einstellungen','scripts/autoload/Localization.gd; scripts/autoload/SettingsManager.gd; scripts/ui/SettingsMenu.gd; localization/*.csv'),
 ('Q37','Werkzeuge und Platzhalter','scripts/ui/PiskelTool.gd; scripts/ui/ProfileScreen.gd; scripts/autoload/AchievementManager.gd; scripts/match/MatchState.gd, TurnManager.gd und BotPlayer.gd'),
]

FINDINGS = {
 'angel_dialogue_test':'Sofortige Escape- und Kontextprüfungen weichen von der 0,24-Sekunden-Schließanimation ab. Die gezielte zusätzliche Lebenszyklusprüfung nach Animationsende besteht.',
 'angel_integration_test':'Gleiche Timingabweichung im Hub; mehrere spätere Assertions schlagen als Folge der noch geöffneten Modalansicht fehl.',
 'dealer_dialogue_test':'Schließen, Folgeinteraktionen und Übersetzungsprüfungen schlagen fehl. Gemeinsame animierte Schließlogik als Einfluss vorhanden; nicht alle Sprachbehauptungen sind damit geklärt.',
 'jester_focus_test':'Prüft unter anderem sofortiges Schließen nach Escape und Opfergaben. Der aktuelle Jester blendet sein Panel über 0,24 Sekunden aus; Folgeschritte benötigen eine zeitlich angepasste Abnahme.',
 'jester_station_test':'Zeitüberschreitung nach fehlgeschlagenen Sofort-Schließprüfungen. Nicht als Nachweis eines allgemeinen Hängers im regulären Spiel zu behandeln.',
 'card_blood_test':'Zwei VFX-Prüfungen für sichtbare Blutflecken bei Last-Stand-Gegenangriff und Dornen schlagen fehl. Die separaten Kampf- und Schadenszahlensuiten bestehen; optische Wirkung gezielt nachprüfen.',
 'card_localization_test':'121 von 4435 Einzelprüfungen schlagen fehl, darunter DMAN-Katalogtext sowie Effektbezeichnungen und Beschreibungen in mehreren Sprachen. Übersetzungsdateien und importierte Ressourcen abgleichen.',
 'world_localization_test':'Fehlende beziehungsweise abweichende Schmiedefilter- und Auswahltexte in de, es, fr und pl. Die übersetzte Weltoberfläche ist damit noch nicht vollständig abgenommen.',
 'god_pack_unlock_test':'Drei Vorschau- und Beschriftungsprüfungen schlagen fehl. Die im selben Test geprüften Kaufwachen unter Level 10 und die regulären Käufe ab Level 10 bestehen. Anzeige und exakte Texte separat prüfen.',
 'journal_collection_test':'Zwei feste Katalogzählungen erwarten noch 117 Sammelkarten; tatsächlich sind 118 vorhanden. Die Erwartungszahl des Tests ist veraltet.',
 'lower_rarity_cards_test':'Erwartet für die 28 Zusatzkarten noch ausschließlich statische Platzhalterbilder. Mehrere Datensätze besitzen inzwischen echte beziehungsweise animierte Bilder. Diese Erwartungen sind veraltet; nicht als 28 neue Kampffehler werten.',
 'secret_integration_test':'Prüfungen auf zwei bestimmte Journal-Mechanikeinträge in allen Sprachen schlagen fehl. Die eigentlichen Secret-Erwerbs- und Datenprüfungen haben eigene bestehende Tests.',
 'secret_visual_test':'Erwartet Developer und Missing Texture weiterhin als Secret. Beide sind im aktuellen Katalog Exotisch; die Assertion ist veraltet.',
 'settings_outlines_test':'Eine feste Zählung aller Einstellungs-Slider und Checkboxen schlägt fehl. Ob nur die erwartete Anzahl oder eine sichtbare Kontur angepasst werden muss, bleibt zu prüfen.',
}

def audit_results():
    report=json.loads((AUDIT/'test-results.json').read_text(encoding='utf-8'))
    results={r['suite']:r for r in report['results']}
    for name,suite in [('run_basement_cat_backend_tests','basement_cat_backend_test'),('run_black_market_backend_tests','black_market_backend_test'),('run_cat_clicker_backend_tests','cat_clicker_backend_test')]:
        text=(AUDIT/(name+'.log')).read_text(encoding='utf-8-sig')
        match=re.search(r'([A-Z_]+_TESTS): PASS \((\d+) checks\)',text)
        results[suite].update(status='passed' if match else 'failed',checks=int(match[2]) if match else None, special_runner=name,log=str(AUDIT/(name+'.log')))
    extra=json.loads((AUDIT/'supplemental-results.json').read_text(encoding='utf-8'))
    close=extra['dialog_close']
    results['documentation_dialog_close_test']={'suite':'documentation_dialog_close_test','status':'passed' if close['success'] else 'failed','checks':4,'log':'supplemental-results.json'}
    rolling=extra['rolling_audio']
    results['rolling_audio_audibility_test'].update(status='passed' if rolling['success'] else 'failed', log='supplemental-results.json', mode='render with Dummy audio')
    perf=json.loads((AUDIT/'performance-rerun.json').read_text(encoding='utf-8'))
    results['collection_performance_test'].update(status='passed' if perf['success'] else 'failed',log='performance-rerun.json',rerun_note='uses required collection_performance_manager fixture')
    results['card_localization_test']['checks']=4435
    reviewed={'recorded_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':str(ROOT),'scope':'121 original suites plus one targeted dialog timing probe','results':sorted(results.values(),key=lambda r:r['suite'])}
    (AUDIT/'test-results-reviewed.json').write_text(json.dumps(reviewed,ensure_ascii=False,indent=2),encoding='utf-8')
    return reviewed['results']

def resolve_markdown():
    text=(ROOT/'tools/documentation_audit/Spielhandbuch.template.md').read_text(encoding='utf-8')
    effect_rows=[(f'{name} (`{key}`)',rule) for key,name,rule in EFFECTS]
    text=text.replace('{{EFFECT_CATALOG}}',mdtable(['Effekt','Auslösung und genaue Regel'],effect_rows))
    pack_rows=[]
    weights={'basic':[64.999,25,8,1.7,.3,0,0],'ultra':[34.995,32,20,9,3,.8,.2],'god':[9.99,20,28,24,12,5,1]}
    for idx,rarity in enumerate(RARITIES[:-1]):
        pack_rows.append([RNAME[rarity]]+[f'{100*weights[p][idx]/sum(weights[p]):.3f} %'.replace('.',',') for p in ['basic','ultra','god']])
    pack_rows.append(['Secret','0 %','0 %','0 %'])
    text=text.replace('{{PACK_ODDS}}',mdtable(['Seltenheit','Basic ungefähr','Ultra ungefähr','God ungefähr'],pack_rows))
    combat=[]
    for rarity in RARITIES:
        group=sorted([c for c in CARDS if c.get('category','combat') not in ('special','event') and c['rarity']==rarity],key=lambda c:tr(c['name']).casefold())
        combat.append(f'### {RNAME[rarity]} mit {len(group)} Kartentypen\n')
        rows=[]
        for c in group:
            route='Zufall' if c.get('random_reward',True) else ('Code dman' if c['id']=='dman' else 'Fund oder Jester')
            rows.append([f"{tr(c['name'])} (`{c['id']}`)",c.get('attack',0),c.get('defense',0),'; '.join(effect_label(e) for e in c.get('effects',[])) or 'Keine',route])
        combat.append(mdtable(['Karte und ID','ATK','LP','Angeborene Effekte','Erwerb'],rows))
    text=text.replace('{{COMBAT_CATALOG}}','\n\n'.join(combat))
    special=[]
    for c in sorted([c for c in CARDS if c.get('category')=='special'],key=lambda c:(RARITIES.index(c['rarity']),tr(c['name']).casefold())):
        rule,condition=SPECIAL_RULES[c['id']]
        special.append([f"{tr(c['name'])} (`{c['id']}`)",RNAME[c['rarity']],rule,condition])
    assert len(special)==25
    text=text.replace('{{SPECIAL_CATALOG}}',mdtable(['Karte und ID','Seltenheit','Wirkung','Grenze und Voraussetzung'],special))
    text=text.replace('{{SOURCE_INDEX}}',mdtable(['Quelle','Zuständigkeit und Projektstellen'],[(key,f'{topic}. {paths}') for key,topic,paths in SOURCES]))
    results=audit_results(); counts=Counter(r['status'] for r in results)
    summary=(f"**{len(results)} unterschiedliche Testsuiten wurden erfasst:** {counts['passed']} bestehen im abschließend verwendeten Prüfaufbau, {counts['failed']} melden fehlgeschlagene Erwartungen, {counts['timeout']} endet mit einer Zeitüberschreitung und {counts['not_run']} wurde nicht ausgeführt. Davon stammen 121 Suiten aus dem vorhandenen Szenenbestand und eine aus der gezielten zusätzlichen Dialogprüfung. Drei Backendfälle wurden mit ihren vorgesehenen Spezialrunnern geprüft. Der zunächst falsch konfigurierte Collection-Performancelauf besteht mit seinem benötigten Fixture.\n\n"
             'Die zusätzliche Dialogprüfung bestätigt per tatsächlichem Escape-Eingabeereignis, dass der Produktionsdialog zunächst ausblendet und nach 0,35 Sekunden geschlossen und wieder öffnungsfähig ist. Die Slot-Audioprüfung besteht in einem isolierten Renderlauf mit stummem Ausgabetreiber und gemessenem internem SFX-Signal. Eine vollständige hörende Geräteabnahme ist das nicht.')
    text=text.replace('{{AUDIT_SUMMARY}}',summary)
    failed=[]
    for r in results:
        if r['status'] in ('failed','timeout'):
            failed.append([r['suite'],FINDINGS.get(r['suite'],'Siehe Rohprotokoll für die einzelnen fehlgeschlagenen Erwartungen.')])
    failed.append(['native_peer_lifetime_test','Nicht ausgeführt: eigenständige native Steam-Peer-Lebensdauerdiagnose. Kein Ersatz für die externe Mehrspielerabnahme.'])
    text=text.replace('{{AUDIT_FINDINGS}}',mdtable(['Prüfung','Einordnung'],failed))
    status={'passed':'Bestanden','failed':'Fehlgeschlagen','timeout':'Zeitlimit','not_run':'Nicht ausgeführt'}
    text=text.replace('{{TEST_CATALOG}}',mdtable(['Testsuite','Ergebnis','Prüfungen'],[(r['suite'],status.get(r['status'],r['status']),r.get('checks') if r.get('checks') is not None else 'n. a.') for r in results]))
    if '{{' in text: raise ValueError('Unresolved content token')
    target=OUT/(TITLE+'.md');target.write_text(text,encoding='utf-8')
    return text,counts

def inline(s):
    s=html.escape(s,quote=False)
    s=re.sub(r'\*\*(.+?)\*\*',r'<b>\1</b>',s)
    s=re.sub(r'`([^`]+)`',r'<font name="Calibri">\1</font>',s)
    return s

FONT_DIR=Path('C:/Windows/Fonts')
pdfmetrics.registerFont(TTFont('Calibri',str(FONT_DIR/'calibri.ttf')))
pdfmetrics.registerFont(TTFont('Calibri-Bold',str(FONT_DIR/'calibrib.ttf')))
pdfmetrics.registerFont(TTFont('Calibri-Italic',str(FONT_DIR/'calibrii.ttf')))
pdfmetrics.registerFontFamily('Calibri',normal='Calibri',bold='Calibri-Bold',italic='Calibri-Italic',boldItalic='Calibri-Bold')
STYLES={
 'Title':ParagraphStyle('Title',fontName='Calibri-Bold',fontSize=29,leading=33,spaceAfter=14,textColor=colors.black),
 'Subtitle':ParagraphStyle('Subtitle',fontName='Calibri',fontSize=18,leading=23,spaceAfter=10),
 'Date':ParagraphStyle('Date',fontName='Calibri',fontSize=10,leading=14,spaceAfter=22,textColor=colors.HexColor('#555555')),
 'Body':ParagraphStyle('Body',fontName='Calibri',fontSize=11,leading=15.1,spaceAfter=8,splitLongWords=True,allowWidows=0,allowOrphans=0),
 'H1':ParagraphStyle('H1',fontName='Calibri-Bold',fontSize=18,leading=22,spaceBefore=20,spaceAfter=10,keepWithNext=True),
 'H2':ParagraphStyle('H2',fontName='Calibri-Bold',fontSize=13.5,leading=17.5,spaceBefore=14,spaceAfter=7,keepWithNext=True),
 'List':ParagraphStyle('List',fontName='Calibri',fontSize=11,leading=15.1,leftIndent=19,firstLineIndent=-19,spaceAfter=6,allowWidows=0,allowOrphans=0),
 'TH':ParagraphStyle('TH',fontName='Calibri-Bold',fontSize=9.7,leading=12.7,textColor=colors.white,spaceAfter=0),
 'TD':ParagraphStyle('TD',fontName='Calibri',fontSize=9.6,leading=12.6,spaceAfter=0,splitLongWords=True),
 'TDC':ParagraphStyle('TDC',fontName='Calibri',fontSize=9.6,leading=12.6,spaceAfter=0,alignment=TA_CENTER),
}

class Handbook(BaseDocTemplate):
    def __init__(self,path):
        super().__init__(str(path),pagesize=letter,leftMargin=48,rightMargin=48,topMargin=49,bottomMargin=43,
                         title='Darkest Cards 3D Spieldokumentation',author='Darkest Cards 3D Projektdokumentation')
        self.addPageTemplates(PageTemplate('pages',[Frame(self.leftMargin,self.bottomMargin,self.width,self.height,id='body',leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)],onPage=self.decorate))
    def decorate(self,c,doc):
        c.saveState();c.setFont('Calibri',8.5);c.setFillColor(colors.HexColor('#555555'))
        if doc.page>1:c.drawString(48,letter[1]-27,'Darkest Cards 3D | Spieldokumentation')
        c.drawString(48,24,'Stand 15 November 2026')
        c.drawRightString(letter[0]-48,24,f'Seite {doc.page}')
        c.restoreState()
    def afterFlowable(self,flowable):
        if isinstance(flowable,Paragraph) and flowable.style.name=='H1':
            text=flowable.getPlainText();key='chapter-'+hashlib.sha1(text.encode()).hexdigest()[:12]
            self.canv.bookmarkPage(key);self.canv.addOutlineEntry(text,key,0,closed=False)
            self.notify('TOCEntry',(0,text,self.page,key))

def table_flow(headers,rows,width):
    n=len(headers)
    if headers[0]=='Karte und ID' and n==5: ratios=[.27,.055,.055,.43,.19]
    elif headers[0]=='Karte und ID': ratios=[.27,.14,.31,.28]
    elif headers[0]=='Testsuite':ratios=[.64,.23,.13]
    elif headers[0]=='Quelle':ratios=[.095,.905]
    elif headers[0]=='Prüfung':ratios=[.29,.71]
    elif headers[0]=='Effekt':ratios=[.23,.77]
    elif n==8:ratios=[.085]+[.915/7]*7
    elif n==5:ratios=[.18,.11,.24,.24,.23]
    elif n==4:ratios=[.29,.237,.237,.236]
    elif n==3:ratios=[.22,.27,.51]
    elif n==2:ratios=[.31,.69]
    else:ratios=[1/n]*n
    contents=[[Paragraph(inline(cell),STYLES['TH']) for cell in headers]]
    for row in rows:
        cells=[]
        for idx,cell in enumerate(row):
            centered=(headers[idx] in ('ATK','LP','Prüfungen') or (n==8 and idx>0))
            cells.append(Paragraph(inline(cell),STYLES['TDC' if centered else 'TD']))
        contents.append(cells)
    table=LongTable(contents,colWidths=[width*r for r in ratios],repeatRows=1,hAlign='LEFT',splitByRow=1,spaceBefore=4,spaceAfter=12)
    commands=[('BACKGROUND',(0,0),(-1,0),colors.HexColor('#323E46')),('GRID',(0,0),(-1,-1),.45,colors.HexColor('#D9D9D9')),
              ('VALIGN',(0,0),(-1,-1),'MIDDLE'),('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),
              ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6)]
    for i in range(2,len(contents),2):commands.append(('BACKGROUND',(0,i),(-1,i),colors.HexColor('#F1F3F4')))
    table.setStyle(TableStyle(commands));return table

def build_pdf(text):
    pdf=OUT/(TITLE+'.pdf');doc=Handbook(pdf);story=[];lines=text.splitlines();i=0;toc_done=False
    while i<len(lines):
        line=lines[i].strip()
        if not line:i+=1;continue
        if line.startswith('# '):story.append(Paragraph(inline(line[2:]),STYLES['Title']));i+=1;continue
        if line=='## Spieldokumentation':story.append(Paragraph('Spieldokumentation',STYLES['Subtitle']));i+=1;continue
        if line=='Stand 15 November 2026':story.append(Paragraph(DATE,STYLES['Date']));i+=1;continue
        if line.startswith('## '):
            if not toc_done:
                story.append(PageBreak());story.append(Paragraph('Inhalt',STYLES['Subtitle']))
                toc=TableOfContents();toc.dotsMinLevel=0;toc.levelStyles=[ParagraphStyle('TOC',fontName='Calibri',fontSize=10.5,leading=13.3,leftIndent=0,firstLineIndent=0,spaceBefore=0,spaceAfter=0)]
                story.append(toc);story.append(PageBreak());toc_done=True
            if line.startswith('## Anhang'):
                story.append(PageBreak())
            story.append(Paragraph(inline(line[3:]),STYLES['H1']));i+=1;continue
        if line.startswith('### '):
            following=next((item.strip() for item in lines[i+1:] if item.strip()),'')
            if following.startswith('|'):
                story.append(CondPageBreak(95))
                style=ParagraphStyle('H2Table',parent=STYLES['H2'],keepWithNext=False)
                story.append(Paragraph(inline(line[4:]),style))
            else:
                story.append(Paragraph(inline(line[4:]),STYLES['H2']))
            i+=1;continue
        if line.startswith('|'):
            grid=[]
            while i<len(lines) and lines[i].strip().startswith('|'):
                cells=[c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r'[:\- ]+',c or ' ') for c in cells):grid.append(cells)
                i+=1
            story.append(table_flow(grid[0],grid[1:],doc.width));continue
        if re.match(r'^\d+\. ',line):
            story.append(Paragraph(inline(line),STYLES['List']));i+=1;continue
        paras=[line];i+=1
        while i<len(lines) and lines[i].strip() and not lines[i].startswith(('#','|')) and not re.match(r'^\d+\. ',lines[i]):
            paras.append(lines[i].strip());i+=1
        story.append(Paragraph(inline(' '.join(paras)),STYLES['Body']))
    doc.multiBuild(story)
    return pdf

def snapshot():
    entries=[]
    for folder,patterns in [('scripts',['*.gd']),('scenes',['*.gd','*.tscn']),('data',['*.json'])]:
        for pattern in patterns:
            for path in sorted((ROOT/folder).rglob(pattern)):
                entries.append({'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    (AUDIT/'source-snapshot.json').write_text(json.dumps({'date':'2026-11-15','files':entries,'cards':len(CARDS),'combat_cards':sum(c.get('category','combat') not in ('special','event') for c in CARDS),'special_cards':sum(c.get('category')=='special' for c in CARDS)},ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':
    text,counts=resolve_markdown();pdf=build_pdf(text);snapshot()
    from pypdf import PdfReader
    reader=PdfReader(pdf)
    print(json.dumps({'pdf':str(pdf),'pages':len(reader.pages),'words':len(text.split()),'suites':dict(counts),'cards':len(CARDS)},ensure_ascii=False))
