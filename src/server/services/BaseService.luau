-- BaseService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Bases: one job. Clones the BaseTemplate (ServerStorage) into 8 base
-- platforms in a ring around the plaza, assigns one to each player,
-- owns the slots a brainrot is placed on.
-- Written for the foundation phase (17 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrainrotData = require(script.Parent:WaitForChild("BrainrotData"))

local BaseService = {}

local basesFolder = nil
local baseModels = {}

-- A base is rotated so its sign sits on the far side from the plaza
-- centre, facing in: yaw = -angle - 90 degrees.
-- Y = 1: with the Platform as PrimaryPart (set in init), the 2-stud
-- platform spans Y 0..2, sitting on the plaza floor (top 0.55).
local function ringCFrame(index)
	local angle = (index - 1) * (math.pi * 2 / Config.BASE_COUNT)
	local x = math.cos(angle) * Config.BASE_RING_RADIUS
	local z = math.sin(angle) * Config.BASE_RING_RADIUS
	return CFrame.new(x, 1, z) * CFrame.Angles(0, -angle - math.pi / 2, 0)
end

local function addSignLabel(model, baseId)
	local sign = model:FindFirstChild("SignBoard")
	if sign == nil then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BaseSign"
	gui.Size = UDim2.new(0, 220, 0, 60)
	gui.StudsOffset = Vector3.new(0, 1, 0)
	gui.AlwaysOnTop = true
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Name = "OwnerLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "Base " .. baseId .. "\n(kosong)"
	label.Parent = gui
end

function BaseService.init()
	basesFolder = Instance.new("Folder")
	basesFolder.Name = "Bases"
	basesFolder.Parent = Workspace
	local template = ServerStorage:WaitForChild("BaseTemplate")
	for i = 1, Config.BASE_COUNT do
		local model = template:Clone()
		model.Name = "Base" .. i
		-- FIX (18 Nov 2026, buried-base bug): the template has no
		-- PrimaryPart, so PivotTo used the bounding-box centre (Y 4.25)
		-- as the pivot and dropped the whole base 4.25 studs under the
		-- floor — Platform Y -3.25, slots Y -2.0, only the sign stuck
		-- out. Pin the pivot to the Platform before pivoting.
		local platform = model:FindFirstChild("Platform")
		if platform ~= nil then
			model.PrimaryPart = platform
		end
		model:PivotTo(ringCFrame(i))
		local platform = model:FindFirstChild("Platform")
		if platform ~= nil then
			platform.Color = Config.BASE_COLORS[i]
		end
		model.Parent = basesFolder
		baseModels[i] = model
		BrainrotData.registerBase(i, model)
		addSignLabel(model, i)
	end
end

function BaseService.getBaseModel(baseId)
	return baseModels[baseId]
end

-- First free base goes to the player. Returns the base id, or nil.
function BaseService.assignBaseToPlayer(player)
	for i = 1, Config.BASE_COUNT do
		local base = BrainrotData.getBase(i)
		if base ~= nil and base.owner == nil then
			if BrainrotData.assignBase(player, i) then
				BaseService.setSignOwner(i, player.Name)
				return i
			end
		end
	end
	return nil
end

function BaseService.setSignOwner(baseId, ownerName)
	local model = baseModels[baseId]
	if model == nil then
		return
	end
	local sign = model:FindFirstChild("SignBoard")
	if sign == nil then
		return
	end
	local gui = sign:FindFirstChild("BaseSign")
	if gui == nil then
		return
	end
	local label = gui:FindFirstChild("OwnerLabel")
	if label ~= nil then
		label.Text = "Base " .. baseId .. "\n" .. ownerName
	end
end

-- World CFrame of a slot pad, lifted so a placed brainrot stands on it.
function BaseService.getSlotCFrame(baseId, slotIndex)
	local model = baseModels[baseId]
	if model == nil then
		return nil
	end
	local pad = model:FindFirstChild("Slot" .. slotIndex)
	if pad == nil then
		return nil
	end
	return pad.CFrame * CFrame.new(0, 1.6, 0)
end

-- Place a carried brainrot on a slot: bookkeeping in BrainrotData, then
-- move its model onto the pad. Called by EconomyService in phase 2.
function BaseService.placeBrainrot(player, uid, slotIndex)
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return false
	end
	local baseId = state.baseId
	if baseId == nil then
		return false
	end
	local record = BrainrotData.getBrainrot(uid)
	if record == nil or record.model == nil then
		return false
	end
	local slotCFrame = BaseService.getSlotCFrame(baseId, slotIndex)
	if slotCFrame == nil then
		return false
	end
	if not BrainrotData.placeBrainrot(player, uid, slotIndex) then
		return false
	end
	-- Placed models live under their base, not the conveyor folder, so
	-- the client's buy scan never mistakes them for conveyor stock.
	record.model.Parent = baseModels[baseId]
	record.model:PivotTo(slotCFrame)
	return true
end

-- Free a slot when its brainrot leaves (steal / sell / rebirth).
function BaseService.clearSlot(uid)
	return BrainrotData.unplaceBrainrot(uid)
end

-- Phase 3: show a base lock on its sign ("Base 3\nDen\n🔒 TERKUNCI").
-- StealService calls this when a lock starts and when it expires.
function BaseService.setLockVisual(baseId, locked)
	local model = baseModels[baseId]
	if model == nil then
		return
	end
	local sign = model:FindFirstChild("SignBoard")
	if sign == nil then
		return
	end
	local gui = sign:FindFirstChild("BaseSign")
	if gui == nil then
		return
	end
	local label = gui:FindFirstChild("OwnerLabel")
	if label == nil then
		return
	end
	local text = label.Text
	if locked then
		if string.find(text, "TERKUNCI", 1, true) == nil then
			label.Text = text .. "\n🔒 TERKUNCI"
		end
	else
		label.Text = string.gsub(text, "\n🔒 TERKUNCI", "")
	end
end

return BaseService
