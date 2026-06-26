--!strict
-- GameService runner — thin Script per TDD §3.1
-- Registers the PhysicsService landing callback and player-disconnect cleanup.
-- Dependencies (CourseService, ScoringService, PhysicsService) are initialized
-- by their own runners and are ready before any player joins.

local ServerScriptService = game:GetService("ServerScriptService")
local GameService = require(ServerScriptService.Modules.GameService)
GameService:Init({})
