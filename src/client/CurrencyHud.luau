-- Ancient Spirit Simulator — currency HUD (Chi pill + Spirit Power bar + rank title).
--
-- The always-on Fusion HUD: a top-left Chi pill, a bottom-center Spirit Power FILL bar
-- (gold candy styling), and the rank title under it. All four pieces of data — Spirit
-- Power held, Soul Jar capacity, Chi, ascension rank — live in Fusion Values; the update
-- functions push the server-driven values in and the bound Computeds repaint automatically.
--
-- Owns + publishes (via ctx.services) the HUD update entry points the other modules call:
--   • updateHudSpirit / updateHudChi / updateHudRank
--   • setJarCapacity(cap)  — the Soul Jar panel calls this when the jar changes.
--
-- Extracted verbatim from the old monolithic client script (only the helper/style defs
-- moved to UiHelpers, and the cross-module calls now go through ctx.services).
return function(ctx)
	local Fusion = ctx.Fusion
	local Children = ctx.Children
	local Juicy3D = ctx.Juicy3D
	local FONT = ctx.FONT
	local OUTLINE = ctx.OUTLINE
	local GOLD = ctx.GOLD
	local SPIRIT_FILL = ctx.SPIRIT_FILL
	local abbreviate = ctx.abbreviate
	local candyGradient = ctx.candyGradient
	local getRankTitle = ctx.getRankTitle
	local getRankColor = ctx.getRankColor
	local playerGui = ctx.playerGui
	local spiritPowerValue = ctx.spiritPowerValue
	local chiValue = ctx.chiValue

	local scope = Fusion.scoped(Fusion)

	-- A horizontal REVEAL mask for a left-anchored fill: fully OPAQUE from the left up to the
	-- fraction `f`, then a hard (anti-aliased) edge to fully transparent. Driving a FULL-SIZE
	-- fill with this — instead of resizing a child frame — lets the fill SHARE the bar's
	-- rounded-pill shape (same size + UICorner), so it can never spill outside the rounded
	-- container and always starts cleanly from the left corner. NumberSequence offsets must be
	-- strictly increasing and end at 1, so the near-empty / near-full ends are special-cased.
	local function fillReveal(f)
		f = math.clamp(f, 0, 1)
		if f <= 0.001 then
			return NumberSequence.new(1) -- empty bar → fill fully transparent
		elseif f >= 0.999 then
			return NumberSequence.new(0) -- full bar → fill fully opaque
		end
		local edge = f + 0.012 -- a ~1px feathered edge at the fill level
		if edge >= 1 then
			-- Near-full: keep the last keypoint exactly at 1 without duplicating offsets.
			return NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.994, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(f, 0),
			NumberSequenceKeypoint.new(edge, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	-- THE STATE — the single source of truth the pills + rank read from. The update
	-- functions further down push the server-driven values into these.
	local spiritHeld = scope:Value(0) -- current Spirit Power held
	local spiritCap = scope:Value(1000) -- current Soul Jar capacity (held fills toward this)
	local chiAmount = scope:Value(0) -- spendable Chi bank
	local ascendCount = scope:Value(0) -- ascension count → drives rank title + color

	-- Current Soul Jar capacity, kept in sync from the server; the bar fills toward it.
	-- Defaults to the Clay Jar until the server reports in. (The Soul Jar panel calls
	-- setJarCapacity, which mirrors it into the spiritCap Value above.)
	local currentJarCapacity = 1000

	-- Derived display state.
	-- Target fill fraction 0..1 (held / cap). Clamped, so e.g. 5.4M / 100M ≈ 0.054 → a thin
	-- left sliver, and a full jar → 1.0. This is the GOAL; the spring below eases toward it.
	local spiritFillFraction = scope:Computed(function(use)
		local cap = use(spiritCap)
		return cap > 0 and math.clamp(use(spiritHeld) / cap, 0, 1) or 0
	end)
	-- Smoothly slide the fill toward its target. Critically damped (damping 1 = no overshoot,
	-- just an ease); speed 16 keeps it snappy so the clicker still feels responsive.
	local spiritFillAnimated = scope:Spring(spiritFillFraction, 16, 1)
	local spiritDisplay = scope:Computed(function(use)
		-- Abbreviated held / cap, e.g. "10M / 10M" — short enough to never overflow the pill.
		return abbreviate(use(spiritHeld)) .. " / " .. abbreviate(use(spiritCap))
	end)
	local chiDisplay = scope:Computed(function(use)
		return abbreviate(use(chiAmount))
	end)
	local rankTitle = scope:Computed(function(use)
		return getRankTitle(use(ascendCount))
	end)
	local rankColor = scope:Computed(function(use)
		return getRankColor(use(ascendCount))
	end)

	-- Pill geometry. Capsule = corner radius == half the height.
	local PILL_W, PILL_H = 250, 52
	local PILL_RADIUS = math.floor(PILL_H / 2)

	-- A small circular icon chip for a pill. Pass `image` (an rbxassetid) to show real art,
	-- or `glyph` (an emoji) as a fallback. The chip is a colored circle with a dark ring;
	-- the image/glyph sits inside it.
	local function iconBadge(bgColor, ringColor, glyph, image)
		local inner
		if image then
			inner = scope:New "ImageLabel" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = image,
				ScaleType = Enum.ScaleType.Fit, -- preserve the icon's aspect ratio
				ZIndex = 3,
				[Children] = {
					scope:New "UIPadding" {
						PaddingTop = UDim.new(0, 5),
						PaddingBottom = UDim.new(0, 5),
						PaddingLeft = UDim.new(0, 5),
						PaddingRight = UDim.new(0, 5),
					},
				},
			}
		else
			inner = scope:New "TextLabel" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = FONT,
				Text = glyph,
				TextScaled = true,
				TextColor3 = ringColor,
				ZIndex = 3,
				[Children] = {
					scope:New "UIPadding" {
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
					},
				},
			}
		end
		return scope:New "Frame" {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(PILL_H - 14, PILL_H - 14),
			BackgroundColor3 = bgColor,
			ZIndex = 3,
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(1, 0) },
				scope:New "UIStroke" { Color = OUTLINE, Thickness = 3 },
				inner,
			},
		}
	end

	-- A chunky outlined number that sits over a pill. `colorArg` may be a Color3 or a
	-- reactive Computed of Color3 (drives the gloss gradient). `align` (optional) overrides
	-- the horizontal text alignment — the Chi display left-aligns so the number hugs its
	-- icon now that it has no pill behind it.
	local function pillNumber(textState, colorArg, align)
		return scope:New "TextLabel" {
			Name = "Value",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = textState,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1), -- white base so the gradient shows true
			TextXAlignment = align or Enum.TextXAlignment.Center,
			ZIndex = 3,
			[Children] = {
				-- Left padding clears the icon badge; right padding keeps the number off the rim.
				scope:New "UIPadding" {
					PaddingTop = UDim.new(0, 7),
					PaddingBottom = UDim.new(0, 7),
					PaddingLeft = UDim.new(0, PILL_H),
					PaddingRight = UDim.new(0, 14),
				},
				scope:New "UITextSizeConstraint" { MaxTextSize = 26 },
				scope:New "UIStroke" {
					Color = OUTLINE,
					Thickness = 3,
					LineJoinMode = Enum.LineJoinMode.Round,
				},
				scope:New "UIGradient" {
					Rotation = 90,
					Color = scope:Computed(function(use)
						return candyGradient(use(colorArg))
					end),
				},
			},
		}
	end

	-- (1) SPIRIT POWER pill — a capsule FILL BAR with the candy-3D glossy look: a dark track,
	-- a GOLD energy fill that eases smoothly toward the Soul Jar capacity, a white gloss sheen
	-- across the top (the reusable recipe's gloss), the "held / cap" number in glossy GOLD, and
	-- the new Spirit icon chip.
	--
	-- FILL (the bug fix): the fill is a FULL-SIZE frame sharing the pill's exact size + corner
	-- radius, so its rounded shape matches the container perfectly and never spills outside it.
	-- We don't resize it; instead a horizontal reveal gradient (fillReveal, driven by the
	-- animated fraction) shows only the left portion — left-anchored, clipped to the pill shape,
	-- a clean vertical edge at the fill level, a thin sliver for small fractions.
	local function spiritPill(order)
		return scope:New "Frame" {
			Name = "SpiritPill",
			LayoutOrder = order,
			Size = UDim2.fromOffset(PILL_W, PILL_H),
			BackgroundColor3 = Color3.fromRGB(38, 40, 52), -- dark track behind the fill
			ClipsDescendants = true,
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, PILL_RADIUS) },
				scope:New "UIStroke" { Color = OUTLINE, Thickness = 3 }, -- thick dark outline
				-- The GOLD fill. Full pill size + matching UICorner ⇒ same shape as the bar; the
				-- reveal gradient (not a resize) controls how much shows, so it stays inside the
				-- rounded pill and grows rightward from the left corner.
				scope:New "Frame" {
					Name = "Fill",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = SPIRIT_FILL,
					BorderSizePixel = 0,
					ZIndex = 2,
					[Children] = {
						scope:New "UICorner" { CornerRadius = UDim.new(0, PILL_RADIUS) },
						-- Horizontal reveal (Rotation 0): opaque left → transparent past the level.
						scope:New "UIGradient" {
							Rotation = 0,
							Transparency = scope:Computed(function(use)
								return fillReveal(use(spiritFillAnimated))
							end),
						},
					},
				},
				-- Glossy white sheen across the top, from the reusable recipe (contained pill).
				Juicy3D.gloss(scope, PILL_RADIUS, 0.5, 0, 3),
				iconBadge(Color3.fromRGB(120, 96, 40), Color3.fromRGB(255, 240, 200), nil, "rbxassetid://17368078790"),
				pillNumber(spiritDisplay, GOLD),
			},
		}
	end

	-- (2) CHI display — just the jade icon chip + the chunky outlined number, floating
	-- freely with NO pill/container behind it (like the click-multiplier element). The
	-- number's thick dark outline keeps it readable straight over the game world. Stays
	-- reactive (chiDisplay) and in the same top-left slot.
	local function chiPill(order)
		return scope:New "Frame" {
			Name = "ChiDisplay",
			LayoutOrder = order,
			Size = UDim2.fromOffset(PILL_W, PILL_H),
			BackgroundTransparency = 1, -- no pill: icon + number only
			[Children] = {
				iconBadge(Color3.fromRGB(46, 140, 104), Color3.fromRGB(190, 255, 224), "☯"),
				-- Left-aligned (with the existing left padding that clears the icon) so the
				-- number sits right next to the chip instead of floating centered away.
				pillNumber(chiDisplay, Color3.fromRGB(150, 240, 200), Enum.TextXAlignment.Left),
			},
		}
	end

	-- The bottom-center rank title, built as a standalone TextLabel so it can be dropped
	-- into the bottom stack below (alongside the Spirit Power bar). LayoutOrder 2 puts it
	-- UNDER the bar. Color-coded by rank via the gloss gradient.
	local function rankTitleLabel(order)
		return scope:New "TextLabel" {
			Name = "RankTitle",
			LayoutOrder = order,
			Size = UDim2.fromOffset(360, 44),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = rankTitle,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1), -- white base so the gradient shows the rank color
			[Children] = {
				scope:New "UITextSizeConstraint" { MaxTextSize = 36 },
				scope:New "UIStroke" {
					Color = OUTLINE,
					Thickness = 3,
					LineJoinMode = Enum.LineJoinMode.Round,
				},
				-- The gloss gradient is built from the rank's color, so the title recolors
				-- itself automatically whenever the player Ascends.
				scope:New "UIGradient" {
					Rotation = 90,
					Color = scope:Computed(function(use)
						return candyGradient(use(rankColor))
					end),
				},
			},
		}
	end

	-- BUILD: top-left CHI pill. Pushed DOWN from the corner so it clears Roblox's reserved
	-- core UI (the hamburger menu + chat toggle live in the top-left). Leaves room BELOW it
	-- for the side-menu grid. The Spirit Power bar lives bottom-center (below).
	scope:New "ScreenGui" {
		Name = "CurrencyHUD",
		Parent = playerGui,
		ResetOnSpawn = false, -- survive respawns, like the other always-on GUIs
		IgnoreGuiInset = true,
		[Children] = {
			scope:New "Frame" {
				Name = "Pills",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.fromOffset(16, 96), -- pushed down, clear of Roblox's core buttons
				Size = UDim2.fromOffset(PILL_W, PILL_H),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
						Padding = UDim.new(0, 10),
					},
					chiPill(1),
				},
			},
		},
	}

	-- BUILD: bottom-center stack — Spirit Power bar on TOP, rank title BELOW it. A short
	-- fixed-height column anchored to the bottom-center, sized exactly to its contents so
	-- the two pieces never overlap each other. It's clear of the Worlds button (bottom-left)
	-- and the stats panel (bottom-right), and its frames don't sink input (so clicking still
	-- earns Spirit Power). The Spirit Power bar keeps filling toward the jar capacity.
	local BOTTOM_STACK_PAD = 8
	local BOTTOM_STACK_H = PILL_H + BOTTOM_STACK_PAD + 44 -- bar (52) + gap + rank (44)
	scope:New "ScreenGui" {
		Name = "BottomHUD",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		[Children] = {
			scope:New "Frame" {
				Name = "BottomStack",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16), -- 16px up from the bottom-center
				Size = UDim2.fromOffset(360, BOTTOM_STACK_H),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Bottom,
						Padding = UDim.new(0, BOTTOM_STACK_PAD),
					},
					spiritPill(1), -- top of the stack
					rankTitleLabel(2), -- directly below the bar
				},
			},
		},
	}

	-- The three update functions just push the server-driven values into the Fusion state —
	-- the pills + rank repaint themselves. Published on ctx.services so the Shop / Ascend
	-- modules can drive them exactly as the old monolith did.
	local function updateHudSpirit()
		spiritHeld:set(spiritPowerValue.Value)
		spiritCap:set(currentJarCapacity)
	end

	local function updateHudChi()
		chiAmount:set(chiValue.Value)
	end

	local function updateHudRank(count)
		ascendCount:set(count)
	end

	-- The Soul Jar panel calls this when the jar changes: mirror the new capacity into the
	-- HUD and repaint. (Replaces the old `currentJarCapacity = cap; updateHudSpirit()`.)
	local function setJarCapacity(cap)
		currentJarCapacity = cap
		updateHudSpirit()
	end

	ctx.services.updateHudSpirit = updateHudSpirit
	ctx.services.updateHudChi = updateHudChi
	ctx.services.updateHudRank = updateHudRank
	ctx.services.setJarCapacity = setJarCapacity

	-- Live wiring + initial draw. Both currencies are read-only on the client: keep the
	-- readouts in sync whenever the server changes them. (Spirit Power only affects this HUD
	-- bar now — it no longer gates any purchase.)
	chiValue.Changed:Connect(updateHudChi)
	spiritPowerValue.Changed:Connect(updateHudSpirit)
	updateHudChi()
	updateHudSpirit()
end
