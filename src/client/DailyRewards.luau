-- Ancient Spirit Simulator — Daily Login Rewards popup.
--
-- Its OWN popup (opened by the "Daily" menu tile via ctx.services.openDailyRewards). The
-- SERVER is the sole authority on the streak, the cooldown and what's claimable — every value
-- here comes from getDailyRewardState / claimDailyReward; this UI only renders that state and
-- asks the server to claim. Reactive: re-pulls on open, after each claim, and live-ticks the
-- cooldown so the Claim button enables itself the moment the reward becomes available (no
-- reopen needed). Styling matches the candy popups (rounded panels, gold outline).
return function(ctx)
	local round = ctx.round
	local stroke = ctx.stroke
	local FONT = ctx.FONT
	local PopupManager = ctx.PopupManager
	local playerGui = ctx.playerGui
	local commafy = ctx.commafy
	local getDailyRewardStateFunc = ctx.getDailyRewardStateFunc
	local claimDailyRewardFunc = ctx.claimDailyRewardFunc

	local RunService = game:GetService("RunService")

	-- Day-cell state palette.
	local CLAIMED_COLOR = Color3.fromRGB(52, 92, 62) -- muted green: already claimed this cycle
	local READY_COLOR = Color3.fromRGB(70, 200, 90) -- bright green: claimable NOW
	local NEXT_COLOR = Color3.fromRGB(58, 78, 130) -- blue: next up, still on cooldown
	local UPCOMING_COLOR = Color3.fromRGB(50, 52, 84) -- dim: later in the cycle
	local LOCKED_BTN_COLOR = Color3.fromRGB(85, 90, 120) -- disabled claim button
	local GOLD = Color3.fromRGB(255, 200, 40)

	--------------------------------------------------------------------------------
	-- Popup shell (shadow + main panel + header + close), mirroring the other popups.
	--------------------------------------------------------------------------------
	local dailyGui = Instance.new("ScreenGui")
	dailyGui.Name = "DailyRewardsGui"
	dailyGui.ResetOnSpawn = false
	dailyGui.IgnoreGuiInset = true
	dailyGui.Enabled = false
	dailyGui.Parent = playerGui
	PopupManager.register(dailyGui)

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 0.5, 6)
	shadow.Size = UDim2.fromOffset(580, 450)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.6
	shadow.ZIndex = 0
	shadow.Parent = dailyGui
	round(shadow, 22)

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.Size = UDim2.fromOffset(560, 430)
	main.BackgroundColor3 = Color3.fromRGB(40, 44, 78)
	main.ZIndex = 1
	main.Parent = dailyGui
	round(main, 20)
	stroke(main, GOLD, 3)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = Color3.fromRGB(64, 74, 140)
	header.ZIndex = 2
	header.Parent = main
	round(header, 20)

	local headerCover = Instance.new("Frame")
	headerCover.Size = UDim2.new(1, 0, 0, 24)
	headerCover.Position = UDim2.new(0, 0, 1, -24)
	headerCover.BackgroundColor3 = header.BackgroundColor3
	headerCover.BorderSizePixel = 0
	headerCover.ZIndex = 2
	headerCover.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.fromOffset(20, 0)
	title.BackgroundTransparency = 1
	title.Text = "DAILY REWARDS"
	title.Font = FONT
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.6
	title.ZIndex = 3
	title.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -14, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(38, 38)
	closeButton.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
	closeButton.Text = "X"
	closeButton.Font = FONT
	closeButton.TextSize = 22
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.ZIndex = 3
	closeButton.Parent = header
	round(closeButton, 10)
	stroke(closeButton, Color3.fromRGB(150, 30, 30), 2)

	-- Grid area where the day cells live (top of the body).
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "DayGrid"
	gridFrame.Position = UDim2.fromOffset(20, 76)
	gridFrame.Size = UDim2.new(1, -40, 0, 212)
	gridFrame.BackgroundTransparency = 1
	gridFrame.ZIndex = 1
	gridFrame.Parent = main

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(120, 100)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.FillDirectionMaxCells = 4 -- 4 per row, then wrap
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = gridFrame

	-- Status line (cooldown countdown / "ready!" / claim result message).
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.new(0.5, 0, 1, -78)
	statusLabel.Size = UDim2.new(1, -40, 0, 32)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = FONT
	statusLabel.TextSize = 18
	statusLabel.TextColor3 = Color3.fromRGB(225, 222, 245)
	statusLabel.TextStrokeTransparency = 0.7
	statusLabel.Text = ""
	statusLabel.ZIndex = 1
	statusLabel.Parent = main

	-- The single Claim button.
	local claimButton = Instance.new("TextButton")
	claimButton.Name = "Claim"
	claimButton.AnchorPoint = Vector2.new(0.5, 1)
	claimButton.Position = UDim2.new(0.5, 0, 1, -16)
	claimButton.Size = UDim2.new(1, -48, 0, 52)
	claimButton.Font = FONT
	claimButton.TextSize = 22
	claimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	claimButton.TextStrokeTransparency = 0.6
	claimButton.AutoButtonColor = false
	claimButton.Text = "CLAIM"
	claimButton.ZIndex = 1
	claimButton.Parent = main
	round(claimButton, 14)
	stroke(claimButton, Color3.fromRGB(40, 120, 55), 2)

	--------------------------------------------------------------------------------
	-- Day cells — built once from the server's reward table, then recolored per render.
	--------------------------------------------------------------------------------
	local dayCells = {} -- [i] = { applyState = function(kind) }
	local cellsBuilt = false

	local function makeDayCell(info)
		-- info: { day, chi, boost }
		local cell = Instance.new("Frame")
		cell.Name = "Day" .. info.day
		cell.LayoutOrder = info.day
		cell.BackgroundColor3 = UPCOMING_COLOR
		cell.BorderSizePixel = 0
		cell.ZIndex = 1
		round(cell, 12)
		stroke(cell, Color3.fromRGB(20, 22, 40), 2)
		cell.Parent = gridFrame

		local dayLabel = Instance.new("TextLabel")
		dayLabel.AnchorPoint = Vector2.new(0.5, 0)
		dayLabel.Position = UDim2.new(0.5, 0, 0, 6)
		dayLabel.Size = UDim2.new(1, -8, 0, 18)
		dayLabel.BackgroundTransparency = 1
		dayLabel.Font = FONT
		dayLabel.TextSize = 14
		dayLabel.Text = "DAY " .. info.day
		dayLabel.TextColor3 = Color3.fromRGB(235, 235, 250)
		dayLabel.ZIndex = 2
		dayLabel.Parent = cell

		local amount = Instance.new("TextLabel")
		amount.AnchorPoint = Vector2.new(0.5, 0.5)
		amount.Position = UDim2.fromScale(0.5, 0.46)
		amount.Size = UDim2.new(1, -8, 0, 30)
		amount.BackgroundTransparency = 1
		amount.Font = FONT
		amount.TextSize = 22
		amount.Text = commafy(info.chi)
		amount.TextColor3 = GOLD
		amount.TextStrokeTransparency = 0.7
		amount.ZIndex = 2
		amount.Parent = cell

		local unit = Instance.new("TextLabel")
		unit.AnchorPoint = Vector2.new(0.5, 0.5)
		unit.Position = UDim2.fromScale(0.5, 0.64)
		unit.Size = UDim2.new(1, -8, 0, 14)
		unit.BackgroundTransparency = 1
		unit.Font = FONT
		unit.TextSize = 12
		unit.Text = info.boost and "Chi  ✦Boost" or "Chi"
		unit.TextColor3 = info.boost and Color3.fromRGB(255, 225, 130) or Color3.fromRGB(205, 205, 225)
		unit.ZIndex = 2
		unit.Parent = cell

		-- Bottom state strip ("✓ Claimed" / "Ready!" / "Soon").
		local statusStrip = Instance.new("TextLabel")
		statusStrip.AnchorPoint = Vector2.new(0.5, 1)
		statusStrip.Position = UDim2.new(0.5, 0, 1, -6)
		statusStrip.Size = UDim2.new(1, -8, 0, 16)
		statusStrip.BackgroundTransparency = 1
		statusStrip.Font = FONT
		statusStrip.TextSize = 13
		statusStrip.Text = ""
		statusStrip.TextColor3 = Color3.fromRGB(235, 235, 250)
		statusStrip.ZIndex = 2
		statusStrip.Parent = cell

		local function applyState(kind)
			if kind == "claimed" then
				cell.BackgroundColor3 = CLAIMED_COLOR
				statusStrip.Text = "✓ Claimed"
				statusStrip.TextColor3 = Color3.fromRGB(190, 240, 200)
			elseif kind == "ready" then
				cell.BackgroundColor3 = READY_COLOR
				statusStrip.Text = "Claim now!"
				statusStrip.TextColor3 = Color3.fromRGB(255, 255, 255)
			elseif kind == "next" then
				cell.BackgroundColor3 = NEXT_COLOR
				statusStrip.Text = "Next up"
				statusStrip.TextColor3 = Color3.fromRGB(210, 222, 255)
			else -- "upcoming"
				cell.BackgroundColor3 = UPCOMING_COLOR
				statusStrip.Text = "Soon"
				statusStrip.TextColor3 = Color3.fromRGB(170, 170, 195)
			end
		end

		return { applyState = applyState }
	end

	local function buildCellsIfNeeded(days)
		if cellsBuilt then
			return
		end
		for _, info in ipairs(days) do
			dayCells[info.day] = makeDayCell(info)
		end
		cellsBuilt = true
	end

	--------------------------------------------------------------------------------
	-- Render + live cooldown countdown.
	--------------------------------------------------------------------------------
	local dailyData = nil -- latest authoritative snapshot
	local countdownDeadline = nil -- os.clock() when the claim becomes available (nil if ready)
	local holdMessageUntil = 0 -- keep a claim-result message on screen briefly

	-- "Xh Ym" / "Ym Zs" / "Zs" from a second count.
	local function formatDuration(seconds)
		seconds = math.max(0, math.floor(seconds))
		local h = math.floor(seconds / 3600)
		local m = math.floor((seconds % 3600) / 60)
		local s = seconds % 60
		if h > 0 then
			return string.format("%dh %02dm", h, m)
		elseif m > 0 then
			return string.format("%dm %02ds", m, s)
		end
		return string.format("%ds", s)
	end

	local refresh -- forward declare (the countdown calls it when the timer elapses)

	local function render()
		local state = dailyData
		if not state then
			return
		end
		buildCellsIfNeeded(state.days)

		-- Which cells read as claimed/ready/next/upcoming. The streak LOOPS, so "claimed this
		-- cycle" = streak mod cycle-length; the claimable day is state.nextDay (= that + 1).
		local cycleLen = #state.days
		local claimedInCycle = cycleLen > 0 and (state.streak % cycleLen) or 0
		for i, cellInfo in ipairs(dayCells) do
			local kind
			if i <= claimedInCycle then
				kind = "claimed"
			elseif i == state.nextDay then
				kind = state.canClaim and "ready" or "next"
			else
				kind = "upcoming"
			end
			cellInfo.applyState(kind)
		end

		if state.canClaim then
			countdownDeadline = nil
			claimButton.Text = "CLAIM DAY " .. state.nextDay
			claimButton.BackgroundColor3 = READY_COLOR
			claimButton.Active = true
			claimButton.AutoButtonColor = true
			if os.clock() >= holdMessageUntil then
				statusLabel.Text = "Your Day " .. state.nextDay .. " reward is ready!"
			end
		else
			-- Anchor the live countdown to the server's reported remaining time.
			countdownDeadline = os.clock() + (state.secondsUntilNext or 0)
			claimButton.Text = "COME BACK LATER"
			claimButton.BackgroundColor3 = LOCKED_BTN_COLOR
			claimButton.Active = false
			claimButton.AutoButtonColor = false
			if os.clock() >= holdMessageUntil then
				statusLabel.Text = "Next reward in " .. formatDuration(state.secondsUntilNext or 0)
			end
		end
	end

	function refresh()
		dailyData = getDailyRewardStateFunc:InvokeServer()
		render()
	end

	-- Live tick: update the countdown label while open and, the moment it hits zero, re-pull so
	-- the server flips canClaim → true (the Claim button enables itself with no reopen).
	local lastTick = 0
	RunService.Heartbeat:Connect(function()
		if not dailyGui.Enabled or countdownDeadline == nil then
			return
		end
		local nowc = os.clock()
		if nowc - lastTick < 0.25 then
			return -- throttle to ~4x/sec
		end
		lastTick = nowc
		local remaining = countdownDeadline - nowc
		if remaining <= 0 then
			countdownDeadline = nil
			refresh() -- cooldown elapsed: server should now allow the claim
		elseif nowc >= holdMessageUntil then
			statusLabel.Text = "Next reward in " .. formatDuration(remaining)
		end
	end)

	claimButton.Activated:Connect(function()
		if not claimButton.Active then
			return -- on cooldown; the server would reject it anyway
		end
		-- Optimistically lock the button so a double-tap can't fire two requests before the
		-- server replies (the server also rejects double claims, but this avoids the round-trip).
		claimButton.Active = false
		claimButton.AutoButtonColor = false

		local result = claimDailyRewardFunc:InvokeServer()
		if not result then
			refresh() -- server hiccup; just re-sync
			return
		end
		dailyData = result.state
		if result.message then
			statusLabel.Text = result.message
			holdMessageUntil = os.clock() + 2.5 -- keep the result visible over the countdown
		end
		render()
		-- Chi HUD updates itself via the Chi IntValue .Changed handler (CurrencyHud) — no manual
		-- refresh needed here.
	end)

	local function openDailyRewards()
		refresh() -- pull fresh authoritative state every open
		PopupManager.open(dailyGui)
	end

	closeButton.Activated:Connect(function()
		PopupManager.close(dailyGui)
	end)

	-- The "Daily" menu tile calls this (registered for MenuGrid, like openWorlds).
	ctx.services.openDailyRewards = openDailyRewards

	-- Prime once so the first open is instant.
	refresh()
end
