-- Ancient Spirit Simulator — click-to-earn (world clicks only).
--
-- Detect clicks/taps and ask the server to grant Spirit Power. We only count clicks on the
-- game world: if Roblox already routed the input to the GUI (a popup, its buttons, etc.) it
-- sets gameProcessedEvent = true, and we skip it. The client never changes Spirit Power
-- itself — it just fires the event.
--
-- Extracted verbatim from the old monolithic client script during the module split.
return function(ctx)
	local UserInputService = ctx.UserInputService
	local clickEarnEvent = ctx.clickEarnEvent

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
end
