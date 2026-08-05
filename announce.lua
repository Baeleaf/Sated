-- Sated announce layer: sends timer beats to party chat — a post-combat
-- cast summary, "Lust is up!" at cooldown end, and up-time marks after that.
--
-- Modes (/sated announce):
--   all    (default) announce every detected lust window, whoever cast it
--   caster announce only lust WE cast — use when several party members run
--          Sated, so the group gets one message instead of five
--   off    never chat
--
-- Cast detection is always silent. Casts detected during combat or an active
-- encounter queue one elapsed-time summary. Ready/mark beats also queue. The
-- queue holds the newest pending event and flushes on PLAYER_REGEN_ENABLED /
-- ENCOUNTER_END; a reload or zone change drops it silently. Flushed messages
-- use the live clock.
local _, Sated = ...

local queue = nil            -- { record, key } — newest pending event only
local encounterActive = false

local function announceMode()
  local m = Sated.db and Sated.db.announceMode
  if m == "caster" or m == "off" then return m end
  return "all"
end

local function channel()
  -- Always PARTY, never INSTANCE_CHAT — Jess wants the warnings in party
  -- chat specifically, even inside queued/instance groups.
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
local function phrase()
  local up = Sated.UpFor()
  if up == nil or up < 3 then return "Lust is up!" end
  return string.format("Lust has been up for %s.", Sated.FmtDur(up))
end

local function queuedCastPhrase()
  local elapsedSeconds = math.floor(math.max(0, Sated.Elapsed() or 0))
  local elapsedMinutes = math.floor(elapsedSeconds / 60)
  local remainingSeconds = elapsedSeconds % 60
  if elapsedMinutes < 1 then
    return string.format("Lust was used %d secs ago", remainingSeconds)
  end
  return string.format(
    "Lust was used %d mins and %d secs ago",
    elapsedMinutes, remainingSeconds)
end

local function send(record, key)
  local chan = channel()
  if not chan then return end  -- group dissolved while queued; drop
  local message = key == "cast" and queuedCastPhrase()
    or phrase()
  SendChatMessage(message, chan)
  record.announcedKeys = record.announcedKeys or {}
  record.announcedKeys[key] = true
  Sated.DebugLog("announce", key .. " → " .. chan)
end

-- Route an announce event: dedup per (window, key), then send or queue.
local function request(record, key)
  if not record then return end
  if not Sated.EnabledHere() then return end
  local mode = announceMode()
  if mode == "off" then return end
  if mode == "caster" and not record.mine then return end
  if record.announcedKeys and record.announcedKeys[key] then return end
  if not IsInGroup() then return end
  if combatLocked() then
    local castSummaryPending = queue and queue.record == record
      and queue.key == "cast" and key ~= "cast"
    if not castSummaryPending then
      queue = { record = record, key = key }
      Sated.DebugLog("queue", key .. " held for combat/encounter end")
    end
  elseif key ~= "cast" then
    send(record, key)
  end
end

local function flush()
  if not queue then return end
  if not Sated.EnabledHere() then
    queue = nil
    return
  end
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
