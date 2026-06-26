--!strict
-- CourseService runner — thin Script per TDD §3.1
-- Builds hole metadata cache and wires the GetCourseData RemoteFunction.

local ServerScriptService = game:GetService("ServerScriptService")
local CourseService = require(ServerScriptService.Modules.CourseService)
CourseService:Init({})
