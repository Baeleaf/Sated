-- Sated announce layer: mirrors the on-screen beats into party/instance
-- chat — the cast, countdown marks (3/5 min), "Lust is up." at the
-- 10-minute cooldown end, and any up-time marks after that.
--
-- Modes (/sated announce):
--   all    (default) announce every detected lust window, whoever cast it
--   caster announce only lust WE cast — use when several party members run
--          Sated, so the group gets one message instead of five
--   off    never chat
--
-- Addon chat is locked during active encounters/M+ combat but permitted
-- before/after — announce immediately when clear, otherwise queue and flush
-- on PLAYER_REGEN_ENABLED / ENCOUNTER_END. The queue holds only the newest
-- pending event and is in-memory only: a reload or zone change drops it
-- silently (stale info by then). Flushed messages are re-phrased from the
-- clock at send time, never from when they were queued.
local _, Sated = ...

local queue = nil            -- { record, key } — newest pending event only
local encounterActive = false

local function announceMode()
  local m = Sated.db and Sated.db.announceMode
  if m == "caster" or m == "off" then return m end
  return "all"
end

local function channel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInGroup() then return "PARTY" end
  return nil  -- solo: chat has nowhere to go
end

local function combatLocked()
  return InCombatLockdown() or UnitAffectingCombat("player") or encounterActive
end

-- One phrasing function for every announce, computed from the current
-- clock so queued messages never report stale numbers. UpFor() is anchored
-- to the debuff actually leaving the bar, so artificial resets (Proving
-- Grounds etc.) phrase correctly too.
local function phrase(record, key)
  local up = Sated.UpFor()
  if up ~= nil then
    if up < 3 then return "Lust is up." end
    return string.format("Lust has been up for %s.", Sated.FmtDur(up))
  end
  local e = Sated.Elapsed() or 0
  if key == "cast" and e < 3 then
    return string.format("Lust used — back around %s.", Sated.BackTime(record))
  end
  return string.format("Lust was used %s ago — back around %s.",
    Sated.FmtClock(e), Sated.BackTime(record))
end

local function send(record, key)
  local chan = channel()
  if not chan then return end  -- group dissolved while queued; drop
  SendChatMessage(phrase(record, key), chan)
  record.announcedKeys = record.announcedKeys or {}
  record.announcedKeys[key] = true
  Sated.DebugLog("announce", key .. " → " .. chan)
end

-- Route an announce event: dedup per (window, key), then send or queue.
local function request(record, key)
  if not record then return end
  local mode = announceMode()
  if mode == "off" then return end
  if mode == "caster" and not record.mine then return end
  if record.announcedKeys and record.announcedKeys[key] then return end
  if not IsInGroup() then return end
  if combatLocked() then
    queue = { record = record, key = key }
    Sated.DebugLog("queue", key .. " held for combat/encounter end")
  else
    send(record, key)
  end
end

local function flush()
  if not queue then return end
  if combatLocked() then return end  -- e.g. regen mid-encounter: keep waiting
  local record, key = queue.record, queue.key
  queue = nil
  -- Only announce if this is still the live window and event.
  if not Sated.db or record ~= Sated.db.lastLust then return end
  if record.announcedKeys and record.announcedKeys[key] then return end
  if announceMode() == "off" then return end
  send(record, key)
end

-- Hooks called by core ------------------------------------------------

function Sated.OnWindowOpened(record)
  request(record, "cast")
end

function Sated.OnLustReady(record)
  request(record, "ready")
end

function Sated.OnLustMark(record, mark)
  request(record, "mark" .. tostring(mark))
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

-- /sated announce all|caster|off  (on = all, for muscle memory)
function Sated.commands.announce(rest)
  rest = (rest or ""):lower()
  if rest == "all" or rest == "on" then
    Sated.db.announceMode = "all"
  elseif rest == "caster" then
    Sated.db.announceMode = "caster"
  elseif rest == "off" then
    Sated.db.announceMode = "off"
    queue = nil
  else
    print("|cff33ff99Sated|r: usage: /sated announce all|caster|off")
    return
  end
  print("|cff33ff99Sated|r: announce " .. Sated.db.announceMode .. ".")
end
