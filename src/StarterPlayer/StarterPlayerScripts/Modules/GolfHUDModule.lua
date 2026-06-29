--!strict
-- GolfHUDModule — Client, Milestone 1
-- Production gameplay HUD: Hole/Par (top-center), Strokes (top-left),
-- Distance to Pin (top-right), Lie + Ball State (bottom-left).
-- Call Init() once; use Set* to update individual fields.

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

-- ── Module ────────────────────────────────────────────────────────────────────

local GolfHUDModule = {}

-- ── Private state ─────────────────────────────────────────────────────────────

local _gui:          ScreenGui? = nil
local _lblHole:      TextLabel? = nil
local _lblStrokes:   TextLabel? = nil
local _lblDistance:  TextLabel? = nil
local _lblLie:       TextLabel? = nil
local _lblState:     TextLabel? = nil
local _puttingPanel: Frame?     = nil

-- ── Build helpers ─────────────────────────────────────────────────────────────

local PANEL_BG = Color3.fromRGB(15, 20, 30)

local function _corner(parent: Frame)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = parent
end

local function _panel(parent: ScreenGui, size: UDim2, pos: UDim2, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3       = PANEL_BG
	f.BackgroundTransparency = 0.18
	f.BorderSizePixel        = 0
	f.Size                   = size
	f.Position               = pos
	if anchor then f.AnchorPoint = anchor end
	f.Parent = parent
	_corner(f)
	return f
end

local function _label(
	parent: Frame,
	text:   string,
	size:   number,
	bold:   boolean,
	color:  Color3,
	posY:   number,
	height: number,
	alignX: Enum.TextXAlignment?
): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size                   = UDim2.new(1, -8, 0, height)
	lbl.Position               = UDim2.new(0, 4, 0, posY)
	lbl.Font                   = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	lbl.TextSize               = size
	lbl.TextColor3             = color
	lbl.TextXAlignment         = alignX or Enum.TextXAlignment.Center
	lbl.TextYAlignment         = Enum.TextYAlignment.Center
	lbl.TextTruncate           = Enum.TextTruncate.AtEnd
	lbl.Text                   = text
	lbl.Parent                 = parent
	return lbl
end

-- ── Public API ────────────────────────────────────────────────────────────────

function GolfHUDModule:Init()
	if _gui and _gui.Parent then _gui:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "GolfHUD"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 95   -- below dev overlay (99) and address prompt (200)

	-- ── Top-center: Hole + Par ─────────────────────────────────────────────────
	local topPanel = _panel(gui, UDim2.new(0, 240, 0, 40), UDim2.new(0.5, -120, 0, 10))
	_lblHole = _label(topPanel, "HOLE 1  —  PAR 4", 16, true, Color3.fromRGB(255, 255, 255), 0, 40)

	-- ── Top-left: Strokes ─────────────────────────────────────────────────────
	local spanel = _panel(gui, UDim2.new(0, 90, 0, 64), UDim2.new(0, 12, 0, 10))
	_label(spanel, "STROKES", 10, false, Color3.fromRGB(150, 162, 172), 4, 20)
	_lblStrokes = _label(spanel, "0", 26, true, Color3.fromRGB(255, 255, 255), 26, 32)

	-- ── Top-right: Distance to Pin ────────────────────────────────────────────
	local dpanel = _panel(gui, UDim2.new(0, 100, 0, 64), UDim2.new(1, -112, 0, 10))
	_label(dpanel, "TO PIN", 10, false, Color3.fromRGB(150, 162, 172), 4, 20)
	_lblDistance = _label(dpanel, "— yds", 20, true, Color3.fromRGB(255, 255, 255), 26, 32)

	-- ── Bottom-left: Lie + Ball State ─────────────────────────────────────────
	local ipanel = _panel(gui, UDim2.new(0, 210, 0, 52), UDim2.new(0, 12, 1, -68), Vector2.new(0, 1))
	_lblLie   = _label(ipanel, "LIE: TEE",  13, true,  Color3.fromRGB(110, 230, 110),  4, 22, Enum.TextXAlignment.Left)
	_lblState = _label(ipanel, "BALL: —",   12, false, Color3.fromRGB(170, 170, 170), 28, 20, Enum.TextXAlignment.Left)

	-- ── Top-center: Putting Mode banner (hidden by default) ───────────────────
	local puttingBanner = _panel(gui, UDim2.new(0, 160, 0, 28), UDim2.new(0.5, -80, 0, 56))
	puttingBanner.BackgroundColor3 = Color3.fromRGB(20, 100, 40)
	_label(puttingBanner, "PUTTING MODE", 13, true, Color3.fromRGB(100, 255, 130), 0, 28)
	puttingBanner.Visible = false
	_puttingPanel = puttingBanner

	gui.Parent = LocalPlayer.PlayerGui
	_gui       = gui
end

function GolfHUDModule:SetHole(n: number, par: number)
	if _lblHole then
		_lblHole.Text = ("HOLE %d  —  PAR %d"):format(n, par)
	end
end

function GolfHUDModule:SetStrokes(n: number)
	if _lblStrokes then _lblStrokes.Text = tostring(n) end
end

function GolfHUDModule:SetDistance(studs: number)
	if not _lblDistance then return end
	if studs <= 0 then
		_lblDistance.Text = "—"
	elseif studs < 30 then
		_lblDistance.Text = math.round(studs * 3) .. " ft"
	else
		_lblDistance.Text = math.round(studs) .. " yds"
	end
end

function GolfHUDModule:SetPuttingMode(active: boolean)
	if _puttingPanel then _puttingPanel.Visible = active end
end

function GolfHUDModule:SetLie(lie: string)
	if _lblLie then _lblLie.Text = "LIE: " .. string.upper(lie) end
end

function GolfHUDModule:SetBallState(state: string)
	if _lblState then _lblState.Text = "BALL: " .. string.upper(state) end
end

function GolfHUDModule:Destroy()
	if _gui and _gui.Parent then _gui:Destroy() end
	_gui          = nil
	_lblHole      = nil
	_lblStrokes   = nil
	_lblDistance  = nil
	_lblLie       = nil
	_lblState     = nil
	_puttingPanel = nil
end

return GolfHUDModule
