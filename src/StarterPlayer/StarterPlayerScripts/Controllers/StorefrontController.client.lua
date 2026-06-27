--!strict
-- StorefrontController — LocalScript thin runner (Sprint 14)
-- All logic lives in StorefrontControllerModule so it can be required and
-- tested independently by Sprint14ClientTest.

local StorefrontControllerModule =
	require(script.Parent.Parent.Modules.StorefrontControllerModule)

StorefrontControllerModule:Init()
