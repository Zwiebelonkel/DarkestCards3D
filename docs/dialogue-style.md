# NPC dialogue colors

`scripts/ui/DialogueStyle.gd` owns the shared speaker-name palette:

| Speaker | Color |
| --- | --- |
| Satan | Red (`#ff4545`) |
| Jester | Green (`#65df70`) |
| Dealer | Violet (`#bc7aff`) |
| Prisoner | Yellow (`#ffe066`) |
| Angel | Blue (`#68b5ff`) |

The regular station dialogs, rescued NPC introductions, Satan's first greeting,
Holy Water return and playtime encounter all use this palette. Speaker colors
are keyed by the character identity, independently of the translated name.

The Holy Water return's fourth sentence and the playtime encounter's full line
also use red body text and `SatanLaughTextEffect.gd`. Each letter has its own
smooth horizontal/vertical motion (up to 1.8/2.6 pixels), speed and phase. The
effect persists after the typewriter finishes. It runs during the encounter's
global pause through the dialog's existing always-processing mode.

The effect is pushed onto the display stack without enabling BBCode parsing.
Steam names and translated text remain literal, with unchanged character counts.
