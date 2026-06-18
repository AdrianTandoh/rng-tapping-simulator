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

--------------------------------------------------------------------------------
-- 2. Give every player a leaderstats folder
--------------------------------------------------------------------------------
-- Roblox automatically shows any IntValue/NumberValue inside a "leaderstats"
-- folder on the in-game leaderboard. We create one Spirit Power value per player.

-- Server-authoritative Zen level per player ([player] = number, starts at 0).
-- Declared here (before setupLeaderstats) so the leaderstats setup can seed it.
local zenLevel = {}

local function setupLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local spiritPower = Instance.new("IntValue")
	spiritPower.Name = "Spirit Power"
	spiritPower.Value = 0 -- everyone starts with zero
	spiritPower.Parent = leaderstats

	leaderstats.Parent = player

	-- Start every player at Zen level 0 (x1 click multiplier).
	zenLevel[player] = 0
end

-- Handle players who join after this script runs...
Players.PlayerAdded:Connect(setupLeaderstats)
-- ...and any players who somehow already exist (e.g. fast Studio start).
for _, player in ipairs(Players:GetPlayers()) do
	setupLeaderstats(player)
end

--------------------------------------------------------------------------------
-- 3. Single chokepoint for granting Spirit Power
--------------------------------------------------------------------------------
-- ALL Spirit Power changes go through this one function. Right now only the
-- click handler calls it (amount = 1), but a future auto-clicker can call the
-- exact same function, so there's only ever one place that touches the stat.

local function grantSpiritPower(player, amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
	if spiritPower then
		spiritPower.Value += amount
	end
end

--------------------------------------------------------------------------------
-- 3b. Zen upgrade (click multiplier)
--------------------------------------------------------------------------------
-- Zen is a click multiplier. multiplier = 2 ^ ZenLevel, so each level doubles
-- click value (level 0 = x1, level 1 = x2, ... level 8 = x256).
--
-- The cap is a VARIABLE, not a hardcoded literal, so a future "Ascend" system
-- can raise it at runtime. The buy logic below only ever compares against this.
local zenCap = 8 -- max Zen level for now (x256); Ascend will raise this later

local ZEN_BASE_PRICE = 50 -- Spirit Power cost of the first level (0 -> 1)
local ZEN_PRICE_MULTIPLIER = 2.5 -- each level costs 2.5x the previous one

-- (zenLevel table is declared earlier, near the leaderstats setup.)

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
	local maxed = level >= zenCap
	return {
		level = level,
		multiplier = getZenMultiplier(level),
		cost = (not maxed) and getZenCost(level) or nil,
		maxed = maxed,
		cap = zenCap,
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
	if level >= zenCap then
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
end)
