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
