--!strict
-- MatchmakingControllerModule — Client singleton (Sprint 15)
-- Tracks local matchmaking queue state.  No real server matchmaking,
-- no TeleportService, no DataStores.
--
-- A code-created ScreenGui (MatchmakingGui) shows queue status when the
-- player is in the queue.  It hides when CancelQueue() is called.
--
-- Valid modes:  Solo | Duo | Squad | Private
--
-- Public API
--   StartQueue(modeName)           — enter queue; warns on invalid mode
--   CancelQueue()                  — leave queue, reset all state
--   IsQueued()                     → boolean
--   GetMode()                      → string  ("" when not queued)
--   SetEstimatedWait(seconds)      — update displayed wait estimate
--   GetEstimatedWait()             → number  (seconds, 0 when not queued)
--   SetMatchFound(matchData)       — store match result (shallow copy)
--   GetMatchFound()                → { [string]: any }?  (shallow copy)
--
-- MatchmakingController.client.lua is the thin runner.

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer

-- ── Fairway Pro design tokens (VS §05) ───────────────────────────────────────

local C_BG    = Color3.fromRGB(13,  43,  26)
local C_CTA   = Color3.fromRGB(76,  175, 125)
local C_GOLD  = Color3.fromRGB(200, 152, 10)
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_MUTED = Color3.fromRGB(140, 180, 155)
local C_PANEL = Color3.fromRGB(7,   28,  16)

-- ── Mode catalogue ────────────────────────────────────────────────────────────

local VALID_MODES: { [string]: boolean } = {
	Solo    = true,
	Duo     = true,
	Squad   = true,
	Private = true,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                 = false
local _isQueued:         boolean                 = false
local _mode:             string                  = ""
local _estimatedWait:    number                  = 0
local _matchFound:       { [string]: any }?      = nil
local _connections:      { RBXScriptConnection } = {}
local _createdInstances: { Instance }            = {}

-- ── UI references (populated async in Init) ───────────────────────────────────

local _queueGui:   ScreenGui? = nil
local _lblMode:    TextLabel? = nil
local _lblWait:    TextLabel? = nil
local _lblMatch:   TextLabel? = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local MatchmakingControllerModule = {}
MatchmakingControllerModule.__index = MatchmakingControllerModule

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
	if not _queueGui then return end
	_queueGui.Enabled = _isQueued

	if _lblMode then
		_lblMode.Text = "Mode: " .. (_mode ~= "" and _mode or "—")
	end
	if _lblWait then
		_lblWait.Text = _estimatedWait > 0
			and ("Est. wait: %ds"):format(_estimatedWait)
			or "Searching…"
	end
	if _lblMatch then
		_lblMatch.Visible = _matchFound ~= nil
		if _matchFound then
			local id = tostring(_matchFound["matchId"] or "")
			_lblMatch.Text = "Match found!  " .. id
		end
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function _buildUI(pg: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name           = "MatchmakingGui"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled        = false
	gui.Parent         = pg
	table.insert(_createdInstances, gui)
	_queueGui = gui

	-- Centred queue card
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 320, 0, 190)
	card.Position         = UDim2.new(0.5, 0, 0.5, 0)
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = C_PANEL
	card.BorderSizePixel  = 0
	card.Parent           = gui
	_corner(card, 14)
	_stroke(card, C_BG, 1)

	-- "MATCHMAKING" header — GOLD (ONE gold element on this card)
	local headerLbl = Instance.new("TextLabel")
	headerLbl.Text                   = "MATCHMAKING"
	headerLbl.Font                   = Enum.Font.GothamBold
	headerLbl.TextSize               = 15
	headerLbl.TextColor3             = C_GOLD
	headerLbl.BackgroundTransparency = 1
	headerLbl.Size                   = UDim2.new(1, -24, 0, 26)
	headerLbl.Position               = UDim2.new(0, 16, 0, 12)
	headerLbl.TextXAlignment         = Enum.TextXAlignment.Left
	headerLbl.Parent                 = card

	-- Separator under header
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, -32, 0, 1)
	sep.Position         = UDim2.new(0, 16, 0, 42)
	sep.BackgroundColor3 = C_CTA
	sep.BorderSizePixel  = 0
	sep.Parent           = card

	-- Mode label
	local modeLbl = Instance.new("TextLabel")
	modeLbl.Text                   = "Mode: —"
	modeLbl.Font                   = Enum.Font.Gotham
	modeLbl.TextSize               = 13
	modeLbl.TextColor3             = C_WHITE
	modeLbl.BackgroundTransparency = 1
	modeLbl.Size                   = UDim2.new(1, -24, 0, 22)
	modeLbl.Position               = UDim2.new(0, 16, 0, 50)
	modeLbl.TextXAlignment         = Enum.TextXAlignment.Left
	modeLbl.Parent                 = card
	_lblMode = modeLbl

	-- Wait / status label
	local waitLbl = Instance.new("TextLabel")
	waitLbl.Text                   = "Searching…"
	waitLbl.Font                   = Enum.Font.Gotham
	waitLbl.TextSize               = 13
	waitLbl.TextColor3             = C_MUTED
	waitLbl.BackgroundTransparency = 1
	waitLbl.Size                   = UDim2.new(1, -24, 0, 22)
	waitLbl.Position               = UDim2.new(0, 16, 0, 72)
	waitLbl.TextXAlignment         = Enum.TextXAlignment.Left
	waitLbl.Parent                 = card
	_lblWait = waitLbl

	-- Match-found label (hidden until SetMatchFound is called)
	local matchLbl = Instance.new("TextLabel")
	matchLbl.Text                   = ""
	matchLbl.Font                   = Enum.Font.GothamBold
	matchLbl.TextSize               = 13
	matchLbl.TextColor3             = C_CTA
	matchLbl.BackgroundTransparency = 1
	matchLbl.Size                   = UDim2.new(1, -24, 0, 22)
	matchLbl.Position               = UDim2.new(0, 16, 0, 96)
	matchLbl.TextXAlignment         = Enum.TextXAlignment.Left
	matchLbl.Visible                = false
	matchLbl.Parent                 = card
	_lblMatch = matchLbl

	-- "Cancel" button
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Text             = "Cancel"
	cancelBtn.Font             = Enum.Font.GothamBold
	cancelBtn.TextSize         = 14
	cancelBtn.TextColor3       = Color3.fromRGB(7, 28, 16)
	cancelBtn.BackgroundColor3 = C_CTA
	cancelBtn.BorderSizePixel  = 0
	cancelBtn.Size             = UDim2.new(1, -32, 0, 40)
	cancelBtn.Position         = UDim2.new(0, 16, 1, -52)
	cancelBtn.AutoButtonColor  = true
	cancelBtn.Parent           = card
	_corner(cancelBtn, 10)

	cancelBtn.Activated:Connect(function()
		if not _initialized then return end
		MatchmakingControllerModule:CancelQueue()
	end)

	_updateUI()
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Enters the matchmaking queue for the given mode.
-- Warns and no-ops for unknown mode names.
function MatchmakingControllerModule:StartQueue(modeName: string)
	if not VALID_MODES[modeName] then
		warn(("[MatchmakingController] StartQueue: unknown mode %q"):format(
			tostring(modeName)))
		return
	end
	_isQueued      = true
	_mode          = modeName
	_matchFound    = nil
	_estimatedWait = 0
	_updateUI()
end

-- Leaves the queue and resets all matchmaking state.
function MatchmakingControllerModule:CancelQueue()
	_isQueued      = false
	_mode          = ""
	_estimatedWait = 0
	_matchFound    = nil
	_updateUI()
end

function MatchmakingControllerModule:IsQueued(): boolean
	return _isQueued
end

function MatchmakingControllerModule:GetMode(): string
	return _mode
end

function MatchmakingControllerModule:SetEstimatedWait(seconds: number)
	_estimatedWait = seconds
	_updateUI()
end

function MatchmakingControllerModule:GetEstimatedWait(): number
	return _estimatedWait
end

-- Stores a shallow copy of the match result data.
-- Requires at least a string "matchId" field; warns and no-ops otherwise.
function MatchmakingControllerModule:SetMatchFound(matchData: { [string]: any })
	if type(matchData) ~= "table" or type(matchData["matchId"]) ~= "string" then
		warn("[MatchmakingController] SetMatchFound: data must be a table with string matchId")
		return
	end
	local copy: { [string]: any } = {}
	for k, v in pairs(matchData) do
		copy[k] = v
	end
	_matchFound = copy
	_updateUI()
end

-- Returns a shallow copy of the stored match data, or nil.
function MatchmakingControllerModule:GetMatchFound(): { [string]: any }?
	if not _matchFound then return nil end
	local copy: { [string]: any } = {}
	for k, v in pairs(_matchFound :: { [string]: any }) do
		copy[k] = v
	end
	return copy
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function MatchmakingControllerModule:Init()
	if _initialized then
		warn("[MatchmakingController] Init called twice — skipping")
		return
	end
	_initialized = true

	task.spawn(function()
		if not _initialized then return end
		local pg = LocalPlayer:WaitForChild("PlayerGui", 15)
		if not pg or not _initialized then return end
		_buildUI(pg :: Instance)
		print("[MatchmakingController] UI ready")
	end)

	print(("[MatchmakingController] ready (player: %s)"):format(LocalPlayer.Name))
end

function MatchmakingControllerModule:Update(_dt: number) end

function MatchmakingControllerModule:Destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)

	for _, inst in ipairs(_createdInstances) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(_createdInstances)

	_queueGui  = nil
	_lblMode   = nil
	_lblWait   = nil
	_lblMatch  = nil

	_isQueued      = false
	_mode          = ""
	_estimatedWait = 0
	_matchFound    = nil
	_initialized   = false
end

return MatchmakingControllerModule
