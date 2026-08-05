-- Sated core: secret-value guard, detection engine, timer marks, slash commands.
local ADDON_NAME, Sated = ...

-- ---------------------------------------------------------------------------
-- Guard: every value read from combat-adjacent APIs passes through here
-- before any comparison or arithmetic. In Midnight (12.0+) some API returns
-- are "secret" inside instanced content — comparing them raises a lua error.
-- Guard returns nil for secret or missing values so callers can degrade to
-- "feature silently unavailable" instead of erroring.
-- ---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

-- Debug ring buffer: last 20 events (detections, secrets encountered,
-- marks, queue actions) for patch-day diagnosis via /sated debug.
-- In-memory only; never stores secret contents, only where one was met.
local debugLog = {}
local DEBUG_MAX = 20

function Sated.DebugLog(kind, detail)
  local entry = string.format("[%s] %s%s", date("%H:%M:%S"), kind,
    detail and (" — " .. detail) or "")
  table.insert(debugLog, entry)
  if #debugLog > DEBUG_MAX then table.remove(debugLog, 1) end
end

function Sated.Guard(v, ctx)
  if v == nil then return nil end
  if issecret(v) then
    Sated.DebugLog("secret", ctx or "unlabeled read")
    return nil
  end
  return v
end
local Guard = Sated.Guard

local MYTHIC_KEYSTONE_DIFFICULTY_ID = 8

local function enabledHere()
  if Sated.db and Sated.db.testMode then return true end
  local difficultyID = Guard(select(3, GetInstanceInfo()),
    "instance.difficultyID")
  return difficultyID == MYTHIC_KEYSTONE_DIFFICULTY_ID
end
Sated.EnabledHere = enabledHere

-- ---------------------------------------------------------------------------
-- Lust window state, persisted in SatedDB.lastLust:
--   at         GetTime() at lust use
--   server     GetServerTime() at lust use
--   mine       true if we (or our pet) cast it
--   debuffSeen true once the Sated debuff was actually observed on our bar
--   readyServer server timestamp lust became pressable again (set when the
--              debuff really falls off — naturally OR via an artificial
--              reset like Proving Grounds; defaults to use + 10 min)
--   readyFired true once the "Lust is up" beat has fired
-- Elapsed values are always computed from server timestamps so they
-- survive /reload (GetTime alone does not).
-- ---------------------------------------------------------------------------
local function readyAtServer(record)
  return record.readyServer or (record.server + Sated.SATED_DURATION)
end

local function elapsed()
  local last = Sated.db and Sated.db.lastLust
  if not last or not last.server then return nil end
  local e = GetServerTime() - last.server
  if e < 0 then return nil end
  return e
end
Sated.Elapsed = elapsed

-- Seconds lust has been pressable again, or nil while still on cooldown.
function Sated.UpFor()
  local record = Sated.db and Sated.db.lastLust
  if not record or not record.server then return nil end
  local now = GetServerTime()
  if record.readyFired or now >= readyAtServer(record) then
    local up = now - readyAtServer(record)
    if up < 0 then up = 0 end
    return up
  end
  return nil
end

-- The window is "active" while the debuff is (believed) still on us.
local function windowActive()
  local record = Sated.db and Sated.db.lastLust
  if not record or not record.server then return false end
  if record.readyFired then return false end
  return GetServerTime() < readyAtServer(record)
end
Sated.WindowActive = windowActive

local function fmtClock(seconds)
  local m = math.floor(seconds / 60)
  local s = math.floor(seconds % 60)
  return string.format("%d:%02d", m, s)
end
Sated.FmtClock = fmtClock

-- "3 min" for whole minutes, "3:12" otherwise — reads better in chat.
local function fmtDur(seconds)
  if seconds >= 60 and seconds % 60 == 0 then
    return string.format("%d min", seconds / 60)
  end
  return fmtClock(seconds)
end
Sated.FmtDur = fmtDur

-- Wall-clock time lust comes (or came) back up, e.g. "14:32".
function Sated.BackTime(record)
  return date("%H:%M", readyAtServer(record))
end

-- Fires once per window, the moment lust is pressable again — whether the
-- debuff expired naturally or was wiped by a reset (Proving Grounds etc).
local function fireReady()
  if not enabledHere() then return end
  local record = Sated.db and Sated.db.lastLust
  if not record or record.readyFired then return end
  record.readyFired = true
  record.readyServer = record.readyServer or GetServerTime()
  Sated.DebugLog("ready")
  if Sated.OnLustReady then Sated.OnLustReady(record) end
end

-- Fires at each mark, counted from the moment the debuff fell off — i.e.
-- how long lust has been sitting available.
local function fireMark(mark)
  if not enabledHere() then return end
  Sated.DebugLog("mark", fmtDur(mark))
  if Sated.OnLustMark then
    Sated.OnLustMark(Sated.db and Sated.db.lastLust, mark)
  end
end

-- ---------------------------------------------------------------------------
-- Timer engine. Everything is anchored to the READY moment (readyAtServer):
-- the ready beat itself, then marks at ready + 3/5/10 min (defaults). When
-- the debuff drops early, timers re-arm against the new anchor; on /reload
-- remaining beats are recomputed from persisted timestamps — already-passed
-- beats never double-fire.
-- ---------------------------------------------------------------------------
local activeTimers = {}

local function cancelTimers()
  for _, t in ipairs(activeTimers) do t:Cancel() end
  wipe(activeTimers)
end

local function armTimers()
  cancelTimers()
  if not enabledHere() then return end
  local record = Sated.db and Sated.db.lastLust
  if not record or not record.server then return end
  local readyIn = readyAtServer(record) - GetServerTime()
  if not record.readyFired and readyIn > 0 then
    table.insert(activeTimers, C_Timer.NewTimer(readyIn, fireReady))
  end
  local marks = (Sated.db and Sated.db.marks) or Sated.DEFAULT_MARKS
  for _, mark in ipairs(marks) do
    local remaining = readyIn + mark
    if remaining > 0 then
      local t = C_Timer.NewTimer(remaining, function() fireMark(mark) end)
      table.insert(activeTimers, t)
    end
  end
end
Sated.ArmTimers = armTimers

local function clearTracking()
  cancelTimers()
  if Sated.db then Sated.db.lastLust = nil end
  if Sated.OnZoneChanged then Sated.OnZoneChanged() end
end

-- The debuff actually left our bar before its natural end (artificial
-- reset: Proving Grounds, M+ start, arena gates...). Lust is up NOW —
-- re-anchor everything to this moment.
local function onDebuffDropped(record)
  if record.readyFired then return end
  Sated.DebugLog("dropped", "debuff removed before natural expiry")
  record.readyServer = GetServerTime()
  armTimers()
  fireReady()
end

local function openWindow(mine, sawDebuff)
  if not enabledHere() then return end
  if windowActive() then
    -- Re-detection inside an active window: only upgrade the mine flag
    -- (cast event and debuff event both fire for our own lust, in either
    -- order — the announce layer needs to hear about the upgrade).
    if mine and not Sated.db.lastLust.mine then
      Sated.db.lastLust.mine = true
      if Sated.OnWindowOpened then Sated.OnWindowOpened(Sated.db.lastLust) end
    end
    return
  end
  Sated.db.lastLust = {
    at = GetTime(),
    server = GetServerTime(),
    mine = mine or false,
    debuffSeen = sawDebuff or false,
  }
  Sated.DebugLog("detect", mine and "mine" or "party")
  armTimers()
  if Sated.OnWindowOpened then Sated.OnWindowOpened(Sated.db.lastLust) end
end

-- ---------------------------------------------------------------------------
-- Detection. Local-first: the timer engine keys off the player's OWN
-- Sated-family debuff (every party member gets it the moment lust is
-- popped), so the addon works solo-installed. The cast path only tags the
-- window as ours to feed the announce layer. While a window is active we
-- also watch for the debuff LEAVING the bar, which is what actually means
-- "lust is up" — including artificial resets.
-- ---------------------------------------------------------------------------
local function auraMatches(aura)
  if not aura then return false end
  local spellId = Guard(aura.spellId, "aura.spellId")
  return spellId ~= nil and Sated.SATED_DEBUFFS[spellId] == true
end

local function scanForSated()
  for i = 1, 40 do
    local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
    if not aura then break end
    if auraMatches(aura) then return aura end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Event frame
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "SatedEventFrame")
Sated.frame = frame

local handlers = {}
Sated.handlers = handlers  -- later files (announce.lua) extend this table

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  SatedDB = SatedDB or {}
  if SatedDB.schema ~= 3 then
    -- v3: marks are seconds AFTER the Sated debuff falls off (lust ready).
    -- Wipe stale marks from older semantics so saved values can't fire at
    -- wrong times; announceMode (v2+) keeps its meaning.
    SatedDB.marks = nil
    SatedDB.announce = nil
    SatedDB.schema = 3
  end
  Sated.db = SatedDB
  frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_ENTERING_WORLD()
  -- Fires after login/reload/zone-in. If the window claims the debuff is
  -- still on us but the bar disagrees (reset happened during a loading
  -- screen, or we reloaded after one), treat it as dropped. Otherwise
  -- re-arm whatever beats are still ahead; armTimers cancels first, so
  -- this is idempotent.
  if not enabledHere() then
    clearTracking()
    Sated.DebugLog("scope", "inactive outside Mythic+")
    return
  end
  if Sated.OnZoneChanged then Sated.OnZoneChanged() end
  local record = Sated.db and Sated.db.lastLust
  if record and windowActive() and record.debuffSeen and not scanForSated() then
    onDebuffDropped(record)
  else
    armTimers()
  end
end

function handlers.CHALLENGE_MODE_START()
  handlers.PLAYER_ENTERING_WORLD()
end

function handlers.UNIT_AURA(unit, updateInfo)
  if unit ~= "player" then return end
  if not enabledHere() then return end

  -- Classify the payload. A secret isFullUpdate flag counts as a full
  -- update: the rescan is the safe path, and issecretvalue is the only
  -- operation permitted on a secret.
  local full
  if updateInfo == nil then
    full = true
  else
    local rawFull = updateInfo.isFullUpdate
    if issecret(rawFull) then
      Sated.DebugLog("secret", "updateInfo.isFullUpdate")
      full = true
    else
      full = rawFull and true or false
    end
  end

  if windowActive() then
    -- Active window: watch for the debuff dropping (naturally or via an
    -- artificial reset). Only re-check the bar when something was removed
    -- or on a full update; and only trust "absent" as a drop if we have
    -- actually seen the debuff on the bar before (a cast-opened window in
    -- fully-secret content never observes it — degrade to the clock).
    local record = Sated.db.lastLust
    local removed = (not full) and updateInfo.removedAuraInstanceIDs or nil
    if full or (removed and #removed > 0) then
      if scanForSated() then
        record.debuffSeen = true
      elseif record.debuffSeen then
        onDebuffDropped(record)
      end
    elseif not record.debuffSeen and updateInfo.addedAuras then
      for _, aura in ipairs(updateInfo.addedAuras) do
        if auraMatches(aura) then record.debuffSeen = true; break end
      end
    end
    return
  end

  -- No active window: look for a fresh Sated-family debuff.
  local found = false
  if full then
    found = scanForSated() ~= nil
  elseif updateInfo.addedAuras then
    for _, aura in ipairs(updateInfo.addedAuras) do
      if auraMatches(aura) then found = true; break end
    end
  end
  if found then openWindow(false, true) end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellId)
  if unit ~= "player" and unit ~= "pet" then return end
  if not enabledHere() then return end
  local id = Guard(spellId, "cast.spellId")
  if id ~= nil and Sated.LUST_CASTS[id] then
    openWindow(true, false)
  end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
frame:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then h(...) end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local commands = {}
Sated.commands = commands

function commands.status()
  if not enabledHere() then
    print("|cff33ff99Sated|r: inactive outside Mythic+; use /sated test to enable test mode.")
    return
  end
  local e = elapsed()
  if e == nil then
    print("|cff33ff99Sated|r loaded, no lust recorded.")
    return
  end
  local record = Sated.db.lastLust
  local who = (record.mine and " (yours)") or ""
  local up = Sated.UpFor()
  if up == nil then
    print(string.format(
      "|cff33ff99Sated|r: last lust %s ago%s — back up in %s (around %s).",
      fmtClock(e), who, fmtClock(readyAtServer(record) - GetServerTime()),
      Sated.BackTime(record)))
  else
    print(string.format(
      "|cff33ff99Sated|r: lust is UP — has been up for %s (last used %s ago%s).",
      fmtClock(up), fmtClock(e), who))
  end
end

function commands.test(rest)
  rest = (rest or ""):lower():match("^%s*(.-)%s*$")
  local enable
  if rest == "" or rest == "on" then
    enable = true
  elseif rest == "off" then
    enable = false
  else
    print("|cff33ff99Sated|r: usage: /sated test [on|off]")
    return
  end

  local wasEnabled = enabledHere()
  Sated.db.testMode = enable and true or nil
  local nowEnabled = enabledHere()

  if not wasEnabled and nowEnabled then
    clearTracking()
    local aura = scanForSated()
    if aura then openWindow(false, true) end
  elseif wasEnabled and not nowEnabled then
    clearTracking()
  end

  if enable then
    print("|cff33ff99Sated|r: test mode ON — addon works anywhere.")
  else
    print("|cff33ff99Sated|r: test mode OFF — Mythic+ only.")
  end
end

function commands.marks(rest)
  local newMarks = {}
  for word in rest:gmatch("%S+") do
    local n = tonumber(word)
    if not n or n <= 0 then
      print("|cff33ff99Sated|r: usage: /sated marks <seconds> <seconds> ...")
      return
    end
    table.insert(newMarks, math.floor(n))
  end
  if #newMarks == 0 then
    print("|cff33ff99Sated|r: usage: /sated marks <seconds> <seconds> ...")
    return
  end
  table.sort(newMarks)
  Sated.db.marks = newMarks
  local parts = {}
  for _, m in ipairs(newMarks) do parts[#parts + 1] = fmtClock(m) end
  print("|cff33ff99Sated|r: marks set to " .. table.concat(parts, ", ") .. ".")
  if Sated.db.lastLust then armTimers() end
end

function commands.reset()
  cancelTimers()
  Sated.db.lastLust = nil
  Sated.DebugLog("reset")
  print("|cff33ff99Sated|r: reset — lust window cleared.")
end

function commands.debug()
  if #debugLog == 0 then
    print("|cff33ff99Sated|r: debug buffer empty.")
    return
  end
  print("|cff33ff99Sated|r debug (last " .. #debugLog .. " events):")
  for _, line in ipairs(debugLog) do print("  " .. line) end
end

SLASH_SATED1 = "/sated"
SlashCmdList.SATED = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local fn = commands[cmd]
  if cmd ~= "" and fn then
    fn(rest)
  else
    commands.status()
  end
end
