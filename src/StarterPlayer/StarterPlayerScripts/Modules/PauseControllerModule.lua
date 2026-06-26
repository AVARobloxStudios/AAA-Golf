--!strict
-- PauseControllerModule — Client singleton (Sprint 10)
-- Manages local pause state and a programmatically-created PauseOverlay
-- ScreenGui styled to the Fairway Pro design token system (VS §05).
-- The overlay uses a dark modal with a gold divider accent line
-- (the ONE gold element per screen rule) and a CTA-green Resume button.
-- PauseController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG     = Color3.fromRGB(13,  43,  26)   -- #0D2B1A deep fairway
local C_CTA    = Color3.fromRGB(76,  175, 125)  -- #4CAF7D CTA green
local C_GOLD   = Color3.fromRGB(200, 152, 10)   -- #C8980A championship gold
local C_WHITE  = Color3.fromRGB(255, 255, 255)
local C_MUTED  = Color3.fromRGB(140, 180, 155)
local C_PANEL  = Color3.fromRGB(7,   28,  16)
local C_DIVIDE = Color3.fromRGB(25,  65,  40)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                 = false
local _paused:      boolean                 = false
local _connections: { RBXScriptConnection } = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _pauseGui: ScreenGui? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local PauseControllerModule = {}
PauseControllerModule.__index = PauseControllerModule

-- ── Private UI helpers ────────────────────────────────────────────────────────

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

local function _lbl(
	parent: Instance, text: string,
	font: Enum.Font, sz: number, color: Color3,
	pos: UDim2, size: UDim2, anchor: Vector2?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Text                   = text
	l.Font                   = font
	l.TextSize               = sz
	l.TextColor3             = color
	l.BackgroundTransparency = 1
	l.Position               = pos
	l.Size                   = size
	l.AnchorPoint            = anchor or Vector2.new(0.5, 0.5)
	l.TextXAlignment         = Enum.TextXAlignment.Center
	l.TextYAlignment         = Enum.TextYAlignment.Center
	l.TextStrokeTransparency = 0.85
	l.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	l.Parent                 = parent
	return l
end

local function _btn(
	parent: Instance, text: string,
	font: Enum.Font, sz: number,
	textColor: Color3, bgColor: Color3,
	pos: UDim2, size: UDim2,
	cornerPx: number?
): TextButton
	local b = Instance.new("TextButton")
	b.Text             = text
	b.Font             = font
	b.TextSize         = sz
	b.TextColor3       = textColor
	b.BackgroundColor3 = bgColor
	b.BorderSizePixel  = 0
	b.Position         = pos
	b.Size             = size
	b.AnchorPoint      = Vector2.new(0.5, 0.5)
	b.TextXAlignment   = Enum.TextXAlignment.Center
	b.Parent           = parent
	if cornerPx then _corner(b, cornerPx) end
	return b
end

-- ── Private state helpers ─────────────────────────────────────────────────────

local function _updatePauseUI()
	if _pauseGui then
		_pauseGui.Enabled = _paused
	end
end

-- ── Build the pause overlay ───────────────────────────────────────────────────

local function _buildOverlay(pg: Instance): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name           = "PauseOverlay"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 100   -- above gameplay HUD
	gui.Enabled        = false
	gui.Parent         = pg

	-- Dim the entire screen behind the modal
	local dim = Instance.new("Frame")
	dim.Size                   = UDim2.new(1, 0, 1, 0)
	dim.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel        = 0
	dim.Parent                 = gui

	-- ── Modal card ────────────────────────────────────────────────────────────
	local modal = Instance.new("Frame")
	modal.Size             = UDim2.new(0, 480, 0, 340)
	modal.Position         = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint      = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = C_PANEL
	modal.BorderSizePixel  = 0
	modal.Parent           = gui
	_corner(modal, 14)
	_stroke(modal, C_DIVIDE, 1)

	-- "PAUSED" heading
	_lbl(modal, "PAUSED",
		Enum.Font.GothamBold, 40, C_WHITE,
		UDim2.new(0.5, 0, 0.18, 0), UDim2.new(0, 440, 0, 54))

	-- ── Gold divider line — the ONE gold element on this screen ──────────────
	local divider = Instance.new("Frame")
	divider.Size             = UDim2.new(0, 320, 0, 2)
	divider.Position         = UDim2.new(0.5, 0, 0.36, 0)
	divider.AnchorPoint      = Vector2.new(0.5, 0.5)
	divider.BackgroundColor3 = C_GOLD
	divider.BorderSizePixel  = 0
	divider.Parent           = modal

	-- ── Resume button (CTA — primary action) ─────────────────────────────────
	local resumeBtn = _btn(modal,
		"Resume",
		Enum.Font.GothamBold, 20, C_WHITE, C_CTA,
		UDim2.new(0.5, 0, 0.56, 0), UDim2.new(0, 320, 0, 54),
		10)
	resumeBtn.AutoButtonColor = true
	resumeBtn.Activated:Connect(function()
		if not _initialized then return end
		PauseControllerModule:Resume()
	end)

	-- ── Settings shortcut (secondary) ────────────────────────────────────────
	local settingsBtn = _btn(modal,
		"⚙  Settings",
		Enum.Font.Gotham, 16, C_MUTED, C_BG,
		UDim2.new(0.5, 0, 0.73, 0), UDim2.new(0, 240, 0, 44),
		8)
	_stroke(settingsBtn, C_DIVIDE, 1)
	-- TODO (UIController): open SettingsController screen without resuming
	settingsBtn.Activated:Connect(function()
		if not _initialized then return end
		print("[PauseController] Settings shortcut — routing deferred to UIController")
	end)

	-- ── Return to Menu (destructive / tertiary) ───────────────────────────────
	local menuBtn = _btn(modal,
		"Return to Main Menu",
		Enum.Font.Gotham, 14, C_MUTED, C_PANEL,
		UDim2.new(0.5, 0, 0.90, 0), UDim2.new(0, 260, 0, 36),
		6)
	menuBtn.BackgroundTransparency = 1
	-- TODO (UIController): abort round via GameService then show main menu
	menuBtn.Activated:Connect(function()
		if not _initialized then return end
		print("[PauseController] Return to Menu — routing deferred to UIController")
		PauseControllerModule:Resume()
	end)

	return gui
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PauseControllerModule:TogglePause()
	_paused = not _paused
	print(("[PauseController] paused=%s"):format(tostring(_paused)))
	_updatePauseUI()
end

-- Clears pause unconditionally.  Safe to call when already unpaused.
function PauseControllerModule:Resume()
	if not _paused then return end
	_paused = false
	print("[PauseController] resumed")
	_updatePauseUI()
end

function PauseControllerModule:IsPaused(): boolean
	return _paused
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PauseControllerModule:Init()
	if _initialized then
		warn("[PauseController] Init called twice — skipping")
		return
	end
	_initialized = true

	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg then
			warn("[PauseController] PlayerGui not available within 15 s")
			return
		end
		_pauseGui = _buildOverlay(pg)
		_updatePauseUI()
		print("[PauseController] overlay ready")
	end)

	print(("[PauseController] ready (player: %s)"):format(LocalPlayer.Name))
end

function PauseControllerModule:Update(_dt: number) end

function PauseControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	if _pauseGui then
		_pauseGui:Destroy()
		_pauseGui = nil
	end

	_paused      = false
	_initialized = false
end

return PauseControllerModule
