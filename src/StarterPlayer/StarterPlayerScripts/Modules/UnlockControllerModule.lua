--!strict
-- UnlockControllerModule — Client singleton (Sprint 13)
-- Manages a local queue of cosmetic unlock notifications and renders a
-- compact unlock popup using the pre-declared
-- PlayerGui.Notifications.AchievementPopup frame.
--
-- Flow: QueueUnlock(data) → ShowNextUnlock() → popup visible → user clicks
-- "Got it!" → ShowNextUnlock() called again → next or hide.
--
-- Public API
--   QueueUnlock(data)      — append an UnlockData to the notification queue
--   GetQueue()             → { UnlockData }  (copy; does not include current)
--   ClearQueue()           — empty the pending queue (does not hide current)
--   ShowNextUnlock()       — pop and display the next item; hides if queue empty
--   IsVisible()            → boolean
--
-- UnlockController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)
local C_BG    = Color3.fromRGB(13,  43,  26)

-- Rarity accent colours — Legendary reuses gold (not a second gold element:
-- rarity badge and the "UNLOCKED" header are the same gold-family accent).
local RARITY_COLORS: { [string]: Color3 } = {
	Common    = C_MUTED,
	Rare      = Color3.fromRGB(80,  140, 255),
	Epic      = Color3.fromRGB(160, 80,  255),
	Legendary = C_GOLD,
}

-- ── Types ─────────────────────────────────────────────────────────────────────

export type UnlockData = {
	itemId:      string,
	displayName: string,
	description: string?,
	rarity:      string?,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _queue:            { UnlockData }          = {}
local _currentUnlock:    UnlockData?             = nil
local _visible:          boolean                 = false
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _popupCard:  Frame?     = nil
local _lblName:    TextLabel? = nil
local _lblRarity:  TextLabel? = nil
local _lblDesc:    TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local UnlockControllerModule = {}
UnlockControllerModule.__index = UnlockControllerModule

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

local function _rarityColor(rarity: string?): Color3
	if rarity == nil then return C_MUTED end
	return RARITY_COLORS[rarity] or C_MUTED
end

local function _updatePopupUI()
	if not _popupCard then return end

	_popupCard.Visible = _visible

	if not _visible or not _currentUnlock then return end
	local data = _currentUnlock :: UnlockData

	if _lblName then
		_lblName.Text = data.displayName
	end
	if _lblRarity then
		local rarity = data.rarity or "Common"
		_lblRarity.Text       = rarity:upper()
		_lblRarity.TextColor3 = _rarityColor(data.rarity)
	end
	if _lblDesc then
		_lblDesc.Text = data.description or ""
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(achFrame: Frame)
	-- Compact toast-style unlock popup — top-centre
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 360, 0, 128)
	card.Position         = UDim2.new(0.5, 0, 0, 32)
	card.AnchorPoint      = Vector2.new(0.5, 0)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Visible          = false
	card.Parent           = achFrame
	_corner(card, 12)
	_stroke(card, C_BG, 1)
	table.insert(_createdInstances, card)
	_popupCard = card

	-- "✦ UNLOCKED" — GOLD header (ONE gold element on this popup)
	local headerLbl = Instance.new("TextLabel")
	headerLbl.Text                   = "✦  UNLOCKED"
	headerLbl.Font                   = Enum.Font.GothamBold
	headerLbl.TextSize               = 12
	headerLbl.TextColor3             = C_GOLD
	headerLbl.BackgroundTransparency = 1
	headerLbl.Size                   = UDim2.new(1, -100, 0, 20)
	headerLbl.Position               = UDim2.new(0, 16, 0, 10)
	headerLbl.TextXAlignment         = Enum.TextXAlignment.Left
	headerLbl.Parent                 = card

	-- Item display name (large, white)
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Text                   = ""
	nameLbl.Font                   = Enum.Font.GothamBold
	nameLbl.TextSize               = 22
	nameLbl.TextColor3             = C_WHITE
	nameLbl.BackgroundTransparency = 1
	nameLbl.Size                   = UDim2.new(1, -100, 0, 30)
	nameLbl.Position               = UDim2.new(0, 16, 0, 32)
	nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
	nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
	nameLbl.Parent                 = card
	_lblName = nameLbl

	-- Rarity badge
	local rarityLbl = Instance.new("TextLabel")
	rarityLbl.Text                   = "COMMON"
	rarityLbl.Font                   = Enum.Font.GothamBold
	rarityLbl.TextSize               = 11
	rarityLbl.TextColor3             = C_MUTED
	rarityLbl.BackgroundTransparency = 1
	rarityLbl.Size                   = UDim2.new(1, -100, 0, 18)
	rarityLbl.Position               = UDim2.new(0, 16, 0, 64)
	rarityLbl.TextXAlignment         = Enum.TextXAlignment.Left
	rarityLbl.Parent                 = card
	_lblRarity = rarityLbl

	-- Description (muted, small)
	local descLbl = Instance.new("TextLabel")
	descLbl.Text                   = ""
	descLbl.Font                   = Enum.Font.Gotham
	descLbl.TextSize               = 11
	descLbl.TextColor3             = C_MUTED
	descLbl.BackgroundTransparency = 1
	descLbl.Size                   = UDim2.new(1, -100, 0, 16)
	descLbl.Position               = UDim2.new(0, 16, 0, 84)
	descLbl.TextXAlignment         = Enum.TextXAlignment.Left
	descLbl.TextTruncate           = Enum.TextTruncate.AtEnd
	descLbl.Parent                 = card
	_lblDesc = descLbl

	-- "Got it!" CTA button — right side
	local gotItBtn = Instance.new("TextButton")
	gotItBtn.Text             = "Got it!"
	gotItBtn.Font             = Enum.Font.GothamBold
	gotItBtn.TextSize         = 14
	gotItBtn.TextColor3       = Color3.fromRGB(7, 28, 16)
	gotItBtn.BackgroundColor3 = C_CTA
	gotItBtn.BorderSizePixel  = 0
	gotItBtn.Size             = UDim2.new(0, 80, 0, 44)
	gotItBtn.Position         = UDim2.new(1, -92, 0.5, 0)
	gotItBtn.AnchorPoint      = Vector2.new(0, 0.5)
	gotItBtn.AutoButtonColor  = true
	gotItBtn.Parent           = card
	_corner(gotItBtn, 8)

	gotItBtn.Activated:Connect(function()
		if not _initialized then return end
		UnlockControllerModule:ShowNextUnlock()
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Appends an unlock notification to the pending queue.
function UnlockControllerModule:QueueUnlock(data: UnlockData)
	if type(data) ~= "table" or type(data.itemId) ~= "string" or data.itemId == "" then
		warn("[UnlockController] QueueUnlock: invalid UnlockData — ignored")
		return
	end
	table.insert(_queue, {
		itemId      = data.itemId,
		displayName = data.displayName or data.itemId,
		description = data.description,
		rarity      = data.rarity,
	})
end

-- Returns a copy of the pending queue (does not include the currently displayed item).
function UnlockControllerModule:GetQueue(): { UnlockData }
	local copy: { UnlockData } = {}
	for i, item in ipairs(_queue) do
		copy[i] = {
			itemId      = item.itemId,
			displayName = item.displayName,
			description = item.description,
			rarity      = item.rarity,
		}
	end
	return copy
end

-- Empties the pending queue.  Does not affect the currently displayed popup.
function UnlockControllerModule:ClearQueue()
	table.clear(_queue)
end

-- Shows the next item in the queue.  Hides the popup if the queue is empty.
function UnlockControllerModule:ShowNextUnlock()
	if #_queue == 0 then
		_currentUnlock = nil
		_visible       = false
		_updatePopupUI()
		return
	end
	_currentUnlock = table.remove(_queue, 1)
	_visible       = true
	_updatePopupUI()
end

function UnlockControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function UnlockControllerModule:Init()
	if _initialized then
		warn("[UnlockController] Init called twice — skipping")
		return
	end
	_initialized = true

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end

		local notifGui = (pg :: Instance):WaitForChild("Notifications", 15)
		if not notifGui or not _initialized then return end

		local achFrame =
			(notifGui :: Instance):WaitForChild("AchievementPopup", 15) :: Frame?
		if not achFrame or not _initialized then return end

		_buildUI(achFrame :: Frame)
		_updatePopupUI()
		print("[UnlockController] UI ready")
	end)

	print(("[UnlockController] ready (player: %s)"):format(LocalPlayer.Name))
end

function UnlockControllerModule:Update(_dt: number) end

function UnlockControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_popupCard = nil
	_lblName   = nil
	_lblRarity = nil
	_lblDesc   = nil

	table.clear(_queue)
	_currentUnlock = nil
	_visible       = false
	_initialized   = false
end

return UnlockControllerModule
