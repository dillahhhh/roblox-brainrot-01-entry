-- HudController.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- HUD: one job. Cash + $/s, owned brainrots (click a row to sell it for
-- 50%), rarity legend, Pasar Tumpah timer label (static until phase 3's
-- EventService exposes a phase), next-tier hint, rebirth button, prompts.
-- Reads state only from the server (GetState once + StateUpdate pushes);
-- never computes income locally.
-- Written for phase 2 (18 Nov 2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BrainrotCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotCatalog"))

local HudController = {}

local player = Players.LocalPlayer
local remotes = nil
local gui = nil
local cashLabel = nil
local incomeLabel = nil
local carryingLabel = nil
local ownedRows = {}
local rowUids = {}
local promptLabel = nil
local nextLabel = nil
local rebirthButton = nil
local eventLabel = nil
local lockButton = nil
local lockUntil = 0
local lockCooldownUntil = 0
local cachedState = nil
local promptHoldUntil = 0

local REBIRTH_CASH = 100000
local MAX_ROWS = 6

-- "100000" -> "100.000" (Indonesian thousands separator).
local function formatMoney(amount)
	local text = tostring(math.floor(amount))
	local out = ""
	while #text > 3 do
		out = "." .. string.sub(text, -3) .. out
		text = string.sub(text, 1, -4)
	end
	return text .. out
end

local function newPanel(parent, name, size, position)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.Size = size
	panel.Position = position
	panel.BackgroundTransparency = 0.35
	panel.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
	panel.BorderSizePixel = 0
	panel.Parent = parent
	return panel
end

local function newLabel(parent, name, size, position, textSize, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "BrainrotHUD"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Cash panel, top-left (below Roblox's own menu buttons).
	local cashPanel = newPanel(gui, "CashPanel", UDim2.new(0, 280, 0, 76), UDim2.new(0, 12, 0, 12))
	cashLabel = newLabel(cashPanel, "Cash", UDim2.new(1, -12, 0, 42), UDim2.new(0, 6, 0, 4), 30, Color3.fromRGB(255, 215, 0))
	cashLabel.Text = "💰 $0"
	incomeLabel = newLabel(cashPanel, "Income", UDim2.new(1, -12, 0, 24), UDim2.new(0, 6, 0, 46), 16, Color3.fromRGB(180, 255, 180))
	incomeLabel.Text = "+$0/s"

	-- Carrying banner, under the cash panel.
	carryingLabel = newLabel(gui, "Carrying", UDim2.new(0, 280, 0, 30), UDim2.new(0, 12, 0, 96), 16, Color3.fromRGB(140, 220, 255))
	carryingLabel.BackgroundTransparency = 0.35
	carryingLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
	carryingLabel.Visible = false

	-- Owned list, left. Rows are buttons: click one to sell it (50%).
	local ownedPanel = newPanel(gui, "OwnedPanel", UDim2.new(0, 280, 0, 196), UDim2.new(0, 12, 0, 132))
	local ownedHeader = newLabel(ownedPanel, "Header", UDim2.new(1, -12, 0, 24), UDim2.new(0, 6, 0, 4), 15, Color3.fromRGB(255, 255, 255))
	ownedHeader.Text = "Base-ku (klik = jual 50%)"
	for i = 1, MAX_ROWS do
		local row = Instance.new("TextButton")
		row.Name = "OwnedRow" .. i
		row.Size = UDim2.new(1, -12, 0, 26)
		row.Position = UDim2.new(0, 6, 0, 30 + (i - 1) * 27)
		row.BackgroundTransparency = 0.6
		row.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
		row.BorderSizePixel = 0
		row.TextColor3 = Color3.fromRGB(255, 255, 255)
		row.TextSize = 14
		row.Font = Enum.Font.GothamBold
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = ""
		row.Visible = false
		row.Parent = ownedPanel
		ownedRows[i] = row
		rowUids[i] = nil
		row.MouseButton1Click:Connect(function()
			local uid = rowUids[i]
			if uid == nil or remotes == nil then
				return
			end
			task.spawn(function()
				local ok, success, message = pcall(function()
					return remotes.SellBrainrot:InvokeServer(uid)
				end)
				if ok then
					HudController.setPrompt(message or "", 3)
				else
					HudController.setPrompt("Gagal menghubungi server.", 3)
				end
			end)
		end)
	end

	-- Next-tier hint, under the owned list.
	nextLabel = newLabel(gui, "NextTier", UDim2.new(0, 280, 0, 30), UDim2.new(0, 12, 0, 336), 15, Color3.fromRGB(255, 220, 120))
	nextLabel.BackgroundTransparency = 0.35
	nextLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
	nextLabel.Text = "Berikutnya: ..."

	-- Rarity legend, top-right.
	local legendPanel = newPanel(gui, "LegendPanel", UDim2.new(0, 220, 0, 196), UDim2.new(1, -232, 0, 12))
	local legendHeader = newLabel(legendPanel, "Header", UDim2.new(1, -12, 0, 24), UDim2.new(0, 6, 0, 4), 15, Color3.fromRGB(255, 255, 255))
	legendHeader.Text = "Rarity"
	for i, tier in ipairs(BrainrotCatalog.TIERS) do
		local row = newLabel(legendPanel, "Tier" .. i, UDim2.new(1, -12, 0, 24), UDim2.new(0, 6, 0, 30 + (i - 1) * 27), 15, tier.color)
		row.Text = "● " .. tier.name
	end

	-- Event timer, top-centre. Phase 3: live from EventService
	-- (EventUpdate pushes phase + seconds left every second).
	local eventPanel = newPanel(gui, "EventPanel", UDim2.new(0, 300, 0, 44), UDim2.new(0.5, -150, 0, 12))
	eventLabel = newLabel(eventPanel, "Event", UDim2.new(1, -12, 0, 44), UDim2.new(0, 6, 0, 0), 16, Color3.fromRGB(140, 220, 255))
	eventLabel.TextXAlignment = Enum.TextXAlignment.Center
	eventLabel.Text = "🌊 Pasar Tumpah: ..."

	-- Prompt, bottom-centre.
	promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "Prompt"
	promptLabel.Size = UDim2.new(0, 520, 0, 40)
	promptLabel.Position = UDim2.new(0.5, -260, 1, -84)
	promptLabel.BackgroundTransparency = 0.35
	promptLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
	promptLabel.BorderSizePixel = 0
	promptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	promptLabel.TextSize = 17
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.Text = ""
	promptLabel.Visible = false
	promptLabel.Parent = gui

	-- Rebirth button, bottom-right.
	rebirthButton = Instance.new("TextButton")
	rebirthButton.Name = "RebirthButton"
	rebirthButton.Size = UDim2.new(0, 208, 0, 48)
	rebirthButton.Position = UDim2.new(1, -220, 1, -76)
	rebirthButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	rebirthButton.BorderSizePixel = 0
	rebirthButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	rebirthButton.TextSize = 15
	rebirthButton.Font = Enum.Font.GothamBold
	rebirthButton.Text = "🔄 Rebirth — butuh $100.000"
	rebirthButton.Parent = gui
	rebirthButton.MouseButton1Click:Connect(function()
		if remotes == nil then
			return
		end
		task.spawn(function()
			local ok, success, message = pcall(function()
				return remotes.Rebirth:InvokeServer()
			end)
			if ok then
				HudController.setPrompt(message or "", 4)
			else
				HudController.setPrompt("Gagal menghubungi server.", 3)
			end
		end)
	end)

	-- Lock button, bottom-left (phase 3): locks your base for 30s,
	-- then a 60s cooldown. The server enforces; the label below only
	-- counts down from what the server answered.
	lockButton = Instance.new("TextButton")
	lockButton.Name = "LockButton"
	lockButton.Size = UDim2.new(0, 208, 0, 48)
	lockButton.Position = UDim2.new(0, 12, 1, -76)
	lockButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	lockButton.BorderSizePixel = 0
	lockButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	lockButton.TextSize = 15
	lockButton.Font = Enum.Font.GothamBold
	lockButton.Text = "🔒 Kunci Base (30 dtk)"
	lockButton.Parent = gui
	lockButton.MouseButton1Click:Connect(function()
		if remotes == nil then
			return
		end
		task.spawn(function()
			local ok, success, message, lockRemaining, cooldownRemaining = pcall(function()
				return remotes.LockBase:InvokeServer()
			end)
			if ok then
				HudController.setPrompt(message or "", 3)
				if success then
					lockUntil = os.clock() + (lockRemaining or 0)
					lockCooldownUntil = os.clock() + (cooldownRemaining or 0)
				elseif cooldownRemaining ~= nil and cooldownRemaining > 0 then
					lockCooldownUntil = os.clock() + cooldownRemaining
				end
			else
				HudController.setPrompt("Gagal menghubungi server.", 3)
			end
		end)
	end)
end

-- "167" -> "2:47".
local function formatClock(seconds)
	local s = math.max(0, math.floor(seconds))
	return math.floor(s / 60) .. ":" .. string.format("%02d", s % 60)
end

-- Next tier to chase: one above the highest tier the player owns
-- (Common when nothing is owned yet).
local function nextTierHint(state)
	local highest = 0
	for _, item in ipairs(state.owned) do
		for i, tier in ipairs(BrainrotCatalog.TIERS) do
			if tier.name == item.tier and i > highest then
				highest = i
			end
		end
	end
	local nextTier = math.min(highest + 1, #BrainrotCatalog.TIERS)
	for _, entry in ipairs(BrainrotCatalog.CHARACTERS) do
		if entry.tier == nextTier then
			return "Berikutnya: " .. entry.name .. " — $" .. entry.rate .. "/s (harga $" .. entry.price .. ")"
		end
	end
	return "Berikutnya: ..."
end

function HudController.applyState(state)
	cachedState = state
	cashLabel.Text = "💰 $" .. formatMoney(state.cash)
	incomeLabel.Text = "+$" .. formatMoney(state.income) .. "/s  •  Rebirth x" .. state.multiplier .. " (" .. state.rebirths .. "x)"
	if state.carrying ~= nil then
		carryingLabel.Text = "Membawa: " .. state.carrying.name .. " — bawa ke base!"
		carryingLabel.Visible = true
	else
		carryingLabel.Visible = false
	end
	for i = 1, MAX_ROWS do
		local item = state.owned[i]
		local row = ownedRows[i]
		if item ~= nil then
			row.Text = "  " .. item.name .. "  $" .. formatMoney(item.rate) .. "/s  •  jual $" .. formatMoney(item.sellPrice)
			row.TextColor3 = item.tierColor
			row.Visible = true
			rowUids[i] = item.uid
		else
			row.Text = ""
			row.Visible = false
			rowUids[i] = nil
		end
	end
	nextLabel.Text = nextTierHint(state)
	if state.cash >= REBIRTH_CASH then
		rebirthButton.Text = "🔄 REBIRTH! (x" .. (state.multiplier * 2) .. ")"
		rebirthButton.BackgroundColor3 = Color3.fromRGB(40, 160, 60)
	else
		rebirthButton.Text = "🔄 Rebirth — butuh $" .. formatMoney(REBIRTH_CASH)
		rebirthButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	end
end

function HudController.getCachedState()
	return cachedState
end

-- Live Pasar Tumpah status from the server (phase 3): the event label
-- shows the countdown to the next flood, the 10s warning (placed
-- brainrots are SAFE), the wave itself, and the scramble window.
function HudController.applyEventUpdate(payload)
	if eventLabel == nil or payload == nil then
		return
	end
	local secondsLeft = payload.secondsLeft or 0
	if payload.phase == "countdown" then
		eventLabel.Text = "⚠️ PASAR TUMPAH! " .. secondsLeft .. " dtk — yang di conveyor & dibawa bisa hanyut, yang di base AMAN!"
		eventLabel.TextColor3 = Color3.fromRGB(255, 90, 60)
	elseif payload.phase == "wave" then
		eventLabel.Text = "🌊 GELOMBANG DATANG! Berlindung di base!"
		eventLabel.TextColor3 = Color3.fromRGB(80, 160, 255)
	elseif payload.phase == "scramble" then
		eventLabel.Text = "📦 PETI TUMPAH! Rebut di scramble zone — " .. formatClock(secondsLeft)
		eventLabel.TextColor3 = Color3.fromRGB(255, 210, 60)
	else
		eventLabel.Text = "🌊 Pasar Tumpah: " .. formatClock(secondsLeft)
		eventLabel.TextColor3 = Color3.fromRGB(140, 220, 255)
	end
end

-- Lock button countdown, from what the server last answered (display
-- only; the server enforces the real lock and cooldown).
local function updateLockButton()
	if lockButton == nil then
		return
	end
	local now = os.clock()
	if now < lockUntil then
		lockButton.Text = "🔒 Terkunci: " .. math.ceil(lockUntil - now) .. " dtk"
		lockButton.BackgroundColor3 = Color3.fromRGB(40, 120, 200)
	elseif now < lockCooldownUntil then
		lockButton.Text = "🔒 Cooldown: " .. math.ceil(lockCooldownUntil - now) .. " dtk"
		lockButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	else
		lockButton.Text = "🔒 Kunci Base (30 dtk)"
		lockButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	end
end

-- A message prompt that stays for holdSeconds, whatever the context
-- prompt does. Empty text hides it.
function HudController.setPrompt(text, holdSeconds)
	if text == nil or text == "" then
		promptLabel.Text = ""
		promptLabel.Visible = false
		return
	end
	promptLabel.Text = text
	promptLabel.Visible = true
	if holdSeconds ~= nil then
		promptHoldUntil = os.clock() + holdSeconds
	end
end

-- The contextual [E] hint. Never overwrites a held message prompt.
function HudController.setContextPrompt(text)
	if os.clock() < promptHoldUntil then
		return
	end
	HudController.setPrompt(text)
end

function HudController.init()
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	buildGui()
	remotes.StateUpdate.OnClientEvent:Connect(function(state)
		if state ~= nil then
			HudController.applyState(state)
		end
	end)
	remotes.EventUpdate.OnClientEvent:Connect(function(payload)
		HudController.applyEventUpdate(payload)
	end)
	-- Lock button countdown, twice a second.
	local lockTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		lockTimer = lockTimer + dt
		if lockTimer < 0.5 then
			return
		end
		lockTimer = 0
		updateLockButton()
	end)
	-- Initial state: ask the server. The join push may predate the
	-- client, so retry once if the first call lands too early.
	local function fetchState()
		local ok, state = pcall(function()
			return remotes.GetState:InvokeServer()
		end)
		if ok and state ~= nil then
			HudController.applyState(state)
			return true
		end
		return false
	end
	if not fetchState() then
		task.delay(2, fetchState)
	end
end

return HudController
