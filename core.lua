-- Sated core: secret-value guard, detection engine, slash commands.
local ADDON_NAME, Sated = ...

-- ---------------------------------------------------------------------------
-- Guard: every value read from combat-adjacent APIs passes through here
-- before any comparison or arithmetic. In Midnight (12.0+) some API returns
-- are "secret" inside instanced content — comparing them raises a lua error.
-- Guard returns nil for secret or missing values so callers can degrade to
-- "feature silently unavailable" instead of erroring.
-- ---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

function Sated.Guard(v)
  if v == nil then return nil end
  if issecret(v) then return nil end
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

local function openWindow(mine)
  if windowActive() then
    -- Re-detection inside an active window: only upgrade the mine flag
    -- (cast event and debuff event both fire for our own lust).
    if mine then Sated.db.lastLust.mine = true end
    return
  end
  Sated.db.lastLust = { at = GetTime(), server = GetServerTime(), mine = mine or false }
  print("|cff33ff99Sated|r: Lust detected — timers armed.")
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
  local spellId = Guard(aura.spellId)
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
  Sated.db = SatedDB
  frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.UNIT_AURA(unit, updateInfo)
  if unit ~= "player" then return end
  if windowActive() then return end
  local found
  if updateInfo and updateInfo.addedAuras and not updateInfo.isFullUpdate then
    for _, aura in ipairs(updateInfo.addedAuras) do
      if auraMatches(aura) then found = true; break end
    end
  else
    -- Full update (or a client without the incremental payload): rescan.
    found = scanAllAuras()
  end
  if found then openWindow(false) end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellId)
  if unit ~= "player" and unit ~= "pet" then return end
  local id = Guard(spellId)
  if id ~= nil and Sated.LUST_CASTS[id] then
    openWindow(true)
  end
end

frame:RegisterEvent("ADDON_LOADED")
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
  else
    local who = (Sated.db.lastLust.mine and " (yours)") or ""
    print(string.format("|cff33ff99Sated|r: last lust %s ago%s.", fmtClock(e), who))
  end
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
