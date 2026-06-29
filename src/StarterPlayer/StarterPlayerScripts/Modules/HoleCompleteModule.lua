--!strict
-- HoleCompleteModule — Client, Milestone 1.9
-- Hole-complete result panel: score tier, strokes, differential, and buttons.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local ScoringRules      = require(ReplicatedStorage.Shared.Modules.ScoringRules)

local HoleCompleteModule = {}

local _gui: ScreenGui? = nil

local SCORE_LABELS: { [string]: string } = {
	CONDOR      = "Condor!",
	ALBATROSS   = "Albatross!",
	EAGLE       = "Eagle!",
	BIRDIE      = "Birdie",
	PAR         = "Par",
	BOGEY       = "Bogey",
	DOUBLE_BOGEY = "Double Bogey",
	WORSE       = "Over Par",
}

local SCORE_COLORS: { [string]: Color3 } = {
	CONDOR      = Color3.fromRGB(255, 215,   0),
	ALBATROSS   = Color3.fromRGB(255, 215,   0),
	EAGLE       = Color3.fromRGB(255, 200,   0),
	BIRDIE      = Color3.fromRGB(100, 220, 255),
	PAR         = Color3.fromRGB(200, 200, 200),
	BOGEY       = Color3.fromRGB(255, 160,  80),
	DOUBLE_BOGEY = Color3.fromRGB(255, 100,  60),
	WORSE       = Color3.fromRGB(255,  60,  60),
}

export type ShowOptions = {
	onContinue:  () -> (),
	onPlayAgain: () -> (),
}

function HoleCompleteModule:Show(holeNum: number, par: number, strokes: number, opts: ShowOptions)
	if _gui and _gui.Parent then _gui:Destroy() end

	local localPlayer = Players.LocalPlayer
	local gui         = Instance.new("ScreenGui")
	gui.Name           = "HoleCompleteScreen"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 150

	-- Dim overlay
	local overlay                    = Instance.new("Frame")
	overlay.BackgroundColor3         = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency   = 0.55
	overlay.Size                     = UDim2.new(1, 0, 1, 0)
	overlay.BorderSizePixel          = 0
	overlay.Parent                   = gui

	-- Main panel: starts below screen, springs up to center
	local panel                      = Instance.new("Frame")
	panel.BackgroundColor3           = Color3.fromRGB(12, 18, 28)
	panel.BackgroundTransparency     = 0.06
	panel.Size                       = UDim2.new(0, 340, 0, 340)
	panel.Position                   = UDim2.new(0.5, -170, 1.4, 0)   -- below viewport
	panel.BorderSizePixel            = 0
	panel.Parent                     = gui
	local corner                     = Instance.new("UICorner")
	corner.CornerRadius              = UDim.new(0, 14)
	corner.Parent                    = panel

	local function makeLbl(text: string, sizeY: number, posY: number,
		fontSize: number, bold: boolean, color: Color3): TextLabel
		local lbl                    = Instance.new("TextLabel")
		lbl.BackgroundTransparency   = 1
		lbl.Size                     = UDim2.new(1, -24, 0, sizeY)
		lbl.Position                 = UDim2.new(0, 12, 0, posY)
		lbl.Font                     = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		lbl.TextSize                 = fontSize
		lbl.TextColor3               = color
		lbl.TextXAlignment           = Enum.TextXAlignment.Center
		lbl.Text                     = text
		lbl.Parent                   = panel
		return lbl
	end

	-- Score calculation
	local tier: string
	if strokes == 1 then
		tier = "CONDOR"  -- show as Hole in One
	else
		tier = ScoringRules.ClassifyScore(strokes, par)
	end

	local diff = strokes - par

	local scoreLabel: string
	if strokes == 1 then
		scoreLabel = "Hole in One!"
	elseif diff == 3 then
		scoreLabel = "Triple Bogey"
	else
		scoreLabel = SCORE_LABELS[tier] or ("+" .. tostring(diff))
	end

	local colorKey = if diff == 3 then "WORSE" else tier
	local scoreColor = SCORE_COLORS[colorKey] or Color3.fromRGB(200, 200, 200)

	local diffStr: string
	if diff > 0 then
		diffStr = "+" .. tostring(diff)
	elseif diff == 0 then
		diffStr = "E"
	else
		diffStr = tostring(diff)
	end

	-- Content rows
	makeLbl("HOLE COMPLETE",                  24,  18, 12, false, Color3.fromRGB(130, 145, 165))
	makeLbl("HOLE " .. holeNum .. "  •  PAR " .. par, 28, 48, 17, false, Color3.fromRGB(190, 200, 215))
	makeLbl(tostring(strokes),                64,  84, 52, true,  Color3.fromRGB(255, 255, 255))
	makeLbl("STROKES",                        22, 152, 11, false, Color3.fromRGB(110, 125, 140))
	makeLbl(scoreLabel,                       36, 180, 22, true,  scoreColor)
	makeLbl(diffStr,                          24, 218, 14, false, Color3.fromRGB(150, 165, 185))

	-- Divider
	local div                    = Instance.new("Frame")
	div.BackgroundColor3         = Color3.fromRGB(40, 55, 75)
	div.BorderSizePixel          = 0
	div.Size                     = UDim2.new(1, -40, 0, 1)
	div.Position                 = UDim2.new(0, 20, 0, 252)
	div.Parent                   = panel

	-- Button helper
	local function makeBtn(text: string, posX: UDim2, color: Color3, callback: () -> ()): TextButton
		local btn                    = Instance.new("TextButton")
		btn.BackgroundColor3         = color
		btn.Size                     = UDim2.new(0, 130, 0, 42)
		btn.Position                 = posX
		btn.Font                     = Enum.Font.GothamBold
		btn.TextSize                 = 15
		btn.TextColor3               = Color3.fromRGB(255, 255, 255)
		btn.Text                     = text
		btn.BorderSizePixel          = 0
		btn.Parent                   = panel
		local bc                     = Instance.new("UICorner")
		bc.CornerRadius              = UDim.new(0, 8)
		bc.Parent                    = btn
		btn.MouseButton1Click:Connect(callback)
		return btn
	end

	makeBtn("Play Again", UDim2.new(0, 20,  0, 272), Color3.fromRGB( 50, 100, 160), function()
		HoleCompleteModule:Hide()
		task.spawn(opts.onPlayAgain)
	end)
	makeBtn("Continue",   UDim2.new(0, 190, 0, 272), Color3.fromRGB( 30, 145,  80), function()
		HoleCompleteModule:Hide()
		task.spawn(opts.onContinue)
	end)

	gui.Parent = localPlayer.PlayerGui
	_gui       = gui

	-- Spring-up entrance: panel slides from below the viewport to vertical center
	TweenService:Create(
		panel,
		TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -170, 0.5, -170) }
	):Play()
end

function HoleCompleteModule:Hide()
	if _gui and _gui.Parent then _gui:Destroy() end
	_gui = nil
end

function HoleCompleteModule:Destroy()
	HoleCompleteModule:Hide()
end

return HoleCompleteModule
