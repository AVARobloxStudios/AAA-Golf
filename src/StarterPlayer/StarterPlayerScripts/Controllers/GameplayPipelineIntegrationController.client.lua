--!strict
-- GameplayPipelineIntegrationController — LocalScript thin runner (Sprint 26)
-- All logic lives in GameplayPipelineIntegrationControllerModule so it can be
-- required and tested independently by Sprint26ClientTest.

local GameplayPipelineIntegrationControllerModule =
	require(script.Parent.Parent.Modules.GameplayPipelineIntegrationControllerModule)

GameplayPipelineIntegrationControllerModule:Init()
