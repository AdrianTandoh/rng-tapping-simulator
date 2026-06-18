-- Ancient Spirit Simulator
-- Core earning mechanic: CLICK-TO-EARN (server-authoritative)
--
-- Players earn the "Spirit Power" stat by clicking the game world. The client
-- only *detects* clicks and asks the server to grant power; the server is the
-- single source of truth and the only thing that ever changes Spirit Power.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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

--------------------------------------------------------------------------------
-- 2. Player progression tables
--------------------------------------------------------------------------------
-- Server-authoritative per-player progression, declared up front so the data
-- loading + leaderstats setup below can seed them.
local zenLevel = {} -- [player] = Zen level (starts at 0)
local ascendCount = {} -- [player] = times Ascended (starts at 0)
local jarTier = {} -- [player] = Soul Jar tier index (0 = Clay, starts at 0)
local canSave = {} -- [player] = true ONLY if their data loaded cleanly (see 2c)

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
	return { SpiritPower = 0, ZenLevel = 0, AscendCount = 0, JarTier = 0 }
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

	-- Existing data: read each field defensively.
	return {
		SpiritPower = tonumber(result.SpiritPower) or 0,
		ZenLevel = tonumber(result.ZenLevel) or 0,
		AscendCount = tonumber(result.AscendCount) or 0,
		JarTier = tonumber(result.JarTier) or 0,
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
	local data = {
		SpiritPower = spiritPower and spiritPower.Value or 0,
		ZenLevel = zenLevel[player] or 0,
		AscendCount = ascendCount[player] or 0,
		JarTier = jarTier[player] or 0,
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

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local spiritPower = Instance.new("IntValue")
	spiritPower.Name = "Spirit Power"
	-- Clamp to the (now-known) jar capacity in case saved data somehow exceeds it.
	spiritPower.Value = math.min(data.SpiritPower, getSpiritCap(player))
	spiritPower.Parent = leaderstats

	leaderstats.Parent = player
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
-- 4. Click-to-earn with a simple rate limit
--------------------------------------------------------------------------------
-- Basic anti-exploit protection: a client could be hacked to fire the RemoteEvent
-- thousands of times per second. We record when each player's last click was
-- accepted and silently ignore any click that arrives sooner than a human could
-- realistically click. This is intentionally minimal, not full anti-cheat.

local MIN_CLICK_GAP = 0.05 -- seconds between accepted clicks (~20 clicks/sec cap)
local lastClickTime = {} -- [player] = os.clock() of last accepted click

clickEarnEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	local last = lastClickTime[player]

	-- Reject clicks that come in faster than the allowed gap.
	if last and (now - last) < MIN_CLICK_GAP then
		return
	end

	lastClickTime[player] = now

	-- One click is worth baseAmount * the player's Zen multiplier. Everything
	-- still flows through grantSpiritPower so a future auto-clicker reuses it.
	local CLICK_BASE_AMOUNT = 1
	local multiplier = getZenMultiplier(zenLevel[player] or 0)
	grantSpiritPower(player, CLICK_BASE_AMOUNT * multiplier)
end)

--------------------------------------------------------------------------------
-- 5. The Shop pad
--------------------------------------------------------------------------------
-- A pad that opens the shop UI when touched. The actual GUI is built on the
-- client (UI is client-only); the server just owns the pad and tells the
-- touching player's client to open the shop via the OpenShop RemoteEvent.

-- Build the gold shop pad, set off to the side near the world origin.
local shopPad = Instance.new("Part")
shopPad.Name = "ShopPad"
shopPad.Size = Vector3.new(12, 1, 12)
shopPad.Position = Vector3.new(24, 0.5, 0) -- 24 studs from origin
shopPad.Anchored = true
shopPad.Material = Enum.Material.Neon -- glowing
shopPad.Color = Color3.fromRGB(255, 200, 40) -- bright gold
shopPad.TopSurface = Enum.SurfaceType.Smooth
shopPad.BottomSurface = Enum.SurfaceType.Smooth
shopPad.Parent = Workspace

-- Floating "SHOP" label hovering above the pad.
local label = Instance.new("BillboardGui")
label.Name = "ShopLabel"
label.Size = UDim2.fromScale(6, 1.5) -- in studs (Adornee scale)
label.StudsOffsetWorldSpace = Vector3.new(0, 4, 0) -- float above the pad
label.AlwaysOnTop = true
label.Adornee = shopPad

local labelText = Instance.new("TextLabel")
labelText.Size = UDim2.fromScale(1, 1)
labelText.BackgroundTransparency = 1
labelText.Text = "SHOP"
labelText.Font = Enum.Font.GothamBold
labelText.TextScaled = true
labelText.TextColor3 = Color3.fromRGB(255, 255, 255)
labelText.TextStrokeTransparency = 0.4
labelText.TextStrokeColor3 = Color3.fromRGB(120, 80, 0)
labelText.Parent = label

label.Parent = shopPad

-- Fire the open event when a player touches the pad. We add a short per-player
-- debounce so a single step-on doesn't spam the remote dozens of times per
-- second. The client safely ignores the event if the shop is already open.
local touchDebounce = {} -- [player] = true while on cooldown

shopPad.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or touchDebounce[player] then
		return
	end

	touchDebounce[player] = true
	openShopEvent:FireClient(player)

	task.delay(1, function()
		touchDebounce[player] = nil
	end)
end)

--------------------------------------------------------------------------------
-- 6. Save on leave + per-player cleanup
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	-- Save BEFORE clearing the tables that savePlayerData reads from.
	savePlayerData(player)

	lastClickTime[player] = nil
	touchDebounce[player] = nil
	zenLevel[player] = nil
	ascendCount[player] = nil
	jarTier[player] = nil
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
