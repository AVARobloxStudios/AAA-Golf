--!strict
-- ClubHUDModule — Client, Milestone 2
-- Bottom-right panel: selected club name, expected carry, distance to pin, lie, wind.
-- Call Init() once; use Set* to update fields after server events.

local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ClubHUDModule = {}

local _gui:      ScreenGui? = nil
local _lblClub:  TextLabel? = nil
local _lblCarry: TextLabel? = nil
local _lblDist:  TextLabel? = nil
local _lblLie:   TextLabel? = nil

local PANEL_BG = Color3.fromRGB(15, 20, 30)
local DIM      = Color3.fromRGB(130, 145, 158)
local WHITE    = Color3.fromRGB(255, 255, 255)

-- ── Build helpers ─────────────────────────────────────────────────────────────

local function _corner(p: Frame)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = p
end

local function _frame(
	parent: ScreenGui | Frame,
	size: UDim2, pos: UDim2,
	anchor: Vector2?,
	bg: Color3?,
	bgTrans: number?
): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3       = bg       or PANEL_BG
	f.BackgroundTransparency = bgTrans  or 0.18
	f.BorderSizePixel        = 0
	f.Size                   = size
	f.Position               = pos
	if anchor then f.AnchorPoint = anchor end
	f.Parent = parent
	return f
end

local function _lbl(
	parent: Frame, text: string,
	sz: number, bold: boolean, color: Color3,
	posY: number, h: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size                   = UDim2.new(1, -12, 0, h)
	l.Position               = UDim2.new(0, 8, 0, posY)
	l.Font                   = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize               = sz
	l.TextColor3             = color
	l.TextXAlignment         = Enum.TextXAlignment.Left
	l.TextYAlignment         = Enum.TextYAlignment.Center
	l.TextTruncate           = Enum.TextTruncate.AtEnd
	l.Text                   = text
	l.Parent                 = parent
	return l
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ClubHUDModule:Init()
	if _gui and _gui.Parent then _gui:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "ClubHUD"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 94   -- just below GolfHUD (95)

	-- 190 × 158 panel anchored to bottom-right corner
	local p = _frame(gui,
		UDim2.new(0, 190, 0, 158),
		UDim2.new(1, -10, 1, -10),
		Vector2.new(1, 1))
	_corner(p)

	-- Club name (large, top of panel)
	_lblClub = _lbl(p, "Driver", 18, true, WHITE, 7, 24)

	-- Thin divider below name
	local div = _frame(p :: any,
		UDim2.new(1, -16, 0, 1),
		UDim2.new(0, 8, 0, 36),
		nil,
		Color3.fromRGB(55, 68, 82),
		0.2)

	-- Row: Carry
	_lbl(p, "CARRY",    10, false, DIM,   42, 13)
	_lblCarry = _lbl(p, "—",  13, true,  WHITE, 55, 16)

	-- Row: Distance
	_lbl(p, "DISTANCE", 10, false, DIM,   76, 13)
	_lblDist  = _lbl(p, "—",  13, true,  WHITE, 89, 16)

	-- Row: Lie
	_lbl(p, "LIE",      10, false, DIM,  110, 13)
	_lblLie   = _lbl(p, "—",  13, true,  WHITE,123, 16)

	-- Row: Wind (static placeholder — future feature)
	_lbl(p, "WIND",     10, false, DIM,  142, 12)
	_lbl(p, "0 mph",    11, false, DIM,  154, 12)

	gui.Parent = LocalPlayer.PlayerGui
	_gui       = gui
end

--- Update displayed club name and expected carry (from ClubDefinition).
function ClubHUDModule:SetClub(clubDef: any)
	if _lblClub then
		_lblClub.Text = tostring(clubDef.displayName)
	end
	if _lblCarry then
		local yards = clubDef.maxRangeYards
		_lblCarry.Text = if yards then (math.round(yards) .. " yds") else "—"
	end
end

--- Update distance remaining to pin (studs; auto-converts to yds or ft).
function ClubHUDModule:SetDistance(studs: number)
	if not _lblDist then return end
	if studs <= 0 then
		_lblDist.Text = "—"
	elseif studs < 30 then
		_lblDist.Text = math.round(studs * 3) .. " ft"
	else
		_lblDist.Text = math.round(studs) .. " yds"
	end
end

--- Update the displayed lie.
function ClubHUDModule:SetLie(lie: string)
	if _lblLie then _lblLie.Text = lie end
end

function ClubHUDModule:Destroy()
	if _gui and _gui.Parent then _gui:Destroy() end
	_gui      = nil
	_lblClub  = nil
	_lblCarry = nil
	_lblDist  = nil
	_lblLie   = nil
end

return ClubHUDModule
