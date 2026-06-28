--!strict
-- SwingController — LocalScript thin runner (Sprint 6)
-- All logic lives in SwingControllerModule so it can be required and tested
-- independently by Sprint6ClientTest.
--
-- Sprint 34.5: SUPERSEDED by SwingEngineControllerModule (drag-based swing).
-- Init() is intentionally NOT called here to prevent this module from competing
-- with SwingEngineControllerModule for MouseButton1 and Space input.
-- Re-enable Init() only when wiring into the full GameBus round pipeline
-- (TEE_OFF → SWING → BALL_IN_FLIGHT state machine).

local SwingControllerModule =
	require(script.Parent.Parent.Modules.SwingControllerModule)

-- GATED: SwingEngineControllerModule owns all swing input in Sprint 34.5+.
-- SwingControllerModule:Init()
local _ = SwingControllerModule  -- keep require so Sprint6ClientTest can still load the module
