-- Barrier Reef: Ice Barrier's damage window for Frost Mages on WoW: Forever. Written from scratch (MIT).
--
-- Why: official Nov 2, 2026 notes made Ice Barrier a damage cooldown. The client tooltip: "increasing your Frost damage by
-- 15% for 1 min. While shielded, your Frost damage is increased by an additional 5%". The 15% is its own aura, Frigid Power
-- (1326891, referenced from Ice Barrier's tooltip as $1326891s1). This box shows one of three states:
--   REEF +20%    the minute is running and the shield still holds
--   BUFF +15%    the minute is running, the shield is gone: REFRESH (a recast restarts the minute and the extra 5%)
--   SHIELD DOWN  in combat, neither is up and Ice Barrier is off cooldown
-- It never draws an absorb bar (Dyre's Shields Up does that) and never casts anything.
--
-- What it can see (picked at runtime; /frost reef debug prints it):
--   the +15% minute: "aura" when Frigid Power can be read right now (never-secret, or the client says it isn't secret), else
--                    "cast": your own Ice Barrier UNIT_SPELLCAST_SUCCEEDED plus 60 s (SpellMisc DurationIndex 3 = 60000 ms,
--                    build 1.60.1.70862; the buff is a fixed minute), else "none" when the client hides your casts.
--   the shield:      "aura" when the Ice Barrier aura can be read right now, else "unknown": the box says
--                    "shield state unknown" and shows BUFF +15% only, never a guessed +20%.
--   the cooldown:    30 s from your cast (SpellCooldowns category 471 "Ice Barrier", 30000 ms); a Cold Snap cast clears it.
-- Spell IDs: SpellName + SkillLineAbility (Mage, Frost), builds 1.60.1.70862 and 70888.
local ADDON, ns = ...
local C, Core, FS = ns.Compat, ns.Core, ns.FrostSuite
local L = Core.L

local BR = {}
KennyBarrierReef = BR
ns.BR = BR
local KEY = "BarrierReef"
local SCHEMA = 1

BR.BARRIER = { [11426] = 1, [13031] = 2, [13032] = 3, [13033] = 4 }
BR.BUFF = 1326891      -- Frigid Power: +15% Frost damage for 1 min
BR.COLD_SNAP = 12472
BR.BUFF_SECONDS = 60
BR.COOLDOWN = 30
-- Ice Barrier is a talent: Talent TierID 6 = level 40 (10 + 5 x 6), SpellLevels.BaseLevel 40 (spell 11426), build 1.60.1.71037.
BR.NEEDS = { { name = L["Ice Barrier"], level = 40, spells = BR.BARRIER, talent = true } }
BR.DEFAULTS = {}

local db, row
local migrations = {}
BR.castAt = nil        -- GetTime() of your last Ice Barrier
BR.lastRank = nil      -- its spell ID (rank)
BR.cdFrom = nil        -- GetTime() the cooldown started (nil = ready; Cold Snap clears it)
BR.hiddenEvents, BR.plainCasts = 0, 0
BR.known = true
BR.modes = { buff = "cast", shield = "unknown" }
BR.state = "idle"
local gen = 0

local function now() return C.Clock() end

-- ---------- detection ----------
function BR.CastsHidden() return BR.hiddenEvents > 0 and BR.plainCasts == 0 end
function BR.EvaluateModes()
  local barrierRead = false
  for id in pairs(BR.BARRIER) do if FS.AuraReadableNow(id, "player") then barrierRead = true end end
  local castOK = not BR.CastsHidden()
  for id in pairs(BR.BARRIER) do if FS.CastSecrecy(id) == 1 then castOK = false end end
  BR.modes.buff = FS.AuraReadableNow(BR.BUFF, "player") and "aura" or (castOK and "cast" or "none")
  BR.modes.shield = barrierRead and "aura" or "unknown"
  return BR.modes
end

-- The +15% minute: true/false and when it ends. The minute is the same length for every rank, so the cast timer is exact
-- unless the buff is removed (only an aura read can show that).
function BR.Buff()
  if BR.modes.buff == "aura" then
    local a, ok = FS.ReadAura("player", BR.BUFF)
    if ok then
      if not a then return false end
      local exp = FS.AuraField(a, "expirationTime")
      return true, (exp and exp > 0) and exp or (BR.castAt and BR.castAt + BR.BUFF_SECONDS)
    end
  end
  if BR.modes.buff == "none" or not BR.castAt then return false end
  local t = BR.castAt + BR.BUFF_SECONDS
  return now() < t, t
end

-- "up", "down" or "unknown". A rank whose aura can't be read right now can't prove "down"; the rank you last cast can.
function BR.Shield(buffUp)
  if BR.modes.shield == "aura" then
    local unreadable = false
    for id in pairs(BR.BARRIER) do
      local a, ok = FS.ReadAura("player", id)
      if ok and a then return "up" end
      if not ok then unreadable = true end
    end
    if not unreadable or (BR.lastRank and FS.AuraReadableNow(BR.lastRank, "player")) then return "down" end
  end
  return buffUp and "unknown" or "down" -- the shield never outlasts the minute (both 60 s)
end

function BR.CooldownLeft()
  if not BR.cdFrom then return 0 end
  local left = BR.cdFrom + BR.COOLDOWN - now()
  if left <= 0 then BR.cdFrom = nil; return 0 end
  return left
end

-- ---------- state ----------
function BR.Compute()
  if not BR.known then return "hidden" end
  local up, untilT = BR.Buff()
  local shield = BR.Shield(up)
  BR.buffUntil = up and untilT or nil
  BR.shield = shield
  if up then
    if shield == "up" then return "reef" end
    if shield == "down" then return "refresh" end
    return "buff"
  end
  if C.InCombat() and BR.CooldownLeft() == 0 and BR.modes.buff ~= "none" then return "down" end
  return "idle"
end

local function tick()
  gen = gen + 1
  local mine = gen
  C_Timer.After(1, function() if mine == gen then BR.Update() end end)
end

function BR.Update()
  BR.EvaluateModes()
  local old, new = BR.state, BR.Compute()
  BR.state = new
  if new ~= old then
    if new == "refresh" and old == "reef" then FS.RequestFlash(KEY, "PULSE")
    elseif new == "down" and (old == "reef" or old == "buff" or old == "refresh") then
      if FS.RequestFlash(KEY, "PULSE") then FS.PlaySound(KEY) end
    end
  end
  if row then BR.Paint() end
  if new == "reef" or new == "buff" or new == "refresh" or BR.CooldownLeft() > 0 then tick() end
  return new
end

function BR.Paint()
  local s = BR.state
  if s == "hidden" then
    if BR.need then FS.NotYet(KEY, BR.need) else FS.State(KEY, "hidden") end
    return
  end
  FS.ClearLines(KEY)
  local left = BR.buffUntil and math.max(0, BR.buffUntil - now()) or nil
  if s == "reef" or s == "buff" or s == "refresh" then
    FS.Headline(KEY, s == "reef" and L["REEF +20%"] or L["BUFF +15%"], "ReefTeal")
    FS.Bar(KEY, left and left / BR.BUFF_SECONDS or nil, "ReefTeal")
    if s == "refresh" then
      FS.Line(KEY, 2, BR.CooldownLeft() > 0 and L["REFRESH when Ice Barrier is ready"] or L["REFRESH"])
    end
    FS.Status(KEY, s == "buff" and L["shield state unknown"] or (left and (("%d s"):format(math.ceil(left))) or ""), "Mist")
    FS.State(KEY, "active")
  elseif s == "down" then
    FS.Headline(KEY, L["SHIELD DOWN"], "ReefTeal")
    FS.Bar(KEY, nil)
    FS.Status(KEY, L["ready"], "Mist")
    FS.State(KEY, "active")
  else
    FS.Headline(KEY, "")
    FS.Bar(KEY, nil)
    local text = BR.modes.buff == "none" and L["can't see your casts here"]
      or (BR.CooldownLeft() > 0 and L["on cooldown"] or L["ready"])
    FS.Status(KEY, text, "Mist")
    FS.State(KEY, "idle")
  end
end

-- ---------- events ----------
function BR.OnSpellcast(unit, _, spellID)
  if unit ~= "player" then return end
  if C.IsSecret(spellID) then
    BR.hiddenEvents = BR.hiddenEvents + 1
    if BR.CastsHidden() and not BR.toldHidden then
      BR.toldHidden = true
      Core.Print(L["The client is hiding your casts here, so Barrier Reef can't start its timer. /frost reef debug shows why."])
    end
    return BR.Update()
  end
  if BR.BARRIER[spellID] then
    BR.plainCasts = BR.plainCasts + 1
    BR.castAt, BR.cdFrom, BR.lastRank = now(), now(), spellID
    BR.Update()
  elseif spellID == BR.COLD_SNAP then
    BR.cdFrom = nil -- "Finishes the remaining cooldown on all your other Frost spells"
    BR.Update()
  end
end

function BR.OnAura(unit) if unit == "player" then BR.Update() end end

function BR.Test()
  if C.InCombat() then Core.Print(L["The preview only runs out of combat."]); return false end
  local steps = { "reef", "refresh", "down" }
  BR.preview = true
  for i, s in ipairs(steps) do
    C_Timer.After((i - 1) * 2, function()
      BR.state = s; BR.buffUntil = s ~= "down" and now() + 40 or nil
      if s == "refresh" or s == "down" then FS.RequestFlash(KEY, "PULSE") end
      BR.Paint()
    end)
  end
  C_Timer.After(#steps * 2, function() BR.preview = false; BR.state = "idle"; BR.Update() end)
  return true
end

function BR.DetectionLines()
  BR.EvaluateModes()
  local up, t = BR.Buff()
  local out = {
    ("+15%% minute (Frigid Power %d): %s  (aura = buff read, cast = 60 s from your Ice Barrier, none = can't see)"):format(BR.BUFF, BR.modes.buff),
    ("shield (+5%%): %s  (aura = Ice Barrier read, unknown = the client hides it)"):format(BR.modes.shield),
    ("secret restrictions: %s, in combat: %s, knows Ice Barrier: %s"):format(tostring(FS.Restricted()), tostring(C.InCombat()), tostring(BR.known)),
    ("buff up: %s%s, shield: %s, cooldown left: %d s, state: %s"):format(tostring(up), up and t and (" (" .. math.ceil(t - now()) .. " s)") or "",
      tostring(BR.Shield(up)), math.ceil(BR.CooldownLeft()), BR.state),
    ("cast events: %d plain Ice Barrier, %d hidden"):format(BR.plainCasts, BR.hiddenEvents),
    ("  %d Frigid Power: aura secrecy %s (0 = never secret)"):format(BR.BUFF, tostring(FS.AuraSecrecy(BR.BUFF))),
  }
  local ids = {}
  for id in pairs(BR.BARRIER) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    out[#out + 1] = ("  %d Ice Barrier %d: aura secrecy %s, cast secrecy %s"):format(id, BR.BARRIER[id],
      tostring(FS.AuraSecrecy(id)), tostring(FS.CastSecrecy(id)))
  end
  return out
end

function BR.Slash(msg)
  local cmd, a = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "test" then BR.Test()
  elseif cmd == "sound" and (a == "on" or a == "off") then db.sound = a == "on"; Core.Print(L["sound:"] .. " " .. a)
  elseif cmd == "debug" then for _, l in ipairs(BR.DetectionLines()) do Core.Print(l) end
  else Core.Print("/frost reef test | sound on|off | debug") end
end

-- ---------- wiring ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")

local function refresh()
  if not C.InCombat() then
    BR.need = FS.IsMage() and FS.Missing(BR.NEEDS) or nil
    BR.known = FS.IsMage() and BR.need == nil
    if BR.known then FS.Learned(KEY) end
  end
  BR.Update()
end
local handlers = {
  PLAYER_LOGIN = refresh, SPELLS_CHANGED = refresh, PLAYER_REGEN_ENABLED = refresh,
  PLAYER_REGEN_DISABLED = function() BR.Update() end,
  UNIT_SPELLCAST_SUCCEEDED = BR.OnSpellcast,
  UNIT_AURA = BR.OnAura,
}
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyBarrierReefDB, migrations, SCHEMA)
    KennyBarrierReefDB = db
    row = FS.Register(KEY, db, { title = L["Barrier Reef"], slash = BR.Slash, help = "test | sound on|off | debug", debug = Core.PrintDebug,
      refresh = refresh })
    Core.SafeCall("refresh", refresh)
    return
  end
  local h = handlers[event]
  if h and db and not BR.preview then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = "/frost reef",
  required = { "C_Timer.After", "PlaySoundFile" },
  optional = { "C_UnitAuras.GetPlayerAuraBySpellID", "C_Secrets.HasSecretRestrictions", "C_Secrets.GetSpellAuraSecrecy",
    "C_Secrets.ShouldSpellAuraBeSecret", "C_Secrets.GetSpellCastSecrecy", "C_SpellBook.IsSpellKnown" },
  db = function() return db end,
  firstRun = { L["Barrier Reef is ready: it shows Ice Barrier's +15% / +20% Frost damage window. /frost reef test shows the states."] },
  debugLines = function() return BR.DetectionLines() end })
