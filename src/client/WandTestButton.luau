-- Ancient Spirit Simulator — TEMPORARY wand equip/unequip test button.
--
-- ⚠️ THROWAWAY TEST UI. This is only here to exercise the slice-1 cosmetic-wand equip mechanic
-- while there's no inventory yet. The REAL trigger for equipping a wand will be the inventory
-- UI later — delete this whole module (and its require in init.client) once that exists.
--
-- It just fires the server's ToggleWand remote; the SERVER owns the wand (creates/welds/removes
-- it on the character, replicated to everyone), so this button is authority-free — it only
-- requests, and flips its own label optimistically for feedback.
return function(ctx)
	local FONT = ctx.FONT
	local round = ctx.round
	local stroke = ctx.stroke
	local playerGui = ctx.playerGui
	local toggleWandEvent = ctx.toggleWandEvent

	local EQUIP_COLOR = Color3.fromRGB(95, 110, 215) -- "Equip Wand"
	local UNEQUIP_COLOR = Color3.fromRGB(200, 90, 90) -- "Unequip Wand"

	local gui = Instance.new("ScreenGui")
	gui.Name = "WandTestGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Bottom-right, clear of the bottom-center Spirit Power bar and the left menu grid.
	local button = Instance.new("TextButton")
	button.Name = "ToggleWand"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -16, 1, -16)
	button.Size = UDim2.fromOffset(170, 48)
	button.BackgroundColor3 = EQUIP_COLOR
	button.Font = FONT
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextStrokeTransparency = 0.6
	button.AutoButtonColor = true
	button.Text = "🪄 Equip Wand"
	button.Parent = gui
	round(button, 12)
	stroke(button, Color3.fromRGB(20, 22, 40), 2)

	-- Local optimistic state purely for the label/color. The wand itself is whatever the server
	-- has welded on the character (the visual source of truth); this never drives gameplay.
	local equipped = false
	local function render()
		button.Text = equipped and "🪄 Unequip Wand" or "🪄 Equip Wand"
		button.BackgroundColor3 = equipped and UNEQUIP_COLOR or EQUIP_COLOR
	end

	button.Activated:Connect(function()
		equipped = not equipped
		render()
		toggleWandEvent:FireServer() -- server performs the actual equip/unequip
	end)
end
