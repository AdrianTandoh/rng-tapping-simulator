-- Ancient Spirit Simulator — Group Rewards popup.
--
-- Its OWN popup (opened by the Group Rewards world pad). The server is the only authority
-- on membership + whether the reward was already claimed; this UI renders that state and
-- asks it to claim. Refreshes the Zen panel (ctx.services.refreshZen) when a claim grants
-- Zen levels.
--
-- Extracted verbatim from the old monolithic client script during the module split.
return function(ctx)
	local round = ctx.round
	local stroke = ctx.stroke
	local FONT = ctx.FONT
	local PopupManager = ctx.PopupManager
	local GuiService = ctx.GuiService
	local playerGui = ctx.playerGui
	local commafy = ctx.commafy
	local openGroupRewardsEvent = ctx.openGroupRewardsEvent
	local getGroupRewardStateFunc = ctx.getGroupRewardStateFunc
	local claimGroupRewardFunc = ctx.claimGroupRewardFunc

	local GROUP_CLAIM_COLOR = Color3.fromRGB(70, 200, 90) -- green: ready to claim
	local GROUP_CHECK_COLOR = Color3.fromRGB(90, 170, 255) -- blue: join / re-check
	local GROUP_DONE_COLOR = Color3.fromRGB(255, 200, 40) -- gold: already claimed
	local GROUP_OFF_COLOR = Color3.fromRGB(110, 100, 140) -- muted: not configured

	-- Built once, hidden, and toggled — exactly like the shop popup.
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
	-- some clients, hence pcall) and re-check membership shortly after.
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
				-- The claim may have granted a Zen level. Refresh the Zen panel to match.
				ctx.services.refreshZen()
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
end
