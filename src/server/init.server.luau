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
local ServerStorage = game:GetService("ServerStorage") -- holds the cosmetic wand source model (slice 1)

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
-- 0c. WORLDS CONFIG — the heart of the multi-world system (edit / add freely)
--------------------------------------------------------------------------------
-- One place, multiple "worlds" (areas), NOT separate places/teleports. This is the
-- single source of truth for every world's tuning. To add a 4th world, just append
-- a new {} entry below — nothing else in this slice needs to change.
--
-- Each world has:
--   name                    : display name (spirit-themed).
--   conversionRate          : Meditation Altar rate. floor(SpiritPower * conversionRate)
--                             Chi per convert. Starter is deliberately stingy (0.3).
--   jarCapMultiplier        : multiplier applied to Soul Jar capacities while in this
--                             world (scales the SP storage cap per world). DEFINED NOW
--                             but NOT yet applied to gameplay — wired in a later slice.
--   clickMultiplier         : extra click-earn multiplier while in this world. DEFINED
--                             NOW but NOT yet applied to gameplay — wired in a later slice.
--   unlockChiCost           : Chi needed to unlock this world (starter is free = 0).
--   unlockAscendRequirement : minimum AscendCount allowed to unlock (starter = 0).
--
-- World 1 is the free, default starter that every player owns. Indices are the save
-- representation (currentWorld = an index; unlockedWorlds = a set/array of indices).
local WORLDS = {
	[1] = {
		name = "Tranquil Grove",
		conversionRate = 0.3,
		jarCapMultiplier = 1, -- scales Soul Jar cap in this world (later slice)
		clickMultiplier = 1, -- extra click-earn multiplier in this world (later slice)
		unlockChiCost = 0, -- free: the default starter world
		unlockAscendRequirement = 0,
	},
	[2] = {
		name = "Whispering Highlands",
		conversionRate = 0.6,
		jarCapMultiplier = 3, -- scales Soul Jar cap in this world (later slice)
		clickMultiplier = 2, -- extra click-earn multiplier in this world (later slice)
		unlockChiCost = 5000,
		unlockAscendRequirement = 1,
	},
	[3] = {
		name = "Celestial Summit",
		conversionRate = 1.0,
		jarCapMultiplier = 10, -- scales Soul Jar cap in this world (later slice)
		clickMultiplier = 5, -- extra click-earn multiplier in this world (later slice)
		unlockChiCost = 50000,
		unlockAscendRequirement = 3,
	},
}

local DEFAULT_WORLD = 1 -- index every player starts in / owns by default

--------------------------------------------------------------------------------
-- 0d. PHYSICAL LAYOUT (Slice W2a: hub + three earning-area worlds + travel)
--------------------------------------------------------------------------------
-- One place, many areas (NOT separate Roblox places). The HUB is a neutral space
-- holding every pad (Shop/Ascend/Group/Altar); each WORLD is a far-away themed
-- platform you stand on to click-earn. Coordinates are deliberately far apart so the
-- areas never overlap. Edit these to move things around.
local HUB_SPAWN = Vector3.new(0, 5, 0) -- where the hub places a character (HumanoidRootPart)
local WORLD_CENTERS = { -- ground center of each world platform
	[1] = Vector3.new(1600, 0, 0),
	[2] = Vector3.new(0, 0, 1600),
	[3] = Vector3.new(-1600, 0, 0),
}
local WORLD_FLOOR_SIZE = 180 -- square world platform (studs)
local WORLD_SPAWN_OFFSET = Vector3.new(0, 5, 0) -- HRP height above a world's center
local RETURN_PORTAL_OFFSET = Vector3.new(0, 4, 60) -- return portal placement within a world

-- Spawn CFrame for a world index (falls back to the starter world if unknown).
local function worldSpawnCFrame(index)
	local center = WORLD_CENTERS[index] or WORLD_CENTERS[DEFAULT_WORLD]
	return CFrame.new(center + WORLD_SPAWN_OFFSET)
end

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

-- Fired by the server when a player touches the Meditation Altar pad, telling that
-- client to request a conversion (the actual convert is the RemoteFunction below).
local altarTouchedEvent = Instance.new("RemoteEvent")
altarTouchedEvent.Name = "AltarTouched"
altarTouchedEvent.Parent = ReplicatedStorage

-- Client invokes this to convert ALL its Spirit Power into Chi. The SERVER does all
-- the work and returns { ok, converted, message } for client-side feedback.
local convertSpiritToChiFunc = Instance.new("RemoteFunction")
convertSpiritToChiFunc.Name = "ConvertSpiritToChi"
convertSpiritToChiFunc.Parent = ReplicatedStorage

-- W2a TRAVEL. Client fires this to REQUEST travel; the SERVER owns the move (sets
-- currentWorld + teleports). Payload: a number — 0 = hub, 1..N = world index. The
-- client never sets its own world (server-authoritative).
local requestTravelEvent = Instance.new("RemoteEvent")
requestTravelEvent.Name = "RequestTravel"
requestTravelEvent.Parent = ReplicatedStorage

-- Client invokes this to populate the HUD "Worlds" menu: the world list (index+name)
-- plus where the player currently is (atHub / currentWorld).
local getWorldsStateFunc = Instance.new("RemoteFunction")
getWorldsStateFunc.Name = "GetWorldsState"
getWorldsStateFunc.Parent = ReplicatedStorage

-- W3 UNLOCK GATING. Server → client PUSH fired the moment a world FIRST unlocks for a
-- player (Ascend + Chi thresholds met simultaneously). Payload: (index, name). The client
-- uses it to refresh an open Worlds menu reactively and show an "unlocked!" toast.
local worldUnlockedEvent = Instance.new("RemoteEvent")
worldUnlockedEvent.Name = "WorldUnlocked"
worldUnlockedEvent.Parent = ReplicatedStorage

-- W3 UNLOCK GATING. Server → client PUSH fired when the server REJECTS a travel request
-- to a still-locked world (menu click or walking into a portal). Payload:
-- (index, name, reqAscend, reqChi) so the client can show the requirement message.
local travelBlockedEvent = Instance.new("RemoteEvent")
travelBlockedEvent.Name = "TravelBlocked"
travelBlockedEvent.Parent = ReplicatedStorage

-- DAILY LOGIN REWARDS. Client invokes this to read its current daily-reward state (the
-- reward table + which day is claimable now / claimed / upcoming + cooldown remaining).
local getDailyRewardStateFunc = Instance.new("RemoteFunction")
getDailyRewardStateFunc.Name = "GetDailyRewardState"
getDailyRewardStateFunc.Parent = ReplicatedStorage

-- DAILY LOGIN REWARDS. Client invokes this to claim the available reward. The SERVER is the
-- sole authority: it validates the cooldown against SERVER time, grants the Chi, advances the
-- streak, persists, and returns { ok, message, ..., state } either way.
local claimDailyRewardFunc = Instance.new("RemoteFunction")
claimDailyRewardFunc.Name = "ClaimDailyReward"
claimDailyRewardFunc.Parent = ReplicatedStorage

-- COSMETIC WAND (slice 1). Client fires this to REQUEST toggling its placeholder wand on/off.
-- The SERVER owns the wand entirely (creates/welds/destroys it on the character), so the wand
-- replicates to everyone; the client only asks. Payload: none (it's a toggle).
local toggleWandEvent = Instance.new("RemoteEvent")
toggleWandEvent.Name = "ToggleWand"
toggleWandEvent.Parent = ReplicatedStorage

-- Server → client PUSH for the Fusion "Live Stats Panel" (display-only). The server
-- fires this with a snapshot of the player's current world stats + Ascend multiplier:
-- once when the client first asks for it, and again whenever those values change (world
-- travel / Ascend). The client never sets these — they're server-authoritative. The
-- client may also FIRE this (no args) to REQUEST its initial snapshot.
local statsUpdateEvent = Instance.new("RemoteEvent")
statsUpdateEvent.Name = "StatsUpdate"
statsUpdateEvent.Parent = ReplicatedStorage

--------------------------------------------------------------------------------
-- 2. Player progression tables
--------------------------------------------------------------------------------
-- Server-authoritative per-player progression, declared up front so the data
-- loading + leaderstats setup below can seed them.
local zenLevel = {} -- [player] = Zen level (starts at 0)
local ascendCount = {} -- [player] = times Ascended (starts at 0)
local jarTier = {} -- [player] = Soul Jar tier index (0 = Clay, starts at 0)
local canSave = {} -- [player] = true ONLY if their data loaded cleanly (see 2c)
-- SAVE THROTTLING (see 2c). dirty[player] = true when the player's in-memory progress has
-- diverged from what's persisted; the periodic autosave (section 6b) flushes it. saving[player]
-- = true while a SetAsync for that player's key is in flight, so two saves of the SAME key can
-- never run at once (this coalescing is what stops the DataStore "request added to queue"
-- warning). Both are cleared in the PlayerRemoving cleanup.
local dirty = {} -- [player] = true if data changed since the last successful save
local saving = {} -- [player] = true while a save for this player's key is in flight
-- [player] = true once setup has STARTED for them. Set SYNCHRONOUSLY (before the
-- yielding DataStore load) so a player can NEVER be set up twice — this is what stops
-- duplicate leaderstats / Spirit Power / Chi objects, the root of the Chi desync.
local initialized = {}
-- Set of players who own the permanent auto-clicker. A player is present (value
-- true) ONLY if they own it; missing = does not own it (defaults to false). This
-- drives the auto-clicker loop.
local hasAutoClicker = {}
-- Set of players who have already claimed the one-time group reward bundle. This
-- is the dedicated one-time-claim gate (separate from hasAutoClicker so the bundle
-- contents can change freely). Missing = not yet claimed (defaults to false).
local claimedGroupReward = {}
-- DAILY LOGIN REWARDS (server-authoritative, persisted). lastDailyClaim[player] is the SERVER
-- os.time() of their last successful claim (0 / absent = never claimed). dailyStreak[player] is
-- the streak DAY they last claimed up to (0 = none); the next claimable day is derived from it
-- and LOOPS over the reward table. Both are seeded from saved data in setupLeaderstats and only
-- ever change inside the daily-reward claim chokepoint (section 3g).
local lastDailyClaim = {} -- [player] = os.time() of last claim (0 = never)
local dailyStreak = {} -- [player] = streak day claimed up to (0 = none)
-- Per-player WORLD state (server-authoritative, persisted). currentWorld[player] is
-- the index of the world they're currently in (default DEFAULT_WORLD). unlockedWorlds
-- [player] is a SET of unlocked indices ({ [1] = true, ... }); it always contains the
-- starter world. These are seeded from saved data in setupLeaderstats.
local currentWorld = {} -- [player] = world index (default 1)
local unlockedWorlds = {} -- [player] = { [index] = true } set of unlocked worlds
-- [player] = true when the player is physically in the HUB, false when in their
-- currentWorld's area (W2a). Saved so a rejoin restores the right area. The hub uses a
-- 1x click multiplier (see applyClick); currentWorld still drives the altar rate even
-- while in the hub (you earn in a world, then convert at that world's rate in the hub).
local atHub = {}

-- The config row for the world a player is currently in. Falls back to the starter
-- world if the stored index is ever missing/invalid, so callers always get a world.
local function getCurrentWorld(player)
	return WORLDS[currentWorld[player] or DEFAULT_WORLD] or WORLDS[DEFAULT_WORLD]
end

-- W3 UNLOCK GATING — a world's unlock REQUIREMENT (NOT a cost; nothing is ever spent).
-- A world unlocks the first moment a player has BOTH AscendCount >= ascend AND Chi >= chi
-- simultaneously. Values come straight from the WORLDS config: unlockAscendRequirement and
-- unlockChiCost ("Cost" is a legacy field name — W3 reads it as a requirement, never spends
-- it). The starter world has a 0/0 requirement, so it's always satisfied.
local function worldUnlockReq(index)
	local w = WORLDS[index]
	return (w and w.unlockAscendRequirement) or 0, (w and w.unlockChiCost) or 0
end

-- Is `index` unlocked for this player? The starter world is ALWAYS unlocked; every other
-- world is unlocked iff it's present in the player's persisted unlockedWorlds set. Defensive
-- against a missing set (treats it as "only the starter is unlocked").
local function isWorldUnlocked(player, index)
	if index == DEFAULT_WORLD then
		return true
	end
	local set = unlockedWorlds[player]
	return set ~= nil and set[index] == true
end

-- Where to place this player's character on spawn: the hub, or their current world.
local function spawnCFrameFor(player)
	if atHub[player] == false then -- explicitly in a world (nil/true both mean hub)
		return worldSpawnCFrame(currentWorld[player] or DEFAULT_WORLD)
	end
	return CFrame.new(HUB_SPAWN)
end

-- Teleport a (possibly still-loading) character to a CFrame.
local function placeCharacter(player, character)
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		hrp.CFrame = spawnCFrameFor(player)
	end
end

-- W2b PER-PLAYER VISIBILITY (state replication half). We publish each player's view
-- location — hub vs which world — as ATTRIBUTES on the Player instance. Roblox replicates
-- instance attributes to every client automatically and fires AttributeChanged, so each
-- client can read where everyone is and hide the worlds/players that aren't relevant to
-- it. This is replication ONLY: the server still owns currentWorld/atHub and performs all
-- travel; clients merely use these values to decide what they RENDER. Call this anywhere
-- atHub/currentWorld changes.
local function syncWorldAttributes(player)
	player:SetAttribute("WorldAtHub", atHub[player] ~= false)
	player:SetAttribute("WorldIndex", currentWorld[player] or DEFAULT_WORLD)
end

-- Forward declaration: pushes the Live Stats Panel snapshot to a client. It's
-- ASSIGNED later (section 3-LIVE), once getCurrentWorld/getAscendMultiplier exist,
-- but declared here so setupLeaderstats (above that point) can call it after a
-- player's saved world/ascend data loads — guaranteeing the panel's first values
-- are correct even for a returning player who isn't in the starter world.
local pushStats

--------------------------------------------------------------------------------
-- 2b. Soul Jar (storage cap) configuration
--------------------------------------------------------------------------------
-- The Soul Jar caps how much Spirit Power a player can HOLD. Tiers are an ordered
-- list (index 1 = tier 0 = Clay, the default). `upgradeCost` is the price to buy
-- THIS tier from the previous one (Clay is free / owned by default).
--
-- PRICING NOTE: upgrade costs are now paid in CHI (the uncapped spendable bank), not
-- Spirit Power, so they're no longer bounded by the current jar's capacity. The
-- numbers are unchanged from when they were Spirit-Power-priced (each upgrade costs
-- the previous jar's full capacity) and will be retuned in a later pass. The jar
-- still CAPS Spirit Power (getSpiritCap) — only the upgrade cost is Chi now. Edit
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
-- How often the periodic autosave (section 6b) flushes dirty players. Roblox budgets roughly
-- 6 + numPlayers DataStore writes per minute PER KEY; one write per player per 60s sits far
-- under that even with the occasional leave/shutdown write on top, so the queue never fills.
local AUTOSAVE_INTERVAL = 60 -- seconds between autosave passes

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
		-- Daily login rewards. A new player has never claimed (timestamp 0) and is on streak 0,
		-- so their first claim is immediately available and grants Day 1.
		LastDailyClaim = 0,
		DailyStreak = 0,
		Chi = 0, -- second, spendable currency (no cap); starts at 0 for new players
		-- World state. CurrentWorld is an index; UnlockedWorlds is a SET (the in-memory
		-- form: { [index] = true }). New players start in / own only the starter world.
		CurrentWorld = DEFAULT_WORLD,
		UnlockedWorlds = { [DEFAULT_WORLD] = true },
		-- New players start in the neutral hub (where all the pads are), not inside a world.
		AtHub = true,
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

	-- World state, read defensively like everything else. A player saved before worlds
	-- existed has neither field, so they default to currentWorld=1 / unlockedWorlds={1},
	-- exactly as required.
	--   * CurrentWorld: must be a valid world index, else snap back to the starter.
	--   * UnlockedWorlds: saved as an ARRAY of indices; rebuild into a SET, keeping only
	--     valid indices and ALWAYS including the starter world (never lockable).
	local savedCurrent = tonumber(result.CurrentWorld) or DEFAULT_WORLD
	if WORLDS[savedCurrent] == nil then
		savedCurrent = DEFAULT_WORLD
	end
	local savedUnlocked = { [DEFAULT_WORLD] = true }
	if type(result.UnlockedWorlds) == "table" then
		for _, idx in ipairs(result.UnlockedWorlds) do
			local n = tonumber(idx)
			if n and WORLDS[n] ~= nil then
				savedUnlocked[n] = true
			end
		end
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
		-- Daily login rewards, read defensively. A player saved before these existed has neither
		-- field, so they default to 0/0 (never claimed, streak 0) — exactly the new-player state.
		LastDailyClaim = tonumber(result.LastDailyClaim) or 0,
		DailyStreak = tonumber(result.DailyStreak) or 0,
		-- Read defensively like the others: a player saved before Chi existed has no
		-- such field, which reads as 0 (the new-player default), exactly as required.
		Chi = tonumber(result.Chi) or 0,
		CurrentWorld = savedCurrent,
		UnlockedWorlds = savedUnlocked, -- SET form (in-memory); serialized as array on save
		-- Physical location. Missing (older saves) reads as true = the hub, a safe default
		-- that drops the player at the pads rather than stranding them in a world.
		AtHub = result.AtHub ~= false,
	}, true
end

-- Flag that a player's in-memory progress now differs from what's saved. Cheap (just sets a
-- bool); call it from EVERY chokepoint that changes a saved field. The actual DataStore write
-- is deferred to the periodic autosave (section 6b), so a thousand rapid changes still cost at
-- most one write per AUTOSAVE_INTERVAL instead of one write each.
local function markDirty(player)
	dirty[player] = true
end

-- Saves a player's current progress, with simple retries. Skips entirely if the
-- player's data never loaded cleanly, which protects their real save from being
-- clobbered by this session's defaults.
--
-- `force` distinguishes the two callers:
--   * false/nil (the periodic autosave): writes ONLY if the player is dirty, and skips if a
--     save is already in flight — so unchanged data is never re-written and the same key is
--     never queued twice. This is the throttling that fixes the "request added to queue" warning.
--   * true (leave / shutdown): MUST persist the very latest state, so it ignores the dirty
--     check, but still WAITS for any in-flight autosave to finish first so the two writes don't
--     collide on the same key.
local function savePlayerData(player, force)
	if not canSave[player] then
		warn("[Save] Skipping save for " .. player.Name .. " — data did not load cleanly this session; protecting existing save.")
		return
	end

	-- COALESCE so the same key is never written by two coroutines at once.
	if force then
		-- Leave/shutdown: wait out any in-flight autosave, then write the latest below.
		while saving[player] do
			task.wait()
		end
	else
		-- Autosave pass: skip if a write is already running, or if nothing changed.
		if saving[player] or not dirty[player] then
			return
		end
	end

	saving[player] = true
	-- Clear dirty BEFORE snapshotting: any change that lands during the (yielding) write
	-- re-marks the player dirty, so the next autosave persists it too — never lost.
	dirty[player] = false

	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	-- Chi lives in its own replicated IntValue on the Player (see setupLeaderstats);
	-- read it the same way Spirit Power is read, defaulting to 0 if absent.
	local chi = player:FindFirstChild("Chi")
	-- Serialize unlockedWorlds (a SET in memory) into a plain ARRAY of indices, which
	-- DataStore stores cleanly. Always guaranteed to include the starter world.
	local unlockedArray = {}
	for idx in pairs(unlockedWorlds[player] or { [DEFAULT_WORLD] = true }) do
		table.insert(unlockedArray, idx)
	end
	local data = {
		SpiritPower = spiritPower and spiritPower.Value or 0,
		ZenLevel = zenLevel[player] or 0,
		AscendCount = ascendCount[player] or 0,
		JarTier = jarTier[player] or 0,
		HasAutoClicker = hasAutoClicker[player] == true,
		ClaimedGroupReward = claimedGroupReward[player] == true,
		LastDailyClaim = lastDailyClaim[player] or 0,
		DailyStreak = dailyStreak[player] or 0,
		Chi = chi and chi.Value or 0,
		CurrentWorld = currentWorld[player] or DEFAULT_WORLD,
		UnlockedWorlds = unlockedArray,
		AtHub = atHub[player] ~= false, -- default true (hub) for anyone never placed in a world
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
		dirty[player] = true -- write failed: stay dirty so a later autosave retries this player
	end

	saving[player] = false
end

--------------------------------------------------------------------------------
-- 2c-W3. World unlock evaluation (server-authoritative, permanent)
--------------------------------------------------------------------------------
-- The single chokepoint that decides whether any world should unlock for a player RIGHT
-- NOW. It reads the authoritative live values (AscendCount + the player's Chi IntValue) and,
-- for every world not yet unlocked, unlocks it the FIRST moment BOTH thresholds are met
-- simultaneously. Unlocking is PERMANENT: we only ever ADD to the set, never remove — so a
-- world stays unlocked through Ascends, Chi dropping back below the threshold, and rejoins.
--
-- Call this anywhere Chi or AscendCount can change (Chi gains route through grantChi; Ascend
-- through buyAscendFunc) and once at join after the saved values are seeded. When something
-- newly unlocks we persist immediately (so the unlock survives a crash before the leave-save)
-- and PUSH each new unlock to the client for a reactive menu refresh + toast. Saving in the
-- background (task.spawn) keeps this off the hot path of whatever gameplay call triggered it.
local function checkWorldUnlocks(player)
	local set = unlockedWorlds[player]
	if not set then
		return -- player not set up yet / already cleaned up
	end

	local chi = player:FindFirstChild("Chi")
	local heldChi = chi and chi.Value or 0
	local count = ascendCount[player] or 0

	local newlyUnlocked = {}
	for index in pairs(WORLDS) do
		if not set[index] then
			local reqAscend, reqChi = worldUnlockReq(index)
			if count >= reqAscend and heldChi >= reqChi then
				set[index] = true -- PERMANENT: only ever added, never removed
				table.insert(newlyUnlocked, index)
			end
		end
	end

	if #newlyUnlocked == 0 then
		return
	end

	-- Mark dirty so the periodic autosave (section 6b) persists the new unlock(s). We no longer
	-- write immediately on every unlock — that, fired alongside altar converts / leaves, was
	-- queuing repeated writes to the same key (the "request added to queue" warning). The
	-- autosave flushes within AUTOSAVE_INTERVAL, and the leave/shutdown saves are a backstop, so
	-- a new unlock survives all the normal exit paths (only a hard crash in the next ~60s loses it).
	markDirty(player)

	-- Notify the client in a stable order (sorted) so the menu/toasts are deterministic.
	table.sort(newlyUnlocked)
	for _, index in ipairs(newlyUnlocked) do
		worldUnlockedEvent:FireClient(player, index, WORLDS[index].name)
	end
end

-- SPAWN SAFETY (W3) — a player must NEVER spawn or stand inside a world they haven't unlocked.
-- This guards against leftover / invalid saved state (e.g. a currentWorld saved before gating
-- existed, or an old test save). If the player's current world isn't unlocked for them, snap
-- them back to the always-safe starter world (Tranquil Grove) in the neutral Hub. A world that
-- IS unlocked is left untouched, so a legitimate in-world respawn still returns them to it.
-- Called on join AND on every respawn (see setupLeaderstats), so the invalid state can never
-- survive to put a character on locked ground.
local function ensureSafeLocation(player)
	local idx = currentWorld[player] or DEFAULT_WORLD
	if isWorldUnlocked(player, idx) then
		return -- current world is unlocked (or it's the starter): already safe
	end
	currentWorld[player] = DEFAULT_WORLD -- starter world: always unlocked
	atHub[player] = true -- drop them in the neutral hub, never inside a locked world
	markDirty(player) -- location changed: flag for the periodic autosave
	syncWorldAttributes(player) -- republish view location for per-player visibility
	pushStats(player) -- refresh the Live Stats Panel (world changed)
end

--------------------------------------------------------------------------------
-- 2d. Player join: load data, then build leaderstats
--------------------------------------------------------------------------------
-- Roblox shows any IntValue inside a "leaderstats" folder on the leaderboard.
local function setupLeaderstats(player)
	-- SINGLE-SOURCE-OF-TRUTH GUARD — this is the Chi-desync fix. setupLeaderstats can be
	-- invoked more than once for the same player: Players.PlayerAdded AND the GetPlayers()
	-- loop below can both fire for someone who joins in that window, and a live-sync reload
	-- re-runs it too. Every run USED to unconditionally Instance.new a fresh leaderstats +
	-- Spirit Power + Chi, leaving the player with DUPLICATE currency objects — the client
	-- cached one Chi (WaitForChild) while the server's FindFirstChild resolved the other, so
	-- the HUD and spendChi drifted apart. We set this flag SYNCHRONOUSLY, before the yielding
	-- load below, so only the first invocation proceeds (no double-load, no race).
	if initialized[player] then
		return
	end
	initialized[player] = true

	-- Load first so everything is seeded from saved progress (or defaults).
	local data, loadOk = loadPlayerData(player)
	-- The load above YIELDS (GetAsync). If the player disconnected during that yield,
	-- PlayerRemoving has already run its leave-save (correctly skipped, since canSave was
	-- still nil) and cleared this player's tables + reset initialized. Resuming here would
	-- re-seed those tables and build leaderstats on a departed player — a harmless memory
	-- leak (no save is triggered, and the autosave loop only iterates current players, so
	-- their real data is never touched). Bail out instead of leaving the orphan behind.
	if not player:IsDescendantOf(Players) then
		return
	end
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
	-- Seed daily-reward state straight from the save (sanitized in loadPlayerData).
	lastDailyClaim[player] = data.LastDailyClaim
	dailyStreak[player] = data.DailyStreak
	-- Seed world state. data.CurrentWorld is a sanitized index and data.UnlockedWorlds
	-- is already a SET (built by loadPlayerData / makeDefaults), so assign directly.
	currentWorld[player] = data.CurrentWorld
	unlockedWorlds[player] = data.UnlockedWorlds
	atHub[player] = data.AtHub
	syncWorldAttributes(player) -- publish initial view location for per-player visibility
	pushStats(player) -- seed the client's Live Stats Panel with the correct loaded values

	-- FIND-OR-CREATE every replicated value (never a blind Instance.new). Combined with the
	-- guard above this guarantees exactly ONE leaderstats / Spirit Power / Chi per player,
	-- even across a live-sync reload where the instances persisted from a previous run (we
	-- reuse the existing object, so the client's cached reference stays valid). The single
	-- Chi IntValue is THE source of truth: grantChi, spendChi, the altar, the HUD and the
	-- save all read/write this exact object.
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local spiritPower = leaderstats:FindFirstChild("Spirit Power")
	if not spiritPower then
		spiritPower = Instance.new("IntValue")
		spiritPower.Name = "Spirit Power"
		spiritPower.Parent = leaderstats
	end
	-- Clamp to the (now-known) jar capacity in case saved data somehow exceeds it.
	spiritPower.Value = math.min(data.SpiritPower, getSpiritCap(player))

	-- Chi: the second, spendable currency. Its OWN replicated IntValue parented directly to
	-- the Player (deliberately NOT inside leaderstats, so it stays off the Roblox leaderboard)
	-- that the client watches read-only. Unlike Spirit Power it has no cap.
	local chi = player:FindFirstChild("Chi")
	if not chi then
		chi = Instance.new("IntValue")
		chi.Name = "Chi"
		chi.Parent = player
	end
	chi.Value = data.Chi

	-- Re-evaluate unlocks now that AscendCount + Chi are seeded from the save. For a normal
	-- returning player whose worlds are already in the saved set this is a no-op; it only acts
	-- as a safety net (e.g. a player who already meets a threshold but predates this gate).
	checkWorldUnlocks(player)

	-- SPAWN SAFETY: validate the loaded location against unlocks BEFORE placing the character,
	-- so a locked currentWorld (e.g. an old test save) snaps back to the Hub/starter world.
	ensureSafeLocation(player)

	-- Now that this player's saved location is known, place their character in the right
	-- area (hub or their world) — both for the current character and every future respawn.
	-- Connecting here (after the load) guarantees spawnCFrameFor reads valid state.
	player.CharacterAdded:Connect(function(character)
		ensureSafeLocation(player) -- re-validate on EVERY respawn (never respawn on locked ground)
		placeCharacter(player, character)
	end)
	if player.Character then
		placeCharacter(player, player.Character)
	end
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
local ASCEND_BASE_REQUIREMENT = 10000 -- Chi needed for the 1st Ascend (same number, now Chi)
local ASCEND_REQUIREMENT_SCALE = 5 -- each Ascend multiplies the requirement by this
local ASCEND_CAP_INCREASE = 2 -- each Ascend raises the Zen level cap by this much
local ASCEND_MULTIPLIER_PER = 1.5 -- permanent Spirit Power multiplier gained per Ascend

-- Permanent global multiplier from prestige: 1.5 ^ AscendCount.
local function getAscendMultiplier(player)
	return ASCEND_MULTIPLIER_PER ^ (ascendCount[player] or 0)
end

--------------------------------------------------------------------------------
-- 3-LIVE. Live stats push (server → client) for the Fusion "Live Stats Panel"
--------------------------------------------------------------------------------
-- The client panel is DISPLAY-ONLY; every value here is server-authoritative. We
-- snapshot the player's CURRENT world stats (name + per-world conversion rate +
-- per-world click multiplier, straight from the WORLDS config) plus their Ascend
-- multiplier, and FireClient it. We push on exactly the moments these can change:
--   * the client's initial request (when its panel starts listening),
--   * world travel (travelToWorld / travelToHub),
--   * Ascend (buyAscendFunc),
--   * the debug world-switch hook.
-- The client copies the snapshot into Fusion state objects, which re-render the
-- panel automatically — no polling, no manual label rewrites.
local function getStatsSnapshot(player)
	local world = getCurrentWorld(player) -- falls back to the starter world if unset
	return {
		worldName = world.name,
		conversionRate = world.conversionRate, -- e.g. 0.3 (Spirit Power → Chi)
		clickMultiplier = world.clickMultiplier, -- this world's click multiplier (config value)
		ascendMultiplier = getAscendMultiplier(player), -- 1.5 ^ AscendCount
	}
end

-- Assigns the forward-declared `pushStats` from section 2.
function pushStats(player)
	statsUpdateEvent:FireClient(player, getStatsSnapshot(player))
end

-- The client fires this (no args) once its Fusion panel is listening, to pull the
-- first snapshot. We reply by pushing the current stats straight back to it.
statsUpdateEvent.OnServerEvent:Connect(function(player)
	pushStats(player)
end)

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
		markDirty(player) -- Spirit Power changed: flag for the periodic autosave
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
		markDirty(player) -- Chi changed: flag for the periodic autosave
		-- Chi just rose: a world may now meet its (Ascend + Chi) unlock threshold (W3).
		checkWorldUnlocks(player)
	end
end

-- Deduct Chi for a purchase. Returns true and deducts ONLY if the player can fully
-- afford `amount`; otherwise returns false and changes nothing. This is the shared
-- affordability+deduction chokepoint for ALL Chi sinks (Zen, Soul Jar, Ascend).
local function spendChi(player, amount)
	amount = math.floor(amount)
	if amount <= 0 then
		return true
	end
	local chi = player:FindFirstChild("Chi")
	if chi and chi.Value >= amount then
		chi.Value -= amount
		markDirty(player) -- Chi changed: flag for the periodic autosave
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
local ZEN_BASE_PRICE = 50 -- Chi cost of the first level (0 -> 1); same number, now Chi
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

-- Purchase handler — fully validated on the server. Cost is now paid in CHI.
buyZenFunc.OnServerInvoke = function(player)
	local level = zenLevel[player] or 0

	-- Reject if already at the cap.
	if level >= getZenCap(player) then
		return getZenState(player) -- unchanged
	end

	-- Charge the Chi cost through the spendChi chokepoint, which BOTH checks the
	-- player can afford it and deducts it atomically. If they can't, nothing changes.
	local cost = getZenCost(level)
	if not spendChi(player, cost) then
		return getZenState(player) -- unchanged (not enough Chi)
	end

	-- Paid: increment level. (multiplier = 2^level, cap, scaling all unchanged.)
	zenLevel[player] = level + 1
	markDirty(player) -- Zen level changed: flag for the periodic autosave
	return getZenState(player)
end

--------------------------------------------------------------------------------
-- 3c. Ascend (prestige)
--------------------------------------------------------------------------------
-- CHI required to Ascend at a given count (same scaling as before, now measured in
-- Chi). count 0 -> 10,000, count 1 -> 50,000, count 2 -> 250,000, ...
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

-- Ascend handler — fully validated on the server. The requirement is now CHI.
buyAscendFunc.OnServerInvoke = function(player)
	local count = ascendCount[player] or 0
	local requirement = getAscendRequirement(count)

	-- Reject if the player doesn't meet the CHI requirement.
	local chi = player:FindFirstChild("Chi")
	local heldChi = chi and chi.Value or 0
	if heldChi < requirement then
		return getAscendState(player) -- unchanged (not enough Chi)
	end

	-- Perform the prestige. CHI is the meaningful reset now:
	--  * empty ALL Chi to 0 — routed through the spendChi chokepoint by spending the
	--    full held balance (held -> 0)
	--  * reset Zen level to 0
	--  * increment Ascend count (this still raises the Zen cap via getZenCap and
	--    strengthens all future SPIRIT POWER gains via getAscendMultiplier — unchanged)
	spendChi(player, heldChi)
	zenLevel[player] = 0
	ascendCount[player] = count + 1
	markDirty(player) -- Ascend count / Zen reset: flag for the periodic autosave

	-- Spirit Power is NO LONGER the prestige currency (it's just conversion fuel now),
	-- but we still zero the live bar for a clean slate. JarTier is intentionally NOT
	-- touched — the Soul Jar persists across Ascends.
	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	if spiritPower then
		spiritPower.Value = 0
	end

	pushStats(player) -- refresh the Live Stats Panel (Ascend multiplier changed)
	-- AscendCount just rose: re-evaluate unlocks. (Ascend empties Chi to 0, so this won't
	-- unlock anything on its own — Chi must climb back up via the altar — but we check on
	-- every AscendCount change for correctness, per the W3 gate's "whenever it changes" rule.)
	checkWorldUnlocks(player)
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

-- Upgrade handler — fully validated on the server. Cost is now paid in CHI. The jar
-- still CAPS Spirit Power (getSpiritCap) exactly as before — only the upgrade cost's
-- currency changed.
buySoulJarFunc.OnServerInvoke = function(player)
	local tier = jarTier[player] or 0
	local nextTier = SOUL_JAR_TIERS[tier + 2]

	-- Reject if already at the top tier.
	if not nextTier then
		return getSoulJarState(player) -- unchanged
	end

	-- Charge the Chi cost through the spendChi chokepoint (checks affordability AND
	-- deducts atomically). If the player can't afford it, nothing changes.
	if not spendChi(player, nextTier.upgradeCost) then
		return getSoulJarState(player) -- unchanged (not enough Chi)
	end

	-- Paid: advance the tier.
	jarTier[player] = tier + 1
	markDirty(player) -- Soul Jar tier changed: flag for the periodic autosave
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

	markDirty(player) -- claim flags / auto-clicker / zen changed: flag for the periodic autosave
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
-- 3f. Meditation Altar — convert Spirit Power into Chi (server-authoritative)
--------------------------------------------------------------------------------
-- "Convert ALL at once": reads the player's Spirit Power, floors SP * conversionRate
-- into Chi, grants that Chi through the Slice-1 grantChi chokepoint, then empties the
-- jar. The conversion rate is now PER-WORLD — it's looked up from the player's CURRENT
-- world in the WORLDS config (section 0c), so converting in a higher world yields more
-- Chi for the same Spirit Power. The graceful case (chiGained <= 0) — which happens at
-- 0 Spirit Power OR when the amount is so small the rate floors to 0 — changes NOTHING
-- and tells the client there's nothing to convert. Returns { ok, converted, message }.
convertSpiritToChiFunc.OnServerInvoke = function(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	if not spiritPower then
		return { ok = false, converted = 0, message = "Meditate to gather more Spirit Power first!" }
	end

	local conversionRate = getCurrentWorld(player).conversionRate
	local chiGained = math.floor(spiritPower.Value * conversionRate)
	if chiGained <= 0 then
		-- Nothing worth converting: leave Spirit Power AND Chi untouched.
		return { ok = false, converted = 0, message = "Meditate to gather more Spirit Power first!" }
	end

	-- Grant first (through the single Chi chokepoint), then empty the jar. Both writes
	-- are to already-persisted live values, so no extra save wiring is needed.
	grantChi(player, chiGained)
	spiritPower.Value = 0

	return { ok = true, converted = chiGained, message = "+" .. chiGained .. " Chi!" }
end

--------------------------------------------------------------------------------
-- 3g. DAILY LOGIN REWARDS (server-authoritative, exploit-resistant)
--------------------------------------------------------------------------------
-- A streak of escalating Chi rewards, one claim per ~24h. ALL timing uses SERVER os.time(),
-- never the client's clock, so a player can't change their device time to claim early.
--
-- ░░ REWARD TABLE — EDIT FREELY ░░ One row per streak day, in order. `chi` is the Chi granted
-- that day; `boost = true` marks a MILESTONE day that ALSO grants a (future) boost. The boost
-- system doesn't exist yet, so a boost day currently just grants its Chi and LOGS the boost as
-- a placeholder (see the claim handler's TODO). Add/extend days by adding rows; the streak
-- LOOPS back to Day 1 after the last row (a repeating weekly cycle), so the table can be any
-- length. Tune these numbers however you like.
local DAILY_REWARDS = {
	{ chi = 500 }, -- Day 1
	{ chi = 1000 }, -- Day 2
	{ chi = 2000 }, -- Day 3
	{ chi = 3500 }, -- Day 4
	{ chi = 6000 }, -- Day 5
	{ chi = 10000 }, -- Day 6
	{ chi = 20000, boost = true }, -- Day 7 — MILESTONE: Chi + placeholder boost (not yet built)
}

-- Claim cadence. A claim is allowed once this much SERVER time has elapsed since the last one.
-- "Pause on miss" (gentle): the streak NEVER resets. If a player is away for days, the streak
-- simply doesn't advance while they're gone; their next valid claim resumes at the next day.
-- The ~48h "miss" idea from the design needs no separate gate here precisely because we never
-- reset — being away >48h is indistinguishable from being away 25h: both just advance by 1.
local DAILY_CLAIM_COOLDOWN = 24 * 60 * 60 -- 24h minimum between claims (in seconds)

-- The day index a player would claim NEXT, derived from their streak and LOOPING over the
-- table. streak 0 → Day 1; streak 7 (table length) → wraps to Day 1 again; streak 3 → Day 4.
local function nextDailyDay(player)
	local streak = dailyStreak[player] or 0
	return (streak % #DAILY_REWARDS) + 1
end

-- Whether a claim is allowed right now, plus seconds remaining until it is (0 if claimable).
-- A player who has never claimed (timestamp 0) can always claim immediately.
local function dailyClaimStatus(player)
	local last = lastDailyClaim[player] or 0
	if last == 0 then
		return true, 0
	end
	local elapsed = os.time() - last -- SERVER time only
	if elapsed >= DAILY_CLAIM_COOLDOWN then
		return true, 0
	end
	return false, DAILY_CLAIM_COOLDOWN - elapsed
end

-- The full authoritative snapshot the client renders: the reward table (for display), the
-- player's streak, which day is claimable next, and the live cooldown. The client trusts this
-- entirely — it never decides claimability itself.
local function getDailyState(player)
	local canClaim, remaining = dailyClaimStatus(player)
	local days = {}
	for i, row in ipairs(DAILY_REWARDS) do
		days[i] = { day = i, chi = row.chi, boost = row.boost == true }
	end
	return {
		days = days, -- the whole table, in order
		streak = dailyStreak[player] or 0, -- streak day claimed up to (0 = none)
		nextDay = nextDailyDay(player), -- the day a claim would grant now
		canClaim = canClaim, -- server's authoritative gate
		secondsUntilNext = remaining, -- 0 when claimable; else cooldown left
		cooldown = DAILY_CLAIM_COOLDOWN, -- so the client can show a sensible countdown
	}
end

getDailyRewardStateFunc.OnServerInvoke = function(player)
	return getDailyState(player)
end

-- THE claim chokepoint — fully validated on the server. Rejects early / double claims using
-- server time, grants the Chi via the existing grantChi chokepoint, advances + persists the
-- streak, and returns the new state either way.
claimDailyRewardFunc.OnServerInvoke = function(player)
	-- 1. Validate the cooldown against SERVER time. This single check rejects double-claims and
	--    any client that tries to claim early (changing the device clock has no effect here).
	local canClaim, remaining = dailyClaimStatus(player)
	if not canClaim then
		return {
			ok = false,
			message = "Already claimed — come back later for your next reward!",
			secondsUntilNext = remaining,
			state = getDailyState(player),
		}
	end

	-- 2. Resolve the reward for the day being claimed (loops over the table; never resets).
	local day = nextDailyDay(player)
	local reward = DAILY_REWARDS[day]

	-- 3. Grant the Chi portion through the single Chi chokepoint (which also runs the W3 world
	--    unlock check, keeps the bank uncapped, etc. — consistent with every other Chi source).
	grantChi(player, reward.chi)

	-- 4. MILESTONE boost is a PLACEHOLDER — the boost system doesn't exist yet. For now we only
	--    log/mark it and still grant the Chi above. TODO(boost): when the boost system is built,
	--    grant the real boost here (e.g. a timed Chi/click multiplier) instead of just logging.
	local boostGranted = false
	if reward.boost then
		boostGranted = true
		print(string.format(
			"[DailyReward] %s claimed milestone Day %d — BOOST placeholder (Chi granted; boost system TODO).",
			player.Name, day
		))
	end

	-- 5. Commit the authoritative state (advance the streak, stamp the claim time) and mark dirty
	--    so the periodic autosave (section 6b) persists it. We don't write immediately anymore —
	--    a claim followed quickly by a leave was queuing two writes to the same key. The streak is
	--    captured by the next autosave and by the guaranteed leave/shutdown save either way.
	dailyStreak[player] = day
	lastDailyClaim[player] = os.time()
	markDirty(player)

	return {
		ok = true,
		message = "Day " .. day .. ": +" .. reward.chi .. " Chi!" .. (boostGranted and "  ✦ Boost!" or ""),
		day = day,
		chi = reward.chi,
		boost = boostGranted,
		state = getDailyState(player),
	}
end

--------------------------------------------------------------------------------
-- 3f-DEBUG. STUDIO-ONLY testing tools (command-bar helpers)
--------------------------------------------------------------------------------
-- A clean, reliable set of debug helpers for fast testing from the Studio command bar.
--
-- SAFETY: the ENTIRE block is wrapped in `if RunService:IsStudio()`. In a published /
-- live server IsStudio() is false, so NONE of these `_G.DEBUG_*` functions are ever
-- registered — `_G.DEBUG_setChi` etc. are simply nil there, so a player could never
-- invoke them even if they found a way to run server Lua. (Clients also have their OWN
-- separate `_G`, so they never see these regardless.)
--
-- HOW TO RUN (read this if they've "never worked"):
--   1. Press PLAY (F5) to start a playtest so the server is actually running.
--   2. In the command bar, set the context dropdown to **Server** (NOT Client). `_G` is
--      per-VM: these live in the SERVER's `_G`, so a Client-context command bar sees nil
--      (the classic "attempt to call a nil value" — the #1 reason they failed before).
--   3. Call by USERNAME (string), e.g.:  _G.DEBUG_setChi("tanxy_z", 5000)
--   Run `_G.DEBUG_help()` for the full list.
--
-- Every helper resolves the player by name, validates/clamps inputs, routes through the
-- real chokepoints where it matters (grantChi/spendChi fire world-unlock checks), and
-- markDirty()s so the change actually persists. Where a value is set DIRECTLY (Spirit
-- Power, Ascend count, Jar tier), that's intentional for testing and noted inline.
if RunService:IsStudio() then
	-- Resolve a debug arg (a username string OR a Player instance) to a Player, or nil.
	local function resolvePlayer(arg)
		if typeof(arg) == "Instance" and arg:IsA("Player") then
			return arg
		end
		if type(arg) == "string" then
			local p = Players:FindFirstChild(arg)
			if p and p:IsA("Player") then
				return p
			end
			local names = {}
			for _, pl in ipairs(Players:GetPlayers()) do
				table.insert(names, pl.Name)
			end
			warn(string.format("[DEBUG] No player named %q. In game now: %s", arg, table.concat(names, ", ")))
			return nil
		end
		warn("[DEBUG] First arg must be a username STRING (e.g. \"tanxy_z\") or a Player instance.")
		return nil
	end

	-- Set Chi to an exact value. Routes the delta through grantChi/spendChi so world-unlock
	-- checks still fire (grantChi calls checkWorldUnlocks). Clamped to >= 0.
	_G.DEBUG_setChi = function(nameOrPlayer, value)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		value = math.max(0, math.floor(tonumber(value) or 0))
		local chi = player:FindFirstChild("Chi")
		if not chi then
			warn("[DEBUG_setChi] " .. player.Name .. " has no Chi value yet (data still loading?).")
			return
		end
		if value > chi.Value then
			grantChi(player, value - chi.Value)
		elseif value < chi.Value then
			spendChi(player, chi.Value - value)
		end
		print(string.format("[DEBUG_setChi] %s Chi = %d", player.Name, chi.Value))
	end

	-- Set Spirit Power to an exact value. Set DIRECTLY (bypasses the Ascend multiplier on
	-- purpose so you get exactly what you asked for), but still clamped to the Soul Jar cap.
	_G.DEBUG_setSpiritPower = function(nameOrPlayer, value)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		local leaderstats = player:FindFirstChild("leaderstats")
		local sp = leaderstats and leaderstats:FindFirstChild("Spirit Power")
		if not sp then
			warn("[DEBUG_setSpiritPower] " .. player.Name .. " has no Spirit Power yet (data still loading?).")
			return
		end
		value = math.max(0, math.floor(tonumber(value) or 0))
		local cap = getSpiritCap(player)
		sp.Value = math.min(value, cap)
		markDirty(player)
		print(string.format("[DEBUG_setSpiritPower] %s Spirit Power = %d (jar cap %d)", player.Name, sp.Value, cap))
	end

	-- Set Ascension count directly. Clamped to >= 0. NOTE: unlike a real Ascend this does NOT
	-- reset Zen/Chi/Spirit Power — it only sets the count (that's what you want for testing the
	-- multiplier / Zen cap / world requirements). Refreshes the stats panel + world unlocks.
	_G.DEBUG_setAscends = function(nameOrPlayer, count)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		count = math.max(0, math.floor(tonumber(count) or 0))
		ascendCount[player] = count
		markDirty(player)
		pushStats(player) -- Ascend multiplier changed
		checkWorldUnlocks(player) -- Ascend threshold may now unlock worlds
		print(string.format("[DEBUG_setAscends] %s AscendCount = %d (mult x%.3f)", player.Name, count, getAscendMultiplier(player)))
	end

	-- Set Soul Jar tier directly (0 = Clay .. #tiers-1). Clamped to a valid tier. Re-clamps
	-- Spirit Power to the new cap if you lowered the tier below the current holdings.
	_G.DEBUG_setJarTier = function(nameOrPlayer, tier)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		tier = math.max(0, math.min(#SOUL_JAR_TIERS - 1, math.floor(tonumber(tier) or 0)))
		jarTier[player] = tier
		local leaderstats = player:FindFirstChild("leaderstats")
		local sp = leaderstats and leaderstats:FindFirstChild("Spirit Power")
		if sp then
			sp.Value = math.min(sp.Value, getSpiritCap(player)) -- lowering tier can shrink the cap
		end
		markDirty(player)
		print(string.format("[DEBUG_setJarTier] %s JarTier = %d (%s, cap %d)", player.Name, tier, SOUL_JAR_TIERS[tier + 1].name, getSpiritCap(player)))
	end

	-- Set Zen level directly. Clamped to [0, current Zen cap] (the cap rises with Ascends).
	_G.DEBUG_setZen = function(nameOrPlayer, level)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		level = math.max(0, math.min(getZenCap(player), math.floor(tonumber(level) or 0)))
		zenLevel[player] = level
		markDirty(player)
		print(string.format("[DEBUG_setZen] %s ZenLevel = %d (x%d click)", player.Name, level, getZenMultiplier(level)))
	end

	-- Unlock a single world for a player (permanent). Pushes the unlock event so an open
	-- Worlds menu refreshes + toasts, exactly like a real unlock.
	_G.DEBUG_unlockWorld = function(nameOrPlayer, index)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		index = tonumber(index)
		if WORLDS[index] == nil then
			warn("[DEBUG_unlockWorld] No world #" .. tostring(index) .. ". Valid: 1.." .. tostring(#WORLDS))
			return
		end
		local set = unlockedWorlds[player] or { [DEFAULT_WORLD] = true }
		unlockedWorlds[player] = set
		set[index] = true
		markDirty(player)
		worldUnlockedEvent:FireClient(player, index, WORLDS[index].name)
		print(string.format("[DEBUG_unlockWorld] %s unlocked world %d (%s)", player.Name, index, WORLDS[index].name))
	end

	-- Unlock ALL configured worlds for a player at once.
	_G.DEBUG_unlockAllWorlds = function(nameOrPlayer)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		local set = unlockedWorlds[player] or { [DEFAULT_WORLD] = true }
		unlockedWorlds[player] = set
		for index in pairs(WORLDS) do
			if not set[index] then
				set[index] = true
				worldUnlockedEvent:FireClient(player, index, WORLDS[index].name)
			end
		end
		markDirty(player)
		print(string.format("[DEBUG_unlockAllWorlds] %s now owns all %d worlds", player.Name, #WORLDS))
	end

	-- Move a player into a world (and unlock it), to verify per-world altar/click rates.
	_G.DEBUG_setWorld = function(nameOrPlayer, index)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		index = tonumber(index)
		if WORLDS[index] == nil then
			warn("[DEBUG_setWorld] No world #" .. tostring(index) .. ". Valid: 1.." .. tostring(#WORLDS))
			return
		end
		currentWorld[player] = index
		local set = unlockedWorlds[player] or { [DEFAULT_WORLD] = true }
		unlockedWorlds[player] = set
		set[index] = true -- unlock it too, so state stays consistent
		atHub[player] = false -- actually stand in the world (not the hub) so rates apply
		markDirty(player)
		syncWorldAttributes(player)
		pushStats(player)
		if player.Character then
			placeCharacter(player, player.Character) -- teleport to the world now
		end
		print(string.format("[DEBUG_setWorld] %s -> world %d (%s), conversionRate = %s", player.Name, index, WORLDS[index].name, tostring(WORLDS[index].conversionRate)))
	end

	-- Fast-test the daily-reward TIME logic without waiting: BACKDATES the last-claim timestamp
	-- by `hours` (default 24). All claim logic uses os.time() deltas, so this is indistinguishable
	-- from real elapsed time. 24h → next claim available; 50h → simulate a >48h "miss".
	_G.DEBUG_dailyAdvance = function(nameOrPlayer, hours)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		hours = tonumber(hours) or 24
		local base = lastDailyClaim[player]
		if base == nil or base == 0 then
			base = os.time() -- never-claimed players are already claimable; backdate from now
		end
		lastDailyClaim[player] = base - math.floor(hours * 3600)
		markDirty(player)
		print(string.format("[DEBUG_dailyAdvance] %s: simulated %s hours (streak day %d, claimable now = %s)", player.Name, tostring(hours), dailyStreak[player] or 0, tostring((select(1, dailyClaimStatus(player))))))
	end

	-- Force an immediate save (respects canSave). Handy to confirm a change persisted before
	-- you stop the playtest.
	_G.DEBUG_save = function(nameOrPlayer)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		savePlayerData(player, true)
		print("[DEBUG_save] forced save requested for " .. player.Name)
	end

	-- Print a player's full current progression state to the output.
	_G.DEBUG_dump = function(nameOrPlayer)
		local player = resolvePlayer(nameOrPlayer)
		if not player then return end
		local leaderstats = player:FindFirstChild("leaderstats")
		local sp = leaderstats and leaderstats:FindFirstChild("Spirit Power")
		local chi = player:FindFirstChild("Chi")
		local unlocked = {}
		for idx in pairs(unlockedWorlds[player] or {}) do
			table.insert(unlocked, idx)
		end
		table.sort(unlocked)
		print(string.format(
			"[DEBUG_dump] %s | Chi=%d  SpiritPower=%d/%d  Ascends=%d  JarTier=%d(%s)  Zen=%d  World=%d atHub=%s  Unlocked={%s}  DailyStreak=%d canSave=%s",
			player.Name,
			chi and chi.Value or -1,
			sp and sp.Value or -1, getSpiritCap(player),
			ascendCount[player] or 0,
			jarTier[player] or 0, SOUL_JAR_TIERS[(jarTier[player] or 0) + 1].name,
			zenLevel[player] or 0,
			currentWorld[player] or DEFAULT_WORLD, tostring(atHub[player]),
			table.concat(unlocked, ","),
			dailyStreak[player] or 0,
			tostring(canSave[player])
		))
	end

	-- List every available debug command.
	_G.DEBUG_help = function()
		print([[
[DEBUG] Studio-only testing commands (run command bar in SERVER context, call by username):
  _G.DEBUG_setChi("name", 5000)
  _G.DEBUG_setSpiritPower("name", 1000)
  _G.DEBUG_setAscends("name", 3)
  _G.DEBUG_setJarTier("name", 4)          -- 0=Clay .. up to top tier
  _G.DEBUG_setZen("name", 5)
  _G.DEBUG_unlockWorld("name", 2)
  _G.DEBUG_unlockAllWorlds("name")
  _G.DEBUG_setWorld("name", 2)            -- move into + unlock a world
  _G.DEBUG_dailyAdvance("name", 24)       -- backdate daily-claim timer by N hours
  _G.DEBUG_save("name")                   -- force an immediate save
  _G.DEBUG_dump("name")                   -- print full state
]])
	end

	print("[DEBUG] Studio testing commands registered. Run _G.DEBUG_help() in the SERVER command bar.")
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
-- Per-world click bonus (W2a). In a world, click-earn is scaled by that world's
-- clickMultiplier; in the hub it's 1x (the hub is neutral — no earning bonus). This
-- stacks on top of Zen here, and grantSpiritPower then layers the Ascend multiplier
-- and the Soul Jar soft cap. (jarCapMultiplier is intentionally NOT applied yet — W2b+.)
local function getWorldClickMultiplier(player)
	if atHub[player] ~= false then
		return 1 -- hub (or unset) = neutral 1x
	end
	local world = WORLDS[currentWorld[player] or DEFAULT_WORLD]
	return (world and world.clickMultiplier) or 1
end

local function applyClick(player, baseAmount)
	local zen = getZenMultiplier(zenLevel[player] or 0)
	local world = getWorldClickMultiplier(player)
	grantSpiritPower(player, (baseAmount or CLICK_BASE_AMOUNT) * zen * world)
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

-- MEDITATION ALTAR (jade/green) — converts Spirit Power into Chi. Placed across the
-- plaza on the opposite (-Z) side from the row of three pads so nothing overlaps, and
-- given a distinct jade glow to read as the special "sell" station. Touching it tells
-- the client to request a conversion (all the conversion logic lives in section 3f).
createMonumentPad({
	name = "MeditationAltarPad",
	position = Vector3.new(0, 0, -24),
	discColor = Color3.fromRGB(60, 220, 130),
	glowColor = Color3.fromRGB(95, 240, 155),
	pedestalColor = Color3.fromRGB(26, 58, 42),
	title = "MEDITATION ALTAR",
	subtitle = "Convert Spirit Power into Chi",
	titleColor = Color3.fromRGB(175, 255, 210),
	strokeColor = Color3.fromRGB(18, 78, 48),
	onTouched = function(plr)
		altarTouchedEvent:FireClient(plr)
	end,
})

--------------------------------------------------------------------------------
-- 5b. Hub spawn + travel portals + the three earning-area worlds (Slice W2a)
--------------------------------------------------------------------------------
-- Travel is SERVER-AUTHORITATIVE: the server sets currentWorld/atHub and teleports the
-- character. Both portals (walked into) and the HUD "Worlds" menu funnel through the
-- same travelToWorld/travelToHub below. travelToWorld enforces the W3 unlock GATE (it
-- refuses locked worlds and returns false), so both paths are gated by one check.

-- Brief per-player cooldown so arriving on top of a portal can't instantly re-trigger it.
local travelDebounce = {} -- [player] = true for a moment after any travel
local function canTravel(player)
	if travelDebounce[player] then
		return false
	end
	travelDebounce[player] = true
	task.delay(1.2, function()
		travelDebounce[player] = nil
	end)
	return true
end

-- Move a player INTO a world: set state (server owns it) then teleport their body.
-- W3 GATE: this is server-authoritative and the SINGLE place travel actually happens, so the
-- unlock check here protects BOTH paths (menu request + physical portal) at once — even if a
-- client bypasses the menu/portal UI, an unlocked-world check it can't satisfy stops it here.
-- Returns true on success, false if the world is invalid or still LOCKED for this player.
local function travelToWorld(player, index)
	if not WORLDS[index] then
		return false
	end
	if not isWorldUnlocked(player, index) then
		return false -- locked: server refuses (the caller surfaces the requirement to the client)
	end
	currentWorld[player] = index
	atHub[player] = false
	markDirty(player) -- location changed: flag for the periodic autosave
	syncWorldAttributes(player) -- tell every client this player is now in world `index`
	pushStats(player) -- refresh the Live Stats Panel (rate/click multiplier changed)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = worldSpawnCFrame(index)
	end
	return true
end

-- Tell a client WHY a travel request to a locked world was refused, sending the requirement
-- numbers so the client can render the message ("Requires 1 Ascend + 5,000 Chi"). Shared by
-- the menu-request path and the physical-portal path.
local function notifyTravelBlocked(player, index)
	local world = WORLDS[index]
	if not world then
		return
	end
	local reqAscend, reqChi = worldUnlockReq(index)
	travelBlockedEvent:FireClient(player, index, world.name, reqAscend, reqChi)
end

-- Move a player back to the neutral hub. currentWorld is intentionally left as-is, so
-- the altar keeps converting at the rate of the world they were last earning in.
local function travelToHub(player)
	atHub[player] = true
	markDirty(player) -- location changed: flag for the periodic autosave
	syncWorldAttributes(player) -- tell every client this player is back in the hub
	pushStats(player) -- refresh the Live Stats Panel (keeps it in sync after travel)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(HUB_SPAWN)
	end
end

-- A walk-through portal: a glowing translucent slab with a floating label.
local function createPortal(opts)
	-- opts: name, position (Vector3 center), color, label, onEnter (function(player)).
	local part = Instance.new("Part")
	part.Name = opts.name
	part.Size = Vector3.new(10, 12, 2)
	part.Position = opts.position
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = opts.color
	part.Transparency = 0.35
	-- Parent defaults to Workspace (hub portals) but a world's RETURN portal passes the
	-- world Model so it hides/shows together with that world for per-player visibility.
	part.Parent = opts.parent or Workspace

	local light = Instance.new("PointLight")
	light.Color = opts.color
	light.Brightness = 4
	light.Range = 16
	light.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(9, 2.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = part
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = opts.label
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard

	part.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if plr and canTravel(plr) then
			opts.onEnter(plr)
		end
	end)
	return part
end

-- ███ PLACEHOLDER — FUTURE BOSS ARENA (no combat yet) ████████████████████████████
-- Reserves a clearly-marked, EMPTY circular zone inside a world for a future combat
-- phase. It is intentionally PURELY decorative: a raised platform, a glowing rim, a
-- ring of roped-off posts, and a "Boss Arena (Coming Soon)" sign. There is NO boss, NO
-- health, NO damage, NO combat logic of any kind here — the only purpose is to lock in
-- the physical space/layout now so a boss system can be dropped in later WITHOUT having
-- to relay out the worlds. The interior is left empty on purpose (room for the boss).
-- `arenaCenter` sits off to the +X side, away from the central earning spot, the world
-- sign, and the return portal, so it never interferes with the earning area.
local function createBossArenaPlaceholder(model, center)
	local arenaCenter = center + Vector3.new(58, 0, 0) -- +X side, clear of earning/spawn
	local ARENA_RADIUS = 20

	-- Raised circular platform — visually distinct (dark stone) from the world floor.
	local platform = Instance.new("Part")
	platform.Name = "BossArenaPlaceholder" -- future combat phase hooks onto this
	platform.Shape = Enum.PartType.Cylinder
	platform.Anchored = true
	platform.Size = Vector3.new(1, ARENA_RADIUS * 2, ARENA_RADIUS * 2) -- 1 = thickness
	platform.Orientation = Vector3.new(0, 0, 90) -- lay the round face up
	platform.Position = arenaCenter + Vector3.new(0, 0.5, 0)
	platform.Material = Enum.Material.Slate
	platform.Color = Color3.fromRGB(70, 64, 78)
	platform.Parent = model

	-- Glowing amber rim just under the platform edge — the "reserved zone" marking.
	local rim = Instance.new("Part")
	rim.Name = "BossArenaRim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Anchored = true
	rim.Size = Vector3.new(0.6, ARENA_RADIUS * 2 + 6, ARENA_RADIUS * 2 + 6)
	rim.Orientation = Vector3.new(0, 0, 90)
	rim.Position = arenaCenter + Vector3.new(0, 0.3, 0)
	rim.Material = Enum.Material.Neon
	rim.Color = Color3.fromRGB(255, 170, 60)
	rim.Parent = model

	-- Ring of short "roped-off" posts around the perimeter (decorative only).
	for i = 0, 7 do
		local ang = math.rad(i * 45)
		local post = Instance.new("Part")
		post.Name = "BossArenaPost"
		post.Anchored = true
		post.Size = Vector3.new(1.5, 5, 1.5)
		post.Position = Vector3.new(
			arenaCenter.X + math.cos(ang) * (ARENA_RADIUS + 2),
			2.5,
			arenaCenter.Z + math.sin(ang) * (ARENA_RADIUS + 2)
		)
		post.Material = Enum.Material.Metal
		post.Color = Color3.fromRGB(95, 90, 105)
		post.Parent = model
	end

	-- "Boss Arena (Coming Soon)" sign on a post at the near edge (keeps the centre empty).
	local signPost = Instance.new("Part")
	signPost.Name = "BossArenaSignPost"
	signPost.Anchored = true
	signPost.Size = Vector3.new(1.5, 16, 1.5)
	signPost.Position = Vector3.new(arenaCenter.X, 8, arenaCenter.Z - (ARENA_RADIUS + 2))
	signPost.Material = Enum.Material.Metal
	signPost.Color = Color3.fromRGB(95, 90, 105)
	signPost.Parent = model

	local sign = Instance.new("BillboardGui")
	sign.Name = "BossArenaSign"
	sign.Size = UDim2.fromScale(16, 5)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	sign.AlwaysOnTop = true
	sign.Adornee = signPost
	sign.Parent = signPost

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "Boss Arena\n(Coming Soon)"
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 205, 130)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.TextStrokeColor3 = Color3.fromRGB(30, 20, 10)
	signLabel.Parent = sign
end
-- ████████████████████████████████████████████████████████████████████████████████

-- Tall INVISIBLE collision barrier around a square area so players cannot walk OR jump
-- off the platform into the void. Used for every world AND the hub. Height is far above
-- the default ~7-stud jump, and the walls sit at the platform EDGE so the whole interior
-- (including the portals, which are placed well inside each area) stays reachable.
local BARRIER_HEIGHT = 30 -- way above jump height; unjumpable
local BARRIER_THICKNESS = 2
local function createBarrier(parent, groundCenter, span)
	local half = span / 2
	local yMid = BARRIER_HEIGHT / 2 -- base sits on the ground (y = 0 of the platform top)
	-- z-walls overhang by the thickness on each end so the corners are sealed.
	local defs = {
		{ Vector3.new(span + BARRIER_THICKNESS * 2, BARRIER_HEIGHT, BARRIER_THICKNESS), Vector3.new(0, yMid, half) },
		{ Vector3.new(span + BARRIER_THICKNESS * 2, BARRIER_HEIGHT, BARRIER_THICKNESS), Vector3.new(0, yMid, -half) },
		{ Vector3.new(BARRIER_THICKNESS, BARRIER_HEIGHT, span), Vector3.new(half, yMid, 0) },
		{ Vector3.new(BARRIER_THICKNESS, BARRIER_HEIGHT, span), Vector3.new(-half, yMid, 0) },
	}
	for _, def in ipairs(defs) do
		local wall = Instance.new("Part")
		wall.Name = "EdgeBarrier"
		wall.Anchored = true
		wall.CanCollide = true -- the whole point: blocks players
		wall.Transparency = 1 -- invisible
		wall.CastShadow = false
		wall.Size = def[1]
		wall.Position = groundCenter + def[2]
		wall.Parent = parent
	end
end

-- Build one themed earning-area world: floor, a low decorative perimeter rim, a tall
-- invisible edge barrier (so you can't walk/jump off), a central accent, a big floating
-- name sign, and a return portal.
local function createWorldArea(opts)
	-- opts: index, name, floorColor, floorMaterial, accentColor, signColor, mist (bool).
	local center = WORLD_CENTERS[opts.index]
	local half = WORLD_FLOOR_SIZE / 2
	local model = Instance.new("Model")
	model.Name = "World" .. opts.index

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(WORLD_FLOOR_SIZE, 2, WORLD_FLOOR_SIZE)
	floor.Position = center + Vector3.new(0, -1, 0) -- top surface at y = 0
	floor.Material = opts.floorMaterial
	floor.Color = opts.floorColor
	floor.Parent = model

	-- Low, semi-transparent perimeter rim — purely a VISUAL edge cue.
	local WALL_H = 7
	local wallDefs = {
		{ Vector3.new(WORLD_FLOOR_SIZE, WALL_H, 2), Vector3.new(0, WALL_H / 2, half) },
		{ Vector3.new(WORLD_FLOOR_SIZE, WALL_H, 2), Vector3.new(0, WALL_H / 2, -half) },
		{ Vector3.new(2, WALL_H, WORLD_FLOOR_SIZE), Vector3.new(half, WALL_H / 2, 0) },
		{ Vector3.new(2, WALL_H, WORLD_FLOOR_SIZE), Vector3.new(-half, WALL_H / 2, 0) },
	}
	for _, def in ipairs(wallDefs) do
		local wall = Instance.new("Part")
		wall.Anchored = true
		wall.Size = def[1]
		wall.Position = center + def[2]
		wall.Material = Enum.Material.SmoothPlastic
		wall.Color = opts.accentColor
		wall.Transparency = 0.5
		wall.Parent = model
	end

	-- The ACTUAL containment: a tall invisible barrier at the platform edge so players
	-- can't walk or jump off into the void. The return portal sits well inside (z+60 of a
	-- ±90 floor), so it stays reachable. Parented to the model so it travels with the world.
	createBarrier(model, center, WORLD_FLOOR_SIZE)

	-- Central glowing accent disc — instant visual identity for the world.
	local accent = Instance.new("Part")
	accent.Name = "Accent"
	accent.Shape = Enum.PartType.Cylinder
	accent.Anchored = true
	accent.Size = Vector3.new(0.6, 44, 44)
	accent.Orientation = Vector3.new(0, 0, 90)
	accent.Position = center + Vector3.new(0, 0.3, 0)
	accent.Material = Enum.Material.Neon
	accent.Color = opts.accentColor
	accent.Parent = model

	-- Optional drifting "mist" layer (Whispering Highlands).
	if opts.mist then
		local mist = Instance.new("Part")
		mist.Name = "Mist"
		mist.Anchored = true
		mist.CanCollide = false
		mist.Size = Vector3.new(WORLD_FLOOR_SIZE, 0.4, WORLD_FLOOR_SIZE)
		mist.Position = center + Vector3.new(0, 6, 0)
		mist.Material = Enum.Material.ForceField
		mist.Color = Color3.fromRGB(210, 225, 240)
		mist.Transparency = 0.4
		mist.Parent = model
	end

	-- Big floating name sign on a post so it's obvious which world you're standing in.
	local post = Instance.new("Part")
	post.Name = "SignPost"
	post.Anchored = true
	post.Size = Vector3.new(2, 26, 2)
	post.Position = center + Vector3.new(0, 13, -30)
	post.Material = Enum.Material.WoodPlanks
	post.Color = opts.accentColor
	post.Parent = model

	local sign = Instance.new("BillboardGui")
	sign.Name = "WorldSign"
	sign.Size = UDim2.fromScale(24, 6)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 16, 0)
	sign.AlwaysOnTop = true
	sign.Adornee = post
	sign.Parent = post

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = opts.name
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.TextColor3 = opts.signColor
	signLabel.TextStrokeTransparency = 0.3
	signLabel.TextStrokeColor3 = Color3.fromRGB(15, 15, 25)
	signLabel.Parent = sign

	-- Reserve the (empty) future boss-arena space inside this world. Placeholder only.
	createBossArenaPlaceholder(model, center)

	model.Parent = Workspace

	-- Return-to-hub portal sitting inside this world (offset from the spawn point).
	-- Parented INTO the world model so it hides/shows with the world (per-player W2b).
	createPortal({
		name = "ReturnPortal" .. opts.index,
		position = center + RETURN_PORTAL_OFFSET,
		color = Color3.fromRGB(255, 225, 150),
		label = "↩ Return to Hub",
		onEnter = travelToHub,
		parent = model,
	})
end

-- The three worlds. Names/order mirror the WORLDS config; themes make each distinct.
createWorldArea({
	index = 1,
	name = "Tranquil Grove",
	floorColor = Color3.fromRGB(86, 160, 72),
	floorMaterial = Enum.Material.Grass,
	accentColor = Color3.fromRGB(55, 120, 55),
	signColor = Color3.fromRGB(190, 255, 180),
})
createWorldArea({
	index = 2,
	name = "Whispering Highlands",
	floorColor = Color3.fromRGB(120, 140, 165),
	floorMaterial = Enum.Material.Slate,
	accentColor = Color3.fromRGB(90, 115, 150),
	signColor = Color3.fromRGB(205, 225, 245),
	mist = true,
})
createWorldArea({
	index = 3,
	name = "Celestial Summit",
	floorColor = Color3.fromRGB(96, 74, 150),
	floorMaterial = Enum.Material.Marble,
	accentColor = Color3.fromRGB(255, 205, 90),
	signColor = Color3.fromRGB(255, 235, 175),
})

-- Hub SpawnLocation so every fresh character first appears in the neutral hub. (On
-- rejoin, setupLeaderstats teleports anyone whose saved location is a world.)
local hubSpawn = Instance.new("SpawnLocation")
hubSpawn.Name = "HubSpawn"
hubSpawn.Anchored = true
hubSpawn.Neutral = true
hubSpawn.Size = Vector3.new(14, 1, 14)
hubSpawn.Position = Vector3.new(0, 0.5, 0)
hubSpawn.Material = Enum.Material.SmoothPlastic
hubSpawn.Color = Color3.fromRGB(230, 225, 245)
hubSpawn.Parent = Workspace

-- Hub edge barrier: a tall invisible wall around the baseplate rim (512x512 → ±256) so
-- players can't walk/jump off the hub into the void. All hub pads and the world portals
-- sit far inside this (within ~±80), so nothing gets blocked. Parented to Workspace (the
-- hub is always-visible neutral space, so it never hides per-player).
createBarrier(Workspace, Vector3.new(0, 0, 0), 512)

-- "CENTRAL HUB" floating sign so the neutral hub is clearly labeled.
local hubSignPost = Instance.new("Part")
hubSignPost.Name = "HubSignPost"
hubSignPost.Anchored = true
hubSignPost.Size = Vector3.new(2, 22, 2)
hubSignPost.Position = Vector3.new(0, 11, 12)
hubSignPost.Material = Enum.Material.Marble
hubSignPost.Color = Color3.fromRGB(120, 110, 150)
hubSignPost.Parent = Workspace

local hubSign = Instance.new("BillboardGui")
hubSign.Name = "HubSign"
hubSign.Size = UDim2.fromScale(20, 5)
hubSign.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
hubSign.AlwaysOnTop = true
hubSign.Adornee = hubSignPost
hubSign.Parent = hubSignPost

local hubSignLabel = Instance.new("TextLabel")
hubSignLabel.Size = UDim2.fromScale(1, 1)
hubSignLabel.BackgroundTransparency = 1
hubSignLabel.Text = "CENTRAL HUB"
hubSignLabel.Font = Enum.Font.FredokaOne
hubSignLabel.TextScaled = true
hubSignLabel.TextColor3 = Color3.fromRGB(245, 240, 255)
hubSignLabel.TextStrokeTransparency = 0.3
hubSignLabel.TextStrokeColor3 = Color3.fromRGB(20, 18, 30)
hubSignLabel.Parent = hubSign

-- One portal per world, in a row on the far (-Z) side of the hub so they never overlap
-- the pads (which sit around z = ±24). Each portal's color matches its world's theme.
local HUB_PORTAL_DEFS = {
	{ index = 1, x = -60, color = Color3.fromRGB(90, 200, 90), name = "Tranquil Grove" },
	{ index = 2, x = 0, color = Color3.fromRGB(130, 160, 195), name = "Whispering Highlands" },
	{ index = 3, x = 60, color = Color3.fromRGB(180, 130, 245), name = "Celestial Summit" },
}
for _, def in ipairs(HUB_PORTAL_DEFS) do
	createPortal({
		name = "HubPortal" .. def.index,
		position = Vector3.new(def.x, 6, -72),
		color = def.color,
		label = "→ " .. def.name,
		onEnter = function(plr)
			-- W3 GATE: walking into a locked world's portal does NOT travel; instead the
			-- player gets a message with the requirement. Once unlocked, the portal just works.
			if not travelToWorld(plr, def.index) then
				notifyTravelBlocked(plr, def.index)
			end
		end,
	})
end

-- Client → server travel request (HUD Worlds menu). 0 = hub, 1..N = world index.
requestTravelEvent.OnServerEvent:Connect(function(player, target)
	if typeof(target) ~= "number" or not canTravel(player) then
		return
	end
	if target == 0 then
		travelToHub(player)
	elseif WORLDS[target] then
		-- W3 GATE: the server is the final authority — even if the client's menu was bypassed
		-- to request a locked world, travelToWorld refuses it and we reply with the requirement.
		if not travelToWorld(player, target) then
			notifyTravelBlocked(player, target)
		end
	end
end)

-- Client reads the world list + its current location to render the Worlds menu. Each world
-- carries its W3 unlock state: `unlocked` (whether this player may travel there) plus the
-- requirement numbers (reqAscend / reqChi) so the menu can label locked worlds. This is the
-- authoritative source the menu trusts — the client never decides unlock state itself.
getWorldsStateFunc.OnServerInvoke = function(player)
	local worlds = {}
	for index, world in ipairs(WORLDS) do
		local reqAscend, reqChi = worldUnlockReq(index)
		table.insert(worlds, {
			index = index,
			name = world.name,
			unlocked = isWorldUnlocked(player, index),
			reqAscend = reqAscend,
			reqChi = reqChi,
		})
	end
	return {
		atHub = atHub[player] ~= false,
		currentWorld = currentWorld[player] or DEFAULT_WORLD,
		worlds = worlds,
	}
end

--------------------------------------------------------------------------------
-- 5c. COSMETIC WAND — equip/unequip, server-authoritative (slice 1: ONE real wand)
--------------------------------------------------------------------------------
-- The FIRST cosmetic-wand slice: prove the core equip mechanic with ONE real wand.
-- The SERVER owns the wand completely — it CLONES a placed source model, welds it into the
-- character's hand, and destroys it — so the wand lives in the character model on the server and
-- Roblox replicates it to EVERY client (other players see it). Clients only send a toggle request
-- via ToggleWand; they never create the wand themselves. NOT YET: inventory, buying, rarity,
-- multiple wands, drops — just this one wand.
--
-- SOURCE: a clean, script-free wand Model placed in ServerStorage named "WandModel" (the "Handle"
-- part is the grip). We load by CLONING that model — NOT by InsertService:LoadAsset, which failed
-- for this asset with "asset not trusted for this place".

local WAND_MODEL_NAME = "Wand" -- name of the wand model once welded onto the character
local SOURCE_MODEL_NAME = "WandModel" -- the source model you placed in ServerStorage
local GRIP_PART_NAME = "Handle" -- the part inside WandModel that should sit in the fist

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  WAND FIT — tweak these to change how the wand sits in the hand.           ║
-- ╠══════════════════════════════════════════════════════════════════════════╣
-- ║  Start by adjusting WAND_SCALE (too big/small?), then WAND_GRIP_ROTATION   ║
-- ║  (pointing the wrong way?), then WAND_GRIP_OFFSET (sitting too high/low or  ║
-- ║  clipping into the arm?). Re-sync Rojo and re-equip after each change.      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
local WAND_SCALE = 1.0 -- uniform size multiplier for the whole wand (raise if tiny, lower if huge)
-- Rotation of the wand in the hand, in DEGREES. Applied as X (pitch), then Y (yaw), then Z (roll).
-- If the wand points down the arm or sideways instead of out of the fist, change these (90/180
-- on one axis usually fixes orientation). e.g. Vector3.new(90, 0, 0) tips it forward.
local WAND_GRIP_ROTATION = Vector3.new(0, 0, 0)
-- Position of the wand relative to the hand's grip point, in STUDS (after rotation). Nudge this
-- if the wand floats away from the palm or clips through the hand/arm. +Y up, +X right, +Z back.
local WAND_GRIP_OFFSET = Vector3.new(0, 0, 0)

-- The grip transform applied on top of the hand's grip attachment. Built from the tunables above.
local function wandGripCFrame()
	local r = WAND_GRIP_ROTATION
	return CFrame.new(WAND_GRIP_OFFSET)
		* CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

-- [player] = true while the player has the wand equipped. In-memory only (this throwaway slice
-- doesn't persist cosmetics); it survives respawns so the wand re-attaches to the new character.
local equippedWand = {}
local wandToggleDebounce = {} -- [player] = true briefly, so spam-clicking can't build two wands

-- The prepared wand template (built once from ServerStorage.WandModel, then cloned per equip).
-- nil if the source model is missing — attachWand warns instead of silently doing nothing.
local wandTemplate = nil

-- Find the grip/root part inside the cloned model: prefer the part named GRIP_PART_NAME
-- ("Handle"), then the model's PrimaryPart, then the largest part as a last resort.
local function findGripPart(model)
	local named = model:FindFirstChild(GRIP_PART_NAME, true)
	if named and named:IsA("BasePart") then
		return named
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local best, bestVolume = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVolume then
				best, bestVolume = d, v
			end
		end
	end
	return best
end

-- Build the wand template ONCE by CLONING ServerStorage.WandModel and normalizing it into a
-- clean, hand-ready Model:
--   • named WAND_MODEL_NAME, with PrimaryPart = the grip part ("Handle")
--   • every part unanchored + massless + non-colliding (so it can't drag or snag the character)
--   • every non-grip part welded to the grip, so the whole wand moves as one rigid piece
--   • scaled by WAND_SCALE
-- Returns the template Model, or nil + a reason string on failure.
local function prepareWandTemplate()
	local source = ServerStorage:FindFirstChild(SOURCE_MODEL_NAME)
	if not source then
		return nil, ("ServerStorage.%s not found"):format(SOURCE_MODEL_NAME)
	end

	local model = source:Clone()
	model.Name = WAND_MODEL_NAME

	-- Drop anything that shouldn't ride along on a cosmetic: existing joints (we re-weld to our
	-- chosen grip) and any stray scripts (the source should already be script-free).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("Snap")
			or d:IsA("BaseScript") then
			d:Destroy()
		end
	end

	local grip = findGripPart(model)
	if not grip then
		model:Destroy()
		return nil, ("%s contains no parts"):format(SOURCE_MODEL_NAME)
	end

	-- Make every part safe to wear, then weld each non-grip part to the grip (reparenting/cloning
	-- preserves world CFrame, so the model stays assembled while we re-weld it).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
			if d ~= grip then
				local w = Instance.new("Weld")
				w.Part0 = grip
				w.Part1 = d
				w.C0 = grip.CFrame:ToObjectSpace(d.CFrame) -- lock current relative pose
				w.Parent = grip
			end
		end
	end
	model.PrimaryPart = grip

	if WAND_SCALE ~= 1 then
		model:ScaleTo(WAND_SCALE) -- scales parts, meshes, and our weld offsets together
	end
	return model, nil
end

-- Clone the prepared template for one equip. Returns model, grip — or nil if the source is missing.
local function buildWandModel()
	if not wandTemplate then
		return nil, nil
	end
	local model = wandTemplate:Clone()
	return model, model.PrimaryPart
end

-- Prepare the template ONCE at startup. If the source model is missing, log a clear message so
-- it's obvious the WandModel needs to be placed (rather than equipping silently doing nothing).
do
	local model, reason = prepareWandTemplate()
	if model then
		wandTemplate = model
		print(("[Wand] Prepared wand from ServerStorage.%s."):format(SOURCE_MODEL_NAME))
	else
		warn(("[Wand] %s — place a clean, script-free wand Model in ServerStorage named '%s' "
			.. "(with the grip part named '%s'). Equipping will no-op until it exists."):format(
			reason, SOURCE_MODEL_NAME, GRIP_PART_NAME))
	end
end

-- The character's hand part (R15 first, R6 fallback). Yields briefly for late-loading R15 limbs.
local function getHandPart(character)
	return character:FindFirstChild("RightHand") -- R15
		or character:WaitForChild("RightHand", 5) -- R15, still streaming in on a fresh spawn
		or character:FindFirstChild("Right Arm") -- R6 fallback
end

-- Remove any wand currently on the player's character (used by unequip + before re-attaching).
local function detachWand(player, character)
	character = character or player.Character
	if not character then
		return
	end
	local existing = character:FindFirstChild(WAND_MODEL_NAME)
	if existing then
		existing:Destroy() -- takes the weld + tip + light with it
	end
end

-- Build + weld the wand into the hand. SERVER-side, so it replicates to all clients. Safe to
-- call repeatedly: it clears any existing wand first. No-ops if the player isn't equipped.
local function attachWand(player, character)
	character = character or player.Character
	if not character or not equippedWand[player] then
		return
	end
	local hand = getHandPart(character)
	-- Re-check after the possible WaitForChild yield: the player may have unequipped or the
	-- character may have changed (respawn) while we waited.
	if not hand or not equippedWand[player] or player.Character ~= character then
		return
	end

	local model, root = buildWandModel()
	if not model then
		-- Template was never built — the source model is missing. We warned once at startup;
		-- warn here too so it's obvious on equip rather than failing silently.
		warn(("[Wand] Cannot equip for %s — ServerStorage.%s is missing (see startup warning)."):format(
			player.Name, SOURCE_MODEL_NAME))
		return
	end

	detachWand(player, character) -- guarantee a single wand

	-- Anchor the weld to the hand's grip attachment when present (R15), else a sane fallback.
	local grip = hand:FindFirstChild("RightGripAttachment")
	local baseGrip = grip and grip.CFrame or CFrame.new(0, -0.2, 0)
	local c0 = baseGrip * wandGripCFrame()
	-- Pre-place the whole wand at the welded pose (PivotTo moves PrimaryPart + welded parts as one)
	-- so there's no one-frame fall before the weld locks.
	model:PivotTo(hand.CFrame * c0)
	model.Parent = character

	local weld = Instance.new("Weld")
	weld.Name = "WandWeld"
	weld.Part0 = hand
	weld.Part1 = root
	weld.C0 = c0
	weld.Parent = root
end

-- Toggle request from the client. The SERVER decides + performs the change (authoritative).
toggleWandEvent.OnServerEvent:Connect(function(player)
	if wandToggleDebounce[player] then
		return -- ignore rapid repeats so we never build two wands at once
	end
	wandToggleDebounce[player] = true
	task.delay(0.3, function()
		wandToggleDebounce[player] = nil
	end)

	if equippedWand[player] then
		equippedWand[player] = nil
		detachWand(player)
	else
		equippedWand[player] = true
		attachWand(player, player.Character)
	end
end)

-- RESPAWN handling: if the wand is equipped, re-attach it to each NEW character. task.spawn so
-- the getHandPart WaitForChild yield can't block the join/respawn flow.
local function hookWandRespawn(player)
	player.CharacterAdded:Connect(function(character)
		if equippedWand[player] then
			task.spawn(attachWand, player, character)
		end
	end)
end
Players.PlayerAdded:Connect(hookWandRespawn)
for _, player in ipairs(Players:GetPlayers()) do
	hookWandRespawn(player)
end

--------------------------------------------------------------------------------
-- 6b. Periodic autosave (the throttle that fixes the DataStore queue warning)
--------------------------------------------------------------------------------
-- Saves used to fire on individual data-change events (every world unlock, every daily claim),
-- which — clustered with the leave/shutdown saves — wrote the SAME key repeatedly within a few
-- seconds and filled Roblox's per-key DataStore request queue ("request added to queue"
-- warning), risking dropped saves. Now changes only set a dirty flag (markDirty); this single
-- loop is the ONLY periodic writer. Every AUTOSAVE_INTERVAL it flushes each dirty player exactly
-- once (savePlayerData skips clean players and coalesces in-flight writes), keeping each key far
-- under the ~6 + numPlayers writes/min budget. Leave + shutdown saves remain as guaranteed
-- backstops, so nothing earned between ticks is ever lost.
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			if dirty[player] then
				-- Per-player spawn: one slow write never delays the others, and each is a
				-- DIFFERENT key so they don't contend with each other's rate budget.
				task.spawn(savePlayerData, player) -- non-forced: writes only if still dirty
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 6. Save on leave + per-player cleanup
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	-- Save BEFORE clearing the tables that savePlayerData reads from. force=true: always persist
	-- the very latest state on leave (ignores the dirty check), so a player who earned Chi then
	-- left immediately still has it saved — it just waits out any in-flight autosave first.
	savePlayerData(player, true)

	lastClickTime[player] = nil
	for _, debounce in ipairs(padDebounces) do
		debounce[player] = nil
	end
	zenLevel[player] = nil
	ascendCount[player] = nil
	jarTier[player] = nil
	hasAutoClicker[player] = nil
	claimedGroupReward[player] = nil
	lastDailyClaim[player] = nil
	dailyStreak[player] = nil
	equippedWand[player] = nil
	wandToggleDebounce[player] = nil
	currentWorld[player] = nil
	unlockedWorlds[player] = nil
	atHub[player] = nil
	travelDebounce[player] = nil
	canSave[player] = nil
	dirty[player] = nil
	saving[player] = nil
	initialized[player] = nil -- allow a clean re-setup if this player rejoins
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
			savePlayerData(player, true) -- force: persist the latest state for everyone on shutdown
			remaining -= 1
		end)
	end

	-- Wait for the saves to complete, but never exceed the shutdown budget.
	local elapsed = 0
	while remaining > 0 and elapsed < 25 do
		elapsed += task.wait()
	end
end)
