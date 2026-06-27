--!strict
-- ClientAckIntegrationController — LocalScript thin runner (Sprint 24)
-- All logic lives in ClientAckIntegrationControllerModule so it can be required
-- and tested independently by Sprint24ClientTest.

local ClientAckIntegrationControllerModule =
	require(script.Parent.Parent.Modules.ClientAckIntegrationControllerModule)

ClientAckIntegrationControllerModule:Init()
