-- EconomyService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- TODO (phase 2, 18 Nov): earn ticks, buy, carry, sell, rebirth.
-- DO NOT implement before the foundation is verified.
-- Planned API (all server-authoritative, through BrainrotData):
--   EconomyService.startEarnLoop()  -- 1s tick: addCash(player, getTotalIncome(player))
--   EconomyService.tryBuy(player, uid)  -- cash check -> carry (single ownership state)
--   EconomyService.sellBrainrot(player, uid)
--   EconomyService.tryRebirth(player)  -- cash >= REBIRTH_CASH, server-validated
local EconomyService = {}

function EconomyService.init()
	-- Phase 2.
end

return EconomyService
