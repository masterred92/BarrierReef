# Barrier Reef

A tiny Frost Mage box for **WoW: Forever** (Interface 16001). Version 1.0.1. Part of Kenny's Frost Suite, and it works alone.

Official Nov 2, 2026 notes made Ice Barrier a damage cooldown. Casting it gives **+15% Frost damage for 1 minute**, plus
**another 5% while the shield holds**. Barrier Reef shows which of those is up, in one of three states:

| State | Means |
| --- | --- |
| `REEF +20%` | the minute is running and the shield still holds |
| `BUFF +15%` + `REFRESH` | the minute is running but the shield is gone; recasting restarts the minute and puts the 5% back |
| `SHIELD DOWN` | in combat, neither is up and Ice Barrier is off cooldown |

It doesn't draw an absorb bar (Dyre's Shields Up already does that). It never casts anything.

## What the game lets it see

| Thing | How it's read | When the game hides it |
| --- | --- | --- |
| The +15% minute | the Frigid Power buff, if the game lets addons read it right now | your own Ice Barrier cast plus 60 seconds (the buff is a fixed minute, from the game's data) |
| The shield (+5%) | the Ice Barrier buff, if the game lets addons read it right now | the box says `shield state unknown` and shows `BUFF +15%` only, never a guessed +20% |
| Cooldown | 30 seconds from your cast (game data); Cold Snap clears it | - |
| Your casts | your own cast events | the box says `can't see your casts here`; chat says it once |

In combat the game usually hides buffs from addons, so expect `shield state unknown` there unless the game marks the shield
as never secret. `/frost reef debug` shows exactly what's readable on your client.

## Commands

The Frost Suite has no per-addon slash commands, only `/frost <sub>`. That keeps the risk of clashing with other addons low.

- `/frost reef test`: cycle the three states (out of combat)
- `/frost reef sound on|off`: the SHIELD DOWN sound (the game's own Frost Armor sound)
- `/frost reef debug`: what the game lets the addon see, rank by rank
- `/frost lock | unlock | scale 0.8-1.4 | reset | debug`: the shared dock

## Frost Suite

With other Frost Suite addons loaded, the boxes stack in one column with one padlock, one scale and only one glow at a time.
Barrier Reef is 4th in priority, after Hold the Weather, Eight Second Argument and Cone of Plenty.

## Checks

`tests/run.sh <wow-ui-source>`, `tools/verify_unit_events.py <wow-ui-source>`, `tools/check_suite_lib.sh <frost-suite-lib folder>`, `tools/verify_media.sh`.
Spell IDs, durations and cooldowns come from the game's own data tables (SpellName, SkillLineAbility, SpellMisc, SpellDuration,
SpellCooldowns) for build 1.60.1.70862.

MIT licence. Uses the game's own sounds and textures only.
