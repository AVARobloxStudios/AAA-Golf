--!strict
-- PowerMeterControllerModule — Client singleton (Sprint 11)
-- Tracks swing power (0.0–1.0) and renders a vertical fill bar inside the
-- pre-declared PlayerGui.HUD.PowerMeter frame using Fairway Pro tokens.
--
-- Visible only during the SWING game state; auto-resets on state exit.
-- Fill colour snaps at power thresholds (never TweenService) per TDD §VS:
--   0 – 0.59  →  CTA green  #4CAF7D
--   0.60–0.84 →  amber      #F5C842
--   0.85–1.0  →  hot orange #FF5520  (danger / over-swing zone)
--
-- GameBus events handled:
--   StateChanged — controls visibility; resets power on SWING exit
--
-- PowerMeterController.client.lua is the thin runner.

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
local C_AMBER  = Color3.fromRGB(245, 200, 66)   -- warning zone
local C_HOT    = Color3.fromRGB(255, 85,  32)   -- danger zone

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _power:            number                  = 0       -- 0.0 to 1.0
local _charging:         boolean                 = false
local _visible:          boolean                 = false
local _gameState:        string                  = "LOBBY"
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _pmCard:    Frame?     = nil   -- root container (Visible toggles with _visible)
local _fillBar:   Frame?     = nil   -- growing fill inside the track
local _pctLabel:  TextLabel? = nil   -- percentage readout

-- ── Module ───────────────────────────────────────────────────────────────────

local PowerMeterControllerModule = {}
PowerMeterControllerModule.__index = PowerMeterControllerModule

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

-- Threshold colour snap — never TweenService (per TDD §VS).
local function _powerColor(power: number): Color3
	if power >= 0.85 then return C_HOT   end
	if power >= 0.60 then return C_AMBER end
	return C_CTA
end

local function _updatePowerUI()
	if _pmCard then
		_pmCard.Visible = _visible
	end
	if _fillBar then
		local h = _power
		_fillBar.Size     = UDim2.new(1, 0, h, 0)
		_fillBar.Position = UDim2.new(0, 0, 1 - h, 0)
		_fillBar.BackgroundColor3 = _powerColor(_power)
	end
	if _pctLabel then
		_pctLabel.Text = ("%d%%"):format(math.round(_power * 100))
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(pmFrame: Frame)
	-- Card — bottom-right, non-obstructive
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 72, 0, 260)
	card.Position         = UDim2.new(1, -100, 1, -280)
	card.AnchorPoint      = Vector2.new(0, 0)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Visible          = false
	card.Parent           = pmFrame
	_corner(card, 10)
	_stroke(card, C_BG, 1)
	table.insert(_createdInstances, card)
	_pmCard = card

	-- "POWER" label
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text                   = "POWER"
	titleLbl.Font                   = Enum.Font.GothamBold
	titleLbl.TextSize               = 11
	titleLbl.TextColor3             = C_MUTED
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size                   = UDim2.new(1, 0, 0, 20)
	titleLbl.Position               = UDim2.new(0, 0, 0, 10)
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Center
	titleLbl.Parent                 = card

	-- Track (dark bg for the fill bar)
	local track = Instance.new("Frame")
	track.Size             = UDim2.new(0, 28, 0, 180)
	track.Position         = UDim2.new(0.5, 0, 0, 36)
	track.AnchorPoint      = Vector2.new(0.5, 0)
	track.BackgroundColor3 = C_BG
	track.BorderSizePixel  = 0
	track.ClipsDescendants = true
	track.Parent           = card
	_corner(track, 6)
	_stroke(track, C_BG, 1)

	-- GOLD tick marks at 60% and 85% thresholds — ONE gold element on this widget
	for _, frac in ipairs({ 0.40, 0.15 }) do   -- 60% = 0.40 from top, 85% = 0.15 from top
		local tick = Instance.new("Frame")
		tick.Size             = UDim2.new(1, 8, 0, 1)
		tick.Position         = UDim2.new(0, -4, frac, 0)
		tick.BackgroundColor3 = C_GOLD
		tick.BorderSizePixel  = 0
		tick.Parent           = track
	end

	-- Fill bar (grows from bottom)
	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(1, 0, 0, 0)
	fill.Position         = UDim2.new(0, 0, 1, 0)
	fill.AnchorPoint      = Vector2.new(0, 1)
	fill.BackgroundColor3 = C_CTA
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	_corner(fill, 4)
	_fillBar = fill

	-- Percentage label at bottom
	local pct = Instance.new("TextLabel")
	pct.Text                   = "0%"
	pct.Font                   = Enum.Font.GothamBold
	pct.TextSize               = 16
	pct.TextColor3             = C_WHITE
	pct.BackgroundTransparency = 1
	pct.Size                   = UDim2.new(1, 0, 0, 26)
	pct.Position               = UDim2.new(0, 0, 1, -32)
	pct.TextXAlignment         = Enum.TextXAlignment.Center
	pct.Parent                 = card
	_pctLabel = pct
end

-- ── Semi-public: exposed for Sprint11ClientTest ──────────────────────────────

function PowerMeterControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	local eventType = envelope.eventType
	if type(eventType) ~= "string" then return end

	if eventType == "StateChanged" then
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.playerId ~= LocalPlayer.UserId then return end

		local newState = tostring(payload.state)
		_gameState = newState
		local wasSwing = _visible
		_visible   = newState == "SWING"

		-- Auto-reset power when leaving SWING
		if wasSwing and not _visible then
			_power    = 0
			_charging = false
		end

		print(("[PowerMeterController] state → %q | visible=%s"):format(
			newState, tostring(_visible)))
		_updatePowerUI()
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PowerMeterControllerModule:SetPower(percent: number)
	_power    = math.clamp(percent, 0, 1)
	_charging = _power > 0
	_updatePowerUI()
end

function PowerMeterControllerModule:ResetPower()
	_power    = 0
	_charging = false
	_updatePowerUI()
end

function PowerMeterControllerModule:GetPower(): number
	return _power
end

function PowerMeterControllerModule:IsCharging(): boolean
	return _charging
end

function PowerMeterControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PowerMeterControllerModule:Init()
	if _initialized then
		warn("[PowerMeterController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			PowerMeterControllerModule:_onClientEvent(envelope)
		end))

	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg then
			warn("[PowerMeterController] PlayerGui not available within 15 s")
			return
		end
		local hud = (pg :: Instance):WaitForChild("HUD", 15)
		if not hud then
			warn("[PowerMeterController] HUD ScreenGui not available within 15 s")
			return
		end
		local found   = (hud :: Instance):WaitForChild("PowerMeter", 15)
		local pmFrame: Frame
		if found then
			pmFrame = found :: Frame
		else
			-- StarterGui frame not yet replicated; create a transparent fallback.
			local fallback = Instance.new("Frame")
			fallback.Name                   = "PowerMeter"
			fallback.Size                   = UDim2.new(1, 0, 1, 0)
			fallback.BackgroundTransparency = 1
			fallback.Parent                 = hud
			table.insert(_createdInstances, fallback)
			pmFrame = fallback
		end
		_buildUI(pmFrame)
		_updatePowerUI()
		print("[PowerMeterController] UI ready")
	end)

	print(("[PowerMeterController] ready (player: %s)"):format(LocalPlayer.Name))
end

function PowerMeterControllerModule:Update(_dt: number) end

function PowerMeterControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_pmCard   = nil
	_fillBar  = nil
	_pctLabel = nil

	_power        = 0
	_charging     = false
	_visible      = false
	_gameState    = "LOBBY"
	_initialized  = false
end

return PowerMeterControllerModule
