--!strict
-- MenuController — LocalScript thin runner (Sprint 10)
-- All logic lives in MenuControllerModule so it can be required and tested
-- independently by Sprint10ClientTest.

local MenuControllerModule =
	require(script.Parent.Parent.Modules.MenuControllerModule)

MenuControllerModule:Init()
