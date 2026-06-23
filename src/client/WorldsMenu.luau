-- Ancient Spirit Simulator — Worlds travel menu (popup) — W2a.
--
-- A small menu listing the worlds; clicking one asks the SERVER to travel there (the same
-- server path the physical portals use). The server owns currentWorld and performs the
-- teleport; this UI only sends a request. Opened by the "Worlds" tile in the menu grid via
-- ctx.services.openWorlds.
--
-- Extracted verbatim from the old monolithic client script during the module split.
return function(ctx)
	local round = ctx.round
	local stroke = ctx.stroke
	local FONT = ctx.FONT
	local TweenService = ctx.TweenService
	local PopupManager = ctx.PopupManager
	local playerGui = ctx.playerGui
	local commafy = ctx.commafy
	local requestTravelEvent = ctx.requestTravelEvent
	local getWorldsStateFunc = ctx.getWorldsStateFunc
	local worldUnlockedEvent = ctx.worldUnlockedEvent -- W3: a world just unlocked
	local travelBlockedEvent = ctx.travelBlockedEvent -- W3: server refused a locked-world travel

	local WORLDS_ACCENT = Color3.fromRGB(120, 200, 255)
	local LOCK_COLOR = Color3.fromRGB(150, 160, 180) -- muted slate: locked / requirement text
	local UNLOCK_COLOR = Color3.fromRGB(255, 215, 120) -- warm gold: "world unlocked!" celebration

	-- W3 requirement label, formatted identically wherever it appears (locked tile + toasts):
	-- e.g. "Requires 1 Ascend + 5,000 Chi". The numbers are the server's authoritative values.
	local function requirementText(reqAscend, reqChi)
		local ascendPart = (reqAscend == 1) and "1 Ascend" or (tostring(reqAscend) .. " Ascends")
		return "Requires " .. ascendPart .. " + " .. commafy(reqChi) .. " Chi"
	end

	-- The popup (own ScreenGui, managed by PopupManager like the shop/ascend popups).
	local worldsGui = Instance.new("ScreenGui")
	worldsGui.Name = "WorldsMenuGui"
	worldsGui.ResetOnSpawn = false
	worldsGui.IgnoreGuiInset = true
	worldsGui.Enabled = false
	worldsGui.Parent = playerGui
	PopupManager.register(worldsGui)

	local wShadow = Instance.new("Frame")
	wShadow.AnchorPoint = Vector2.new(0.5, 0.5)
	wShadow.Position = UDim2.new(0.5, 0, 0.5, 6)
	wShadow.Size = UDim2.fromOffset(440, 420)
	wShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	wShadow.BackgroundTransparency = 0.6
	wShadow.ZIndex = 0
	wShadow.Parent = worldsGui
	round(wShadow, 22)

	local wMain = Instance.new("Frame")
	wMain.Name = "Main"
	wMain.AnchorPoint = Vector2.new(0.5, 0.5)
	wMain.Position = UDim2.fromScale(0.5, 0.5)
	wMain.Size = UDim2.fromOffset(420, 400)
	wMain.BackgroundColor3 = Color3.fromRGB(35, 45, 70)
	wMain.ZIndex = 1
	wMain.Parent = worldsGui
	round(wMain, 20)
	stroke(wMain, WORLDS_ACCENT, 3)

	local wHeader = Instance.new("Frame")
	wHeader.Size = UDim2.new(1, 0, 0, 60)
	wHeader.BackgroundColor3 = Color3.fromRGB(55, 80, 130)
	wHeader.ZIndex = 2
	wHeader.Parent = wMain
	round(wHeader, 20)

	local wHeaderCover = Instance.new("Frame")
	wHeaderCover.Size = UDim2.new(1, 0, 0, 24)
	wHeaderCover.Position = UDim2.new(0, 0, 1, -24)
	wHeaderCover.BackgroundColor3 = wHeader.BackgroundColor3
	wHeaderCover.BorderSizePixel = 0
	wHeaderCover.ZIndex = 2
	wHeaderCover.Parent = wHeader

	local wTitle = Instance.new("TextLabel")
	wTitle.Size = UDim2.new(1, -70, 1, 0)
	wTitle.Position = UDim2.fromOffset(20, 0)
	wTitle.BackgroundTransparency = 1
	wTitle.Text = "TRAVEL"
	wTitle.Font = FONT
	wTitle.TextSize = 28
	wTitle.TextXAlignment = Enum.TextXAlignment.Left
	wTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	wTitle.TextStrokeTransparency = 0.6
	wTitle.ZIndex = 3
	wTitle.Parent = wHeader

	local wClose = Instance.new("TextButton")
	wClose.AnchorPoint = Vector2.new(1, 0.5)
	wClose.Position = UDim2.new(1, -14, 0.5, 0)
	wClose.Size = UDim2.fromOffset(38, 38)
	wClose.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
	wClose.Text = "X"
	wClose.Font = FONT
	wClose.TextSize = 22
	wClose.TextColor3 = Color3.fromRGB(255, 255, 255)
	wClose.ZIndex = 3
	wClose.Parent = wHeader
	round(wClose, 10)
	stroke(wClose, Color3.fromRGB(150, 30, 30), 2)

	-- Scrollable-free list (few worlds): a column of travel buttons.
	local worldsList = Instance.new("Frame")
	worldsList.Name = "List"
	worldsList.Position = UDim2.fromOffset(0, 72)
	worldsList.Size = UDim2.new(1, 0, 1, -84)
	worldsList.BackgroundTransparency = 1
	worldsList.ZIndex = 1
	worldsList.Parent = wMain

	local worldsListLayout = Instance.new("UIListLayout")
	worldsListLayout.FillDirection = Enum.FillDirection.Vertical
	worldsListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	worldsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	worldsListLayout.Padding = UDim.new(0, 10)
	worldsListLayout.Parent = worldsList

	-- A transient floating toast (own ScreenGui, above the menu) for W3 feedback: a locked
	-- world's requirement, a refused portal/menu travel, or a "world unlocked!" celebration.
	-- Fire-and-forget juice, not a PopupManager popup (mirrors the AltarToast pattern).
	local toastGui = Instance.new("ScreenGui")
	toastGui.Name = "WorldTravelToast"
	toastGui.ResetOnSpawn = false
	toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 60 -- above the worlds popup
	toastGui.Parent = playerGui

	local toastLabel = Instance.new("TextLabel")
	toastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toastLabel.Size = UDim2.fromOffset(600, 64)
	toastLabel.BackgroundTransparency = 1
	toastLabel.Font = FONT
	toastLabel.TextScaled = true
	toastLabel.TextColor3 = LOCK_COLOR
	toastLabel.TextStrokeColor3 = Color3.fromRGB(14, 18, 28)
	toastLabel.TextTransparency = 1
	toastLabel.TextStrokeTransparency = 1
	toastLabel.Text = ""
	toastLabel.Parent = toastGui

	local toastCap = Instance.new("UITextSizeConstraint")
	toastCap.MaxTextSize = 40
	toastCap.Parent = toastLabel

	local TOAST_START_Y = 0.4
	local function showTravelToast(text, color)
		toastLabel.Text = text
		toastLabel.TextColor3 = color or LOCK_COLOR
		toastLabel.Position = UDim2.fromScale(0.5, TOAST_START_Y) -- cancels any in-flight tween
		toastLabel.TextTransparency = 0
		toastLabel.TextStrokeTransparency = 0.4
		TweenService:Create(
			toastLabel,
			TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromScale(0.5, TOAST_START_Y - 0.07),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}
		):Play()
	end

	-- Build one UNLOCKED travel row. `highlight` marks the player's CURRENT location.
	local function makeTravelButton(text, target, highlight)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -40, 0, 54)
		btn.BackgroundColor3 = highlight and Color3.fromRGB(70, 110, 80) or Color3.fromRGB(58, 70, 105)
		btn.Text = text
		btn.Font = FONT
		btn.TextSize = 20
		btn.TextColor3 = Color3.fromRGB(245, 245, 255)
		btn.AutoButtonColor = true
		btn.ZIndex = 1
		round(btn, 12)
		btn.Activated:Connect(function()
			requestTravelEvent:FireServer(target)
			PopupManager.close(worldsGui)
		end)
		return btn
	end

	-- Build one LOCKED world row: visibly disabled (muted, padlock) and showing the unlock
	-- requirement. It does NOT request travel — clicking just re-shows the requirement toast.
	-- (The server would refuse a locked travel anyway; this keeps the UI honest about it.)
	local function makeLockedButton(world)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -40, 0, 54)
		btn.BackgroundColor3 = Color3.fromRGB(46, 50, 64)
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.ZIndex = 1
		round(btn, 12)
		stroke(btn, Color3.fromRGB(70, 76, 92), 1)

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, -20, 0, 26)
		title.Position = UDim2.fromOffset(10, 6)
		title.Font = FONT
		title.TextSize = 18
		title.Text = "🔒 " .. world.name
		title.TextColor3 = Color3.fromRGB(205, 210, 225)
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.ZIndex = 2
		title.Parent = btn

		local req = Instance.new("TextLabel")
		req.BackgroundTransparency = 1
		req.Size = UDim2.new(1, -20, 0, 18)
		req.Position = UDim2.new(0, 10, 1, -22)
		req.Font = FONT
		req.TextSize = 14
		req.Text = requirementText(world.reqAscend, world.reqChi)
		req.TextColor3 = LOCK_COLOR
		req.TextXAlignment = Enum.TextXAlignment.Center
		req.ZIndex = 2
		req.Parent = btn

		btn.Activated:Connect(function()
			showTravelToast(world.name .. " — " .. requirementText(world.reqAscend, world.reqChi), LOCK_COLOR)
		end)
		return btn
	end

	-- Rebuild the list from the server's authoritative world list + current location. The
	-- server stamps each world's `unlocked` flag + requirement, so this is purely a render of
	-- authoritative state — the client never decides what's unlocked.
	local function refreshWorldsMenu()
		for _, child in ipairs(worldsList:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local state = getWorldsStateFunc:InvokeServer()
		if not state then
			return
		end
		for _, w in ipairs(state.worlds) do
			local b
			if w.unlocked then
				local here = (not state.atHub) and state.currentWorld == w.index
				b = makeTravelButton((here and "● " or "→ ") .. w.name, w.index, here)
			else
				b = makeLockedButton(w)
			end
			b.LayoutOrder = w.index
			b.Parent = worldsList
		end
		-- Return-to-hub row (always available; highlighted when you're already in the hub).
		local hubBtn = makeTravelButton((state.atHub and "● " or "↩ ") .. "Return to Hub", 0, state.atHub)
		hubBtn.LayoutOrder = 100
		hubBtn.Parent = worldsList
	end

	-- W3 REACTIVE UPDATES (server pushes). A world unlocking mid-session refreshes the open
	-- menu so the row flips from locked → travelable without reopening, and celebrates it.
	worldUnlockedEvent.OnClientEvent:Connect(function(_index, name)
		showTravelToast("✦ " .. name .. " unlocked! ✦", UNLOCK_COLOR)
		if worldsGui.Enabled then
			refreshWorldsMenu()
		end
	end)

	-- A refused travel (walked into a locked portal, or a rejected menu/direct request): show
	-- the requirement the server sent back.
	travelBlockedEvent.OnClientEvent:Connect(function(_index, name, reqAscend, reqChi)
		showTravelToast(name .. " — " .. requirementText(reqAscend, reqChi), LOCK_COLOR)
	end)

	local function openWorlds()
		refreshWorldsMenu() -- pull fresh state each open
		PopupManager.open(worldsGui)
	end

	wClose.Activated:Connect(function()
		PopupManager.close(worldsGui)
	end)

	-- The left-side menu grid's "Worlds" tile calls this.
	ctx.services.openWorlds = openWorlds

	-- Shared with PortalBarriers (the physical locked-portal barriers) so menu and portals use
	-- ONE feedback system — the same toast + the same "Requires X Ascend + Y Chi" formatter.
	ctx.services.showTravelToast = showTravelToast
	ctx.services.requirementText = requirementText
end
