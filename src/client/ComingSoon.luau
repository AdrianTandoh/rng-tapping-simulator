-- Ancient Spirit Simulator — shared "Coming Soon" popup (Fusion).
--
-- One popup with a REACTIVE title Value: ctx.services.showComingSoon("Pets") sets the title
-- and opens it. Registered with PopupManager so it cooperates with the single-popup rule.
-- Reused by the Pets / Codes / Inventory / Settings menu tiles.
--
-- Extracted verbatim from the old monolithic client script during the module split.
return function(ctx)
	local Fusion = ctx.Fusion
	local Children = ctx.Children
	local OnEvent = ctx.OnEvent
	local FONT = ctx.FONT
	local OUTLINE = ctx.OUTLINE
	local PopupManager = ctx.PopupManager
	local playerGui = ctx.playerGui

	local scope = Fusion.scoped(Fusion)

	local comingSoonTitle = scope:Value("Soon")

	local comingSoonGui = scope:New "ScreenGui" {
		Name = "ComingSoonGui",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false, -- hidden until shown; PopupManager flips this on/off
		[Children] = {
			-- Soft drop shadow behind the card.
			scope:New "Frame" {
				Name = "Shadow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 6),
				Size = UDim2.fromOffset(380, 244),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.6,
				ZIndex = 0,
				[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 22) } },
			},
			-- Main card (matches the other popups: deep violet + gold outline).
			scope:New "Frame" {
				Name = "Main",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(360, 220),
				BackgroundColor3 = Color3.fromRGB(45, 35, 70),
				ZIndex = 1,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, 20) },
					scope:New "UIStroke" { Color = Color3.fromRGB(255, 200, 40), Thickness = 3 },
					-- Big feature name (reactive: "PETS" / "CODES").
					scope:New "TextLabel" {
						Name = "Heading",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 26),
						Size = UDim2.new(1, -40, 0, 50),
						BackgroundTransparency = 1,
						Font = FONT,
						Text = scope:Computed(function(use)
							return string.upper(use(comingSoonTitle))
						end),
						TextScaled = true,
						TextColor3 = Color3.fromRGB(255, 224, 130),
						ZIndex = 2,
						[Children] = {
							scope:New "UITextSizeConstraint" { MaxTextSize = 40 },
							scope:New "UIStroke" {
								Color = OUTLINE,
								Thickness = 3,
								LineJoinMode = Enum.LineJoinMode.Round,
							},
						},
					},
					-- Body message.
					scope:New "TextLabel" {
						Name = "Body",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.52),
						Size = UDim2.new(1, -48, 0, 44),
						BackgroundTransparency = 1,
						Font = FONT,
						Text = "Coming soon — check back later!",
						TextSize = 20,
						TextWrapped = true,
						TextColor3 = Color3.fromRGB(225, 220, 245),
						ZIndex = 2,
					},
					-- OK button (closes the popup).
					scope:New "TextButton" {
						Name = "Ok",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -20),
						Size = UDim2.fromOffset(160, 48),
						BackgroundColor3 = Color3.fromRGB(70, 200, 90),
						Font = FONT,
						Text = "OK",
						TextSize = 24,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						AutoButtonColor = true,
						ZIndex = 2,
						[OnEvent "Activated"] = function()
							PopupManager.close(comingSoonGui)
						end,
						[Children] = {
							scope:New "UICorner" { CornerRadius = UDim.new(0, 14) },
							scope:New "UIStroke" { Color = OUTLINE, Thickness = 2 },
						},
					},
				},
			},
		},
	}
	PopupManager.register(comingSoonGui)

	-- Set the title, then open (which closes any other popup).
	ctx.services.showComingSoon = function(featureName)
		comingSoonTitle:set(featureName)
		PopupManager.open(comingSoonGui)
	end
end
