-- Main.server.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Server entry: wires the services together. State lives in BrainrotData,
-- the conveyor walks the cast, bases are built and assigned here.
-- Written for the foundation phase (17 Nov 2026).

local Players = game:GetService("Players")

local BrainrotData = require(script:WaitForChild("services"):WaitForChild("BrainrotData"))
local BaseService = require(script:WaitForChild("services"):WaitForChild("BaseService"))
local ConveyorService = require(script:WaitForChild("services"):WaitForChild("ConveyorService"))
local EconomyService = require(script:WaitForChild("services"):WaitForChild("EconomyService"))
local StealService = require(script:WaitForChild("services"):WaitForChild("StealService"))
local EventService = require(script:WaitForChild("services"):WaitForChild("EventService"))

BrainrotData.init()
BaseService.init()
ConveyorService.init()
EconomyService.init()
StealService.init()
EventService.init()

Players.PlayerAdded:Connect(function(player)
	BrainrotData.addPlayer(player)
	BaseService.assignBaseToPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	-- TODO phase 3: disconnect-while-carrying rule (a carried brainrot
	-- returns to the conveyor or becomes a crate, never vanishes).
	BrainrotData.removePlayer(player)
end)

print("[BRAINROT NUSANTARA] Server ready -- foundation (plaza, bases, conveyor, catalog).")
