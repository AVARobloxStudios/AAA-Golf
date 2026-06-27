--!strict
-- LandingPipelineService — Server-only singleton (Sprint 29)
-- Coordinates safe ball-landing observation by delegating to
-- ShotLifecycleService:MarkBallLanded and tracking per-player landing state.
--
-- This service does NOT call PhysicsService, ScoringService, or GameService.
-- The physics/scoring pipeline (PhysicsService → GameService._onBallLanded →
-- ScoringService:CommitStroke) runs entirely independently.  LandingPipeline
-- is a pure observation and metadata coordinator.
--
-- Counter semantics:
--   landingCount  — RecordLanding calls where SLS:MarkBallLanded succeeded
--   rejectedCount — RecordLanding calls that failed (validation OR SLS failure)
--
-- Public API
--   RecordLanding(player, landingPosition) → LandResult
--   GetLandingState(player)                → LandingState  (copy)
--   ResetLanding(player)
--   GetLandingCount()  → number
--   GetRejectedCount() → number
--   ResetCounts()

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Logger)
local SLS    = require(ServerScriptService.Services.ShotLifecycleService)

-- ── Types ─────────────────────────────────────────────────────────────────────

type LandingEntry = {
	state:           string,
	landingPosition: Vector3,
}

type LandResult = {
	success: boolean,
	status:  string,
}

type LandingState = {
	state:              string,
	hasLandingPosition: boolean,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean                       = false
local _landings:      { [number]: LandingEntry? }   = {}
local _landingCount:  number                        = 0
local _rejectedCount: number                        = 0

-- ── Module ───────────────────────────────────────────────────────────────────

local LandingPipelineService = {}
LandingPipelineService.__index = LandingPipelineService

-- ── Public API ────────────────────────────────────────────────────────────────

-- Validates landingPosition, then delegates to SLS:MarkBallLanded.
-- On SLS success: stores landing entry and increments landingCount.
-- On any failure (validation or SLS): increments rejectedCount.
function LandingPipelineService:RecordLanding(
	player:          Player,
	landingPosition: any
): LandResult
	if not _initialized then
		return { success = false, status = "NotInitialized" }
	end
	if typeof(landingPosition) ~= "Vector3" then
		_rejectedCount += 1
		Logger:Warn("LandingPipelineService",
			("RecordLanding: landingPosition must be Vector3 for %s"):format(player.Name))
		return { success = false, status = "InvalidLandingPosition" }
	end

	local result = SLS:MarkBallLanded(player, landingPosition)
	if result.success then
		_landings[player.UserId] = {
			state           = "Landed",
			landingPosition = landingPosition,
		}
		_landingCount += 1
		Logger:Debug("LandingPipelineService",
			("landing recorded for %s at %s"):format(player.Name, tostring(landingPosition)))
	else
		_rejectedCount += 1
		Logger:Warn("LandingPipelineService",
			("RecordLanding: SLS rejected for %s — status=%q"):format(
				player.Name, result.status))
	end

	return result
end

-- Returns a copy of the player's current landing state.
function LandingPipelineService:GetLandingState(player: Player): LandingState
	local entry = _landings[player.UserId]
	if not entry then
		return { state = "None", hasLandingPosition = false }
	end
	return {
		state              = entry.state,
		hasLandingPosition = true,
	}
end

-- Clears the player's landing state.
function LandingPipelineService:ResetLanding(player: Player)
	_landings[player.UserId] = nil
end

function LandingPipelineService:GetLandingCount(): number
	return _landingCount
end

function LandingPipelineService:GetRejectedCount(): number
	return _rejectedCount
end

function LandingPipelineService:ResetCounts()
	_landingCount  = 0
	_rejectedCount = 0
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function LandingPipelineService:Init(_deps: { [string]: any })
	if _initialized then
		warn("[LandingPipelineService] Init called twice — skipping")
		return
	end
	_initialized = true
	table.clear(_landings)
	LandingPipelineService:ResetCounts()

	Logger:Info("LandingPipelineService", "ready")
end

function LandingPipelineService:Update(_dt: number) end

function LandingPipelineService:Destroy()
	table.clear(_landings)
	LandingPipelineService:ResetCounts()
	_initialized = false
end

return LandingPipelineService
