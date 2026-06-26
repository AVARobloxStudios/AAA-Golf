--!strict
-- LoadingControllerModule — Client singleton (Sprint 10)
-- Shows and hides the PlayerGui.Loading ScreenGui per the Fairway Pro
-- design token system (VS §05).
--
-- Layout:
--   Full-screen #0D2B1A background → #4CAF7D message text, centered
--   Progress bar with #C8980A gold fill (the ONE gold element per screen)
--
-- ShowLoading(message) — makes the screen visible with the given message.
-- HideLoading()        — hides the screen.
-- SetProgress(0–1)     — updates the gold fill bar width.
-- IsLoading() / GetMessage() — internal state getters.
--
-- LoadingController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG    = Color3.fromRGB(13,  43,  26)
local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized: boolean                 = false
local _loading:     boolean                 = false
local _message:     string                  = ""
local _progress:    number                  = 0       -- 0..1
local _connections: { RBXScriptConnection } = {}
local _createdInstances: { Instance }       = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _loadingGui:    ScreenGui? = nil
local _lblMessage:    TextLabel? = nil
local _progressFill:  Frame?    = nil   -- gold fill bar, width driven by _progress

-- ── Module ───────────────────────────────────────────────────────────────────

local LoadingControllerModule = {}
LoadingControllerModule.__index = LoadingControllerModule

-- ── Private UI helpers ────────────────────────────────────────────────────────

local function _corner(inst: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = inst
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

-- ── UI state refresh ──────────────────────────────────────────────────────────

local function _updateLoadingUI()
	if _loadingGui then
		_loadingGui.Enabled = _loading
	end
	if _lblMessage then
		_lblMessage.Text = _message
	end
	if _progressFill then
		_progressFill.Size = UDim2.new(_progress, 0, 1, 0)
	end
end

-- ── Build loading screen content ──────────────────────────────────────────────

local function _buildLoadingUI(loadingGui: ScreenGui)
	-- ── LoadingScreen frame ───────────────────────────────────────────────────
	local lsFrame = loadingGui:FindFirstChild("LoadingScreen") :: Frame?

	-- Always create a root bg inside the ScreenGui for the overlay.
	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = C_BG
	bg.BorderSizePixel  = 0
	bg.ZIndex           = 1
	bg.Parent           = if lsFrame then lsFrame :: Instance else loadingGui :: Instance
	table.insert(_createdInstances, bg)

	-- ── Logo / title ──────────────────────────────────────────────────────────
	_lbl(bg, "⛳",
		Enum.Font.GothamBold, 72, C_WHITE,
		UDim2.new(0.5, 0, 0.32, 0), UDim2.new(0, 120, 0, 90))
	_lbl(bg, "AAA GOLF",
		Enum.Font.GothamBold, 38, C_WHITE,
		UDim2.new(0.5, 0, 0.44, 0), UDim2.new(0, 360, 0, 54))

	-- ── Message text (CTA colour — the primary text element) ─────────────────
	local msgLbl = _lbl(bg, "",
		Enum.Font.Gotham, 18, C_CTA,
		UDim2.new(0.5, 0, 0.54, 0), UDim2.new(0, 440, 0, 32))
	_lblMessage = msgLbl

	-- ── Progress bar ─────────────────────────────────────────────────────────
	-- Track frame (dark panel background)
	local pbFrame = loadingGui:FindFirstChild("ProgressBar") :: Frame?
	local track: Frame

	if pbFrame then
		-- Use the pre-declared ProgressBar frame from StarterGui as the track container.
		local trackBg = Instance.new("Frame")
		trackBg.Size             = UDim2.new(1, 0, 1, 0)
		trackBg.BackgroundColor3 = C_PANEL
		trackBg.BorderSizePixel  = 0
		trackBg.Parent           = pbFrame
		_corner(trackBg, 6)
		table.insert(_createdInstances, trackBg)
		track = trackBg
	else
		-- Fallback: create progress bar directly in the BG frame.
		local fallback = Instance.new("Frame")
		fallback.Size             = UDim2.new(0, 480, 0, 12)
		fallback.Position         = UDim2.new(0.5, 0, 0.64, 0)
		fallback.AnchorPoint      = Vector2.new(0.5, 0.5)
		fallback.BackgroundColor3 = C_PANEL
		fallback.BorderSizePixel  = 0
		fallback.Parent           = bg
		_corner(fallback, 6)
		track = fallback
	end

	-- ── Gold fill — the ONE gold element on this screen ───────────────────────
	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(0, 0, 1, 0)   -- starts empty; SetProgress drives this
	fill.BackgroundColor3 = C_GOLD
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	_corner(fill, 6)
	_progressFill = fill

	-- Subtle loading hint text below bar
	_lbl(bg, "Loading Sunnybrook Meadows…",
		Enum.Font.Gotham, 13, C_MUTED,
		UDim2.new(0.5, 0, 0.70, 0), UDim2.new(0, 400, 0, 20))
end

-- ── Public API ────────────────────────────────────────────────────────────────

function LoadingControllerModule:ShowLoading(message: string)
	_loading  = true
	_message  = message
	_progress = 0
	print(("[LoadingController] show — %q"):format(message))
	_updateLoadingUI()
end

function LoadingControllerModule:HideLoading()
	_loading  = false
	_progress = 1   -- snap to full just before hiding (visual polish)
	print("[LoadingController] hide")
	_updateLoadingUI()
	_progress = 0   -- reset internally for next show
end

-- Sets the gold progress bar fill to [0, 1].
function LoadingControllerModule:SetProgress(value: number)
	_progress = math.clamp(value, 0, 1)
	if _progressFill then
		_progressFill.Size = UDim2.new(_progress, 0, 1, 0)
	end
end

function LoadingControllerModule:IsLoading(): boolean
	return _loading
end

function LoadingControllerModule:GetMessage(): string
	return _message
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function LoadingControllerModule:Init()
	if _initialized then
		warn("[LoadingController] Init called twice — skipping")
		return
	end
	_initialized = true

	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg then
			warn("[LoadingController] PlayerGui not available within 15 s")
			return
		end
		local gui = (pg :: Instance):WaitForChild("Loading", 15) :: ScreenGui?
		if not gui then
			warn("[LoadingController] Loading ScreenGui not available within 15 s")
			return
		end
		_loadingGui = gui :: ScreenGui
		_buildLoadingUI(gui :: ScreenGui)
		_updateLoadingUI()
		print("[LoadingController] UI ready")
	end)

	print(("[LoadingController] ready (player: %s)"):format(LocalPlayer.Name))
end

function LoadingControllerModule:Update(_dt: number) end

function LoadingControllerModule:Destroy()
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

	_lblMessage   = nil
	_progressFill = nil
	_loadingGui   = nil

	_loading     = false
	_message     = ""
	_progress    = 0
	_initialized = false
end

return LoadingControllerModule
