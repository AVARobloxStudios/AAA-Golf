--!strict
-- AddressBallModule — Client, Milestone 1
-- Shows "[ E ]  Address Ball" when the local player is within ADDRESS_RADIUS studs
-- of a stopped ball, and fires onAddress() when E is pressed while in range.
-- Call Enable(ball, onAddress) each time a ball stops; Disable() to tear down.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ADDRESS_RADIUS = 8   -- studs

local LocalPlayer = Players.LocalPlayer

-- ── Module ────────────────────────────────────────────────────────────────────

local AddressBallModule = {}

-- ── Private state ─────────────────────────────────────────────────────────────

local _active:    boolean               = false
local _ball:      Part?                 = nil
local _onAddress: (() -> ())?           = nil
local _pollConn:  RBXScriptConnection?  = nil
local _inputConn: RBXScriptConnection?  = nil
local _promptGui: ScreenGui?            = nil
local _inRange:   boolean               = false

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _destroyPrompt()
	if _promptGui and _promptGui.Parent then
		_promptGui:Destroy()
	end
	_promptGui = nil
	_inRange   = false
end

local function _buildPrompt()
	_destroyPrompt()

	local gui = Instance.new("ScreenGui")
	gui.Name           = "AddressBallPrompt"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 200
	gui.Enabled        = false   -- hidden until player enters range

	local bg = Instance.new("Frame")
	bg.BackgroundColor3       = Color3.fromRGB(12, 12, 12)
	bg.BackgroundTransparency = 0.25
	bg.Size                   = UDim2.new(0, 260, 0, 38)
	bg.Position               = UDim2.new(0.5, -130, 0.62, 0)
	bg.BorderSizePixel        = 0
	bg.Parent                 = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = bg

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size                   = UDim2.new(1, 0, 1, 0)
	lbl.Font                   = Enum.Font.GothamBold
	lbl.TextSize               = 16
	lbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	lbl.TextXAlignment         = Enum.TextXAlignment.Center
	lbl.Text                   = "[ E ]  Address Ball"
	lbl.Parent                 = bg

	gui.Parent = LocalPlayer.PlayerGui
	_promptGui = gui
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Starts proximity polling for ball. Fires onAddress() when E is pressed in range.
function AddressBallModule:Enable(ball: Part, onAddress: () -> ())
	AddressBallModule:Disable()

	_ball      = ball
	_onAddress = onAddress
	_active    = true
	_buildPrompt()

	_pollConn = RunService.RenderStepped:Connect(function()
		if not _active then return end
		local b = _ball
		if not b or not b.Parent then
			if _promptGui then _promptGui.Enabled = false end
			return
		end
		local char = LocalPlayer.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		local nowInRange = hrp ~= nil
			and ((hrp :: BasePart).Position - b.Position).Magnitude <= ADDRESS_RADIUS
		if nowInRange ~= _inRange then
			_inRange = nowInRange
			if _promptGui then _promptGui.Enabled = nowInRange end
		end
	end)

	_inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp or not _active or not _inRange then return end
		if input.KeyCode ~= Enum.KeyCode.E then return end
		local cb = _onAddress
		AddressBallModule:Disable()
		if cb then cb() end
	end)
end

-- Tears down polling, prompt, and input listener.
function AddressBallModule:Disable()
	_active    = false
	_ball      = nil
	_onAddress = nil
	_inRange   = false
	if _pollConn  then _pollConn:Disconnect();  _pollConn  = nil end
	if _inputConn then _inputConn:Disconnect(); _inputConn = nil end
	_destroyPrompt()
end

function AddressBallModule:Destroy()
	AddressBallModule:Disable()
end

return AddressBallModule
