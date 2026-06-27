--!strict
-- RoundSummaryControllerModule — Client singleton (Sprint 12)
-- Tracks a final round summary and renders a polished post-round result card
-- as a code-created modal ScreenGui (no StarterGui frame required).
--
-- The card uses the Fairway Pro design tokens — ONE gold element (the round
-- title header) per the VS §05 single-gold rule.
--
-- Show path:  ShowSummary(data) — explicit call from GameBus handler / tests.
--             Also auto-shown by GameBus "RoundComplete" / "MatchComplete" events
--             if the server broadcasts a summary payload.
-- Hide path:  HideSummary()  explicit.
--             StateChanged → LOBBY  auto-resets.
--
-- Public API
--   ShowSummary(summary)  — store summary, show card
--   HideSummary()         — hide card, clear summary
--   GetSummary()          → RoundSummary?
--   IsVisible()           → boolean
--
-- RoundSummaryController.client.lua is the thin runner.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer: Player = Players.LocalPlayer

local GameBus: RemoteEvent =
	ReplicatedStorage.Network.RemoteEvents.GameBus :: RemoteEvent

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG     = Color3.fromRGB(13,  43,  26)
local C_CTA    = Color3.fromRGB(76,  175, 125)
local C_GOLD   = Color3.fromRGB(200, 152, 10)
local C_WHITE  = Color3.fromRGB(255, 255, 255)
local C_MUTED  = Color3.fromRGB(140, 180, 155)
local C_PANEL  = Color3.fromRGB(7,   28,  16)
local C_DIVIDE = Color3.fromRGB(25,  65,  40)

-- ── Type ─────────────────────────────────────────────────────────────────────

export type RoundSummary = {
	courseId:       string,
	totalStrokes:   number,
	totalPar:       number,
	scoreToPar:     number,
	totalCoins:     number,
	totalXP:        number,
	completedHoles: number,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _summary:          RoundSummary?           = nil
local _visible:          boolean                 = false
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _summaryGui: ScreenGui? = nil   -- code-created ScreenGui in PlayerGui
local _card:       Frame?     = nil   -- the result card frame
local _lblSTP:     TextLabel? = nil   -- score-to-par readout
local _lblCourse:  TextLabel? = nil
local _lblStrokes: TextLabel? = nil
local _lblPar:     TextLabel? = nil
local _lblHoles:   TextLabel? = nil
local _lblCoins:   TextLabel? = nil
local _lblXP:      TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local RoundSummaryControllerModule = {}
RoundSummaryControllerModule.__index = RoundSummaryControllerModule

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

local function _statLabel(parent: Frame, x: number, value: string, caption: string)
	local cell = Instance.new("Frame")
	cell.Size             = UDim2.new(0, 80, 0, 56)
	cell.Position         = UDim2.new(0, x, 0, 0)
	cell.BackgroundColor3 = C_BG
	cell.BorderSizePixel  = 0
	cell.Parent           = parent
	_corner(cell, 6)

	local valLbl = Instance.new("TextLabel")
	valLbl.Text                   = value
	valLbl.Font                   = Enum.Font.GothamBold
	valLbl.TextSize               = 22
	valLbl.TextColor3             = C_WHITE
	valLbl.BackgroundTransparency = 1
	valLbl.Size                   = UDim2.new(1, 0, 0, 30)
	valLbl.Position               = UDim2.new(0, 0, 0, 6)
	valLbl.TextXAlignment         = Enum.TextXAlignment.Center
	valLbl.Parent                 = cell

	local capLbl = Instance.new("TextLabel")
	capLbl.Text                   = caption
	capLbl.Font                   = Enum.Font.Gotham
	capLbl.TextSize               = 10
	capLbl.TextColor3             = C_MUTED
	capLbl.BackgroundTransparency = 1
	capLbl.Size                   = UDim2.new(1, 0, 0, 14)
	capLbl.Position               = UDim2.new(0, 0, 1, -16)
	capLbl.TextXAlignment         = Enum.TextXAlignment.Center
	capLbl.Parent                 = cell

	return valLbl
end

local function _stpColor(stp: number): Color3
	if stp < 0 then return C_CTA   end
	if stp > 0 then return C_MUTED end
	return C_WHITE
end

local function _stpText(stp: number): string
	if stp > 0 then return "+" .. tostring(stp) end
	if stp < 0 then return tostring(stp)          end
	return "E"
end

local function _updateSummaryUI()
	if not _summaryGui then return end
	_summaryGui.Enabled = _visible

	if not _visible or not _summary then return end
	local s = _summary :: RoundSummary

	if _card then _card.Visible = true end
	if _lblCourse  then _lblCourse.Text  = s.courseId end
	if _lblSTP then
		_lblSTP.Text       = _stpText(s.scoreToPar)
		_lblSTP.TextColor3 = _stpColor(s.scoreToPar)
	end
	if _lblStrokes then _lblStrokes.Text = tostring(s.totalStrokes)   end
	if _lblPar     then _lblPar.Text     = tostring(s.totalPar)       end
	if _lblHoles   then _lblHoles.Text   = tostring(s.completedHoles) end
	if _lblCoins   then _lblCoins.Text   = tostring(s.totalCoins)     end
	if _lblXP      then _lblXP.Text      = tostring(s.totalXP)        end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(pg: Instance)
	-- Code-created ScreenGui (no StarterGui frame for this)
	local gui = Instance.new("ScreenGui")
	gui.Name            = "RoundSummaryGui"
	gui.ResetOnSpawn    = false
	gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	gui.Enabled         = false
	gui.Parent          = pg
	table.insert(_createdInstances, gui)
	_summaryGui = gui

	-- Dark full-screen overlay
	local overlay = Instance.new("Frame")
	overlay.Size                 = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3     = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel      = 0
	overlay.Parent               = gui

	-- Centred result card
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 380, 0, 340)
	card.Position         = UDim2.new(0.5, 0, 0.5, 0)
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Parent           = gui
	_corner(card, 14)
	_stroke(card, C_DIVIDE, 1)
	_card = card

	-- "ROUND COMPLETE" — GOLD (ONE gold element on this screen)
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text                   = "ROUND COMPLETE"
	titleLbl.Font                   = Enum.Font.GothamBold
	titleLbl.TextSize               = 18
	titleLbl.TextColor3             = C_GOLD
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size                   = UDim2.new(1, -32, 0, 28)
	titleLbl.Position               = UDim2.new(0, 16, 0, 16)
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Center
	titleLbl.Parent                 = card

	-- CTA green divider
	local div = Instance.new("Frame")
	div.Size             = UDim2.new(1, -64, 0, 2)
	div.Position         = UDim2.new(0, 32, 0, 50)
	div.BackgroundColor3 = C_CTA
	div.BorderSizePixel  = 0
	div.Parent           = card

	-- Course name
	local courseLbl = Instance.new("TextLabel")
	courseLbl.Text                   = ""
	courseLbl.Font                   = Enum.Font.Gotham
	courseLbl.TextSize               = 13
	courseLbl.TextColor3             = C_MUTED
	courseLbl.BackgroundTransparency = 1
	courseLbl.Size                   = UDim2.new(1, -32, 0, 20)
	courseLbl.Position               = UDim2.new(0, 16, 0, 58)
	courseLbl.TextXAlignment         = Enum.TextXAlignment.Center
	courseLbl.Parent                 = card
	_lblCourse = courseLbl

	-- Score-to-par (large centred)
	local stpLbl = Instance.new("TextLabel")
	stpLbl.Text                   = "E"
	stpLbl.Font                   = Enum.Font.GothamBold
	stpLbl.TextSize               = 52
	stpLbl.TextColor3             = C_WHITE
	stpLbl.BackgroundTransparency = 1
	stpLbl.Size                   = UDim2.new(1, 0, 0, 64)
	stpLbl.Position               = UDim2.new(0, 0, 0, 84)
	stpLbl.TextXAlignment         = Enum.TextXAlignment.Center
	stpLbl.Parent                 = card
	_lblSTP = stpLbl

	-- Stats row
	local statsRow = Instance.new("Frame")
	statsRow.Size             = UDim2.new(1, -32, 0, 56)
	statsRow.Position         = UDim2.new(0, 16, 0, 158)
	statsRow.BackgroundTransparency = 1
	statsRow.BorderSizePixel  = 0
	statsRow.Parent           = card

	_lblStrokes = _statLabel(statsRow, 0,   "0",  "Strokes")
	_lblPar     = _statLabel(statsRow, 86,  "0",  "Par")
	_lblHoles   = _statLabel(statsRow, 172, "0",  "Holes")
	_lblCoins   = _statLabel(statsRow, 258, "0",  "Coins")

	-- XP row below stats
	local xpRow = Instance.new("Frame")
	xpRow.Size             = UDim2.new(1, -32, 0, 28)
	xpRow.Position         = UDim2.new(0, 16, 0, 222)
	xpRow.BackgroundTransparency = 1
	xpRow.BorderSizePixel  = 0
	xpRow.Parent           = card

	local xpCapLbl = Instance.new("TextLabel")
	xpCapLbl.Text                   = "XP Earned"
	xpCapLbl.Font                   = Enum.Font.Gotham
	xpCapLbl.TextSize               = 12
	xpCapLbl.TextColor3             = C_MUTED
	xpCapLbl.BackgroundTransparency = 1
	xpCapLbl.Size                   = UDim2.new(0.5, 0, 1, 0)
	xpCapLbl.Position               = UDim2.new(0, 0, 0, 0)
	xpCapLbl.TextXAlignment         = Enum.TextXAlignment.Left
	xpCapLbl.Parent                 = xpRow

	local xpValLbl = Instance.new("TextLabel")
	xpValLbl.Text                   = "0"
	xpValLbl.Font                   = Enum.Font.GothamBold
	xpValLbl.TextSize               = 14
	xpValLbl.TextColor3             = C_CTA
	xpValLbl.BackgroundTransparency = 1
	xpValLbl.Size                   = UDim2.new(0.5, 0, 1, 0)
	xpValLbl.Position               = UDim2.new(0.5, 0, 0, 0)
	xpValLbl.TextXAlignment         = Enum.TextXAlignment.Right
	xpValLbl.Parent                 = xpRow
	_lblXP = xpValLbl

	-- "Close" CTA button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text             = "Close"
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextSize         = 16
	closeBtn.TextColor3       = Color3.fromRGB(7, 28, 16)
	closeBtn.BackgroundColor3 = C_CTA
	closeBtn.BorderSizePixel  = 0
	closeBtn.Size             = UDim2.new(1, -64, 0, 48)
	closeBtn.Position         = UDim2.new(0, 32, 1, -64)
	closeBtn.AutoButtonColor  = true
	closeBtn.Parent           = card
	_corner(closeBtn, 10)

	closeBtn.Activated:Connect(function()
		if not _initialized then return end
		RoundSummaryControllerModule:HideSummary()
	end)
end

-- ── Semi-public: exposed for Sprint12ClientTest ──────────────────────────────

function RoundSummaryControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	local eventType = envelope.eventType
	if type(eventType) ~= "string" then return end

	if eventType == "StateChanged" then
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.playerId ~= LocalPlayer.UserId then return end

		local newState = tostring(payload.state)
		if newState == "LOBBY" then
			RoundSummaryControllerModule:HideSummary()
		end

	elseif eventType == "RoundComplete" or eventType == "MatchComplete" then
		-- Server may broadcast summary data directly in the payload
		local payload = envelope.payload
		if type(payload) == "table" then
			RoundSummaryControllerModule:ShowSummary(payload :: RoundSummary)
		end
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function RoundSummaryControllerModule:ShowSummary(summary: RoundSummary)
	_summary = summary
	_visible = true
	_updateSummaryUI()
end

function RoundSummaryControllerModule:HideSummary()
	_summary = nil
	_visible = false
	_updateSummaryUI()
end

function RoundSummaryControllerModule:GetSummary(): RoundSummary?
	return _summary
end

function RoundSummaryControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function RoundSummaryControllerModule:Init()
	if _initialized then
		warn("[RoundSummaryController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			RoundSummaryControllerModule:_onClientEvent(envelope)
		end))

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end
		_buildUI(pg :: Instance)
		_updateSummaryUI()
		print("[RoundSummaryController] UI ready")
	end)

	print(("[RoundSummaryController] ready (player: %s)"):format(LocalPlayer.Name))
end

function RoundSummaryControllerModule:Update(_dt: number) end

function RoundSummaryControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_summaryGui = nil
	_card       = nil
	_lblSTP     = nil
	_lblCourse  = nil
	_lblStrokes = nil
	_lblPar     = nil
	_lblHoles   = nil
	_lblCoins   = nil
	_lblXP      = nil

	_summary     = nil
	_visible     = false
	_initialized = false
end

return RoundSummaryControllerModule
