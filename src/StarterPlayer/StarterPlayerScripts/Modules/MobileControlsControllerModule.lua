--!strict
-- MobileControlsControllerModule — Client singleton (Sprint 16)
-- Manages the on-screen touch button overlay used for mobile gameplay.
-- Tracks the pressed state of each named button; callers (e.g. a future
-- InputController integration) drive state via SetButtonState().
--
-- Code-created ScreenGui "MobileControlsGui" — no StarterGui frame exists
-- for mobile controls.  Tracked in _createdInstances for clean teardown.
--
-- Valid buttons:  Swing | AimLeft | AimRight | ClubNext | ClubPrevious | Pause
--
-- Layout (thumb-zone approach):
--   Bottom-left  : AimLeft, AimRight
--   Bottom-right : ClubPrevious, ClubNext (row), Swing (large, primary)
--   Top-right    : Pause
--
-- The Swing button carries a C_GOLD UIStroke — ONE gold element on this screen.
--
-- Public API
--   ShowControls()                       — enable the overlay
--   HideControls()                       — disable the overlay
--   IsVisible()                          → boolean
--   SetButtonState(buttonName, isPressed) — track press state; warns on bad name
--   GetButtonState(buttonName)           → boolean  (false for unknown names)
--   ResetButtons()                       — set all buttons to not-pressed
--
-- MobileControlsController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)
local C_BG    = Color3.fromRGB(13,  43,  26)

-- ── Button catalogue ──────────────────────────────────────────────────────────

local VALID_BUTTONS: { [string]: boolean } = {
	Swing        = true,
	AimLeft      = true,
	AimRight     = true,
	ClubNext     = true,
	ClubPrevious = true,
	Pause        = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _visible:          boolean                 = false
local _buttonStates:     { [string]: boolean }   = {}
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references ────────────────────────────────────────────────────────────

local _controlsGui: ScreenGui?               = nil
local _buttonViews: { [string]: GuiObject }  = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local MobileControlsControllerModule = {}
MobileControlsControllerModule.__index = MobileControlsControllerModule

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

local function _updateButtonVisual(name: string)
	local view = _buttonViews[name]
	if not view then return end
	local pressed = _buttonStates[name] == true
	if view:IsA("TextButton") then
		local btn = view :: TextButton
		btn.BackgroundColor3 = pressed and C_CTA or C_PANEL
		btn.TextColor3       = pressed and C_BG  or C_WHITE
	end
end

local function _updateAllButtonVisuals()
	for name in pairs(VALID_BUTTONS) do
		_updateButtonVisual(name)
	end
end

local function _updateUI()
	if not _controlsGui then return end
	_controlsGui.Enabled = _visible
	_updateAllButtonVisuals()
end

-- Creates one labelled TextButton and registers it in _buttonViews.
local function _makeButton(
	parent:   Instance,
	name:     string,
	label:    string,
	size:     UDim2,
	position: UDim2,
	radius:   number
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name              = name
	btn.Text              = label
	btn.Font              = Enum.Font.GothamBold
	btn.TextSize          = 14
	btn.TextColor3        = C_WHITE
	btn.BackgroundColor3  = C_PANEL
	btn.BorderSizePixel   = 0
	btn.Size              = size
	btn.Position          = position
	btn.AutoButtonColor   = false
	btn.AnchorPoint       = Vector2.new(0.5, 0.5)
	btn.Parent            = parent
	_corner(btn, radius)
	_buttonViews[name] = btn

	-- Drive pressed state through the public API so all state stays consistent.
	btn.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch and
		   input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if not _initialized then return end
		MobileControlsControllerModule:SetButtonState(name, true)
	end)
	btn.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch and
		   input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if not _initialized then return end
		MobileControlsControllerModule:SetButtonState(name, false)
	end)

	return btn
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(pg: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name                       = "MobileControlsGui"
	gui.ResetOnSpawn               = false
	gui.ZIndexBehavior             = Enum.ZIndexBehavior.Sibling
	gui.Enabled                    = false
	gui.IgnoreGuiInset             = true
	gui.Parent                     = pg
	table.insert(_createdInstances, gui)
	_controlsGui = gui

	-- ── Pause (top-right corner) ─────────────────────────────────────────
	_makeButton(gui, "Pause", "⏸",
		UDim2.new(0, 44, 0, 44),
		UDim2.new(1, -38, 0, 38),
		10)

	-- ── Aim zone (bottom-left) ───────────────────────────────────────────
	local aimZone = Instance.new("Frame")
	aimZone.Size             = UDim2.new(0, 160, 0, 72)
	aimZone.Position         = UDim2.new(0, 20, 1, -96)
	aimZone.BackgroundColor3 = C_BG
	aimZone.BorderSizePixel  = 0
	aimZone.Parent           = gui
	_corner(aimZone, 14)
	_stroke(aimZone, C_PANEL, 1)

	_makeButton(aimZone, "AimLeft",  "◀",
		UDim2.new(0, 68, 0, 60),
		UDim2.new(0, 36, 0.5, 0),
		10)
	_makeButton(aimZone, "AimRight", "▶",
		UDim2.new(0, 68, 0, 60),
		UDim2.new(1, -36, 0.5, 0),
		10)

	-- ── Club zone (bottom-right, above Swing) ────────────────────────────
	local clubZone = Instance.new("Frame")
	clubZone.Size             = UDim2.new(0, 160, 0, 52)
	clubZone.Position         = UDim2.new(1, -180, 1, -168)
	clubZone.BackgroundColor3 = C_BG
	clubZone.BorderSizePixel  = 0
	clubZone.Parent           = gui
	_corner(clubZone, 10)
	_stroke(clubZone, C_PANEL, 1)

	_makeButton(clubZone, "ClubPrevious", "◂",
		UDim2.new(0, 68, 0, 40),
		UDim2.new(0, 36, 0.5, 0),
		8)
	_makeButton(clubZone, "ClubNext",     "▸",
		UDim2.new(0, 68, 0, 40),
		UDim2.new(1, -36, 0.5, 0),
		8)

	-- ── Swing button (bottom-right) — GOLD stroke = ONE gold element ─────
	local swingBtn = _makeButton(gui, "Swing", "SWING",
		UDim2.new(0, 96, 0, 96),
		UDim2.new(1, -78, 1, -68),
		48)   -- near-circle (radius = half of 96)
	swingBtn.TextSize = 16
	_stroke(swingBtn, C_GOLD, 3)  -- gold accent on the primary action button

	_updateUI()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function MobileControlsControllerModule:ShowControls()
	_visible = true
	_updateUI()
end

function MobileControlsControllerModule:HideControls()
	_visible = false
	_updateUI()
end

function MobileControlsControllerModule:IsVisible(): boolean
	return _visible
end

function MobileControlsControllerModule:SetButtonState(buttonName: string, isPressed: boolean)
	if not VALID_BUTTONS[buttonName] then
		warn(("[MobileControlsController] SetButtonState: unknown button %q"):format(
			tostring(buttonName)))
		return
	end
	_buttonStates[buttonName] = isPressed
	_updateButtonVisual(buttonName)
end

-- Returns false for invalid button names rather than raising an error.
function MobileControlsControllerModule:GetButtonState(buttonName: string): boolean
	if not VALID_BUTTONS[buttonName] then return false end
	return _buttonStates[buttonName] == true
end

function MobileControlsControllerModule:ResetButtons()
	for name in pairs(VALID_BUTTONS) do
		_buttonStates[name] = false
	end
	_updateAllButtonVisuals()
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function MobileControlsControllerModule:Init()
	if _initialized then
		warn("[MobileControlsController] Init called twice — skipping")
		return
	end
	_initialized = true

	for name in pairs(VALID_BUTTONS) do
		_buttonStates[name] = false
	end

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end
		_buildUI(pg :: Instance)
		print("[MobileControlsController] UI ready")
	end)

	print(("[MobileControlsController] ready (player: %s)"):format(LocalPlayer.Name))
end

function MobileControlsControllerModule:Update(_dt: number) end

function MobileControlsControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_controlsGui = nil
	table.clear(_buttonViews)
	table.clear(_buttonStates)

	_visible     = false
	_initialized = false
end

return MobileControlsControllerModule
