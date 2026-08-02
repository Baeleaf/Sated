-- Minimal WoW API stubs for running Sated under Lua 5.1 (lupa) off-game.
-- Test-harness only; never deployed to the AddOns folder.
-- Simulates: frames/events, C_Timer, auras, casts, combat state, chat,
-- slash commands, and Midnight-style secret values.

SATED_SHARED = {}   -- the addon-private table passed as select(2, ...)

-- clock ---------------------------------------------------------------
local now = 1000.0
local SERVER_EPOCH = 1754000000
function GetTime() return now end
function GetServerTime() return SERVER_EPOCH + math.floor(now) end
date = os.date

-- frames & events -----------------------------------------------------
local allFrames = {}
SCREEN_MESSAGES = {}
function CreateFrame(ftype, name, parent, template)
  local f = { _type = ftype, _events = {}, _scripts = {}, _messages = {}, _shown = true }
  function f:RegisterEvent(e) self._events[e] = true end
  function f:RegisterUnitEvent(e, unit) self._events[e] = unit or true end
  function f:UnregisterEvent(e) self._events[e] = nil end
  function f:SetScript(h, fn) self._scripts[h] = fn end
  function f:GetScript(h) return self._scripts[h] end
  function f:Show() self._shown = true end
  function f:Hide() self._shown = false end
  function f:IsShown() return self._shown end
  function f:SetPoint() end
  function f:SetSize() end
  function f:SetFrameStrata() end
  function f:SetInsertMode() end
  function f:SetTimeVisible() end
  function f:SetFadeDuration() end
  function f:SetFontObject() end
  function f:SetJustifyH() end
  function f:AddMessage(msg)
    table.insert(self._messages, msg)
    table.insert(SCREEN_MESSAGES, msg)
  end
  table.insert(allFrames, f)
  if name then _G[name] = f end
  return f
end
function FireEvent(event, ...)
  for _, f in ipairs(allFrames) do
    if f._events[event] and f._scripts.OnEvent then
      f._scripts.OnEvent(f, event, ...)
    end
  end
end
UIParent = CreateFrame("Frame", "UIParent")
GameFontNormalHuge = {}

-- timers --------------------------------------------------------------
local timers = {}
C_Timer = {}
function C_Timer.After(delay, cb)
  table.insert(timers, { fireAt = now + delay, cb = cb, cancelled = false })
end
function C_Timer.NewTimer(delay, cb)
  local t = { fireAt = now + delay, cb = cb, cancelled = false }
  function t:Cancel() self.cancelled = true end
  table.insert(timers, t)
  return t
end
-- Advance the fake clock, firing due timers in chronological order.
function AdvanceTime(dt)
  local target = now + dt
  while true do
    local best, bi
    for i, t in ipairs(timers) do
      if not t.cancelled and t.fireAt <= target and (not best or t.fireAt < best.fireAt) then
        best, bi = t, i
      end
    end
    if not best then break end
    table.remove(timers, bi)
    now = best.fireAt
    best.cb()
  end
  now = target
end

-- secrets -------------------------------------------------------------
-- Real secret values error on comparison; our stand-in is a table, which
-- errors on arithmetic/concat naturally and never compares equal to a
-- number — close enough to catch unguarded reads in tests.
local secretSet = setmetatable({}, { __mode = "k" })
function issecretvalue(v) return secretSet[v] == true end
function MakeSecret()
  local s = setmetatable({}, { __tostring = function() return "<secret>" end })
  secretSet[s] = true
  return s
end

-- chat / print --------------------------------------------------------
PRINTED = {}
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  table.insert(PRINTED, table.concat(parts, " "))
end
SENT_MESSAGES = {}
function SendChatMessage(msg, chatType, lang, target)
  table.insert(SENT_MESSAGES, { msg = msg, chatType = chatType })
end

-- combat / encounter / group ------------------------------------------
local inCombat = false
function InCombatLockdown() return inCombat end
function UnitAffectingCombat(unit) return inCombat end
function SetCombat(flag)
  if flag == inCombat then return end
  inCombat = flag
  if flag then FireEvent("PLAYER_REGEN_DISABLED")
  else FireEvent("PLAYER_REGEN_ENABLED") end
end
function SetEncounter(flag)
  if flag then FireEvent("ENCOUNTER_START", 1, "Test Boss", 8, 5)
  else FireEvent("ENCOUNTER_END", 1, "Test Boss", 8, 5, 1) end
end
LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2
local groupState = { home = false, instance = false }
function IsInGroup(cat)
  if cat == LE_PARTY_CATEGORY_INSTANCE then return groupState.instance end
  if cat == LE_PARTY_CATEGORY_HOME then return groupState.home end
  return groupState.home or groupState.instance
end
function SetGroup(home, instance)
  groupState.home = home and true or false
  groupState.instance = instance and true or false
end

-- auras ---------------------------------------------------------------
local auras = {}
local nextInstanceID = 1
C_UnitAuras = {}
function C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
  return auras[index]
end
function ApplyAura(spellId, duration, opts)
  opts = opts or {}
  local aura = {
    auraInstanceID = nextInstanceID,
    spellId = opts.secret and MakeSecret() or spellId,
    duration = opts.secretDuration and MakeSecret() or duration,
    expirationTime = now + (duration or 0),
    isHarmful = true,
    name = opts.name or ("Aura" .. tostring(spellId)),
  }
  nextInstanceID = nextInstanceID + 1
  table.insert(auras, aura)
  FireEvent("UNIT_AURA", "player", { addedAuras = { aura }, isFullUpdate = false })
  return aura
end
function FireFullAuraUpdate()
  FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
end
function ClearAuras() auras = {} end

-- casts ---------------------------------------------------------------
function CastSpell(spellId, opts)
  opts = opts or {}
  local id = opts.secret and MakeSecret() or spellId
  FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid-1", id)
end

-- misc ----------------------------------------------------------------
PLAYED_SOUNDS = {}
function PlaySound(id) table.insert(PLAYED_SOUNDS, id) end
SOUNDKIT = { RAID_WARNING = 8959 }
SlashCmdList = {}
function RunSlash(text)
  local cmd, rest = text:match("^(%S+)%s*(.-)$")
  for key, fn in pairs(SlashCmdList) do
    local i = 1
    while _G["SLASH_" .. key .. i] do
      if _G["SLASH_" .. key .. i] == cmd then fn(rest); return true end
      i = i + 1
    end
  end
  return false
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
