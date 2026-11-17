-- StealService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- TODO (phase 3, 19 Nov): steal, base lock, slap.
-- DO NOT implement before the foundation + economy phases are verified.
-- Planned API (all server-authoritative, through BrainrotData):
--   StealService.lockBase(player)  -- 30s lock, 60s cooldown
--   StealService.trySteal(thief, victim, uid)  -- real server transaction:
--     ownership transfer + lock check; never while the victim's base is locked
--   StealService.slap(attacker, target)  -- light knockback, cooldown, anti-spam
local StealService = {}

function StealService.init()
	-- Phase 3.
end

return StealService
