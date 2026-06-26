--!strict
-- MenuControllerModule — Client singleton (Sprint 10)
-- Controls the Lobby ScreenGui panel visibility and tracks the active menu
-- panel.  UI is built to the Fairway Pro design-token system (VS §05):
--   Background  #0D2B1A  deep fairway
--   CTA green   #4CAF7D  sole primary-action colour
--   Gold        #C8980A  exactly one element per screen
-- MenuController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG     = Color3.fromRGB(13,  43,  26)   -- #0D2B1A deep fairway
local C_CTA    = Color3.fromRGB(76,  175, 125)  -- #4CAF7D CTA green
local C_GOLD   = Color3.fromRGB(200, 152, 10)   -- #C8980A championship gold
local C_WHITE  = Color3.fromRGB(255, 255, 255)
local C_MUTED  = Color3.fromRGB(140, 180, 155)  -- secondary / disabled text
local C_PANEL  = Color3.fromRGB(7,   28,  16)   -- card / panel background
local C_DIVIDE = Color3.fromRGB(25,  65,  40)   -- subtle separator / locked border

-- ── Panel map ────────────────────────────────────────────────────────────────

local PANEL_MAP: { [string]: string } = {
	MainMenu         = "MainMenu",
	CourseSelect     = "CourseSelectScreen",
	AvatarCustomiser = "AvatarCustomiser",
	FriendsPanel     = "FriendsPanel",
	Matchmaking      = "MatchmakingModal",
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:       boolean                 = false
local _visible:           boolean                 = false
local _activeMenu:        string                  = ""
local _connections:       { RBXScriptConnection } = {}
local _createdInstances:  { Instance }            = {}   -- destroyed in Destroy()

-- ── UI references (populated async) ──────────────────────────────────────────

local _lobbyGui: ScreenGui? = nil
local _lblCoins: TextLabel? = nil   -- live-updated Coins display in MainMenu

-- ── Module ───────────────────────────────────────────────────────────────────

local MenuControllerModule = {}
MenuControllerModule.__index = MenuControllerModule

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
	parent:   Instance,
	text:     string,
	font:     Enum.Font,
	sz:       number,
	color:    Color3,
	pos:      UDim2,
	size:     UDim2,
	anchor:   Vector2?
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

local function _btn(
	parent:    Instance,
	text:      string,
	font:      Enum.Font,
	sz:        number,
	textColor: Color3,
	bgColor:   Color3,
	pos:       UDim2,
	size:      UDim2,
	anchor:    Vector2?,
	cornerPx:  number?
): TextButton
	local b = Instance.new("TextButton")
	b.Text            = text
	b.Font            = font
	b.TextSize        = sz
	b.TextColor3      = textColor
	b.BackgroundColor3 = bgColor
	b.BorderSizePixel = 0
	b.Position        = pos
	b.Size            = size
	b.AnchorPoint     = anchor or Vector2.new(0.5, 0.5)
	b.TextXAlignment  = Enum.TextXAlignment.Center
	b.Parent          = parent
	if cornerPx then _corner(b, cornerPx) end
	return b
end

-- ── Panel builders ────────────────────────────────────────────────────────────

local function _buildMainMenu(frame: Frame)
	-- Root background — makes the transparent Rojo frame opaque.
	local bg = Instance.new("Frame")
	bg.Size              = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3  = C_BG
	bg.BorderSizePixel   = 0
	bg.Parent            = frame
	table.insert(_createdInstances, bg)   -- track for Destroy()

	-- ── Gold coin chip (top-right) ────────────────────────────────────────────
	-- GOLD RULE: this is the ONE gold element on this screen.
	local chip = Instance.new("Frame")
	chip.Size             = UDim2.new(0, 168, 0, 44)
	chip.Position         = UDim2.new(1, -184, 0, 16)
	chip.AnchorPoint      = Vector2.new(0, 0)
	chip.BackgroundColor3 = C_PANEL
	chip.BorderSizePixel  = 0
	chip.Parent           = bg
	_corner(chip, 22)
	_stroke(chip, C_GOLD, 2)
	local coinLbl = _lbl(chip, "⛳  0  Coins",
		Enum.Font.GothamBold, 15, C_GOLD,
		UDim2.new(0.5, 0, 0.5, 0), UDim2.new(1, -12, 1, 0))
	_lblCoins = coinLbl

	-- ── Logo ─────────────────────────────────────────────────────────────────
	_lbl(bg, "⛳  AAA GOLF",
		Enum.Font.GothamBold, 52, C_WHITE,
		UDim2.new(0.5, 0, 0.30, 0), UDim2.new(0, 480, 0, 70))
	_lbl(bg, "Sunnybrook Meadows  —  Course 1",
		Enum.Font.Gotham, 17, C_CTA,
		UDim2.new(0.5, 0, 0.39, 0), UDim2.new(0, 400, 0, 28))

	-- ── Primary CTA — the sole CTA-green button on this screen ───────────────
	local playBtn = _btn(bg, "PLAY NOW",
		Enum.Font.GothamBold, 22, C_WHITE, C_CTA,
		UDim2.new(0.5, 0, 0.52, 0), UDim2.new(0, 360, 0, 58), nil, 10)
	playBtn.AutoButtonColor = true
	-- TODO (UIController, Phase 1): route to GameService:StartRound on Course 1
	playBtn.Activated:Connect(function()
		if not _initialized then return end
		print("[MenuController] PLAY NOW — routing deferred to UIController")
	end)

	-- ── Secondary: Course Select ──────────────────────────────────────────────
	local csBtn = _btn(bg, "Course Select",
		Enum.Font.GothamBold, 18, C_CTA, C_PANEL,
		UDim2.new(0.5, 0, 0.62, 0), UDim2.new(0, 320, 0, 50), nil, 8)
	_stroke(csBtn, C_CTA, 1)
	csBtn.Activated:Connect(function()
		if not _initialized then return end
		MenuControllerModule:OpenMenu("CourseSelect")
	end)

	-- ── Tertiary: Settings ────────────────────────────────────────────────────
	local settingsBtn = _btn(bg, "⚙  Settings",
		Enum.Font.Gotham, 16, C_MUTED, C_BG,
		UDim2.new(0.5, 0, 0.72, 0), UDim2.new(0, 200, 0, 44), nil, 6)
	settingsBtn.BackgroundTransparency = 1
	-- TODO (UIController): open SettingsController screen
	settingsBtn.Activated:Connect(function()
		if not _initialized then return end
		print("[MenuController] Settings — routing deferred to UIController")
	end)

	-- ── Daily streak placeholder ──────────────────────────────────────────────
	-- TODO (DailyRewardsController, Phase 2): bind to PlayerDataService streak value
	_lbl(bg, "🔥  Day 1 Streak  —  Log in daily for rewards",
		Enum.Font.Gotham, 13, C_MUTED,
		UDim2.new(0.5, 0, 0.88, 0), UDim2.new(0, 440, 0, 22))

	-- TODO (Phase 4): Battle Pass / Clubhouse Pass strip goes here
end

local function _buildCourseSelect(frame: Frame)
	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = C_BG
	bg.BorderSizePixel  = 0
	bg.Parent           = frame
	table.insert(_createdInstances, bg)

	_lbl(bg, "Select Course",
		Enum.Font.GothamBold, 32, C_WHITE,
		UDim2.new(0.5, 0, 0.10, 0), UDim2.new(0, 420, 0, 52))

	-- Builds one course card.
	-- Gold rule: the PLAYABLE badge on Course 1 is the ONE gold element here.
	local function _card(
		yFrac:     number,
		name:      string,
		detail:    string,
		sublabel:  string,
		locked:    boolean,
		lockMsg:   string?
	)
		local card = Instance.new("Frame")
		card.Size             = UDim2.new(0, 540, 0, 104)
		card.Position         = UDim2.new(0.5, 0, yFrac, 0)
		card.AnchorPoint      = Vector2.new(0.5, 0.5)
		card.BackgroundColor3 = C_PANEL
		card.BorderSizePixel  = 0
		card.Parent           = bg
		_corner(card, 12)
		_stroke(card, if locked then C_DIVIDE else C_CTA, if locked then 1 else 2)

		local nameColor = if locked then C_MUTED else C_WHITE
		_lbl(card, (if locked then "🔒  " else "") .. name,
			Enum.Font.GothamBold, 18, nameColor,
			UDim2.new(0.06, 0, 0.28, 0), UDim2.new(0.68, 0, 0, 24),
			Vector2.new(0, 0.5))

		_lbl(card, detail,
			Enum.Font.Gotham, 13, C_MUTED,
			UDim2.new(0.06, 0, 0.62, 0), UDim2.new(0.7, 0, 0, 20),
			Vector2.new(0, 0.5))

		if locked then
			_lbl(card, lockMsg or "",
				Enum.Font.Gotham, 12, C_DIVIDE,
				UDim2.new(0.06, 0, 0.86, 0), UDim2.new(0.8, 0, 0, 16),
				Vector2.new(0, 0.5))
		else
			-- Gold "PLAYABLE" badge (the ONE gold element on Course Select screen)
			local badge = Instance.new("Frame")
			badge.Size             = UDim2.new(0, 108, 0, 34)
			badge.Position         = UDim2.new(1, -120, 0.5, 0)
			badge.AnchorPoint      = Vector2.new(0, 0.5)
			badge.BackgroundColor3 = C_PANEL
			badge.BorderSizePixel  = 0
			badge.Parent           = card
			_corner(badge, 17)
			_stroke(badge, C_GOLD, 1)
			_lbl(badge, "PLAYABLE",
				Enum.Font.GothamBold, 13, C_GOLD,
				UDim2.new(0.5, 0, 0.5, 0), UDim2.new(1, -8, 1, 0))

			-- Sublabel (e.g. build complexity) beneath detail
			_lbl(card, sublabel,
				Enum.Font.Gotham, 12, C_MUTED,
				UDim2.new(0.06, 0, 0.86, 0), UDim2.new(0.7, 0, 0, 16),
				Vector2.new(0, 0.5))
		end
	end

	_card(0.30,
		"Sunnybrook Meadows",
		"9 Holes  ·  Par 36  ·  Aim Assist enabled",
		"Complexity ★★✦✦✦  ·  Wind: off (Course 1 only)",
		false, nil)

	_card(0.52,
		"Coral Cove",
		"9 Holes  ·  Par 36  ·  Wind mechanic (15%)",
		"",
		true, "Complete Sunnybrook Meadows to unlock")

	_card(0.74,
		"Sakura Highlands",
		"9 Holes  ·  Par 35  ·  Precision bank shots",
		"",
		true, "Complete Coral Cove to unlock")

	-- Back button
	local backBtn = _btn(bg, "← Back",
		Enum.Font.Gotham, 16, C_MUTED, C_BG,
		UDim2.new(0.5, 0, 0.92, 0), UDim2.new(0, 200, 0, 44), nil, 6)
	backBtn.BackgroundTransparency = 1
	backBtn.Activated:Connect(function()
		if not _initialized then return end
		MenuControllerModule:OpenMenu("MainMenu")
	end)
end

local function _buildStubPanel(frame: Frame, title: string)
	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = C_BG
	bg.BorderSizePixel  = 0
	bg.Parent           = frame
	table.insert(_createdInstances, bg)
	_lbl(bg, title .. "\n(Coming in a future update)",
		Enum.Font.Gotham, 20, C_MUTED,
		UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0, 440, 0, 80))
end

local function _setupUI(lobbyGui: ScreenGui)
	local function child(name: string): Frame?
		return lobbyGui:FindFirstChild(name) :: Frame?
	end

	local mm = child("MainMenu")
	if mm then _buildMainMenu(mm) end

	local cs = child("CourseSelectScreen")
	if cs then _buildCourseSelect(cs) end

	-- Stub panels (deferred to future sprints)
	local ac = child("AvatarCustomiser")
	if ac then _buildStubPanel(ac, "Avatar Customiser") end     -- TODO: cosmetics sprint

	local fp = child("FriendsPanel")
	if fp then _buildStubPanel(fp, "Friends") end               -- TODO: Phase 3 multiplayer

	local mm2 = child("MatchmakingModal")
	if mm2 then _buildStubPanel(mm2, "Matchmaking") end         -- TODO: Phase 3 multiplayer
end

-- ── Private state helpers ─────────────────────────────────────────────────────

local function _showPanel(panelFrameName: string)
	local gui = _lobbyGui
	if not gui then return end
	for _, frameName in pairs(PANEL_MAP) do
		local f = gui:FindFirstChild(frameName) :: Frame?
		if f then
			f.Visible = frameName == panelFrameName
		end
	end
end

local function _updateMenuUI()
	if _lobbyGui then
		_lobbyGui.Enabled = _visible
	end
	if _visible and _activeMenu ~= "" then
		local frameName = PANEL_MAP[_activeMenu]
		if frameName then
			_showPanel(frameName)
		end
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function MenuControllerModule:OpenMenu(menuName: string)
	_activeMenu = menuName
	_visible    = true
	print(("[MenuController] open → %q"):format(menuName))
	_updateMenuUI()
end

function MenuControllerModule:CloseMenu()
	_activeMenu = ""
	_visible    = false
	print("[MenuController] closed")
	_updateMenuUI()
end

function MenuControllerModule:GetActiveMenu(): string
	return _activeMenu
end

function MenuControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function MenuControllerModule:Init()
	if _initialized then
		warn("[MenuController] Init called twice — skipping")
		return
	end
	_initialized = true

	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg then
			warn("[MenuController] PlayerGui not available within 15 s")
			return
		end
		local lobby = (pg :: Instance):WaitForChild("Lobby", 15)
		if not lobby then
			warn("[MenuController] Lobby ScreenGui not available within 15 s")
			return
		end
		_lobbyGui = lobby :: ScreenGui
		_setupUI(lobby :: ScreenGui)
		_updateMenuUI()
		print("[MenuController] UI ready")
	end)

	print(("[MenuController] ready (player: %s)"):format(LocalPlayer.Name))
end

function MenuControllerModule:Update(_dt: number) end

function MenuControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	-- Destroy all programmatically created UI roots (children cleaned up automatically).
	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(_createdInstances)

	_lobbyGui    = nil
	_lblCoins    = nil
	_activeMenu  = ""
	_visible     = false
	_initialized = false
end

return MenuControllerModule
