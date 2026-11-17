-- Main.server.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Server entry: wires the services together. State lives in BrainrotData,
-- the conveyor walks the cast, bases are built and assigned here, and
-- the economy (earn ticks, buy/carry/place, sell, rebirth) runs through
-- the Remotes folder in ReplicatedStorage.
-- Written for the foundation phase (17 Nov 2026); economy wired in
-- phase 2 (18 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- NOTE (18 Nov 2026, first Studio play-test): Rojo $path maps src/server/
-- to the Folder ServerScriptService.Server; Main is a Script INSIDE it and
-- services/ is its SIBLING, not its child. The services must be required
-- through script.Parent — script:WaitForChild("services") never resolves,
-- Main errors at line 12 and NO service ever initialises (empty dark plaza).
local BrainrotData = require(script.Parent:WaitForChild("services"):WaitForChild("BrainrotData"))
local BaseService = require(script.Parent:WaitForChild("services"):WaitForChild("BaseService"))
local ConveyorService = require(script.Parent:WaitForChild("services"):WaitForChild("ConveyorService"))
local EconomyService = require(script.Parent:WaitForChild("services"):WaitForChild("EconomyService"))
local StealService = require(script.Parent:WaitForChild("services"):WaitForChild("StealService"))
local EventService = require(script.Parent:WaitForChild("services"):WaitForChild("EventService"))

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
