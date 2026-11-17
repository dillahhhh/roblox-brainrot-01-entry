-- EffectsController.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Effects: one job. Parts-based feedback, no external assets: buy
-- sparkle, place confetti, sell puff, rebirth burst, earn tick pop,
-- screen shake. Visual only; the server decides everything that
-- matters and broadcasts effects through the EffectEvent remote.
-- Written for phase 2 (18 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EffectsController = {}

local player = Players.LocalPlayer

-- A burst of small neon parts flying out from a point, shrinking and
-- fading, then gone. Pure parts + tweens: no textures, no sounds.
local function spawnBurst(position, colors, count, speed, size, up)
	local folder = Instance.new("Folder")
	folder.Name = "EffectBurst"
	folder.Parent = Workspace
	for _ = 1, count do
		local part = Instance.new("Part")
		part.Name = "Spark"
		part.Size = Vector3.new(size, size, size)
		part.Color = colors[math.random(1, #colors)]
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = CFrame.new(position)
		part.Parent = folder
		local angle = math.random() * math.pi * 2
		local distance = speed * (0.5 + math.random() * 0.5)
		local target = position + Vector3.new(math.cos(angle) * distance, up + math.random() * 2, math.sin(angle) * distance)
		local tween = TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(target),
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1),
		})
		tween:Play()
	end
	task.delay(1, function()
		folder:Destroy()
	end)
end

function EffectsController.playBuy(position, color)
	spawnBurst(position, { color, Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 255, 255) }, 12, 4, 0.4, 2)
end

function EffectsController.playPlace(position, color)
	spawnBurst(position, { color, Color3.fromRGB(255, 215, 0), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 120, 200) }, 18, 5, 0.35, 3)
end

function EffectsController.playSell(position)
	spawnBurst(position, { Color3.fromRGB(255, 210, 60), Color3.fromRGB(255, 255, 255) }, 10, 3, 0.4, 2)
end

function EffectsController.playRebirth(position)
	spawnBurst(position, { Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 120, 200) }, 24, 6, 0.5, 4)
	EffectsController.shakeScreen(0.4)
end

-- Phase 3: Pasar Tumpah siren (red/blue flash at the plaza centre).
function EffectsController.playSiren(position)
	spawnBurst(position, { Color3.fromRGB(255, 60, 60), Color3.fromRGB(80, 160, 255), Color3.fromRGB(255, 255, 255) }, 20, 8, 0.5, 5)
	EffectsController.shakeScreen(0.3)
end

-- Phase 3: the flood wave sweeping the plaza.
function EffectsController.playWave(position)
	spawnBurst(position, { Color3.fromRGB(40, 140, 255), Color3.fromRGB(140, 220, 255), Color3.fromRGB(255, 255, 255) }, 28, 10, 0.6, 4)
	EffectsController.shakeScreen(0.6)
end

-- Phase 3: a crate appearing in the scramble zone, or being claimed.
function EffectsController.playCrate(position, color)
	spawnBurst(position, { color, Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 255, 255) }, 16, 5, 0.4, 3)
end

-- Phase 3: a steal landing on someone's base.
function EffectsController.playSteal(position)
	spawnBurst(position, { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 255, 255) }, 16, 5, 0.4, 3)
end

-- Phase 3: being slapped (fired at the victim only).
function EffectsController.playSlap(position)
	spawnBurst(position, { Color3.fromRGB(255, 120, 120), Color3.fromRGB(255, 255, 255) }, 8, 3, 0.4, 2)
	EffectsController.shakeScreen(0.3)
end

function EffectsController.playEarnTick(position)
	spawnBurst(position, { Color3.fromRGB(255, 215, 0) }, 3, 1.5, 0.3, 1.5)
end

-- Brief camera shake through Humanoid.CameraOffset: the default camera
-- script owns the CFrame, so the offset is the safe channel.
function EffectsController.shakeScreen(strength)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	if humanoid == nil then
		return
	end
	task.spawn(function()
		for _ = 1, 12 do
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.new(0, 0, 0)
	end)
end

function EffectsController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes.EffectEvent.OnClientEvent:Connect(function(payload)
		if payload == nil or payload.kind == nil or payload.position == nil then
			return
		end
		local color = payload.color or Color3.fromRGB(255, 215, 0)
		if payload.kind == "buy" then
			EffectsController.playBuy(payload.position, color)
		elseif payload.kind == "place" then
			EffectsController.playPlace(payload.position, color)
		elseif payload.kind == "sell" then
			EffectsController.playSell(payload.position)
		elseif payload.kind == "rebirth" then
			EffectsController.playRebirth(payload.position)
		elseif payload.kind == "earn" then
			EffectsController.playEarnTick(payload.position)
		elseif payload.kind == "siren" then
			EffectsController.playSiren(payload.position)
		elseif payload.kind == "wave" then
			EffectsController.playWave(payload.position)
		elseif payload.kind == "crate" then
			EffectsController.playCrate(payload.position, color)
		elseif payload.kind == "steal" then
			EffectsController.playSteal(payload.position)
		elseif payload.kind == "slap" then
			EffectsController.playSlap(payload.position)
		end
	end)
end

return EffectsController
