-- Sated config: all spell/debuff IDs live here as data. Zero magic numbers
-- in core.lua or announce.lua — patch-day fixes happen in this file only.
local _, Sated = ...

Sated.LUST_CASTS = {      -- spellIds that trigger the announce layer (you cast these)
  [2825]   = "Bloodlust",            -- Shaman (Horde)
  [32182]  = "Heroism",              -- Shaman (Alliance)
  [80353]  = "Time Warp",            -- Mage
  [264667] = "Primal Rage",          -- Hunter pet
  [390386] = "Fury of the Aspects",  -- Evoker
}

Sated.SATED_DEBUFFS = {   -- self-debuffs that start the timer engine
  [57724]  = true,  -- Sated (Bloodlust)
  [57723]  = true,  -- Exhaustion (Heroism)
  [80354]  = true,  -- Temporal Displacement (Time Warp)
  [264689] = true,  -- Fatigued (Primal Rage)
  [390435] = true,  -- Exhaustion (Fury of the Aspects)
}

Sated.DEFAULT_MARKS = { 180, 300, 600 }  -- seconds after lust

Sated.SATED_DURATION = 600  -- the lust-lockout window, seconds
