--!strict
-- NetworkControllerModule — Client singleton (Sprint 18)
-- Locates and caches all ReplicatedStorage.Network remotes at Init time.
-- Provides a safe, testable facade over FireServer / InvokeServer so callers
-- never hold direct remote references in module-level scope.
--
-- Discovery is synchronous: ReplicatedStorage contents exist before any
-- LocalScript runs in Play mode, so FindFirstChild succeeds immediately.
-- If the Network folder is absent (e.g. stripped build), IsReady() stays false
-- and Send/Invoke warn rather than error.
--
-- Public API
--   IsReady()                  → boolean
--   GetRemote(name)            → Instance?  (RemoteEvent or RemoteFunction)
--   Send(eventName, payload)   — FireServer on a RemoteEvent; warns if unknown
--   Invoke(functionName, payload) → any     — InvokeServer on a RemoteFunction
--
-- NetworkController.client.lua is the thin runner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Module state ─────────────────────────────────────────────────────────────

local _initialized:      boolean                = false
local _ready:            boolean                = false
local _remoteEvents:     { [string]: Instance } = {}
local _remoteFunctions:  { [string]: Instance } = {}

-- ── Module ───────────────────────────────────────────────────────────────────

local NetworkControllerModule = {}
NetworkControllerModule.__index = NetworkControllerModule

-- ── Public API ────────────────────────────────────────────────────────────────

function NetworkControllerModule:IsReady(): boolean
	return _ready
end

-- Returns the cached remote (RemoteEvent or RemoteFunction) or nil.
function NetworkControllerModule:GetRemote(name: string): Instance?
	local re = _remoteEvents[name]
	if re then return re end
	return _remoteFunctions[name] or nil
end

-- Fires a RemoteEvent to the server.  No-ops with a warning for unknown names.
-- Does not call FireServer if not ready or name is unknown — test-safe.
function NetworkControllerModule:Send(eventName: string, payload: any)
	if not _ready then
		warn("[NetworkController] Send: not ready — remotes not yet available")
		return
	end
	local remote = _remoteEvents[eventName]
	if not remote then
		warn(("[NetworkController] Send: unknown RemoteEvent %q"):format(
			tostring(eventName)))
		return
	end
	local re = remote :: RemoteEvent
	re:FireServer(payload)
end

-- Invokes a RemoteFunction and returns the server response.
-- Returns nil with a warning for unknown function names.
function NetworkControllerModule:Invoke(functionName: string, payload: any): any
	if not _ready then
		warn("[NetworkController] Invoke: not ready — remotes not yet available")
		return nil
	end
	local remote = _remoteFunctions[functionName]
	if not remote then
		warn(("[NetworkController] Invoke: unknown RemoteFunction %q"):format(
			tostring(functionName)))
		return nil
	end
	local rf = remote :: RemoteFunction
	return rf:InvokeServer(payload)
end

-- ── TDD §3.1 Interface ───────────────────────────────────────────────────────

function NetworkControllerModule:Init()
	if _initialized then
		warn("[NetworkController] Init called twice — skipping")
		return
	end
	_initialized = true

	-- Synchronous discovery: Network folder is present before LocalScripts run.
	local network = ReplicatedStorage:FindFirstChild("Network")
	if not network then
		warn("[NetworkController] ReplicatedStorage.Network not found — staying not-ready")
		return
	end

	local eventsFolder = (network :: Instance):FindFirstChild("RemoteEvents")
	if eventsFolder then
		for _, child in ipairs((eventsFolder :: Instance):GetChildren()) do
			if child:IsA("RemoteEvent") or child:IsA("UnreliableRemoteEvent") then
				_remoteEvents[child.Name] = child
			end
		end
	end

	local functionsFolder = (network :: Instance):FindFirstChild("RemoteFunctions")
	if functionsFolder then
		for _, child in ipairs((functionsFolder :: Instance):GetChildren()) do
			if child:IsA("RemoteFunction") then
				_remoteFunctions[child.Name] = child
			end
		end
	end

	_ready = true

	local reCount = 0
	for _ in pairs(_remoteEvents)   do reCount   += 1 end
	local rfCount = 0
	for _ in pairs(_remoteFunctions) do rfCount += 1 end
	print(("[NetworkController] ready — %d RemoteEvents, %d RemoteFunctions"):format(
		reCount, rfCount))
end

function NetworkControllerModule:Update(_dt: number) end

function NetworkControllerModule:Destroy()
	table.clear(_remoteEvents)
	table.clear(_remoteFunctions)
	_ready       = false
	_initialized = false
end

return NetworkControllerModule
