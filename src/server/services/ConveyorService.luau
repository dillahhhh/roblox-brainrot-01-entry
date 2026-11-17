-- ConveyorService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- The conveyor: one job. Spawns brainrots on the bridge, walks them
-- across the plaza, despawns them at the far gate. It also owns the two
-- shared systems every character uses:
--   1. one movement system (a single Heartbeat loop moves every active
--      brainrot along the path), and
--   2. one base animation system (a single Heartbeat loop calls the
--      character's signature animation: beat, slosh, trot, sway, steam,
--      drive, float, hop, flap, crawl, glow, stance).
-- Character models are parts-based, built here in code from the catalog
-- (distinctive silhouette per character), never copied from anywhere.
-- Written for the foundation phase (17 Nov 2026).
-- Buy / carry / place is phase 2 (EconomyService); this service only
-- exposes removeFromConveyor + getActive for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrainrotCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotCatalog"))
local BrainrotData = require(script.Parent:WaitForChild("BrainrotData"))

local ConveyorService = {}

local active = {}
local conveyorFolder = nil
local spawnTimer = 0
local animClock = 0

-- Part helper -----------------------------------------------------------
-- rotation: Vector3 of degrees, or nil. Animated parts carry their base
-- offset as attributes (BaseX/BaseY/BaseZ) so the animation system can
-- rebuild their CFrame from the model pivot each frame.

local function newPart(parent, name, size, color, position, material, shape, rotation)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.Material = material or Enum.Material.SmoothPlastic
	if shape ~= nil then
		part.Shape = shape
	end
	if rotation ~= nil then
		part.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	else
		part.Position = position
	end
	part.Parent = parent
	return part
end

local function markAnimated(part, x, y, z, phase)
	part:SetAttribute("BaseX", x)
	part:SetAttribute("BaseY", y)
	part:SetAttribute("BaseZ", z)
	if phase ~= nil then
		part:SetAttribute("Phase", phase)
	end
end

local function partBase(part)
	return part:GetAttribute("BaseX") or 0, part:GetAttribute("BaseY") or 0, part:GetAttribute("BaseZ") or 0
end

-- Silhouette builders (one per character, parts relative to origin) -----

-- Tung Tung Sahur: a wooden kentongan log with two beating sticks.
local function buildKentongan(model, color)
	local log = newPart(model, "Body", Vector3.new(3, 2, 2), color, Vector3.new(0, 1.5, 0), Enum.Material.Wood, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	local armL = newPart(model, "ArmL", Vector3.new(0.25, 1.6, 0.25), Color3.fromRGB(120, 80, 40), Vector3.new(-1.1, 1.2, 0.3), Enum.Material.Wood, nil, Vector3.new(0, 0, 20))
	local armR = newPart(model, "ArmR", Vector3.new(0.25, 1.6, 0.25), Color3.fromRGB(120, 80, 40), Vector3.new(1.1, 1.2, 0.3), Enum.Material.Wood, nil, Vector3.new(0, 0, -20))
	markAnimated(armL, -1.1, 1.2, 0.3)
	markAnimated(armR, 1.1, 1.2, 0.3)
	newPart(model, "Knob", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(90, 60, 30), Vector3.new(0, 3.2, 0), Enum.Material.Wood, Enum.PartType.Ball)
	return log
end

-- Es Teh Manis: a big glass of iced tea with a straw.
local function buildEsTeh(model, color)
	local glass = newPart(model, "Body", Vector3.new(2.6, 2.4, 2.4), Color3.fromRGB(220, 240, 255), Vector3.new(0, 1.3, 0), Enum.Material.Glass, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	glass.Transparency = 0.3
	local tea = newPart(model, "Tea", Vector3.new(2.2, 2, 2), color, Vector3.new(0, 1.2, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	markAnimated(tea, 0, 1.2, 0)
	newPart(model, "Ice1", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(240, 250, 255), Vector3.new(-0.5, 2.6, 0.3), Enum.Material.SmoothPlastic)
	newPart(model, "Ice2", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(240, 250, 255), Vector3.new(0.5, 2.6, -0.3), Enum.Material.SmoothPlastic)
	local straw = newPart(model, "Straw", Vector3.new(1.8, 0.3, 0.3), Color3.fromRGB(220, 40, 60), Vector3.new(0.5, 2.9, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 20))
	markAnimated(straw, 0.5, 2.9, 0)
	return glass
end

-- Kambing Garut: a white fighting goat with horns.
local function buildKambing(model, color)
	local body = newPart(model, "Body", Vector3.new(3, 1.8, 1.8), color, Vector3.new(0, 1.6, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), color, Vector3.new(1.9, 2.2, 0), Enum.Material.SmoothPlastic)
	local hornL = newPart(model, "HornL", Vector3.new(1, 0.3, 0.3), Color3.fromRGB(120, 80, 40), Vector3.new(1.9, 3, 0.5), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, -40))
	local hornR = newPart(model, "HornR", Vector3.new(1, 0.3, 0.3), Color3.fromRGB(120, 80, 40), Vector3.new(1.9, 3, -0.5), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, -40))
	markAnimated(hornL, 1.9, 3, 0.5)
	markAnimated(hornR, 1.9, 3, -0.5)
	newPart(model, "Beard", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(200, 200, 200), Vector3.new(2.3, 1.6, 0), Enum.Material.SmoothPlastic)
	local legPositions = { { -1.1, 0.6 }, { 1.1, 0.6 }, { -1.1, -0.6 }, { 1.1, -0.6 } }
	for i, pos in ipairs(legPositions) do
		local leg = newPart(model, "Leg" .. i, Vector3.new(0.4, 1.2, 0.4), Color3.fromRGB(220, 220, 220), Vector3.new(pos[1], 0.6, pos[2]), Enum.Material.SmoothPlastic)
		local phase = 0
		if i % 2 == 0 then
			phase = 1
		end
		markAnimated(leg, pos[1], 0.6, pos[2], phase)
	end
	newPart(model, "Tail", Vector3.new(0.6, 0.4, 0.4), color, Vector3.new(-1.7, 2, 0), Enum.Material.SmoothPlastic)
	return body
end

-- Ondel-Ondel: a giant Betawi puppet, big round head, swaying body.
local function buildOndel(model, color)
	local body = newPart(model, "Body", Vector3.new(3, 3.5, 2), Color3.fromRGB(40, 120, 220), Vector3.new(0, 1.75, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(2.2, 2.2, 2.2), color, Vector3.new(0, 4.2, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Headdress", Vector3.new(2.6, 0.5, 2.6), Color3.fromRGB(255, 210, 60), Vector3.new(0, 5.2, 0), Enum.Material.SmoothPlastic)
	local armL = newPart(model, "ArmL", Vector3.new(0.5, 2, 0.5), Color3.fromRGB(40, 120, 220), Vector3.new(-1.8, 2, 0), Enum.Material.SmoothPlastic)
	local armR = newPart(model, "ArmR", Vector3.new(0.5, 2, 0.5), Color3.fromRGB(40, 120, 220), Vector3.new(1.8, 2, 0), Enum.Material.SmoothPlastic)
	markAnimated(armL, -1.8, 2, 0)
	markAnimated(armR, 1.8, 2, 0)
	return body
end

-- Nasi Padang: a plate of rice with side dishes, steam rising.
local function buildNasiPadang(model, color)
	newPart(model, "Leaf", Vector3.new(4.5, 0.2, 4.5), Color3.fromRGB(40, 140, 60), Vector3.new(0, 0.5, 0), Enum.Material.SmoothPlastic)
	local plate = newPart(model, "Plate", Vector3.new(0.5, 4, 4), Color3.fromRGB(245, 245, 245), Vector3.new(0, 0.8, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	local rice = newPart(model, "Body", Vector3.new(2.4, 1.5, 2.4), color, Vector3.new(0, 1.6, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish1", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(200, 60, 40), Vector3.new(1.4, 1.2, 0.8), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish2", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(60, 160, 60), Vector3.new(-1.4, 1.2, 0.8), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish3", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(140, 90, 40), Vector3.new(0, 1.2, -1.4), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local steam = newPart(model, "Steam", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(255, 255, 255), Vector3.new(0, 2.6, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	steam.Transparency = 0.5
	markAnimated(steam, 0, 2.6, 0)
	return rice
end

-- Bajaj Biru: a blue three-wheeled taxi with spinning wheels.
local function buildBajaj(model, color)
	local body = newPart(model, "Body", Vector3.new(3.2, 1.8, 2.4), color, Vector3.new(0, 1.4, 0), Enum.Material.Metal)
	newPart(model, "Roof", Vector3.new(3.4, 0.3, 2.6), Color3.fromRGB(30, 90, 200), Vector3.new(0, 2.6, 0), Enum.Material.Metal)
	local windshield = newPart(model, "Windshield", Vector3.new(0.2, 1, 2), Color3.fromRGB(200, 230, 255), Vector3.new(1.5, 2, 0), Enum.Material.Glass)
	windshield.Transparency = 0.3
	newPart(model, "Headlight", Vector3.new(0.3, 0.4, 0.4), Color3.fromRGB(255, 240, 150), Vector3.new(1.7, 1.2, 0), Enum.Material.Neon)
	local wheelPositions = { { 1.4, 0 }, { -1.2, 1.1 }, { -1.2, -1.1 } }
	for i, pos in ipairs(wheelPositions) do
		local wheel = newPart(model, "Wheel" .. i, Vector3.new(0.5, 1, 1), Color3.fromRGB(30, 30, 30), Vector3.new(pos[1], 0.5, pos[2]), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 90, 0))
		markAnimated(wheel, pos[1], 0.5, pos[2])
	end
	return body
end

-- Kuntilanak: a floating white ghost, long black hair, no feet.
local function buildKuntilanak(model, color)
	local dress = newPart(model, "Body", Vector3.new(2.5, 2.2, 2.2), color, Vector3.new(0, 1.25, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	newPart(model, "Torso", Vector3.new(1.6, 1.2, 1), color, Vector3.new(0, 2.8, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(250, 240, 230), Vector3.new(0, 3.8, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local hair = newPart(model, "Hair", Vector3.new(1.4, 2.2, 0.6), Color3.fromRGB(20, 20, 20), Vector3.new(0, 3.6, -0.6), Enum.Material.SmoothPlastic)
	markAnimated(hair, 0, 3.6, -0.6)
	local armL = newPart(model, "ArmL", Vector3.new(0.4, 1.6, 0.4), color, Vector3.new(-1, 2.8, 0), Enum.Material.SmoothPlastic)
	local armR = newPart(model, "ArmR", Vector3.new(0.4, 1.6, 0.4), color, Vector3.new(1, 2.8, 0), Enum.Material.SmoothPlastic)
	markAnimated(armL, -1, 2.8, 0)
	markAnimated(armR, 1, 2.8, 0)
	return dress
end

-- Tuyul Kantong: a small green child carrying a money bag.
local function buildTuyul(model, color)
	local body = newPart(model, "Body", Vector3.new(1.6, 1.6, 1.4), color, Vector3.new(0, 1.1, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(1.4, 1.4, 1.4), Color3.fromRGB(200, 170, 130), Vector3.new(0, 2.4, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local bag = newPart(model, "Bag", Vector3.new(1.6, 1.2, 1.6), Color3.fromRGB(140, 100, 50), Vector3.new(1.4, 0.8, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	markAnimated(bag, 1.4, 0.8, 0)
	newPart(model, "Coins", Vector3.new(0.5, 1, 1), Color3.fromRGB(255, 210, 60), Vector3.new(1.4, 1.6, 0), Enum.Material.Metal, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	newPart(model, "LegL", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(90, 130, 80), Vector3.new(-0.4, 0.3, 0), Enum.Material.SmoothPlastic)
	newPart(model, "LegR", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(90, 130, 80), Vector3.new(0.4, 0.3, 0), Enum.Material.SmoothPlastic)
	return body
end

-- Garuda Emas: a golden garuda with flapping wings.
local function buildGaruda(model, color)
	local body = newPart(model, "Body", Vector3.new(2.2, 1.8, 1.6), color, Vector3.new(0, 1.8, 0), Enum.Material.Metal)
	local wingL = newPart(model, "WingL", Vector3.new(2.5, 0.2, 1.4), color, Vector3.new(-2, 2.2, 0), Enum.Material.Metal)
	local wingR = newPart(model, "WingR", Vector3.new(2.5, 0.2, 1.4), color, Vector3.new(2, 2.2, 0), Enum.Material.Metal)
	markAnimated(wingL, -2, 2.2, 0)
	markAnimated(wingR, 2, 2.2, 0)
	newPart(model, "Head", Vector3.new(1.1, 1.1, 1.1), color, Vector3.new(1.4, 2.6, 0), Enum.Material.Metal, Enum.PartType.Ball)
	newPart(model, "Beak", Vector3.new(0.7, 0.4, 0.4), Color3.fromRGB(255, 140, 40), Vector3.new(2.1, 2.6, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Tail1", Vector3.new(1.6, 0.2, 0.4), color, Vector3.new(-1.8, 1.6, 0), Enum.Material.Metal)
	newPart(model, "Tail2", Vector3.new(1.6, 0.2, 0.4), color, Vector3.new(-1.8, 1.6, 0.5), Enum.Material.Metal, nil, Vector3.new(0, 20, 0))
	newPart(model, "Tail3", Vector3.new(1.6, 0.2, 0.4), color, Vector3.new(-1.8, 1.6, -0.5), Enum.Material.Metal, nil, Vector3.new(0, -20, 0))
	return body
end

-- Komodo Raja: a long grey-green dragon with a sweeping tail.
local function buildKomodo(model, color)
	local body = newPart(model, "Body", Vector3.new(4, 1.4, 1.8), color, Vector3.new(0, 1, 0), Enum.Material.SmoothPlastic)
	local tail = newPart(model, "Tail", Vector3.new(2.5, 0.6, 0.6), color, Vector3.new(-3, 1, 0), Enum.Material.SmoothPlastic)
	markAnimated(tail, -3, 1, 0)
	newPart(model, "Head", Vector3.new(1.4, 1, 1.2), color, Vector3.new(2.4, 1.2, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Tongue", Vector3.new(0.8, 0.15, 0.3), Color3.fromRGB(220, 60, 60), Vector3.new(3.4, 1.1, 0), Enum.Material.SmoothPlastic)
	local spikePositions = { -1, 0, 1 }
	for i, x in ipairs(spikePositions) do
		newPart(model, "Spike" .. i, Vector3.new(0.5, 0.8, 0.5), Color3.fromRGB(80, 100, 70), Vector3.new(x, 1.9, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, 45))
	end
	local legPositions = { { -1.4, 0.8 }, { 1.4, 0.8 }, { -1.4, -0.8 }, { 1.4, -0.8 } }
	for i, pos in ipairs(legPositions) do
		newPart(model, "Leg" .. i, Vector3.new(0.5, 0.8, 0.5), Color3.fromRGB(90, 120, 80), Vector3.new(pos[1], 0.4, pos[2]), Enum.Material.SmoothPlastic)
	end
	return body
end

-- Sang Hyang Tung Tung: a giant golden kentongan with a crown and glow.
local function buildSangHyang(model, color)
	local log = newPart(model, "Body", Vector3.new(4, 2.6, 2.6), color, Vector3.new(0, 2, 0), Enum.Material.Wood, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	newPart(model, "Crown", Vector3.new(0.5, 2.8, 2.8), Color3.fromRGB(255, 210, 60), Vector3.new(0, 4.3, 0), Enum.Material.Metal, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	for i = 1, 3 do
		local x = (i - 2) * 0.9
		newPart(model, "CrownSpike" .. i, Vector3.new(0.3, 0.8, 0.3), Color3.fromRGB(255, 210, 60), Vector3.new(x, 4.9, 0), Enum.Material.Metal)
	end
	local armL = newPart(model, "ArmL", Vector3.new(0.35, 2, 0.35), Color3.fromRGB(255, 210, 60), Vector3.new(-1.5, 2, 0.3), Enum.Material.Metal)
	local armR = newPart(model, "ArmR", Vector3.new(0.35, 2, 0.35), Color3.fromRGB(255, 210, 60), Vector3.new(1.5, 2, 0.3), Enum.Material.Metal)
	markAnimated(armL, -1.5, 2, 0.3)
	markAnimated(armR, 1.5, 2, 0.3)
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Color3.fromRGB(255, 200, 80)
	glow.Brightness = 2
	glow.Range = 12
	glow.Parent = log
	return log
end

-- Nusantara Prime: a composite hero — Papuan feather headdress, red-gold
-- torso, round shield, keris at the waist, sarong.
local function buildNusantaraPrime(model, color)
	local torso = newPart(model, "Body", Vector3.new(2.6, 2.4, 2), color, Vector3.new(0, 1.6, 0), Enum.Material.Metal)
	newPart(model, "Sarong", Vector3.new(2.4, 1.2, 2.1), Color3.fromRGB(120, 30, 30), Vector3.new(0, 0.6, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(1.3, 1.3, 1.3), Color3.fromRGB(200, 170, 130), Vector3.new(0, 3.2, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local featherColors = { Color3.fromRGB(220, 40, 40), Color3.fromRGB(255, 210, 60), Color3.fromRGB(40, 180, 80) }
	for i, featherColor in ipairs(featherColors) do
		local x = (i - 2) * 0.5
		local feather = newPart(model, "Feather" .. i, Vector3.new(0.25, 1.6, 0.6), featherColor, Vector3.new(x, 4.2, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, (i - 2) * -20))
		markAnimated(feather, x, 4.2, 0)
	end
	local shield = newPart(model, "Shield", Vector3.new(0.3, 2.2, 2.2), Color3.fromRGB(255, 210, 60), Vector3.new(-1.6, 1.8, 0), Enum.Material.Metal, Enum.PartType.Cylinder)
	markAnimated(shield, -1.6, 1.8, 0)
	newPart(model, "Keris", Vector3.new(0.2, 1.4, 0.4), Color3.fromRGB(200, 200, 210), Vector3.new(1.2, 1, 0.6), Enum.Material.Metal, nil, Vector3.new(0, 0, 30))
	return torso
end

local BUILDERS = {
	kentongan = buildKentongan,
	es_teh = buildEsTeh,
	kambing = buildKambing,
	ondel = buildOndel,
	nasi_padang = buildNasiPadang,
	bajaj = buildBajaj,
	kuntilanak = buildKuntilanak,
	tuyul = buildTuyul,
	garuda = buildGaruda,
	komodo = buildKomodo,
	sang_hyang = buildSangHyang,
	nusantara_prime = buildNusantaraPrime,
}

-- Label + mutation ------------------------------------------------------

local function addLabel(model, bodyPart, entry, mutation, rate)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BrainrotLabel"
	gui.Size = UDim2.new(0, 180, 0, 56)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = bodyPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	local text = entry.name .. "\n" .. BrainrotCatalog.getTierName(entry.tier) .. "  $" .. rate .. "/s"
	if mutation ~= nil then
		text = mutation.name .. " " .. text
	end
	label.Text = text
	label.Parent = gui
end

-- Mutation visual: tint the body + a neon edge for Diamond/Rainbow.
local function applyMutation(model, bodyPart, mutation)
	if mutation == nil then
		return
	end
	bodyPart.Color = mutation.color
	if mutation.name == "Diamond" or mutation.name == "Rainbow" then
		bodyPart.Material = Enum.Material.Neon
	end
end

function ConveyorService.buildCharacterModel(entry, mutation)
	local model = Instance.new("Model")
	model.Name = entry.id
	local builder = BUILDERS[entry.silhouette]
	local bodyPart = builder(model, entry.color)
	applyMutation(model, bodyPart, mutation)
	local rate = BrainrotCatalog.getRate(entry, mutation)
	addLabel(model, bodyPart, entry, mutation, rate)
	model.PrimaryPart = bodyPart
	return model
end

-- Animation system ------------------------------------------------------
-- One function per signature animation. Each takes (model, pivot, t) and
-- returns the pivot (possibly tilted/bobbed). Part offsets come from the
-- attributes the builders wrote, so the animation never depends on where
-- the model was built.

local function animBeat(model, pivot, t)
	local swing = math.sin(t * 6) * 0.7
	for _, name in ipairs({ "ArmL", "ArmR" }) do
		local arm = model:FindFirstChild(name)
		if arm ~= nil then
			local bx, by, bz = partBase(arm)
			arm.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(swing, 0, 0)
		end
	end
	return pivot
end

local function animSlosh(model, pivot, t)
	local tea = model:FindFirstChild("Tea")
	if tea ~= nil then
		local bx, by, bz = partBase(tea)
		tea.CFrame = pivot * CFrame.new(bx, by + math.sin(t * 3) * 0.1, bz)
	end
	local straw = model:FindFirstChild("Straw")
	if straw ~= nil then
		local bx, by, bz = partBase(straw)
		straw.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, math.rad(20 + math.sin(t * 3) * 8))
	end
	return pivot
end

local function animTrot(model, pivot, t)
	for i = 1, 4 do
		local leg = model:FindFirstChild("Leg" .. i)
		if leg ~= nil then
			local bx, by, bz = partBase(leg)
			local phase = leg:GetAttribute("Phase") or 0
			local swing = math.sin(t * 8 + phase * math.pi) * 0.5
			leg.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(swing, 0, 0)
		end
	end
	return pivot
end

local function animSway(model, pivot, t)
	local tilt = math.sin(t * 2) * 0.06
	for _, name in ipairs({ "ArmL", "ArmR" }) do
		local arm = model:FindFirstChild(name)
		if arm ~= nil then
			local bx, by, bz = partBase(arm)
			arm.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, math.sin(t * 2) * 0.2)
		end
	end
	return pivot * CFrame.Angles(0, 0, tilt)
end

local function animSteam(model, pivot, t)
	local steam = model:FindFirstChild("Steam")
	if steam ~= nil then
		local bx, by, bz = partBase(steam)
		local cycle = (t * 0.5) % 1
		steam.CFrame = pivot * CFrame.new(bx, by + cycle * 1.5, bz)
		steam.Transparency = 0.3 + cycle * 0.6
	end
	return pivot * CFrame.new(0, math.sin(t * 2) * 0.05, 0)
end

local function animDrive(model, pivot, t)
	for i = 1, 3 do
		local wheel = model:FindFirstChild("Wheel" .. i)
		if wheel ~= nil then
			local bx, by, bz = partBase(wheel)
			wheel.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, t * 8) * CFrame.Angles(0, math.rad(90), 0)
		end
	end
	return pivot * CFrame.new(0, math.abs(math.sin(t * 10)) * 0.08, 0)
end

local function animFloat(model, pivot, t)
	local hair = model:FindFirstChild("Hair")
	if hair ~= nil then
		local bx, by, bz = partBase(hair)
		hair.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, math.sin(t * 1.5) * 0.15)
	end
	return pivot * CFrame.new(0, math.sin(t * 1.5) * 0.3, 0)
end

local function animHop(model, pivot, t)
	local bag = model:FindFirstChild("Bag")
	if bag ~= nil then
		local bx, by, bz = partBase(bag)
		bag.CFrame = pivot * CFrame.new(bx, by + math.abs(math.sin(t * 4)) * 0.2, bz)
	end
	return pivot * CFrame.new(0, math.abs(math.sin(t * 4)) * 0.5, 0)
end

local function animFlap(model, pivot, t)
	local flap = math.sin(t * 5) * 0.5
	for _, name in ipairs({ "WingL", "WingR" }) do
		local wing = model:FindFirstChild(name)
		if wing ~= nil then
			local bx, by, bz = partBase(wing)
			local sign = 1
			if name == "WingR" then
				sign = -1
			end
			wing.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, flap * sign)
		end
	end
	return pivot * CFrame.new(0, math.sin(t * 5) * 0.1, 0)
end

local function animCrawl(model, pivot, t)
	local tail = model:FindFirstChild("Tail")
	if tail ~= nil then
		local bx, by, bz = partBase(tail)
		tail.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, math.sin(t * 3) * 0.3, 0)
	end
	return pivot * CFrame.Angles(0, 0, math.sin(t * 3) * 0.05)
end

local function animGlow(model, pivot, t)
	local glow = model:FindFirstChild("Glow", true)
	if glow ~= nil then
		glow.Brightness = 2 + math.sin(t * 3)
	end
	return animBeat(model, pivot, t)
end

local function animStance(model, pivot, t)
	local shield = model:FindFirstChild("Shield")
	if shield ~= nil then
		local bx, by, bz = partBase(shield)
		shield.CFrame = pivot * CFrame.new(bx, by + math.sin(t * 2) * 0.15, bz)
	end
	return pivot * CFrame.Angles(0, math.sin(t * 0.5) * 0.3, 0)
end

local ANIMATIONS = {
	beat = animBeat,
	slosh = animSlosh,
	trot = animTrot,
	sway = animSway,
	steam = animSteam,
	drive = animDrive,
	float = animFloat,
	hop = animHop,
	flap = animFlap,
	crawl = animCrawl,
	glow = animGlow,
	stance = animStance,
}

-- Spawn / movement ------------------------------------------------------

local function countActive()
	local count = 0
	for _ in pairs(active) do
		count = count + 1
	end
	return count
end

function ConveyorService.spawnBrainrot()
	if countActive() >= Config.MAX_ON_CONVEYOR then
		return nil
	end
	local entry = BrainrotCatalog.rollCharacter()
	local mutation = BrainrotCatalog.rollMutation()
	local record = BrainrotData.createBrainrot(entry.id, mutation and mutation.name or nil)
	if record == nil then
		return nil
	end
	local model = ConveyorService.buildCharacterModel(entry, mutation)
	model:PivotTo(CFrame.new(Config.CONVEYOR_START))
	model.Parent = conveyorFolder
	BrainrotData.setBrainrotModel(record.uid, model)
	active[record.uid] = {
		uid = record.uid,
		model = model,
		entry = entry,
		distance = 0,
		animT = math.random() * 10,
	}
	return record.uid
end

-- Phase 2 hook: take a brainrot off the conveyor (bought). Its model is
-- handed over, not destroyed; ownership moves in BrainrotData.
function ConveyorService.removeFromConveyor(uid)
	local item = active[uid]
	if item == nil then
		return nil
	end
	active[uid] = nil
	return item.model
end

function ConveyorService.getActive()
	local list = {}
	for uid, item in pairs(active) do
		table.insert(list, { uid = uid, entry = item.entry, model = item.model })
	end
	return list
end

local function despawnBrainrot(uid)
	local item = active[uid]
	if item == nil then
		return
	end
	active[uid] = nil
	BrainrotData.setBrainrotState(uid, "gone")
	if item.model ~= nil then
		item.model:Destroy()
	end
end

local function updateConveyor(dt)
	animClock = animClock + dt
	spawnTimer = spawnTimer + dt
	if spawnTimer >= Config.SPAWN_INTERVAL then
		spawnTimer = 0
		ConveyorService.spawnBrainrot()
	end
	local path = Config.CONVEYOR_FINISH - Config.CONVEYOR_START
	local pathLength = path.Magnitude
	for uid, item in pairs(active) do
		item.distance = item.distance + Config.CONVEYOR_SPEED * dt
		item.animT = item.animT + dt
		local progress = item.distance / pathLength
		if progress >= 1 then
			despawnBrainrot(uid)
		else
			local position = Config.CONVEYOR_START + path * progress
			local pivot = CFrame.new(position)
			local animate = ANIMATIONS[item.entry.animation]
			if animate ~= nil then
				pivot = animate(item.model, pivot, item.animT)
			end
			item.model:PivotTo(pivot)
		end
	end
end

function ConveyorService.init()
	conveyorFolder = Instance.new("Folder")
	conveyorFolder.Name = "ConveyorBrainrots"
	conveyorFolder.Parent = Workspace
	RunService.Heartbeat:Connect(updateConveyor)
end

return ConveyorService
