-- Main.server.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Server entry: wires the services together. State lives in BrainrotData,
-- the conveyor walks the cast, bases are built and assigned here, and
-- the economy (earn ticks, buy/carry/place, sell, rebirth) runs through
-- the Remotes folder in ReplicatedStorage.
-- Written for the foundation phase (17 Nov 2026); economy wired in
-- phase 2 (18 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(script:WaitForChild("services"):WaitForChild("BrainrotData"))
local BaseService = require(script:WaitForChild("services"):WaitForChild("BaseService"))
local ConveyorService = require(script:WaitForChild("services"):WaitForChild("ConveyorService"))
local EconomyService = require(script:WaitForChild("services"):WaitForChild("EconomyService"))
local StealService = require(script:WaitForChild("services"):WaitForChild("StealService"))
local EventService = require(script:WaitForChild("services"):WaitForChild("EventService"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")

BrainrotData.init()
BaseService.init()
ConveyorService.init()
EconomyService.init(remotes)
StealService.init(remotes)
EventService.init(remotes)

local function onPlayerAdded(player)
	BrainrotData.addPlayer(player)
	BaseService.assignBaseToPlayer(player)
	-- The client also asks for state with GetState on start; this push
	-- covers the case where it is already listening.
	EconomyService.sendState(player)
end

-- Players already in the game when this script runs (Studio Play Solo).
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	-- Phase 3 disconnect-while-carrying rule: the carried brainrot
	-- returns to the conveyor (or becomes a crate if the event already
	-- marked it washing). It never vanishes.
	EconomyService.releaseCarried(player)
	BrainrotData.removePlayer(player)
end)

print("[BRAINROT NUSANTARA] Server ready -- phase 3 (Pasar Tumpah, steal, lock, slap).")
