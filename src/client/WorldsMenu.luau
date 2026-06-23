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
	local PopupManager = ctx.PopupManager
	local playerGui = ctx.playerGui
	local requestTravelEvent = ctx.requestTravelEvent
	local getWorldsStateFunc = ctx.getWorldsStateFunc

	local WORLDS_ACCENT = Color3.fromRGB(120, 200, 255)

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

	-- Build one travel row. `highlight` marks the player's CURRENT location.
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

	-- Rebuild the list from the server's authoritative world list + current location.
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
			local here = (not state.atHub) and state.currentWorld == w.index
			local b = makeTravelButton((here and "● " or "→ ") .. w.name, w.index, here)
			b.LayoutOrder = w.index
			b.Parent = worldsList
		end
		-- Return-to-hub row (highlighted when you're already in the hub).
		local hubBtn = makeTravelButton((state.atHub and "● " or "↩ ") .. "Return to Hub", 0, state.atHub)
		hubBtn.LayoutOrder = 100
		hubBtn.Parent = worldsList
	end

	local function openWorlds()
		refreshWorldsMenu() -- pull fresh state each open
		PopupManager.open(worldsGui)
	end

	wClose.Activated:Connect(function()
		PopupManager.close(worldsGui)
	end)

	-- The left-side menu grid's "Worlds" tile calls this.
	ctx.services.openWorlds = openWorlds
end
