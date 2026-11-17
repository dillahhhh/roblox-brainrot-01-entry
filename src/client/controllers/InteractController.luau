-- InteractController.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Interact: one job. E (ContextActionService) buys the nearest conveyor
-- brainrot and places a carried brainrot on the nearest free slot of the
-- player's own base. The client only asks: every purchase is a server
-- transaction, and the prompt is just a hint — the server re-checks
-- distance, cash, ownership and slots.
-- Written for phase 2 (18 Nov 2026).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BrainrotCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotCatalog"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local HudController = require(script.Parent:WaitForChild("HudController"))

local InteractController = {}

local player = Players.LocalPlayer
local remotes = nil
local INTERACT_DISTANCE = 12
local PROMPT_INTERVAL = 0.2

local targetUid = nil
local targetKind = nil -- "buy" or "place"

local function getRoot()
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

-- Free slots of the player's own base, from the cached server state
-- (exact: the server is the one that books slots).
local function getFreeSlots(state)
	local occupied = {}
	for _, item in ipairs(state.owned) do
		if item.slotIndex ~= nil then
			occupied[item.slotIndex] = true
		end
	end
	local free = {}
	for i = 1, Config.BASE_SLOTS do
		if not occupied[i] then
			table.insert(free, i)
		end
	end
	return free
end

local function findNearestBuy(root)
	local folder = Workspace:FindFirstChild("ConveyorBrainrots")
	if folder == nil then
		return nil, ""
	end
	local bestUid = nil
	local bestDist = INTERACT_DISTANCE
	local bestText = ""
	local state = HudController.getCachedState()
	local cash = 0
	if state ~= nil then
		cash = state.cash
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart ~= nil then
			local uid = model:GetAttribute("Uid")
			if uid ~= nil then
				local dist = (root.Position - model.PrimaryPart.Position).Magnitude
				if dist < bestDist then
					local entry = BrainrotCatalog.getCharacter(model.Name)
					if entry ~= nil then
						bestDist = dist
						bestUid = uid
						if cash < entry.price then
							bestText = "Tekan [E] untuk membeli " .. entry.name .. " — $" .. entry.price .. " (uang kurang!)"
						else
							bestText = "Tekan [E] untuk membeli " .. entry.name .. " — $" .. entry.price .. " (" .. BrainrotCatalog.getTierName(entry.tier) .. ")"
						end
					end
				end
			end
		end
	end
	return bestUid, bestText
end

local function findNearestPlace(root, state)
	local bases = Workspace:FindFirstChild("Bases")
	if bases == nil then
		return false
	end
	local baseModel = bases:FindFirstChild("Base" .. state.baseId)
	if baseModel == nil then
		return false
	end
	local freeSlots = getFreeSlots(state)
	if #freeSlots == 0 then
		return false
	end
	for _, slotIndex in ipairs(freeSlots) do
		local pad = baseModel:FindFirstChild("Slot" .. slotIndex)
		if pad ~= nil and (root.Position - pad.Position).Magnitude < INTERACT_DISTANCE then
			return true
		end
	end
	return false
end

local function updatePrompt()
	local root = getRoot()
	if root == nil then
		targetUid = nil
		targetKind = nil
		HudController.setContextPrompt("")
		return
	end
	local state = HudController.getCachedState()
	if state ~= nil and state.carrying ~= nil and state.baseId ~= nil then
		if findNearestPlace(root, state) then
			targetUid = nil
			targetKind = "place"
			HudController.setContextPrompt("Tekan [E] untuk menaruh " .. state.carrying.name .. " di base")
		else
			targetUid = nil
			targetKind = nil
			HudController.setContextPrompt("Bawa " .. state.carrying.name .. " ke base!")
		end
		return
	end
	local uid, text = findNearestBuy(root)
	targetUid = uid
	if uid ~= nil then
		targetKind = "buy"
	else
		targetKind = nil
	end
	HudController.setContextPrompt(text)
end

local function onInteract(_, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if targetKind == "buy" and targetUid ~= nil then
		local uid = targetUid
		targetUid = nil
		targetKind = nil
		local ok, success, message = pcall(function()
			return remotes.BuyBrainrot:InvokeServer(uid)
		end)
		if ok then
			HudController.setPrompt(message or "", 3)
		else
			HudController.setPrompt("Gagal menghubungi server.", 3)
		end
	elseif targetKind == "place" then
		targetKind = nil
		local ok, success, message = pcall(function()
			return remotes.PlaceBrainrot:InvokeServer()
		end)
		if ok then
			HudController.setPrompt(message or "", 3)
		else
			HudController.setPrompt("Gagal menghubungi server.", 3)
		end
	end
	return Enum.ContextActionResult.Sink
end

function InteractController.init()
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	ContextActionService:BindAction("BrainrotInteract", onInteract, false, Enum.KeyCode.E)
	local promptTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		promptTimer = promptTimer + dt
		if promptTimer < PROMPT_INTERVAL then
			return
		end
		promptTimer = 0
		updatePrompt()
	end)
end

return InteractController
