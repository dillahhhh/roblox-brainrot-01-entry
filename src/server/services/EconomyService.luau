-- EconomyService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Economy: one job. Earn ticks, buy / carry / place, sell, rebirth.
-- All server-authoritative: the client only asks through RemoteFunctions,
-- every check (cash, distance, ownership, slot, threshold) runs here,
-- and every change goes through BrainrotData. The server also pushes the
-- player's state (cash, income, owned, carrying, rebirths) to the HUD
-- after every change and once per earn tick.
-- Written for phase 2 (18 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrainrotCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotCatalog"))
local BrainrotData = require(script.Parent:WaitForChild("BrainrotData"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local ConveyorService = require(script.Parent:WaitForChild("ConveyorService"))

local EconomyService = {}

-- Sell returns half the catalog price.
local SELL_FRACTION = 0.5
-- Server-side distance checks (client only offers nearer targets; the
-- extra margin absorbs lag). A player teleporting across the map cannot
-- buy or place from afar.
local BUY_DISTANCE = 20
local PLACE_DISTANCE = 20
local CARRY_HEIGHT = 3.2

local remotes = nil
local carriedAnims = {}
local placedAnims = {}
-- Carried brainrots live in their own folder, not under
-- ConveyorBrainrots: the client's buy scan only looks at the conveyor
-- folder, so a carried brainrot never shows up as buyable.
local carriedFolder = nil

-- State payload sent to one player's HUD. Never computed on the client.
function EconomyService.getState(player)
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return nil
	end
	local owned = {}
	for _, uid in ipairs(state.brainrots) do
		local record = BrainrotData.getBrainrot(uid)
		if record ~= nil and record.state == "placed" then
			local entry = BrainrotCatalog.getCharacter(record.catalogId)
			local tier = BrainrotCatalog.getTier(record.tier)
			table.insert(owned, {
				uid = uid,
				name = record.name,
				tier = BrainrotCatalog.getTierName(record.tier),
				tierColor = tier.color,
				rate = record.rate * record.mutationMult,
				mutation = record.mutation,
				slotIndex = record.slotIndex,
				sellPrice = math.floor(entry.price * SELL_FRACTION),
			})
		end
	end
	local carrying = nil
	if state.carrying ~= nil then
		local record = BrainrotData.getBrainrot(state.carrying)
		if record ~= nil then
			carrying = { uid = record.uid, name = record.name }
		end
	end
	return {
		cash = state.cash,
		income = BrainrotData.getTotalIncome(player),
		rebirths = state.rebirths,
		multiplier = state.multiplier,
		baseId = state.baseId,
		carrying = carrying,
		owned = owned,
	}
end

function EconomyService.sendState(player)
	if remotes == nil then
		return
	end
	local payload = EconomyService.getState(player)
	if payload == nil then
		return
	end
	remotes.StateUpdate:FireClient(player, payload)
end

-- Effect broadcast. targetPlayer == nil means every client.
local function fireEffect(kind, position, color, targetPlayer)
	if remotes == nil then
		return
	end
	local payload = { kind = kind, position = position, color = color }
	if targetPlayer ~= nil then
		remotes.EffectEvent:FireClient(targetPlayer, payload)
	else
		remotes.EffectEvent:FireAllClients(payload)
	end
end

-- Buy: cash check -> spend -> off the conveyor -> carried (one ownership
-- state: the brainrot is nowhere else now). Returns (success, message).
function EconomyService.tryBuy(player, uid)
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return false, "State pemain tidak ditemukan."
	end
	if state.carrying ~= nil then
		return false, "Kamu sudah membawa satu brainrot. Taruh dulu di base."
	end
	local record = BrainrotData.getBrainrot(uid)
	if record == nil or record.state ~= "conveyor" then
		return false, "Brainrot itu sudah tidak di conveyor."
	end
	if record.washPending then
		return false, "Brainrot itu sedang hanyut — gelombang datang!"
	end
	local entry = BrainrotCatalog.getCharacter(record.catalogId)
	if entry == nil then
		return false, "Brainrot tidak dikenal."
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if root == nil then
		return false, "Karakter belum siap."
	end
	if record.model == nil or record.model.PrimaryPart == nil then
		return false, "Brainrot tidak ditemukan."
	end
	if (root.Position - record.model.PrimaryPart.Position).Magnitude > BUY_DISTANCE then
		return false, "Terlalu jauh dari brainrot itu."
	end
	if not BrainrotData.spendCash(player, entry.price) then
		return false, "Uang tidak cukup: butuh $" .. entry.price .. "."
	end
	local taken = ConveyorService.removeFromConveyor(uid)
	if taken == nil then
		-- Despawned between the check and the take: refund in full.
		BrainrotData.addCash(player, entry.price)
		return false, "Brainrot itu keburu pergi."
	end
	taken.Parent = carriedFolder
	record.state = "carried"
	record.owner = player
	state.carrying = uid
	carriedAnims[uid] = 0
	EconomyService.sendState(player)
	fireEffect("buy", root.Position + Vector3.new(0, 3, 0), BrainrotCatalog.getTier(record.tier).color)
	return true, "Membeli " .. entry.name .. " seharga $" .. entry.price .. ". Bawa ke base!"
end

-- Place: the carried brainrot goes on the first free slot of the
-- player's own base. The server picks the slot; the client never does.
function EconomyService.tryPlace(player)
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return false, "State pemain tidak ditemukan."
	end
	local uid = state.carrying
	if uid == nil then
		return false, "Kamu tidak membawa brainrot."
	end
	local baseId = state.baseId
	if baseId == nil then
		return false, "Kamu belum punya base."
	end
	local record = BrainrotData.getBrainrot(uid)
	if record == nil or record.model == nil then
		return false, "Brainrot yang dibawa hilang."
	end
	if record.washPending then
		return false, "Brainrot itu sedang hanyut!"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if root == nil then
		return false, "Karakter belum siap."
	end
	-- FIX (18 Nov 2026, audit fixed6): the client offers place near ANY
	-- free slot pad (12 studs), but the server used to measure distance
	-- to the FIRST free slot only — up to ~18 studs from the pad the
	-- player stands by, so a shown [E] prompt could be refused with
	-- "Terlalu jauh dari base." Measure the NEAREST free slot instead,
	-- the same one the client's prompt is standing by.
	local base = BrainrotData.getBase(baseId)
	local slotIndex = nil
	local slotCFrame = nil
	local bestDist = nil
	if base ~= nil then
		for i = 1, Config.BASE_SLOTS do
			if base.slots[i] == nil then
				local cf = BaseService.getSlotCFrame(baseId, i)
				if cf ~= nil then
					local d = (root.Position - cf.Position).Magnitude
					if bestDist == nil or d < bestDist then
						bestDist = d
						slotIndex = i
						slotCFrame = cf
					end
				end
			end
		end
	end
	if slotIndex == nil then
		return false, "Base penuh! Jual satu brainrot dulu."
	end
	if slotCFrame == nil then
		return false, "Slot tidak ditemukan."
	end
	if bestDist > PLACE_DISTANCE then
		return false, "Terlalu jauh dari base."
	end
	if not BaseService.placeBrainrot(player, uid, slotIndex) then
		return false, "Gagal menaruh brainrot."
	end
	carriedAnims[uid] = nil
	placedAnims[uid] = {
		model = record.model,
		entry = BrainrotCatalog.getCharacter(record.catalogId),
		t = 0,
	}
	EconomyService.sendState(player)
	fireEffect("place", slotCFrame.Position, BrainrotCatalog.getTier(record.tier).color)
	return true, "Ditaruh di base! Sekarang menghasilkan $" .. (record.rate * record.mutationMult) .. "/s."
end

-- Sell: a placed brainrot back for half its catalog price. Frees the
-- slot and destroys the model; the brainrot is gone for good.
function EconomyService.sellBrainrot(player, uid)
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return false, "State pemain tidak ditemukan."
	end
	local record = BrainrotData.getBrainrot(uid)
	if record == nil or record.state ~= "placed" or record.owner ~= player then
		return false, "Brainrot itu bukan milikmu atau tidak di base."
	end
	local entry = BrainrotCatalog.getCharacter(record.catalogId)
	if entry == nil then
		return false, "Brainrot tidak dikenal."
	end
	local sellPrice = math.floor(entry.price * SELL_FRACTION)
	local slotPosition = nil
	if record.baseId ~= nil and record.slotIndex ~= nil then
		local slotCFrame = BaseService.getSlotCFrame(record.baseId, record.slotIndex)
		if slotCFrame ~= nil then
			slotPosition = slotCFrame.Position
		end
	end
	local model = record.model
	placedAnims[uid] = nil
	BaseService.clearSlot(uid)
	if model ~= nil then
		model:Destroy()
	end
	BrainrotData.addCash(player, sellPrice)
	EconomyService.sendState(player)
	if slotPosition ~= nil then
		fireEffect("sell", slotPosition, Color3.fromRGB(255, 210, 60))
	end
	return true, "Terjual " .. record.name .. " +$" .. sellPrice .. "."
end

-- Rebirth: ONE threshold (concept v3). Cash >= 100.000 resets cash and
-- all brainrots for a permanent x2 multiplier, stacking.
function EconomyService.tryRebirth(player)
	local state = BrainrotData.getPlayer(player)
	if state == nil then
		return false, "State pemain tidak ditemukan."
	end
	if state.cash < Config.REBIRTH_CASH then
		return false, "Butuh $" .. Config.REBIRTH_CASH .. " untuk rebirth."
	end
	local ownedCopy = {}
	for _, uid in ipairs(state.brainrots) do
		table.insert(ownedCopy, uid)
	end
	for _, uid in ipairs(ownedCopy) do
		local record = BrainrotData.getBrainrot(uid)
		local model = nil
		if record ~= nil then
			model = record.model
		end
		placedAnims[uid] = nil
		BaseService.clearSlot(uid)
		if model ~= nil then
			model:Destroy()
		end
	end
	state.brainrots = {}
	if state.carrying ~= nil then
		local record = BrainrotData.getBrainrot(state.carrying)
		if record ~= nil then
			if record.model ~= nil then
				record.model:Destroy()
			end
			record.state = "gone"
			record.owner = nil
		end
		carriedAnims[state.carrying] = nil
		state.carrying = nil
	end
	state.cash = 0
	BrainrotData.addRebirth(player)
	EconomyService.sendState(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") or nil
	if head ~= nil then
		fireEffect("rebirth", head.Position, Color3.fromRGB(255, 215, 0))
	end
	return true, "REBIRTH! Multiplier sekarang x" .. state.multiplier .. "."
end

-- Called from Main.server on PlayerRemoving, before BrainrotData forgets
-- the player. Phase 3 disconnect-while-carrying rule: the brainrot
-- returns to the conveyor, or stays with the event when it is already
-- washing (it becomes a crate). It never vanishes.
function EconomyService.releaseCarried(player)
	local state = BrainrotData.getPlayer(player)
	if state == nil or state.carrying == nil then
		return
	end
	local uid = state.carrying
	local record = BrainrotData.getBrainrot(uid)
	state.carrying = nil
	carriedAnims[uid] = nil
	if record == nil then
		return
	end
	if record.washPending then
		-- The event owns it now; it becomes a crate in the scramble zone.
		return
	end
	if record.model ~= nil then
		ConveyorService.returnToConveyor(uid)
	else
		record.state = "gone"
		record.owner = nil
	end
end

-- Phase 3 hook: hand a brainrot to a player as carried (crate claim,
-- steal). The caller validates everything first (not already carrying,
-- record + model exist); this only books the single ownership state.
-- model is optional: pass a freshly built one (crate claim), or nil to
-- reuse the record's current model (steal).
function EconomyService.giveCarried(player, uid, model)
	local state = BrainrotData.getPlayer(player)
	local record = BrainrotData.getBrainrot(uid)
	if state == nil or record == nil then
		return false
	end
	if model ~= nil then
		record.model = model
	end
	if record.model == nil then
		return false
	end
	record.model.Parent = carriedFolder
	record.state = "carried"
	record.owner = player
	record.washPending = false
	state.carrying = uid
	carriedAnims[uid] = 0
	return true
end

-- Phase 3 hook: the event clears a carried animation when its brainrot
-- is marked for washing, so the carry loop stops moving the model.
function EconomyService.clearCarriedAnim(uid)
	carriedAnims[uid] = nil
end

-- Phase 3 hook: StealService calls this when a brainrot leaves its slot
-- by stealing, so the placed-animation loop stops tracking it.
function EconomyService.unregisterPlaced(uid)
	placedAnims[uid] = nil
end

-- Earn loop: every second each placed brainrot pays rate x mutation x
-- rebirth multiplier into its owner's cash, then the HUD is pushed.
local function earnLoop()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local income = BrainrotData.getTotalIncome(player)
			if income > 0 then
				BrainrotData.addCash(player, income)
			end
			EconomyService.sendState(player)
		end
	end
end

-- Carry / placed animation loop: carried models hover above the owner's
-- head (anchored parts moved by PivotTo, never welded), placed models
-- keep their signature animation on their slot. One Heartbeat, one
-- animation system (ConveyorService.animateModel).
local function updateCarried(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local state = BrainrotData.getPlayer(player)
		if state ~= nil and state.carrying ~= nil then
			local record = BrainrotData.getBrainrot(state.carrying)
			local character = player.Character
			local head = character and character:FindFirstChild("Head") or nil
			if record ~= nil and record.model ~= nil and head ~= nil then
				local entry = BrainrotCatalog.getCharacter(record.catalogId)
				carriedAnims[record.uid] = (carriedAnims[record.uid] or 0) + dt
				local target = head.CFrame * CFrame.new(0, CARRY_HEIGHT, 0)
				record.model:PivotTo(target)
				if entry ~= nil then
					ConveyorService.animateModel(record.model, entry, carriedAnims[record.uid])
				end
			end
		end
	end
	for uid, anim in pairs(placedAnims) do
		local record = BrainrotData.getBrainrot(uid)
		if record ~= nil and record.model ~= nil and record.state == "placed" then
			anim.t = anim.t + dt
			ConveyorService.animateModel(anim.model, anim.entry, anim.t)
		else
			placedAnims[uid] = nil
		end
	end
end

function EconomyService.init(remoteFolder)
	remotes = remoteFolder
	carriedFolder = Workspace:FindFirstChild("CarriedBrainrots")
	if carriedFolder == nil then
		carriedFolder = Instance.new("Folder")
		carriedFolder.Name = "CarriedBrainrots"
		carriedFolder.Parent = Workspace
	end
	remotes.BuyBrainrot.OnServerInvoke = function(player, uid)
		return EconomyService.tryBuy(player, uid)
	end
	remotes.PlaceBrainrot.OnServerInvoke = function(player)
		return EconomyService.tryPlace(player)
	end
	remotes.SellBrainrot.OnServerInvoke = function(player, uid)
		return EconomyService.sellBrainrot(player, uid)
	end
	remotes.Rebirth.OnServerInvoke = function(player)
		return EconomyService.tryRebirth(player)
	end
	remotes.GetState.OnServerInvoke = function(player)
		return EconomyService.getState(player)
	end
	RunService.Heartbeat:Connect(updateCarried)
	task.spawn(earnLoop)
end

return EconomyService
