-- Main.client.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Client entry: starts the three controllers. The client never owns
-- game state; it only shows it (HUD), asks for it (interact) and
-- dresses it up (effects).
-- Written for the foundation phase (17 Nov 2026).

local HudController = require(script:WaitForChild("controllers"):WaitForChild("HudController"))
local InteractController = require(script:WaitForChild("controllers"):WaitForChild("InteractController"))
local EffectsController = require(script:WaitForChild("controllers"):WaitForChild("EffectsController"))

HudController.init()
InteractController.init()
EffectsController.init()

print("[BRAINROT NUSANTARA] Client ready.")
