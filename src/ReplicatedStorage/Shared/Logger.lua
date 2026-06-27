--!strict
-- Logger — Shared singleton (AAA Golf)
-- Simple scoped logger available to both client and server modules.
-- Place in ReplicatedStorage.Shared so any side can require it.
--
-- Usage:
--   local Logger = require(game:GetService("ReplicatedStorage").Shared.Logger)
--   Logger:Info("MyController",  "ready")
--   Logger:Debug("MyController", "state → SWING")   -- suppressed when DEBUG=false
--   Logger:Warn("MyController",  "unexpected value") -- always calls warn()
--
-- Toggle at the top of a Play session to enable verbose debug logs:
--   Logger.DEBUG = true

local Logger = {}

-- ── Level flags ───────────────────────────────────────────────────────────────

Logger.DEBUG = false  -- set true to see state-transition and stream logs
Logger.INFO  = true   -- set false to suppress even startup / ready messages

-- ── API ───────────────────────────────────────────────────────────────────────

-- Prints only when Logger.DEBUG == true.
-- Use for high-frequency events: state transitions, per-frame stream packets.
function Logger:Debug(scope: string, message: string)
	if not self.DEBUG then return end
	print(("[%s] %s"):format(scope, message))
end

-- Prints only when Logger.INFO == true (default: true).
-- Use for one-time startup confirmations and meaningful player actions.
function Logger:Info(scope: string, message: string)
	if not self.INFO then return end
	print(("[%s] %s"):format(scope, message))
end

-- Always calls warn(). Use for recoverable unexpected conditions.
-- Mirrors existing direct warn() calls — never suppressed.
function Logger:Warn(scope: string, message: string)
	warn(("[%s] %s"):format(scope, message))
end

return Logger
