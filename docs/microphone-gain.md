# Microphone gain

Settings → Microphone gain controls how loudly the other player hears your
voice, from 0% (silent) to 2000%, with 100% as the default. The value is saved
and also applies to the local microphone test. Received voice volume remains
a separate local control, also adjustable from 0% to 2000%. It boosts received
voice without changing the other player's microphone setting. Its default stays
at 30%, and the chosen volume is saved. High gain can clip loud input at the valid sample limits.

The outgoing voice envelope uses a two-byte percentage for gains above 200%.
The receiver still accepts the original one-byte envelope and raw Steam audio.
Both players need the updated game to use the full range through 2000%.

Run `tests/microphone_gain_test.tscn` through the isolated match-feature runner.
It checks settings persistence and UI changes, packet round trips through
2000%, malformed packets, legacy input and matching local/remote amplification.
Real microphone capture and a live Steam match need a separate manual check.
