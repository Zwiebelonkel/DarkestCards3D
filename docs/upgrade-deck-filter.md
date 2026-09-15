# Upgrade machine deck filter

Click the **YOUR CARDS** heading on the upgrade machine to show only owned combat card types in the current deck. Click it again to restore the full owned combat-card list. The active heading is highlighted and keeps its position in the machine's touch screen.

Duplicate deck copies share one entry because upgrades apply to a card type. An empty deck shows an empty list. The visible count, ownership amounts and selection update as cards are acquired or the deck is edited. If a selected card leaves the filtered list, its preview and upgrade target are cleared.

`tests/upgrade_deck_filter_test.tscn` exercises the actual 3D screen input forwarding, both toggle directions, duplicates, empty decks, live collection/deck changes, and safe selection handling. Run through the isolated test runner to avoid modifying player saves.
