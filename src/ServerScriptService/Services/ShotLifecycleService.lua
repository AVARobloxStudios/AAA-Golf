--!strict
-- ShotLifecycleService — Server-only singleton (Sprint 28)
-- Lifecycle coordinator for one shot per player: tracks InFlight → Landed state
-- without owning physics, scoring, or state-machine logic.
--
-- StartShot validates its payload locally, then delegates execution to
-- ActionExecutionService (which calls GameService:OnSwingFired).  Physics and
-- scoring remain entirely within the existing PhysicsService → GameService →
-- ScoringService chain; this service only observes and records outcomes.
--
-- MarkBallLanded is a pure metadata update — it does NOT trigger scoring or
-- physics.  The real ball-landing pipeline is still driven by PhysicsService's
-- landing callback → GameService:_onBallLanded → ScoringService:CommitStroke.
--
-- Counter semantics:
--   startedCount  — StartShot calls whose AES result was success=true
--   landedCount   — MarkBallLanded calls that succeeded (state was InFlight)
--   rejectedCount — StartShot calls that failed (validation OR AES failure)
--
-- Public API
--   StartShot(player, payload)          → ExecutionResult
--   MarkBallLanded(player, landingPos)  → LandResult
--   GetShotState(player)                → ShotState  (copy)
--   ResetShot(player)
--   GetStartedCount()   → number
--   GetLandedCount()    → number
--   GetRejectedCount()  → number
--   ResetCounts()

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Logger)
local AES    = require(ServerScriptService.Services.ActionExecutionService)

-- ── Types ─────────────────────────────────────────────────────────────────────

type ShotEntry = {
	state:           string,
	payload:         { [string]: any }?,
	landingPosition: Vector3?,
}

type ExecutionResult = {
	success: boolean,
	status:  string,
	payload: any,
}

type LandResult = {
	success: boolean,
	status:  string,
}

type ShotState = {
	state:              string,
	hasPayload:         boolean,
	hasLandingPosition: boolean,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean                    = false
local _shots:         { [number]: ShotEntry? }   = {}
local _startedCount:  number                     = 0
local _landedCount:   number                     = 0
local _rejectedCount: number                     = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local ShotLifecycleService = {}
ShotLifecycleService.__index = ShotLifecycleService

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _fail(status: string): ExecutionResult
	return { success = false, status = status, payload = nil }
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Validates payload locally, then forwards to AES:Execute(SwingIntent).
-- On AES success: records InFlight state and increments startedCount.
-- On any failure (validation or AES): increments rejectedCount.
function ShotLifecycleService:StartShot(
	player:  Player,
	payload: any
): ExecutionResult
	if not _initialized then
		return _fail("NotInitialized")
	end

	if type(payload) ~= "table" then
		_rejectedCount += 1
		Logger:Warn("ShotLifecycleService",
			("StartShot: non-table payload from %s — rejecting"):format(player.Name))
		return _fail("InvalidPayload")
	end
	if typeof(payload.aimVector) ~= "Vector3" then
		_rejectedCount += 1
		Logger:Warn("ShotLifecycleService",
			("StartShot: aimVector must be Vector3 for %s — rejecting"):format(player.Name))
		return _fail("InvalidAimVector")
	end
	if type(payload.power) ~= "number"
		or payload.power < 0
		or payload.power > 1 then
		_rejectedCount += 1
		Logger:Warn("ShotLifecycleService",
			("StartShot: power must be [0,1] for %s — rejecting"):format(player.Name))
		return _fail("InvalidPower")
	end
	if payload.clubName ~= nil
		and (type(payload.clubName) ~= "string" or payload.clubName == "") then
		_rejectedCount += 1
		Logger:Warn("ShotLifecycleService",
			("StartShot: clubName must be non-empty string for %s — rejecting"):format(player.Name))
		return _fail("InvalidClubName")
	end

	local result = AES:Execute(player, { eventType = "SwingIntent", payload = payload })

	if result.success then
		_shots[player.UserId] = {
			state = "InFlight",
			payload = {
				aimVector = payload.aimVector,
				power     = payload.power,
				accuracy  = payload.accuracy,
				clubName  = payload.clubName,
			},
			landingPosition = nil,
		}
		_startedCount += 1
		Logger:Debug("ShotLifecycleService",
			("shot started for %s — state=InFlight"):format(player.Name))
	else
		_rejectedCount += 1
		Logger:Warn("ShotLifecycleService",
			("StartShot: AES returned failure for %s — status=%q"):format(
				player.Name, result.status))
	end

	return result
end

-- Records a landing position for the player's current shot.
-- Only valid when the shot state is "InFlight".
-- Does NOT trigger ScoringService or GameService — this is pure metadata.
function ShotLifecycleService:MarkBallLanded(
	player:          Player,
	landingPosition: any
): LandResult
	if not _initialized then
		return { success = false, status = "NotInitialized" }
	end
	if typeof(landingPosition) ~= "Vector3" then
		Logger:Warn("ShotLifecycleService",
			("MarkBallLanded: landingPosition must be Vector3 for %s"):format(player.Name))
		return { success = false, status = "InvalidLandingPosition" }
	end
	local entry = _shots[player.UserId]
	if not entry or entry.state ~= "InFlight" then
		Logger:Warn("ShotLifecycleService",
			("MarkBallLanded: shot not InFlight for %s (state=%q)"):format(
				player.Name, entry and entry.state or "None"))
		return { success = false, status = "NotInFlight" }
	end
	entry.state           = "Landed"
	entry.landingPosition = landingPosition
	_landedCount += 1
	Logger:Debug("ShotLifecycleService",
		("ball landed for %s at %s"):format(player.Name, tostring(landingPosition)))
	return { success = true, status = "Landed" }
end

-- Returns a copy of the player's current shot state.
function ShotLifecycleService:GetShotState(player: Player): ShotState
	local entry = _shots[player.UserId]
	if not entry then
		return { state = "None", hasPayload = false, hasLandingPosition = false }
	end
	return {
		state              = entry.state,
		hasPayload         = entry.payload ~= nil,
		hasLandingPosition = entry.landingPosition ~= nil,
	}
end

-- Clears the tracked shot state for the player.
function ShotLifecycleService:ResetShot(player: Player)
	_shots[player.UserId] = nil
end

function ShotLifecycleService:GetStartedCount(): number
	return _startedCount
end

function ShotLifecycleService:GetLandedCount(): number
	return _landedCount
end

function ShotLifecycleService:GetRejectedCount(): number
	return _rejectedCount
end

function ShotLifecycleService:ResetCounts()
	_startedCount  = 0
	_landedCount   = 0
	_rejectedCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ShotLifecycleService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[ShotLifecycleService] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_shots)
	ShotLifecycleService:ResetCounts()

	Logger:Info("ShotLifecycleService", "ready")
end

function ShotLifecycleService:Update(_dt: number) end

function ShotLifecycleService:Destroy()
	table.clear(_shots)
	ShotLifecycleService:ResetCounts()
	_initialized = false
end

return ShotLifecycleService
