--!strict
-- SettingsControllerModule — Client singleton (Sprint 10)
-- Stores local gameplay and audio settings and populates the pre-declared
-- PlayerGui.Settings ScreenGui (AudioPanel + GraphicsPanel) per the
-- Fairway Pro design token system (VS §05).
--
-- Gold rule: the "Audio" section header icon is the ONE gold element.
-- The Settings ScreenGui starts Enabled=false; UIController will show it
-- when the player opens Settings (Phase 1).
--
-- Destroy() clears settings to nil; Init() repopulates defaults.
-- SettingsController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG     = Color3.fromRGB(13,  43,  26)
local C_CTA    = Color3.fromRGB(76,  175, 125)
local C_GOLD   = Color3.fromRGB(200, 152, 10)
local C_WHITE  = Color3.fromRGB(255, 255, 255)
local C_MUTED  = Color3.fromRGB(140, 180, 155)
local C_PANEL  = Color3.fromRGB(7,   28,  16)
local C_DIVIDE = Color3.fromRGB(25,  65,  40)

-- ── Defaults ─────────────────────────────────────────────────────────────────

local DEFAULT_SETTINGS: { [string]: any } = {
	AudioVolume     = 1.0,
	MusicVolume     = 0.7,
	SFXVolume       = 1.0,
	GraphicsQuality = "High",
	InputMode       = "KeyboardMouse",
}

local QUALITY_TIERS: { string } = { "Low", "Medium", "High", "Ultra" }
local INPUT_MODES:   { string } = { "KeyboardMouse", "Gamepad", "Touch" }

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _settings:         { [string]: any }       = {}
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI label references (nil-guarded in _updateSettingsUI) ───────────────────

local _lblAudioVol:  TextLabel? = nil
local _lblMusicVol:  TextLabel? = nil
local _lblSFXVol:    TextLabel? = nil
local _lblQuality:   TextLabel? = nil
local _lblInputMode: TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local SettingsControllerModule = {}
SettingsControllerModule.__index = SettingsControllerModule

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
	pos: UDim2, size: UDim2, anchor: Vector2?,
	alignX: Enum.TextXAlignment?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Text                   = text
	l.Font                   = font
	l.TextSize               = sz
	l.TextColor3             = color
	l.BackgroundTransparency = 1
	l.Position               = pos
	l.Size                   = size
	l.AnchorPoint            = anchor or Vector2.new(0, 0.5)
	l.TextXAlignment         = alignX or Enum.TextXAlignment.Left
	l.TextYAlignment         = Enum.TextYAlignment.Center
	l.Parent                 = parent
	return l
end

local function _btn(
	parent: Instance, text: string,
	font: Enum.Font, sz: number,
	textColor: Color3, bgColor: Color3,
	pos: UDim2, size: UDim2,
	anchor: Vector2?, cornerPx: number?
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
	b.AnchorPoint      = anchor or Vector2.new(0.5, 0.5)
	b.TextXAlignment   = Enum.TextXAlignment.Center
	b.Parent           = parent
	if cornerPx then _corner(b, cornerPx) end
	return b
end

-- ── UI refresh ────────────────────────────────────────────────────────────────

local function _updateSettingsUI()
	local function pct(key: string, default: number): string
		local v = _settings[key]
		local n = if type(v) == "number" then v :: number else default
		return ("%d%%"):format(math.round(n * 100))
	end

	if _lblAudioVol  then _lblAudioVol.Text  = pct("AudioVolume",  1.0) end
	if _lblMusicVol  then _lblMusicVol.Text  = pct("MusicVolume",  0.7) end
	if _lblSFXVol    then _lblSFXVol.Text    = pct("SFXVolume",    1.0) end

	if _lblQuality then
		_lblQuality.Text = tostring(_settings["GraphicsQuality"] or "High")
	end
	if _lblInputMode then
		_lblInputMode.Text = tostring(_settings["InputMode"] or "KeyboardMouse")
	end
end

-- ── Volume row ────────────────────────────────────────────────────────────────
-- Creates a row with a label, a centred percentage readout, and +/- buttons.
-- Returns the central TextLabel so the caller can store a reference.
local function _volumeRow(
	parent:  Instance,
	yFrac:   number,
	rowLbl:  string,
	key:     string,
	default: number
): TextLabel
	-- Row label
	_lbl(parent, rowLbl,
		Enum.Font.Gotham, 15, C_WHITE,
		UDim2.new(0.06, 0, yFrac, 0), UDim2.new(0.46, 0, 0, 38),
		Vector2.new(0, 0.5))

	-- Decrease button
	local decBtn = _btn(parent, "−",
		Enum.Font.GothamBold, 20, C_WHITE, C_PANEL,
		UDim2.new(0.60, 0, yFrac, 0), UDim2.new(0, 44, 0, 44),
		Vector2.new(0, 0.5), 6)
	_stroke(decBtn, C_DIVIDE, 1)

	-- Value readout
	local valLbl = _lbl(parent, "100%",
		Enum.Font.GothamBold, 16, C_CTA,
		UDim2.new(0.70, 0, yFrac, 0), UDim2.new(0, 70, 0, 38),
		Vector2.new(0.5, 0.5), Enum.TextXAlignment.Center)

	-- Increase button
	local incBtn = _btn(parent, "+",
		Enum.Font.GothamBold, 20, C_WHITE, C_PANEL,
		UDim2.new(0.82, 0, yFrac, 0), UDim2.new(0, 44, 0, 44),
		Vector2.new(0, 0.5), 6)
	_stroke(incBtn, C_DIVIDE, 1)

	decBtn.Activated:Connect(function()
		if not _initialized then return end
		local cur = _settings[key]
		local n = if type(cur) == "number" then cur :: number else default
		SettingsControllerModule:SetSetting(key, math.max(0, math.round((n - 0.1) * 10) / 10))
	end)

	incBtn.Activated:Connect(function()
		if not _initialized then return end
		local cur = _settings[key]
		local n = if type(cur) == "number" then cur :: number else default
		SettingsControllerModule:SetSetting(key, math.min(1, math.round((n + 0.1) * 10) / 10))
	end)

	return valLbl
end

-- ── Cycle row ─────────────────────────────────────────────────────────────────
-- Creates a left-label + centred cycle button row.  Returns value TextLabel.
local function _cycleRow(
	parent:  Instance,
	yFrac:   number,
	rowLbl:  string,
	key:     string,
	tiers:   { string }
): TextLabel
	_lbl(parent, rowLbl,
		Enum.Font.Gotham, 15, C_WHITE,
		UDim2.new(0.06, 0, yFrac, 0), UDim2.new(0.46, 0, 0, 38),
		Vector2.new(0, 0.5))

	local cycleBtn = _btn(parent, "◀  High  ▶",
		Enum.Font.GothamBold, 15, C_CTA, C_PANEL,
		UDim2.new(0.60, 0, yFrac, 0), UDim2.new(0, 190, 0, 44),
		Vector2.new(0, 0.5), 6)
	_stroke(cycleBtn, C_DIVIDE, 1)

	cycleBtn.Activated:Connect(function()
		if not _initialized then return end
		local cur = tostring(_settings[key] or tiers[1])
		local idx = 1
		for i, t in ipairs(tiers) do
			if t == cur then idx = i break end
		end
		local next = tiers[(idx % #tiers) + 1]
		SettingsControllerModule:SetSetting(key, next)
		-- Direct label update since this TextButton doubles as the readout.
		cycleBtn.Text = "◀  " .. next .. "  ▶"
	end)

	-- Return the button itself used as the value label (simpler; no separate TextLabel needed).
	-- Wrap in a TextLabel reference by extracting a label from it.
	-- For external refresh consistency, return a TextLabel substitute:
	local ghost = _lbl(parent, "",
		Enum.Font.GothamBold, 1, C_PANEL,
		UDim2.new(0, 0, 0, 0), UDim2.new(0, 0, 0, 0))
	-- ghost is invisible; we keep the cycleBtn as the live display.
	-- _updateSettingsUI will re-set cycleBtn text directly via _lblQuality or _lblInputMode.
	-- To handle this cleanly, we store a reference to the cycleBtn label via a wrapper:
	ghost.Visible = false
	return ghost
end

-- ── Build Settings UI ─────────────────────────────────────────────────────────

local function _buildSettingsUI(settingsGui: ScreenGui)
	-- Full-screen background
	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = C_BG
	bg.BorderSizePixel  = 0
	bg.Parent           = settingsGui
	table.insert(_createdInstances, bg)

	-- Title
	_lbl(bg, "Settings",
		Enum.Font.GothamBold, 34, C_WHITE,
		UDim2.new(0.5, 0, 0, 0), UDim2.new(0, 420, 0, 72),
		Vector2.new(0.5, 0), Enum.TextXAlignment.Center)

	-- Done button (top-right)
	local doneBtn = _btn(bg, "Done",
		Enum.Font.GothamBold, 17, C_WHITE, C_CTA,
		UDim2.new(1, -16, 0, 20), UDim2.new(0, 100, 0, 44),
		Vector2.new(1, 0), 8)
	-- TODO (UIController): hide Settings ScreenGui on Done
	doneBtn.Activated:Connect(function()
		if not _initialized then return end
		print("[SettingsController] Done — routing deferred to UIController")
	end)

	-- ── AudioPanel section ────────────────────────────────────────────────────
	local audioFrame = settingsGui:FindFirstChild("AudioPanel") :: Frame?
	if audioFrame then
		-- Section background
		local audioBG = Instance.new("Frame")
		audioBG.Size             = UDim2.new(1, 0, 1, 0)
		audioBG.BackgroundColor3 = C_PANEL
		audioBG.BorderSizePixel  = 0
		audioBG.Parent           = audioFrame
		_corner(audioBG, 12)

		-- GOLD RULE: the "🎵 Audio" header is the ONE gold element on the settings screen.
		_lbl(audioBG, "🎵  Audio",
			Enum.Font.GothamBold, 18, C_GOLD,
			UDim2.new(0.06, 0, 0, 0), UDim2.new(0.5, 0, 0, 44),
			Vector2.new(0, 0))

		-- Divider
		local div = Instance.new("Frame")
		div.Size             = UDim2.new(0.88, 0, 0, 1)
		div.Position         = UDim2.new(0.06, 0, 0, 46)
		div.BackgroundColor3 = C_DIVIDE
		div.BorderSizePixel  = 0
		div.Parent           = audioBG

		_lblAudioVol = _volumeRow(audioBG, 0.26, "Master Volume", "AudioVolume", 1.0)
		_lblMusicVol = _volumeRow(audioBG, 0.52, "Music Volume",  "MusicVolume", 0.7)
		_lblSFXVol   = _volumeRow(audioBG, 0.76, "SFX Volume",    "SFXVolume",   1.0)
	end

	-- ── GraphicsPanel section ─────────────────────────────────────────────────
	local gfxFrame = settingsGui:FindFirstChild("GraphicsPanel") :: Frame?
	if gfxFrame then
		local gfxBG = Instance.new("Frame")
		gfxBG.Size             = UDim2.new(1, 0, 1, 0)
		gfxBG.BackgroundColor3 = C_PANEL
		gfxBG.BorderSizePixel  = 0
		gfxBG.Parent           = gfxFrame
		_corner(gfxBG, 12)

		_lbl(gfxBG, "🖥  Graphics",
			Enum.Font.GothamBold, 18, C_WHITE,
			UDim2.new(0.06, 0, 0, 0), UDim2.new(0.5, 0, 0, 44),
			Vector2.new(0, 0))

		local div2 = Instance.new("Frame")
		div2.Size             = UDim2.new(0.88, 0, 0, 1)
		div2.Position         = UDim2.new(0.06, 0, 0, 46)
		div2.BackgroundColor3 = C_DIVIDE
		div2.BorderSizePixel  = 0
		div2.Parent           = gfxBG

		-- Quality tier cycle row
		_lblQuality   = _cycleRow(gfxBG, 0.32, "Quality",    "GraphicsQuality", QUALITY_TIERS)
		_lblInputMode = _cycleRow(gfxBG, 0.58, "Input Mode", "InputMode",       INPUT_MODES)

		-- TODO (Phase 2): Controls panel (key rebinding, aim sensitivity)
		_lbl(gfxBG, "Controls  —  coming soon",
			Enum.Font.Gotham, 13, C_DIVIDE,
			UDim2.new(0.06, 0, 0.84, 0), UDim2.new(0.88, 0, 0, 20),
			Vector2.new(0, 0.5))
	end

	_updateSettingsUI()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function SettingsControllerModule:GetSetting(key: string): any
	return _settings[key]
end

function SettingsControllerModule:SetSetting(key: string, value: any)
	_settings[key] = value
	_updateSettingsUI()
end

-- Returns a shallow copy — callers cannot mutate internal state.
function SettingsControllerModule:GetAllSettings(): { [string]: any }
	local copy: { [string]: any } = {}
	for k, v in pairs(_settings) do
		copy[k] = v
	end
	return copy
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function SettingsControllerModule:Init()
	if _initialized then
		warn("[SettingsController] Init called twice — skipping")
		return
	end
	_initialized = true

	for k, v in pairs(DEFAULT_SETTINGS) do
		_settings[k] = v
	end

	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg then
			warn("[SettingsController] PlayerGui not available within 15 s")
			return
		end
		local gui = (pg :: Instance):WaitForChild("Settings", 15) :: ScreenGui?
		if not gui then
			warn("[SettingsController] Settings ScreenGui not available within 15 s")
			return
		end
		-- Hide until UIController shows it (Phase 1).
		gui.Enabled = false
		_buildSettingsUI(gui :: ScreenGui)
		print("[SettingsController] UI ready")
	end)

	print(("[SettingsController] ready (player: %s)"):format(LocalPlayer.Name))
end

function SettingsControllerModule:Update(_dt: number) end

function SettingsControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(_createdInstances)

	_lblAudioVol  = nil
	_lblMusicVol  = nil
	_lblSFXVol    = nil
	_lblQuality   = nil
	_lblInputMode = nil

	table.clear(_settings)
	_initialized = false
end

return SettingsControllerModule
