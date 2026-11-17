-- EventService.luau -- BRAINROT NUSANTARA (roblox-brainrot-01)
-- TODO (phase 3, 19 Nov): PASAR TUMPAH, the signature flood event.
-- DO NOT implement before the foundation + economy phases are verified.
--
-- Server state machine (locked in concept v3):
--   1. Countdown starts (siren + 10s, HUD warning: conveyor + carried
--      brainrots can wash away, placed brainrots are SAFE).
--   2. Conveyor stops spawning new brainrots for now.
--   3. Wash-away list: brainrots on the conveyor + brainrots carried by
--      players who have not reached base. Each is marked processing
--      IMMEDIATELY, before the wave finishes (no double-claim).
--   4. Conveyor path reroutes to the next configuration.
--   5. Wave sweeps the plaza (visual + light knockback outside bases).
--   6. One crate per washed-away brainrot (1 brainrot = 1 crate; crate
--      class from the brainrot's tier: Pasar / Pedagang / Tumpah).
--   7. Scramble zone active for 60s, then unclaimed crates vanish.
--   8. Event ends, conveyor back to normal, spawning resumes.
-- Invariants: one event at a time (event id + phase); crates carry a
-- unique id + AVAILABLE / CLAIMED / EXPIRED state; crate claims are
-- server-validated atomically; no object is ever both on the conveyor
-- and in a crate.
--
-- Planned API:
--   EventService.init()  -- starts the 180s timer
--   EventService.startEvent()  -- runs the 8 phases above
--   EventService.getPhase()  -- current phase, for the HUD timer
local EventService = {}

function EventService.init()
	-- Phase 3.
end

return EventService
