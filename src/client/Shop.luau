-- Ancient Spirit Simulator — Spirit Shop popup (Zen + Soul Jar tabs).
--
-- The tabbed shop window opened by the shop pad: the Zen tab (click-multiplier upgrade)
-- and the Soul Jar tab (Spirit Power storage cap). Plain-GUI (Instance.new), server-
-- authoritative — the panels just render what the server returns and ask it to buy.
--
-- Publishes ctx.services.refreshZen (the Ascend + Group modules refresh the Zen panel
-- after granting Zen levels). Calls ctx.services.setJarCapacity when the jar changes.
--
-- Extracted verbatim from the old monolithic client script during the module split.
return function(ctx)
	local PopupManager = ctx.PopupManager
	local round = ctx.round
	local stroke = ctx.stroke
	local FONT = ctx.FONT
	local commafy = ctx.commafy
	local playerGui = ctx.playerGui
	local chiValue = ctx.chiValue
	local TABS = ctx.TABS
	local DEFAULT_TAB = ctx.DEFAULT_TAB
	local openShopEvent = ctx.openShopEvent
	local getZenStateFunc = ctx.getZenStateFunc
	local buyZenFunc = ctx.buyZenFunc
	local getSoulJarStateFunc = ctx.getSoulJarStateFunc
	local buySoulJarFunc = ctx.buySoulJarFunc

	--------------------------------------------------------------------------------
	-- Build the popup once, keep it hidden, and just toggle visibility
	--------------------------------------------------------------------------------
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
	-- Tab switching: show one panel, hide the rest, highlight the matching button.
	--------------------------------------------------------------------------------
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

	-- The server tells us to open the shop when the player touches the pad. Re-touching
	-- while it's already open just re-shows the default tab — harmless.
	openShopEvent.OnClientEvent:Connect(openShop)

	--------------------------------------------------------------------------------
	-- Zen tab: click multiplier upgrade
	--------------------------------------------------------------------------------
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
			buyButton.Text = "BUY  •  " .. state.cost .. " Chi"
			buyButton.BackgroundColor3 = BUY_COLOR
			buyButton.AutoButtonColor = true
			buyButton.Active = true
		end
	end

	-- Ask the server for the latest state and redraw.
	local function refreshZen()
		renderZen(getZenStateFunc:InvokeServer())
	end

	-- Buying: the server validates and returns the resulting state, which we render.
	buyButton.Activated:Connect(function()
		if not buyButton.Active then
			return
		end
		renderZen(buyZenFunc:InvokeServer())
	end)

	-- Keep the panel current: refresh once at startup and every time the shop opens.
	openShopEvent.OnClientEvent:Connect(refreshZen)
	refreshZen()

	-- Published so the Ascend + Group modules can refresh Zen after granting Zen levels.
	ctx.services.refreshZen = refreshZen

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
	-- placeholder values so the live .Changed handler can never read a nil field during
	-- the first refresh's network round-trip.
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
		ctx.services.setJarCapacity(soulJarData.currentCapacity)

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

		-- Enabled only when affordable (checked live against CHI now — the upgrade cost is
		-- Chi). The jar still HOLDS Spirit Power (see jarCapLabel above); only cost changed.
		local affordable = chiValue.Value >= soulJarData.nextCost
		buyJarButton.Text = "BUY  •  " .. commafy(soulJarData.nextCost) .. " Chi"
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

	-- Buying: the server validates and returns the resulting state, which we render.
	buyJarButton.Activated:Connect(function()
		if not buyJarButton.Active then
			return
		end
		soulJarData = buySoulJarFunc:InvokeServer()
		renderSoulJar()
	end)

	-- CHI changing re-evaluates whether the Soul Jar BUY button is affordable (the cost
	-- is Chi now). The HUD vessel bar itself is updated by the Spirit Power handler.
	chiValue.Changed:Connect(renderSoulJar)

	-- Refresh whenever the shop opens, plus an initial draw.
	openShopEvent.OnClientEvent:Connect(refreshSoulJar)
	refreshSoulJar()
end
