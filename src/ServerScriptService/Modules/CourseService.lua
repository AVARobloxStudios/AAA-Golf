--!strict
-- CourseService — Server-only singleton
-- Owns hole rotation for the active course. Reads hole metadata (Par, Tee CFrame,
-- Pin CFrame) from Workspace Metadata Value instances and exposes a clean API to
-- GameService and the GetCourseData RemoteFunction.
--
-- Logical IDs (e.g. "course_1") are used throughout the public API.
-- Workspace folder names (e.g. "Course_1_SunnybrookMeadows") are an implementation
-- detail translated inside this module before calls to CourseLoader.
--
-- TDD §2.5, §6.3, §8 (GetCourseData RemoteFunction).

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")

local CourseLoader = require(ServerScriptService.Modules.CourseLoader)

-- ── Constants ──────────────────────────────────────────────────────────────

-- The only course in the Vertical Slice.
local ACTIVE_COURSE_ID    = "course_1"
local COURSE_FOLDER_NAME  = "Course_1_SunnybrookMeadows"
local COURSE_DISPLAY_NAME = "Sunnybrook Meadows"
local TOTAL_HOLES         = 9

-- Stub par values used when Workspace Metadata IntValue is absent.
-- Index 1 = Hole 1, index 9 = Hole 9.
local DEFAULT_PAR: { number } = { 4, 4, 4, 3, 5, 4, 4, 3, 5 }  -- par 36

-- ── Types ──────────────────────────────────────────────────────────────────

export type HoleMeta = {
	holeNumber   : number,
	par          : number,
	teePosition  : Vector3,
	pinPosition  : Vector3,
}

export type CourseRecord = {
	id          : string,
	displayName : string,
	totalHoles  : number,
	holes       : { [string]: HoleMeta },
}

-- ── Module state ───────────────────────────────────────────────────────────

local _initialized    = false
local _activeCourseId = ""
local _activeHoleId: string? = nil
local _courseCache: { [string]: CourseRecord } = {}

-- ── Module ─────────────────────────────────────────────────────────────────

local CourseService = {}
CourseService.__index = CourseService

-- ── Private helpers ────────────────────────────────────────────────────────

local function _parseHoleNumber(holeId: string): number?
	local s = holeId:match("^Hole_(%d+)$")
	if not s then
		return nil
	end
	return tonumber(s)
end

local function _formatHoleId(n: number): string
	return ("Hole_%02d"):format(n)
end

-- Reads one hole's metadata from Workspace.
-- Falls back to stub defaults when any Value instance is absent, so CourseService
-- remains usable before real hole geometry is placed by designers.
local function _readHoleMeta(courseFolder: Instance, holeId: string, holeNumber: number): HoleMeta
	-- Stub positions: spaced far apart so they can't be confused for real data.
	local stubTee = Vector3.new(holeNumber * 500, 0,   0)
	local stubPin = Vector3.new(holeNumber * 500, 0, 200)
	local par         = DEFAULT_PAR[holeNumber] or 4
	local teePosition = stubTee
	local pinPosition = stubPin

	local holesFolder = courseFolder:FindFirstChild("Holes")
	if holesFolder then
		local holeFolder = holesFolder:FindFirstChild(holeId)
		if holeFolder then
			local metaFolder = holeFolder:FindFirstChild("Metadata")
			if metaFolder then
				-- Par
				local parValue = metaFolder:FindFirstChild("Par")
				if parValue and parValue:IsA("IntValue") then
					par = (parValue :: IntValue).Value
				end

				-- Tee (accept CFrameValue or Vector3Value)
				local teeValue = metaFolder:FindFirstChild("Tee")
				if teeValue then
					if teeValue:IsA("CFrameValue") then
						teePosition = (teeValue :: CFrameValue).Value.Position
					elseif teeValue:IsA("Vector3Value") then
						teePosition = (teeValue :: Vector3Value).Value
					end
				end

				-- Pin (accept CFrameValue or Vector3Value)
				local pinValue = metaFolder:FindFirstChild("Pin")
				if pinValue then
					if pinValue:IsA("CFrameValue") then
						pinPosition = (pinValue :: CFrameValue).Value.Position
					elseif pinValue:IsA("Vector3Value") then
						pinPosition = (pinValue :: Vector3Value).Value
					end
				end
			end
		end
	end

	return {
		holeNumber  = holeNumber,
		par         = par,
		teePosition = teePosition,
		pinPosition = pinPosition,
	}
end

-- Walks Workspace to build the full CourseRecord for a course.
local function _buildCourseRecord(courseId: string): CourseRecord
	local courses = Workspace:FindFirstChild("Courses")
	assert(courses, "CourseService: Workspace.Courses folder not found")

	local courseFolder = courses:FindFirstChild(COURSE_FOLDER_NAME)
	assert(
		courseFolder,
		("CourseService: Workspace.Courses.%s not found"):format(COURSE_FOLDER_NAME)
	)

	local holes: { [string]: HoleMeta } = {}
	for n = 1, TOTAL_HOLES do
		local holeId = _formatHoleId(n)
		holes[holeId] = _readHoleMeta(courseFolder :: Instance, holeId, n)
	end

	return {
		id          = courseId,
		displayName = COURSE_DISPLAY_NAME,
		totalHoles  = TOTAL_HOLES,
		holes       = holes,
	}
end

-- Wires the GetCourseData RemoteFunction (TDD §8).
-- The RF is declared in default.project.json and is guaranteed to exist by
-- the time server scripts run, so FindFirstChild (not WaitForChild) is used.
local function _wireRemoteFunction()
	local network = ReplicatedStorage:FindFirstChild("Network")
	if not network then
		warn("CourseService: ReplicatedStorage.Network not found — GetCourseData RF not wired")
		return
	end
	local rfFolder = network:FindFirstChild("RemoteFunctions")
	if not rfFolder then
		warn("CourseService: RemoteFunctions folder not found — GetCourseData RF not wired")
		return
	end
	local rf = rfFolder:FindFirstChild("GetCourseData")
	if not rf or not rf:IsA("RemoteFunction") then
		warn("CourseService: GetCourseData RemoteFunction not found")
		return
	end

	local getCourseDataRF = rf :: RemoteFunction
	getCourseDataRF.OnServerInvoke = function(player: Player, payload: any): any
		local ok, result = pcall(function(): any
			if type(payload) ~= "table" or type(payload.courseId) ~= "string" then
				error("invalid payload: courseId must be a string")
			end
			return CourseService:GetCourseData(payload.courseId :: string)
		end)
		if not ok then
			warn(("CourseService: GetCourseData error for %s: %s"):format(
				player.Name, tostring(result)
			))
			return nil
		end
		return result
	end
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function CourseService:Init(_deps: { [string]: any })
	if _initialized then
		return
	end
	_initialized = true

	CourseLoader:Init({})

	-- Build metadata cache for the only course in the VS.
	_courseCache[ACTIVE_COURSE_ID] = _buildCourseRecord(ACTIVE_COURSE_ID)
	_activeCourseId = ACTIVE_COURSE_ID

	_wireRemoteFunction()
end

function CourseService:Update(_dt: number) end

function CourseService:Destroy()
	_initialized    = false
	_activeCourseId = ""
	_activeHoleId   = nil
	table.clear(_courseCache)
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Returns the logical ID of the active course (e.g. "course_1").
-- AimAssist uses this to enable course-1-only features (TDD §15.3).
function CourseService:GetCourseId(): string
	return _activeCourseId
end

-- Returns the full CourseRecord for a logical courseId.
-- Called by the GetCourseData RemoteFunction handler and GameService.
-- Errors if courseId is not loaded (unknown course).
function CourseService:GetCourseData(courseId: string): CourseRecord
	local record = _courseCache[courseId]
	if not record then
		error(
			("CourseService:GetCourseData — unknown courseId %q (only %q is loaded in the VS)"):format(
				courseId, ACTIVE_COURSE_ID
			),
			2
		)
	end
	return record
end

-- Returns the HoleMeta for a given holeId ("Hole_NN") in the active course.
-- Called by GameService on LOADING→PRE_SHOT to get par, tee position, and pin position.
-- Errors if the active course is not initialized or holeId is out of range.
function CourseService:GetHoleMeta(holeId: string): HoleMeta
	local record = _courseCache[_activeCourseId]
	if not record then
		error("CourseService:GetHoleMeta — course not initialized (call Init first)", 2)
	end
	local meta = record.holes[holeId]
	if not meta then
		error(
			("CourseService:GetHoleMeta — unknown holeId %q for course %q"):format(
				holeId, _activeCourseId
			),
			2
		)
	end
	return meta
end

-- Returns the next holeId after holeId in the active course rotation,
-- or nil when holeId is the last hole.
-- Used by StreamingController to request pre-fetching (TDD §6.3).
-- Errors if holeId is malformed.
function CourseService:GetNextHole(holeId: string): string?
	local n = _parseHoleNumber(holeId)
	if not n then
		error(
			("CourseService:GetNextHole — malformed holeId %q, expected Hole_NN"):format(holeId),
			2
		)
	end
	local record = _courseCache[_activeCourseId]
	local total  = if record then record.totalHoles else TOTAL_HOLES
	if n >= total then
		return nil
	end
	return _formatHoleId(n + 1)
end

-- Activates the given hole: delegates streaming priority to CourseLoader and
-- records the active hole for subsequent GetHoleMeta queries.
-- Called by GameService on each LOADING→PRE_SHOT transition.
-- Errors if holeId is not a valid hole in the active course.
function CourseService:ActivateHole(holeId: string)
	local record = _courseCache[_activeCourseId]
	if not record then
		error("CourseService:ActivateHole — course not initialized", 2)
	end
	if not record.holes[holeId] then
		error(
			("CourseService:ActivateHole — unknown holeId %q"):format(holeId),
			2
		)
	end
	CourseLoader:ActivateHole(COURSE_FOLDER_NAME, holeId)
	_activeHoleId = holeId
end

return CourseService
