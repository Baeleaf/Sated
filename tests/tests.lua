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

-- Sprint 2 ------------------------------------------------------------

add("custom marks fire alerts with sound at 10/20/30s", function()
  RunSlash("/sated marks 10 20 30")
  assert(SatedDB.marks and SatedDB.marks[1] == 10, "marks not persisted")
  ApplyAura(57724, 600)
  AdvanceTime(35)
  assert(#SCREEN_MESSAGES == 3, "expected 3 alerts, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[1]:find("0:10"), "first alert wrong: " .. SCREEN_MESSAGES[1])
  assert(SCREEN_MESSAGES[3]:find("0:30"), "third alert wrong: " .. SCREEN_MESSAGES[3])
  assert(#PLAYED_SOUNDS == 3, "expected 3 sounds, got " .. #PLAYED_SOUNDS)
end)

add("default marks fire at 3:00 / 5:00 / 10:00", function()
  ApplyAura(57724, 600)
  AdvanceTime(601)
  assert(#SCREEN_MESSAGES == 3, "expected 3 alerts, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[1]:find("3:00") and SCREEN_MESSAGES[2]:find("5:00")
    and SCREEN_MESSAGES[3]:find("10:00"), "default mark labels wrong")
end)

add("/reload at 15s: later marks fire once, passed mark does not", function()
  SatedDB.marks = { 10, 20, 30 }
  SatedDB.lastLust = { at = GetTime() - 15, server = GetServerTime() - 15, mine = false }
  FireEvent("PLAYER_ENTERING_WORLD")  -- what WoW fires after a /reload
  AdvanceTime(30)
  assert(#SCREEN_MESSAGES == 2,
    "expected exactly the 20s and 30s alerts, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[1]:find("0:20") and SCREEN_MESSAGES[2]:find("0:30"),
    "wrong marks fired after reload")
end)

add("repeat PLAYER_ENTERING_WORLD (zone-in) never double-fires marks", function()
  RunSlash("/sated marks 10 20")
  ApplyAura(57724, 600)
  AdvanceTime(5)
  FireEvent("PLAYER_ENTERING_WORLD")
  FireEvent("PLAYER_ENTERING_WORLD")
  AdvanceTime(30)
  assert(#SCREEN_MESSAGES == 2, "double-fired: got " .. #SCREEN_MESSAGES .. " alerts")
end)

add("alerts still fire while in combat (display path unrestricted)", function()
  RunSlash("/sated marks 10")
  ApplyAura(57724, 600)
  SetCombat(true)
  AdvanceTime(15)
  assert(#SCREEN_MESSAGES == 1, "alert did not fire in combat")
  SetCombat(false)
end)

add("/sated sound off silences alerts; on restores; persisted", function()
  RunSlash("/sated sound off")
  assert(SatedDB.sound == false, "sound=off not persisted")
  RunSlash("/sated marks 10")
  ApplyAura(57724, 600)
  AdvanceTime(15)
  assert(#SCREEN_MESSAGES == 1 and #PLAYED_SOUNDS == 0,
    "alert should show without sound")
  RunSlash("/sated sound on")
  assert(SatedDB.sound == true, "sound=on not persisted")
end)

add("/sated reset cancels pending marks and clears the window", function()
  RunSlash("/sated marks 10 20")
  ApplyAura(57724, 600)
  RunSlash("/sated reset")
  assert(SatedDB.lastLust == nil, "window not cleared")
  AdvanceTime(60)
  assert(#SCREEN_MESSAGES == 0, "cancelled marks still fired")
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("no lust recorded"), "status not reset")
end)

add("changing marks mid-window re-arms against the same window", function()
  RunSlash("/sated marks 100")
  ApplyAura(57724, 600)
  AdvanceTime(10)
  RunSlash("/sated marks 20 30")   -- 20s mark is 10s away now
  AdvanceTime(25)                  -- now at t=35 into the window
  assert(#SCREEN_MESSAGES == 2, "re-armed marks wrong: " .. #SCREEN_MESSAGES)
  AdvanceTime(100)
  assert(#SCREEN_MESSAGES == 2, "old 100s mark should be cancelled")
end)

add("bad marks input rejected, marks unchanged", function()
  RunSlash("/sated marks 10 nope 30")
  assert(SatedDB.marks == nil, "invalid input must not persist")
  assert(PRINTED[#PRINTED]:find("usage"), "no usage message")
end)

-- Sprint 3 ------------------------------------------------------------

add("own cast in a party, out of combat: one PARTY message", function()
  SetGroup(true, false)
  CastSpell(2825)
  assert(#SENT_MESSAGES == 1, "expected 1 message, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[1].chatType == "PARTY", "wrong channel: " .. tostring(SENT_MESSAGES[1].chatType))
  assert(SENT_MESSAGES[1].msg:find("^Lust used — back around %d+:%d+%.$"),
    "bad message: " .. SENT_MESSAGES[1].msg)
end)

add("instance group announces to INSTANCE_CHAT", function()
  SetGroup(false, true)
  CastSpell(80353)
  assert(#SENT_MESSAGES == 1 and SENT_MESSAGES[1].chatType == "INSTANCE_CHAT",
    "expected INSTANCE_CHAT announce")
end)

add("cast mid-combat: queued, flushed on regen with elapsed phrasing", function()
  SetGroup(true, false)
  SetCombat(true)
  CastSpell(2825)
  assert(#SENT_MESSAGES == 0, "announced during combat")
  AdvanceTime(130)
  SetCombat(false)  -- fires PLAYER_REGEN_ENABLED
  assert(#SENT_MESSAGES == 1, "queue did not flush on regen")
  assert(SENT_MESSAGES[1].msg:find("was used 2:10 ago"),
    "elapsed phrasing wrong: " .. SENT_MESSAGES[1].msg)
end)

add("cast during encounter: queued, flushed on ENCOUNTER_END", function()
  SetGroup(true, false)
  SetEncounter(true)
  CastSpell(2825)
  assert(#SENT_MESSAGES == 0, "announced during encounter")
  AdvanceTime(30)
  SetEncounter(false)
  assert(#SENT_MESSAGES == 1, "queue did not flush on encounter end")
end)

add("regen mid-encounter keeps the queue until encounter ends", function()
  SetGroup(true, false)
  SetEncounter(true)
  SetCombat(true)
  CastSpell(2825)
  SetCombat(false)          -- regen fires but boss fight still running
  assert(#SENT_MESSAGES == 0, "flushed while encounter still active")
  SetEncounter(false)
  assert(#SENT_MESSAGES == 1, "never flushed after encounter end")
end)

add("partner's lust: silent in chat, local timers still run", function()
  SetGroup(true, false)
  RunSlash("/sated marks 10")
  ApplyAura(57724, 600)      -- debuff only; we cast nothing
  AdvanceTime(15)
  assert(#SENT_MESSAGES == 0, "announced someone else's lust")
  assert(#SCREEN_MESSAGES == 1, "local timers did not run")
end)

add("never announces twice per window (repeat cast + repeat regen)", function()
  SetGroup(true, false)
  CastSpell(2825)
  CastSpell(2825)
  SetCombat(true)
  SetCombat(false)
  assert(#SENT_MESSAGES == 1, "double announce: " .. #SENT_MESSAGES)
end)

add("debuff lands before cast event: still exactly one announce", function()
  SetGroup(true, false)
  ApplyAura(57724, 600)      -- our own debuff arrives first
  CastSpell(2825)            -- then the cast event upgrades mine
  assert(#SENT_MESSAGES == 1, "expected 1 announce, got " .. #SENT_MESSAGES)
end)

add("never announces solo", function()
  SetGroup(false, false)
  CastSpell(2825)
  assert(#SENT_MESSAGES == 0, "announced while solo")
end)

add("/sated announce off silences; on restores; persisted", function()
  SetGroup(true, false)
  RunSlash("/sated announce off")
  assert(SatedDB.announce == false, "announce=off not persisted")
  CastSpell(2825)
  assert(#SENT_MESSAGES == 0, "announced while disabled")
  RunSlash("/sated announce on")
  assert(SatedDB.announce == true, "announce=on not persisted")
end)

add("queued announce is dropped on zone change (run over)", function()
  SetGroup(true, false)
  SetCombat(true)
  CastSpell(2825)
  FireEvent("PLAYER_ENTERING_WORLD")  -- left the instance before regen
  SetCombat(false)
  assert(#SENT_MESSAGES == 0, "stale queue was announced")
end)

add("queued announce is dropped by /sated reset", function()
  SetGroup(true, false)
  SetCombat(true)
  CastSpell(2825)
  RunSlash("/sated reset")
  SetCombat(false)
  assert(#SENT_MESSAGES == 0, "reset window still announced")
end)

-- Sprint 4 ------------------------------------------------------------

add("/sated debug shows a sane event trail for a full run", function()
  SetGroup(true, false)
  RunSlash("/sated marks 10")
  SetCombat(true)
  CastSpell(2825)
  ApplyAura(57724, 600)
  AdvanceTime(15)
  SetCombat(false)
  RunSlash("/sated debug")
  local out = table.concat(PRINTED, "\n")
  assert(out:find("detect — mine"), "no detect entry")
  assert(out:find("mark — 0:10"), "no mark entry")
  assert(out:find("queue —"), "no queue entry")
  assert(out:find("announce — PARTY"), "no announce entry")
end)

add("secret encounters are logged to the debug buffer", function()
  ApplyAura(57724, 600, { secret = true })
  CastSpell(2825, { secret = true })
  RunSlash("/sated debug")
  local out = table.concat(PRINTED, "\n")
  assert(out:find("secret — aura.spellId"), "aura secret not logged")
  assert(out:find("secret — cast.spellId"), "cast secret not logged")
end)

add("debug ring buffer caps at 20 entries", function()
  for i = 1, 30 do SATED_SHARED.DebugLog("test", tostring(i)) end
  RunSlash("/sated debug")
  local count = 0
  for _, line in ipairs(PRINTED) do
    if line:find("test — ") then count = count + 1 end
  end
  assert(count == 20, "expected 20 entries, got " .. count)
  assert(table.concat(PRINTED, "\n"):find("test — 30"), "newest entry missing")
  assert(not table.concat(PRINTED, "\n"):find("test — 5\n"), "oldest entries not evicted")
end)

add("secret isFullUpdate flag routes to the safe rescan path", function()
  ApplyAura(57724, 600, { silentAdd = true })
  FireEvent("UNIT_AURA", "player",
    { addedAuras = {}, isFullUpdate = MakeSecret() })
  assert(SatedDB.lastLust, "secret full-update flag broke detection")
end)

add("empty debug buffer prints a friendly line", function()
  RunSlash("/sated debug")
  assert(PRINTED[#PRINTED]:find("debug buffer empty"), "no empty message")
end)
