--!strict
-- CourseLoader — Server-only ModuleScript
-- Activates and deactivates hole Folders in Workspace, managing the
-- StreamingPriority attribute used by Roblox Content Streaming and our
-- own StreamingController to determine which hole geometry to load.
--
-- Workspace path: Workspace.Courses[courseId].Holes[holeId]
-- courseId: the Workspace folder name (e.g. "Course_1_SunnybrookMeadows")
-- holeId:   the Workspace folder name (e.g. "Hole_01")
--
-- StreamingPriority semantics:
--   10 — current hole (fully load ASAP)
--    5 — next hole    (pre-fetch while player is on current)
--    0 — all others   (release; unload when memory pressure is high)
--
-- Required by CourseService. Has no background loop; no runner script needed.
-- TDD §20.2 — Hole Pre-Fetch.

local Workspace = game:GetService("Workspace")

-- ── Module state ───────────────────────────────────────────────────────────

local _initialized = false

-- ── Module ─────────────────────────────────────────────────────────────────

local CourseLoader = {}
CourseLoader.__index = CourseLoader

-- ── Private helpers ────────────────────────────────────────────────────────

-- Extracts the 1-based hole number from a holeId string.
-- Returns nil for any input that doesn't match "Hole_NN".
local function _parseHoleNumber(holeId: string): number?
	local s = holeId:match("^Hole_(%d+)$")
	if not s then
		return nil
	end
	return tonumber(s)
end

-- Formats a 1-based hole number back to the canonical holeId string.
local function _formatHoleId(n: number): string
	return ("Hole_%02d"):format(n)
end

-- Returns the hole Folder instance, or nil if any step of the path is absent.
-- Never errors; callers that need an error use _requireHoleFolder instead.
local function _findHoleFolder(courseId: string, holeId: string): Instance?
	local courses = Workspace:FindFirstChild("Courses")
	if not courses then
		return nil
	end
	local course = courses:FindFirstChild(courseId)
	if not course then
		return nil
	end
	local holesContainer = course:FindFirstChild("Holes")
	if not holesContainer then
		return nil
	end
	return holesContainer:FindFirstChild(holeId)
end

-- Returns the hole Folder instance, or errors with a descriptive message.
-- Use for operations where a missing folder is a programmer/designer bug.
local function _requireHoleFolder(courseId: string, holeId: string): Instance
	local folder = _findHoleFolder(courseId, holeId)
	if not folder then
		error(
			("CourseLoader: hole folder not found — Workspace/Courses/%s/Holes/%s"):format(courseId, holeId),
			2
		)
	end
	return folder
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function CourseLoader:Init(_deps: { [string]: any })
	if _initialized then
		return
	end
	_initialized = true
end

function CourseLoader:Update(_dt: number) end

function CourseLoader:Destroy()
	_initialized = false
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Activates a hole for play: sets StreamingPriority = 10 on the current hole,
-- pre-fetches the next hole at 5, and releases the previous hole at 0.
-- Gracefully skips next/previous steps when those folders don't exist
-- (e.g. activating Hole_01 has no previous; Hole_09 has no next).
-- Errors if courseId or holeId do not resolve to a Workspace folder.
function CourseLoader:ActivateHole(courseId: string, holeId: string)
	local n = _parseHoleNumber(holeId)
	if not n then
		error(
			("CourseLoader: malformed holeId %q — expected Hole_NN (e.g. Hole_01)"):format(holeId),
			2
		)
	end

	-- Current hole: top priority
	local current = _requireHoleFolder(courseId, holeId)
	current:SetAttribute("StreamingPriority", 10)

	-- Next hole: pre-fetch at lower priority
	local nextFolder = _findHoleFolder(courseId, _formatHoleId(n + 1))
	if nextFolder then
		nextFolder:SetAttribute("StreamingPriority", 5)
	end

	-- Previous hole: release
	local prevFolder = _findHoleFolder(courseId, _formatHoleId(n - 1))
	if prevFolder then
		prevFolder:SetAttribute("StreamingPriority", 0)
	end
end

-- Explicitly zeros the StreamingPriority on a hole, signalling that its
-- geometry can be unloaded when under memory pressure.
-- Errors if the hole folder does not exist.
function CourseLoader:DeactivateHole(courseId: string, holeId: string)
	local holeFolder = _requireHoleFolder(courseId, holeId)
	holeFolder:SetAttribute("StreamingPriority", 0)
end

-- Marks the next hole for pre-fetching without fully activating it.
-- Used when CourseService wants to begin streaming Hole N+1 early.
-- No-ops gracefully if there is no next hole.
-- Errors if holeId is malformed.
function CourseLoader:PrefetchNextHole(courseId: string, holeId: string)
	local n = _parseHoleNumber(holeId)
	if not n then
		error(
			("CourseLoader: malformed holeId %q — expected Hole_NN"):format(holeId),
			2
		)
	end
	local nextFolder = _findHoleFolder(courseId, _formatHoleId(n + 1))
	if nextFolder then
		nextFolder:SetAttribute("StreamingPriority", 5)
	end
end

-- Returns the hole Folder instance for diagnostic use, or nil if not found.
-- CourseService uses this to read Metadata Values (Par, Tee CFrame, Pin CFrame).
function CourseLoader:GetHoleFolder(courseId: string, holeId: string): Instance?
	return _findHoleFolder(courseId, holeId)
end

return CourseLoader
