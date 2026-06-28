--!strict
-- SwingEngineControllerModule — Client singleton (Sprint 34.5)
-- Central swing orchestrator. Owns all four swing sub-modules and exposes
-- a callback-based API so any hole/range/tutorial controller can consume
-- SwingResult without knowing how input is captured or analyzed.
--
-- Consumers (PlayableHoleControllerModule, future DrivingRangeController, etc.)
-- must call:
--   1. Init()
--   2. SetAimDirectionProvider(fn)
--   3. SetSwingResultCallback(fn)
--   4. Start()   — when the player should be able to swing
--   5. Stop()    — when swinging should be suspended
--   6. Destroy() — on cleanup
--
-- Isolation guarantee: this module does NOT require DeveloperAction, GameBus,
-- PlayableHoleService, or any server transport. Transport changes never require
-- touching swing logic.

local UserInputService = game:GetService("UserInputService")

local SwingInputControllerModule  = require(script.Parent.SwingInputControllerModule)
local SwingAnalyzerModule         = require(script.Parent.SwingAnalyzerModule)
local FaceControlControllerModule = require(script.Parent.FaceControlControllerModule)
local SwingFeedbackHUDModule      = require(script.Parent.SwingFeedbackHUDModule)

-- ── Types ─────────────────────────────────────────────────────────────────────

export type EngineState = {
	enabled:     boolean,
	swingPhase:  string,
	lastContact: string,
	lastShape:   string,
}

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:         boolean                 = false
local _enabled:             boolean                 = false
local _connections:         { RBXScriptConnection } = {}
local _aimDirProvider:      (() -> Vector3)?        = nil
local _swingResultCallback: ((any) -> ())?          = nil

-- ── Module ───────────────────────────────────────────────────────────────────

local SwingEngineControllerModule = {}
SwingEngineControllerModule.__index = SwingEngineControllerModule

-- ── Private ───────────────────────────────────────────────────────────────────

local function _processSwing()
	local rawData = SwingInputControllerModule:GetRawSwingData()
	if not rawData then return end

	if rawData.cancelled then
		SwingFeedbackHUDModule:UpdatePhase("Idle")
		return
	end

	local aimDir: Vector3 = if _aimDirProvider
		then _aimDirProvider()
		else Vector3.new(0, 0, -1)

	local faceData    = FaceControlControllerModule:GetFaceInputData()
	local swingResult = SwingAnalyzerModule:Analyze(rawData, faceData, aimDir)

	if not swingResult.valid then
		SwingFeedbackHUDModule:UpdatePhase("Idle")
		return
	end

	SwingFeedbackHUDModule:ShowResult(swingResult)

	if _swingResultCallback then
		_swingResultCallback(swingResult)
	end

	FaceControlControllerModule:Reset()
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Sets the function that returns the current aim direction (e.g. camera LookVector).
function SwingEngineControllerModule:SetAimDirectionProvider(fn: () -> Vector3)
	_aimDirProvider = fn
end

-- Sets the function called with a SwingResult after each valid swing.
-- The callback is responsible for any server transport — this module never
-- fires RemoteEvents.
function SwingEngineControllerModule:SetSwingResultCallback(fn: (any) -> ())
	_swingResultCallback = fn
end

function SwingEngineControllerModule:SetEnabled(enabled: boolean)
	if not _initialized then return end
	_enabled = enabled
	SwingInputControllerModule:SetEnabled(enabled)
	if not enabled then
		SwingInputControllerModule:CancelInput()
		FaceControlControllerModule:Reset()
	end
end

-- Begins accepting swing input. Call when the hole/range enters a shootable state.
function SwingEngineControllerModule:Start()
	if not _initialized then return end
	_enabled = true
	SwingInputControllerModule:SetEnabled(true)
	SwingFeedbackHUDModule:ResetDisplay()
end

-- Suspends swing input without destroying sub-module state.
function SwingEngineControllerModule:Stop()
	if not _initialized then return end
	_enabled = false
	SwingInputControllerModule:SetEnabled(false)
	SwingInputControllerModule:CancelInput()
	FaceControlControllerModule:Reset()
	SwingFeedbackHUDModule:UpdatePhase("Idle")
end

-- Clears any in-progress swing state without changing enabled status.
function SwingEngineControllerModule:Reset()
	if not _initialized then return end
	SwingInputControllerModule:CancelInput()
	FaceControlControllerModule:Reset()
	SwingAnalyzerModule:Reset()
	SwingFeedbackHUDModule:ResetDisplay()
end

-- Runs the full analysis pipeline using the last completed RawSwingData.
-- Exposed as a public method for testing and programmatic triggering.
function SwingEngineControllerModule:ProcessSwing()
	_processSwing()
end

function SwingEngineControllerModule:GetState(): EngineState
	local swState    = SwingInputControllerModule:GetSwingState()
	local lastResult = SwingAnalyzerModule:GetLastResult()
	return {
		enabled     = _enabled,
		swingPhase  = swState.phase,
		lastContact = if lastResult then lastResult.contactQuality else "--",
		lastShape   = if lastResult then lastResult.shotShape else "--",
	}
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function SwingEngineControllerModule:Init()
	if _initialized then
		warn("[SwingEngineControllerModule] Init called twice — skipping")
		return
	end
	_initialized = true
	_enabled     = false

	SwingInputControllerModule:Init()
	FaceControlControllerModule:Init()
	SwingAnalyzerModule:Init()
	SwingFeedbackHUDModule:Init()

	-- InputBegan: drag start + Spacebar face timing
	table.insert(_connections, UserInputService.InputBegan:Connect(
		function(input: InputObject, gameProcessed: boolean)
			if not _enabled then return end
			if gameProcessed then return end

			if input.KeyCode == Enum.KeyCode.Space then
				FaceControlControllerModule:RegisterFaceInput()

			elseif input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local pos = Vector2.new(input.Position.X, input.Position.Y)
				SwingInputControllerModule:BeginInput(pos)
				SwingFeedbackHUDModule:UpdatePhase("InputStarted")
			end
		end
	))

	-- InputChanged: movement — update phases and open face window when downswing starts
	table.insert(_connections, UserInputService.InputChanged:Connect(
		function(input: InputObject, gameProcessed: boolean)
			if not _enabled then return end
			if gameProcessed then return end
			local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
			local isTouch = input.UserInputType == Enum.UserInputType.Touch
			if not (isMouse or isTouch) then return end

			local pos       = Vector2.new(input.Position.X, input.Position.Y)
			local prevState = SwingInputControllerModule:GetSwingState()
			SwingInputControllerModule:UpdateInput(pos)
			local newState  = SwingInputControllerModule:GetSwingState()

			if prevState.phase ~= "Downswing" and newState.phase == "Downswing" then
				FaceControlControllerModule:StartFaceWindow()
			end
			if newState.phase ~= prevState.phase then
				SwingFeedbackHUDModule:UpdatePhase(newState.phase)
			end
		end
	))

	-- InputEnded: release → finalize input → analyze
	table.insert(_connections, UserInputService.InputEnded:Connect(
		function(input: InputObject, gameProcessed: boolean)
			if not _enabled then return end
			if gameProcessed then return end
			local isMouse1 = input.UserInputType == Enum.UserInputType.MouseButton1
			local isTouch  = input.UserInputType == Enum.UserInputType.Touch
			if not (isMouse1 or isTouch) then return end

			local pos = Vector2.new(input.Position.X, input.Position.Y)
			SwingInputControllerModule:EndInput(pos)
			FaceControlControllerModule:EndFaceWindow()
			_processSwing()
		end
	))
end

function SwingEngineControllerModule:Update(_dt: number) end

function SwingEngineControllerModule:Destroy()
	for _, conn in ipairs(_connections) do conn:Disconnect() end
	table.clear(_connections)

	SwingInputControllerModule:Destroy()
	FaceControlControllerModule:Destroy()
	SwingAnalyzerModule:Destroy()
	SwingFeedbackHUDModule:Destroy()

	_enabled            = false
	_aimDirProvider     = nil
	_swingResultCallback = nil
	_initialized        = false
end

return SwingEngineControllerModule
