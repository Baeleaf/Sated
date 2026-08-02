-- Sated announce layer. Caster-only: fires only when WE cast a lust spell,
-- so five party members with the addon still produce exactly one message.
-- Addon chat is locked during active encounters/M+ combat but permitted
-- before/after — announce immediately when clear, otherwise queue and flush
-- on PLAYER_REGEN_ENABLED / ENCOUNTER_END. The queue is in-memory only: a
-- reload or zone change drops it silently (stale info by then).
local _, Sated = ...

local queue = nil            -- at most one pending record per window
local encounterActive = false

local function announceEnabled()
  return Sated.db == nil or Sated.db.announce ~= false  -- default: on
end

local function channel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInGroup() then return "PARTY" end
  return nil  -- solo: never announce
end

local function combatLocked()
  return InCombatLockdown() or UnitAffectingCombat("player") or encounterActive
end

local function backTime(record)
  return date("%H:%M", record.server + Sated.SATED_DURATION)
end

local function send(record)
  local chan = channel()
  if not chan then return end  -- group dissolved while queued; drop
  local e = Sated.Elapsed() or 0
  local msg
  if e < 3 then
    msg = string.format("Lust used — back around %s.", backTime(record))
  else
    msg = string.format("Lust was used %s ago — back around %s.",
      Sated.FmtClock(e), backTime(record))
  end
  SendChatMessage(msg, chan)
  record.announced = true
  Sated.DebugLog("announce", chan)
end

local function flush()
  if not queue then return end
  if combatLocked() then return end  -- e.g. regen mid-encounter: keep waiting
  local record = queue
  queue = nil
  -- Only announce if this is still the live, unannounced window.
  if not Sated.db or record ~= Sated.db.lastLust then return end
  if not Sated.WindowActive() then return end
  if record.announced then return end
  if not announceEnabled() then return end
  send(record)
end

-- Called by core when a window opens, or when an active window is upgraded
-- to mine=true (cast and debuff events arrive in either order).
function Sated.OnWindowOpened(record)
  if not record.mine then return end
  if record.announced then return end
  if not announceEnabled() then return end
  if not IsInGroup() then return end
  if combatLocked() then
    queue = record
    Sated.DebugLog("queue", "announce held for combat/encounter end")
  else
    send(record)
  end
end

function Sated.OnZoneChanged()
  if queue then Sated.DebugLog("drop", "queued announce stale on zone change") end
  queue = nil  -- run is over or world changed; a queued announce is stale
end

-- Event wiring: extend core's handler table and frame registrations.
function Sated.handlers.PLAYER_REGEN_ENABLED()
  flush()
end

function Sated.handlers.ENCOUNTER_START()
  encounterActive = true
end

function Sated.handlers.ENCOUNTER_END()
  encounterActive = false
  flush()
end

Sated.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
Sated.frame:RegisterEvent("ENCOUNTER_START")
Sated.frame:RegisterEvent("ENCOUNTER_END")

-- /sated announce on|off
function Sated.commands.announce(rest)
  rest = (rest or ""):lower()
  if rest == "on" then
    Sated.db.announce = true
  elseif rest == "off" then
    Sated.db.announce = false
    queue = nil
  else
    print("|cff33ff99Sated|r: usage: /sated announce on|off")
    return
  end
  print("|cff33ff99Sated|r: announce " .. rest .. ".")
end
