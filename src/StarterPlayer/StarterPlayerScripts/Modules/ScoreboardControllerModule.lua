--!strict
-- ScoreboardControllerModule — Client singleton (Sprint 12)
-- Tracks per-hole scores locally and renders a live score chip plus a
-- hole-by-hole card strip using the Scoreboard ScreenGui frames pre-declared
-- in StarterGui (LiveScorePanel, HoleByHoleGrid).
--
-- Visible states: SCORE_REVEAL, ROUND_COMPLETE.
-- Hidden states:  LOBBY, TEE_OFF, SWING, BALL_IN_FLIGHT (and all others).
--
-- Public API
--   SetHoleScore(hole, strokes, par, tier)
--   GetHoleScore(hole)          → HoleScore?
--   GetTotalStrokes()           → number
--   GetTotalPar()               → number
--   GetScoreToPar()             → number  (strokes − par, negative = under)
--   ClearScores()
--   IsVisible()                 → boolean
--
-- GameBus events handled:
--   StateChanged — controls visibility; filtered by LocalPlayer.UserId
--
-- ScoreboardController.client.lua is the thin runner.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer: Player = Players.LocalPlayer

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG    = Color3.fromRGB(13,  43,  26)
local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)

-- ── Score-tier colours (snapped, no interpolation) ────────────────────────────

local TIER_COLORS: { [string]: Color3 } = {
	ALBATROSS    = C_GOLD,
	EAGLE        = C_GOLD,
	BIRDIE       = C_CTA,
	PAR          = C_WHITE,
	BOGEY        = Color3.fromRGB(230, 190, 100),
	DOUBLE_BOGEY = Color3.fromRGB(255, 120, 120),
	WORSE        = Color3.fromRGB(255, 80,  80),
}

local function _tierColor(tier: string): Color3
	return TIER_COLORS[tier:upper()] or C_MUTED
end

local function _tierShort(tier: string): string
	local t = tier:upper()
	if t == "ALBATROSS"    then return "−3" end
	if t == "EAGLE"        then return "−2" end
	if t == "BIRDIE"       then return "−1" end
	if t == "PAR"          then return "E"  end
	if t == "BOGEY"        then return "+1" end
	if t == "DOUBLE_BOGEY" then return "+2" end
	return "+?"
end

-- States in which the scoreboard is visible.
local VISIBLE_STATES: { [string]: boolean } = {
	SCORE_REVEAL   = true,
	ROUND_COMPLETE = true,
}

-- ── Types ─────────────────────────────────────────────────────────────────────

export type HoleScore = {
	strokes: number,
	par:     number,
	tier:    string,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                  = false
local _holeScores:       { [number]: HoleScore }  = {}
local _visible:          boolean                  = false
local _gameState:        string                   = "LOBBY"
local _connections:      { RBXScriptConnection }  = {}
local _createdInstances: { Instance }             = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _liveCard:    Frame?     = nil   -- compact score chip container
local _lblSTP:      TextLabel? = nil   -- score-to-par readout
local _lblStrokes:  TextLabel? = nil   -- "17 strokes / 18 par"
local _gridRoot:    Frame?     = nil   -- root of hole-by-hole strip
local _gridCards:   Frame?     = nil   -- inner scrollable card row

-- ── Module ───────────────────────────────────────────────────────────────────

local ScoreboardControllerModule = {}
ScoreboardControllerModule.__index = ScoreboardControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _corner(inst: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = inst
end

local function _stroke(inst: Instance, color: Color3, px: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = px
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
end

local function _getTotalStrokes(): number
	local n = 0
	for _, s in pairs(_holeScores) do n += s.strokes end
	return n
end

local function _getTotalPar(): number
	local n = 0
	for _, s in pairs(_holeScores) do n += s.par end
	return n
end

local function _getScoreToPar(): number
	return _getTotalStrokes() - _getTotalPar()
end

local function _stpText(stp: number): string
	if stp > 0 then return "+" .. tostring(stp) end
	if stp < 0 then return tostring(stp)          end
	return "E"
end

local function _stpColor(stp: number): Color3
	if stp < 0 then return C_CTA   end
	if stp > 0 then return C_MUTED end
	return C_WHITE
end

local function _rebuildHoleCards()
	if not _gridCards then return end
	for _, child in ipairs(_gridCards:GetChildren()) do
		child:Destroy()
	end

	local holes: { number } = {}
	for h in pairs(_holeScores) do table.insert(holes, h) end
	table.sort(holes)

	for i, h in ipairs(holes) do
		local score = _holeScores[h]
		local tc = _tierColor(score.tier)

		local card = Instance.new("Frame")
		card.Size             = UDim2.new(0, 52, 1, -8)
		card.Position         = UDim2.new(0, (i - 1) * 56, 0, 4)
		card.BackgroundColor3 = C_PANEL
		card.BorderSizePixel  = 0
		card.Parent           = _gridCards
		_corner(card, 6)
		_stroke(card, tc, 1)

		local hLbl = Instance.new("TextLabel")
		hLbl.Text                   = "H" .. tostring(h)
		hLbl.Font                   = Enum.Font.GothamBold
		hLbl.TextSize               = 9
		hLbl.TextColor3             = C_MUTED
		hLbl.BackgroundTransparency = 1
		hLbl.Size                   = UDim2.new(1, 0, 0, 14)
		hLbl.Position               = UDim2.new(0, 0, 0, 4)
		hLbl.TextXAlignment         = Enum.TextXAlignment.Center
		hLbl.Parent                 = card

		local sLbl = Instance.new("TextLabel")
		sLbl.Text                   = tostring(score.strokes)
		sLbl.Font                   = Enum.Font.GothamBold
		sLbl.TextSize               = 20
		sLbl.TextColor3             = C_WHITE
		sLbl.BackgroundTransparency = 1
		sLbl.Size                   = UDim2.new(1, 0, 0, 26)
		sLbl.Position               = UDim2.new(0, 0, 0, 20)
		sLbl.TextXAlignment         = Enum.TextXAlignment.Center
		sLbl.Parent                 = card

		local tLbl = Instance.new("TextLabel")
		tLbl.Text                   = _tierShort(score.tier)
		tLbl.Font                   = Enum.Font.GothamBold
		tLbl.TextSize               = 10
		tLbl.TextColor3             = tc
		tLbl.BackgroundTransparency = 1
		tLbl.Size                   = UDim2.new(1, 0, 0, 14)
		tLbl.Position               = UDim2.new(0, 0, 1, -16)
		tLbl.TextXAlignment         = Enum.TextXAlignment.Center
		tLbl.Parent                 = card
	end
end

local function _updateScoreUI()
	if _liveCard then
		_liveCard.Visible = _visible
	end
	if _gridRoot then
		_gridRoot.Visible = _visible
	end

	local stp = _getScoreToPar()

	if _lblSTP then
		_lblSTP.Text       = _stpText(stp)
		_lblSTP.TextColor3 = _stpColor(stp)
	end
	if _lblStrokes then
		_lblStrokes.Text = ("%d / %d"):format(_getTotalStrokes(), _getTotalPar())
	end

	_rebuildHoleCards()
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildLivePanel(frame: Frame)
	-- Compact chip — top-right, non-obstructive
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 110, 0, 72)
	card.Position         = UDim2.new(1, -124, 0, 16)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Visible          = false
	card.Parent           = frame
	_corner(card, 10)
	_stroke(card, C_BG, 1)
	table.insert(_createdInstances, card)
	_liveCard = card

	-- Score-to-par (large, GOLD on even = ONE gold element on this chip)
	local stpLbl = Instance.new("TextLabel")
	stpLbl.Text                   = "E"
	stpLbl.Font                   = Enum.Font.GothamBold
	stpLbl.TextSize               = 32
	stpLbl.TextColor3             = C_GOLD   -- starts at E (even par = gold accent)
	stpLbl.BackgroundTransparency = 1
	stpLbl.Size                   = UDim2.new(1, 0, 0, 40)
	stpLbl.Position               = UDim2.new(0, 0, 0, 6)
	stpLbl.TextXAlignment         = Enum.TextXAlignment.Center
	stpLbl.Parent                 = card
	_lblSTP = stpLbl

	-- "strokes / par" secondary line
	local strokesLbl = Instance.new("TextLabel")
	strokesLbl.Text                   = "0 / 0"
	strokesLbl.Font                   = Enum.Font.Gotham
	strokesLbl.TextSize               = 12
	strokesLbl.TextColor3             = C_MUTED
	strokesLbl.BackgroundTransparency = 1
	strokesLbl.Size                   = UDim2.new(1, 0, 0, 18)
	strokesLbl.Position               = UDim2.new(0, 0, 1, -20)
	strokesLbl.TextXAlignment         = Enum.TextXAlignment.Center
	strokesLbl.Parent                 = card
	_lblStrokes = strokesLbl
end

local function _buildHoleGrid(frame: Frame)
	-- Horizontal strip — bottom of screen
	local root = Instance.new("Frame")
	root.Size             = UDim2.new(1, 0, 0, 88)
	root.Position         = UDim2.new(0, 0, 1, -96)
	root.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	root.BackgroundTransparency = 0.5
	root.BorderSizePixel  = 0
	root.Visible          = false
	root.ClipsDescendants = true
	root.Parent           = frame
	table.insert(_createdInstances, root)
	_gridRoot = root

	-- Inner scrollable card row
	local cards = Instance.new("Frame")
	cards.Size             = UDim2.new(1, -24, 1, 0)
	cards.Position         = UDim2.new(0, 12, 0, 0)
	cards.BackgroundTransparency = 1
	cards.BorderSizePixel  = 0
	cards.ClipsDescendants = false
	cards.Parent           = root
	_gridCards = cards
end

-- ── Semi-public: exposed for Sprint12ClientTest ──────────────────────────────

function ScoreboardControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	local eventType = envelope.eventType
	if type(eventType) ~= "string" then return end

	if eventType == "StateChanged" then
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.playerId ~= LocalPlayer.UserId then return end

		local newState = tostring(payload.state)
		_gameState = newState
		_visible   = VISIBLE_STATES[newState] == true

		print(("[ScoreboardController] state → %q | visible=%s"):format(
			newState, tostring(_visible)))
		_updateScoreUI()
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ScoreboardControllerModule:SetHoleScore(
	holeNumber: number, strokes: number, par: number, tier: string)
	_holeScores[holeNumber] = { strokes = strokes, par = par, tier = tier }
	_updateScoreUI()
end

function ScoreboardControllerModule:GetHoleScore(holeNumber: number): HoleScore?
	return _holeScores[holeNumber]
end

function ScoreboardControllerModule:GetTotalStrokes(): number
	return _getTotalStrokes()
end

function ScoreboardControllerModule:GetTotalPar(): number
	return _getTotalPar()
end

function ScoreboardControllerModule:GetScoreToPar(): number
	return _getScoreToPar()
end

function ScoreboardControllerModule:ClearScores()
	table.clear(_holeScores)
	_updateScoreUI()
end

function ScoreboardControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ScoreboardControllerModule:Init()
	if _initialized then
		warn("[ScoreboardController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			ScoreboardControllerModule:_onClientEvent(envelope)
		end))

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end

		local sbGui = (pg :: Instance):WaitForChild("Scoreboard", 15)
		if not sbGui or not _initialized then return end

		local liveFrame = (sbGui :: Instance):WaitForChild("LiveScorePanel", 15) :: Frame?
		local gridFrame = (sbGui :: Instance):WaitForChild("HoleByHoleGrid", 15) :: Frame?
		if not _initialized then return end

		if liveFrame then _buildLivePanel(liveFrame :: Frame) end
		if gridFrame  then _buildHoleGrid(gridFrame :: Frame)  end

		_updateScoreUI()
		print("[ScoreboardController] UI ready")
	end)

	print(("[ScoreboardController] ready (player: %s)"):format(LocalPlayer.Name))
end

function ScoreboardControllerModule:Update(_dt: number) end

function ScoreboardControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_liveCard   = nil
	_lblSTP     = nil
	_lblStrokes = nil
	_gridRoot   = nil
	_gridCards  = nil

	table.clear(_holeScores)
	_visible     = false
	_gameState   = "LOBBY"
	_initialized = false
end

return ScoreboardControllerModule
