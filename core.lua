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

-- ---------------------------------------------------------------------------
-- Lust window state. The record persists in SatedDB.lastLust:
--   { at = GetTime(), server = GetServerTime(), mine = boolean }
-- Elapsed time is always computed from the server timestamp so it survives
-- /reload (GetTime alone does not).
-- ---------------------------------------------------------------------------
local function elapsed()
  local last = Sated.db and Sated.db.lastLust
  if not last or not last.server then return nil end
  local e = GetServerTime() - last.server
  if e < 0 then return nil end
  return e
end
Sated.Elapsed = elapsed

local function windowActive()
  local e = elapsed()
  return e ~= nil and e < Sated.SATED_DURATION
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
  return date("%H:%M", record.server + Sated.SATED_DURATION)
end

-- ---------------------------------------------------------------------------
-- Alerts: a dedicated message frame (RaidNotice-style) + sound. Pure local
-- display — no chat, no comms — so it is unrestricted in combat.
-- ---------------------------------------------------------------------------
local msgFrame = CreateFrame("MessageFrame", "SatedMessageFrame", UIParent)
msgFrame:SetPoint("TOP", UIParent, "TOP", 0, -220)
msgFrame:SetSize(600, 60)
msgFrame:SetFrameStrata("HIGH")
msgFrame:SetFontObject(GameFontNormalHuge)
msgFrame:SetInsertMode("TOP")
msgFrame:SetTimeVisible(4)
msgFrame:SetFadeDuration(1)
Sated.msgFrame = msgFrame

local ALERT_SOUND = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959

local function alert(text)
  msgFrame:AddMessage(text)
  if Sated.db == nil or Sated.db.sound ~= false then  -- default: on
    PlaySound(ALERT_SOUND)
  end
end

-- Fires the moment the Sated debuff expires: lust is castable again.
local function fireReady()
  Sated.DebugLog("ready")
  alert("|cff33ff99Lust is up!|r")
  if Sated.OnLustReady then Sated.OnLustReady(Sated.db and Sated.db.lastLust) end
end

-- Fires at each mark, counted from lust USE. Before the cooldown ends the
-- alert is a countdown ("Lust back in 7 min"); marks set past the cooldown
-- read as up-time ("Lust has been up for 3 min").
local function fireMark(mark)
  Sated.DebugLog("mark", fmtDur(mark))
  local dur = Sated.SATED_DURATION
  if mark < dur then
    alert(string.format("|cffff4444Lust back in %s|r", fmtDur(dur - mark)))
  else
    alert(string.format("|cff33ff99Lust has been up for %s|r", fmtDur(mark - dur)))
  end
  if Sated.OnLustMark then
    Sated.OnLustMark(Sated.db and Sated.db.lastLust, mark)
  end
end

-- ---------------------------------------------------------------------------
-- Timer engine. Marks are seconds-after-lust; on window open (or /reload
-- mid-window via PLAYER_ENTERING_WORLD) we schedule only the marks still in
-- the future, computed from the persisted server timestamp — already-passed
-- marks never double-fire.
-- ---------------------------------------------------------------------------
local activeTimers = {}

local function cancelTimers()
  for _, t in ipairs(activeTimers) do t:Cancel() end
  wipe(activeTimers)
end

local function armTimers()
  cancelTimers()
  local e = elapsed()
  if e == nil then return end
  local ready = Sated.SATED_DURATION
  -- "Lust is up" the moment the cooldown (Sated debuff) ends...
  if ready - e > 0 then
    table.insert(activeTimers, C_Timer.NewTimer(ready - e, fireReady))
  end
  -- ...plus marks counted from lust use (default 3/5/10 min). A mark equal
  -- to the cooldown itself is skipped — the ready alert IS that moment.
  local marks = (Sated.db and Sated.db.marks) or Sated.DEFAULT_MARKS
  for _, mark in ipairs(marks) do
    local remaining = mark - e
    if mark ~= ready and remaining > 0 then
      local t = C_Timer.NewTimer(remaining, function() fireMark(mark) end)
      table.insert(activeTimers, t)
    end
  end
end
Sated.ArmTimers = armTimers

local function openWindow(mine)
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
  Sated.db.lastLust = { at = GetTime(), server = GetServerTime(), mine = mine or false }
  Sated.DebugLog("detect", mine and "mine" or "party")
  print("|cff33ff99Sated|r: Lust detected — timers armed.")
  armTimers()
  if Sated.OnWindowOpened then Sated.OnWindowOpened(Sated.db.lastLust) end
end

-- ---------------------------------------------------------------------------
-- Detection. Local-first: the timer engine keys off the player's OWN
-- Sated-family debuff (every party member gets it the moment lust is
-- popped), so the addon works solo-installed. The cast path only tags the
-- window as ours to feed the announce layer.
-- ---------------------------------------------------------------------------
local function auraMatches(aura)
  if not aura then return false end
  local spellId = Guard(aura.spellId, "aura.spellId")
  return spellId ~= nil and Sated.SATED_DEBUFFS[spellId] == true
end

local function scanAllAuras()
  for i = 1, 40 do
    local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
    if not aura then break end
    if auraMatches(aura) then return true end
  end
  return false
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
  if SatedDB.schema ~= 2 then
    -- v2: marks are now seconds-since-lust-use and announce is a mode
    -- string. Wipe stale settings (including leftover test marks) so old
    -- saved values can't fire at wrong times.
    SatedDB.marks = nil
    SatedDB.announce = nil
    SatedDB.announceMode = nil
    SatedDB.schema = 2
  end
  Sated.db = SatedDB
  frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_ENTERING_WORLD()
  -- Fires after login/reload/zone-in. Re-arm whatever marks are still ahead
  -- of us; armTimers cancels first, so this is idempotent.
  armTimers()
  if Sated.OnZoneChanged then Sated.OnZoneChanged() end
end

function handlers.UNIT_AURA(unit, updateInfo)
  if unit ~= "player" then return end
  if windowActive() then return end
  -- Decide between the incremental payload and a whole-bar rescan. A secret
  -- isFullUpdate flag counts as a full update: the rescan is the safe path,
  -- and issecretvalue is the only operation permitted on a secret.
  local useIncremental = false
  if updateInfo and updateInfo.addedAuras then
    local rawFull = updateInfo.isFullUpdate
    if issecret(rawFull) then
      Sated.DebugLog("secret", "updateInfo.isFullUpdate")
    elseif not rawFull then
      useIncremental = true
    end
  end
  local found
  if useIncremental then
    for _, aura in ipairs(updateInfo.addedAuras) do
      if auraMatches(aura) then found = true; break end
    end
  else
    found = scanAllAuras()
  end
  if found then openWindow(false) end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellId)
  if unit ~= "player" and unit ~= "pet" then return end
  local id = Guard(spellId, "cast.spellId")
  if id ~= nil and Sated.LUST_CASTS[id] then
    openWindow(true)
  end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
  local e = elapsed()
  if e == nil then
    print("|cff33ff99Sated|r loaded, no lust recorded.")
    return
  end
  local who = (Sated.db.lastLust.mine and " (yours)") or ""
  if e < Sated.SATED_DURATION then
    print(string.format(
      "|cff33ff99Sated|r: last lust %s ago%s — back up in %s (around %s).",
      fmtClock(e), who, fmtClock(Sated.SATED_DURATION - e),
      Sated.BackTime(Sated.db.lastLust)))
  else
    print(string.format(
      "|cff33ff99Sated|r: lust is UP — has been up for %s (last used %s ago%s).",
      fmtClock(e - Sated.SATED_DURATION), fmtClock(e), who))
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
  if windowActive() then armTimers() end
end

function commands.sound(rest)
  rest = (rest or ""):lower()
  if rest == "on" then
    Sated.db.sound = true
  elseif rest == "off" then
    Sated.db.sound = false
  else
    print("|cff33ff99Sated|r: usage: /sated sound on|off")
    return
  end
  print("|cff33ff99Sated|r: sound " .. rest .. ".")
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
