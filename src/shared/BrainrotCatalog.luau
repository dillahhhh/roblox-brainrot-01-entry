-- BrainrotCatalog.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- The cast: 12 original Nusantara brainrot characters on a 6-tier ladder,
-- 2 characters per tier, plus the mutation table.
-- Every character has a silhouette key (how ConveyorService builds its
-- parts-based model) and an animation key (its signature idle animation).
-- Written for the foundation phase (17 Nov 2026).

local BrainrotCatalog = {}

-- Tiers, weakest first. weight = spawn share out of 100.
BrainrotCatalog.TIERS = {
	{ name = "Common", weight = 40, color = Color3.fromRGB(200, 200, 200) },
	{ name = "Rare", weight = 25, color = Color3.fromRGB(80, 160, 255) },
	{ name = "Epic", weight = 15, color = Color3.fromRGB(180, 90, 255) },
	{ name = "Legendary", weight = 10, color = Color3.fromRGB(255, 170, 40) },
	{ name = "Mythic", weight = 6, color = Color3.fromRGB(255, 70, 120) },
	{ name = "Brainrot God", weight = 4, color = Color3.fromRGB(255, 215, 0) },
}

-- Mutations: rolled on spawn, visual + rate multiplier.
-- Roll 1-100: 1 = Rainbow, 2-4 = Diamond, 5-14 = Gold, else none.
BrainrotCatalog.MUTATIONS = {
	{ name = "Gold", multiplier = 2, color = Color3.fromRGB(255, 210, 60) },
	{ name = "Diamond", multiplier = 5, color = Color3.fromRGB(140, 220, 255) },
	{ name = "Rainbow", multiplier = 10, color = Color3.fromRGB(255, 120, 200) },
}

-- price = rate x 10, so the ladder is readable: a character pays for
-- itself in 10 seconds of income, and the next tier is always the goal.
BrainrotCatalog.CHARACTERS = {
	-- Common
	{ id = "tung_tung_sahur", name = "Tung Tung Sahur", tier = 1, rate = 5, price = 50,
		silhouette = "kentongan", animation = "beat", color = Color3.fromRGB(150, 100, 50),
		blurb = "Kentongan sahur yang tidak pernah tidur." },
	{ id = "es_teh_manis", name = "Es Teh Manis", tier = 1, rate = 8, price = 80,
		silhouette = "es_teh", animation = "slosh", color = Color3.fromRGB(230, 140, 40),
		blurb = "Segelas es teh, es batunya masih berenang." },
	-- Rare
	{ id = "kambing_garut", name = "Kambing Garut", tier = 2, rate = 25, price = 250,
		silhouette = "kambing", animation = "trot", color = Color3.fromRGB(240, 240, 240),
		blurb = "Kambing aduan, tanduknya juara." },
	{ id = "ondel_ondel", name = "Ondel-Ondel", tier = 2, rate = 40, price = 400,
		silhouette = "ondel", animation = "sway", color = Color3.fromRGB(220, 40, 40),
		blurb = "Boneka raksasa Betawi, goyangnya menular." },
	-- Epic
	{ id = "nasi_padang", name = "Nasi Padang", tier = 3, rate = 90, price = 900,
		silhouette = "nasi_padang", animation = "steam", color = Color3.fromRGB(240, 210, 90),
		blurb = "Sepiring nasi, lauknya tidak pernah habis." },
	{ id = "bajaj_biru", name = "Bajaj Biru", tier = 3, rate = 140, price = 1400,
		silhouette = "bajaj", animation = "drive", color = Color3.fromRGB(40, 120, 255),
		blurb = "Bajaj ngebut, knalpotnya ngebul." },
	-- Legendary
	{ id = "kuntilanak", name = "Kuntilanak", tier = 4, rate = 300, price = 3000,
		silhouette = "kuntilanak", animation = "float", color = Color3.fromRGB(245, 245, 245),
		blurb = "Hantu putih yang melayang, tidak pernah menyentuh tanah." },
	{ id = "tuyul_kantong", name = "Tuyul Kantong", tier = 4, rate = 450, price = 4500,
		silhouette = "tuyul", animation = "hop", color = Color3.fromRGB(120, 180, 110),
		blurb = "Bocah kecil bawa kantong uang." },
	-- Mythic
	{ id = "garuda_emas", name = "Garuda Emas", tier = 5, rate = 900, price = 9000,
		silhouette = "garuda", animation = "flap", color = Color3.fromRGB(255, 200, 40),
		blurb = "Garuda emas, sayapnya berkilau." },
	{ id = "komodo_raja", name = "Komodo Raja", tier = 5, rate = 1400, price = 14000,
		silhouette = "komodo", animation = "crawl", color = Color3.fromRGB(110, 140, 100),
		blurb = "Raja komodo, ekornya menyapu lantai." },
	-- Brainrot God
	{ id = "sang_hyang_tung_tung", name = "Sang Hyang Tung Tung", tier = 6, rate = 5000, price = 50000,
		silhouette = "sang_hyang", animation = "glow", color = Color3.fromRGB(200, 140, 60),
		blurb = "Kentongan para dewa, bermahkota emas." },
	{ id = "nusantara_prime", name = "Nusantara Prime", tier = 6, rate = 10000, price = 100000,
		silhouette = "nusantara_prime", animation = "stance", color = Color3.fromRGB(200, 60, 50),
		blurb = "Gabungan seluruh nusantara dalam satu wujud." },
}

function BrainrotCatalog.getCharacter(id)
	for _, entry in ipairs(BrainrotCatalog.CHARACTERS) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function BrainrotCatalog.getTier(tierIndex)
	return BrainrotCatalog.TIERS[tierIndex]
end

function BrainrotCatalog.getTierName(tierIndex)
	local tier = BrainrotCatalog.TIERS[tierIndex]
	if tier then
		return tier.name
	end
	return "Common"
end

-- Weighted tier roll: 1-100 against the tier weights.
function BrainrotCatalog.rollTier()
	local roll = math.random(1, 100)
	local running = 0
	for i, tier in ipairs(BrainrotCatalog.TIERS) do
		running = running + tier.weight
		if roll <= running then
			return i
		end
	end
	return 1
end

-- Pick a random character of a tier (2 per tier).
function BrainrotCatalog.rollCharacter()
	local tier = BrainrotCatalog.rollTier()
	local pool = {}
	for _, entry in ipairs(BrainrotCatalog.CHARACTERS) do
		if entry.tier == tier then
			table.insert(pool, entry)
		end
	end
	return pool[math.random(1, #pool)]
end

-- Mutation roll: 1% Rainbow, 3% Diamond, 10% Gold, else none.
function BrainrotCatalog.rollMutation()
	local roll = math.random(1, 100)
	if roll <= 1 then
		return BrainrotCatalog.MUTATIONS[3]
	elseif roll <= 4 then
		return BrainrotCatalog.MUTATIONS[2]
	elseif roll <= 14 then
		return BrainrotCatalog.MUTATIONS[1]
	end
	return nil
end

function BrainrotCatalog.getMutation(name)
	if name == nil then
		return nil
	end
	for _, mutation in ipairs(BrainrotCatalog.MUTATIONS) do
		if mutation.name == name then
			return mutation
		end
	end
	return nil
end

-- Income per second of one brainrot, mutation included.
function BrainrotCatalog.getRate(entry, mutation)
	local mult = 1
	if mutation ~= nil then
		mult = mutation.multiplier
	end
	return entry.rate * mult
end

return BrainrotCatalog
