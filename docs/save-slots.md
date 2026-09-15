# Drei Spielstände

Im Hauptmenü wird einer von drei Spielständen ausgewählt. Die Auswahl zeigt
zunächst nur eine Vorschau; „Spielen“ lädt Sammlung, Karteninstanzen, Deck,
Starthand, Upgrades, Münzen, Level und dauerhafte Freischaltungen gemeinsam.
Der zuletzt gestartete Spielstand wird beim nächsten Programmstart geladen.

`SaveSlots` wird vor den Fortschritts-Autoloads initialisiert und verwaltet
`user://saves/slot_1/` bis `slot_3/`. Die vier bisherigen Fortschrittsdateien
werden einmalig nach Slot 1 kopiert; die Originale bleiben erhalten. Der globale
Migrationsmarker verhindert, dass zurückgesetzter Fortschritt erneut importiert wird.

„Spielstand zurücksetzen“ löscht ausschließlich den im Dialog genannten Slot.
Einstellungen, Sprache, Diagnoseprotokolle und Piskel-Exporte bleiben global.
Ein Wechsel ist nur im Hauptmenü außerhalb einer Online-Sitzung möglich.
Bereits gebuchte Slot-Gewinne und ausstehende Pack-Erstattungen bleiben dem
jeweiligen Spielstand zugeordnet und werden beim Laden genau einmal abgewickelt.

Die Manager behalten ihre bisherigen Lade-/Speicher-APIs; Pfade werden über
`SaveSlots.get_save_path()` aufgelöst. Ein expliziter `GameCurrency.save_path`
bleibt für isolierte Wallet-Tests möglich. `clear_profile_state()` verwirft
flüchtigen Zustand ohne zu speichern oder Signale zu senden. Der Slotcontroller
benachrichtigt Beobachter erst nach dem vollständigen Wechsel.

Regression: `tests/save_slots_test.tscn` über den isolierten Match-Feature-Runner
mit Erfolgsmeldung `SAVE_SLOTS_TESTS: PASS`. Die Suite prüft unter anderem
Profiltrennung, exakte Kartenidentitäten, Transaktionswiederherstellung,
Einladungs- und Wiederholungssperren, beschädigte Ziele und getrennten Reset.
