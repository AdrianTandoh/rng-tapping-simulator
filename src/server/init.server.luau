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

--------------------------------------------------------------------------------
-- 2. Give every player a leaderstats folder
--------------------------------------------------------------------------------
-- Roblox automatically shows any IntValue/NumberValue inside a "leaderstats"
-- folder on the in-game leaderboard. We create one Spirit Power value per player.

local function setupLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local spiritPower = Instance.new("IntValue")
	spiritPower.Name = "Spirit Power"
	spiritPower.Value = 0 -- everyone starts with zero
	spiritPower.Parent = leaderstats

	leaderstats.Parent = player
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
	grantSpiritPower(player, 1) -- one click = +1 Spirit Power
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
end)
