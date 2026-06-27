--!strict
-- PurchasePreviewControllerModule — Client singleton (Sprint 14)
-- Tracks the currently previewed cosmetic item and renders a compact
-- preview popup.  No items are granted, no currency is deducted.
--
-- The popup is built as a code-created ScreenGui added to PlayerGui
-- (no StarterGui frame exists for this).  It is tracked in _createdInstances
-- for clean Destroy() teardown.
--
-- Public API
--   PreviewItem(itemData)    — store item and show preview popup
--   ClearPreview()           — hide popup and clear stored item
--   GetPreviewItem()         → PreviewItemData?  (deep copy)
--   IsPreviewing()           → boolean
--
-- PurchasePreviewController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG    = Color3.fromRGB(13,  43,  26)
local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)

-- Rarity accent colours (independent of the gold-per-screen rule: this is
-- a data-driven badge, not a design-accent element).
local RARITY_COLORS: { [string]: Color3 } = {
	Common    = C_MUTED,
	Rare      = Color3.fromRGB(80,  140, 255),
	Epic      = Color3.fromRGB(160, 80,  255),
	Legendary = C_GOLD,
}

-- ── Types ─────────────────────────────────────────────────────────────────────

-- Matches StorefrontControllerModule.StoreItem fields, all optional except itemId.
export type PreviewItemData = {
	itemId:      string,
	displayName: string,
	category:    string,
	rarity:      string,
	priceCoins:  number,
	premiumOnly: boolean,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _previewItem:      PreviewItemData?         = nil
local _isPreviewing:     boolean                 = false
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _previewGui:  ScreenGui? = nil
local _card:        Frame?     = nil
local _lblName:     TextLabel? = nil
local _lblCategory: TextLabel? = nil
local _lblRarity:   TextLabel? = nil
local _lblPrice:    TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local PurchasePreviewControllerModule = {}
PurchasePreviewControllerModule.__index = PurchasePreviewControllerModule

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

local function _rarityColor(rarity: string): Color3
	return RARITY_COLORS[rarity] or C_MUTED
end

local function _updatePreviewUI()
	if not _previewGui then return end
	_previewGui.Enabled = _isPreviewing

	if not _isPreviewing or not _previewItem then return end
	local item = _previewItem :: PreviewItemData

	if _lblName     then _lblName.Text     = item.displayName                      end
	if _lblCategory then _lblCategory.Text = item.category                          end
	if _lblRarity   then
		_lblRarity.Text       = item.rarity:upper()
		_lblRarity.TextColor3 = _rarityColor(item.rarity)
	end
	if _lblPrice    then
		if item.premiumOnly then
			_lblPrice.Text = "Premium Only"
		else
			_lblPrice.Text = tostring(item.priceCoins) .. " Coins"
		end
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(pg: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name           = "PurchasePreviewGui"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled        = false
	gui.Parent         = pg
	table.insert(_createdInstances, gui)
	_previewGui = gui

	-- Centred preview card
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 340, 0, 240)
	card.Position         = UDim2.new(0.5, 0, 0.5, 0)
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Parent           = gui
	_corner(card, 14)
	_stroke(card, C_BG, 1)
	_card = card

	-- "PREVIEW" header — GOLD (ONE gold element on this popup)
	local headerLbl = Instance.new("TextLabel")
	headerLbl.Text                   = "✦  PREVIEW"
	headerLbl.Font                   = Enum.Font.GothamBold
	headerLbl.TextSize               = 13
	headerLbl.TextColor3             = C_GOLD
	headerLbl.BackgroundTransparency = 1
	headerLbl.Size                   = UDim2.new(1, -24, 0, 24)
	headerLbl.Position               = UDim2.new(0, 16, 0, 12)
	headerLbl.TextXAlignment         = Enum.TextXAlignment.Left
	headerLbl.Parent                 = card

	-- Item display name
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Text                   = ""
	nameLbl.Font                   = Enum.Font.GothamBold
	nameLbl.TextSize               = 24
	nameLbl.TextColor3             = C_WHITE
	nameLbl.BackgroundTransparency = 1
	nameLbl.Size                   = UDim2.new(1, -24, 0, 34)
	nameLbl.Position               = UDim2.new(0, 16, 0, 40)
	nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
	nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
	nameLbl.Parent                 = card
	_lblName = nameLbl

	-- Category badge (muted)
	local catLbl = Instance.new("TextLabel")
	catLbl.Text                   = ""
	catLbl.Font                   = Enum.Font.Gotham
	catLbl.TextSize               = 12
	catLbl.TextColor3             = C_MUTED
	catLbl.BackgroundTransparency = 1
	catLbl.Size                   = UDim2.new(1, -24, 0, 18)
	catLbl.Position               = UDim2.new(0, 16, 0, 76)
	catLbl.TextXAlignment         = Enum.TextXAlignment.Left
	catLbl.Parent                 = card
	_lblCategory = catLbl

	-- Rarity label (coloured by tier)
	local rarityLbl = Instance.new("TextLabel")
	rarityLbl.Text                   = ""
	rarityLbl.Font                   = Enum.Font.GothamBold
	rarityLbl.TextSize               = 13
	rarityLbl.TextColor3             = C_MUTED
	rarityLbl.BackgroundTransparency = 1
	rarityLbl.Size                   = UDim2.new(1, -24, 0, 20)
	rarityLbl.Position               = UDim2.new(0, 16, 0, 96)
	rarityLbl.TextXAlignment         = Enum.TextXAlignment.Left
	rarityLbl.Parent                 = card
	_lblRarity = rarityLbl

	-- Price
	local priceLbl = Instance.new("TextLabel")
	priceLbl.Text                   = ""
	priceLbl.Font                   = Enum.Font.GothamBold
	priceLbl.TextSize               = 18
	priceLbl.TextColor3             = C_CTA
	priceLbl.BackgroundTransparency = 1
	priceLbl.Size                   = UDim2.new(1, -24, 0, 28)
	priceLbl.Position               = UDim2.new(0, 16, 0, 122)
	priceLbl.TextXAlignment         = Enum.TextXAlignment.Left
	priceLbl.Parent                 = card
	_lblPrice = priceLbl

	-- "PREVIEW ONLY" disclaimer
	local disclaimerLbl = Instance.new("TextLabel")
	disclaimerLbl.Text                   = "Preview only — no purchase will be made."
	disclaimerLbl.Font                   = Enum.Font.Gotham
	disclaimerLbl.TextSize               = 11
	disclaimerLbl.TextColor3             = C_MUTED
	disclaimerLbl.BackgroundTransparency = 1
	disclaimerLbl.Size                   = UDim2.new(1, -24, 0, 16)
	disclaimerLbl.Position               = UDim2.new(0, 16, 0, 156)
	disclaimerLbl.TextXAlignment         = Enum.TextXAlignment.Left
	disclaimerLbl.Parent                 = card

	-- CTA separator
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, -32, 0, 1)
	sep.Position         = UDim2.new(0, 16, 0, 179)
	sep.BackgroundColor3 = C_CTA
	sep.BorderSizePixel  = 0
	sep.Parent           = card

	-- "Close" button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text             = "Close"
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextSize         = 15
	closeBtn.TextColor3       = Color3.fromRGB(7, 28, 16)
	closeBtn.BackgroundColor3 = C_CTA
	closeBtn.BorderSizePixel  = 0
	closeBtn.Size             = UDim2.new(1, -32, 0, 44)
	closeBtn.Position         = UDim2.new(0, 16, 1, -56)
	closeBtn.AutoButtonColor  = true
	closeBtn.Parent           = card
	_corner(closeBtn, 10)

	closeBtn.Activated:Connect(function()
		if not _initialized then return end
		PurchasePreviewControllerModule:ClearPreview()
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Stores a preview item and shows the popup.
-- Accepts any table with at least an itemId field.
-- Does NOT grant items or deduct currency.
function PurchasePreviewControllerModule:PreviewItem(itemData: { [string]: any })
	if type(itemData) ~= "table" then
		warn("[PurchasePreviewController] PreviewItem: expected table — ignored")
		return
	end
	local rawId = itemData.itemId
	if type(rawId) ~= "string" or rawId == "" then
		warn("[PurchasePreviewController] PreviewItem: missing itemId — ignored")
		return
	end
	_previewItem = {
		itemId      = rawId,
		displayName = type(itemData.displayName) == "string"
			and itemData.displayName or rawId,
		category    = type(itemData.category)    == "string"
			and itemData.category    or "",
		rarity      = type(itemData.rarity)      == "string"
			and itemData.rarity      or "Common",
		priceCoins  = type(itemData.priceCoins)  == "number"
			and itemData.priceCoins  or 0,
		premiumOnly = itemData.premiumOnly == true,
	}
	_isPreviewing = true
	_updatePreviewUI()
end

-- Hides the popup and clears the stored preview item.
function PurchasePreviewControllerModule:ClearPreview()
	_previewItem  = nil
	_isPreviewing = false
	_updatePreviewUI()
end

-- Returns a deep copy of the current preview item, or nil if not previewing.
function PurchasePreviewControllerModule:GetPreviewItem(): PreviewItemData?
	if not _previewItem then return nil end
	local p = _previewItem :: PreviewItemData
	return {
		itemId      = p.itemId,
		displayName = p.displayName,
		category    = p.category,
		rarity      = p.rarity,
		priceCoins  = p.priceCoins,
		premiumOnly = p.premiumOnly,
	}
end

function PurchasePreviewControllerModule:IsPreviewing(): boolean
	return _isPreviewing
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function PurchasePreviewControllerModule:Init()
	if _initialized then
		warn("[PurchasePreviewController] Init called twice — skipping")
		return
	end
	_initialized = true

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end
		_buildUI(pg :: Instance)
		_updatePreviewUI()
		print("[PurchasePreviewController] UI ready")
	end)

	print(("[PurchasePreviewController] ready (player: %s)"):format(LocalPlayer.Name))
end

function PurchasePreviewControllerModule:Update(_dt: number) end

function PurchasePreviewControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_previewGui  = nil
	_card        = nil
	_lblName     = nil
	_lblCategory = nil
	_lblRarity   = nil
	_lblPrice    = nil

	_previewItem  = nil
	_isPreviewing = false
	_initialized  = false
end

return PurchasePreviewControllerModule
