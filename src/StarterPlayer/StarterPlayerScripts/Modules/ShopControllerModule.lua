--!strict
-- ShopControllerModule — Client singleton (Sprint 14)
-- Manages shop overlay visibility and the active cosmetic category.
-- The Shop ScreenGui (StarterGui/Shop) has no pre-declared child frames, so
-- the full panel is built from code and tracked in _createdInstances.
--
-- No purchases, no currency deduction, and no inventory changes happen here.
-- ShopController is the shell; StorefrontController owns item data.
--
-- Default categories (in display order):
--   Ball Skins · Club Skins · Trails · Caddies · Nameplates · Victory Animations
--
-- Public API
--   OpenShop()                   — show the shop panel
--   CloseShop()                  — hide the shop panel
--   IsVisible()                  → boolean
--   SetActiveCategory(name)      — select a category; warns on unknown names
--   GetActiveCategory()          → string  ("" before first selection)
--   GetCategories()              → { string }  (ordered copy)
--
-- ShopController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG    = Color3.fromRGB(13,  43,  26)
local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)

-- ── Category catalogue ────────────────────────────────────────────────────────

local CATEGORIES: { string } = {
	"Ball Skins",
	"Club Skins",
	"Trails",
	"Caddies",
	"Nameplates",
	"Victory Animations",
}

local _categorySet: { [string]: boolean } = {}
for _, cat in ipairs(CATEGORIES) do _categorySet[cat] = true end

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _visible:          boolean                 = false
local _activeCategory:   string                  = ""
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _shopRoot:      Frame?                    = nil   -- root panel container
local _categoryBtns:  { [string]: TextButton }  = {}   -- cat name → button

-- ── Module ───────────────────────────────────────────────────────────────────

local ShopControllerModule = {}
ShopControllerModule.__index = ShopControllerModule

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

local function _updateCategoryBtns()
	for cat, btn in pairs(_categoryBtns) do
		if cat == _activeCategory then
			btn.BackgroundColor3 = C_CTA
			btn.TextColor3       = Color3.fromRGB(7, 28, 16)
		else
			btn.BackgroundColor3 = C_PANEL
			btn.TextColor3       = C_MUTED
		end
	end
end

local function _updateShopVisibility()
	if _shopRoot then
		_shopRoot.Visible = _visible
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(shopGui: ScreenGui)
	-- Full-screen overlay with dimmed background
	local overlay = Instance.new("Frame")
	overlay.Size                    = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3        = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency  = 0.5
	overlay.BorderSizePixel         = 0
	overlay.Visible                 = false
	overlay.Parent                  = shopGui
	table.insert(_createdInstances, overlay)
	_shopRoot = overlay

	-- Main shop panel
	local panel = Instance.new("Frame")
	panel.Size             = UDim2.new(0.84, 0, 0.80, 0)
	panel.Position         = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint      = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = C_PANEL
	panel.BorderSizePixel  = 0
	panel.Parent           = overlay
	_corner(panel, 14)
	_stroke(panel, C_BG, 1)

	-- Header bar
	local header = Instance.new("Frame")
	header.Size             = UDim2.new(1, 0, 0, 52)
	header.BackgroundColor3 = C_BG
	header.BorderSizePixel  = 0
	header.Parent           = panel
	_corner(header, 14)   -- top corners only via child override

	-- "SHOP" title — GOLD (ONE gold element on this screen)
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text                   = "⛳  SHOP"
	titleLbl.Font                   = Enum.Font.GothamBold
	titleLbl.TextSize               = 20
	titleLbl.TextColor3             = C_GOLD
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size                   = UDim2.new(1, -60, 1, 0)
	titleLbl.Position               = UDim2.new(0, 20, 0, 0)
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
	titleLbl.TextYAlignment         = Enum.TextYAlignment.Center
	titleLbl.Parent                 = header

	-- Close button (top-right of header, ≥44×44 touch target)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text             = "✕"
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextSize         = 18
	closeBtn.TextColor3       = C_MUTED
	closeBtn.BackgroundColor3 = C_BG
	closeBtn.BorderSizePixel  = 0
	closeBtn.Size             = UDim2.new(0, 44, 0, 44)
	closeBtn.Position         = UDim2.new(1, -48, 0, 4)
	closeBtn.AutoButtonColor  = true
	closeBtn.Parent           = header
	_corner(closeBtn, 8)

	closeBtn.Activated:Connect(function()
		if not _initialized then return end
		ShopControllerModule:CloseShop()
	end)

	-- Sidebar: category tabs (left column)
	local sidebar = Instance.new("Frame")
	sidebar.Size             = UDim2.new(0, 180, 1, -52)
	sidebar.Position         = UDim2.new(0, 0, 0, 52)
	sidebar.BackgroundColor3 = C_BG
	sidebar.BorderSizePixel  = 0
	sidebar.Parent           = panel

	for i, cat in ipairs(CATEGORIES) do
		local btn = Instance.new("TextButton")
		btn.Text             = cat
		btn.Font             = Enum.Font.Gotham
		btn.TextSize         = 13
		btn.TextColor3       = C_MUTED
		btn.BackgroundColor3 = C_PANEL
		btn.BorderSizePixel  = 0
		btn.Size             = UDim2.new(1, -16, 0, 44)
		btn.Position         = UDim2.new(0, 8, 0, (i - 1) * 48 + 8)
		btn.TextXAlignment   = Enum.TextXAlignment.Left
		btn.AutoButtonColor  = true
		btn.Parent           = sidebar
		_corner(btn, 8)

		local catCapture = cat
		btn.Activated:Connect(function()
			if not _initialized then return end
			ShopControllerModule:SetActiveCategory(catCapture)
		end)

		_categoryBtns[cat] = btn
	end

	-- Content area: item grid placeholder (right column)
	local content = Instance.new("Frame")
	content.Size             = UDim2.new(1, -180, 1, -52)
	content.Position         = UDim2.new(0, 180, 0, 52)
	content.BackgroundTransparency = 1
	content.BorderSizePixel  = 0
	content.Parent           = panel

	local placeholderLbl = Instance.new("TextLabel")
	placeholderLbl.Text                   = "Select a category to browse cosmetics."
	placeholderLbl.Font                   = Enum.Font.Gotham
	placeholderLbl.TextSize               = 14
	placeholderLbl.TextColor3             = C_MUTED
	placeholderLbl.BackgroundTransparency = 1
	placeholderLbl.Size                   = UDim2.new(1, 0, 1, 0)
	placeholderLbl.TextXAlignment         = Enum.TextXAlignment.Center
	placeholderLbl.TextYAlignment         = Enum.TextYAlignment.Center
	placeholderLbl.Parent                 = content

	-- Sync initial visual state
	_updateCategoryBtns()
	_updateShopVisibility()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ShopControllerModule:OpenShop()
	_visible = true
	_updateShopVisibility()
end

function ShopControllerModule:CloseShop()
	_visible = false
	_updateShopVisibility()
end

function ShopControllerModule:IsVisible(): boolean
	return _visible
end

-- Sets the active category.  Warns and no-ops for unrecognised names.
function ShopControllerModule:SetActiveCategory(name: string)
	if not _categorySet[name] then
		warn(("[ShopController] SetActiveCategory: unknown category %q"):format(
			tostring(name)))
		return
	end
	_activeCategory = name
	_updateCategoryBtns()
end

function ShopControllerModule:GetActiveCategory(): string
	return _activeCategory
end

-- Returns an ordered copy of the category list.
function ShopControllerModule:GetCategories(): { string }
	local copy: { string } = {}
	for i, cat in ipairs(CATEGORIES) do
		copy[i] = cat
	end
	return copy
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function ShopControllerModule:Init()
	if _initialized then
		warn("[ShopController] Init called twice — skipping")
		return
	end
	_initialized    = true
	_activeCategory = CATEGORIES[1]   -- default: Ball Skins

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end

		local shopGui = (pg :: Instance):WaitForChild("Shop", 15) :: ScreenGui?
		if not shopGui or not _initialized then return end

		_buildUI(shopGui :: ScreenGui)
		print("[ShopController] UI ready")
	end)

	print(("[ShopController] ready (player: %s)"):format(LocalPlayer.Name))
end

function ShopControllerModule:Update(_dt: number) end

function ShopControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	table.clear(_categoryBtns)
	_shopRoot = nil

	_visible        = false
	_activeCategory = ""
	_initialized    = false
end

return ShopControllerModule
