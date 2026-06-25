--!strict
-- BallPool — Server-only ModuleScript
-- Pre-allocates BALL_POOL_SIZE ball Model instances at server start.
-- Lease/Release pattern: no Model creation or destruction during gameplay.
-- PhysicsService is the sole caller; holds at most one leased ball per active shot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local BPC       = require(ReplicatedStorage.Shared.Modules.BallPhysicsConstants)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

-- ── Types ──────────────────────────────────────────────────────────────────

type BallEntry = {
	model:    Model,
	isLeased: boolean,
}

-- ── Constants ──────────────────────────────────────────────────────────────

local BALL_DIAMETER = BPC.BALL_RADIUS * 2

-- Off-map storage position: below playable terrain, outside any camera frustum.
local PARK_CFrame = CFrame.new(0, -500, 0)

-- ── Module state ───────────────────────────────────────────────────────────

local _pool:   { BallEntry } = {}
local _folder: Folder?       = nil

-- ── Module ─────────────────────────────────────────────────────────────────

local BallPool = {}
BallPool.__index = BallPool

-- ── Private ────────────────────────────────────────────────────────────────

-- Creates one BallModel with PrimaryPart, StateValue, and OwnerValue per TDD §6.1.
-- parent must be non-nil (caller passes the ActiveBalls folder after creation).
function BallPool:_createBallModel(index: number, parent: Instance): Model
	local model  = Instance.new("Model")
	model.Name   = "PoolBall_" .. tostring(index)

	local part            = Instance.new("Part")
	part.Name             = "BallPart"
	part.Shape            = Enum.PartType.Ball
	part.Size             = Vector3.new(BALL_DIAMETER, BALL_DIAMETER, BALL_DIAMETER)
	part.Anchored         = true    -- PhysicsService sets CFrame directly; no Roblox solver
	part.CanCollide       = false   -- collision handled via PhysicsService raycasts
	part.CastShadow       = false
	part.Transparency     = 1       -- invisible while idle in the pool
	part.CFrame           = PARK_CFrame
	part.Material         = Enum.Material.SmoothPlastic
	part.Color            = Color3.fromRGB(255, 255, 255)
	part.Parent           = model

	-- StateValue: tracks ball state machine state; readable by PhysicsService and clients.
	local stateValue       = Instance.new("StringValue")
	stateValue.Name        = "StateValue"
	stateValue.Value       = "IDLE"
	stateValue.Parent      = model

	-- OwnerValue: ObjectValue pointing to the leasing Player; nil when idle.
	local ownerValue       = Instance.new("ObjectValue")
	ownerValue.Name        = "OwnerValue"
	ownerValue.Value       = nil
	ownerValue.Parent      = model

	model.PrimaryPart = part
	model.Parent      = parent

	return model
end

-- ── TDD §3.1 Interface ─────────────────────────────────────────────────────

function BallPool:Init(_dependencies: { [string]: any })
	-- Guard: prevent duplicate folders if Init is called more than once.
	if _folder then
		warn("[BallPool] Init called while already initialised — skipping")
		return
	end

	-- TDD §2.1: pooled ball instances live under Workspace/ActiveBalls.
	local folder  = Instance.new("Folder")
	folder.Name   = "ActiveBalls"
	folder.Parent = Workspace
	_folder       = folder

	for i = 1, Constants.BALL_POOL_SIZE do
		local entry: BallEntry = {
			model    = self:_createBallModel(i, folder),
			isLeased = false,
		}
		table.insert(_pool, entry)
	end
end

function BallPool:Update(_dt: number) end

function BallPool:Destroy()
	-- Destroying the folder cascades to all child Models (and their children).
	if _folder then
		_folder:Destroy()
		_folder = nil
	end
	table.clear(_pool)
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Returns the first idle ball and marks it leased.
-- Raises an error (not a warning) if all BALL_POOL_SIZE balls are in use;
-- the caller (PhysicsService) must Release before leasing again.
function BallPool:Lease(): Model
	for _, entry in ipairs(_pool) do
		if not entry.isLeased then
			entry.isLeased = true

			local part = entry.model.PrimaryPart
			if part then
				part.Transparency = 0
			end

			local sv = entry.model:FindFirstChild("StateValue") :: StringValue?
			if sv then
				sv.Value = "LEASED"
			end

			return entry.model
		end
	end
	error(string.format(
		"[BallPool] Pool exhausted — all %d balls are leased",
		Constants.BALL_POOL_SIZE
	))
end

-- Returns a ball to the pool: parks it off-map and hides it.
-- Warns if the model is not recognized (defensive; should never happen in normal flow).
function BallPool:Release(ball: Model)
	for _, entry in ipairs(_pool) do
		if entry.model == ball then
			entry.isLeased = false

			local part = entry.model.PrimaryPart
			if part then
				part.Transparency = 1
				part.CFrame       = PARK_CFrame
			end

			local sv = entry.model:FindFirstChild("StateValue") :: StringValue?
			if sv then
				sv.Value = "IDLE"
			end

			local ov = entry.model:FindFirstChild("OwnerValue") :: ObjectValue?
			if ov then
				ov.Value = nil
			end

			return
		end
	end
	warn("[BallPool] Release called with unrecognized model: ", ball)
end

return BallPool
