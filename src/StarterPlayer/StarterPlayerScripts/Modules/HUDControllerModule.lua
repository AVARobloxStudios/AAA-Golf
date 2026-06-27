--!strict
-- HUDControllerModule — Client singleton (Sprint 9)
-- Tracks per-round state (hole, strokes, coins, XP, wind, status) and mirrors
-- it onto the pre-declared HUD ScreenGui in PlayerGui.
--
-- Internal state is the single source of truth; the UI is a write-only sink.
-- All five required getters (GetState, IsVisible, GetStrokeCount,
-- GetHoleNumber, GetStatusMessage) read from internal state, never from UI.
--
-- GameBus events handled:
--   StateChanged     — drives visibility, resets state on LOBBY re-entry
--   StrokeCommitted  — updates stroke count, par, coins, XP
--   HoleComplete     — advances hole number, resets strokes, sets status
--   MatchComplete / RoundComplete — forces visible, sets round-end status
--
-- UI setup runs in task.spawn so it never blocks the thin runner.
-- HUDController.client.lua is the thin runner.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local LocalPlayer: Player = Players.LocalPlayer

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Visibility table ─────────────────────────────────────────────────────────

-- States in which the HUD should be shown.
local VISIBLE_STATES: { [string]: boolean } = {
	TEE_OFF        = true,
	SWING          = true,
	BALL_IN_FLIGHT = true,
	SCORE_REVEAL   = true,
	ROUND_COMPLETE = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:   boolean               = false
local _currentState:  string                = "LOBBY"
local _visible:       boolean               = false
local _strokeCount:   number                = 0
local _holeNumber:    number                = 1
local _par:           number                = 0
local _coins:         number                = 0
local _xp:            number                = 0
local _currentClub:   string                = "DRIVER"
local _windInfo:      string                = "-- mph"
local _statusMessage: string                = ""
local _connections:   { RBXScriptConnection } = {}

-- ── UI references ────────────────────────────────────────────────────────────
-- Populated asynchronously once PlayerGui.HUD is available.

local _hudGui:      ScreenGui? = nil
local _lblHoleInfo: TextLabel? = nil
local _lblStrokes:  TextLabel? = nil
local _lblClub:     TextLabel? = nil
local _lblWind:     TextLabel? = nil
local _lblStatus:   TextLabel? = nil
local _lblCoinsXP:  TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local HUDControllerModule = {}
HUDControllerModule.__index = HUDControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

-- Creates and returns a styled TextLabel.
local function _makeLabel(
	parent: Instance,
	pos:    UDim2,
	size:   UDim2,
	anchor: Vector2,
	align:  Enum.TextXAlignment,
	size18: boolean
): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency  = 1
	lbl.Position                = pos
	lbl.Size                    = size
	lbl.AnchorPoint             = anchor
	lbl.Font                    = Enum.Font.GothamBold
	lbl.TextSize                = if size18 then 18 else 14
	lbl.TextColor3              = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency  = 0.5
	lbl.TextStrokeColor3        = Color3.fromRGB(0, 0, 0)
	lbl.TextXAlignment          = align
	lbl.TextScaled              = false
	lbl.Text                    = ""
	lbl.Parent                  = parent
	return lbl
end

-- Populates TextLabels inside the existing HUD Frame children.
local function _setupUI(hudGui: ScreenGui)
	local holeFrame   = hudGui:FindFirstChild("HoleInfoBanner") :: Frame?
	local strokeFrame = hudGui:FindFirstChild("StrokeCounter")  :: Frame?
	local aimFrame    = hudGui:FindFirstChild("AimIndicator")   :: Frame?
	local windFrame   = hudGui:FindFirstChild("WindIndicator")  :: Frame?

	if holeFrame then
		_lblHoleInfo = _makeLabel(
			holeFrame,
			UDim2.new(0, 12, 0, 10),
			UDim2.new(0, 380, 0, 36),
			Vector2.new(0, 0),
			Enum.TextXAlignment.Left,
			true)
	end

	if strokeFrame then
		_lblStrokes = _makeLabel(
			strokeFrame,
			UDim2.new(0, 12, 0, 52),
			UDim2.new(0, 220, 0, 30),
			Vector2.new(0, 0),
			Enum.TextXAlignment.Left,
			false)
		_lblCoinsXP = _makeLabel(
			strokeFrame,
			UDim2.new(0, 12, 0, 86),
			UDim2.new(0, 260, 0, 26),
			Vector2.new(0, 0),
			Enum.TextXAlignment.Left,
			false)
	end

	if aimFrame then
		_lblClub = _makeLabel(
			aimFrame,
			UDim2.new(0, 12, 1, -52),
			UDim2.new(0, 220, 0, 28),
			Vector2.new(0, 1),
			Enum.TextXAlignment.Left,
			false)
	end

	if windFrame then
		_lblWind = _makeLabel(
			windFrame,
			UDim2.new(0.5, 0, 0, 10),
			UDim2.new(0, 200, 0, 28),
			Vector2.new(0.5, 0),
			Enum.TextXAlignment.Center,
			false)
	end

	-- Status label lives directly in the ScreenGui for centred overlay display.
	local statusLbl = _makeLabel(
		hudGui,
		UDim2.new(0.5, 0, 0.44, 0),
		UDim2.new(0, 460, 0, 42),
		Vector2.new(0.5, 0.5),
		Enum.TextXAlignment.Center,
		true)
	_lblStatus = statusLbl
end

-- Pushes all internal state values to the UI labels.
-- Each update is nil-guarded; safe to call before UI is ready.
local function _updateUI()
	if _hudGui then
		_hudGui.Enabled = _visible
	end
	if _lblHoleInfo then
		_lblHoleInfo.Text = ("Hole %d  |  Par %d  |  Shots: %d"):format(
			_holeNumber, _par, _strokeCount)
	end
	if _lblStrokes then
		_lblStrokes.Text = ("Strokes: %d"):format(_strokeCount)
	end
	if _lblCoinsXP then
		_lblCoinsXP.Text = ("Coins: %d   XP: %d"):format(_coins, _xp)
	end
	if _lblClub then
		_lblClub.Text = "Club: " .. _currentClub
	end
	if _lblWind then
		_lblWind.Text = "Wind: " .. _windInfo
	end
	if _lblStatus then
		_lblStatus.Text = _statusMessage
	end
end

-- ── Semi-public: exposed for Sprint9ClientTest ───────────────────────────────

function HUDControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	local eventType = envelope.eventType
	if type(eventType) ~= "string" then return end

	-- ── StateChanged ──────────────────────────────────────────────────────────
	if eventType == "StateChanged" then
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.playerId ~= LocalPlayer.UserId then return end

		local newState: string = tostring(payload.state)
		if newState == _currentState then return end

		_currentState = newState
		_visible      = VISIBLE_STATES[newState] == true

		-- State-specific side effects.
		if newState == "LOBBY" then
			-- Full reset on returning to lobby (round ended or aborted).
			_strokeCount   = 0
			_holeNumber    = 1
			_par           = 0
			_statusMessage = ""
		elseif newState == "TEE_OFF" then
			_statusMessage = "Aim and press Space to swing"
		elseif newState == "SWING" then
			_statusMessage = "Hold to charge — release to swing"
		elseif newState == "BALL_IN_FLIGHT" then
			_statusMessage = "Ball in flight…"
		elseif newState == "SCORE_REVEAL" then
			_statusMessage = "Nice shot!"
		elseif newState == "ROUND_COMPLETE" then
			_statusMessage = "Round complete!"
		end

		Logger:Debug("HUDController", ("state → %q | visible=%s"):format(
			newState, tostring(_visible)))
		_updateUI()

	-- ── StrokeCommitted ───────────────────────────────────────────────────────
	elseif eventType == "StrokeCommitted" then
		local payload = envelope.payload
		if type(payload) ~= "table" then return end

		if type(payload.strokes) == "number" then
			_strokeCount = payload.strokes
		end
		if type(payload.par) == "number" then
			_par = payload.par
		end
		if type(payload.coinDelta) == "number" then
			_coins += payload.coinDelta
		end
		if type(payload.xpDelta) == "number" then
			_xp += payload.xpDelta
		end

		Logger:Debug("HUDController", ("StrokeCommitted — strokes=%d par=%d coins=%d xp=%d"):format(
			_strokeCount, _par, _coins, _xp))
		_updateUI()

	-- ── HoleComplete ──────────────────────────────────────────────────────────
	elseif eventType == "HoleComplete" then
		local completedHole = _holeNumber
		_holeNumber    += 1
		_strokeCount    = 0
		_statusMessage  = ("Hole %d complete!"):format(completedHole)

		Logger:Debug("HUDController", ("HoleComplete — advancing to hole %d"):format(_holeNumber))
		_updateUI()

	-- ── MatchComplete / RoundComplete ─────────────────────────────────────────
	elseif eventType == "MatchComplete" or eventType == "RoundComplete" then
		_visible       = true
		_statusMessage = "Round complete! Great game!"

		Logger:Debug("HUDController", eventType)
		_updateUI()
	end
end

-- ── Getters for Sprint9ClientTest ─────────────────────────────────────────────

function HUDControllerModule:GetState(): string
	return _currentState
end

function HUDControllerModule:IsVisible(): boolean
	return _visible
end

function HUDControllerModule:GetStrokeCount(): number
	return _strokeCount
end

function HUDControllerModule:GetHoleNumber(): number
	return _holeNumber
end

function HUDControllerModule:GetStatusMessage(): string
	return _statusMessage
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function HUDControllerModule:Init()
	if _initialized then
		warn("[HUDController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			HUDControllerModule:_onClientEvent(envelope)
		end))

	-- UI setup is async: avoids blocking the thin runner and handles the brief
	-- window between the script starting and PlayerGui.HUD being replicated.
	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg then
			warn("[HUDController] PlayerGui not available within 15 s — no UI")
			return
		end
		local hud = (pg :: Instance):WaitForChild("HUD", 15)
		if not hud then
			warn("[HUDController] HUD ScreenGui not available within 15 s — no UI")
			return
		end
		_hudGui = hud :: ScreenGui
		_setupUI(hud :: ScreenGui)
		_updateUI()
		Logger:Info("HUDController", "UI elements created and synced")
	end)

	Logger:Info("HUDController", ("ready (player: %s)"):format(LocalPlayer.Name))
end

function HUDControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	-- Destroy the TextLabels this module created; leave the HUD ScreenGui
	-- and its frame children intact (they belong to StarterGui).
	if _lblHoleInfo then _lblHoleInfo:Destroy() end
	if _lblStrokes  then _lblStrokes:Destroy()  end
	if _lblCoinsXP  then _lblCoinsXP:Destroy()  end
	if _lblClub     then _lblClub:Destroy()     end
	if _lblWind     then _lblWind:Destroy()     end
	if _lblStatus   then _lblStatus:Destroy()   end

	_lblHoleInfo = nil
	_lblStrokes  = nil
	_lblCoinsXP  = nil
	_lblClub     = nil
	_lblWind     = nil
	_lblStatus   = nil
	_hudGui      = nil

	-- Reset all internal state.
	_currentState  = "LOBBY"
	_visible       = false
	_strokeCount   = 0
	_holeNumber    = 1
	_par           = 0
	_coins         = 0
	_xp            = 0
	_currentClub   = "DRIVER"
	_windInfo      = "-- mph"
	_statusMessage = ""
	_initialized   = false
end

return HUDControllerModule
