-- Config.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Shared tuning: every number the systems share lives here, in one place.
-- Written for the foundation phase (17 Nov 2026). No gameplay logic here.

local Config = {}

Config.GAME_TITLE = "BRAINROT NUSANTARA"
Config.START_CASH = 100
Config.MAX_PLAYERS = 8

-- Bases: 8 platforms in a ring around the plaza.
Config.BASE_COUNT = 8
Config.BASE_RING_RADIUS = 55
Config.BASE_SLOTS = 6
Config.BASE_UPGRADE_MAX = 2

-- Conveyor: the bridge across the plaza centre. Brainrots walk from
-- CONVEYOR_START to CONVEYOR_FINISH and despawn at the far gate.
Config.CONVEYOR_START = Vector3.new(-45, 4, 0)
Config.CONVEYOR_FINISH = Vector3.new(45, 4, 0)
Config.CONVEYOR_SPEED = 4
Config.SPAWN_INTERVAL = 4
Config.MAX_ON_CONVEYOR = 12

-- Event: Pasar Tumpah (signature flood event, phase 3).
Config.EVENT_INTERVAL = 180
Config.EVENT_COUNTDOWN = 10
Config.SCRAMBLE_DURATION = 60
Config.WAVE_DURATION = 3
-- Scramble zone: the four far plaza corners (x, z = +/-70), the only
-- place Peti Tumpah ever lands. Peti Pasar lands near the base ring,
-- Peti Pedagang mid-plaza.
Config.SCRAMBLE_CORNERS = {
	Vector3.new(70, 0, 70),
	Vector3.new(-70, 0, 70),
	Vector3.new(70, 0, -70),
	Vector3.new(-70, 0, -70),
}
-- Crate claim distance (server-validated) and class colours.
Config.CRATE_CLAIM_DISTANCE = 12
Config.CRATE_COLORS = {
	Pasar = Color3.fromRGB(80, 220, 120),
	Pedagang = Color3.fromRGB(255, 210, 60),
	Tumpah = Color3.fromRGB(200, 90, 255),
}

-- Steal / lock / slap (phase 3).
Config.LOCK_DURATION = 30
Config.LOCK_COOLDOWN = 60
Config.SLAP_COOLDOWN = 3
Config.SLAP_FORCE = 40
Config.SLAP_RANGE = 10
Config.STEAL_DISTANCE = 20
Config.STEAL_TARGET_RANGE = 15

-- Rebirth: one threshold (phase 2). Reset cash + brainrots for a
-- permanent multiplier, stacking, shown as a badge.
Config.REBIRTH_CASH = 100000
Config.REBIRTH_MULTIPLIER = 2

-- One colour per base index; BaseService tints each base platform.
Config.BASE_COLORS = {
	Color3.fromRGB(255, 196, 120),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(255, 140, 160),
	Color3.fromRGB(140, 230, 170),
	Color3.fromRGB(200, 160, 255),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(130, 220, 220),
	Color3.fromRGB(255, 170, 90),
}

return Config
