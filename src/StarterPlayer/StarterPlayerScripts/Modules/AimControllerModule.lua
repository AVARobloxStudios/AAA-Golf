--!strict
-- AimControllerModule — Client singleton (Sprint 11)
-- Tracks the player's horizontal aim direction (unit Vector3, XZ plane) and
-- the corresponding angle in degrees from forward (0° = -Z, 90° = +X).
-- Renders a compact compass readout inside PlayerGui.HUD.AimIndicator.
--
-- Visible during TEE_OFF and SWING; hidden at all other states.
--
-- Public API
--   SetAimDirection(dir)   — normalise & store a new aim vector
--   RotateLeft()           — subtract ROTATE_STEP degrees
--   RotateRight()          — add ROTATE_STEP degrees
--   ResetAim()             — restore default forward direction
--   GetAimDirection()      — current unit Vector3 (XZ plane)
--   GetAimAngle()          — current angle in degrees [0, 360)
--   IsVisible()
--
-- GameBus events handled:
--   StateChanged — controls visibility
--
-- AimController.client.lua is the thin runner.

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

-- ── Constants ─────────────────────────────────────────────────────────────────

local ROTATE_STEP = 5   -- degrees per RotateLeft / RotateRight call
local DEFAULT_DIR = Vector3.new(0, 0, -1)   -- forward = -Z

-- States in which the aim indicator is visible.
local VISIBLE_STATES: { [string]: boolean } = {
	TEE_OFF = true,
	SWING   = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _aimDirection:     Vector3                 = DEFAULT_DIR
local _aimAngle:         number                  = 0      -- degrees [0, 360)
local _visible:          boolean                 = false
local _gameState:        string                  = "LOBBY"
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _aimCard:   Frame?     = nil
local _lblAngle:  TextLabel? = nil   -- "90°" readout
local _lblDir:    TextLabel? = nil   -- "E" / "NW" cardinal label

-- ── Module ───────────────────────────────────────────────────────────────────

local AimControllerModule = {}
AimControllerModule.__index = AimControllerModule

-- ── Private helpers ───────────────────────────────────────────────────────────

-- Converts angle (degrees) → 8-point cardinal label.
local function _cardinal(deg: number): string
	local n = math.round(deg / 45) % 8
	local names = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	return names[n + 1] or "N"
end

-- Recomputes _aimAngle from _aimDirection.
local function _angleFromDir(dir: Vector3): number
	local a = math.deg(math.atan2(dir.X, -dir.Z)) % 360
	return a
end

-- Recomputes _aimDirection from _aimAngle.
local function _dirFromAngle(deg: number): Vector3
	local r = math.rad(deg)
	return Vector3.new(math.sin(r), 0, -math.cos(r))
end

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

local function _updateAimUI()
	if _aimCard then
		_aimCard.Visible = _visible
	end
	if _lblAngle then
		_lblAngle.Text = ("%d°"):format(math.round(_aimAngle))
	end
	if _lblDir then
		_lblDir.Text = _cardinal(_aimAngle)
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(aimFrame: Frame)
	-- Compact compass card — bottom-centre, non-obstructive
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 240, 0, 68)
	card.Position         = UDim2.new(0.5, 0, 1, -90)
	card.AnchorPoint      = Vector2.new(0.5, 0)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Visible          = false
	card.Parent           = aimFrame
	_corner(card, 10)
	_stroke(card, C_BG, 1)
	table.insert(_createdInstances, card)
	_aimCard = card

	-- "AIM" label
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text                   = "AIM"
	titleLbl.Font                   = Enum.Font.GothamBold
	titleLbl.TextSize               = 11
	titleLbl.TextColor3             = C_MUTED
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size                   = UDim2.new(0, 40, 1, 0)
	titleLbl.Position               = UDim2.new(0, 12, 0, 0)
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
	titleLbl.TextYAlignment         = Enum.TextYAlignment.Center
	titleLbl.Parent                 = card

	-- Cardinal direction (GOLD — the ONE gold element on this widget)
	local dirLbl = Instance.new("TextLabel")
	dirLbl.Text                   = "N"
	dirLbl.Font                   = Enum.Font.GothamBold
	dirLbl.TextSize               = 22
	dirLbl.TextColor3             = C_GOLD
	dirLbl.BackgroundTransparency = 1
	dirLbl.Size                   = UDim2.new(0, 52, 1, 0)
	dirLbl.Position               = UDim2.new(0.5, -26, 0, 0)
	dirLbl.TextXAlignment         = Enum.TextXAlignment.Center
	dirLbl.TextYAlignment         = Enum.TextYAlignment.Center
	dirLbl.Parent                 = card
	_lblDir = dirLbl

	-- Degree readout
	local angleLbl = Instance.new("TextLabel")
	angleLbl.Text                   = "0°"
	angleLbl.Font                   = Enum.Font.GothamBold
	angleLbl.TextSize               = 14
	angleLbl.TextColor3             = C_WHITE
	angleLbl.BackgroundTransparency = 1
	angleLbl.Size                   = UDim2.new(0, 60, 1, 0)
	angleLbl.Position               = UDim2.new(1, -72, 0, 0)
	angleLbl.TextXAlignment         = Enum.TextXAlignment.Right
	angleLbl.TextYAlignment         = Enum.TextYAlignment.Center
	angleLbl.Parent                 = card
	_lblAngle = angleLbl

	-- Thin CTA separator under title
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(0, 1, 0, 32)
	sep.Position         = UDim2.new(0, 58, 0.5, 0)
	sep.AnchorPoint      = Vector2.new(0, 0.5)
	sep.BackgroundColor3 = C_CTA
	sep.BorderSizePixel  = 0
	sep.Parent           = card
end

-- ── Semi-public: exposed for Sprint11ClientTest ──────────────────────────────

function AimControllerModule:_onClientEvent(envelope: any)
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

		print(("[AimController] state → %q | visible=%s"):format(
			newState, tostring(_visible)))
		_updateAimUI()
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Accepts any direction in world space; only XZ components used.
function AimControllerModule:SetAimDirection(dir: Vector3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.001 then
		warn("[AimController] SetAimDirection: degenerate vector ignored")
		return
	end
	_aimDirection = flat.Unit
	_aimAngle     = _angleFromDir(_aimDirection)
	_updateAimUI()
end

function AimControllerModule:RotateLeft()
	_aimAngle     = (_aimAngle - ROTATE_STEP) % 360
	_aimDirection = _dirFromAngle(_aimAngle)
	_updateAimUI()
end

function AimControllerModule:RotateRight()
	_aimAngle     = (_aimAngle + ROTATE_STEP) % 360
	_aimDirection = _dirFromAngle(_aimAngle)
	_updateAimUI()
end

function AimControllerModule:ResetAim()
	_aimDirection = DEFAULT_DIR
	_aimAngle     = 0
	_updateAimUI()
end

function AimControllerModule:GetAimDirection(): Vector3
	return _aimDirection
end

function AimControllerModule:GetAimAngle(): number
	return _aimAngle
end

function AimControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function AimControllerModule:Init()
	if _initialized then
		warn("[AimController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			AimControllerModule:_onClientEvent(envelope)
		end))

	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg then
			warn("[AimController] PlayerGui not available within 15 s")
			return
		end
		local hud = (pg :: Instance):WaitForChild("HUD", 15)
		if not hud then
			warn("[AimController] HUD ScreenGui not available within 15 s")
			return
		end
		local found    = (hud :: Instance):WaitForChild("AimIndicator", 15)
		local aimFrame: Frame
		if found then
			aimFrame = found :: Frame
		else
			-- StarterGui frame not yet replicated; create a transparent fallback.
			local fallback = Instance.new("Frame")
			fallback.Name                   = "AimIndicator"
			fallback.Size                   = UDim2.new(1, 0, 1, 0)
			fallback.BackgroundTransparency = 1
			fallback.Parent                 = hud
			table.insert(_createdInstances, fallback)
			aimFrame = fallback
		end
		_buildUI(aimFrame)
		_updateAimUI()
		print("[AimController] UI ready")
	end)

	print(("[AimController] ready (player: %s)"):format(LocalPlayer.Name))
end

function AimControllerModule:Update(_dt: number) end

function AimControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_aimCard  = nil
	_lblAngle = nil
	_lblDir   = nil

	_aimDirection = DEFAULT_DIR
	_aimAngle     = 0
	_visible      = false
	_gameState    = "LOBBY"
	_initialized  = false
end

return AimControllerModule
