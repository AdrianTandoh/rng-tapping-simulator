-- Ancient Spirit Simulator
-- Core earning mechanic: CLICK-TO-EARN (server-authoritative)
--
-- Players earn the "Spirit Power" stat by clicking the game world. The client
-- only *detects* clicks and asks the server to grant power; the server is the
-- single source of truth and the only thing that ever changes Spirit Power.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService") -- Heartbeat for the auto-clicker

--------------------------------------------------------------------------------
-- 0. One-time cleanup: strip the stray team-create sample script
--------------------------------------------------------------------------------
-- A leftover sample Script keeps getting restored loose in Workspace by the
-- team-create session (path Workspace.Script.Script.Script — a Script named
-- "Script" with nested copies of itself). It isn't in our Rojo files and errors on
-- run, so we remove it on every server startup. This is deliberately narrow: it
-- ONLY destroys Script instances parented DIRECTLY under Workspace AND named
-- "Script" — destroying each also takes its nested copies with it. Our real scripts
-- live in ServerScriptService / StarterPlayer / etc. (never loose in Workspace), and
-- LocalScripts/ModuleScripts don't pass IsA("Script"), so nothing real is touched.
for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("Script") and child.Name == "Script" then
		child:Destroy()
	end
end

--------------------------------------------------------------------------------
-- 0b. GROUP REWARDS + AUTO-CLICKER CONFIG (edit these freely)
--------------------------------------------------------------------------------
-- All of the tunable values for this slice live here so they're easy to change.

-- The Roblox group players must join to claim the reward bundle.
local GROUP_ID = 9319576 -- REPLACE with your Roblox group ID

-- The one-time reward bundle granted when a group member claims. Defined as an
-- editable table so rewards can be changed / added later (gems, pets, etc.).
-- The one-time-ness is tracked by a dedicated saved flag (ClaimedGroupReward), so
-- you can freely change which rewards are in the bundle below.
local GROUP_REWARD = {
	autoClicker = true, -- HEADLINE reward: permanent auto-clicker (1 click/sec)
	spiritPower = 500, -- lump of Spirit Power granted on claim
	zenLevels = 1, -- free Zen levels granted on claim (respects the cap)
	-- Add more rewards here later (e.g. gems = 100, pet = "Spirit Fox", ...) and
	-- grant them in claimGroupReward() below.
}

-- Auto-clicker tuning.
local AUTO_CLICK_BASE_AMOUNT = 1 -- base Spirit Power per auto-click, BEFORE the Zen multiplier
local AUTO_CLICK_INTERVAL = 1 -- seconds between auto-clicks (1 = one per second)

--------------------------------------------------------------------------------
-- 1. RemoteEvents
--------------------------------------------------------------------------------
-- Created here on the server and parented to ReplicatedStorage so the client can
-- safely find them with WaitForChild.

-- Fired by the client on each valid world click; server grants Spirit Power.
local clickEarnEvent = Instance.new("RemoteEvent")
clickEarnEvent.Name = "ClickEarn"
clickEarnEvent.Parent = ReplicatedStorage

-- Fired by the server to ask a client to open its shop popup (touch the pad).
local openShopEvent = Instance.new("RemoteEvent")
openShopEvent.Name = "OpenShop"
openShopEvent.Parent = ReplicatedStorage

-- Fired by the server to ask a client to open its Group Rewards popup (touch the
-- standalone Group Rewards pad in the world — separate from the shop).
local openGroupRewardsEvent = Instance.new("RemoteEvent")
openGroupRewardsEvent.Name = "OpenGroupRewards"
openGroupRewardsEvent.Parent = ReplicatedStorage

-- Fired by the server to ask a client to open its Ascend popup (touch the
-- standalone Ascend pad in the world — moved out of the shop).
local openAscendEvent = Instance.new("RemoteEvent")
openAscendEvent.Name = "OpenAscend"
openAscendEvent.Parent = ReplicatedStorage

-- Client invokes this to read its current Zen state (level/cost/multiplier).
local getZenStateFunc = Instance.new("RemoteFunction")
getZenStateFunc.Name = "GetZenState"
getZenStateFunc.Parent = ReplicatedStorage

-- Client invokes this to request a Zen purchase. The SERVER validates and
-- returns the resulting (authoritative) Zen state either way.
local buyZenFunc = Instance.new("RemoteFunction")
buyZenFunc.Name = "BuyZen"
buyZenFunc.Parent = ReplicatedStorage

-- Client invokes this to read its current Ascend state (count/requirement/mult).
local getAscendStateFunc = Instance.new("RemoteFunction")
getAscendStateFunc.Name = "GetAscendState"
getAscendStateFunc.Parent = ReplicatedStorage

-- Client invokes this to request an Ascend. The SERVER validates and returns
-- the resulting (authoritative) Ascend state either way.
local buyAscendFunc = Instance.new("RemoteFunction")
buyAscendFunc.Name = "Ascend"
buyAscendFunc.Parent = ReplicatedStorage

-- Client invokes this to read its current Soul Jar state (tier/capacity/price).
local getSoulJarStateFunc = Instance.new("RemoteFunction")
getSoulJarStateFunc.Name = "GetSoulJarState"
getSoulJarStateFunc.Parent = ReplicatedStorage

-- Client invokes this to request a Soul Jar upgrade. The SERVER validates and
-- returns the resulting (authoritative) Soul Jar state either way.
local buySoulJarFunc = Instance.new("RemoteFunction")
buySoulJarFunc.Name = "BuySoulJar"
buySoulJarFunc.Parent = ReplicatedStorage

-- Client invokes this to read its Group Reward state (in group? claimed? bundle).
local getGroupRewardStateFunc = Instance.new("RemoteFunction")
getGroupRewardStateFunc.Name = "GetGroupRewardState"
getGroupRewardStateFunc.Parent = ReplicatedStorage

-- Client invokes this to claim the group reward. The SERVER validates membership
-- + one-time-ness and grants the bundle, returning the result + new state.
local claimGroupRewardFunc = Instance.new("RemoteFunction")
claimGroupRewardFunc.Name = "ClaimGroupReward"
claimGroupRewardFunc.Parent = ReplicatedStorage

--------------------------------------------------------------------------------
-- 2. Player progression tables
--------------------------------------------------------------------------------
-- Server-authoritative per-player progression, declared up front so the data
-- loading + leaderstats setup below can seed them.
local zenLevel = {} -- [player] = Zen level (starts at 0)
local ascendCount = {} -- [player] = times Ascended (starts at 0)
local jarTier = {} -- [player] = Soul Jar tier index (0 = Clay, starts at 0)
local canSave = {} -- [player] = true ONLY if their data loaded cleanly (see 2c)
-- Set of players who own the permanent auto-clicker. A player is present (value
-- true) ONLY if they own it; missing = does not own it (defaults to false). This
-- drives the auto-clicker loop.
local hasAutoClicker = {}
-- Set of players who have already claimed the one-time group reward bundle. This
-- is the dedicated one-time-claim gate (separate from hasAutoClicker so the bundle
-- contents can change freely). Missing = not yet claimed (defaults to false).
local claimedGroupReward = {}

--------------------------------------------------------------------------------
-- 2b. Soul Jar (storage cap) configuration
--------------------------------------------------------------------------------
-- The Soul Jar caps how much Spirit Power a player can HOLD. Tiers are an ordered
-- list (index 1 = tier 0 = Clay, the default). `upgradeCost` is the price to buy
-- THIS tier from the previous one (Clay is free / owned by default).
--
-- PRICING NOTE: the design hint suggested "~half the next tier's capacity", but
-- since Spirit Power is hard-clamped to the CURRENT jar, a price above the
-- current capacity could never be afforded. So each upgrade instead costs the
-- current jar's full capacity (fill it, then upgrade) — always reachable. Edit
-- these numbers freely.
local SOUL_JAR_TIERS = {
	{ name = "Clay Jar", capacity = 1000, upgradeCost = 0 }, -- starting tier (owned)
	{ name = "Jade Jar", capacity = 10000, upgradeCost = 1000 },
	{ name = "Crystal Jar", capacity = 100000, upgradeCost = 10000 },
	{ name = "Obsidian Jar", capacity = 1000000, upgradeCost = 100000 },
	{ name = "Phoenix Urn", capacity = 10000000, upgradeCost = 1000000 },
	{ name = "Dragon Vessel", capacity = 100000000, upgradeCost = 10000000 },
	{ name = "Astral Chalice", capacity = 1000000000, upgradeCost = 100000000 },
	{ name = "Eternal Reliquary", capacity = 10000000000, upgradeCost = 1000000000 },
}

-- The Spirit Power cap for a player's current jar.
local function getSpiritCap(player)
	local tier = jarTier[player] or 0
	return SOUL_JAR_TIERS[tier + 1].capacity
end

--------------------------------------------------------------------------------
-- 2c. DataStore saving / loading
--------------------------------------------------------------------------------
-- Persists the four progress values (Spirit Power, Zen, Ascend, Jar) per UserId.
-- Every DataStore call is wrapped in pcall because they can throw.
local DataStoreService = game:GetService("DataStoreService")

local DATASTORE_NAME = "AncientSpiritData" -- single store
local DATA_KEY_VERSION = "PlayerData_v1" -- versioned key prefix; bump to migrate
local SAVE_MAX_ATTEMPTS = 3 -- retry a failing SAVE up to this many times
local SAVE_RETRY_DELAY = 2 -- seconds to wait between save retries

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local function dataKey(player)
	return DATA_KEY_VERSION .. "_" .. player.UserId
end

-- Fresh default progress for a brand-new player.
local function makeDefaults()
	return {
		SpiritPower = 0,
		ZenLevel = 0,
		AscendCount = 0,
		JarTier = 0,
		HasAutoClicker = false,
		ClaimedGroupReward = false,
		Chi = 0, -- second, spendable currency (no cap); starts at 0 for new players
	}
end

-- Returns: dataTable, loadOk(boolean).
-- loadOk is false ONLY when the DataStore call actually errored. A brand-new
-- player (no saved data) is a SUCCESSFUL load that returns defaults.
local function loadPlayerData(player)
	local ok, result = pcall(function()
		return dataStore:GetAsync(dataKey(player))
	end)

	if not ok then
		-- The call failed. Do NOT treat this as "new player" — that would risk
		-- overwriting good saved data with defaults. Use defaults for THIS
		-- session only and forbid saving (canSave stays false).
		warn("[Save] LOAD FAILED for " .. player.Name .. ": " .. tostring(result))
		return makeDefaults(), false
	end

	if result == nil then
		return makeDefaults(), true -- brand-new player
	end

	-- Existing data: read each field defensively. A player saved before these flags
	-- existed simply has no such field, which reads as false (default for existing
	-- players, exactly as required).
	return {
		SpiritPower = tonumber(result.SpiritPower) or 0,
		ZenLevel = tonumber(result.ZenLevel) or 0,
		AscendCount = tonumber(result.AscendCount) or 0,
		JarTier = tonumber(result.JarTier) or 0,
		HasAutoClicker = result.HasAutoClicker == true,
		ClaimedGroupReward = result.ClaimedGroupReward == true,
		-- Read defensively like the others: a player saved before Chi existed has no
		-- such field, which reads as 0 (the new-player default), exactly as required.
		Chi = tonumber(result.Chi) or 0,
	}, true
end

-- Saves a player's current progress, with simple retries. Skips entirely if the
-- player's data never loaded cleanly, which protects their real save from being
-- clobbered by this session's defaults.
local function savePlayerData(player)
	if not canSave[player] then
		warn("[Save] Skipping save for " .. player.Name .. " — data did not load cleanly this session; protecting existing save.")
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	-- Chi lives in its own replicated IntValue on the Player (see setupLeaderstats);
	-- read it the same way Spirit Power is read, defaulting to 0 if absent.
	local chi = player:FindFirstChild("Chi")
	local data = {
		SpiritPower = spiritPower and spiritPower.Value or 0,
		ZenLevel = zenLevel[player] or 0,
		AscendCount = ascendCount[player] or 0,
		JarTier = jarTier[player] or 0,
		HasAutoClicker = hasAutoClicker[player] == true,
		ClaimedGroupReward = claimedGroupReward[player] == true,
		Chi = chi and chi.Value or 0,
	}

	local attempt = 0
	local ok, err
	repeat
		attempt += 1
		ok, err = pcall(function()
			dataStore:SetAsync(dataKey(player), data)
		end)
		if not ok then
			warn("[Save] SAVE attempt " .. attempt .. " failed for " .. player.Name .. ": " .. tostring(err))
			if attempt < SAVE_MAX_ATTEMPTS then
				task.wait(SAVE_RETRY_DELAY)
			end
		end
	until ok or attempt >= SAVE_MAX_ATTEMPTS

	if ok then
		print("[Save] Saved progress for " .. player.Name)
	else
		warn("[Save] GAVE UP saving for " .. player.Name .. " after " .. attempt .. " attempts.")
	end
end

--------------------------------------------------------------------------------
-- 2d. Player join: load data, then build leaderstats
--------------------------------------------------------------------------------
-- Roblox shows any IntValue inside a "leaderstats" folder on the leaderboard.
local function setupLeaderstats(player)
	-- Load first so everything is seeded from saved progress (or defaults).
	local data, loadOk = loadPlayerData(player)
	canSave[player] = loadOk -- only allow saving if the load was clean

	zenLevel[player] = data.ZenLevel
	ascendCount[player] = data.AscendCount
	jarTier[player] = data.JarTier
	-- Store only when true, so these stay clean sets (missing = false).
	if data.HasAutoClicker then
		hasAutoClicker[player] = true
	end
	if data.ClaimedGroupReward then
		claimedGroupReward[player] = true
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local spiritPower = Instance.new("IntValue")
	spiritPower.Name = "Spirit Power"
	-- Clamp to the (now-known) jar capacity in case saved data somehow exceeds it.
	spiritPower.Value = math.min(data.SpiritPower, getSpiritCap(player))
	spiritPower.Parent = leaderstats

	leaderstats.Parent = player

	-- Chi: the second, spendable currency. It lives in its OWN replicated IntValue
	-- parented directly to the Player (deliberately NOT inside leaderstats, so it
	-- doesn't appear on the Roblox leaderboard) that the client watches read-only —
	-- mirroring how Spirit Power is exposed. Unlike Spirit Power it has no cap.
	local chi = Instance.new("IntValue")
	chi.Name = "Chi"
	chi.Value = data.Chi
	chi.Parent = player
end

-- Handle players who join after this script runs...
Players.PlayerAdded:Connect(setupLeaderstats)
-- ...and any players who already exist (e.g. fast Studio start / script reload).
-- task.spawn so a slow load for one doesn't block the others or script init.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupLeaderstats, player)
end

--------------------------------------------------------------------------------
-- 3. Ascend rewards + the single chokepoint for granting Spirit Power
--------------------------------------------------------------------------------
-- Ascend (prestige) tuning values — all grouped here so they're easy to tweak.
local ASCEND_BASE_REQUIREMENT = 10000 -- Spirit Power needed for the 1st Ascend
local ASCEND_REQUIREMENT_SCALE = 5 -- each Ascend multiplies the requirement by this
local ASCEND_CAP_INCREASE = 2 -- each Ascend raises the Zen level cap by this much
local ASCEND_MULTIPLIER_PER = 1.5 -- permanent Spirit Power multiplier gained per Ascend

-- Permanent global multiplier from prestige: 1.5 ^ AscendCount.
local function getAscendMultiplier(player)
	return ASCEND_MULTIPLIER_PER ^ (ascendCount[player] or 0)
end

-- ALL Spirit Power changes go through this one function, so every gain (clicks
-- now, auto-clicker later) automatically receives the Ascend multiplier on top
-- of whatever amount the caller passes in.
local function grantSpiritPower(player, amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	if spiritPower then
		-- Apply the permanent Ascend multiplier and floor to a whole number, then
		-- SOFT-CAP to the Soul Jar capacity: overflow beyond the cap is discarded
		-- (clicks still register; clicking while full simply wastes the excess).
		local gain = math.floor(amount * getAscendMultiplier(player))
		spiritPower.Value = math.min(spiritPower.Value + gain, getSpiritCap(player))
	end
end

--------------------------------------------------------------------------------
-- 3a. Chi — the single chokepoint for the second (spendable) currency
--------------------------------------------------------------------------------
-- Chi is introduced in this slice as PLUMBING only. Unlike Spirit Power (which the
-- Soul Jar soft-caps), Chi has NO cap — it's the spendable bank future slices will
-- draw from. It has no source or sink in normal play yet, so it stays 0 until a
-- future slice grants it (e.g. converting Spirit Power at an altar).
--
-- ALL Chi changes route through grantChi / spendChi, mirroring how grantSpiritPower
-- is the single chokepoint for Spirit Power — giving future slices exactly one place
-- to hook conversion, pricing, etc. The Ascend multiplier is intentionally NOT
-- applied here (Chi is a raw bank, not an earnings stream).
local function grantChi(player, amount)
	amount = math.floor(amount)
	if amount <= 0 then
		return -- ignore zero / negative grants; deductions go through spendChi
	end
	local chi = player:FindFirstChild("Chi")
	if chi then
		chi.Value += amount -- no cap: Chi is the spendable bank
	end
end

-- Deduct Chi for a purchase. Returns true and deducts ONLY if the player can fully
-- afford `amount`; otherwise returns false and changes nothing. Unused this slice
-- (Chi is currently unspendable), but defined now so every future sink routes here.
local function spendChi(player, amount)
	amount = math.floor(amount)
	if amount <= 0 then
		return true
	end
	local chi = player:FindFirstChild("Chi")
	if chi and chi.Value >= amount then
		chi.Value -= amount
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- 3b. Zen upgrade (click multiplier)
--------------------------------------------------------------------------------
-- Zen is a click multiplier. multiplier = 2 ^ ZenLevel, so each level doubles
-- click value (level 0 = x1, level 1 = x2, ... level 8 = x256).
--
-- The cap is computed per player (getZenCap) from a base value plus the Ascend
-- bonus, so the buy logic never hardcodes the limit.
local ZEN_BASE_CAP = 8 -- base max Zen level (x256); each Ascend raises it by ASCEND_CAP_INCREASE
local ZEN_BASE_PRICE = 50 -- Spirit Power cost of the first level (0 -> 1)
local ZEN_PRICE_MULTIPLIER = 2.5 -- each level costs 2.5x the previous one

-- (zenLevel table is declared earlier, near the leaderstats setup.)

-- A player's current Zen cap rises with how many times they've Ascended.
local function getZenCap(player)
	return ZEN_BASE_CAP + (ascendCount[player] or 0) * ASCEND_CAP_INCREASE
end

-- Click value multiplier for a given Zen level.
local function getZenMultiplier(level)
	return 2 ^ level
end

-- Cost (whole number) to buy the NEXT level when currently at `level`.
-- At level 0 -> 50, level 1 -> 125, level 2 -> 313, level 3 -> 781, ...
local function getZenCost(level)
	return math.round(ZEN_BASE_PRICE * (ZEN_PRICE_MULTIPLIER ^ level))
end

-- Snapshot of a player's Zen state, sent to the client to render the panel.
-- When maxed, `cost` is nil (there's nothing left to buy).
local function getZenState(player)
	local level = zenLevel[player] or 0
	local cap = getZenCap(player)
	local maxed = level >= cap
	return {
		level = level,
		multiplier = getZenMultiplier(level),
		cost = (not maxed) and getZenCost(level) or nil,
		maxed = maxed,
		cap = cap,
	}
end

-- The client asks for its current Zen state when it opens the shop.
getZenStateFunc.OnServerInvoke = function(player)
	return getZenState(player)
end

-- Purchase handler — fully validated on the server.
buyZenFunc.OnServerInvoke = function(player)
	local level = zenLevel[player] or 0

	-- Reject if already at the cap.
	if level >= getZenCap(player) then
		return getZenState(player) -- unchanged
	end

	-- Reject if the player can't afford the next level.
	local cost = getZenCost(level)
	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	if not spiritPower or spiritPower.Value < cost then
		return getZenState(player) -- unchanged
	end

	-- Valid purchase: deduct cost and increment level.
	spiritPower.Value -= cost
	zenLevel[player] = level + 1
	return getZenState(player)
end

--------------------------------------------------------------------------------
-- 3c. Ascend (prestige)
--------------------------------------------------------------------------------
-- Spirit Power required to Ascend at a given count.
-- count 0 -> 10,000, count 1 -> 50,000, count 2 -> 250,000, ...
local function getAscendRequirement(count)
	return ASCEND_BASE_REQUIREMENT * (ASCEND_REQUIREMENT_SCALE ^ count)
end

-- Snapshot of a player's Ascend state for the client to render.
local function getAscendState(player)
	local count = ascendCount[player] or 0
	return {
		count = count,
		requirement = getAscendRequirement(count),
		multiplier = getAscendMultiplier(player),
	}
end

-- Client asks for its current Ascend state (on shop open / startup).
getAscendStateFunc.OnServerInvoke = function(player)
	return getAscendState(player)
end

-- Ascend handler — fully validated on the server.
buyAscendFunc.OnServerInvoke = function(player)
	local count = ascendCount[player] or 0
	local requirement = getAscendRequirement(count)

	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")

	-- Reject if the player doesn't meet the Spirit Power requirement.
	if not spiritPower or spiritPower.Value < requirement then
		return getAscendState(player) -- unchanged
	end

	-- Perform the prestige:
	--  * reset Spirit Power to 0
	--  * reset Zen level to 0
	--  * increment Ascend count (this also raises the Zen cap via getZenCap and
	--    strengthens all future gains via getAscendMultiplier)
	spiritPower.Value = 0
	zenLevel[player] = 0
	ascendCount[player] = count + 1
	-- NOTE: JarTier is intentionally NOT touched here — the Soul Jar persists
	-- across Ascends.
	return getAscendState(player)
end

--------------------------------------------------------------------------------
-- 3d. Soul Jar purchases
--------------------------------------------------------------------------------
-- Snapshot of a player's Soul Jar state for the client to render.
local function getSoulJarState(player)
	local tier = jarTier[player] or 0
	local current = SOUL_JAR_TIERS[tier + 1]
	local nextTier = SOUL_JAR_TIERS[tier + 2] -- nil when already at the top
	return {
		tier = tier,
		currentName = current.name,
		currentCapacity = current.capacity,
		maxed = nextTier == nil,
		nextName = nextTier and nextTier.name or nil,
		nextCapacity = nextTier and nextTier.capacity or nil,
		nextCost = nextTier and nextTier.upgradeCost or nil,
	}
end

-- Client asks for its current Soul Jar state (on shop open / startup).
getSoulJarStateFunc.OnServerInvoke = function(player)
	return getSoulJarState(player)
end

-- Upgrade handler — fully validated on the server.
buySoulJarFunc.OnServerInvoke = function(player)
	local tier = jarTier[player] or 0
	local nextTier = SOUL_JAR_TIERS[tier + 2]

	-- Reject if already at the top tier.
	if not nextTier then
		return getSoulJarState(player) -- unchanged
	end

	-- Reject if the player can't afford the upgrade.
	local cost = nextTier.upgradeCost
	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	if not spiritPower or spiritPower.Value < cost then
		return getSoulJarState(player) -- unchanged
	end

	-- Valid purchase: deduct cost and advance the tier.
	spiritPower.Value -= cost
	jarTier[player] = tier + 1
	return getSoulJarState(player)
end

--------------------------------------------------------------------------------
-- 3e. Group reward (one-time claim, server-authoritative)
--------------------------------------------------------------------------------
-- Membership is verified with the proper Roblox API, Player:IsInGroup(groupId),
-- wrapped in pcall because it can throw. CAVEAT: IsInGroup is cached when the
-- player joins the server, so a player who joins the group mid-session may need
-- to rejoin the experience before it returns true.
local function isInGroup(player)
	if GROUP_ID <= 0 then
		return false -- group not configured yet (placeholder GROUP_ID)
	end
	local ok, result = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if not ok then
		warn("[Group] IsInGroup failed for " .. player.Name .. ": " .. tostring(result))
		return false
	end
	return result
end

-- Snapshot of a player's group-reward state for the client to render. `claimed`
-- is gated on the dedicated ClaimedGroupReward flag, which makes the bundle
-- strictly one-time across sessions regardless of which rewards are in it.
local function getGroupRewardState(player)
	return {
		configured = GROUP_ID > 0,
		groupId = GROUP_ID,
		inGroup = isInGroup(player),
		claimed = claimedGroupReward[player] == true,
		reward = {
			autoClicker = GROUP_REWARD.autoClicker,
			spiritPower = GROUP_REWARD.spiritPower,
			zenLevels = GROUP_REWARD.zenLevels,
		},
	}
end

-- Claim handler — fully validated on the server. RE-VERIFIES membership AND
-- not-already-claimed before granting. Returns { ok, message, state }.
local function claimGroupReward(player)
	-- Reject: group not set up, already claimed, or not a member.
	if GROUP_ID <= 0 then
		return { ok = false, message = "Group rewards aren't set up yet.", state = getGroupRewardState(player) }
	end
	if claimedGroupReward[player] == true then
		return { ok = false, message = "You've already claimed this reward.", state = getGroupRewardState(player) }
	end
	if not isInGroup(player) then
		return { ok = false, message = "Join the group first, then claim!", state = getGroupRewardState(player) }
	end

	-- Valid claim: mark the one-time claim used (persisted), then grant each piece
	-- of the bundle. (Add future rewards here.)
	claimedGroupReward[player] = true
	if GROUP_REWARD.autoClicker then
		hasAutoClicker[player] = true -- permanent; turns on the auto-clicker loop
	end
	if GROUP_REWARD.spiritPower and GROUP_REWARD.spiritPower > 0 then
		-- Routed through grantSpiritPower so it respects the Soul Jar soft cap (and
		-- picks up the Ascend multiplier), consistent with every other SP gain.
		grantSpiritPower(player, GROUP_REWARD.spiritPower)
	end
	if GROUP_REWARD.zenLevels and GROUP_REWARD.zenLevels > 0 then
		-- Respect the per-player Zen cap; never push past it.
		zenLevel[player] = math.min((zenLevel[player] or 0) + GROUP_REWARD.zenLevels, getZenCap(player))
	end

	return { ok = true, message = "Reward claimed! Auto-clicker activated.", state = getGroupRewardState(player) }
end

-- Client asks for its current group-reward state (on shop open / startup).
getGroupRewardStateFunc.OnServerInvoke = function(player)
	return getGroupRewardState(player)
end

-- Client requests a claim; the server validates and grants.
claimGroupRewardFunc.OnServerInvoke = function(player)
	return claimGroupReward(player)
end

--------------------------------------------------------------------------------
-- 4. Click-to-earn with a simple rate limit
--------------------------------------------------------------------------------
-- Basic anti-exploit protection: a client could be hacked to fire the RemoteEvent
-- thousands of times per second. We record when each player's last click was
-- accepted and silently ignore any click that arrives sooner than a human could
-- realistically click. This is intentionally minimal, not full anti-cheat.

local MIN_CLICK_GAP = 0.05 -- seconds between accepted clicks (~20 clicks/sec cap)
local CLICK_BASE_AMOUNT = 1 -- base Spirit Power per click, BEFORE the Zen multiplier
local lastClickTime = {} -- [player] = os.clock() of last accepted click

-- The single definition of "what one click is worth". A click is its base amount
-- scaled by the player's Zen multiplier, then routed through grantSpiritPower
-- (which layers on the Ascend multiplier and the Soul Jar soft cap). Both manual
-- clicks AND the auto-clicker call this, so they behave IDENTICALLY apart from the
-- base amount each passes in.
local function applyClick(player, baseAmount)
	local multiplier = getZenMultiplier(zenLevel[player] or 0)
	grantSpiritPower(player, (baseAmount or CLICK_BASE_AMOUNT) * multiplier)
end

clickEarnEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	local last = lastClickTime[player]

	-- Reject clicks that come in faster than the allowed gap.
	if last and (now - last) < MIN_CLICK_GAP then
		return
	end

	lastClickTime[player] = now
	applyClick(player)
end)

--------------------------------------------------------------------------------
-- 4b. Auto-clicker (server-side Heartbeat timer)
--------------------------------------------------------------------------------
-- Players who own the auto-clicker get one free "click" per second, granted
-- entirely on the server. We accumulate Heartbeat delta-time and grant whole
-- ticks once each interval elapses (NOT a wait() loop), and only iterate the set
-- of owners. Each tick reuses applyClick(), so auto-clicks inherit the Zen
-- multiplier, the Ascend multiplier and the soft cap exactly like manual clicks.
local autoClickAccumulator = 0

RunService.Heartbeat:Connect(function(dt)
	autoClickAccumulator += dt
	if autoClickAccumulator < AUTO_CLICK_INTERVAL then
		return
	end

	-- Number of whole intervals that elapsed (normally 1; >1 guards a frame hitch
	-- so a lag spike doesn't silently swallow earned auto-clicks).
	local ticks = math.floor(autoClickAccumulator / AUTO_CLICK_INTERVAL)
	autoClickAccumulator -= ticks * AUTO_CLICK_INTERVAL

	for player in pairs(hasAutoClicker) do
		for _ = 1, ticks do
			applyClick(player, AUTO_CLICK_BASE_AMOUNT)
		end
	end
end)

--------------------------------------------------------------------------------
-- 5. World pads (matching glowing monuments: Shop, Ascend, Group Rewards)
--------------------------------------------------------------------------------
-- Each pad is a raised "monument": a dark stone pedestal with a glowing lit disc
-- on top that players can stand on, plus a floating title above it. Touching one
-- tells the player's client to open the matching popup (the UI is client-side;
-- the server only owns the pads and fires the open RemoteEvents).

-- Per-pad debounce tables are registered here so PlayerRemoving can clear them.
local padDebounces = {} -- list of { [player] = true } tables, one per pad

-- Reusable monument builder. `opts`:
--   name, position (Vector3 ground center), discColor, glowColor?, pedestalColor?,
--   title, subtitle?, titleColor?, strokeColor?, onTouched (function(player)).
local function createMonumentPad(opts)
	local model = Instance.new("Model")
	model.Name = opts.name

	-- Dark stone pedestal (the podium). A wide, short cylinder laid flat
	-- (Orientation rotates its axis from X to vertical Y so the round face is up).
	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Size = Vector3.new(1.5, 24, 24) -- X = height (after rotation), Y/Z = diameter
	pedestal.Orientation = Vector3.new(0, 0, 90)
	pedestal.Position = opts.position + Vector3.new(0, 0.75, 0)
	pedestal.Anchored = true
	pedestal.Material = Enum.Material.Slate
	pedestal.Color = opts.pedestalColor or Color3.fromRGB(48, 44, 60)
	pedestal.Parent = model

	-- Glowing lit disc on top — the platform players stand on.
	local disc = Instance.new("Part")
	disc.Name = "GlowDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.8, 18, 18) -- thin disc, 18 studs across
	disc.Orientation = Vector3.new(0, 0, 90)
	disc.Position = opts.position + Vector3.new(0, 1.9, 0)
	disc.Anchored = true
	disc.Material = Enum.Material.Neon
	disc.Color = opts.discColor
	disc.Parent = model

	-- A matching PointLight so the monument casts a glow on its surroundings.
	local glow = Instance.new("PointLight")
	glow.Color = opts.glowColor or opts.discColor
	glow.Brightness = 4
	glow.Range = 18
	glow.Parent = disc

	-- Floating label above the monument: a big title, plus an optional subtitle.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromScale(10, 3) -- studs (Adornee scale)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = disc

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.fromScale(0.5, 0)
	titleLabel.Size = opts.subtitle and UDim2.fromScale(1, 0.65) or UDim2.fromScale(1, 1)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = opts.title
	titleLabel.Font = Enum.Font.FredokaOne -- playful, matches the rest of the game
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = opts.titleColor or Color3.fromRGB(255, 255, 255)
	titleLabel.TextStrokeTransparency = 0.3
	titleLabel.TextStrokeColor3 = opts.strokeColor or Color3.fromRGB(20, 20, 30)
	titleLabel.Parent = billboard

	if opts.subtitle then
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.Name = "Subtitle"
		subtitleLabel.AnchorPoint = Vector2.new(0.5, 1)
		subtitleLabel.Position = UDim2.fromScale(0.5, 1)
		subtitleLabel.Size = UDim2.fromScale(1, 0.35)
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Text = opts.subtitle
		subtitleLabel.Font = Enum.Font.FredokaOne
		subtitleLabel.TextScaled = true
		subtitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		subtitleLabel.TextStrokeTransparency = 0.4
		subtitleLabel.TextStrokeColor3 = opts.strokeColor or Color3.fromRGB(20, 20, 30)
		subtitleLabel.Parent = billboard
	end

	billboard.Parent = disc
	model.Parent = Workspace

	-- Per-pad debounce so one step-on doesn't spam the remote. Both parts share the
	-- handler so touching the pedestal edge or stepping onto the disc both work.
	local debounce = {}
	table.insert(padDebounces, debounce)

	local function onTouched(hit)
		local character = hit.Parent
		local plr = character and Players:GetPlayerFromCharacter(character)
		if not plr or debounce[plr] then
			return
		end
		debounce[plr] = true
		opts.onTouched(plr)
		task.delay(1, function()
			debounce[plr] = nil
		end)
	end

	disc.Touched:Connect(onTouched)
	pedestal.Touched:Connect(onTouched)

	return model
end

-- The three pads, spaced 32 studs apart along X at z = 24 (pedestals are 24 wide,
-- so a 32-stud gap leaves clear space between them — no overlap).
local PAD_Z = 24

-- SHOP (gold) — opens the shop popup (now Zen + Soul Jar only).
createMonumentPad({
	name = "ShopPad",
	position = Vector3.new(-32, 0, PAD_Z),
	discColor = Color3.fromRGB(255, 200, 40),
	glowColor = Color3.fromRGB(255, 215, 90),
	pedestalColor = Color3.fromRGB(70, 58, 30),
	title = "SHOP",
	titleColor = Color3.fromRGB(255, 235, 170),
	strokeColor = Color3.fromRGB(120, 80, 0),
	onTouched = function(plr)
		openShopEvent:FireClient(plr)
	end,
})

-- ASCEND (cyan/teal) — opens the standalone Ascend popup.
createMonumentPad({
	name = "AscendPad",
	position = Vector3.new(0, 0, PAD_Z),
	discColor = Color3.fromRGB(40, 220, 220),
	glowColor = Color3.fromRGB(90, 240, 240),
	pedestalColor = Color3.fromRGB(28, 56, 60),
	title = "ASCEND",
	titleColor = Color3.fromRGB(190, 255, 255),
	strokeColor = Color3.fromRGB(0, 70, 80),
	onTouched = function(plr)
		openAscendEvent:FireClient(plr)
	end,
})

-- GROUP REWARDS (purple) — opens the Group Rewards popup. The claim/membership
-- LOGIC lives in section 3e; this pad is only the trigger.
createMonumentPad({
	name = "GroupRewardsPad",
	position = Vector3.new(32, 0, PAD_Z),
	discColor = Color3.fromRGB(160, 90, 245),
	glowColor = Color3.fromRGB(170, 100, 255),
	pedestalColor = Color3.fromRGB(48, 38, 74),
	title = "GROUP REWARDS",
	subtitle = "Join the Group for Rewards!",
	titleColor = Color3.fromRGB(220, 180, 255),
	strokeColor = Color3.fromRGB(60, 25, 110),
	onTouched = function(plr)
		openGroupRewardsEvent:FireClient(plr)
	end,
})

--------------------------------------------------------------------------------
-- 6. Save on leave + per-player cleanup
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	-- Save BEFORE clearing the tables that savePlayerData reads from.
	savePlayerData(player)

	lastClickTime[player] = nil
	for _, debounce in ipairs(padDebounces) do
		debounce[player] = nil
	end
	zenLevel[player] = nil
	ascendCount[player] = nil
	jarTier[player] = nil
	hasAutoClicker[player] = nil
	claimedGroupReward[player] = nil
	canSave[player] = nil
end)

--------------------------------------------------------------------------------
-- 7. Save everyone on server shutdown
--------------------------------------------------------------------------------
-- BindToClose runs when the server shuts down, so progress isn't lost on close.
-- Saves run in parallel and we wait (up to a budget) for them to finish.
game:BindToClose(function()
	local players = Players:GetPlayers()
	local remaining = #players
	if remaining == 0 then
		return
	end

	for _, player in ipairs(players) do
		task.spawn(function()
			savePlayerData(player)
			remaining -= 1
		end)
	end

	-- Wait for the saves to complete, but never exceed the shutdown budget.
	local elapsed = 0
	while remaining > 0 and elapsed < 25 do
		elapsed += task.wait()
	end
end)
