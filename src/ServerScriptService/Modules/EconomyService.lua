--!strict
-- EconomyService — Server-only ModuleScript
-- Grants hole/round/daily rewards through PlayerDataService. Sole handler for
-- MarketplaceService coin-pack receipts. Never writes to profiles directly.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants         = require(ReplicatedStorage.Shared.Modules.Constants)
local ScoringRules      = require(ReplicatedStorage.Shared.Modules.ScoringRules)
local PlayerDataService = require(script.Parent.PlayerDataService)

-- Developer Product id → coins granted. Populate with real product IDs before launch.
local COIN_PACKS: { [number]: number } = {
	-- [123456789] = 1000,
}

local DAILY_REWARDS: { [number]: { coins: number, xp: number } } = {
	[1] = { coins = 100, xp = 50  },
	[2] = { coins = 150, xp = 75  },
	[3] = { coins = 200, xp = 100 },
	[4] = { coins = 250, xp = 125 },
	[5] = { coins = 300, xp = 150 },
	[6] = { coins = 400, xp = 200 },
	[7] = { coins = 600, xp = 300 },
}

-- Placement bonus on top of the base XP_ROUND_MIN completion grant.
local PLACEMENT_REWARDS: { [number]: { coins: number, xp: number } } = {
	[1] = { coins = 500, xp = Constants.XP_ROUND_MAX - Constants.XP_ROUND_MIN },
	[2] = { coins = 300, xp = 100 },
	[3] = { coins = 200, xp = 50  },
}

local PARTICIPATION_COINS   = 100
local DAILY_STREAK_RESET_H  = 48  -- hours before a missed claim resets the streak

-- ── MarketplaceService receipt handler (stub — not wired in VS) ───────────────
-- Assign to MarketplaceService.ProcessReceipt when Dev Products go live.

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Guard: profile must be loaded before we can safely process the receipt.
	if not PlayerDataService:GetProfile(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if PlayerDataService:HasPurchaseId(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local coins = COIN_PACKS[receiptInfo.ProductId]
	if not coins then
		warn(("[EconomyService] Unknown ProductId: %d"):format(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	PlayerDataService:AddCoins(player, coins)
	PlayerDataService:AddPurchaseId(player, purchaseId)  -- FlushNow called inside

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ── Module ─────────────────────────────────────────────────────────────────

local EconomyService = {}
EconomyService.__index = EconomyService

function EconomyService:Init()
	-- processReceipt is ready but not wired until Dev Products are live (post-VS).
end

function EconomyService:Update(_dt: number) end

function EconomyService:Destroy() end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Grants XP + coins for a single hole result.
-- Returns { tier, xp, coins } so ScoringService can drive score-reveal UI.
function EconomyService:GrantHoleReward(
	player: Player,
	strokes: number,
	par: number
): { tier: string, xp: number, coins: number }
	local tier  = ScoringRules.ClassifyScore(strokes, par)
	local xp    = ScoringRules.TIER_XP[tier]   :: number
	local coins = ScoringRules.TIER_COINS[tier] :: number

	PlayerDataService:AddXP(player, xp)
	PlayerDataService:AddCoins(player, coins)

	return { tier = tier, xp = xp, coins = coins }
end

-- Grants the round-completion bonus.
-- placement: 1-based position among players; nil means solo play.
-- Returns { xp, coins } totals granted.
function EconomyService:GrantRoundReward(
	player: Player,
	placement: number?
): { xp: number, coins: number }
	local xp    = Constants.XP_ROUND_MIN  -- base for completing any round
	local coins = PARTICIPATION_COINS

	if placement then
		local bonus = PLACEMENT_REWARDS[placement]
		if bonus then
			xp    += bonus.xp
			coins  = bonus.coins
		end
	end

	PlayerDataService:AddXP(player, xp)
	PlayerDataService:AddCoins(player, coins)

	return { xp = xp, coins = coins }
end

-- Claims the daily reward for a player.
-- Returns { claimed = true, xp, coins, streak } on success,
--         { claimed = false, reason = "already_claimed" } if already claimed today.
function EconomyService:ClaimDailyReward(player: Player): { [string]: any }
	local todayStr = os.date("%Y-%m-%d") :: string
	local state    = PlayerDataService:GetDailyRewardState(player)

	if state.date == todayStr then
		return { claimed = false, reason = "already_claimed" }
	end

	-- Compute new streak; reset if more than DAILY_STREAK_RESET_H hours since last claim.
	local now      = os.time()
	local gapHours = (now - state.time) / 3600

	local newStreak = state.streak
	if state.time > 0 and gapHours > DAILY_STREAK_RESET_H then
		newStreak = 0
	end
	newStreak += 1

	PlayerDataService:SetDailyRewardState(player, todayStr, now, newStreak)

	-- Cycle through 7 tiers; players at day 8+ stay at tier 7 until reset.
	local tier   = math.min(newStreak, 7)
	local reward = DAILY_REWARDS[tier]

	PlayerDataService:AddCoins(player, reward.coins)
	PlayerDataService:AddXP(player, reward.xp)

	return {
		claimed = true,
		xp      = reward.xp,
		coins   = reward.coins,
		streak  = newStreak,
	}
end

return EconomyService
