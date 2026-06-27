--!strict
-- FeedbackControllerModule — Client singleton (Sprint 17)
-- Displays a single toast notification driven by ShowMessage / ClearMessage.
--
-- UI is built inside PlayerGui.Notifications.ToastNotification (pre-declared
-- StarterGui frame).  If the frame is not available within 15 s a transparent
-- fallback Frame is created in its place, following the Sprint 15 pattern.
--
-- Valid message types and their accent colors:
--   Info    — cornflower blue  (100, 149, 237)
--   Success — CTA green        (76,  175, 125)
--   Warning — amber            (245, 200,  66)
--   Error   — red              (220,  60,  60)
--   Reward  — championship gold — ONE gold element on this screen
--
-- Public API
--   ShowMessage(message, messageType)  — display toast; warns on bad type
--   ClearMessage()                     — hide toast and clear state
--   GetMessage()                       → string
--   GetMessageType()                   → string
--   IsVisible()                        → boolean
--
-- FeedbackController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)
local C_BG    = Color3.fromRGB(13,  43,  26)

-- ── Message type catalogue ────────────────────────────────────────────────────

local VALID_TYPES: { [string]: boolean } = {
	Info    = true,
	Success = true,
	Warning = true,
	Error   = true,
	Reward  = true,
}

local TYPE_COLORS: { [string]: Color3 } = {
	Info    = Color3.fromRGB(100, 149, 237),
	Success = C_CTA,
	Warning = Color3.fromRGB(245, 200,  66),
	Error   = Color3.fromRGB(220,  60,  60),
	Reward  = C_GOLD,   -- ONE gold element on this screen
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _message:          string                  = ""
local _messageType:      string                  = ""
local _visible:          boolean                 = false
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references ────────────────────────────────────────────────────────────

local _toastCard:   Frame?     = nil
local _barType:     Frame?     = nil
local _lblMessage:  TextLabel? = nil
local _lblType:     TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local FeedbackControllerModule = {}
FeedbackControllerModule.__index = FeedbackControllerModule

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
	if not _toastCard then return end
	_toastCard.Visible = _visible

	local typeColor = TYPE_COLORS[_messageType] or C_MUTED
	if _barType    then _barType.BackgroundColor3    = typeColor end
	if _lblType    then
		_lblType.Text       = _messageType
		_lblType.TextColor3 = typeColor
	end
	if _lblMessage then _lblMessage.Text = _message end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildToast(parent: Frame)
	-- Toast card — top-centre, compact pill
	local card = Instance.new("Frame")
	card.Name             = "FeedbackToastCard"
	card.Size             = UDim2.new(0, 400, 0, 64)
	card.Position         = UDim2.new(0.5, 0, 0, 16)
	card.AnchorPoint      = Vector2.new(0.5, 0)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Visible          = false
	card.Parent           = parent
	table.insert(_createdInstances, card)
	_corner(card, 10)
	_stroke(card, C_BG, 1)
	_toastCard = card

	-- Left accent bar (colour reflects message type)
	local bar = Instance.new("Frame")
	bar.Name             = "TypeBar"
	bar.Size             = UDim2.new(0, 6, 1, -16)
	bar.Position         = UDim2.new(0, 8, 0.5, 0)
	bar.AnchorPoint      = Vector2.new(0, 0.5)
	bar.BackgroundColor3 = C_MUTED
	bar.BorderSizePixel  = 0
	bar.Parent           = card
	_corner(bar, 3)
	_barType = bar

	-- Message type label (small, coloured)
	local typeLbl = Instance.new("TextLabel")
	typeLbl.Text                   = ""
	typeLbl.Font                   = Enum.Font.GothamBold
	typeLbl.TextSize               = 11
	typeLbl.TextColor3             = C_MUTED
	typeLbl.BackgroundTransparency = 1
	typeLbl.Size                   = UDim2.new(0, 100, 0, 16)
	typeLbl.Position               = UDim2.new(0, 22, 0, 8)
	typeLbl.TextXAlignment         = Enum.TextXAlignment.Left
	typeLbl.Parent                 = card
	_lblType = typeLbl

	-- Main message label
	local msgLbl = Instance.new("TextLabel")
	msgLbl.Text                   = ""
	msgLbl.Font                   = Enum.Font.Gotham
	msgLbl.TextSize               = 15
	msgLbl.TextColor3             = C_WHITE
	msgLbl.BackgroundTransparency = 1
	msgLbl.Size                   = UDim2.new(1, -80, 0, 26)
	msgLbl.Position               = UDim2.new(0, 22, 0, 26)
	msgLbl.TextXAlignment         = Enum.TextXAlignment.Left
	msgLbl.TextTruncate           = Enum.TextTruncate.AtEnd
	msgLbl.Parent                 = card
	_lblMessage = msgLbl

	-- Dismiss button (top-right of card)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text             = "✕"
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextSize         = 13
	closeBtn.TextColor3       = C_MUTED
	closeBtn.BackgroundColor3 = C_BG
	closeBtn.BorderSizePixel  = 0
	closeBtn.Size             = UDim2.new(0, 36, 0, 36)
	closeBtn.Position         = UDim2.new(1, -44, 0.5, 0)
	closeBtn.AnchorPoint      = Vector2.new(0, 0.5)
	closeBtn.AutoButtonColor  = true
	closeBtn.Parent           = card
	_corner(closeBtn, 8)

	closeBtn.Activated:Connect(function()
		if not _initialized then return end
		FeedbackControllerModule:ClearMessage()
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Displays a toast notification.  Warns and no-ops for unknown message types.
function FeedbackControllerModule:ShowMessage(message: string, messageType: string)
	if not VALID_TYPES[messageType] then
		warn(("[FeedbackController] ShowMessage: unknown type %q"):format(
			tostring(messageType)))
		return
	end
	_message     = message
	_messageType = messageType
	_visible     = true
	_updateUI()
end

function FeedbackControllerModule:ClearMessage()
	_message     = ""
	_messageType = ""
	_visible     = false
	_updateUI()
end

function FeedbackControllerModule:GetMessage(): string
	return _message
end

function FeedbackControllerModule:GetMessageType(): string
	return _messageType
end

function FeedbackControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function FeedbackControllerModule:Init()
	if _initialized then
		warn("[FeedbackController] Init called twice — skipping")
		return
	end
	_initialized = true

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end

		local notifs = (pg :: Instance):WaitForChild("Notifications", 15)
		if not notifs or not _initialized then
			warn("[FeedbackController] Notifications ScreenGui not available within 15 s")
			return
		end

		local found = (notifs :: Instance):WaitForChild("ToastNotification", 15)
		local toastFrame: Frame
		if found then
			toastFrame = found :: Frame
		else
			local fallback = Instance.new("Frame")
			fallback.Name                   = "ToastNotification"
			fallback.Size                   = UDim2.new(1, 0, 1, 0)
			fallback.BackgroundTransparency = 1
			fallback.Parent                 = notifs
			table.insert(_createdInstances, fallback)
			toastFrame = fallback
		end

		_buildToast(toastFrame)
		_updateUI()
		print("[FeedbackController] UI ready")
	end)

	print(("[FeedbackController] ready (player: %s)"):format(LocalPlayer.Name))
end

function FeedbackControllerModule:Update(_dt: number) end

function FeedbackControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_toastCard  = nil
	_barType    = nil
	_lblMessage = nil
	_lblType    = nil

	_message     = ""
	_messageType = ""
	_visible     = false
	_initialized = false
end

return FeedbackControllerModule
