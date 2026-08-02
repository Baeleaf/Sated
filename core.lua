-- Sated core: event wiring, secret-value guard, slash command.
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

-- ---------------------------------------------------------------------------
-- Event frame
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "SatedEventFrame")
Sated.frame = frame

local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  SatedDB = SatedDB or {}
  Sated.db = SatedDB
  frame:UnregisterEvent("ADDON_LOADED")
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then h(...) end
end)

Sated.handlers = handlers  -- later files (announce.lua) extend this table

-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------
SLASH_SATED1 = "/sated"
SlashCmdList.SATED = function(msg)
  print("|cff33ff99Sated|r loaded, no lust recorded.")
end
