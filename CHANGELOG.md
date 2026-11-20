# Changelog

## 1.0.1 (Nov 20, 2026)

- Layout fixes (FrostSuite-1.0 r4, shared by the suite): a status too long to sit beside the title moves to its own line instead of running into it, and box heights fit their text.
- Box is 78 px in combat, so the `REFRESH` line sits inside it.

## 1.0.0 (Nov 20, 2026)

First release, part of the Frost Suite.

- Shows Ice Barrier's damage window: `REEF +20%`, `BUFF +15%` with `REFRESH`, or `SHIELD DOWN` in combat when it's off cooldown.
- The +15% minute comes from the Frigid Power buff when the game lets addons read it, otherwise from your cast plus 60 seconds.
- The shield is read from the Ice Barrier buff only when the game allows it. Otherwise the box says `shield state unknown`
  and never shows +20%.
- 30-second cooldown from your cast; Cold Snap clears it. One pulse and the game's Frost Armor sound when the shield goes down.
- `/frost reef test | sound on|off | debug`. Docks with the other Frost Suite boxes.
