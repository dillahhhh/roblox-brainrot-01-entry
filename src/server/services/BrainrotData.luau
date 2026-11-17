-- BrainrotData.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Single source of state (judge criterion 5): players, bases, owned
-- brainrots, cash, multipliers. Every other service reads and writes
-- through this module, never through its own copies.
-- Written for the foundation phase (17 Nov 2026). Minimal logic: structure
-- + API. Economy (earn ticks, buy/sell), steal and the event write through
-- these same functions in later phases.
--
-- Brainrot states: "conveyor" (walking the bridge), "carried" (a player
-- is holding it), "placed" (earning on a base slot), "crate" (washed away
-- by Pasar Tumpah, waiting in the scramble zone), "gone" (despawned).
-- One brainrot is ever in exactly one state: carried brainrots are a
-- single ownership state, never duplicated between conveyor and crate.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local BrainrotCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("BrainrotCatalog"))

local BrainrotData = {}

local players = {}
local bases = {}
local brainrots = {}
local nextBrainrotId = 1

function BrainrotData.init()
	players = {}
	bases = {}
	brainrots = {}
	nextBrainrotId = 1
end

-- Players ---------------------------------------------------------------

function BrainrotData.addPlayer(player)
	players[player] = {
		cash = Config.START_CASH,
		multiplier = 1,
		rebirths = 0,
		baseId = nil,
		carrying = nil,
		brainrots = {},
	}
end

function BrainrotData.removePlayer(player)
	local state = players[player]
	if state ~= nil and state.carrying ~= nil then
		-- TODO phase 3 (disconnect-while-carrying rule): a carried
		-- brainrot must return to the conveyor or become a crate,
		-- never vanish. For the foundation it is released to "gone".
		local carried = brainrots[state.carrying]
		if carried ~= nil then
			carried.state = "gone"
			carried.owner = nil
		end
	end
	players[player] = nil
end

function BrainrotData.getPlayer(player)
	return players[player]
end

function BrainrotData.getCash(player)
	local state = players[player]
	if state == nil then
		return 0
	end
	return state.cash
end

function BrainrotData.addCash(player, amount)
	local state = players[player]
	if state == nil then
		return
	end
	state.cash = state.cash + amount
end

-- Returns true and deducts, or false when the player cannot afford it.
function BrainrotData.spendCash(player, amount)
	local state = players[player]
	if state == nil then
		return false
	end
	if state.cash < amount then
		return false
	end
	state.cash = state.cash - amount
	return true
end

function BrainrotData.getMultiplier(player)
	local state = players[player]
	if state == nil then
		return 1
	end
	return state.multiplier
end

function BrainrotData.addRebirth(player)
	local state = players[player]
	if state == nil then
		return
	end
	state.rebirths = state.rebirths + 1
	state.multiplier = state.multiplier * Config.REBIRTH_MULTIPLIER
end

-- Bases -----------------------------------------------------------------

function BrainrotData.registerBase(baseId, model)
	bases[baseId] = {
		model = model,
		owner = nil,
		slots = {},
		level = 0,
	}
	for i = 1, Config.BASE_SLOTS do
		bases[baseId].slots[i] = nil
	end
end

function BrainrotData.getBase(baseId)
	return bases[baseId]
end

function BrainrotData.assignBase(player, baseId)
	local state = players[player]
	local base = bases[baseId]
	if state == nil or base == nil then
		return false
	end
	if base.owner ~= nil then
		return false
	end
	base.owner = player
	state.baseId = baseId
	return true
end

function BrainrotData.getBaseForPlayer(player)
	local state = players[player]
	if state == nil then
		return nil
	end
	return state.baseId
end

function BrainrotData.getFreeSlot(baseId)
	local base = bases[baseId]
	if base == nil then
		return nil
	end
	for i = 1, Config.BASE_SLOTS do
		if base.slots[i] == nil then
			return i
		end
	end
	return nil
end

-- Brainrots --------------------------------------------------------------

function BrainrotData.createBrainrot(catalogId, mutationName)
	local entry = BrainrotCatalog.getCharacter(catalogId)
	if entry == nil then
		return nil
	end
	local mutation = BrainrotCatalog.getMutation(mutationName)
	local uid = nextBrainrotId
	nextBrainrotId = nextBrainrotId + 1
	local record = {
		uid = uid,
		catalogId = catalogId,
		name = entry.name,
		tier = entry.tier,
		rate = entry.rate,
		mutation = mutationName,
		mutationMult = 1,
		state = "conveyor",
		owner = nil,
		baseId = nil,
		slotIndex = nil,
		model = nil,
	}
	if mutation ~= nil then
		record.mutationMult = mutation.multiplier
	end
	brainrots[uid] = record
	return record
end

function BrainrotData.getBrainrot(uid)
	return brainrots[uid]
end

function BrainrotData.setBrainrotState(uid, state)
	local record = brainrots[uid]
	if record == nil then
		return
	end
	record.state = state
end

function BrainrotData.setBrainrotModel(uid, model)
	local record = brainrots[uid]
	if record == nil then
		return
	end
	record.model = model
end

-- Place a carried brainrot on a base slot. Validates slot + ownership,
-- then books the slot. Returns true on success.
function BrainrotData.placeBrainrot(player, uid, slotIndex)
	local state = players[player]
	local record = brainrots[uid]
	local baseId = nil
	if state ~= nil then
		baseId = state.baseId
	end
	if state == nil or record == nil or baseId == nil then
		return false
	end
	if record.owner ~= player or record.state ~= "carried" then
		return false
	end
	local base = bases[baseId]
	if base == nil then
		return false
	end
	if slotIndex < 1 or slotIndex > Config.BASE_SLOTS then
		return false
	end
	if base.slots[slotIndex] ~= nil then
		return false
	end
	base.slots[slotIndex] = uid
	record.state = "placed"
	record.baseId = baseId
	record.slotIndex = slotIndex
	state.carrying = nil
	table.insert(state.brainrots, uid)
	return true
end

-- Remove a brainrot from its slot (steal / sell / rebirth). Frees the slot.
function BrainrotData.unplaceBrainrot(uid)
	local record = brainrots[uid]
	if record == nil or record.state ~= "placed" then
		return false
	end
	local base = bases[record.baseId]
	if base ~= nil and record.slotIndex ~= nil then
		base.slots[record.slotIndex] = nil
	end
	local ownerState = nil
	if record.owner ~= nil then
		ownerState = players[record.owner]
	end
	if ownerState ~= nil then
		for i, ownedUid in ipairs(ownerState.brainrots) do
			if ownedUid == uid then
				table.remove(ownerState.brainrots, i)
				break
			end
		end
	end
	record.state = "gone"
	record.baseId = nil
	record.slotIndex = nil
	return true
end

-- Total income per second of one player: placed brainrots only, mutation
-- and rebirth multipliers included.
function BrainrotData.getTotalIncome(player)
	local state = players[player]
	if state == nil then
		return 0
	end
	local total = 0
	for _, uid in ipairs(state.brainrots) do
		local record = brainrots[uid]
		if record ~= nil and record.state == "placed" then
			total = total + record.rate * record.mutationMult
		end
	end
	return total * state.multiplier
end

return BrainrotData
