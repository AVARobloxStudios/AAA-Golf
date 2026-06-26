--!strict
-- EventBusHandler runner — thin Script per TDD §3.1
-- Establishes the single GameBus.OnServerEvent connection.
-- Dependencies (GameService, PhysicsService) are initialized by their own runners.

local ServerScriptService = game:GetService("ServerScriptService")
local EventBusHandler = require(ServerScriptService.Modules.EventBusHandler)
EventBusHandler:Init({})
