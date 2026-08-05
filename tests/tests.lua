-- Sated behavioral tests. Each entry runs in a fresh stub environment
-- (see tests/run_tests.py). SATED_SHARED is the addon-private table.
--
-- Timeline model (Sprint 7 semantics): lust used at T; the 10-minute
-- Sated debuff is the blocker. T+10:00 (debuff falls off) → "Lust is
-- up". Marks are seconds AFTER that moment (default 3/5/10 min →
-- T+13:00 / T+15:00 / T+20:00) as "Lust has been up for N min". Chat
-- mirrors every beat; default announce mode is "all" (whoever cast it).
TESTS = {}
local function add(name, fn) table.insert(TESTS, { name = name, fn = fn }) end
local S = SATED_SHARED

-- Sprint 0 ------------------------------------------------------------

add("addon loads and ADDON_LOADED initializes SatedDB", function()
  assert(type(S.Guard) == "function", "Guard missing")
  assert(type(SatedDB) == "table", "SatedDB not initialized")
  assert(S.db == SatedDB, "Sated.db not wired to SatedDB")
  assert(SatedDB.schema == 3, "schema stamp missing")
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

add("v3 migration wipes stale marks, keeps announceMode", function()
  SatedDB.marks = { 10, 20, 30 }   -- leftover marks from older semantics
  SatedDB.announce = false
  SatedDB.announceMode = "caster"
  SatedDB.schema = 2
  S.handlers.ADDON_LOADED("Sated")
  assert(SatedDB.marks == nil, "stale marks survived migration")
  assert(SatedDB.announce == nil, "stale announce flag survived migration")
  assert(SatedDB.announceMode == "caster", "announceMode should survive")
  assert(SatedDB.schema == 3, "schema not stamped")
  SatedDB.announceMode = nil
end)

-- Sprint 1 ------------------------------------------------------------

add("own sated debuff opens a window (debuff path, mine=false)", function()
  ApplyAura(57724, 600)
  assert(SatedDB.lastLust, "no lust window recorded")
  assert(SatedDB.lastLust.mine == false, "debuff path must not claim mine")
  assert(#PRINTED == 0, "detection must not print a local message")
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
  local record = SatedDB.lastLust
  ApplyAura(57724, 600)
  ApplyAura(80354, 600)
  assert(SatedDB.lastLust == record, "re-detection was not ignored")
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

add("'Lust is up' party message fires exactly when the cooldown ends", function()
  SatedDB.marks = {}  -- isolate the ready message
  SetGroup(true, false)
  ApplyAura(57724, 600)
  AdvanceTime(599)
  assert(#SENT_MESSAGES == 1, "ready message fired early")
  AdvanceTime(2)
  assert(#SENT_MESSAGES == 2, "no ready message at 10:00")
  assert(SENT_MESSAGES[2].msg == "Lust is up!",
    "wrong text: " .. SENT_MESSAGES[2].msg)
  assert(#SCREEN_MESSAGES == 0 and #PLAYED_SOUNDS == 0,
    "ready beat must not create a local alert or sound")
end)

add("custom marks fire after the debuff drops: up-for 10/20/30s", function()
  SetGroup(true, false)
  RunSlash("/sated marks 10 20 30")
  assert(SatedDB.marks and SatedDB.marks[1] == 10, "marks not persisted")
  ApplyAura(57724, 600)
  AdvanceTime(635)  -- past ready (600) and all three marks (610/620/630)
  assert(#SENT_MESSAGES == 5,
    "expected cast + ready + 3 marks, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[3].msg == "Lust has been up for 0:10.",
    "first mark wrong: " .. SENT_MESSAGES[3].msg)
  assert(SENT_MESSAGES[5].msg == "Lust has been up for 0:30.",
    "third mark wrong: " .. SENT_MESSAGES[5].msg)
end)

add("default marks: up at 10:00, up-for 3/5/10 min after that", function()
  SetGroup(true, false)
  ApplyAura(57724, 600)
  AdvanceTime(1201)  -- through ready + 3/5/10-min up-marks (T+20:01)
  assert(#SENT_MESSAGES == 5,
    "expected cast + ready + 3 marks, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[2].msg == "Lust is up!",
    "ready message wrong: " .. SENT_MESSAGES[2].msg)
  assert(SENT_MESSAGES[3].msg == "Lust has been up for 3 min.",
    "3-min message wrong: " .. SENT_MESSAGES[3].msg)
  assert(SENT_MESSAGES[4].msg == "Lust has been up for 5 min.",
    "5-min message wrong: " .. SENT_MESSAGES[4].msg)
  assert(SENT_MESSAGES[5].msg == "Lust has been up for 10 min.",
    "10-min message wrong: " .. SENT_MESSAGES[5].msg)
end)

add("/reload mid-cooldown: ready + marks re-arm exactly once", function()
  SetGroup(true, false)
  SatedDB.marks = { 10, 20, 30 }
  SatedDB.lastLust = { at = GetTime() - 590, server = GetServerTime() - 590, mine = false }
  FireEvent("PLAYER_ENTERING_WORLD")  -- what WoW fires after a /reload
  AdvanceTime(25)  -- ready lands at +10, first mark at +20
  assert(#SENT_MESSAGES == 2,
    "expected ready + 10s mark, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[1].msg == "Lust is up!"
    and SENT_MESSAGES[2].msg == "Lust has been up for 0:10.",
    "wrong messages after reload")
end)

add("/reload after ready: passed ready/marks never refire", function()
  SetGroup(true, false)
  SatedDB.marks = { 10, 20, 30 }
  SatedDB.lastLust = { at = GetTime() - 615, server = GetServerTime() - 615, mine = false }
  FireEvent("PLAYER_ENTERING_WORLD")
  AdvanceTime(20)  -- 20s/30s up-marks still ahead; ready and 10s passed
  assert(#SENT_MESSAGES == 2,
    "expected exactly the 20s and 30s marks, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[1].msg == "Lust has been up for 0:20."
    and SENT_MESSAGES[2].msg == "Lust has been up for 0:30.",
    "wrong marks fired after reload")
end)

add("repeat PLAYER_ENTERING_WORLD (zone-in) never double-fires", function()
  SetGroup(true, false)
  RunSlash("/sated marks 10 20")
  ApplyAura(57724, 600)
  AdvanceTime(5)
  FireEvent("PLAYER_ENTERING_WORLD")
  FireEvent("PLAYER_ENTERING_WORLD")
  AdvanceTime(700)
  assert(#SENT_MESSAGES == 4,  -- cast + ready + both marks, once each
    "double-fired: got " .. #SENT_MESSAGES .. " messages")
end)

add("timer beats queue without local alerts during combat", function()
  SetGroup(true, false)
  RunSlash("/sated marks 10")
  ApplyAura(57724, 600)
  SetCombat(true)
  AdvanceTime(615)
  assert(#SENT_MESSAGES == 1, "party message sent during combat")
  assert(#SCREEN_MESSAGES == 0 and #PLAYED_SOUNDS == 0,
    "combat beats must not create local alerts")
  SetCombat(false)
  assert(#SENT_MESSAGES == 2
    and SENT_MESSAGES[2].msg == "Lust has been up for 0:15.",
    "newest queued beat did not flush after combat")
end)

add("/sated reset cancels pending messages and clears the window", function()
  SetGroup(true, false)
  RunSlash("/sated marks 10 20")
  ApplyAura(57724, 600)
  RunSlash("/sated reset")
  assert(SatedDB.lastLust == nil, "window not cleared")
  AdvanceTime(700)
  assert(#SENT_MESSAGES == 1, "cancelled messages still fired")
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("no lust recorded"), "status not reset")
end)

add("changing marks mid-window re-arms against the same window", function()
  SetGroup(true, false)
  RunSlash("/sated marks 100")
  ApplyAura(57724, 600)
  AdvanceTime(10)
  RunSlash("/sated marks 20 30")
  AdvanceTime(700)  -- 20s/30s marks + ready
  assert(#SENT_MESSAGES == 4,
    "re-armed messages wrong: " .. #SENT_MESSAGES)
  AdvanceTime(100)
  assert(#SENT_MESSAGES == 4, "old 100s mark should be cancelled")
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

add("instance groups still announce to PARTY, never INSTANCE_CHAT", function()
  SetGroup(false, true)
  CastSpell(80353)
  assert(#SENT_MESSAGES == 1 and SENT_MESSAGES[1].chatType == "PARTY",
    "expected PARTY announce, got " .. tostring(SENT_MESSAGES[1] and SENT_MESSAGES[1].chatType))
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

-- Sprint 7: beats anchored to the debuff falling off ------------------

add("chat gets 'Lust is up!' then up-for 3/5/10 min", function()
  SetGroup(true, false)
  CastSpell(2825)            -- SENT 1: cast announce
  AdvanceTime(601)           -- T+10:00 ready
  assert(#SENT_MESSAGES == 2, "no ready message")
  assert(SENT_MESSAGES[2].msg == "Lust is up!",
    "ready message wrong: " .. SENT_MESSAGES[2].msg)
  AdvanceTime(179)           -- T+13:00
  assert(SENT_MESSAGES[3] and SENT_MESSAGES[3].msg == "Lust has been up for 3 min.",
    "3-min message wrong: " .. tostring(SENT_MESSAGES[3] and SENT_MESSAGES[3].msg))
  AdvanceTime(120)           -- T+15:00
  assert(SENT_MESSAGES[4] and SENT_MESSAGES[4].msg == "Lust has been up for 5 min.",
    "5-min message wrong")
  AdvanceTime(300)           -- T+20:00
  assert(SENT_MESSAGES[5] and SENT_MESSAGES[5].msg == "Lust has been up for 10 min.",
    "10-min message wrong")
  assert(#SENT_MESSAGES == 5, "extra announces: " .. #SENT_MESSAGES)
end)

add("partner's lust gets the full chat pipeline in mode all", function()
  SetGroup(true, false)
  ApplyAura(57724, 600)
  AdvanceTime(1201)
  assert(#SENT_MESSAGES == 5, "expected 5 messages, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[2].msg == "Lust is up!", "second message not the ready beat")
  assert(SENT_MESSAGES[5].msg == "Lust has been up for 10 min.",
    "last message not the 10-min up-mark")
end)

add("ready queued in combat re-phrases from the live clock", function()
  SetGroup(true, false)
  CastSpell(2825)            -- SENT 1
  SetCombat(true)
  AdvanceTime(600)           -- ready fires mid-combat → queued
  AdvanceTime(130)
  SetCombat(false)
  assert(#SENT_MESSAGES == 2, "queue did not flush")
  assert(SENT_MESSAGES[2].msg == "Lust has been up for 2:10.",
    "not re-phrased live: " .. SENT_MESSAGES[2].msg)
end)

add("combat queue keeps only the newest beat (no message burst)", function()
  SetGroup(true, false)
  CastSpell(2825)            -- SENT 1
  SetCombat(true)
  AdvanceTime(790)           -- ready (600) and 3-min up-mark (780) both queue
  SetCombat(false)
  assert(#SENT_MESSAGES == 2,
    "expected one flushed message, got " .. (#SENT_MESSAGES - 1))
  assert(SENT_MESSAGES[2].msg == "Lust has been up for 3:10.",
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

-- Sprint 8: artificial resets (Proving Grounds etc.) ------------------

add("early debuff removal fires 'Lust is up' immediately", function()
  SatedDB.marks = {}
  SetGroup(true, false)
  local a = ApplyAura(57724, 600)
  AdvanceTime(60)
  RemoveAura(a)   -- Proving Grounds reset wipes the debuff at 1:00
  assert(#SENT_MESSAGES == 2, "no ready message on early removal")
  assert(SENT_MESSAGES[2].msg == "Lust is up!",
    "wrong message: " .. SENT_MESSAGES[2].msg)
  RunSlash("/sated")
  assert(PRINTED[#PRINTED]:find("lust is UP"), "status not up: " .. PRINTED[#PRINTED])
end)

add("marks re-anchor to the actual drop moment", function()
  SetGroup(true, false)
  RunSlash("/sated marks 10 20")
  local a = ApplyAura(57724, 600)
  AdvanceTime(60)
  RemoveAura(a)
  AdvanceTime(25)  -- marks land at drop+10 and drop+20
  assert(#SENT_MESSAGES == 4,
    "expected cast + ready + 2 marks, got " .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[3].msg == "Lust has been up for 0:10."
    and SENT_MESSAGES[4].msg == "Lust has been up for 0:20.",
    "marks not re-anchored to drop")
end)

add("chat announces the reset ready + re-anchored marks", function()
  SetGroup(true, false)
  CastSpell(2825)          -- SENT 1
  local a = ApplyAura(57724, 600)
  AdvanceTime(60)
  RemoveAura(a)
  assert(#SENT_MESSAGES == 2 and SENT_MESSAGES[2].msg == "Lust is up!",
    "no ready chat on reset")
  AdvanceTime(180)         -- default 3-min mark, anchored to the drop
  assert(#SENT_MESSAGES == 3 and SENT_MESSAGES[3].msg == "Lust has been up for 3 min.",
    "3-min mark not re-anchored: " .. tostring(SENT_MESSAGES[3] and SENT_MESSAGES[3].msg))
end)

add("natural expiry + removal event: ready fires exactly once", function()
  SatedDB.marks = {}
  SetGroup(true, false)
  local a = ApplyAura(57724, 600)
  AdvanceTime(601)         -- clock path fires ready
  assert(#SENT_MESSAGES == 2, "no natural ready")
  RemoveAura(a)            -- the removal event lands right after
  AdvanceTime(30)
  assert(#SENT_MESSAGES == 2, "ready double-fired: " .. #SENT_MESSAGES)
end)

add("removal just before the clock: once, and clock timer cancelled", function()
  SatedDB.marks = {}
  SetGroup(true, false)
  local a = ApplyAura(57724, 600)
  AdvanceTime(599)
  RemoveAura(a)            -- server removed it a hair early
  assert(#SENT_MESSAGES == 2, "no ready on removal")
  AdvanceTime(10)          -- the old 600s timer must not fire again
  assert(#SENT_MESSAGES == 2, "clock timer double-fired")
end)

add("secret removal ids still detected via bar rescan", function()
  SatedDB.marks = {}
  SetGroup(true, false)
  local a = ApplyAura(57724, 600)
  AdvanceTime(60)
  RemoveAura(a, { secretId = true })
  assert(#SENT_MESSAGES == 2 and SENT_MESSAGES[2].msg == "Lust is up!",
    "secret removal id broke reset detection")
end)

add("unrelated debuff removal does not end the window", function()
  SatedDB.marks = {}
  SetGroup(true, false)
  local lust = ApplyAura(57724, 600)
  local moonfire = ApplyAura(8921, 12)
  AdvanceTime(30)
  RemoveAura(moonfire)
  assert(#SENT_MESSAGES == 1, "unrelated removal ended the window")
  AdvanceTime(575)         -- natural ready still at 600
  assert(#SENT_MESSAGES == 2, "natural ready lost")
end)

add("re-lust after a reset starts a fresh cycle", function()
  SetGroup(true, false)
  RunSlash("/sated marks 30")
  local a = ApplyAura(57724, 600)
  AdvanceTime(60)
  RemoveAura(a)            -- reset; ready #1 fires
  AdvanceTime(5)
  local resetRecord = SatedDB.lastLust
  ApplyAura(57724, 600)    -- lust pressed again in Proving Grounds
  assert(SatedDB.lastLust ~= resetRecord, "re-lust not detected")
  AdvanceTime(700)         -- new ready at +600, new mark at +630
  assert(#SENT_MESSAGES == 5,
    "expected two casts, reset-ready, new ready, and new mark; got "
    .. #SENT_MESSAGES)
  assert(SENT_MESSAGES[4].msg == "Lust is up!"
    and SENT_MESSAGES[5].msg == "Lust has been up for 0:30.",
    "fresh cycle beats wrong")
end)

add("reload into a reset state fires ready on PLAYER_ENTERING_WORLD", function()
  SetGroup(true, false)
  -- SavedVariables restored: window opened 60s ago, debuff was seen, but
  -- the bar is empty now (reset happened around the loading screen).
  SatedDB.lastLust = { at = GetTime() - 60, server = GetServerTime() - 60,
    mine = false, debuffSeen = true }
  FireEvent("PLAYER_ENTERING_WORLD")
  assert(#SENT_MESSAGES == 1 and SENT_MESSAGES[1].msg == "Lust is up!",
    "reload-resync missed the reset")
  AdvanceTime(180)         -- default 3-min mark anchored to the resync
  assert(#SENT_MESSAGES == 2
    and SENT_MESSAGES[2].msg == "Lust has been up for 3 min.",
    "marks not anchored to resync drop")
end)

add("re-lust while up-for reminders are pending resets the cycle", function()
  SetGroup(true, false)
  ApplyAura(57724, 600)
  AdvanceTime(660)         -- natural ready fired at 600; the
                           -- 3/5/10-min reminders are pending
  assert(#SENT_MESSAGES == 2, "setup wrong")
  local firstRecord = SatedDB.lastLust
  ApplyAura(57724, 600)    -- lust popped again at T+11:00
  assert(SatedDB.lastLust ~= firstRecord, "re-lust not detected")
  AdvanceTime(300)         -- old 3-min (T+13:00) and 5-min (T+15:00)
                           -- reminders would land in here — must not
  assert(#SENT_MESSAGES == 3, "old reminders fired after re-lust: got "
    .. #SENT_MESSAGES)
  AdvanceTime(350)         -- past the new cycle's ready at 660+600 = T+21:00
  assert(#SENT_MESSAGES == 4 and SENT_MESSAGES[4].msg == "Lust is up!",
    "new cycle ready missing")
  AdvanceTime(180)         -- new cycle's own 3-min reminder
  assert(#SENT_MESSAGES == 5
    and SENT_MESSAGES[5].msg == "Lust has been up for 3 min.",
    "new cycle reminders missing")
end)

add("cast-only window (debuff never seen) trusts the clock, not absence", function()
  SatedDB.marks = {}
  CastSpell(2825)          -- window opens; no debuff ever observed
  AdvanceTime(60)
  FireEvent("UNIT_AURA", "player", { removedAuraInstanceIDs = { 4242 } })
  assert(not SatedDB.lastLust.readyFired,
    "absence treated as drop without debuffSeen")
  AdvanceTime(545)         -- natural clock ready at 600
  assert(SatedDB.lastLust.readyFired, "clock fallback ready missing")
end)
