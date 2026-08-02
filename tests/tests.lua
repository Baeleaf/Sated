-- Sated behavioral tests. Each entry runs in a fresh stub environment
-- (see tests/run_tests.py). SATED_SHARED is the addon-private table.
TESTS = {}
local function add(name, fn) table.insert(TESTS, { name = name, fn = fn }) end
local S = SATED_SHARED

-- Sprint 0 ------------------------------------------------------------

add("addon loads and ADDON_LOADED initializes SatedDB", function()
  assert(type(S.Guard) == "function", "Guard missing")
  assert(type(SatedDB) == "table", "SatedDB not initialized")
  assert(S.db == SatedDB, "Sated.db not wired to SatedDB")
end)

add("config tables carry the briefed IDs", function()
  assert(S.LUST_CASTS[2825] == "Bloodlust", "Bloodlust cast id missing")
  assert(S.LUST_CASTS[390386] == "Fury of the Aspects", "Evoker cast id missing")
  assert(S.SATED_DEBUFFS[57724] == true, "Sated debuff id missing")
  assert(S.SATED_DEBUFFS[390435] == true, "Evoker exhaustion id missing")
  assert(#S.DEFAULT_MARKS == 3 and S.DEFAULT_MARKS[1] == 180
    and S.DEFAULT_MARKS[2] == 300 and S.DEFAULT_MARKS[3] == 600,
    "default marks wrong")
end)

add("Guard passes plain values through", function()
  assert(S.Guard(42) == 42)
  assert(S.Guard("x") == "x")
  assert(S.Guard(true) == true)
  assert(S.Guard(nil) == nil)
end)

add("Guard nils secret values", function()
  local s = MakeSecret()
  assert(S.Guard(s) == nil, "secret value leaked through Guard")
end)

add("/sated prints the loaded message", function()
  assert(RunSlash("/sated"), "slash command not registered")
  assert(#PRINTED >= 1, "nothing printed")
  assert(PRINTED[#PRINTED]:find("Sated"), "message does not mention Sated")
end)

-- Sprint 1 ------------------------------------------------------------

add("own sated debuff opens a window (debuff path, mine=false)", function()
  ApplyAura(57724, 600)
  assert(SatedDB.lastLust, "no lust window recorded")
  assert(SatedDB.lastLust.mine == false, "debuff path must not claim mine")
  assert(PRINTED[#PRINTED]:find("timers armed"), "no detection message")
end)

add("someone else's lust: debuff-only detection still works", function()
  ApplyAura(390435, 600)  -- Evoker exhaustion, no cast event from us
  assert(SatedDB.lastLust and SatedDB.lastLust.mine == false)
end)

add("own cast tags the window mine=true; debuff does not re-open", function()
  CastSpell(2825)
  assert(SatedDB.lastLust and SatedDB.lastLust.mine == true, "cast path missed")
  local prints = #PRINTED
  ApplyAura(57724, 600)  -- the debuff lands right after our cast
  assert(#PRINTED == prints, "window re-opened / double print")
  assert(SatedDB.lastLust.mine == true, "mine flag lost")
end)

add("debuff first then cast upgrades mine flag without reopening", function()
  ApplyAura(57724, 600)
  local firstServer = SatedDB.lastLust.server
  CastSpell(2825)
  assert(SatedDB.lastLust.mine == true, "mine not upgraded")
  assert(SatedDB.lastLust.server == firstServer, "window was reopened")
end)

add("re-detections inside an active window are ignored", function()
  ApplyAura(57724, 600)
  local prints = #PRINTED
  ApplyAura(57724, 600)
  ApplyAura(80354, 600)
  assert(#PRINTED == prints, "re-detection was not ignored")
end)

add("secret aura spellId degrades silently (no error, no window)", function()
  ApplyAura(57724, 600, { secret = true })
  assert(SatedDB.lastLust == nil, "secret aura must not open a window")
end)

add("secret cast spellId degrades silently", function()
  CastSpell(2825, { secret = true })
  assert(SatedDB.lastLust == nil, "secret cast must not open a window")
end)

add("full-update payload falls back to a whole-bar rescan", function()
  ApplyAura(264689, 600, { silentAdd = true })  -- in aura list, no incremental event
  FireFullAuraUpdate()
  assert(SatedDB.lastLust, "full update rescan missed the debuff")
end)

add("irrelevant auras open nothing", function()
  ApplyAura(8921, 12)  -- Moonfire is not lust
  assert(SatedDB.lastLust == nil)
end)

add("non-lust casts open nothing", function()
  CastSpell(116)  -- Frostbolt
  assert(SatedDB.lastLust == nil)
end)

add("/sated shows a running mm:ss clock", function()
  ApplyAura(57724, 600)
  AdvanceTime(90)
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("1:30"), "expected 1:30, got: " .. PRINTED[#PRINTED])
end)

add("elapsed survives /reload (server-timestamp persistence)", function()
  -- Simulate SavedVariables restored after a reload 90s into the window:
  SatedDB.lastLust = { at = GetTime() - 90, server = GetServerTime() - 90, mine = true }
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("1:30"), "reload elapsed wrong: " .. PRINTED[#PRINTED])
  assert(PRINTED[#PRINTED]:find("yours"), "mine flag not reported")
end)
