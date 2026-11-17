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
-- Phase 3: the event pauses new spawns and reroutes the path.
local paused = false
local pathStart = Config.CONVEYOR_START
local pathFinish = Config.CONVEYOR_FINISH
local reversed = false

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
-- Polish: cute face on the front cap, real drumsticks in the hands, red band.
local function buildKentongan(model, color)
	local log = newPart(model, "Body", Vector3.new(3, 2, 2), color, Vector3.new(0, 1.5, 0), Enum.Material.Wood, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	local armL = newPart(model, "ArmL", Vector3.new(0.25, 1.6, 0.25), Color3.fromRGB(120, 80, 40), Vector3.new(-1.1, 1.2, 0.3), Enum.Material.Wood, nil, Vector3.new(0, 0, 20))
	local armR = newPart(model, "ArmR", Vector3.new(0.25, 1.6, 0.25), Color3.fromRGB(120, 80, 40), Vector3.new(1.1, 1.2, 0.3), Enum.Material.Wood, nil, Vector3.new(0, 0, -20))
	markAnimated(armL, -1.1, 1.2, 0.3)
	markAnimated(armR, 1.1, 1.2, 0.3)
	local stickL = newPart(model, "StickL", Vector3.new(0.18, 1.4, 0.18), Color3.fromRGB(90, 60, 30), Vector3.new(-1.35, 2.4, 0.3), Enum.Material.Wood, Enum.PartType.Cylinder)
	local stickR = newPart(model, "StickR", Vector3.new(0.18, 1.4, 0.18), Color3.fromRGB(90, 60, 30), Vector3.new(1.35, 2.4, 0.3), Enum.Material.Wood, Enum.PartType.Cylinder)
	markAnimated(stickL, -1.35, 2.4, 0.3)
	markAnimated(stickR, 1.35, 2.4, 0.3)
	newPart(model, "EyeL", Vector3.new(0.28, 0.28, 0.28), Color3.fromRGB(40, 25, 15), Vector3.new(1.5, 1.8, 0.45), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "EyeR", Vector3.new(0.28, 0.28, 0.28), Color3.fromRGB(40, 25, 15), Vector3.new(1.5, 1.8, -0.45), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Band", Vector3.new(0.35, 2.1, 2.1), Color3.fromRGB(200, 40, 40), Vector3.new(0, 1.5, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Knob", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(90, 60, 30), Vector3.new(0, 3.2, 0), Enum.Material.Wood, Enum.PartType.Ball)
	return log
end

-- Es Teh Manis: a tall glass of iced tea with a straw.
-- Polish: upright glass (was lying on its side), third ice cube, lemon
-- slice on the rim, cute eyes on the glass.
local function buildEsTeh(model, color)
	local glass = newPart(model, "Body", Vector3.new(2.4, 2.6, 2.4), Color3.fromRGB(220, 240, 255), Vector3.new(0, 1.4, 0), Enum.Material.Glass, Enum.PartType.Cylinder)
	glass.Transparency = 0.3
	local tea = newPart(model, "Tea", Vector3.new(2, 2.3, 2), color, Vector3.new(0, 1.3, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	markAnimated(tea, 0, 1.3, 0)
	newPart(model, "Ice1", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(240, 250, 255), Vector3.new(-0.5, 2.5, 0.3), Enum.Material.SmoothPlastic)
	newPart(model, "Ice2", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(240, 250, 255), Vector3.new(0.5, 2.5, -0.3), Enum.Material.SmoothPlastic)
	newPart(model, "Ice3", Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(240, 250, 255), Vector3.new(0, 2.5, 0.55), Enum.Material.SmoothPlastic)
	local straw = newPart(model, "Straw", Vector3.new(0.35, 2, 0.35), Color3.fromRGB(220, 40, 60), Vector3.new(0.6, 3, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 20))
	markAnimated(straw, 0.6, 3, 0)
	newPart(model, "Lemon", Vector3.new(0.9, 0.15, 0.9), Color3.fromRGB(255, 220, 60), Vector3.new(0.95, 2.7, 0.4), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 15))
	newPart(model, "EyeL", Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(30, 20, 15), Vector3.new(0.4, 1.5, 1.15), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "EyeR", Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(30, 20, 15), Vector3.new(-0.4, 1.5, 1.15), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	return glass
end

-- Kambing Garut: a white fighting goat with horns.
-- Polish: bigger horns, fuller beard, red collar with gold bell, angry eyebrows.
local function buildKambing(model, color)
	local body = newPart(model, "Body", Vector3.new(3, 1.8, 1.8), color, Vector3.new(0, 1.6, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), color, Vector3.new(1.9, 2.2, 0), Enum.Material.SmoothPlastic)
	local hornL = newPart(model, "HornL", Vector3.new(1.4, 0.4, 0.4), Color3.fromRGB(120, 80, 40), Vector3.new(1.9, 3.1, 0.55), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, -40))
	local hornR = newPart(model, "HornR", Vector3.new(1.4, 0.4, 0.4), Color3.fromRGB(120, 80, 40), Vector3.new(1.9, 3.1, -0.55), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, -40))
	markAnimated(hornL, 1.9, 3.1, 0.55)
	markAnimated(hornR, 1.9, 3.1, -0.55)
	newPart(model, "Beard", Vector3.new(0.5, 0.9, 0.5), Color3.fromRGB(170, 170, 170), Vector3.new(2.35, 1.5, 0), Enum.Material.SmoothPlastic)
	newPart(model, "BrowL", Vector3.new(0.2, 0.5, 0.3), Color3.fromRGB(60, 60, 60), Vector3.new(2.45, 2.65, 0.35), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, -20))
	newPart(model, "BrowR", Vector3.new(0.2, 0.5, 0.3), Color3.fromRGB(60, 60, 60), Vector3.new(2.45, 2.65, -0.35), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, 20))
	newPart(model, "Collar", Vector3.new(0.35, 0.45, 1.9), Color3.fromRGB(200, 40, 40), Vector3.new(1.45, 1.9, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Bell", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 210, 60), Vector3.new(1.6, 1.45, 0), Enum.Material.Metal, Enum.PartType.Ball)
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
-- Polish: red robe (catalog colour), skin-tone head, gold crown with red
-- jewel, gold belt and cuffs — closer to the reference.
local function buildOndel(model, color)
	local body = newPart(model, "Body", Vector3.new(3, 3.5, 2), color, Vector3.new(0, 1.75, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(2.2, 2.2, 2.2), Color3.fromRGB(250, 220, 180), Vector3.new(0, 4.2, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Crown", Vector3.new(0.4, 2, 2), Color3.fromRGB(255, 210, 60), Vector3.new(0, 5.1, 0), Enum.Material.Metal, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	for i = 1, 3 do
		local x = (i - 2) * 0.6
		newPart(model, "CrownSpike" .. i, Vector3.new(0.25, 0.7, 0.25), Color3.fromRGB(255, 210, 60), Vector3.new(x, 5.6, 0), Enum.Material.Metal)
	end
	newPart(model, "Jewel", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 60, 60), Vector3.new(0, 5.1, 1.05), Enum.Material.Neon, Enum.PartType.Ball)
	newPart(model, "Belt", Vector3.new(3.1, 0.4, 2.1), Color3.fromRGB(255, 210, 60), Vector3.new(0, 1.2, 0), Enum.Material.Metal)
	local armL = newPart(model, "ArmL", Vector3.new(0.5, 2, 0.5), color, Vector3.new(-1.8, 2, 0), Enum.Material.SmoothPlastic)
	local armR = newPart(model, "ArmR", Vector3.new(0.5, 2, 0.5), color, Vector3.new(1.8, 2, 0), Enum.Material.SmoothPlastic)
	markAnimated(armL, -1.8, 2, 0)
	markAnimated(armR, 1.8, 2, 0)
	newPart(model, "CuffL", Vector3.new(0.6, 0.3, 0.6), Color3.fromRGB(255, 210, 60), Vector3.new(-1.8, 1.2, 0), Enum.Material.Metal)
	newPart(model, "CuffR", Vector3.new(0.6, 0.3, 0.6), Color3.fromRGB(255, 210, 60), Vector3.new(1.8, 1.2, 0), Enum.Material.Metal)
	return body
end

-- Nasi Padang: a plate of rice with side dishes, steam rising.
-- Polish: two more side dishes, a red chili, a second steam puff, cute
-- eyes on the rice mound.
local function buildNasiPadang(model, color)
	newPart(model, "Leaf", Vector3.new(4.5, 0.2, 4.5), Color3.fromRGB(40, 140, 60), Vector3.new(0, 0.5, 0), Enum.Material.SmoothPlastic)
	local plate = newPart(model, "Plate", Vector3.new(0.5, 4, 4), Color3.fromRGB(245, 245, 245), Vector3.new(0, 0.8, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	local rice = newPart(model, "Body", Vector3.new(2.4, 1.5, 2.4), color, Vector3.new(0, 1.6, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish1", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(200, 60, 40), Vector3.new(1.4, 1.2, 0.8), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish2", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(60, 160, 60), Vector3.new(-1.4, 1.2, 0.8), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish3", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(140, 90, 40), Vector3.new(0, 1.2, -1.4), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish4", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(230, 120, 40), Vector3.new(-1.2, 1.2, -1), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Dish5", Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(240, 200, 60), Vector3.new(1.2, 1.2, -0.6), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Chili", Vector3.new(0.15, 0.9, 0.15), Color3.fromRGB(220, 30, 30), Vector3.new(-0.9, 1.3, 1.1), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 30))
	newPart(model, "EyeL", Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(30, 20, 15), Vector3.new(1.1, 1.9, 0.4), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "EyeR", Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(30, 20, 15), Vector3.new(1.1, 1.9, -0.4), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local steam = newPart(model, "Steam", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(255, 255, 255), Vector3.new(0, 2.6, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	steam.Transparency = 0.5
	markAnimated(steam, 0, 2.6, 0)
	local steam2 = newPart(model, "Steam2", Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(255, 255, 255), Vector3.new(0.6, 2.3, 0.4), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	steam2.Transparency = 0.6
	return rice
end

-- Bajaj Biru: a blue three-wheeled taxi with spinning wheels.
-- Polish: twin headlights, front bumper, side mirrors, exhaust pipe,
-- Indonesian flag and a yellow TAXI roof sign.
local function buildBajaj(model, color)
	local body = newPart(model, "Body", Vector3.new(3.2, 1.8, 2.4), color, Vector3.new(0, 1.4, 0), Enum.Material.Metal)
	newPart(model, "Roof", Vector3.new(3.4, 0.3, 2.6), Color3.fromRGB(30, 90, 200), Vector3.new(0, 2.6, 0), Enum.Material.Metal)
	local windshield = newPart(model, "Windshield", Vector3.new(0.2, 1, 2), Color3.fromRGB(200, 230, 255), Vector3.new(1.5, 2, 0), Enum.Material.Glass)
	windshield.Transparency = 0.3
	newPart(model, "HeadlightL", Vector3.new(0.3, 0.4, 0.4), Color3.fromRGB(255, 240, 150), Vector3.new(1.7, 1.2, 0.7), Enum.Material.Neon)
	newPart(model, "HeadlightR", Vector3.new(0.3, 0.4, 0.4), Color3.fromRGB(255, 240, 150), Vector3.new(1.7, 1.2, -0.7), Enum.Material.Neon)
	newPart(model, "Bumper", Vector3.new(0.3, 0.4, 2.2), Color3.fromRGB(40, 40, 45), Vector3.new(1.7, 0.6, 0), Enum.Material.Metal)
	newPart(model, "MirrorL", Vector3.new(0.1, 0.5, 0.4), Color3.fromRGB(30, 30, 30), Vector3.new(1.5, 2.3, 1.35), Enum.Material.SmoothPlastic)
	newPart(model, "MirrorR", Vector3.new(0.1, 0.5, 0.4), Color3.fromRGB(30, 30, 30), Vector3.new(1.5, 2.3, -1.35), Enum.Material.SmoothPlastic)
	newPart(model, "Exhaust", Vector3.new(0.8, 0.35, 0.35), Color3.fromRGB(50, 50, 55), Vector3.new(-1.8, 0.8, 0.8), Enum.Material.Metal, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	newPart(model, "TaxiSign", Vector3.new(0.9, 0.3, 0.7), Color3.fromRGB(255, 210, 60), Vector3.new(0, 2.9, 0), Enum.Material.Neon)
	newPart(model, "FlagPole", Vector3.new(0.08, 0.9, 0.08), Color3.fromRGB(200, 200, 200), Vector3.new(-1.1, 3.1, 0.9), Enum.Material.Metal, Enum.PartType.Cylinder)
	newPart(model, "FlagRed", Vector3.new(0.55, 0.22, 0.05), Color3.fromRGB(220, 30, 30), Vector3.new(-0.8, 3.45, 0.9), Enum.Material.SmoothPlastic)
	newPart(model, "FlagWhite", Vector3.new(0.55, 0.22, 0.05), Color3.fromRGB(245, 245, 245), Vector3.new(-0.8, 3.22, 0.9), Enum.Material.SmoothPlastic)
	local wheelPositions = { { 1.4, 0 }, { -1.2, 1.1 }, { -1.2, -1.1 } }
	for i, pos in ipairs(wheelPositions) do
		local wheel = newPart(model, "Wheel" .. i, Vector3.new(0.5, 1, 1), Color3.fromRGB(30, 30, 30), Vector3.new(pos[1], 0.5, pos[2]), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 90, 0))
		markAnimated(wheel, pos[1], 0.5, pos[2])
	end
	return body
end

-- Kuntilanak: a floating white ghost, long black hair, no feet.
-- Polish: glowing red eyes, a white flower in her hair (sways with it),
-- pale blue aura light.
local function buildKuntilanak(model, color)
	local dress = newPart(model, "Body", Vector3.new(2.5, 2.2, 2.2), color, Vector3.new(0, 1.25, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	newPart(model, "Torso", Vector3.new(1.6, 1.2, 1), color, Vector3.new(0, 2.8, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(250, 240, 230), Vector3.new(0, 3.8, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "EyeL", Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(255, 40, 40), Vector3.new(0.25, 3.9, 0.55), Enum.Material.Neon, Enum.PartType.Ball)
	newPart(model, "EyeR", Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(255, 40, 40), Vector3.new(-0.25, 3.9, 0.55), Enum.Material.Neon, Enum.PartType.Ball)
	local hair = newPart(model, "Hair", Vector3.new(1.4, 2.2, 0.6), Color3.fromRGB(20, 20, 20), Vector3.new(0, 3.6, -0.6), Enum.Material.SmoothPlastic)
	markAnimated(hair, 0, 3.6, -0.6)
	local flower = newPart(model, "Flower", Vector3.new(0.32, 0.32, 0.32), Color3.fromRGB(255, 255, 255), Vector3.new(0.45, 4.45, -0.1), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	markAnimated(flower, 0.45, 4.45, -0.1)
	local flowerCenter = newPart(model, "FlowerCenter", Vector3.new(0.16, 0.16, 0.16), Color3.fromRGB(255, 210, 60), Vector3.new(0.45, 4.45, 0.06), Enum.Material.Neon, Enum.PartType.Ball)
	markAnimated(flowerCenter, 0.45, 4.45, 0.06)
	local armL = newPart(model, "ArmL", Vector3.new(0.4, 1.6, 0.4), color, Vector3.new(-1, 2.8, 0), Enum.Material.SmoothPlastic)
	local armR = newPart(model, "ArmR", Vector3.new(0.4, 1.6, 0.4), color, Vector3.new(1, 2.8, 0), Enum.Material.SmoothPlastic)
	markAnimated(armL, -1, 2.8, 0)
	markAnimated(armR, 1, 2.8, 0)
	local aura = Instance.new("PointLight")
	aura.Name = "Aura"
	aura.Color = Color3.fromRGB(150, 200, 255)
	aura.Brightness = 1.5
	aura.Range = 8
	aura.Parent = dress
	return dress
end

-- Tuyul Kantong: a small green child carrying a money bag.
-- Polish: bright green skin and head, little cap, pointy ears, bigger
-- bag, a coin pile at his feet.
local function buildTuyul(model, color)
	local body = newPart(model, "Body", Vector3.new(1.6, 1.6, 1.4), color, Vector3.new(0, 1.1, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Head", Vector3.new(1.4, 1.4, 1.4), Color3.fromRGB(90, 200, 90), Vector3.new(0, 2.4, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	newPart(model, "Cap", Vector3.new(1.2, 0.3, 1.2), Color3.fromRGB(50, 140, 60), Vector3.new(0, 3, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	newPart(model, "EarL", Vector3.new(0.3, 0.5, 0.3), Color3.fromRGB(90, 200, 90), Vector3.new(0.75, 2.6, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, 30))
	newPart(model, "EarR", Vector3.new(0.3, 0.5, 0.3), Color3.fromRGB(90, 200, 90), Vector3.new(-0.75, 2.6, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, -30))
	local bag = newPart(model, "Bag", Vector3.new(1.9, 1.4, 1.9), Color3.fromRGB(140, 100, 50), Vector3.new(1.5, 0.9, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	markAnimated(bag, 1.5, 0.9, 0)
	newPart(model, "Coins", Vector3.new(0.5, 1, 1), Color3.fromRGB(255, 210, 60), Vector3.new(1.5, 1.7, 0), Enum.Material.Metal, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	for i = 1, 3 do
		newPart(model, "CoinPile" .. i, Vector3.new(0.6, 0.15, 0.6), Color3.fromRGB(255, 210, 60), Vector3.new(1.9, 0.1 + (i - 1) * 0.16, 0.7), Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	newPart(model, "LegL", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(90, 130, 80), Vector3.new(-0.4, 0.3, 0), Enum.Material.SmoothPlastic)
	newPart(model, "LegR", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(90, 130, 80), Vector3.new(0.4, 0.3, 0), Enum.Material.SmoothPlastic)
	return body
end

-- Garuda Emas: a golden garuda with flapping wings.
-- Polish: bigger layered wings (second feather layer), red crest, talons.
local function buildGaruda(model, color)
	local body = newPart(model, "Body", Vector3.new(2.2, 1.8, 1.6), color, Vector3.new(0, 1.8, 0), Enum.Material.Metal)
	local wingL = newPart(model, "WingL", Vector3.new(3.2, 0.25, 1.8), color, Vector3.new(-2.3, 2.2, 0), Enum.Material.Metal)
	local wingR = newPart(model, "WingR", Vector3.new(3.2, 0.25, 1.8), color, Vector3.new(2.3, 2.2, 0), Enum.Material.Metal)
	markAnimated(wingL, -2.3, 2.2, 0)
	markAnimated(wingR, 2.3, 2.2, 0)
	local wingL2 = newPart(model, "WingL2", Vector3.new(2.2, 0.2, 1.2), Color3.fromRGB(230, 170, 30), Vector3.new(-1.9, 1.9, 0), Enum.Material.Metal)
	local wingR2 = newPart(model, "WingR2", Vector3.new(2.2, 0.2, 1.2), Color3.fromRGB(230, 170, 30), Vector3.new(1.9, 1.9, 0), Enum.Material.Metal)
	markAnimated(wingL2, -1.9, 1.9, 0)
	markAnimated(wingR2, 1.9, 1.9, 0)
	newPart(model, "Head", Vector3.new(1.1, 1.1, 1.1), color, Vector3.new(1.4, 2.6, 0), Enum.Material.Metal, Enum.PartType.Ball)
	newPart(model, "Beak", Vector3.new(0.7, 0.4, 0.4), Color3.fromRGB(255, 140, 40), Vector3.new(2.1, 2.6, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Crest", Vector3.new(0.25, 0.6, 0.4), Color3.fromRGB(220, 40, 40), Vector3.new(1.3, 3.2, 0), Enum.Material.SmoothPlastic)
	newPart(model, "TalonL", Vector3.new(0.4, 0.3, 0.4), Color3.fromRGB(60, 50, 40), Vector3.new(0.5, 0.75, 0), Enum.Material.SmoothPlastic)
	newPart(model, "TalonR", Vector3.new(0.4, 0.3, 0.4), Color3.fromRGB(60, 50, 40), Vector3.new(-0.5, 0.75, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Tail1", Vector3.new(1.6, 0.2, 0.4), color, Vector3.new(-1.8, 1.6, 0), Enum.Material.Metal)
	newPart(model, "Tail2", Vector3.new(1.6, 0.2, 0.4), color, Vector3.new(-1.8, 1.6, 0.5), Enum.Material.Metal, nil, Vector3.new(0, 20, 0))
	newPart(model, "Tail3", Vector3.new(1.6, 0.2, 0.4), color, Vector3.new(-1.8, 1.6, -0.5), Enum.Material.Metal, nil, Vector3.new(0, -20, 0))
	return body
end

-- Komodo Raja: a long grey-green dragon with a sweeping tail.
-- Polish: five back spikes plus tail spikes, glowing yellow eyes, bigger
-- tongue, lower jaw.
local function buildKomodo(model, color)
	local body = newPart(model, "Body", Vector3.new(4, 1.4, 1.8), color, Vector3.new(0, 1, 0), Enum.Material.SmoothPlastic)
	local tail = newPart(model, "Tail", Vector3.new(2.5, 0.6, 0.6), color, Vector3.new(-3, 1, 0), Enum.Material.SmoothPlastic)
	markAnimated(tail, -3, 1, 0)
	newPart(model, "Head", Vector3.new(1.4, 1, 1.2), color, Vector3.new(2.4, 1.2, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Tongue", Vector3.new(1, 0.15, 0.35), Color3.fromRGB(220, 60, 60), Vector3.new(3.5, 1.05, 0), Enum.Material.SmoothPlastic)
	newPart(model, "Jaw", Vector3.new(0.9, 0.25, 1), Color3.fromRGB(90, 115, 80), Vector3.new(2.7, 0.72, 0), Enum.Material.SmoothPlastic)
	newPart(model, "EyeL", Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(255, 220, 60), Vector3.new(3.05, 1.4, 0.3), Enum.Material.Neon, Enum.PartType.Ball)
	newPart(model, "EyeR", Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(255, 220, 60), Vector3.new(3.05, 1.4, -0.3), Enum.Material.Neon, Enum.PartType.Ball)
	local spikePositions = { -1.6, -0.8, 0, 0.8, 1.6 }
	for i, x in ipairs(spikePositions) do
		newPart(model, "Spike" .. i, Vector3.new(0.5, 0.8, 0.5), Color3.fromRGB(80, 100, 70), Vector3.new(x, 1.9, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, 45))
	end
	newPart(model, "TailSpike1", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(80, 100, 70), Vector3.new(-3.5, 1.5, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, 45))
	newPart(model, "TailSpike2", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(80, 100, 70), Vector3.new(-4.2, 1.4, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, 45))
	local legPositions = { { -1.4, 0.8 }, { 1.4, 0.8 }, { -1.4, -0.8 }, { 1.4, -0.8 } }
	for i, pos in ipairs(legPositions) do
		newPart(model, "Leg" .. i, Vector3.new(0.5, 0.8, 0.5), Color3.fromRGB(90, 120, 80), Vector3.new(pos[1], 0.4, pos[2]), Enum.Material.SmoothPlastic)
	end
	return body
end

-- Sang Hyang Tung Tung: a giant golden kentongan with a crown and glow.
-- Polish: golden hammers in both hands (they ride the arm swing), a halo
-- ring of light behind the crown, red jewel, gold shoulder pads.
local function buildSangHyang(model, color)
	local log = newPart(model, "Body", Vector3.new(4, 2.6, 2.6), color, Vector3.new(0, 2, 0), Enum.Material.Wood, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	newPart(model, "Crown", Vector3.new(0.5, 2.8, 2.8), Color3.fromRGB(255, 210, 60), Vector3.new(0, 4.3, 0), Enum.Material.Metal, Enum.PartType.Cylinder, Vector3.new(0, 0, 90))
	for i = 1, 3 do
		local x = (i - 2) * 0.9
		newPart(model, "CrownSpike" .. i, Vector3.new(0.3, 0.8, 0.3), Color3.fromRGB(255, 210, 60), Vector3.new(x, 4.9, 0), Enum.Material.Metal)
	end
	newPart(model, "Jewel", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 60, 60), Vector3.new(0, 4.3, 1.45), Enum.Material.Neon, Enum.PartType.Ball)
	for i = 1, 8 do
		local a = (i - 1) * math.rad(45)
		newPart(model, "Halo" .. i, Vector3.new(0.35, 0.35, 0.35), Color3.fromRGB(255, 215, 0), Vector3.new(0, 4.3 + 2.3 * math.sin(a), 2.3 * math.cos(a)), Enum.Material.Neon, Enum.PartType.Ball)
	end
	local armL = newPart(model, "ArmL", Vector3.new(0.35, 2, 0.35), Color3.fromRGB(255, 210, 60), Vector3.new(-1.5, 2, 0.3), Enum.Material.Metal)
	local armR = newPart(model, "ArmR", Vector3.new(0.35, 2, 0.35), Color3.fromRGB(255, 210, 60), Vector3.new(1.5, 2, 0.3), Enum.Material.Metal)
	markAnimated(armL, -1.5, 2, 0.3)
	markAnimated(armR, 1.5, 2, 0.3)
	local hammerL = newPart(model, "HammerL", Vector3.new(0.2, 1.3, 0.2), Color3.fromRGB(255, 210, 60), Vector3.new(-1.7, 3.2, 0.3), Enum.Material.Metal, Enum.PartType.Cylinder)
	local hammerR = newPart(model, "HammerR", Vector3.new(0.2, 1.3, 0.2), Color3.fromRGB(255, 210, 60), Vector3.new(1.7, 3.2, 0.3), Enum.Material.Metal, Enum.PartType.Cylinder)
	markAnimated(hammerL, -1.7, 3.2, 0.3)
	markAnimated(hammerR, 1.7, 3.2, 0.3)
	local hammerHeadL = newPart(model, "HammerHeadL", Vector3.new(0.7, 0.5, 0.5), Color3.fromRGB(255, 210, 60), Vector3.new(-1.85, 3.85, 0.3), Enum.Material.Metal)
	local hammerHeadR = newPart(model, "HammerHeadR", Vector3.new(0.7, 0.5, 0.5), Color3.fromRGB(255, 210, 60), Vector3.new(1.85, 3.85, 0.3), Enum.Material.Metal)
	markAnimated(hammerHeadL, -1.85, 3.85, 0.3)
	markAnimated(hammerHeadR, 1.85, 3.85, 0.3)
	newPart(model, "ShoulderL", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(255, 210, 60), Vector3.new(-1.7, 3.1, 0.3), Enum.Material.Metal, Enum.PartType.Ball)
	newPart(model, "ShoulderR", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(255, 210, 60), Vector3.new(1.7, 3.1, 0.3), Enum.Material.Metal, Enum.PartType.Ball)
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
-- Polish: pink translucent wings, two more headdress feathers, gold chest
-- emblem, shoulder pads, gold belt.
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
	local feather4 = newPart(model, "Feather4", Vector3.new(0.25, 1.4, 0.6), Color3.fromRGB(255, 120, 40), Vector3.new(1, 4, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, -35))
	markAnimated(feather4, 1, 4, 0)
	local feather5 = newPart(model, "Feather5", Vector3.new(0.25, 1.4, 0.6), Color3.fromRGB(60, 120, 255), Vector3.new(-1, 4, 0), Enum.Material.SmoothPlastic, nil, Vector3.new(0, 0, 35))
	markAnimated(feather5, -1, 4, 0)
	local wingL = newPart(model, "WingL", Vector3.new(2.6, 0.15, 1.6), Color3.fromRGB(255, 120, 200), Vector3.new(-1.9, 2.3, -0.9), Enum.Material.Neon, nil, Vector3.new(0, 0, 25))
	wingL.Transparency = 0.3
	local wingR = newPart(model, "WingR", Vector3.new(2.6, 0.15, 1.6), Color3.fromRGB(255, 120, 200), Vector3.new(1.9, 2.3, -0.9), Enum.Material.Neon, nil, Vector3.new(0, 0, -25))
	wingR.Transparency = 0.3
	newPart(model, "Emblem", Vector3.new(0.5, 0.5, 0.15), Color3.fromRGB(255, 210, 60), Vector3.new(1.35, 1.9, 0), Enum.Material.Metal, nil, Vector3.new(0, 0, 45))
	newPart(model, "ShoulderL", Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 210, 60), Vector3.new(-1.35, 2.7, 0), Enum.Material.Metal, Enum.PartType.Ball)
	newPart(model, "ShoulderR", Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 210, 60), Vector3.new(1.35, 2.7, 0), Enum.Material.Metal, Enum.PartType.Ball)
	newPart(model, "Belt", Vector3.new(2.7, 0.35, 2.1), Color3.fromRGB(255, 210, 60), Vector3.new(0, 1, 0), Enum.Material.Metal)
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
	gui.Size = UDim2.new(0, 150, 0, 48)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
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
	-- Accessories held in the hands (kentongan sticks, god hammers) ride
	-- the arm swing: same rotation, pivoted at the arm's base, so they
	-- stay in the hand instead of spinning in place.
	for _, pair in ipairs({ { "ArmL", "StickL" }, { "ArmL", "HammerL" }, { "ArmL", "HammerHeadL" }, { "ArmR", "StickR" }, { "ArmR", "HammerR" }, { "ArmR", "HammerHeadR" } }) do
		local arm = model:FindFirstChild(pair[1])
		local held = model:FindFirstChild(pair[2])
		if arm ~= nil and held ~= nil then
			local ax, ay, az = partBase(arm)
			local hx, hy, hz = partBase(held)
			local offset = Vector3.new(hx - ax, hy - ay, hz - az)
			held.CFrame = pivot * CFrame.new(ax, ay, az) * CFrame.Angles(swing, 0, 0) * CFrame.new(offset)
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
	local sway = math.sin(t * 1.5) * 0.15
	local hair = model:FindFirstChild("Hair")
	if hair ~= nil then
		local bx, by, bz = partBase(hair)
		hair.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, sway)
	end
	-- The flower sits in the hair, so it sways with it.
	for _, name in ipairs({ "Flower", "FlowerCenter" }) do
		local flower = model:FindFirstChild(name)
		if flower ~= nil then
			local bx, by, bz = partBase(flower)
			flower.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, sway)
		end
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
	-- name, sign, lag: the second feather layer follows at 0.7 strength.
	for _, spec in ipairs({ { "WingL", 1, 1 }, { "WingR", -1, 1 }, { "WingL2", 1, 0.7 }, { "WingR2", -1, 0.7 } }) do
		local wing = model:FindFirstChild(spec[1])
		if wing ~= nil then
			local bx, by, bz = partBase(wing)
			wing.CFrame = pivot * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, flap * spec[2] * spec[3])
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

-- Public: run one character's signature animation at the model's current
-- pivot. Used by the conveyor loop and by EconomyService for carried /
-- placed brainrots, so every character animates from the same system.
function ConveyorService.animateModel(model, entry, animT)
	local animate = ANIMATIONS[entry.animation]
	if animate == nil or model == nil then
		return
	end
	local pivot = model:GetPivot()
	local newPivot = animate(model, pivot, animT)
	if newPivot ~= pivot then
		model:PivotTo(newPivot)
	end
end

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
	model:SetAttribute("Uid", record.uid)
	model:PivotTo(CFrame.new(pathStart))
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

-- Phase 3: pause new spawns (Pasar Tumpah countdown + wave + scramble).
-- Walkers already on the bridge keep walking.
function ConveyorService.setPaused(value)
	paused = value
end

function ConveyorService.isPaused()
	return paused
end

-- Phase 3: reroute the conveyor (Pasar Tumpah step 4). The bridge
-- reverses direction each event, and the spawn / exit beams swap sides
-- so the reroute reads in the world, not only in code.
function ConveyorService.setReversed(value)
	if value == reversed then
		return
	end
	reversed = value
	if reversed then
		pathStart = Config.CONVEYOR_FINISH
		pathFinish = Config.CONVEYOR_START
	else
		pathStart = Config.CONVEYOR_START
		pathFinish = Config.CONVEYOR_FINISH
	end
	local conveyor = Workspace:FindFirstChild("Conveyor")
	if conveyor ~= nil then
		local spawnBeam = conveyor:FindFirstChild("SpawnBeam")
		local exitBeam = conveyor:FindFirstChild("ExitBeam")
		if spawnBeam ~= nil and exitBeam ~= nil then
			local pos = spawnBeam.Position
			spawnBeam.Position = exitBeam.Position
			exitBeam.Position = pos
		end
		local pairs = {
			{ "SpawnPostL", "ExitPostL" },
			{ "SpawnPostR", "ExitPostR" },
		}
		for _, pair in ipairs(pairs) do
			local a = conveyor:FindFirstChild(pair[1])
			local b = conveyor:FindFirstChild(pair[2])
			if a ~= nil and b ~= nil then
				local pos = a.Position
				a.Position = b.Position
				b.Position = pos
			end
		end
	end
end

function ConveyorService.isReversed()
	return reversed
end

-- Phase 3: disconnect-while-carrying rule. A brainrot its owner dropped
-- by leaving returns to the start of the bridge and walks again — it
-- never vanishes. The record and model come back exactly as they were.
function ConveyorService.returnToConveyor(uid)
	local record = BrainrotData.getBrainrot(uid)
	if record == nil or record.model == nil then
		return false
	end
	if active[uid] ~= nil then
		return false
	end
	record.state = "conveyor"
	record.owner = nil
	record.washPending = false
	record.model:PivotTo(CFrame.new(pathStart))
	record.model.Parent = conveyorFolder
	active[uid] = {
		uid = uid,
		model = record.model,
		entry = BrainrotCatalog.getCharacter(record.catalogId),
		distance = 0,
		animT = math.random() * 10,
	}
	return true
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
	if not paused then
		spawnTimer = spawnTimer + dt
		if spawnTimer >= Config.SPAWN_INTERVAL then
			spawnTimer = 0
			ConveyorService.spawnBrainrot()
		end
	end
	local path = pathFinish - pathStart
	local pathLength = path.Magnitude
	for uid, item in pairs(active) do
		item.distance = item.distance + Config.CONVEYOR_SPEED * dt
		item.animT = item.animT + dt
		local progress = item.distance / pathLength
		if progress >= 1 then
			despawnBrainrot(uid)
		else
			local position = pathStart + path * progress
			item.model:PivotTo(CFrame.new(position))
			ConveyorService.animateModel(item.model, item.entry, item.animT)
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
