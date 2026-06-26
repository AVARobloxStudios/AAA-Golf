--!strict
-- GameService — Server-only singleton
-- Owns the authoritative per-player match state machine per TDD §4.1.
-- Coordinates CourseService, ScoringService, and PhysicsService.
-- Every state transition fires a "StateChanged" envelope on GameBus so client
-- controllers (CameraController, UIController, InputController) can react.
--
-- EventBusHandler (Sprint 5+) routes:
--   HoleReady  → GameService:OnHoleReady(player)
--   SwingIntent → GameService:OnSwingFired(player)  (after SimulateSwing dispatched)

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ScoringRules   = require(ReplicatedStorage.Shared.Modules.ScoringRules)
local CourseService  = require(ServerScriptService.Modules.CourseService)
local ScoringService = require(ServerScriptService.Modules.ScoringService)
local PhysicsService = require(ServerScriptService.Modules.PhysicsService)

-- ── Network ────────────────────────────────────────────────────────────────

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent
local HoleCompleteRE: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.HoleComplete :: RemoteEvent
local MatchCompleteRE: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.MatchComplete :: RemoteEvent

-- ── State name constants ────────────────────────────────────────────────────
-- These strings appear in session.state and in the "StateChanged" GameBus
-- payload. Client-side listeners match them exactly. They are intentionally
-- kept local to GameService rather than added to Enums.GameState so that
-- name changes here don't ripple through shared code without review.

local STATE_LOBBY          = "LOBBY"
local STATE_COUNTDOWN      = "COUNTDOWN"
local STATE_LOADING        = "LOADING"
local STATE_TEE_OFF        = "TEE_OFF"
local STATE_SWING          = "SWING"
local STATE_BALL_IN_FLIGHT = "BALL_IN_FLIGHT"
local STATE_SCORE_REVEAL   = "SCORE_REVEAL"
local STATE_NEXT_HOLE      = "NEXT_HOLE"
local STATE_ROUND_COMPLETE = "ROUND_COMPLETE"

-- ── Match constants ─────────────────────────────────────────────────────────

local ACTIVE_COURSE_ID: string   = "course_1"
local MAX_SHOTS_PER_HOLE: number = ScoringRules.MAX_STROKES_PER_HOLE :: any
local HOLE_IN_RADIUS: number     = 3.0  -- studs: ball within this range of pin = holed
local SCORE_REVEAL_DELAY: number = 3.0  -- seconds before auto-advancing from SCORE_REVEAL

-- ── Types ──────────────────────────────────────────────────────────────────

-- Local alias to avoid cross-module type imports.
type HoleMeta = {
	holeNumber  : number,
	par         : number,
	teePosition : Vector3,
	pinPosition : Vector3,
}

type PlayerGameSession = {
	state         : string,
	courseId      : string,
	holeNumber    : number,   -- current hole number, 1-based
	par           : number,   -- current hole's par
	shotsThisHole : number,   -- shots completed on the current hole
	ballPos       : Vector3?, -- last settled ball position; nil before first shot
	teePosition   : Vector3,
	pinPosition   : Vector3,
}

-- ── Module state ───────────────────────────────────────────────────────────

local _initialized = false
local _destroyed   = false
local _sessions: { [number]: PlayerGameSession? } = {}

-- ── Module ─────────────────────────────────────────────────────────────────

local GameService = {}
GameService.__index = GameService

-- ── Private helpers ────────────────────────────────────────────────────────

local function _formatHoleId(n: number): string
	return ("Hole_%02d"):format(n)
end

local function _parseHoleNumber(holeId: string): number?
	local s = holeId:match("^Hole_(%d+)$")
	if not s then return nil end
	return tonumber(s)
end

-- Broadcasts a StateChanged envelope on GameBus for all clients.
local function _fireStateChanged(player: Player, newState: string)
	GameBus:FireAllClients({
		eventType = "StateChanged",
		payload   = {
			playerId = player.UserId,
			state    = newState,
		} :: any,
		timestamp = os.time(),
	})
end

-- Updates session.state and broadcasts StateChanged. No-ops if no session.
local function _transition(player: Player, newState: string)
	local session = _sessions[player.UserId]
	if not session then return end
	session.state = newState
	_fireStateChanged(player, newState)
end

-- Returns true when the active hole should be finalised (max shots reached or
-- ball settled within HOLE_IN_RADIUS of the pin).
local function _isHoleComplete(session: PlayerGameSession): boolean
	if session.shotsThisHole >= MAX_SHOTS_PER_HOLE then
		return true
	end
	local pos = session.ballPos
	if pos and (pos - session.pinPosition).Magnitude <= HOLE_IN_RADIUS then
		return true
	end
	return false
end

-- Activates a hole and transitions LOADING → TEE_OFF.
-- Tells CourseService (streaming priority) and ScoringService (hole session).
-- In the VS, streaming is treated as synchronous so TEE_OFF follows immediately;
-- the client still sends HoleReady before the swing meter arms.
local function _enterLoading(player: Player, holeNumber: number)
	local session = _sessions[player.UserId]
	if not session then return end

	_transition(player, STATE_LOADING)

	local holeId = _formatHoleId(holeNumber)
	local meta   = CourseService:GetHoleMeta(holeId)

	CourseService:ActivateHole(holeId)
	ScoringService:StartHole(player, meta.holeNumber, meta.par)

	session.holeNumber    = meta.holeNumber
	session.par           = meta.par
	session.teePosition   = meta.teePosition
	session.pinPosition   = meta.pinPosition
	session.shotsThisHole = 0
	session.ballPos       = nil

	_transition(player, STATE_TEE_OFF)
end

-- ── Private: state-advance entry points ────────────────────────────────────

-- Landing callback: registered with PhysicsService in Init.
-- Drives BALL_IN_FLIGHT → SCORE_REVEAL after the ball settles, then schedules
-- the auto-advance to the next shot or hole end.
function GameService:_onBallLanded(player: Player, pos: Vector3, surface: string)
	if _destroyed then return end
	local session = _sessions[player.UserId]
	if not session then return end
	if session.state ~= STATE_BALL_IN_FLIGHT then
		warn(("[GameService] _onBallLanded: unexpected state %q for %s — ignoring"):format(
			session.state, player.Name))
		return
	end

	session.ballPos = pos
	session.shotsThisHole += 1

	ScoringService:CommitStroke(player, surface)
	_transition(player, STATE_SCORE_REVEAL)

	-- Auto-advance after the reveal delay.
	-- _destroyed is checked both here (inside the closure) and at the top of
	-- _advanceFromScoreReveal so that Destroy() silences this path regardless
	-- of which guard is evaluated first by the Luau task scheduler.
	task.delay(SCORE_REVEAL_DELAY, function()
		if _destroyed then return end
		GameService:_advanceFromScoreReveal(player)
	end)
end

-- Drives the state machine forward from SCORE_REVEAL.
-- If the hole is complete: HoleComplete → NEXT_HOLE → LOADING (next hole) or ROUND_COMPLETE.
-- If the hole is not complete: back to TEE_OFF for the next shot.
-- Exposed with an underscore prefix so Sprint5Test can call it directly,
-- bypassing the SCORE_REVEAL_DELAY for synchronous test assertions.
function GameService:_advanceFromScoreReveal(player: Player)
	if _destroyed then return end
	local session = _sessions[player.UserId]
	if not session then return end
	if session.state ~= STATE_SCORE_REVEAL then return end  -- guard against double-advance

	if _isHoleComplete(session) then
		-- Transition first so any re-entrant call (e.g. a delayed closure that fires
		-- while ScoringService:HoleComplete is mid-execution) hits the state guard
		-- above and returns before reaching ScoringService a second time.
		_transition(player, STATE_NEXT_HOLE)

		local holeScore = ScoringService:HoleComplete(player)

		HoleCompleteRE:FireAllClients({
			playerId   = player.UserId,
			holeNumber = holeScore.holeNumber,
			strokes    = holeScore.strokes,
			par        = holeScore.par,
			scoreTier  = holeScore.scoreTier,
		})

		local nextHoleId = CourseService:GetNextHole(_formatHoleId(session.holeNumber))
		if nextHoleId then
			local nextNum = _parseHoleNumber(nextHoleId)
			if nextNum then
				_enterLoading(player, nextNum)
			end
		else
			GameService:_enterRoundComplete(player)
		end
	else
		-- Hole is still in progress — player shoots from the ball's current lie.
		_transition(player, STATE_TEE_OFF)
	end
end

-- Finalises the round: calls ScoringService, broadcasts MatchComplete, and
-- clears the session so GetState returns LOBBY.
-- Exposed with underscore prefix for direct test calls.
function GameService:_enterRoundComplete(player: Player)
	local session = _sessions[player.UserId]
	if not session then return end

	_transition(player, STATE_ROUND_COMPLETE)

	local summary = ScoringService:FinalizeRound(player)

	MatchCompleteRE:FireAllClients({
		playerId = player.UserId,
		summary  = summary,
	})

	_sessions[player.UserId] = nil  -- GetState now returns LOBBY
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

-- Registers the PhysicsService landing callback and the PlayerRemoving cleanup
-- handler. Dependencies (CourseService, ScoringService, PhysicsService) are each
-- initialized by their own thin runner scripts and are ready before players join.
function GameService:Init(_deps: { [string]: any })
	_destroyed = false          -- clear before the guard so re-Init after Destroy works
	if _initialized then return end
	_initialized = true

	PhysicsService:SetLandingCallback(function(player: Player, pos: Vector3, surface: string)
		GameService:_onBallLanded(player, pos, surface)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		GameService:AbortRound(player)
	end)
end

function GameService:Update(_dt: number) end

function GameService:Destroy()
	_destroyed = true           -- causes all pending task.delay callbacks to no-op
	table.clear(_sessions)
	_initialized = false
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Returns the current match state string for player. Returns "LOBBY" if the
-- player has no active session (never started a round or round is complete).
function GameService:GetState(player: Player): string
	local session = _sessions[player.UserId]
	if not session then return STATE_LOBBY end
	return session.state
end

-- Returns "Hole_NN" for the player's current hole, or nil if not in a round.
function GameService:GetCurrentHoleId(player: Player): string?
	local session = _sessions[player.UserId]
	if not session then return nil end
	return _formatHoleId(session.holeNumber)
end

-- Returns the tee position for the current hole, or nil if not in a round.
function GameService:GetTeePosition(player: Player): Vector3?
	local session = _sessions[player.UserId]
	if not session then return nil end
	return session.teePosition
end

-- Returns the pin position for the current hole, or nil if not in a round.
-- Exposed so EventBusHandler and tests can place the ball at the pin.
function GameService:GetPinPosition(player: Player): Vector3?
	local session = _sessions[player.UserId]
	if not session then return nil end
	return session.pinPosition
end

-- Starts a new round for the player. Creates a session, fires COUNTDOWN (which
-- in the VS transitions to LOADING and TEE_OFF synchronously in the same frame
-- since there is no lobby countdown UI in the vertical slice).
-- Errors if the player already has an active session.
function GameService:StartRound(player: Player)
	if _sessions[player.UserId] then
		error(("[GameService] StartRound: %s already has an active session"):format(player.Name), 2)
	end

	-- Prime the session with hole-1 metadata so the struct is immediately valid.
	local firstMeta = CourseService:GetHoleMeta("Hole_01")

	_sessions[player.UserId] = {
		state         = STATE_LOBBY,
		courseId      = ACTIVE_COURSE_ID,
		holeNumber    = 1,
		par           = firstMeta.par,
		shotsThisHole = 0,
		ballPos       = nil,
		teePosition   = firstMeta.teePosition,
		pinPosition   = firstMeta.pinPosition,
	}

	ScoringService:StartRound(player, ACTIVE_COURSE_ID)

	-- COUNTDOWN fires immediately and transitions to LOADING then TEE_OFF in the
	-- same synchronous call stack (no real timer in the VS).
	_transition(player, STATE_COUNTDOWN)
	_enterLoading(player, 1)
end

-- Called by EventBusHandler when the client sends HoleReady (camera dolly done).
-- Transitions TEE_OFF → SWING, arming InputController on the client.
-- Errors if the player is not in TEE_OFF state.
function GameService:OnHoleReady(player: Player)
	local session = _sessions[player.UserId]
	if not session then
		error(("[GameService] OnHoleReady: %s has no active session"):format(player.Name), 2)
	end
	if session.state ~= STATE_TEE_OFF then
		error(("[GameService] OnHoleReady: expected TEE_OFF, got %q for %s"):format(
			session.state, player.Name), 2)
	end
	_transition(player, STATE_SWING)
end

-- Called by EventBusHandler after SwingIntent is processed and
-- PhysicsService:SimulateSwing has been dispatched.
-- Transitions SWING → BALL_IN_FLIGHT. The landing callback drives the next step.
-- Errors if the player is not in SWING state.
function GameService:OnSwingFired(player: Player)
	local session = _sessions[player.UserId]
	if not session then
		error(("[GameService] OnSwingFired: %s has no active session"):format(player.Name), 2)
	end
	if session.state ~= STATE_SWING then
		error(("[GameService] OnSwingFired: expected SWING, got %q for %s"):format(
			session.state, player.Name), 2)
	end
	_transition(player, STATE_BALL_IN_FLIGHT)
end

-- Cleans up a player's round on disconnect or forced exit.
-- Drains and flushes pending rewards so nothing is lost.
-- No-ops silently if the player has no session.
function GameService:AbortRound(player: Player)
	if not _sessions[player.UserId] then return end
	pcall(function()
		ScoringService:FinalizeRound(player)
	end)
	_sessions[player.UserId] = nil
end

return GameService
