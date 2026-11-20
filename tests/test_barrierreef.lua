-- Barrier Reef: the three states, Cold Snap, and honest "shield state unknown", against realistic secret-value rules.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local S = W.S
local check = W.check
local ns = W.loadAddon(".", "BarrierReef")
W.fire("PLAYER_LOGIN")
local BR, FS = ns.BR, _G.FrostSuite_1_0
local row = FS.rows.BarrierReef
local IB, FP = 13033, 1326891

local function reset()
  W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(100)
  S.install(W); W.sounds = {}; W.prints = {}
  BR.lastRank, BR.castAt, BR.cdFrom, BR.hiddenEvents, BR.plainCasts, BR.toldHidden = nil, nil, nil, 0, 0, nil
  FS.lastSound = -100; FS.flashKey = nil
  W.fire("PLAYER_LOGIN")
end
local function fight() W.combat = true; W.fire("PLAYER_REGEN_DISABLED") end
local function barrier() S.cast(IB); S.gain(IB, 0, 60); S.gain(FP, 0, 60) end

check(BR.BUFF_SECONDS == 60 and BR.COOLDOWN == 30, "60 s minute, 30 s cooldown (client data)")
check(row.statusText == "ready" and row.state == "idle", "idle strip: ready")

-- 1. Strict client: auras secret in combat. The minute comes from the cast; the shield is unknown; never +20%.
reset(); fight(); S.reads = 0
check(BR.modes.buff == "cast" and BR.modes.shield == "unknown", "strict: buff by cast, shield unknown")
check(row.headText == "SHIELD DOWN", "in combat, nothing up, off cooldown: SHIELD DOWN")
barrier()
check(BR.state == "buff" and row.headText == "BUFF +15%" and row.statusText == "shield state unknown", "BUFF +15% + shield unknown")
check(row.headText ~= "REEF +20%", "never a guessed +20%")
check(S.reads == 0, "no aura reads while auras are secret")
W.advance(30)
check(BR.state == "buff" and math.abs(row.barValue - 0.5) < 0.05, "bar halfway at 30 s")
W.advance(30.5)
check(BR.state == "down" and row.headText == "SHIELD DOWN", "the minute ends: SHIELD DOWN (off cooldown)")
check(FS.Glowing() == "BarrierReef" and #W.sounds == 1 and W.sounds[1][1] == 569286, "pulse + frostarmor sound on SHIELD DOWN")

-- 2. Out of combat everything is readable: REEF +20%, then the shield breaks -> BUFF +15% + REFRESH.
reset()
barrier()
check(BR.modes.shield == "aura" and BR.state == "reef" and row.headText == "REEF +20%", "readable: REEF +20%")
S.drop(IB)
check(BR.state == "refresh" and row.headText == "BUFF +15%", "shield gone: BUFF +15%")
check(row.lineText[2] == "REFRESH when Ice Barrier is ready", "REFRESH waits for the 30 s cooldown")
W.advance(31)
check(row.lineText[2] == "REFRESH", "REFRESH once off cooldown")
-- Cold Snap clears the cooldown.
barrier(); S.drop(IB)
check(BR.CooldownLeft() > 0, "cooldown running")
S.cast(12472)
check(BR.CooldownLeft() == 0 and row.lineText[2] == "REFRESH", "Cold Snap clears it")

-- 3. Never-secret Frigid Power and Ice Barrier: aura mode in combat, the shield break is seen live.
reset(); S.never[IB] = true; S.never[FP] = true; fight()
check(BR.modes.buff == "aura" and BR.modes.shield == "aura", "never-secret: both by aura in combat")
barrier()
check(BR.state == "reef", "REEF +20% in combat")
W.advance(5)
S.drop(IB)
check(BR.state == "refresh" and FS.Glowing() == "BarrierReef", "shield broke: REFRESH pulse")
S.drop(FP)
check(BR.state == "idle" and row.statusText == "on cooldown", "buff removed early (aura), Ice Barrier on cooldown: quiet")
W.advance(26)
check(BR.state == "down" and row.headText == "SHIELD DOWN", "off cooldown again: SHIELD DOWN")

-- 4. Hidden casts: fail visibly, no timer from a guess.
reset(); S.castSecretInCombat = true; fight()
S.cast(IB)
check(BR.modes.buff == "none" and BR.castAt == nil, "hidden cast: no timer")
check(row.statusText == "can't see your casts here" and row.headText ~= "SHIELD DOWN", "box says it can't see casts")
check(W.printed("can't start its timer"), "chat says so once")

-- 5. Not a Mage / no Ice Barrier: no slot. Other units ignored.
reset(); W.known = {}; W.fire("SPELLS_CHANGED")
check(row.state == "hidden", "Ice Barrier not known: hidden")
W.known = nil; W.fire("SPELLS_CHANGED")
S.cast(IB, "party1")
check(BR.castAt == nil, "other units' Ice Barrier ignored")

-- 6. /frost reef test cycles the three states out of combat.
reset()
SlashCmdList.FROSTSUITE("reef test")
W.advance(0.01); check(row.headText == "REEF +20%", "test: REEF")
W.advance(2); check(row.headText == "BUFF +15%" and row.lineText[2] == "REFRESH", "test: BUFF + REFRESH")
W.advance(2); check(row.headText == "SHIELD DOWN", "test: SHIELD DOWN")
W.advance(2.1); check(row.state == "idle", "test ends")
local src = io.open("BarrierReef.lua"):read("*a")
check(not src:find("CastSpell") and not src:find("TargetUnit") and not src:find("UseAction"), "no cast, target or movement calls")
W.done("BarrierReef")
