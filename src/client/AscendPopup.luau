-- Ancient Spirit Simulator — Ascend (prestige) popup.
--
-- Opened by the cyan Ascend world pad. Plain-GUI, server-authoritative: shows the rank,
-- ascension count, permanent multiplier, and the requirement for the next Ascend, and asks
-- the server to Ascend. Drives the HUD rank (ctx.services.updateHudRank) and refreshes the
-- Zen panel after a successful Ascend (ctx.services.refreshZen), exactly as before.
--
-- Extracted verbatim from the old monolithic client script during the module split.
-- (The spiritPowerValue.Changed wiring + initial Spirit draw that used to sit here moved
-- to CurrencyHud, which owns that state — same runtime behavior.)
return function(ctx)
	local round = ctx.round
	local stroke = ctx.stroke
	local FONT = ctx.FONT
	local PopupManager = ctx.PopupManager
	local playerGui = ctx.playerGui
	local chiValue = ctx.chiValue
	local getRankTitle = ctx.getRankTitle
	local getRankColor = ctx.getRankColor
	local fmtMult = ctx.fmtMult
	local commafy = ctx.commafy
	local getAscendStateFunc = ctx.getAscendStateFunc
	local ascendFunc = ctx.ascendFunc
	local openAscendEvent = ctx.openAscendEvent

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
	ascReqLabel.Text = "Next Ascend needs 10,000 Chi"
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
		ascReqLabel.Text = "Next Ascend needs " .. commafy(ascendData.requirement) .. " Chi"

		-- Button is enabled only when the player meets the requirement (checked live
		-- against the CHI value now); otherwise it shows locked + the cost.
		local ready = chiValue.Value >= ascendData.requirement
		if ready then
			ascendButton.Text = "ASCEND"
			ascendButton.BackgroundColor3 = ASCEND_READY_COLOR
			ascendButton.TextColor3 = Color3.fromRGB(60, 40, 0)
			ascendButton.AutoButtonColor = true
			ascendButton.Active = true
		else
			ascendButton.Text = "LOCKED  •  need " .. commafy(ascendData.requirement) .. " Chi"
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
		ctx.services.updateHudRank(ascendData.count)
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
		ctx.services.updateHudRank(ascendData.count)
		ctx.services.refreshZen()
		-- The server reset Chi to 0 (and zeroed the Spirit Power bar for a clean slate),
		-- which fires their .Changed handlers and updates both HUD readouts automatically.
	end)

	-- CHI is the purchase currency now, so Chi changing re-evaluates whether the player
	-- can afford to ASCEND.
	chiValue.Changed:Connect(renderAscend)

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
	refreshAscend()
end
