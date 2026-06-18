-- Ancient Spirit Simulator
-- Slice: Shop UI shell (open / tab-switch / close only — no buying logic yet)
--
-- This LocalScript builds the shop popup entirely on the client (UI is
-- client-only). The server fires the "OpenShop" RemoteEvent when the player
-- touches the shop pad; we listen for it and show the popup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local openShopEvent = ReplicatedStorage:WaitForChild("OpenShop")

-- Tab definitions: order here is the order shown along the top.
local TABS = { "Zen", "Soul Jar", "Ascend" }
local DEFAULT_TAB = "Zen"

-- Playful UI font used everywhere (HUD + shop).
-- NOTE: "Baloo 2" is NOT a valid Enum.Font and isn't a built-in Roblox FontFace
-- family, so it would error / silently fall back. FredokaOne is the closest
-- guaranteed built-in rounded, playful font. Swap this one constant later if you
-- upload Baloo 2 as a custom FontFace.
local FONT = Enum.Font.FredokaOne

--------------------------------------------------------------------------------
-- Small styling helpers
--------------------------------------------------------------------------------

-- Adds rounded corners to any GUI object.
local function round(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = instance
	return corner
end

-- Adds a colored outline (stroke) to any GUI object.
local function stroke(instance, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = instance
	return s
end

--------------------------------------------------------------------------------
-- Build the popup once, keep it hidden, and just toggle visibility
--------------------------------------------------------------------------------
-- Building it a single time (instead of rebuilding on every touch) is what makes
-- "touching the pad again while open" harmless: we only ever flip .Visible.

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopGui"
screenGui.ResetOnSpawn = false -- survive respawns
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false -- hidden until the player touches the pad
screenGui.Parent = playerGui

-- Soft drop shadow: a slightly larger dark frame sitting behind the main frame.
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(0.5, 0, 0.5, 6) -- nudged down for the shadow effect
shadow.Size = UDim2.fromOffset(580, 420)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.6
shadow.ZIndex = 0
shadow.Parent = screenGui
round(shadow, 22)

-- Main popup frame.
local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.Size = UDim2.fromOffset(560, 400)
main.BackgroundColor3 = Color3.fromRGB(45, 35, 70) -- deep violet
main.ZIndex = 1
main.Parent = screenGui
round(main, 20)
stroke(main, Color3.fromRGB(255, 200, 40), 3) -- gold outline

-- Header bar.
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 64)
header.BackgroundColor3 = Color3.fromRGB(120, 80, 200) -- bright purple
header.ZIndex = 2
header.Parent = main
round(header, 20)

-- Cover the header's lower rounded corners so it blends into the body.
local headerCover = Instance.new("Frame")
headerCover.Size = UDim2.new(1, 0, 0, 24)
headerCover.Position = UDim2.new(0, 0, 1, -24)
headerCover.BackgroundColor3 = header.BackgroundColor3
headerCover.BorderSizePixel = 0
headerCover.ZIndex = 2
headerCover.Parent = header

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.fromOffset(20, 0)
title.BackgroundTransparency = 1
title.Text = "SPIRIT SHOP"
title.Font = FONT
title.TextSize = 30
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextStrokeTransparency = 0.6
title.ZIndex = 3
title.Parent = header

-- Close ("X") button, top-right of the header.
local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -16, 0.5, 0)
closeButton.Size = UDim2.fromOffset(40, 40)
closeButton.BackgroundColor3 = Color3.fromRGB(235, 70, 70) -- red
closeButton.Text = "X"
closeButton.Font = FONT
closeButton.TextSize = 24
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.ZIndex = 3
closeButton.AutoButtonColor = true
closeButton.Parent = header
round(closeButton, 12)
stroke(closeButton, Color3.fromRGB(150, 30, 30), 2)

-- Row that holds the tab buttons.
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -32, 0, 50)
tabBar.Position = UDim2.fromOffset(16, 80)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 2
tabBar.Parent = main

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Padding = UDim.new(0, 10)
tabLayout.Parent = tabBar

-- Content area below the tabs, where the selected panel is shown.
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -32, 1, -150)
content.Position = UDim2.fromOffset(16, 142)
content.BackgroundColor3 = Color3.fromRGB(60, 50, 95)
content.ZIndex = 1
content.Parent = main
round(content, 16)
stroke(content, Color3.fromRGB(90, 75, 130), 2)

--------------------------------------------------------------------------------
-- Create one tab button + one panel per tab
--------------------------------------------------------------------------------

-- Highlighted vs idle tab colors.
local SELECTED_BG = Color3.fromRGB(255, 200, 40)
local SELECTED_TEXT = Color3.fromRGB(60, 40, 0)
local IDLE_BG = Color3.fromRGB(90, 75, 130)
local IDLE_TEXT = Color3.fromRGB(235, 230, 245)

local tabButtons = {} -- [name] = TextButton
local panels = {} -- [name] = Frame

for index, name in ipairs(TABS) do
	-- Tab button.
	local button = Instance.new("TextButton")
	button.Name = name .. "Tab"
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(160, 44)
	button.Text = name
	button.Font = FONT
	button.TextSize = 20
	button.AutoButtonColor = true
	button.ZIndex = 2
	button.Parent = tabBar
	round(button, 12)
	tabButtons[name] = button

	-- Matching panel. The Zen panel is built for real further below; the other
	-- tabs keep their placeholder text for now.
	local panel = Instance.new("Frame")
	panel.Name = name .. "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.ZIndex = 1
	panel.Parent = content
	panels[name] = panel

	if name ~= "Zen" and name ~= "Ascend" and name ~= "Soul Jar" then
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.fromScale(1, 1)
		placeholder.BackgroundTransparency = 1
		placeholder.Text = name .. " upgrades coming soon"
		placeholder.Font = FONT
		placeholder.TextSize = 26
		placeholder.TextColor3 = Color3.fromRGB(255, 255, 255)
		placeholder.TextWrapped = true
		placeholder.ZIndex = 1
		placeholder.Parent = panel
	end
end

--------------------------------------------------------------------------------
-- Tab switching
--------------------------------------------------------------------------------
-- Show one panel, hide the rest, and highlight the matching tab button.

local function selectTab(selectedName)
	for name, button in pairs(tabButtons) do
		local isSelected = (name == selectedName)
		button.BackgroundColor3 = isSelected and SELECTED_BG or IDLE_BG
		button.TextColor3 = isSelected and SELECTED_TEXT or IDLE_TEXT
		panels[name].Visible = isSelected
	end
end

for name, button in pairs(tabButtons) do
	button.Activated:Connect(function()
		selectTab(name)
	end)
end

--------------------------------------------------------------------------------
-- Open / close wiring
--------------------------------------------------------------------------------

local function openShop()
	selectTab(DEFAULT_TAB) -- always start on the default tab
	screenGui.Enabled = true
end

local function closeShop()
	screenGui.Enabled = false
end

closeButton.Activated:Connect(closeShop)

-- The server tells us to open the shop when the player touches the pad.
-- Re-touching while it's already open just calls openShop() again, which simply
-- re-shows the default tab — harmless.
openShopEvent.OnClientEvent:Connect(openShop)

--------------------------------------------------------------------------------
-- Click-to-earn (world clicks only)
--------------------------------------------------------------------------------
-- Detect clicks/taps and ask the server to grant Spirit Power. We only count
-- clicks on the game world: if Roblox already routed the input to the GUI (the
-- shop popup, its buttons, etc.) it sets gameProcessedEvent = true, and we skip
-- it. The client never changes Spirit Power itself — it just fires the event.

local UserInputService = game:GetService("UserInputService")
local clickEarnEvent = ReplicatedStorage:WaitForChild("ClickEarn")

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	-- Ignore anything the GUI already handled (clicks on the shop / buttons).
	if gameProcessedEvent then
		return
	end

	-- Only count a left mouse click or a touch tap.
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		clickEarnEvent:FireServer()
	end
end)

--------------------------------------------------------------------------------
-- Zen tab: click multiplier upgrade
--------------------------------------------------------------------------------
-- Builds the real Zen panel and wires it to the server. The server is the only
-- authority on Zen level / Spirit Power; this UI just displays what the server
-- returns and asks it to buy. The panel re-renders whenever the shop opens and
-- after every purchase attempt.

local getZenStateFunc = ReplicatedStorage:WaitForChild("GetZenState")
local buyZenFunc = ReplicatedStorage:WaitForChild("BuyZen")

local zenPanel = panels["Zen"]

-- Big current-multiplier readout (e.g. "x4").
local multLabel = Instance.new("TextLabel")
multLabel.Name = "Multiplier"
multLabel.AnchorPoint = Vector2.new(0.5, 0)
multLabel.Position = UDim2.new(0.5, 0, 0, 16)
multLabel.Size = UDim2.new(1, -32, 0, 70)
multLabel.BackgroundTransparency = 1
multLabel.Text = "x1"
multLabel.Font = FONT
multLabel.TextSize = 56
multLabel.TextColor3 = Color3.fromRGB(255, 200, 40) -- gold accent
multLabel.TextStrokeTransparency = 0.7
multLabel.ZIndex = 1
multLabel.Parent = zenPanel

-- Current Zen level.
local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "Level"
levelLabel.AnchorPoint = Vector2.new(0.5, 0)
levelLabel.Position = UDim2.new(0.5, 0, 0, 88)
levelLabel.Size = UDim2.new(1, -32, 0, 28)
levelLabel.BackgroundTransparency = 1
levelLabel.Text = "Zen Level 0"
levelLabel.Font = FONT
levelLabel.TextSize = 22
levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
levelLabel.ZIndex = 1
levelLabel.Parent = zenPanel

-- Short description of what Zen does.
local descLabel = Instance.new("TextLabel")
descLabel.Name = "Desc"
descLabel.AnchorPoint = Vector2.new(0.5, 0)
descLabel.Position = UDim2.new(0.5, 0, 0, 118)
descLabel.Size = UDim2.new(1, -40, 0, 24)
descLabel.BackgroundTransparency = 1
descLabel.Text = "Each level doubles your click power."
descLabel.Font = FONT
descLabel.TextSize = 16
descLabel.TextColor3 = Color3.fromRGB(210, 200, 230)
descLabel.TextWrapped = true
descLabel.ZIndex = 1
descLabel.Parent = zenPanel

-- BUY button (also shows the cost / MAX state).
local BUY_COLOR = Color3.fromRGB(70, 200, 90) -- friendly green
local MAX_COLOR = Color3.fromRGB(110, 100, 140) -- muted when maxed

local buyButton = Instance.new("TextButton")
buyButton.Name = "Buy"
buyButton.AnchorPoint = Vector2.new(0.5, 1)
buyButton.Position = UDim2.new(0.5, 0, 1, -16)
buyButton.Size = UDim2.new(1, -40, 0, 56)
buyButton.BackgroundColor3 = BUY_COLOR
buyButton.Text = "BUY"
buyButton.Font = FONT
buyButton.TextSize = 24
buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buyButton.TextStrokeTransparency = 0.6
buyButton.AutoButtonColor = true
buyButton.ZIndex = 1
buyButton.Parent = zenPanel
round(buyButton, 14)
stroke(buyButton, Color3.fromRGB(40, 120, 55), 2)

-- Render the panel from an authoritative state table sent by the server.
local function renderZen(state)
	multLabel.Text = string.format("x%d", state.multiplier)
	levelLabel.Text = "Zen Level " .. state.level

	if state.maxed then
		buyButton.Text = "MAX"
		buyButton.BackgroundColor3 = MAX_COLOR
		buyButton.AutoButtonColor = false
		buyButton.Active = false -- unbuyable at the cap
	else
		buyButton.Text = "BUY  •  " .. state.cost .. " Spirit Power"
		buyButton.BackgroundColor3 = BUY_COLOR
		buyButton.AutoButtonColor = true
		buyButton.Active = true
	end
end

-- Ask the server for the latest state and redraw.
local function refreshZen()
	renderZen(getZenStateFunc:InvokeServer())
end

-- Buying: the server validates and returns the resulting state (unchanged if the
-- purchase was rejected for being maxed or too expensive), which we render.
buyButton.Activated:Connect(function()
	if not buyButton.Active then
		return
	end
	renderZen(buyZenFunc:InvokeServer())
end)

-- Keep the panel current: refresh once at startup and every time the shop opens.
openShopEvent.OnClientEvent:Connect(refreshZen)
refreshZen()

--------------------------------------------------------------------------------
-- Rank titles & colors (edit these freely to rename / recolor ranks)
--------------------------------------------------------------------------------
-- Ordered ladder: AscendCount 0 = first title; anything past the last title
-- stays at the final one.
local RANK_TITLES = {
	"Seeker", "Disciple", "Adept", "Mystic", "Sage",
	"Ascendant", "Immortal", "Celestial", "Transcendent", "Eternal",
}

-- Colors escalate in grandeur: gray/white/blue -> purple -> gold/glowing.
local RANK_COLORS = {
	Seeker = Color3.fromRGB(170, 175, 185), -- gray
	Disciple = Color3.fromRGB(240, 240, 245), -- white
	Adept = Color3.fromRGB(90, 170, 255), -- blue
	Mystic = Color3.fromRGB(120, 110, 245), -- indigo
	Sage = Color3.fromRGB(175, 95, 235), -- purple
	Ascendant = Color3.fromRGB(225, 90, 205), -- magenta
	Immortal = Color3.fromRGB(255, 115, 90), -- ember orange
	Celestial = Color3.fromRGB(255, 185, 65), -- amber
	Transcendent = Color3.fromRGB(255, 215, 60), -- gold
	Eternal = Color3.fromRGB(255, 245, 170), -- glowing pale gold
}

local function getRankTitle(count)
	return RANK_TITLES[math.min(count + 1, #RANK_TITLES)]
end

local function getRankColor(count)
	return RANK_COLORS[getRankTitle(count)]
end

--------------------------------------------------------------------------------
-- Number formatting helpers
--------------------------------------------------------------------------------

-- "12345" -> "12,345"
local function commafy(n)
	local s = tostring(math.floor(n))
	while true do
		local replaced, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = replaced
		if count == 0 then
			break
		end
	end
	return s
end

-- 1.5 -> "x1.5", 1 -> "x1", 2.25 -> "x2.25"
local function fmtMult(m)
	local s = string.format("%.2f", m)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return "x" .. s
end

--------------------------------------------------------------------------------
-- Live Spirit Power value (read-only on the client)
--------------------------------------------------------------------------------
-- The server owns this IntValue; we just watch it so the HUD and the Ascend
-- button update live. The client never writes to it.

local statsFolder = player:WaitForChild("leaderstats")
local spiritPowerValue = statsFolder:WaitForChild("Spirit Power")

local getAscendStateFunc = ReplicatedStorage:WaitForChild("GetAscendState")
local ascendFunc = ReplicatedStorage:WaitForChild("Ascend")
local getSoulJarStateFunc = ReplicatedStorage:WaitForChild("GetSoulJarState")
local buySoulJarFunc = ReplicatedStorage:WaitForChild("BuySoulJar")

--------------------------------------------------------------------------------
-- On-screen HUD (always visible, separate from the shop popup)
--------------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "HUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.Parent = playerGui

-- Big SILVER Spirit Power counter, top-center.
local spiritCounter = Instance.new("TextLabel")
spiritCounter.Name = "SpiritCounter"
spiritCounter.AnchorPoint = Vector2.new(0.5, 0)
spiritCounter.Position = UDim2.new(0.5, 0, 0, 14)
spiritCounter.Size = UDim2.fromOffset(460, 52)
spiritCounter.BackgroundTransparency = 1
spiritCounter.Font = FONT
spiritCounter.TextScaled = true
spiritCounter.TextColor3 = Color3.fromRGB(205, 210, 220) -- silver
spiritCounter.TextStrokeTransparency = 0.35
spiritCounter.TextStrokeColor3 = Color3.fromRGB(40, 40, 55)
spiritCounter.Text = "0 Spirit Power"
spiritCounter.Parent = hud

local spiritCap = Instance.new("UITextSizeConstraint")
spiritCap.MaxTextSize = 44
spiritCap.Parent = spiritCounter

-- Big COLOR-CODED rank title, just below the counter.
local rankDisplay = Instance.new("TextLabel")
rankDisplay.Name = "RankDisplay"
rankDisplay.AnchorPoint = Vector2.new(0.5, 0)
rankDisplay.Position = UDim2.new(0.5, 0, 0, 66)
rankDisplay.Size = UDim2.fromOffset(360, 40)
rankDisplay.BackgroundTransparency = 1
rankDisplay.Font = FONT
rankDisplay.TextScaled = true
rankDisplay.TextStrokeTransparency = 0.45
rankDisplay.TextStrokeColor3 = Color3.fromRGB(20, 20, 28)
rankDisplay.Text = "Seeker"
rankDisplay.Parent = hud

local rankCap = Instance.new("UITextSizeConstraint")
rankCap.MaxTextSize = 34
rankCap.Parent = rankDisplay

-- Current Soul Jar capacity, kept in sync from the server; used to show the
-- "held / cap" counter. Defaults to the Clay Jar until the server reports in.
local currentJarCapacity = 1000

local function updateHudSpirit()
	spiritCounter.Text = commafy(spiritPowerValue.Value) .. " / " .. commafy(currentJarCapacity)
end

local function updateHudRank(count)
	rankDisplay.Text = getRankTitle(count)
	rankDisplay.TextColor3 = getRankColor(count)
end

--------------------------------------------------------------------------------
-- Ascend tab (prestige) panel
--------------------------------------------------------------------------------

local ascendPanel = panels["Ascend"]
local ASCEND_READY_COLOR = Color3.fromRGB(255, 200, 40) -- gold when ready
local ASCEND_LOCKED_COLOR = Color3.fromRGB(110, 100, 140) -- muted when locked

-- Rank title (color-coded), big at the top of the panel.
local ascRankLabel = Instance.new("TextLabel")
ascRankLabel.AnchorPoint = Vector2.new(0.5, 0)
ascRankLabel.Position = UDim2.new(0.5, 0, 0, 12)
ascRankLabel.Size = UDim2.new(1, -32, 0, 50)
ascRankLabel.BackgroundTransparency = 1
ascRankLabel.Font = FONT
ascRankLabel.TextSize = 42
ascRankLabel.TextStrokeTransparency = 0.6
ascRankLabel.Text = "Seeker"
ascRankLabel.ZIndex = 1
ascRankLabel.Parent = ascendPanel

-- Ascension count.
local ascCountLabel = Instance.new("TextLabel")
ascCountLabel.AnchorPoint = Vector2.new(0.5, 0)
ascCountLabel.Position = UDim2.new(0.5, 0, 0, 66)
ascCountLabel.Size = UDim2.new(1, -32, 0, 26)
ascCountLabel.BackgroundTransparency = 1
ascCountLabel.Font = FONT
ascCountLabel.TextSize = 20
ascCountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ascCountLabel.Text = "Ascensions: 0"
ascCountLabel.ZIndex = 1
ascCountLabel.Parent = ascendPanel

-- Permanent multiplier reward.
local ascMultLabel = Instance.new("TextLabel")
ascMultLabel.AnchorPoint = Vector2.new(0.5, 0)
ascMultLabel.Position = UDim2.new(0.5, 0, 0, 92)
ascMultLabel.Size = UDim2.new(1, -32, 0, 26)
ascMultLabel.BackgroundTransparency = 1
ascMultLabel.Font = FONT
ascMultLabel.TextSize = 20
ascMultLabel.TextColor3 = Color3.fromRGB(255, 200, 40)
ascMultLabel.Text = "Permanent bonus: x1"
ascMultLabel.ZIndex = 1
ascMultLabel.Parent = ascendPanel

-- Requirement for the next Ascend.
local ascReqLabel = Instance.new("TextLabel")
ascReqLabel.AnchorPoint = Vector2.new(0.5, 0)
ascReqLabel.Position = UDim2.new(0.5, 0, 0, 122)
ascReqLabel.Size = UDim2.new(1, -40, 0, 24)
ascReqLabel.BackgroundTransparency = 1
ascReqLabel.Font = FONT
ascReqLabel.TextSize = 16
ascReqLabel.TextColor3 = Color3.fromRGB(210, 200, 230)
ascReqLabel.TextWrapped = true
ascReqLabel.Text = "Next Ascend needs 10,000 Spirit Power"
ascReqLabel.ZIndex = 1
ascReqLabel.Parent = ascendPanel

-- ASCEND button.
local ascendButton = Instance.new("TextButton")
ascendButton.AnchorPoint = Vector2.new(0.5, 1)
ascendButton.Position = UDim2.new(0.5, 0, 1, -16)
ascendButton.Size = UDim2.new(1, -40, 0, 56)
ascendButton.Font = FONT
ascendButton.TextSize = 24
ascendButton.TextStrokeTransparency = 0.6
ascendButton.AutoButtonColor = false
ascendButton.Text = "ASCEND"
ascendButton.ZIndex = 1
ascendButton.Parent = ascendPanel
round(ascendButton, 14)
stroke(ascendButton, Color3.fromRGB(150, 120, 30), 2)

-- Latest authoritative Ascend state from the server.
local ascendData = { count = 0, requirement = 0, multiplier = 1 }

local function renderAscend()
	local count = ascendData.count
	ascRankLabel.Text = getRankTitle(count)
	ascRankLabel.TextColor3 = getRankColor(count)
	ascCountLabel.Text = "Ascensions: " .. count
	ascMultLabel.Text = "Permanent bonus: " .. fmtMult(ascendData.multiplier)
	ascReqLabel.Text = "Next Ascend needs " .. commafy(ascendData.requirement) .. " Spirit Power"

	-- Button is enabled only when the player meets the requirement (checked live
	-- against the Spirit Power value); otherwise it shows locked + the cost.
	local ready = spiritPowerValue.Value >= ascendData.requirement
	if ready then
		ascendButton.Text = "ASCEND"
		ascendButton.BackgroundColor3 = ASCEND_READY_COLOR
		ascendButton.TextColor3 = Color3.fromRGB(60, 40, 0)
		ascendButton.AutoButtonColor = true
		ascendButton.Active = true
	else
		ascendButton.Text = "LOCKED  •  need " .. commafy(ascendData.requirement)
		ascendButton.BackgroundColor3 = ASCEND_LOCKED_COLOR
		ascendButton.TextColor3 = Color3.fromRGB(225, 220, 235)
		ascendButton.AutoButtonColor = false
		ascendButton.Active = false
	end
end

-- Ask the server for the latest Ascend state, then redraw the panel + HUD rank.
local function refreshAscend()
	ascendData = getAscendStateFunc:InvokeServer()
	renderAscend()
	updateHudRank(ascendData.count)
end

-- Ascending: the server validates and returns the new state (unchanged if the
-- requirement wasn't met). After a successful Ascend, Zen was reset and its cap
-- raised, so we refresh that panel too.
ascendButton.Activated:Connect(function()
	if not ascendButton.Active then
		return
	end
	ascendData = ascendFunc:InvokeServer()
	renderAscend()
	updateHudRank(ascendData.count)
	refreshZen()
	-- The server reset Spirit Power to 0, which fires the .Changed handler below
	-- and updates the HUD counter automatically.
end)

--------------------------------------------------------------------------------
-- Live wiring
--------------------------------------------------------------------------------

-- Spirit Power changing updates the HUD counter and re-evaluates whether the
-- ASCEND button should now be unlocked.
spiritPowerValue.Changed:Connect(function()
	updateHudSpirit()
	renderAscend()
end)

-- Refresh the Ascend panel whenever the shop opens, too.
openShopEvent.OnClientEvent:Connect(refreshAscend)

-- Initial draw.
updateHudSpirit()
refreshAscend()

--------------------------------------------------------------------------------
-- Soul Jar tab (storage cap) panel
--------------------------------------------------------------------------------

local soulJarPanel = panels["Soul Jar"]
local JAR_BUY_COLOR = Color3.fromRGB(70, 200, 90) -- green when affordable
local JAR_LOCKED_COLOR = Color3.fromRGB(110, 100, 140) -- muted when unaffordable / maxed

-- Current jar name (big).
local jarNameLabel = Instance.new("TextLabel")
jarNameLabel.AnchorPoint = Vector2.new(0.5, 0)
jarNameLabel.Position = UDim2.new(0.5, 0, 0, 12)
jarNameLabel.Size = UDim2.new(1, -32, 0, 46)
jarNameLabel.BackgroundTransparency = 1
jarNameLabel.Font = FONT
jarNameLabel.TextSize = 36
jarNameLabel.TextColor3 = Color3.fromRGB(255, 200, 40)
jarNameLabel.TextStrokeTransparency = 0.6
jarNameLabel.Text = "Clay Jar"
jarNameLabel.ZIndex = 1
jarNameLabel.Parent = soulJarPanel

-- Current capacity.
local jarCapLabel = Instance.new("TextLabel")
jarCapLabel.AnchorPoint = Vector2.new(0.5, 0)
jarCapLabel.Position = UDim2.new(0.5, 0, 0, 62)
jarCapLabel.Size = UDim2.new(1, -32, 0, 26)
jarCapLabel.BackgroundTransparency = 1
jarCapLabel.Font = FONT
jarCapLabel.TextSize = 20
jarCapLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
jarCapLabel.Text = "Holds 1,000 Spirit Power"
jarCapLabel.ZIndex = 1
jarCapLabel.Parent = soulJarPanel

-- Next jar info.
local jarNextLabel = Instance.new("TextLabel")
jarNextLabel.AnchorPoint = Vector2.new(0.5, 0)
jarNextLabel.Position = UDim2.new(0.5, 0, 0, 96)
jarNextLabel.Size = UDim2.new(1, -40, 0, 44)
jarNextLabel.BackgroundTransparency = 1
jarNextLabel.Font = FONT
jarNextLabel.TextSize = 18
jarNextLabel.TextColor3 = Color3.fromRGB(210, 200, 230)
jarNextLabel.TextWrapped = true
jarNextLabel.Text = "Next: Jade Jar (10,000)"
jarNextLabel.ZIndex = 1
jarNextLabel.Parent = soulJarPanel

-- BUY button.
local buyJarButton = Instance.new("TextButton")
buyJarButton.AnchorPoint = Vector2.new(0.5, 1)
buyJarButton.Position = UDim2.new(0.5, 0, 1, -16)
buyJarButton.Size = UDim2.new(1, -40, 0, 56)
buyJarButton.Font = FONT
buyJarButton.TextSize = 22
buyJarButton.TextStrokeTransparency = 0.6
buyJarButton.AutoButtonColor = false
buyJarButton.Text = "BUY"
buyJarButton.ZIndex = 1
buyJarButton.Parent = soulJarPanel
round(buyJarButton, 14)
stroke(buyJarButton, Color3.fromRGB(40, 120, 55), 2)

-- Latest authoritative Soul Jar state from the server. Initialized with complete
-- placeholder values (not just partial) so the live .Changed handler can never
-- read a nil field during the first refresh's network round-trip.
local soulJarData = {
	currentName = "Clay Jar",
	currentCapacity = 1000,
	maxed = false,
	nextName = "Jade Jar",
	nextCapacity = 10000,
	nextCost = 1000,
}

local function renderSoulJar()
	jarNameLabel.Text = soulJarData.currentName
	jarCapLabel.Text = "Holds " .. commafy(soulJarData.currentCapacity) .. " Spirit Power"

	-- Keep the HUD "held / cap" readout in sync with the current jar.
	currentJarCapacity = soulJarData.currentCapacity
	updateHudSpirit()

	if soulJarData.maxed then
		jarNextLabel.Text = "Maximum jar reached!"
		buyJarButton.Text = "MAX TIER"
		buyJarButton.BackgroundColor3 = JAR_LOCKED_COLOR
		buyJarButton.TextColor3 = Color3.fromRGB(225, 220, 235)
		buyJarButton.AutoButtonColor = false
		buyJarButton.Active = false
		return
	end

	jarNextLabel.Text = "Next: " .. soulJarData.nextName
		.. "  (holds " .. commafy(soulJarData.nextCapacity) .. ")"

	-- Enabled only when affordable (checked live against Spirit Power).
	local affordable = spiritPowerValue.Value >= soulJarData.nextCost
	buyJarButton.Text = "BUY  •  " .. commafy(soulJarData.nextCost) .. " Spirit Power"
	if affordable then
		buyJarButton.BackgroundColor3 = JAR_BUY_COLOR
		buyJarButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		buyJarButton.AutoButtonColor = true
		buyJarButton.Active = true
	else
		buyJarButton.BackgroundColor3 = JAR_LOCKED_COLOR
		buyJarButton.TextColor3 = Color3.fromRGB(225, 220, 235)
		buyJarButton.AutoButtonColor = false
		buyJarButton.Active = false
	end
end

-- Ask the server for the latest Soul Jar state, then redraw.
local function refreshSoulJar()
	soulJarData = getSoulJarStateFunc:InvokeServer()
	renderSoulJar()
end

-- Buying: the server validates and returns the resulting state (unchanged if the
-- upgrade was rejected for being maxed or too expensive), which we render.
buyJarButton.Activated:Connect(function()
	if not buyJarButton.Active then
		return
	end
	soulJarData = buySoulJarFunc:InvokeServer()
	renderSoulJar()
end)

-- Spirit Power changing re-evaluates whether the BUY button is affordable (and
-- updates the HUD "held / cap" readout via renderSoulJar -> updateHudSpirit).
spiritPowerValue.Changed:Connect(renderSoulJar)

-- Refresh whenever the shop opens, plus an initial draw.
openShopEvent.OnClientEvent:Connect(refreshSoulJar)
refreshSoulJar()
