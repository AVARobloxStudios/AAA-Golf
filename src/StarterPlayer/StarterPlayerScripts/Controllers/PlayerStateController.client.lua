--!strict
-- PlayerStateController — LocalScript thin runner (Sprint 18)
-- All logic lives in PlayerStateControllerModule so it can be required and
-- tested independently by Sprint18ClientTest.

local PlayerStateControllerModule =
	require(script.Parent.Parent.Modules.PlayerStateControllerModule)

PlayerStateControllerModule:Init()
