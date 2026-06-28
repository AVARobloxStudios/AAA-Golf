--!strict
-- PlayableHoleRunner — thin Script per TDD §3.1 (Sprint 33)

local ServerScriptService = game:GetService("ServerScriptService")
local PlayableHoleService = require(ServerScriptService.Services.PlayableHoleService)
PlayableHoleService:Init({})
