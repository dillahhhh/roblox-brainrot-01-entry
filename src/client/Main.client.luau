-- Main.client.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- Client entry: starts the three controllers. The client never owns
-- game state; it only shows it (HUD), asks for it (interact) and
-- dresses it up (effects).
-- Written for the foundation phase (17 Nov 2026).

-- NOTE (18 Nov 2026, first Studio play-test): Rojo $path maps src/client/
-- to the Folder StarterPlayerScripts.Client; Main is a Script INSIDE it and
-- controllers/ is its SIBLING, not its child. The controllers must be
-- required through script.Parent — script:WaitForChild("controllers")
-- infinite-yields and no controller ever starts (no HUD, no interact).
local HudController = require(script.Parent:WaitForChild("controllers"):WaitForChild("HudController"))
local InteractController = require(script.Parent:WaitForChild("controllers"):WaitForChild("InteractController"))
local EffectsController = require(script.Parent:WaitForChild("controllers"):WaitForChild("EffectsController"))

HudController.init()
InteractController.init()
EffectsController.init()

print("[BRAINROT NUSANTARA] Client ready.")
