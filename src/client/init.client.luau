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
title.Font = Enum.Font.GothamBold
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
closeButton.Font = Enum.Font.GothamBold
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
	button.Font = Enum.Font.GothamBold
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

	if name ~= "Zen" then
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.fromScale(1, 1)
		placeholder.BackgroundTransparency = 1
		placeholder.Text = name .. " upgrades coming soon"
		placeholder.Font = Enum.Font.GothamBold
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
multLabel.Font = Enum.Font.GothamBold
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
levelLabel.Font = Enum.Font.GothamBold
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
descLabel.Font = Enum.Font.Gotham
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
buyButton.Font = Enum.Font.GothamBold
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
