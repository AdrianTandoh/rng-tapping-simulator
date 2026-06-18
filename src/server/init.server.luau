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

--------------------------------------------------------------------------------
-- 2. Give every player a leaderstats folder
--------------------------------------------------------------------------------
-- Roblox automatically shows any IntValue/NumberValue inside a "leaderstats"
-- folder on the in-game leaderboard. We create one Spirit Power value per player.

-- Server-authoritative per-player progression, declared here (before
-- setupLeaderstats) so the leaderstats setup can seed them.
local zenLevel = {} -- [player] = Zen level (number, starts at 0)
local ascendCount = {} -- [player] = number of times Ascended (starts at 0)

local function setupLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local spiritPower = Instance.new("IntValue")
	spiritPower.Name = "Spirit Power"
	spiritPower.Value = 0 -- everyone starts with zero
	spiritPower.Parent = leaderstats

	leaderstats.Parent = player

	-- Start every player at Zen level 0 (x1 click multiplier) and Ascend count 0.
	zenLevel[player] = 0
	ascendCount[player] = 0
end

-- Handle players who join after this script runs...
Players.PlayerAdded:Connect(setupLeaderstats)
-- ...and any players who somehow already exist (e.g. fast Studio start).
for _, player in ipairs(Players:GetPlayers()) do
	setupLeaderstats(player)
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
		-- Apply the permanent Ascend multiplier, then floor to a whole number.
		spiritPower.Value += math.floor(amount * getAscendMultiplier(player))
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
	return getAscendState(player)
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
-- 6. Per-player cleanup
--------------------------------------------------------------------------------
-- Drop a leaving player's bookkeeping so the tables don't grow forever.
Players.PlayerRemoving:Connect(function(player)
	lastClickTime[player] = nil
	touchDebounce[player] = nil
	zenLevel[player] = nil
	ascendCount[player] = nil
end)
