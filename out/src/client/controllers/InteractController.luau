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
local targetKind = nil -- "buy", "place", "crate" or "steal"
local targetCrateId = nil
local targetStealUid = nil
local targetStealVictim = nil
local stealTargets = {}
local stealFetchTimer = 0

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

-- Nearest unclaimed crate in the scramble zone (phase 3). The crate
-- label carries its class + brainrot, so the prompt reads it straight
-- off the world.
local function findNearestCrate(root)
	local folder = Workspace:FindFirstChild("ScrambleCrates")
	if folder == nil then
		return nil, ""
	end
	local bestId = nil
	local bestDist = INTERACT_DISTANCE
	local bestText = ""
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart ~= nil then
			local crateId = model:GetAttribute("CrateId")
			if crateId ~= nil then
				local dist = (root.Position - model.PrimaryPart.Position).Magnitude
				if dist < bestDist then
					local text = "Peti"
					local gui = model.PrimaryPart:FindFirstChild("CrateLabel")
					if gui ~= nil then
						local label = gui:FindFirstChildOfClass("TextLabel")
						if label ~= nil then
							text = string.gsub(label.Text, "\n", " — ")
						end
					end
					bestDist = dist
					bestId = crateId
					bestText = "Tekan [E] untuk membuka " .. text
				end
			end
		end
	end
	return bestId, bestText
end

-- Nearest stealable brainrot from the server's cached list (phase 3).
local function findNearestSteal(root)
	local bestUid = nil
	local bestVictim = nil
	local bestDist = INTERACT_DISTANCE
	local bestText = ""
	for _, target in ipairs(stealTargets) do
		local dist = (root.Position - target.position).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestUid = target.uid
			bestVictim = target.victim
			bestText = "Tekan [E] untuk MENCURI " .. target.name .. " dari " .. target.victim
		end
	end
	return bestUid, bestVictim, bestText
end

local function clearTargets()
	targetUid = nil
	targetKind = nil
	targetCrateId = nil
	targetStealUid = nil
	targetStealVictim = nil
end

local function updatePrompt()
	local root = getRoot()
	if root == nil then
		clearTargets()
		HudController.setContextPrompt("")
		return
	end
	local state = HudController.getCachedState()
	if state ~= nil and state.carrying ~= nil and state.baseId ~= nil then
		if findNearestPlace(root, state) then
			clearTargets()
			targetKind = "place"
			HudController.setContextPrompt("Tekan [E] untuk menaruh " .. state.carrying.name .. " di base")
		else
			clearTargets()
			HudController.setContextPrompt("Bawa " .. state.carrying.name .. " ke base!")
		end
		return
	end
	-- Crate claim first: the scramble window is time-limited.
	local crateId, crateText = findNearestCrate(root)
	if crateId ~= nil then
		clearTargets()
		targetCrateId = crateId
		targetKind = "crate"
		HudController.setContextPrompt(crateText)
		return
	end
	local uid, text = findNearestBuy(root)
	targetUid = uid
	if uid ~= nil then
		targetKind = "buy"
		targetCrateId = nil
		targetStealUid = nil
		targetStealVictim = nil
		HudController.setContextPrompt(text)
		return
	end
	local stealUid, stealVictim, stealText = findNearestSteal(root)
	if stealUid ~= nil then
		clearTargets()
		targetStealUid = stealUid
		targetStealVictim = stealVictim
		targetKind = "steal"
		HudController.setContextPrompt(stealText)
	else
		clearTargets()
		HudController.setContextPrompt("")
	end
end

local function onInteract(_, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if targetKind == "crate" and targetCrateId ~= nil then
		local crateId = targetCrateId
		clearTargets()
		local ok, success, message = pcall(function()
			return remotes.ClaimCrate:InvokeServer(crateId)
		end)
		if ok then
			HudController.setPrompt(message or "", 3)
		else
			HudController.setPrompt("Gagal menghubungi server.", 3)
		end
	elseif targetKind == "steal" and targetStealUid ~= nil and targetStealVictim ~= nil then
		local uid = targetStealUid
		local victim = targetStealVictim
		clearTargets()
		local ok, success, message = pcall(function()
			return remotes.TrySteal:InvokeServer(victim, uid)
		end)
		if ok then
			HudController.setPrompt(message or "", 3)
		else
			HudController.setPrompt("Gagal menghubungi server.", 3)
		end
	elseif targetKind == "buy" and targetUid ~= nil then
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
		-- Steal targets come from the server (it knows ownership and
		-- locks); refresh twice a second, never blocking the prompt.
		stealFetchTimer = stealFetchTimer + PROMPT_INTERVAL
		if stealFetchTimer >= 0.5 then
			stealFetchTimer = 0
			task.spawn(function()
				local ok, targets = pcall(function()
					return remotes.GetStealTargets:InvokeServer()
				end)
				if ok and targets ~= nil then
					stealTargets = targets
				end
			end)
		end
	end)
end

return InteractController
