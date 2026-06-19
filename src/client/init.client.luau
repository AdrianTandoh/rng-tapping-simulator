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
-- Ascend moved out to its own world pad/popup, so the shop is just Zen + Soul Jar.
local TABS = { "Zen", "Soul Jar" }
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
-- Popup manager: only ONE popup open at a time
--------------------------------------------------------------------------------
-- Every popup (Shop, Ascend, Group Rewards, and any future ones) registers its
-- ScreenGui here. Opening one through PopupManager.open() automatically closes
-- every other registered popup, so two can never be open at once. Adding a new
-- popup later is just: register(gui) once, then open(gui) / close(gui).
local GuiService = game:GetService("GuiService")

local PopupManager = {}
PopupManager._registered = {} -- list of ScreenGuis

function PopupManager.register(gui)
	table.insert(PopupManager._registered, gui)
end

function PopupManager.open(gui)
	-- Enable the requested popup, disable all the others.
	for _, other in ipairs(PopupManager._registered) do
		other.Enabled = (other == gui)
	end
end

function PopupManager.close(gui)
	gui.Enabled = false
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
PopupManager.register(screenGui)

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

	if name ~= "Zen" and name ~= "Soul Jar" then
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
	PopupManager.open(screenGui) -- closes any other open popup
end

local function closeShop()
	PopupManager.close(screenGui)
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
-- Chi is the second currency: a replicated IntValue parented to the Player (not in
-- leaderstats). The server owns it; we only watch it to drive the HUD counter.
local chiValue = player:WaitForChild("Chi")

local getAscendStateFunc = ReplicatedStorage:WaitForChild("GetAscendState")
local ascendFunc = ReplicatedStorage:WaitForChild("Ascend")
local openAscendEvent = ReplicatedStorage:WaitForChild("OpenAscend")
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

-- The whole HUD is a centered vertical stack: rank title, then the Spirit Power
-- "vessel" bar, then the Chi bank counter. A UIListLayout keeps the three pieces
-- tidy and non-overlapping regardless of text length.
local hudStack = Instance.new("Frame")
hudStack.Name = "Stack"
hudStack.AnchorPoint = Vector2.new(0.5, 0)
hudStack.Position = UDim2.new(0.5, 0, 0, 12)
hudStack.Size = UDim2.fromOffset(440, 150)
hudStack.BackgroundTransparency = 1
hudStack.Parent = hud

local hudLayout = Instance.new("UIListLayout")
hudLayout.FillDirection = Enum.FillDirection.Vertical
hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
hudLayout.SortOrder = Enum.SortOrder.LayoutOrder
hudLayout.Padding = UDim.new(0, 8)
hudLayout.Parent = hudStack

-- (1) Big COLOR-CODED rank title at the top of the stack.
local rankDisplay = Instance.new("TextLabel")
rankDisplay.Name = "RankDisplay"
rankDisplay.LayoutOrder = 1
rankDisplay.Size = UDim2.fromOffset(360, 38)
rankDisplay.BackgroundTransparency = 1
rankDisplay.Font = FONT
rankDisplay.TextScaled = true
rankDisplay.TextStrokeTransparency = 0.45
rankDisplay.TextStrokeColor3 = Color3.fromRGB(20, 20, 28)
rankDisplay.Text = "Seeker"
rankDisplay.Parent = hudStack

local rankCap = Instance.new("UITextSizeConstraint")
rankCap.MaxTextSize = 34
rankCap.Parent = rankDisplay

-- (2) SILVER Spirit Power vessel BAR. A dark rounded track with a silver fill that
-- grows toward the current Soul Jar capacity, plus the "held / cap" text on top —
-- so the player can literally see their vessel filling ("getting full, time to
-- convert"). Keeps the silver styling of the old counter.
local spiritBar = Instance.new("Frame")
spiritBar.Name = "SpiritBar"
spiritBar.LayoutOrder = 2
spiritBar.Size = UDim2.fromOffset(420, 46)
spiritBar.BackgroundColor3 = Color3.fromRGB(38, 40, 52) -- dark track behind the fill
spiritBar.Parent = hudStack
round(spiritBar, 14)
stroke(spiritBar, Color3.fromRGB(120, 126, 140), 2) -- silver rim

-- The fill. Its width scales 0..1 with held/cap; its own rounded corners match the
-- track so the left end stays clean at any fill level.
local spiritFill = Instance.new("Frame")
spiritFill.Name = "Fill"
spiritFill.AnchorPoint = Vector2.new(0, 0.5)
spiritFill.Position = UDim2.fromScale(0, 0.5)
spiritFill.Size = UDim2.fromScale(0, 1)
spiritFill.BackgroundColor3 = Color3.fromRGB(190, 196, 210) -- silver
spiritFill.BorderSizePixel = 0
spiritFill.Parent = spiritBar
round(spiritFill, 14)

-- Subtle vertical sheen so the silver fill reads as a polished metal vessel.
local fillGradient = Instance.new("UIGradient")
fillGradient.Rotation = 90
fillGradient.Color = ColorSequence.new(
	Color3.fromRGB(228, 232, 242),
	Color3.fromRGB(148, 154, 170)
)
fillGradient.Parent = spiritFill

-- "held / cap" text, centered over the bar. White with a strong stroke so it stays
-- readable over both the dark empty track and the light silver fill.
local spiritText = Instance.new("TextLabel")
spiritText.Name = "Text"
spiritText.Size = UDim2.fromScale(1, 1)
spiritText.BackgroundTransparency = 1
spiritText.Font = FONT
spiritText.TextScaled = true
spiritText.Text = "0 / 1,000"
spiritText.TextColor3 = Color3.fromRGB(245, 247, 250)
spiritText.TextStrokeTransparency = 0.35
spiritText.TextStrokeColor3 = Color3.fromRGB(28, 30, 40)
spiritText.ZIndex = 2
spiritText.Parent = spiritBar

local spiritTextPad = Instance.new("UIPadding")
spiritTextPad.PaddingTop = UDim.new(0, 8)
spiritTextPad.PaddingBottom = UDim.new(0, 8)
spiritTextPad.Parent = spiritText

local spiritCap = Instance.new("UITextSizeConstraint")
spiritCap.MaxTextSize = 24
spiritCap.Parent = spiritText

-- (3) Chi bank COUNTER. A distinct jade pill (Spirit Power = silver, Chi = jade)
-- so the two currencies never read as the same thing. This is the spendable bank.
local chiCounter = Instance.new("Frame")
chiCounter.Name = "ChiCounter"
chiCounter.LayoutOrder = 3
chiCounter.Size = UDim2.fromOffset(220, 36)
chiCounter.BackgroundColor3 = Color3.fromRGB(30, 56, 48) -- deep jade
chiCounter.Parent = hudStack
round(chiCounter, 12)
stroke(chiCounter, Color3.fromRGB(90, 210, 160), 2) -- jade-green rim

local chiLabel = Instance.new("TextLabel")
chiLabel.Name = "Text"
chiLabel.Size = UDim2.fromScale(1, 1)
chiLabel.BackgroundTransparency = 1
chiLabel.Font = FONT
chiLabel.TextScaled = true
chiLabel.Text = "0 Chi"
chiLabel.TextColor3 = Color3.fromRGB(150, 240, 200) -- jade
chiLabel.TextStrokeTransparency = 0.5
chiLabel.TextStrokeColor3 = Color3.fromRGB(12, 28, 22)
chiLabel.Parent = chiCounter

local chiTextPad = Instance.new("UIPadding")
chiTextPad.PaddingTop = UDim.new(0, 6)
chiTextPad.PaddingBottom = UDim.new(0, 6)
chiTextPad.Parent = chiLabel

local chiCap = Instance.new("UITextSizeConstraint")
chiCap.MaxTextSize = 22
chiCap.Parent = chiLabel

-- Current Soul Jar capacity, kept in sync from the server; the bar fills toward it.
-- Defaults to the Clay Jar until the server reports in.
local currentJarCapacity = 1000

local function updateHudSpirit()
	local held = spiritPowerValue.Value
	local cap = currentJarCapacity
	-- Fraction of the vessel that's full (guard against a 0/None capacity).
	local frac = cap > 0 and math.clamp(held / cap, 0, 1) or 0
	spiritFill.Size = UDim2.fromScale(frac, 1)
	spiritText.Text = commafy(held) .. " / " .. commafy(cap)
end

local function updateHudChi()
	chiLabel.Text = commafy(chiValue.Value) .. " Chi"
end

local function updateHudRank(count)
	rankDisplay.Text = getRankTitle(count)
	rankDisplay.TextColor3 = getRankColor(count)
end

-- Chi is read-only on the client: keep the counter in sync whenever the server
-- changes it, plus an initial draw.
chiValue.Changed:Connect(updateHudChi)
updateHudChi()

--------------------------------------------------------------------------------
-- Ascend popup (prestige — standalone, opened by the cyan Ascend world pad)
--------------------------------------------------------------------------------
-- Moved out of the shop into its own popup. The Ascend mechanics/logic are
-- unchanged; only the trigger moved (the Ascend pad fires OpenAscend).

local ASCEND_READY_COLOR = Color3.fromRGB(255, 200, 40) -- gold when ready
local ASCEND_LOCKED_COLOR = Color3.fromRGB(110, 100, 140) -- muted when locked
local ASCEND_ACCENT = Color3.fromRGB(40, 220, 220) -- cyan/teal, matches the pad

-- Built once, hidden, toggled via the popup manager (like the shop popup).
local ascendGui = Instance.new("ScreenGui")
ascendGui.Name = "AscendGui"
ascendGui.ResetOnSpawn = false
ascendGui.IgnoreGuiInset = true
ascendGui.Enabled = false
ascendGui.Parent = playerGui
PopupManager.register(ascendGui)

local ascendShadow = Instance.new("Frame")
ascendShadow.Name = "Shadow"
ascendShadow.AnchorPoint = Vector2.new(0.5, 0.5)
ascendShadow.Position = UDim2.new(0.5, 0, 0.5, 6)
ascendShadow.Size = UDim2.fromOffset(540, 420)
ascendShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ascendShadow.BackgroundTransparency = 0.6
ascendShadow.ZIndex = 0
ascendShadow.Parent = ascendGui
round(ascendShadow, 22)

local ascendMain = Instance.new("Frame")
ascendMain.Name = "Main"
ascendMain.AnchorPoint = Vector2.new(0.5, 0.5)
ascendMain.Position = UDim2.fromScale(0.5, 0.5)
ascendMain.Size = UDim2.fromOffset(520, 400)
ascendMain.BackgroundColor3 = Color3.fromRGB(45, 35, 70)
ascendMain.ZIndex = 1
ascendMain.Parent = ascendGui
round(ascendMain, 20)
stroke(ascendMain, ASCEND_ACCENT, 3) -- cyan outline

local ascendHeader = Instance.new("Frame")
ascendHeader.Name = "Header"
ascendHeader.Size = UDim2.new(1, 0, 0, 64)
ascendHeader.BackgroundColor3 = Color3.fromRGB(30, 120, 130) -- teal
ascendHeader.ZIndex = 2
ascendHeader.Parent = ascendMain
round(ascendHeader, 20)

local ascendHeaderCover = Instance.new("Frame")
ascendHeaderCover.Size = UDim2.new(1, 0, 0, 24)
ascendHeaderCover.Position = UDim2.new(0, 0, 1, -24)
ascendHeaderCover.BackgroundColor3 = ascendHeader.BackgroundColor3
ascendHeaderCover.BorderSizePixel = 0
ascendHeaderCover.ZIndex = 2
ascendHeaderCover.Parent = ascendHeader

local ascendHeaderTitle = Instance.new("TextLabel")
ascendHeaderTitle.Size = UDim2.new(1, -80, 1, 0)
ascendHeaderTitle.Position = UDim2.fromOffset(20, 0)
ascendHeaderTitle.BackgroundTransparency = 1
ascendHeaderTitle.Text = "ASCEND"
ascendHeaderTitle.Font = FONT
ascendHeaderTitle.TextSize = 30
ascendHeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
ascendHeaderTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
ascendHeaderTitle.TextStrokeTransparency = 0.6
ascendHeaderTitle.ZIndex = 3
ascendHeaderTitle.Parent = ascendHeader

local ascendCloseButton = Instance.new("TextButton")
ascendCloseButton.Name = "Close"
ascendCloseButton.AnchorPoint = Vector2.new(1, 0.5)
ascendCloseButton.Position = UDim2.new(1, -16, 0.5, 0)
ascendCloseButton.Size = UDim2.fromOffset(40, 40)
ascendCloseButton.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
ascendCloseButton.Text = "X"
ascendCloseButton.Font = FONT
ascendCloseButton.TextSize = 24
ascendCloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ascendCloseButton.ZIndex = 3
ascendCloseButton.AutoButtonColor = true
ascendCloseButton.Parent = ascendHeader
round(ascendCloseButton, 12)
stroke(ascendCloseButton, Color3.fromRGB(150, 30, 30), 2)

local ascendContent = Instance.new("Frame")
ascendContent.Name = "Content"
ascendContent.Size = UDim2.new(1, -32, 1, -96)
ascendContent.Position = UDim2.fromOffset(16, 80)
ascendContent.BackgroundColor3 = Color3.fromRGB(60, 50, 95)
ascendContent.ZIndex = 1
ascendContent.Parent = ascendMain
round(ascendContent, 16)
stroke(ascendContent, Color3.fromRGB(70, 130, 140), 2)

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
ascRankLabel.Parent = ascendContent

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
ascCountLabel.Parent = ascendContent

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
ascMultLabel.Parent = ascendContent

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
ascReqLabel.Parent = ascendContent

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
ascendButton.Parent = ascendContent
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

-- Open / close wiring for the standalone Ascend popup.
local function openAscend()
	refreshAscend() -- pull fresh state every time the pad is touched
	PopupManager.open(ascendGui) -- closes any other open popup
end

ascendCloseButton.Activated:Connect(function()
	PopupManager.close(ascendGui)
end)

-- The server tells us to open this popup when the player touches the Ascend pad.
openAscendEvent.OnClientEvent:Connect(openAscend)

-- Initial draw (HUD rank + panel state), so the HUD is correct before first open.
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

--------------------------------------------------------------------------------
-- Group Rewards popup (standalone — opened by the Group Rewards world pad)
--------------------------------------------------------------------------------
-- This is its OWN popup (not a shop tab). The Group Rewards pad in the world fires
-- the OpenGroupRewards RemoteEvent, which shows this popup. The server remains the
-- only authority on membership + whether the reward was already claimed; this UI
-- just renders the state it returns and asks it to claim.

local openGroupRewardsEvent = ReplicatedStorage:WaitForChild("OpenGroupRewards")
local getGroupRewardStateFunc = ReplicatedStorage:WaitForChild("GetGroupRewardState")
local claimGroupRewardFunc = ReplicatedStorage:WaitForChild("ClaimGroupReward")

local GROUP_CLAIM_COLOR = Color3.fromRGB(70, 200, 90) -- green: ready to claim
local GROUP_CHECK_COLOR = Color3.fromRGB(90, 170, 255) -- blue: join / re-check
local GROUP_DONE_COLOR = Color3.fromRGB(255, 200, 40) -- gold: already claimed
local GROUP_OFF_COLOR = Color3.fromRGB(110, 100, 140) -- muted: not configured

-- Built once, hidden, and toggled — exactly like the shop popup. Re-touching the
-- pad while it's open simply re-shows it (harmless).
local groupGui = Instance.new("ScreenGui")
groupGui.Name = "GroupRewardsGui"
groupGui.ResetOnSpawn = false -- survive respawns
groupGui.IgnoreGuiInset = true
groupGui.Enabled = false -- hidden until the player touches the pad
groupGui.Parent = playerGui
PopupManager.register(groupGui)

-- Soft drop shadow behind the popup.
local groupShadow = Instance.new("Frame")
groupShadow.Name = "Shadow"
groupShadow.AnchorPoint = Vector2.new(0.5, 0.5)
groupShadow.Position = UDim2.new(0.5, 0, 0.5, 6)
groupShadow.Size = UDim2.fromOffset(540, 420)
groupShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
groupShadow.BackgroundTransparency = 0.6
groupShadow.ZIndex = 0
groupShadow.Parent = groupGui
round(groupShadow, 22)

-- Main popup frame (matches the shop's deep-violet + gold-outline styling).
local groupMain = Instance.new("Frame")
groupMain.Name = "Main"
groupMain.AnchorPoint = Vector2.new(0.5, 0.5)
groupMain.Position = UDim2.fromScale(0.5, 0.5)
groupMain.Size = UDim2.fromOffset(520, 400)
groupMain.BackgroundColor3 = Color3.fromRGB(45, 35, 70)
groupMain.ZIndex = 1
groupMain.Parent = groupGui
round(groupMain, 20)
stroke(groupMain, Color3.fromRGB(160, 90, 245), 3) -- purple outline (matches the pad)

-- Header bar (purple to echo the monument).
local groupHeader = Instance.new("Frame")
groupHeader.Name = "Header"
groupHeader.Size = UDim2.new(1, 0, 0, 64)
groupHeader.BackgroundColor3 = Color3.fromRGB(120, 80, 200)
groupHeader.ZIndex = 2
groupHeader.Parent = groupMain
round(groupHeader, 20)

-- Cover the header's lower rounded corners so it blends into the body.
local groupHeaderCover = Instance.new("Frame")
groupHeaderCover.Size = UDim2.new(1, 0, 0, 24)
groupHeaderCover.Position = UDim2.new(0, 0, 1, -24)
groupHeaderCover.BackgroundColor3 = groupHeader.BackgroundColor3
groupHeaderCover.BorderSizePixel = 0
groupHeaderCover.ZIndex = 2
groupHeaderCover.Parent = groupHeader

local groupHeaderTitle = Instance.new("TextLabel")
groupHeaderTitle.Size = UDim2.new(1, -80, 1, 0)
groupHeaderTitle.Position = UDim2.fromOffset(20, 0)
groupHeaderTitle.BackgroundTransparency = 1
groupHeaderTitle.Text = "GROUP REWARDS"
groupHeaderTitle.Font = FONT
groupHeaderTitle.TextSize = 30
groupHeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
groupHeaderTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
groupHeaderTitle.TextStrokeTransparency = 0.6
groupHeaderTitle.ZIndex = 3
groupHeaderTitle.Parent = groupHeader

-- Close ("X") button.
local groupCloseButton = Instance.new("TextButton")
groupCloseButton.Name = "Close"
groupCloseButton.AnchorPoint = Vector2.new(1, 0.5)
groupCloseButton.Position = UDim2.new(1, -16, 0.5, 0)
groupCloseButton.Size = UDim2.fromOffset(40, 40)
groupCloseButton.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
groupCloseButton.Text = "X"
groupCloseButton.Font = FONT
groupCloseButton.TextSize = 24
groupCloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
groupCloseButton.ZIndex = 3
groupCloseButton.AutoButtonColor = true
groupCloseButton.Parent = groupHeader
round(groupCloseButton, 12)
stroke(groupCloseButton, Color3.fromRGB(150, 30, 30), 2)

-- Body area below the header, where the reward content lives.
local groupContent = Instance.new("Frame")
groupContent.Name = "Content"
groupContent.Size = UDim2.new(1, -32, 1, -96)
groupContent.Position = UDim2.fromOffset(16, 80)
groupContent.BackgroundColor3 = Color3.fromRGB(60, 50, 95)
groupContent.ZIndex = 1
groupContent.Parent = groupMain
round(groupContent, 16)
stroke(groupContent, Color3.fromRGB(120, 90, 170), 2)

-- Small heading above the reward list.
local groupBundleHeading = Instance.new("TextLabel")
groupBundleHeading.AnchorPoint = Vector2.new(0.5, 0)
groupBundleHeading.Position = UDim2.new(0.5, 0, 0, 10)
groupBundleHeading.Size = UDim2.new(1, -32, 0, 32)
groupBundleHeading.BackgroundTransparency = 1
groupBundleHeading.Font = FONT
groupBundleHeading.TextSize = 24
groupBundleHeading.TextColor3 = Color3.fromRGB(255, 200, 40)
groupBundleHeading.TextStrokeTransparency = 0.6
groupBundleHeading.Text = "Reward Bundle"
groupBundleHeading.ZIndex = 1
groupBundleHeading.Parent = groupContent

-- The reward bundle, listed (built from the server's reward summary).
local groupRewards = Instance.new("TextLabel")
groupRewards.AnchorPoint = Vector2.new(0.5, 0)
groupRewards.Position = UDim2.new(0.5, 0, 0, 46)
groupRewards.Size = UDim2.new(1, -36, 0, 96)
groupRewards.BackgroundTransparency = 1
groupRewards.Font = FONT
groupRewards.TextSize = 18
groupRewards.TextYAlignment = Enum.TextYAlignment.Top
groupRewards.TextColor3 = Color3.fromRGB(235, 230, 245)
groupRewards.TextWrapped = true
groupRewards.Text = ""
groupRewards.ZIndex = 1
groupRewards.Parent = groupContent

-- Small hint shown only when the player isn't in the group yet.
local groupHint = Instance.new("TextLabel")
groupHint.Name = "Hint"
groupHint.AnchorPoint = Vector2.new(0.5, 1)
groupHint.Position = UDim2.new(0.5, 0, 1, -128)
groupHint.Size = UDim2.new(1, -36, 0, 32)
groupHint.BackgroundTransparency = 1
groupHint.Font = FONT
groupHint.TextSize = 14
groupHint.TextColor3 = Color3.fromRGB(180, 175, 200)
groupHint.TextWrapped = true
groupHint.Visible = false
groupHint.Text = "Already joined? You may need to rejoin the game for it to register."
groupHint.ZIndex = 1
groupHint.Parent = groupContent

-- Status / instructions line.
local groupStatus = Instance.new("TextLabel")
groupStatus.AnchorPoint = Vector2.new(0.5, 1)
groupStatus.Position = UDim2.new(0.5, 0, 1, -80)
groupStatus.Size = UDim2.new(1, -36, 0, 44)
groupStatus.BackgroundTransparency = 1
groupStatus.Font = FONT
groupStatus.TextSize = 16
groupStatus.TextColor3 = Color3.fromRGB(210, 200, 230)
groupStatus.TextWrapped = true
groupStatus.Text = ""
groupStatus.ZIndex = 1
groupStatus.Parent = groupContent

-- Adaptive action button (claim / re-check / claimed / coming soon).
local groupButton = Instance.new("TextButton")
groupButton.AnchorPoint = Vector2.new(0.5, 1)
groupButton.Position = UDim2.new(0.5, 0, 1, -16)
groupButton.Size = UDim2.new(1, -40, 0, 56)
groupButton.Font = FONT
groupButton.TextSize = 22
groupButton.TextStrokeTransparency = 0.6
groupButton.AutoButtonColor = false
groupButton.Text = "CLAIM"
groupButton.ZIndex = 1
groupButton.Parent = groupContent
round(groupButton, 14)
stroke(groupButton, Color3.fromRGB(40, 120, 55), 2)

-- Latest authoritative group-reward state from the server.
local groupData = {
	configured = false,
	groupId = 0,
	inGroup = false,
	claimed = false,
	reward = { autoClicker = true, spiritPower = 0, zenLevels = 0 },
}

-- Build the bundle list from whatever rewards the server reports.
local function describeRewards(reward)
	local lines = {}
	if reward.autoClicker then
		table.insert(lines, "• Permanent Auto-Clicker")
	end
	if reward.spiritPower and reward.spiritPower > 0 then
		table.insert(lines, "• " .. commafy(reward.spiritPower) .. " Spirit Power")
	end
	if reward.zenLevels and reward.zenLevels > 0 then
		local plural = reward.zenLevels == 1 and " Zen Level" or " Zen Levels"
		table.insert(lines, "• +" .. reward.zenLevels .. plural)
	end
	return table.concat(lines, "\n")
end

-- Render one of the three real states: not-in-group, in-group (redeemable), or
-- already-claimed. (No "coming soon" — that placeholder is gone.)
local function renderGroup()
	groupRewards.Text = describeRewards(groupData.reward)

	if groupData.claimed then
		-- (c) Already claimed: show the claimed state, no button.
		groupHint.Visible = false
		groupStatus.Text = "Claimed! Your auto-clicker is active. Thanks for joining \u{2764}"
		groupButton.Visible = false
	elseif groupData.inGroup then
		-- (b) Member, not claimed: green redeem button.
		groupHint.Visible = false
		groupStatus.Text = "You're a member \u{2014} redeem your reward bundle!"
		groupButton.Visible = true
		groupButton.Text = "REDEEM REWARDS"
		groupButton.BackgroundColor3 = GROUP_CLAIM_COLOR
		groupButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		groupButton.AutoButtonColor = true
		groupButton.Active = true
	else
		-- (a) Not in group: join button + the "already joined?" rejoin hint.
		groupHint.Visible = true
		groupStatus.Text = "Join our Roblox group to unlock the reward bundle!"
		groupButton.Visible = true
		groupButton.Text = "JOIN GROUP"
		groupButton.BackgroundColor3 = GROUP_CHECK_COLOR
		groupButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		groupButton.AutoButtonColor = true
		groupButton.Active = true
	end
end

-- Ask the server for the latest group-reward state, then redraw.
local function refreshGroup()
	groupData = getGroupRewardStateFunc:InvokeServer()
	renderGroup()
end

-- Trigger Roblox's group-join flow. NOTE: Roblox has no guaranteed in-experience
-- "join group" prompt API, so we open the group's web page (GuiService is gated on
-- some clients, hence pcall) and re-check membership shortly after. The on-screen
-- hint reminds the player they may need to rejoin for membership to register.
local function attemptJoinGroup()
	local url = "https://www.roblox.com/groups/" .. tostring(groupData.groupId)
	local opened = pcall(function()
		GuiService:OpenBrowserWindow(url)
	end)
	if not opened then
		groupStatus.Text = "Find our group (#" .. tostring(groupData.groupId)
			.. ") in the Roblox app, join, then come back."
	end
	-- Re-check membership a moment later (covers the no-rejoin-needed case).
	task.delay(2, refreshGroup)
end

-- Button: redeem if a member, otherwise start the join flow.
groupButton.Activated:Connect(function()
	if not groupButton.Active then
		return
	end

	if groupData.claimed then
		return -- nothing to do; button is hidden anyway
	elseif groupData.inGroup then
		-- Redeem: the server RE-VERIFIES membership + not-already-claimed, grants the
		-- bundle, and returns { ok, message, state }.
		local result = claimGroupRewardFunc:InvokeServer()
		groupData = result.state
		renderGroup()
		groupStatus.Text = result.message
		if result.ok then
			-- The claim may have granted a Zen level (Spirit Power changes are picked
			-- up by the .Changed handler). Refresh the Zen panel to match.
			refreshZen()
		end
	else
		attemptJoinGroup()
	end
end)

-- Open / close wiring (re-checks membership every open, as required).
local function openGroupRewards()
	refreshGroup() -- pull fresh state (incl. membership) every time the pad is touched
	PopupManager.open(groupGui) -- closes any other open popup
end

groupCloseButton.Activated:Connect(function()
	PopupManager.close(groupGui)
end)

-- The server tells us to open this popup when the player touches the Group pad.
openGroupRewardsEvent.OnClientEvent:Connect(openGroupRewards)

-- Prime the state once at startup so the first open is instant.
refreshGroup()

--------------------------------------------------------------------------------
-- Meditation Altar: convert Spirit Power -> Chi (with feedback "juice")
--------------------------------------------------------------------------------
-- The server fires AltarTouched when the player steps on the altar; we then ask the
-- server (the only authority) to convert. The HUD updates itself via the existing
-- Spirit Power / Chi .Changed handlers (the bar empties, the Chi counter rises), so
-- here we only add a brief floating-text toast for feedback. The toast is NOT a
-- PopupManager popup — it's transient, fire-and-forget juice that never blocks or
-- closes the shop/ascend/group popups.

local TweenService = game:GetService("TweenService")
local altarTouchedEvent = ReplicatedStorage:WaitForChild("AltarTouched")
local convertSpiritToChiFunc = ReplicatedStorage:WaitForChild("ConvertSpiritToChi")

local CONVERT_OK_COLOR = Color3.fromRGB(120, 240, 170) -- jade green: success
local CONVERT_NONE_COLOR = Color3.fromRGB(225, 215, 240) -- soft lilac: nothing to convert

-- Its own ScreenGui on top so the toast floats above the HUD and any popup.
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "AltarToast"
toastGui.ResetOnSpawn = false
toastGui.IgnoreGuiInset = true
toastGui.DisplayOrder = 50
toastGui.Parent = playerGui

local toastLabel = Instance.new("TextLabel")
toastLabel.Name = "Toast"
toastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
toastLabel.Size = UDim2.fromOffset(540, 70)
toastLabel.BackgroundTransparency = 1
toastLabel.Font = FONT
toastLabel.TextScaled = true
toastLabel.TextColor3 = CONVERT_OK_COLOR
toastLabel.TextStrokeColor3 = Color3.fromRGB(12, 28, 22)
toastLabel.TextTransparency = 1 -- hidden until a conversion happens
toastLabel.TextStrokeTransparency = 1
toastLabel.Text = ""
toastLabel.Parent = toastGui

local toastCap = Instance.new("UITextSizeConstraint")
toastCap.MaxTextSize = 52
toastCap.Parent = toastLabel

-- Pop the toast in at center, then float it up and fade out over ~1.1s.
local START_Y = 0.44
local function showToast(text, color)
	toastLabel.Text = text
	toastLabel.TextColor3 = color
	-- Snap back to the visible start state (cancels any in-flight tween).
	toastLabel.Position = UDim2.fromScale(0.5, START_Y)
	toastLabel.TextTransparency = 0
	toastLabel.TextStrokeTransparency = 0.4
	TweenService:Create(
		toastLabel,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromScale(0.5, START_Y - 0.08),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	):Play()
end

-- Ask the server to convert; show feedback based on its authoritative result.
local function requestConversion()
	local result = convertSpiritToChiFunc:InvokeServer()
	if not result then
		return -- server hiccup; nothing to show
	end
	if result.ok then
		showToast(result.message, CONVERT_OK_COLOR) -- e.g. "+300 Chi!"
	else
		showToast(result.message, CONVERT_NONE_COLOR) -- "Meditate to gather more..."
	end
end

altarTouchedEvent.OnClientEvent:Connect(requestConversion)
