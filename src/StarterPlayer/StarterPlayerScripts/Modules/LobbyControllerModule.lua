--!strict
-- LobbyControllerModule — Client singleton (Sprint 15)
-- Manages the local lobby flow state and selected course.  A code-created
-- status chip (LobbyStatusGui) reflects the current state when visible.
--
-- MenuControllerModule (Sprint 10) manages the Lobby ScreenGui panels.
-- LobbyControllerModule is a separate flow coordinator and creates its own
-- ScreenGui to avoid any conflict with MenuController.
--
-- Valid lobby states (in flow order):
--   Idle → SelectingCourse → ReadyCheck → MatchStarting → InMatch
--
-- Public API
--   OpenLobby()                — show the lobby status chip
--   CloseLobby()               — hide the lobby status chip
--   IsVisible()                → boolean
--   SetLobbyState(stateName)   — transition state; warns on unknown names
--   GetLobbyState()            → string
--   SetSelectedCourse(courseId) — store selected course ID
--   GetSelectedCourse()        → string
--
-- LobbyController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)
local C_BG    = Color3.fromRGB(13,  43,  26)

-- ── Lobby state catalogue ─────────────────────────────────────────────────────

local VALID_STATES: { [string]: boolean } = {
	Idle            = true,
	SelectingCourse = true,
	ReadyCheck      = true,
	MatchStarting   = true,
	InMatch         = true,
}

local DEFAULT_STATE  = "Idle"
local DEFAULT_COURSE = "course_1"

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _visible:          boolean                 = false
local _lobbyState:       string                  = ""
local _selectedCourse:   string                  = ""
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _statusGui:   ScreenGui? = nil
local _chip:        Frame?     = nil
local _lblState:    TextLabel? = nil
local _lblCourse:   TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local LobbyControllerModule = {}
LobbyControllerModule.__index = LobbyControllerModule

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

local function _updateUI()
	if not _statusGui then return end
	_statusGui.Enabled = _visible
	if _lblState  then _lblState.Text  = _lobbyState    end
	if _lblCourse then _lblCourse.Text = _selectedCourse end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(pg: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name           = "LobbyStatusGui"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled        = false
	gui.Parent         = pg
	table.insert(_createdInstances, gui)
	_statusGui = gui

	-- Compact status chip — top-centre
	local chip = Instance.new("Frame")
	chip.Size             = UDim2.new(0, 380, 0, 44)
	chip.Position         = UDim2.new(0.5, 0, 0, 12)
	chip.AnchorPoint      = Vector2.new(0.5, 0)
	chip.BackgroundColor3 = C_PANEL
	chip.BorderSizePixel  = 0
	chip.Parent           = gui
	_corner(chip, 10)
	_stroke(chip, C_BG, 1)
	_chip = chip

	-- "⛳ LOBBY" — GOLD (ONE gold element on this chip)
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text                   = "⛳  LOBBY"
	titleLbl.Font                   = Enum.Font.GothamBold
	titleLbl.TextSize               = 13
	titleLbl.TextColor3             = C_GOLD
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size                   = UDim2.new(0, 90, 1, 0)
	titleLbl.Position               = UDim2.new(0, 12, 0, 0)
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
	titleLbl.TextYAlignment         = Enum.TextYAlignment.Center
	titleLbl.Parent                 = chip

	-- Separator
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(0, 1, 0, 20)
	sep.Position         = UDim2.new(0, 106, 0.5, 0)
	sep.AnchorPoint      = Vector2.new(0, 0.5)
	sep.BackgroundColor3 = C_CTA
	sep.BorderSizePixel  = 0
	sep.Parent           = chip

	-- State label
	local stateLbl = Instance.new("TextLabel")
	stateLbl.Text                   = DEFAULT_STATE
	stateLbl.Font                   = Enum.Font.Gotham
	stateLbl.TextSize               = 12
	stateLbl.TextColor3             = C_WHITE
	stateLbl.BackgroundTransparency = 1
	stateLbl.Size                   = UDim2.new(0, 120, 1, 0)
	stateLbl.Position               = UDim2.new(0, 114, 0, 0)
	stateLbl.TextXAlignment         = Enum.TextXAlignment.Left
	stateLbl.TextYAlignment         = Enum.TextYAlignment.Center
	stateLbl.Parent                 = chip
	_lblState = stateLbl

	-- Course label
	local courseLbl = Instance.new("TextLabel")
	courseLbl.Text                   = DEFAULT_COURSE
	courseLbl.Font                   = Enum.Font.Gotham
	courseLbl.TextSize               = 12
	courseLbl.TextColor3             = C_MUTED
	courseLbl.BackgroundTransparency = 1
	courseLbl.Size                   = UDim2.new(0, 120, 1, 0)
	courseLbl.Position               = UDim2.new(0, 248, 0, 0)
	courseLbl.TextXAlignment         = Enum.TextXAlignment.Right
	courseLbl.TextYAlignment         = Enum.TextYAlignment.Center
	courseLbl.Parent                 = chip
	_lblCourse = courseLbl

	_updateUI()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function LobbyControllerModule:OpenLobby()
	_visible = true
	_updateUI()
end

function LobbyControllerModule:CloseLobby()
	_visible = false
	_updateUI()
end

function LobbyControllerModule:IsVisible(): boolean
	return _visible
end

-- Transitions to a new lobby state.  Warns and no-ops for unknown names.
function LobbyControllerModule:SetLobbyState(stateName: string)
	if not VALID_STATES[stateName] then
		warn(("[LobbyController] SetLobbyState: unknown state %q"):format(
			tostring(stateName)))
		return
	end
	_lobbyState = stateName
	_updateUI()
end

function LobbyControllerModule:GetLobbyState(): string
	return _lobbyState
end

function LobbyControllerModule:SetSelectedCourse(courseId: string)
	_selectedCourse = courseId
	_updateUI()
end

function LobbyControllerModule:GetSelectedCourse(): string
	return _selectedCourse
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function LobbyControllerModule:Init()
	if _initialized then
		warn("[LobbyController] Init called twice — skipping")
		return
	end
	_initialized    = true
	_lobbyState     = DEFAULT_STATE
	_selectedCourse = DEFAULT_COURSE

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end
		_buildUI(pg :: Instance)
		print("[LobbyController] UI ready")
	end)

	print(("[LobbyController] ready (player: %s)"):format(LocalPlayer.Name))
end

function LobbyControllerModule:Update(_dt: number) end

function LobbyControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_statusGui  = nil
	_chip       = nil
	_lblState   = nil
	_lblCourse  = nil

	_visible        = false
	_lobbyState     = ""
	_selectedCourse = ""
	_initialized    = false
end

return LobbyControllerModule
