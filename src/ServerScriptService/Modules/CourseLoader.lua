-- CourseLoader — Activates/deactivates hole Folders, manages StreamingEnabled priority
-- Hides streaming latency by pre-fetching the next hole while current is active
-- Implemented: Sprint 4

local CourseLoader = {}
CourseLoader.__index = CourseLoader

function CourseLoader:Init(dependencies: table)
end

function CourseLoader:Update(dt: number)
end

function CourseLoader:Destroy()
end

-- Activates the given hole folder and sets its streaming priority to high
function CourseLoader:ActivateHole(holeId: string)
end

-- Deactivates the given hole folder (hides geometry, lowers stream priority)
function CourseLoader:DeactivateHole(holeId: string)
end

-- Pre-fetches the next hole while the player is on the current one
function CourseLoader:PrefetchNextHole(currentHoleId: string)
end

function CourseLoader:_getHoleFolder(holeId: string)
end

return CourseLoader
