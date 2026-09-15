# Collection angel dialogue

The existing angel in the physical collection offers short, hopeful conversations.
`scripts/rooms/AngelDialogueContent.gd` contains 20 original German sentence keys
in `AngelDialogueContent.SENTENCES`. Each conversation uses one sentence.
The tone offers encouragement and small moments of rest within the dark setting;
the lines do not promise victories, rewards or changes to gameplay.

The title `Der Engel` and every sentence are translated into German, English,
Spanish, French and Polish in `localization/journal.csv`, alongside the existing
Jester dialogue keys. Each localized line contains exactly one sentence with one
closing period and no rich-text markup. The controller keeps the selected source
key so a language change updates the same sentence instead of choosing another.

Clicking the existing angel opens one randomly selected sentence. The controller
uses its own random generator and excludes the immediately previous sentence,
preserving gameplay randomness. The content resource contains no collection,
currency, deck or save access.

Text appears with a typewriter effect while Satan's existing laugh plays on the
SFX bus with its normal pitch variation. Finishing or skipping the sentence stops
the typing voice without a sentence-end sound. The dialog has no buttons. A left click anywhere,
inside or outside the text panel, reveals unfinished text; once the sentence is
fully visible, a left click closes it. Escape dismisses the conversation at any
time. Closing stops the voice and consumes that click before collection or
navigation controls use it.

The modal blocks collection interactions while open and closes when the scene
pauses, the collection becomes unavailable or the application loses focus.
The existing angel sprite and its animation remain in place.
Neither hovering nor opening the conversation changes the angel's scale or
zooms the camera. In the hub, conversation is available on the Collection side;
turning, room travel, the journal, and progression controls wait until it closes.
The standalone Collection screen supports the same conversation. Foreground
cards and buttons retain their clicks instead of opening the angel behind them.

Import the CSV through Godot when changing the text and include the regenerated
`localization/journal.*.translation` resources. Dialogue tests check all 20 keys
in all five languages, text fit, stable selection during language changes and
unchanged game state.
