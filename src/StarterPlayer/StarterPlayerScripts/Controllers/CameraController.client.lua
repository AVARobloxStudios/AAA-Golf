--!strict
-- CameraController — LocalScript thin runner (Sprint 8)
-- All logic lives in CameraControllerModule so it can be required and tested
-- independently by Sprint8ClientTest.

local CameraControllerModule =
	require(script.Parent.Parent.Modules.CameraControllerModule)

CameraControllerModule:Init()
