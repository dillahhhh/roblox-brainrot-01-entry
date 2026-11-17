-- EventService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- PASAR TUMPAH, the signature flood event. Server state machine (locked
-- in concept v3):
--   1. Countdown (siren + 10s, HUD warning: conveyor + carried brainrots
--      can wash away, placed brainrots are SAFE).
--   2. Conveyor stops spawning new brainrots for now.
--   3. Wash-away list: brainrots on the conveyor + brainrots carried by
--      players who have NOT reached their base. Each is marked
--      processing IMMEDIATELY (state "washing", washPending) before the
--      wave finishes, so it can never be bought, placed, or claimed twice.
--   4. Conveyor path reroutes (direction reverses, spawn/exit beams swap).
--   5. Wave sweeps the plaza (visual + light knockback outside bases).
--   6. One crate per washed-away brainrot (1 brainrot = 1 crate; crate
--      class from the brainrot's tier).
--   7. Scramble zone active for 60s, then unclaimed crates expire.
--   8. Event ends, conveyor back to normal, spawning resumes.
-- Invariants: one event at a time (event id + phase); one brainrot one
-- owner/location; max one crate per brainrot per event; one crate one
-- claimer (unique ids, AVAILABLE / CLAIMED / EXPIRED, atomic server
-- claim with distance + status validation); event end never leaves the
-- conveyor stopped (cleanup runs even if a phase errors); re-running
-- never duplicates objects or rewards.
-- Debug trigger (Studio command bar, for the 2-player test):
--   require(game.ServerScriptService.Server.services.EventService).startEvent()
-- Written for phase 3 (19 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrainrotCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotCatalog"))
local BrainrotData = require(script.Parent:WaitForChild("BrainrotData"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local ConveyorService = require(script.Parent:WaitForChild("ConveyorService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local EventService = {}

local remotes = nil
local cratesFolder = nil
local crates = {}
local nextCrateId = 1
local washList = {}
local eventId = 0
local phase = "idle" -- "idle" | "countdown" | "wave" | "scramble"
local nextEventAt = 0
local countdownEndsAt = 0
local waveEndsAt = 0
local scrambleEndsAt = 0

-- Stall centres (from default.project.json): crates never spawn inside
-- a stall counter.
local STALL_CENTERS = {
	Vector3.new(27.7, 0, 11.5),
	Vector3.new(-11.5, 0, 27.7),
	Vector3.new(-27.7, 0, -11.5),
	Vector3.new(11.5, 0, -27.7),
}

function EventService.getPhase()
	return phase
end

function EventService.getSecondsLeft()
	local now = os.clock()
	if phase == "countdown" then
		return math.max(0, math.ceil(countdownEndsAt - now))
	elseif phase == "wave" then
		return math.max(0, math.ceil(waveEndsAt - now))
	elseif phase == "scramble" then
		return math.max(0, math.ceil(scrambleEndsAt - now))
	else
		return math.max(0, math.ceil(nextEventAt - now))
	end
end

local function broadcast()
	if remotes == nil then
		return
	end
	remotes.EventUpdate:FireAllClients({
		phase = phase,
		eventId = eventId,
		secondsLeft = EventService.getSecondsLeft(),
	})
end

local function fireEffect(kind, position, color)
	if remotes == nil then
		return
	end
	remotes.EffectEvent:FireAllClients({ kind = kind, position = position, color = color })
end

-- A carrier is safe only when standing on their own base platform
-- (within 14 studs of its centre). Standing on the base means they
-- "reached base" before the wave; anywhere else, the carried brainrot
-- washes away with them.
local function isSafeOnBase(player)
	local state = BrainrotData.getPlayer(player)
	if state == nil or state.baseId == nil then
		return false
	end
	local baseModel = BaseService.getBaseModel(state.baseId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if baseModel == nil or root == nil then
		return false
	end
	local center = baseModel:GetPivot().Position
	local delta = root.Position - center
	return Vector3.new(delta.X, 0, delta.Z).Magnitude < 14
end

-- Step 3: build the wash list and mark every entry processing NOW, in
-- one synchronous pass (no yield between check and mark). Conveyor
-- walkers leave the active list; carried brainrots leave their owner's
-- hands. Placed brainrots are never touched: they are ALWAYS safe.
local function buildWashList()
	local list = {}
	for _, item in ipairs(ConveyorService.getActive()) do
		local model = ConveyorService.removeFromConveyor(item.uid)
		if model ~= nil then
			local record = BrainrotData.getBrainrot(item.uid)
			if record ~= nil then
				record.state = "washing"
				record.washPending = true
				table.insert(list, { uid = item.uid, model = model })
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local state = BrainrotData.getPlayer(player)
		if state ~= nil and state.carrying ~= nil then
			local record = BrainrotData.getBrainrot(state.carrying)
			if record ~= nil and record.state == "carried" then
				if not isSafeOnBase(player) then
					local uid = state.carrying
					state.carrying = nil
					EconomyService.clearCarriedAnim(uid)
					record.state = "washing"
					record.washPending = true
					table.insert(list, { uid = uid, model = record.model })
				end
			end
		end
	end
	return list
end

-- Step 5: a translucent wall sweeps the plaza, and everyone not
-- standing on their base gets a light knockback in the wave's direction.
local function runWave()
	local wave = Instance.new("Part")
	wave.Name = "FloodWave"
	wave.Size = Vector3.new(6, 14, 170)
	wave.Color = Color3.fromRGB(40, 140, 255)
	wave.Material = Enum.Material.Glass
	wave.Transparency = 0.35
	wave.Anchored = true
	wave.CanCollide = false
	wave.CFrame = CFrame.new(-85, 7, 0)
	wave.Parent = Workspace
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") or nil
		if root ~= nil and not isSafeOnBase(player) then
			root.AssemblyLinearVelocity = Vector3.new(25, 8, 0)
		end
	end
	fireEffect("wave", Vector3.new(0, 6, 0), Color3.fromRGB(40, 140, 255))
	local startTime = os.clock()
	while os.clock() - startTime < Config.WAVE_DURATION do
		local t = (os.clock() - startTime) / Config.WAVE_DURATION
		wave.CFrame = CFrame.new(-85 + t * 170, 7, 0)
		task.wait(0.05)
	end
	wave:Destroy()
end

-- Crate class from tier (concept v3): Pasar = Common-Rare (near bases),
-- Pedagang = Rare-Epic-Legendary (mid plaza), Tumpah = Epic-Mythic
-- (small chance for Epic, always for Mythic/God — far scramble zone only).
local function classForTier(tier)
	if tier <= 2 then
		return "Pasar"
	end
	if tier == 3 then
		if math.random() <= 0.25 then
			return "Tumpah"
		end
		return "Pedagang"
	end
	if tier == 4 then
		return "Pedagang"
	end
	return "Tumpah"
end

local function cratePosition(class)
	local pos = Vector3.new(0, 0, 0)
	for _ = 1, 4 do
		local candidate = nil
		if class == "Pasar" then
			local angle = math.random() * math.pi * 2
			local r = 42 + math.random() * 10
			candidate = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		elseif class == "Pedagang" then
			local angle = math.random() * math.pi * 2
			local r = 18 + math.random() * 14
			candidate = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		else
			local corner = Config.SCRAMBLE_CORNERS[math.random(1, #Config.SCRAMBLE_CORNERS)]
			candidate = corner + Vector3.new((math.random() - 0.5) * 12, 0, (math.random() - 0.5) * 12)
		end
		pos = candidate
		local blocked = false
		for _, stall in ipairs(STALL_CENTERS) do
			if (candidate - stall).Magnitude < 7 then
				blocked = true
				break
			end
		end
		if not blocked then
			break
		end
	end
	return pos
end

local function buildCrateModel(crateId, class, record)
	local color = Config.CRATE_COLORS[class]
	local tier = BrainrotCatalog.getTier(record.tier)
	local rate = record.rate * record.mutationMult
	local model = Instance.new("Model")
	model.Name = "Crate" .. crateId
	local base = Instance.new("Part")
	base.Name = "CrateBase"
	base.Size = Vector3.new(3.5, 2.5, 3.5)
	base.Color = Color3.fromRGB(140, 100, 50)
	base.Material = Enum.Material.Wood
	base.Anchored = true
	base.CanCollide = true
	base.Position = Vector3.new(0, 1.8, 0)
	base.Parent = model
	local lid = Instance.new("Part")
	lid.Name = "CrateLid"
	lid.Size = Vector3.new(3.7, 0.8, 3.7)
	lid.Color = Color3.fromRGB(110, 75, 35)
	lid.Material = Enum.Material.Wood
	lid.Anchored = true
	lid.CanCollide = false
	lid.Position = Vector3.new(0, 3.4, 0)
	lid.Parent = model
	local trim = Instance.new("Part")
	trim.Name = "CrateTrim"
	trim.Size = Vector3.new(3.7, 0.3, 3.7)
	trim.Color = color
	trim.Material = Enum.Material.Neon
	trim.Anchored = true
	trim.CanCollide = false
	trim.Position = Vector3.new(0, 3, 0)
	trim.Parent = model
	local light = Instance.new("PointLight")
	light.Name = "CrateLight"
	light.Color = color
	light.Brightness = 2
	light.Range = 10
	light.Parent = base
	local gui = Instance.new("BillboardGui")
	gui.Name = "CrateLabel"
	gui.Size = UDim2.new(0, 200, 0, 64)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = base
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	local mutationText = ""
	if record.mutation ~= nil then
		mutationText = record.mutation .. " "
	end
	label.Text = "Peti " .. class .. "\n" .. mutationText .. record.name .. "\n" .. tier.name .. "  $" .. rate .. "/s"
	label.Parent = gui
	model.PrimaryPart = base
	model:SetAttribute("CrateId", crateId)
	return model
end

-- Step 6: one crate per washed-away brainrot. The old model is
-- destroyed only after its crate exists, so the brainrot is never in
-- two places and never in none.
local function createCrates()
	for _, washed in ipairs(washList) do
		local record = BrainrotData.getBrainrot(washed.uid)
		if record ~= nil then
			local class = classForTier(record.tier)
			local crateId = nextCrateId
			nextCrateId = nextCrateId + 1
			local model = buildCrateModel(crateId, class, record)
			local pos = cratePosition(class)
			model:PivotTo(CFrame.new(pos))
			model.Parent = cratesFolder
			record.state = "crate"
			record.washPending = false
			crates[crateId] = {
				id = crateId,
				uid = washed.uid,
				class = class,
				status = "AVAILABLE",
				model = model,
				position = pos,
				eventId = eventId,
			}
			if washed.model ~= nil then
				washed.model:Destroy()
			end
			fireEffect("crate", pos + Vector3.new(0, 3, 0), Config.CRATE_COLORS[class])
		end
	end
end

-- Step 7 end: unclaimed crates expire; their brainrots are gone for
-- good (they were never owned by anyone at that point).
local function expireCrates()
	for crateId, crate in pairs(crates) do
		if crate.status == "AVAILABLE" then
			crate.status = "EXPIRED"
			local record = BrainrotData.getBrainrot(crate.uid)
			if record ~= nil then
				record.state = "gone"
				record.owner = nil
			end
			if crate.model ~= nil then
				crate.model:Destroy()
			end
		end
		crates[crateId] = nil
	end
end

-- A phase that fails must never leave the conveyor stopped or a
-- brainrot stuck washing: crates expire, washing brainrots return to
-- the conveyor, the phase goes idle, the timer restarts.
function EventService.cleanupAfterError()
	expireCrates()
	for _, washed in ipairs(washList) do
		local record = BrainrotData.getBrainrot(washed.uid)
		if record ~= nil and record.state == "washing" then
			record.washPending = false
			if washed.model ~= nil then
				ConveyorService.returnToConveyor(washed.uid)
			else
				record.state = "gone"
				record.owner = nil
			end
		end
	end
	washList = {}
	phase = "idle"
	nextEventAt = os.clock() + Config.EVENT_INTERVAL
	ConveyorService.setPaused(false)
	broadcast()
end

local function runEvent()
	-- 1. Countdown: siren + 10s. Players can still buy / dash home.
	phase = "countdown"
	countdownEndsAt = os.clock() + Config.EVENT_COUNTDOWN
	ConveyorService.setPaused(true)
	fireEffect("siren", Vector3.new(0, 6, 0), Color3.fromRGB(255, 60, 60))
	broadcast()
	task.wait(Config.EVENT_COUNTDOWN)
	-- 3. Wash list, marked processing immediately.
	washList = buildWashList()
	-- 4. Conveyor reroutes to the next configuration.
	ConveyorService.setReversed(not ConveyorService.isReversed())
	-- 5. Wave sweeps the plaza.
	phase = "wave"
	waveEndsAt = os.clock() + Config.WAVE_DURATION
	broadcast()
	runWave()
	-- 6. Crates from the wash list.
	phase = "scramble"
	scrambleEndsAt = os.clock() + Config.SCRAMBLE_DURATION
	createCrates()
	broadcast()
	-- 7. Scramble window (claims arrive through ClaimCrate).
	while os.clock() < scrambleEndsAt do
		task.wait(1)
		broadcast()
	end
	expireCrates()
	-- 8. Event ends, conveyor back to normal, spawning resumes.
	washList = {}
	phase = "idle"
	nextEventAt = os.clock() + Config.EVENT_INTERVAL
	ConveyorService.setPaused(false)
	broadcast()
end

-- Starts one event. Returns false when one is already running (one
-- event at a time, by event id + phase). Callable from the Studio
-- command bar for testing: require(...EventService).startEvent()
function EventService.startEvent()
	if phase ~= "idle" then
		return false
	end
	eventId = eventId + 1
	task.spawn(function()
		local ok, err = pcall(runEvent)
		if not ok then
			warn("[EventService] event " .. eventId .. " failed: " .. tostring(err))
			EventService.cleanupAfterError()
		end
	end)
	return true
end

-- Claim a crate: every check runs first, then the claim flips to
-- CLAIMED in one synchronous step — no yield between check and set,
-- so two players can never claim the same crate. The brainrot becomes
-- carried (the player must bring it home to their base).
function EventService.claimCrate(player, crateId)
	local crate = crates[crateId]
	if crate == nil then
		return false, "Peti itu sudah tidak ada."
	end
	if crate.status ~= "AVAILABLE" then
		return false, "Peti itu sudah diambil orang lain."
	end
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return false, "State pemain tidak ditemukan."
	end
	if state.carrying ~= nil then
		return false, "Kamu sudah membawa brainrot. Taruh dulu di base."
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if root == nil then
		return false, "Karakter belum siap."
	end
	if crate.model == nil or crate.model.PrimaryPart == nil then
		return false, "Peti tidak ditemukan."
	end
	if (root.Position - crate.model.PrimaryPart.Position).Magnitude > Config.CRATE_CLAIM_DISTANCE then
		return false, "Terlalu jauh dari peti."
	end
	local record = BrainrotData.getBrainrot(crate.uid)
	if record == nil or record.state ~= "crate" then
		return false, "Isi peti sudah hilang."
	end
	-- All checks passed: claim atomically.
	crate.status = "CLAIMED"
	local entry = BrainrotCatalog.getCharacter(record.catalogId)
	local mutation = BrainrotCatalog.getMutation(record.mutation)
	local model = ConveyorService.buildCharacterModel(entry, mutation)
	model:SetAttribute("Uid", record.uid)
	local crateModel = crate.model
	local cratePos = crate.position
	local crateClass = crate.class
	crates[crateId] = nil
	if crateModel ~= nil then
		crateModel:Destroy()
	end
	if not EconomyService.giveCarried(player, crate.uid, model) then
		model:Destroy()
		return false, "Gagal mengambil isi peti."
	end
	EconomyService.sendState(player)
	fireEffect("crate", cratePos + Vector3.new(0, 3, 0), Config.CRATE_COLORS[crateClass])
	return true, "Kamu membuka Peti " .. crateClass .. " — dapat " .. record.name .. "! Bawa ke base!"
end

local function eventLoop()
	while true do
		task.wait(1)
		if phase == "idle" and os.clock() >= nextEventAt then
			EventService.startEvent()
		end
		broadcast()
	end
end

function EventService.init(remoteFolder)
	remotes = remoteFolder
	cratesFolder = Workspace:FindFirstChild("ScrambleCrates")
	if cratesFolder == nil then
		cratesFolder = Instance.new("Folder")
		cratesFolder.Name = "ScrambleCrates"
		cratesFolder.Parent = Workspace
	end
	remotes.ClaimCrate.OnServerInvoke = function(player, crateId)
		return EventService.claimCrate(player, crateId)
	end
	nextEventAt = os.clock() + Config.EVENT_INTERVAL
	task.spawn(eventLoop)
end

return EventService
