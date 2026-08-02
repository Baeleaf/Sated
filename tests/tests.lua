-- Sated behavioral tests. Each entry runs in a fresh stub environment
-- (see tests/run_tests.py). SATED_SHARED is the addon-private table.
--
-- Timeline model (Sprint 6 semantics): lust used at T. The 10-minute
-- Sated debuff is the cooldown. Marks are seconds SINCE USE (default
-- 3/5/10 min): pre-ready marks alert "Lust back in X", T+10:00 alerts
-- "Lust is up" (a mark equal to the cooldown is folded into that), and
-- marks past the cooldown alert "Lust has been up for X". Chat mirrors
-- every beat; default announce mode is "all" (whoever cast it).
TESTS = {}
local function add(name, fn) table.insert(TESTS, { name = name, fn = fn }) end
local S = SATED_SHARED

-- Sprint 0 ------------------------------------------------------------

add("addon loads and ADDON_LOADED initializes SatedDB", function()
  assert(type(S.Guard) == "function", "Guard missing")
  assert(type(SatedDB) == "table", "SatedDB not initialized")
  assert(S.db == SatedDB, "Sated.db not wired to SatedDB")
  assert(SatedDB.schema == 2, "schema stamp missing")
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

add("v2 migration wipes stale v1 marks and announce settings", function()
  SatedDB.marks = { 10, 20, 30 }   -- leftover test marks from a v1 install
  SatedDB.announce = false
  SatedDB.schema = nil
  S.handlers.ADDON_LOADED("Sated")
  assert(SatedDB.marks == nil, "stale marks survived migration")
  assert(SatedDB.announce == nil, "stale announce flag survived migration")
  assert(SatedDB.schema == 2, "schema not stamped")
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

add("/sated shows a running clock with back-up countdown", function()
  ApplyAura(57724, 600)
  AdvanceTime(90)
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("1:30"), "expected 1:30, got: " .. PRINTED[#PRINTED])
  assert(PRINTED[#PRINTED]:find("back up in 8:30"),
    "expected back-up countdown, got: " .. PRINTED[#PRINTED])
end)

add("elapsed survives /reload (server-timestamp persistence)", function()
  -- Simulate SavedVariables restored after a reload 90s into the window:
  SatedDB.lastLust = { at = GetTime() - 90, server = GetServerTime() - 90, mine = true }
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("1:30"), "reload elapsed wrong: " .. PRINTED[#PRINTED])
  assert(PRINTED[#PRINTED]:find("yours"), "mine flag not reported")
end)

-- Sprint 2 (marks are seconds since lust use) -------------------------

add("'Lust is up' alert fires exactly when the cooldown ends", function()
  SatedDB.marks = {}  -- isolate the ready alert
  ApplyAura(57724, 600)
  AdvanceTime(599)
  assert(#SCREEN_MESSAGES == 0, "alert fired early")
  AdvanceTime(2)
  assert(#SCREEN_MESSAGES == 1, "no ready alert at 10:00")
  assert(SCREEN_MESSAGES[1]:find("Lust is up"), "wrong text: " .. SCREEN_MESSAGES[1])
  assert(#PLAYED_SOUNDS == 1, "no sound on ready alert")
end)

add("custom marks fire since use with countdown text", function()
  RunSlash("/sated marks 10 20 30")
  assert(SatedDB.marks and SatedDB.marks[1] == 10, "marks not persisted")
  ApplyAura(57724, 600)
  AdvanceTime(35)
  assert(#SCREEN_MESSAGES == 3, "expected 3 marks, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[1]:find("Lust back in 9:50"),
    "first mark wrong: " .. SCREEN_MESSAGES[1])
  assert(SCREEN_MESSAGES[3]:find("Lust back in 9:30"),
    "third mark wrong: " .. SCREEN_MESSAGES[3])
  assert(#PLAYED_SOUNDS == 3, "expected 3 sounds, got " .. #PLAYED_SOUNDS)
end)

add("default marks: 3 min, 5 min, then 'Lust is up' at 10 min", function()
  ApplyAura(57724, 600)
  AdvanceTime(601)
  assert(#SCREEN_MESSAGES == 3, "expected 3 alerts, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[1]:find("Lust back in 7 min"),
    "3-min alert wrong: " .. SCREEN_MESSAGES[1])
  assert(SCREEN_MESSAGES[2]:find("Lust back in 5 min"),
    "5-min alert wrong: " .. SCREEN_MESSAGES[2])
  assert(SCREEN_MESSAGES[3]:find("Lust is up"),
    "10-min alert wrong: " .. SCREEN_MESSAGES[3])
end)

add("marks set past the cooldown read as up-time", function()
  RunSlash("/sated marks 780")
  ApplyAura(57724, 600)
  AdvanceTime(785)
  assert(#SCREEN_MESSAGES == 2, "expected ready + up-mark, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[2]:find("has been up for 3 min"),
    "up-mark wrong: " .. SCREEN_MESSAGES[2])
end)

add("/reload mid-cooldown: passed marks don't refire, later ones do", function()
  SatedDB.marks = { 10, 20, 30 }
  SatedDB.lastLust = { at = GetTime() - 15, server = GetServerTime() - 15, mine = false }
  FireEvent("PLAYER_ENTERING_WORLD")  -- what WoW fires after a /reload
  AdvanceTime(20)
  assert(#SCREEN_MESSAGES == 2,
    "expected exactly the 20s and 30s marks, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[1]:find("9:40") and SCREEN_MESSAGES[2]:find("9:30"),
    "wrong marks fired after reload")
end)

add("/reload after ready: passed ready/marks never refire", function()
  SatedDB.marks = { 10, 630 }
  SatedDB.lastLust = { at = GetTime() - 615, server = GetServerTime() - 615, mine = false }
  FireEvent("PLAYER_ENTERING_WORLD")
  AdvanceTime(20)
  assert(#SCREEN_MESSAGES == 1,
    "expected only the 630s up-mark, got " .. #SCREEN_MESSAGES)
  assert(SCREEN_MESSAGES[1]:find("has been up for 0:30"),
    "wrong alert after late reload: " .. SCREEN_MESSAGES[1])
end)

add("repeat PLAYER_ENTERING_WORLD (zone-in) never double-fires", function()
  RunSlash("/sated marks 10 20")
  ApplyAura(57724, 600)
  AdvanceTime(5)
  FireEvent("PLAYER_ENTERING_WORLD")
  FireEvent("PLAYER_ENTERING_WORLD")
  AdvanceTime(700)
  assert(#SCREEN_MESSAGES == 3,  -- both marks + ready, exactly once each
    "double-fired: got " .. #SCREEN_MESSAGES .. " alerts")
end)

add("alerts still fire while in combat (display path unrestricted)", function()
  RunSlash("/sated marks 10")
  ApplyAura(57724, 600)
  SetCombat(true)
  AdvanceTime(615)
  assert(#SCREEN_MESSAGES == 2, "mark + ready did not fire in combat")
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

add("/sated reset cancels pending alerts and clears the window", function()
  RunSlash("/sated marks 10 20")
  ApplyAura(57724, 600)
  RunSlash("/sated reset")
  assert(SatedDB.lastLust == nil, "window not cleared")
  AdvanceTime(700)
  assert(#SCREEN_MESSAGES == 0, "cancelled alerts still fired")
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("no lust recorded"), "status not reset")
end)

add("changing marks mid-window re-arms against the same window", function()
  RunSlash("/sated marks 100")
  ApplyAura(57724, 600)
  AdvanceTime(10)
  RunSlash("/sated marks 20 30")
  AdvanceTime(700)  -- 20s/30s marks + ready
  assert(#SCREEN_MESSAGES == 3, "re-armed alerts wrong: " .. #SCREEN_MESSAGES)
  AdvanceTime(100)
  assert(#SCREEN_MESSAGES == 3, "old 100s mark should be cancelled")
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

add("partner's lust announces too by default (mode all)", function()
  SetGroup(true, false)
  ApplyAura(57724, 600)  -- debuff only; we cast nothing
  assert(#SENT_MESSAGES == 1, "partner lust not announced in mode all")
  assert(SENT_MESSAGES[1].msg:find("^Lust used — back around"),
    "bad message: " .. SENT_MESSAGES[1].msg)
end)

add("/sated announce caster: partner silent, own cast speaks", function()
  SetGroup(true, false)
  RunSlash("/sated announce caster")
  assert(SatedDB.announceMode == "caster", "mode not persisted")
  ApplyAura(57724, 600)
  AdvanceTime(601)  -- marks + ready pass too
  assert(#SENT_MESSAGES == 0, "caster mode announced someone else's lust")
  RunSlash("/sated reset")
  CastSpell(2825)
  assert(#SENT_MESSAGES == 1, "caster mode silenced our own cast")
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

add("cast event never announces twice (repeat cast + repeat regen)", function()
  SetGroup(true, false)
  CastSpell(2825)
  CastSpell(2825)
  SetCombat(true)
  SetCombat(false)
  assert(#SENT_MESSAGES == 1, "double announce: " .. #SENT_MESSAGES)
end)

add("debuff then cast event: still exactly one cast announce", function()
  SetGroup(true, false)
  ApplyAura(57724, 600)      -- announces (mode all)
  CastSpell(2825)            -- upgrades mine; must not re-announce
  assert(#SENT_MESSAGES == 1, "expected 1 announce, got " .. #SENT_MESSAGES)
end)

add("never announces solo", function()
  SetGroup(false, false)
  CastSpell(2825)
  AdvanceTime(1201)          -- marks + ready pass too
  assert(#SENT_MESSAGES == 0, "announced while solo")
end)

add("/sated announce off silences everything; all restores", function()
  SetGroup(true, false)
  RunSlash("/sated announce off")
  assert(SatedDB.announceMode == "off", "announce=off not persisted")
  CastSpell(2825)
  AdvanceTime(601)
  assert(#SENT_MESSAGES == 0, "announced while disabled")
  RunSlash("/sated announce all")
  assert(SatedDB.announceMode == "all", "announce=all not persisted")
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
  AdvanceTime(615)           -- mark + ready fire during combat, chat queued
  SetCombat(false)
  RunSlash("/sated debug")
  local out = table.concat(PRINTED, "\n")
  assert(out:find("detect — mine"), "no detect entry")
  assert(out:find("mark — 0:10"), "no mark entry")
  assert(out:find("ready"), "no ready entry")
  assert(out:find("queue —"), "no queue entry")
  assert(out:find("announce — "), "no announce entry")
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

-- Sprint 6: marks since use + chat on every beat ----------------------

add("chat gets 3 min / 5 min countdowns then 'Lust is up.'", function()
  SetGroup(true, false)
  CastSpell(2825)            -- SENT 1: cast announce
  AdvanceTime(601)
  assert(#SENT_MESSAGES == 4, "expected 4 messages, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[2].msg == "Lust back in 7 min.",
    "3-min message wrong: " .. SENT_MESSAGES[2].msg)
  assert(SENT_MESSAGES[3].msg == "Lust back in 5 min.",
    "5-min message wrong: " .. SENT_MESSAGES[3].msg)
  assert(SENT_MESSAGES[4].msg == "Lust is up.",
    "ready message wrong: " .. SENT_MESSAGES[4].msg)
end)

add("partner's lust gets the full chat pipeline in mode all", function()
  SetGroup(true, false)
  ApplyAura(57724, 600)
  AdvanceTime(601)
  assert(#SENT_MESSAGES == 4, "expected 4 messages, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[4].msg == "Lust is up.", "last message not the ready beat")
end)

add("queued countdown mark re-phrases from the live clock", function()
  SetGroup(true, false)
  CastSpell(2825)            -- SENT 1
  SetCombat(true)
  AdvanceTime(250)           -- 3-min mark fired at 180 and queued
  SetCombat(false)
  assert(#SENT_MESSAGES == 2, "queue did not flush")
  assert(SENT_MESSAGES[2].msg == "Lust back in 5:50.",
    "not re-phrased live: " .. SENT_MESSAGES[2].msg)
end)

add("combat queue keeps only the newest beat (no message burst)", function()
  SetGroup(true, false)
  CastSpell(2825)            -- SENT 1
  SetCombat(true)
  AdvanceTime(601)           -- 3-min, 5-min, ready all queue; newest wins
  SetCombat(false)
  assert(#SENT_MESSAGES == 2,
    "expected one flushed message, got " .. (#SENT_MESSAGES - 1))
  assert(SENT_MESSAGES[2].msg == "Lust is up.",
    "wrong flushed message: " .. SENT_MESSAGES[2].msg)
end)

add("/sated status flips to up-for phrasing after ready", function()
  ApplyAura(57724, 600)
  AdvanceTime(690)
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("lust is UP"), "no up status: " .. PRINTED[#PRINTED])
  assert(PRINTED[#PRINTED]:find("has been up for 1:30"),
    "up-for time wrong: " .. PRINTED[#PRINTED])
end)