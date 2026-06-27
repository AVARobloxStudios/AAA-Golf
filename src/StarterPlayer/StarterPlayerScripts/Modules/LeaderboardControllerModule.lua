--!strict
-- LeaderboardControllerModule — Client singleton (Sprint 12)
-- Tracks leaderboard entries locally, sorts them, and renders a compact
-- player-ranking overlay inside the pre-declared
-- PlayerGui.Scoreboard.LeaderboardOverlay frame.
--
-- Sort order: scoreToPar ascending (most under-par first), tie-broken by
-- totalStrokes ascending.
--
-- Visible state:  ROUND_COMPLETE.
-- Hidden states:  all others.
--
-- Public API
--   SetEntries(entries)    — store, sort, and render
--   GetEntries()           → { LeaderboardEntry }  (sorted copy)
--   ClearEntries()         — empty list, refresh UI
--   IsVisible()            → boolean
--
-- GameBus events handled:
--   StateChanged — controls visibility; filtered by LocalPlayer.UserId
--
-- LeaderboardController.client.lua is the thin runner.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

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

local C_RANK2 = Color3.fromRGB(180, 190, 200)  -- silver
local C_RANK3 = Color3.fromRGB(200, 140, 80)   -- bronze

-- ── Type ─────────────────────────────────────────────────────────────────────

export type LeaderboardEntry = {
	displayName:  string,
	userId:       number,
	scoreToPar:   number,
	totalStrokes: number,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                   = false
local _entries:          { LeaderboardEntry }      = {}
local _visible:          boolean                   = false
local _gameState:        string                    = "LOBBY"
local _connections:      { RBXScriptConnection }   = {}
local _createdInstances: { Instance }              = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _lbCard:   Frame? = nil   -- root container inside LeaderboardOverlay
local _lbList:   Frame? = nil   -- inner frame where entry rows live

-- ── Module ───────────────────────────────────────────────────────────────────

local LeaderboardControllerModule = {}
LeaderboardControllerModule.__index = LeaderboardControllerModule

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

local function _stpText(stp: number): string
	if stp > 0 then return "+" .. tostring(stp) end
	if stp < 0 then return tostring(stp)          end
	return "E"
end

local function _rankColor(rank: number): Color3
	if rank == 1 then return C_GOLD  end
	if rank == 2 then return C_RANK2 end
	if rank == 3 then return C_RANK3 end
	return C_WHITE
end

local function _sortEntries()
	table.sort(_entries, function(a: LeaderboardEntry, b: LeaderboardEntry): boolean
		if a.scoreToPar ~= b.scoreToPar then
			return a.scoreToPar < b.scoreToPar
		end
		return a.totalStrokes < b.totalStrokes
	end)
end

local function _rebuildRows()
	if not _lbList then return end
	for _, child in ipairs(_lbList:GetChildren()) do
		child:Destroy()
	end

	for rank, entry in ipairs(_entries) do
		local rc = _rankColor(rank)

		local row = Instance.new("Frame")
		row.Size             = UDim2.new(1, 0, 0, 36)
		row.Position         = UDim2.new(0, 0, 0, (rank - 1) * 38)
		row.BackgroundTransparency = 1
		row.BorderSizePixel  = 0
		row.Parent           = _lbList

		-- Rank badge
		local rankLbl = Instance.new("TextLabel")
		rankLbl.Text                   = "#" .. tostring(rank)
		rankLbl.Font                   = Enum.Font.GothamBold
		rankLbl.TextSize               = 14
		rankLbl.TextColor3             = rc
		rankLbl.BackgroundTransparency = 1
		rankLbl.Size                   = UDim2.new(0, 36, 1, 0)
		rankLbl.TextXAlignment         = Enum.TextXAlignment.Left
		rankLbl.Parent                 = row

		-- Display name
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Text                   = entry.displayName
		nameLbl.Font                   = Enum.Font.Gotham
		nameLbl.TextSize               = 13
		nameLbl.TextColor3             = rc
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size                   = UDim2.new(0, 110, 1, 0)
		nameLbl.Position               = UDim2.new(0, 38, 0, 0)
		nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
		nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
		nameLbl.Parent                 = row

		-- Score to par
		local stpLbl = Instance.new("TextLabel")
		stpLbl.Text                   = _stpText(entry.scoreToPar)
		stpLbl.Font                   = Enum.Font.GothamBold
		stpLbl.TextSize               = 14
		stpLbl.TextColor3             = rc
		stpLbl.BackgroundTransparency = 1
		stpLbl.Size                   = UDim2.new(0, 44, 1, 0)
		stpLbl.Position               = UDim2.new(0, 150, 0, 0)
		stpLbl.TextXAlignment         = Enum.TextXAlignment.Right
		stpLbl.Parent                 = row

		-- Total strokes (muted secondary)
		local strokesLbl = Instance.new("TextLabel")
		strokesLbl.Text                   = tostring(entry.totalStrokes)
		strokesLbl.Font                   = Enum.Font.Gotham
		strokesLbl.TextSize               = 11
		strokesLbl.TextColor3             = C_MUTED
		strokesLbl.BackgroundTransparency = 1
		strokesLbl.Size                   = UDim2.new(0, 44, 1, 0)
		strokesLbl.Position               = UDim2.new(0, 198, 0, 0)
		strokesLbl.TextXAlignment         = Enum.TextXAlignment.Right
		strokesLbl.Parent                 = row
	end
end

local function _updateLeaderboardUI()
	if _lbCard then
		_lbCard.Visible = _visible
	end
	_rebuildRows()
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(lbFrame: Frame)
	-- Card anchored to the right side, full-height friendly
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 260, 0, 400)
	card.Position         = UDim2.new(1, -276, 0, 80)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Visible          = false
	card.Parent           = lbFrame
	_corner(card, 12)
	_stroke(card, C_BG, 1)
	table.insert(_createdInstances, card)
	_lbCard = card

	-- "LEADERBOARD" — GOLD title (ONE gold element on this overlay)
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text                   = "LEADERBOARD"
	titleLbl.Font                   = Enum.Font.GothamBold
	titleLbl.TextSize               = 14
	titleLbl.TextColor3             = C_GOLD
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size                   = UDim2.new(1, -24, 0, 22)
	titleLbl.Position               = UDim2.new(0, 12, 0, 12)
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
	titleLbl.Parent                 = card

	-- CTA green divider
	local div = Instance.new("Frame")
	div.Size             = UDim2.new(1, -24, 0, 1)
	div.Position         = UDim2.new(0, 12, 0, 38)
	div.BackgroundColor3 = C_CTA
	div.BorderSizePixel  = 0
	div.Parent           = card

	-- Row list area
	local list = Instance.new("Frame")
	list.Size             = UDim2.new(1, -24, 1, -52)
	list.Position         = UDim2.new(0, 12, 0, 46)
	list.BackgroundTransparency = 1
	list.BorderSizePixel  = 0
	list.ClipsDescendants = true
	list.Parent           = card
	_lbList = list
end

-- ── Semi-public: exposed for Sprint12ClientTest ──────────────────────────────

function LeaderboardControllerModule:_onClientEvent(envelope: any)
	if type(envelope) ~= "table" then return end
	local eventType = envelope.eventType
	if type(eventType) ~= "string" then return end

	if eventType == "StateChanged" then
		local payload = envelope.payload
		if type(payload) ~= "table" then return end
		if payload.playerId ~= LocalPlayer.UserId then return end

		local newState = tostring(payload.state)
		_gameState = newState
		_visible   = newState == "ROUND_COMPLETE"

		Logger:Debug("LeaderboardController", ("state → %q | visible=%s"):format(
			newState, tostring(_visible)))
		_updateLeaderboardUI()
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function LeaderboardControllerModule:SetEntries(entries: { LeaderboardEntry })
	table.clear(_entries)
	for _, e in ipairs(entries) do
		table.insert(_entries, {
			displayName  = e.displayName,
			userId       = e.userId,
			scoreToPar   = e.scoreToPar,
			totalStrokes = e.totalStrokes,
		})
	end
	_sortEntries()
	_updateLeaderboardUI()
end

-- Returns a sorted shallow copy so callers cannot mutate internal state.
function LeaderboardControllerModule:GetEntries(): { LeaderboardEntry }
	local copy: { LeaderboardEntry } = {}
	for i, e in ipairs(_entries) do
		copy[i] = {
			displayName  = e.displayName,
			userId       = e.userId,
			scoreToPar   = e.scoreToPar,
			totalStrokes = e.totalStrokes,
		}
	end
	return copy
end

function LeaderboardControllerModule:ClearEntries()
	table.clear(_entries)
	_updateLeaderboardUI()
end

function LeaderboardControllerModule:IsVisible(): boolean
	return _visible
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function LeaderboardControllerModule:Init()
	if _initialized then
		warn("[LeaderboardController] Init called twice — skipping")
		return
	end
	_initialized = true

	table.insert(_connections,
		GameBus.OnClientEvent:Connect(function(envelope: any)
			LeaderboardControllerModule:_onClientEvent(envelope)
		end))

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end

		local sbGui = (pg :: Instance):WaitForChild("Scoreboard", 15)
		if not sbGui or not _initialized then return end

		local lbFrame =
			(sbGui :: Instance):WaitForChild("LeaderboardOverlay", 15) :: Frame?
		if not lbFrame or not _initialized then return end

		_buildUI(lbFrame :: Frame)
		_updateLeaderboardUI()
		Logger:Info("LeaderboardController", "UI ready")
	end)

	Logger:Info("LeaderboardController", ("ready (player: %s)"):format(LocalPlayer.Name))
end

function LeaderboardControllerModule:Update(_dt: number) end

function LeaderboardControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_lbCard = nil
	_lbList = nil

	table.clear(_entries)
	_visible     = false
	_gameState   = "LOBBY"
	_initialized = false
end

return LeaderboardControllerModule
