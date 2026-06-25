--!strict
-- PhysicsService runner — thin Script per TDD §3.1

local ServerScriptService = game:GetService("ServerScriptService")
local PhysicsService = require(ServerScriptService.Modules.PhysicsService)
PhysicsService:Init({})
