-- Ancient Spirit Simulator — Meditation Altar conversion toast.
--
-- The server fires AltarTouched when the player steps on the altar; we ask the server (the
-- only authority) to convert Spirit Power → Chi. The HUD updates itself via the currency
-- .Changed handlers; here we only add a brief floating-text toast for feedback. The toast
-- is NOT a PopupManager popup — it's transient, fire-and-forget juice.
--
-- Extracted verbatim from the old monolithic client script during the module split.
return function(ctx)
	local FONT = ctx.FONT
	local TweenService = ctx.TweenService
	local playerGui = ctx.playerGui
	local altarTouchedEvent = ctx.altarTouchedEvent
	local convertSpiritToChiFunc = ctx.convertSpiritToChiFunc

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
end
