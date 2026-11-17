-- StealService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Steal, base lock, slap. All server-authoritative: the client only
-- asks, every check (lock, ownership, distance, carrying) runs here,
-- and every change goes through BrainrotData + EconomyService.
--   lockBase(player)  -- 30s lock, 60s cooldown after it ends
--   trySteal(thief, victimName, uid)  -- real server transaction:
--     ownership transfer + lock check; never while the victim's base
--     is locked, never while the thief is already carrying one
--   getStealTargets(player)  -- placed brainrots of other players near
--     the caller, for the client's [E] prompt
--   slap: a "Tamparan" Tool in every player's backpack; clicking a
--     nearby player knocks them back (light knockback, 3s cooldown,
--     anti-spam). The tool is cloned per player on spawn, so Activated
--     is connected per clone through Backpack.ChildAdded.
-- Written for phase 3 (19 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrainrotData = require(script.Parent:WaitForChild("BrainrotData"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local StealService = {}

local remotes = nil
-- baseId -> {lockedUntil, cooldownUntil} (os.clock seconds)
local locks = {}
-- attacker -> last slap time (os.clock), cooldown + anti-spam
local lastSlap = {}

local function now()
	return os.clock()
end

function StealService.isBaseLocked(baseId)
	local lock = locks[baseId]
	if lock == nil then
		return false
	end
	return lock.lockedUntil > now()
end

-- Lock: 30s of protection, then a 60s cooldown before it can be used
-- again. Returns (success, message, lockRemaining, cooldownRemaining)
-- so the HUD button can count down locally; the server enforces.
function StealService.lockBase(player)
	local state = BrainrotData.getPlayer(player)
	if state == nil or state.baseId == nil then
		return false, "Kamu belum punya base.", 0, 0
	end
	local lock = locks[state.baseId]
	if lock ~= nil and lock.cooldownUntil > now() then
		local remaining = math.ceil(lock.cooldownUntil - now())
		return false, "Kunci base cooldown: " .. remaining .. " dtk lagi.", 0, remaining
	end
	if lock ~= nil and lock.lockedUntil > now() then
		local remaining = math.ceil(lock.lockedUntil - now())
		return false, "Base sudah terkunci: " .. remaining .. " dtk lagi.", remaining, 0
	end
	locks[state.baseId] = {
		lockedUntil = now() + Config.LOCK_DURATION,
		cooldownUntil = now() + Config.LOCK_DURATION + Config.LOCK_COOLDOWN,
	}
	BaseService.setLockVisual(state.baseId, true)
	return true, "Base terkunci 30 dtk! Tidak ada yang bisa mencuri.", Config.LOCK_DURATION, Config.LOCK_COOLDOWN
end

-- Stealable brainrots near the caller: placed, owned by someone else,
-- model present. The client shows the nearest as an [E] prompt; the
-- server re-validates everything in trySteal.
function StealService.getStealTargets(player)
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return {}
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if root == nil then
		return {}
	end
	local list = {}
	for _, record in ipairs(BrainrotData.getPlacedBrainrots()) do
		if record.owner ~= nil and record.owner ~= player and record.model ~= nil and record.model.PrimaryPart ~= nil then
			local dist = (root.Position - record.model.PrimaryPart.Position).Magnitude
			if dist <= Config.STEAL_TARGET_RANGE then
				table.insert(list, {
					uid = record.uid,
					name = record.name,
					victim = record.owner.Name,
					position = record.model.PrimaryPart.Position,
				})
			end
		end
	end
	return list
end

-- Steal: the brainrot leaves the victim's slot and becomes carried by
-- the thief, who must bring it home to their own base. One brainrot,
-- one owner, one location: the slot is freed first (removeFromSlot),
-- then the single ownership state moves (giveCarried).
function StealService.trySteal(thief, victimName, uid)
	local thiefState = BrainrotData.getPlayer(thief)
	if thiefState == nil then
		return false, "State pemain tidak ditemukan."
	end
	if thiefState.carrying ~= nil then
		return false, "Kamu sudah membawa brainrot. Taruh dulu di base."
	end
	if typeof(victimName) ~= "string" then
		return false, "Korban tidak dikenal."
	end
	local victim = Players:FindFirstChild(victimName)
	if victim == nil or victim == thief then
		return false, "Korban tidak ditemukan."
	end
	local record = BrainrotData.getBrainrot(uid)
	if record == nil or record.state ~= "placed" or record.owner ~= victim then
		return false, "Brainrot itu sudah tidak di base korban."
	end
	local victimState = BrainrotData.getPlayer(victim)
	if victimState == nil or victimState.baseId == nil then
		return false, "Base korban tidak ditemukan."
	end
	if StealService.isBaseLocked(victimState.baseId) then
		return false, "Base " .. victim.Name .. " sedang TERKUNCI! Coba lagi nanti."
	end
	local character = thief.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if root == nil then
		return false, "Karakter belum siap."
	end
	if record.model == nil or record.model.PrimaryPart == nil then
		return false, "Brainrot tidak ditemukan."
	end
	if (root.Position - record.model.PrimaryPart.Position).Magnitude > Config.STEAL_DISTANCE then
		return false, "Terlalu jauh dari brainrot itu."
	end
	EconomyService.unregisterPlaced(uid)
	if not BrainrotData.removeFromSlot(uid) then
		return false, "Gagal mencuri brainrot itu."
	end
	local stealPos = record.model.PrimaryPart.Position
	if not EconomyService.giveCarried(thief, uid, nil) then
		return false, "Gagal mencuri brainrot itu."
	end
	EconomyService.sendState(thief)
	EconomyService.sendState(victim)
	if remotes ~= nil then
		remotes.EffectEvent:FireAllClients({
			kind = "steal",
			position = stealPos,
			color = Color3.fromRGB(255, 80, 80),
		})
	end
	return true, "Kamu mencuri " .. record.name .. " dari " .. victim.Name .. "! Cepat bawa ke base!"
end

-- Slap: light knockback on the nearest other player in range. Cooldown
-- 3s per attacker; the check and the timestamp set run synchronously,
-- so spamming the click cannot queue extra slaps.
local function onSlapActivated(attacker)
	local last = lastSlap[attacker]
	if last ~= nil and now() - last < Config.SLAP_COOLDOWN then
		return
	end
	local character = attacker.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if root == nil then
		return
	end
	local bestTarget = nil
	local bestDist = Config.SLAP_RANGE
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= attacker then
			local targetCharacter = player.Character
			local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart") or nil
			if targetRoot ~= nil then
				local dist = (root.Position - targetRoot.Position).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestTarget = player
				end
			end
		end
	end
	if bestTarget == nil then
		return
	end
	local targetCharacter = bestTarget.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart") or nil
	if targetRoot == nil then
		return
	end
	lastSlap[attacker] = now()
	local away = targetRoot.Position - root.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, 1)
	end
	targetRoot.AssemblyLinearVelocity = away.Unit * Config.SLAP_FORCE + Vector3.new(0, 8, 0)
	if remotes ~= nil then
		remotes.EffectEvent:FireClient(bestTarget, {
			kind = "slap",
			position = targetRoot.Position,
			color = Color3.fromRGB(255, 120, 120),
		})
	end
end

local function connectSlapTool(tool)
	if tool.Name ~= "Tamparan" then
		return
	end
	tool.Activated:Connect(function()
		local player = Players:GetPlayerFromCharacter(tool.Parent)
		if player ~= nil then
			onSlapActivated(player)
		end
	end)
end

local function giveSlapTool(player)
	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(connectSlapTool)
	for _, child in ipairs(backpack:GetChildren()) do
		connectSlapTool(child)
	end
end

-- Clear expired lock visuals once a second (the lock itself is checked
-- live in isBaseLocked; this only cleans the sign).
local function lockSweep()
	while true do
		task.wait(1)
		for baseId, lock in pairs(locks) do
			if lock.lockedUntil <= now() then
				BaseService.setLockVisual(baseId, false)
			end
		end
	end
end

function StealService.init(remoteFolder)
	remotes = remoteFolder
	remotes.LockBase.OnServerInvoke = function(player)
		return StealService.lockBase(player)
	end
	remotes.TrySteal.OnServerInvoke = function(player, victimName, uid)
		return StealService.trySteal(player, victimName, uid)
	end
	remotes.GetStealTargets.OnServerInvoke = function(player)
		return StealService.getStealTargets(player)
	end
	-- The Tamparan tool: one per player, cloned from StarterPack on
	-- spawn. Activated is connected per clone (a StarterPack original
	-- never fires for its clones).
	local tool = Instance.new("Tool")
	tool.Name = "Tamparan"
	tool.ToolTip = "Tamparan — klik pemain lain di dekatmu untuk menamparnya"
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 1.6, 1)
	handle.Color = Color3.fromRGB(200, 150, 100)
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.CanCollide = false
	handle.Parent = tool
	tool.Parent = StarterPack
	for _, player in ipairs(Players:GetPlayers()) do
		giveSlapTool(player)
	end
	Players.PlayerAdded:Connect(giveSlapTool)
	Players.PlayerRemoving:Connect(function(player)
		lastSlap[player] = nil
	end)
	task.spawn(lockSweep)
end

return StealService
