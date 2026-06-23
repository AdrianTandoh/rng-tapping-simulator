-- Ancient Spirit Simulator — left-side MENU GRID (Fusion).
--
-- A grid of glossy icon-tiles on the LEFT, below the Chi pill, built from a CONFIG list
-- (MENU_TILES). Each tile has Fusion-driven HOVER + PRESS feedback driving the Juicy3D
-- recipe's knobs. Tiles route through ctx.services:
--   • Worlds → ctx.services.openWorlds (the travel menu)
--   • Pets / Codes / Inventory / Settings → ctx.services.showComingSoon (placeholder popup)
--
-- Extracted verbatim from the old monolithic client script during the module split (only
-- the cross-module calls now go through ctx.services).
return function(ctx)
	local Fusion = ctx.Fusion
	local Children = ctx.Children
	local OnEvent = ctx.OnEvent
	local FONT = ctx.FONT
	local OUTLINE = ctx.OUTLINE
	local lighten = ctx.lighten
	local Juicy3D = ctx.Juicy3D
	local playerGui = ctx.playerGui

	local scope = Fusion.scoped(Fusion)

	-- CHUNKY proportions: a fat 88px square (was 72 — +8px on every side) with a big 20px
	-- corner radius and a 4px outline. Everything below (holder, pedestal, surface, hitbox,
	-- grid cell) is derived from TILE, so this one bump resizes the whole tile.
	local TILE = 88
	local TILE_RADIUS = 20
	local PEDESTAL_DROP = 10 -- how much taller the holder is than the tile, so the base peeks

	-- One menu tile = a juicy 3D surface (Juicy3D recipe) + a label. Interaction is driven by
	-- two booleans → three Springs → the Juicy3D knobs (scale/bevel/gloss/color).
	local function menuTile(config, order)
		-- ── INTERACTION STATE (two booleans drive ALL the feedback) ────────────────────
		local isHovering = scope:Value(false)
		local isPressed = scope:Value(false)

		-- (a) SCALE — hover grows the tile, press shrinks it. A Spring eases the actual value
		-- toward this target; under-damped (damping < 1) so it overshoots = a bouncy pop.
		local targetScale = scope:Computed(function(use)
			if use(isPressed) then
				return 0.90 -- pressed: shrink (with the bevel flatten below = "pushed in")
			elseif use(isHovering) then
				return 1.08 -- hovered: pop out a little
			end
			return 1.0
		end)
		local scaleSpring = scope:Spring(targetScale, 30, 0.55)

		-- (b) BEVEL strength — 1 at rest, springs down toward 0.4 while PRESSED so the inner
		-- highlight/shadow FLATTEN. Combined with the shrink, the tile reads as physically
		-- pushed into its pedestal, then springs back out on release.
		local bevelTarget = scope:Computed(function(use)
			return use(isPressed) and 0.4 or 1.0
		end)
		local bevelSpring = scope:Spring(bevelTarget, 28, 0.7)

		-- (c) GLOSS boost — hover intensifies the top sheen (0 → 0.22), eased so it glints in.
		local glossTarget = scope:Computed(function(use)
			return use(isHovering) and 0.22 or 0.0
		end)
		local glossSpring = scope:Spring(glossTarget, 22, 0.9)

		-- (d) COLOR — brighten the body tint on hover (feeds Juicy3D's lit gradient).
		local tileColor = scope:Computed(function(use)
			return use(isHovering) and lighten(config.color, 0.12) or config.color
		end)

		return scope:New "Frame" {
			Name = config.id .. "Cell",
			LayoutOrder = order,
			Size = UDim2.fromOffset(TILE + 8, TILE + PEDESTAL_DROP + 24), -- icon area + label
			BackgroundTransparency = 1,
			[Children] = {
				-- Fixed-size holder so the grid layout stays still while the surface scales
				-- inside it (it overflows the holder on hover instead of shoving neighbours).
				scope:New "Frame" {
					Name = "IconHolder",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.fromOffset(TILE + 8, TILE + PEDESTAL_DROP),
					BackgroundTransparency = 1,
					[Children] = {
						-- (0) STACKED BASE — a darker, larger pedestal centred behind the surface
						-- and nudged down so it peeks out the bottom like a little plinth.
						Juicy3D.pedestal(scope, {
							color = tileColor,
							radius = TILE_RADIUS,
							anchor = Vector2.new(0.5, 0.5),
							position = UDim2.new(0.5, 0, 0.5, 3),
							size = UDim2.fromOffset(TILE + 8, TILE + 8),
							stroke = 4,
							zindex = 0,
						}),
						-- THE JUICY 3D SURFACE — bevel + gloss + lit gradient + outline, all from
						-- the shared recipe. The Springs above drive its scale/bevel/gloss/color.
						Juicy3D.surface(scope, {
							name = "Surface",
							anchor = Vector2.new(0.5, 0.5),
							position = UDim2.fromScale(0.5, 0.5),
							size = UDim2.fromOffset(TILE, TILE),
							color = tileColor,
							radius = TILE_RADIUS,
							stroke = 4,
							padding = 16, -- chunky internal padding; bumped 12→16 so the icon grows only
						-- slightly with the bigger tile (icon ≈ TILE−2*padding = 56px, was 48) and
						-- keeps breathing room instead of filling the whole tile
							glossFraction = 0.42, -- gloss covers the top ~42%
							glossBoost = glossSpring,
							bevel = bevelSpring,
							scale = scaleSpring,
							zindex = 2,
							content = {
								-- REAL ICON: the tile's image asset (config.image) fills the padded
								-- content area. ScaleType.Fit preserves the icon's aspect ratio so
								-- non-square art isn't stretched.
								scope:New "ImageLabel" {
									Name = "Icon",
									Size = UDim2.fromScale(1, 1),
									BackgroundTransparency = 1,
									Image = config.image,
									ScaleType = Enum.ScaleType.Fit,
								},
							},
						}),
						-- INPUT HITBOX — a transparent TextButton over the tile. Keeping input
						-- SEPARATE from the Juicy3D visuals keeps the recipe purely cosmetic. Its
						-- OnEvent handlers only flip the two booleans; Fusion animates from there.
						scope:New "TextButton" {
							Name = "Hitbox",
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromOffset(TILE, TILE),
							BackgroundTransparency = 1,
							Text = "",
							AutoButtonColor = false, -- all feedback is our own
							ZIndex = 50, -- on top so it always receives the input
							[OnEvent "MouseEnter"] = function()
								isHovering:set(true)
							end,
							[OnEvent "MouseLeave"] = function()
								-- Clear BOTH so a tile can't get stuck "pressed" if the cursor leaves
								-- before the button is released.
								isHovering:set(false)
								isPressed:set(false)
							end,
							[OnEvent "MouseButton1Down"] = function()
								isPressed:set(true) -- push in (shrink + bevel flatten)
							end,
							[OnEvent "MouseButton1Up"] = function()
								isPressed:set(false) -- release → springs back out
							end,
							-- Activated fires on a completed click OR a touch tap (works on mobile,
							-- where there's no hover). This is the actual "do the thing".
							[OnEvent "Activated"] = function()
								config.onClick()
							end,
						},
					},
				},
				-- LABEL beneath the tile.
				scope:New "TextLabel" {
					Name = "Label",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, 0),
					Size = UDim2.new(1, 12, 0, 20),
					BackgroundTransparency = 1,
					Font = FONT,
					Text = config.label,
					TextSize = 16,
					TextColor3 = Color3.fromRGB(245, 245, 255),
					[Children] = {
						scope:New "UIStroke" { Color = OUTLINE, Thickness = 2 },
					},
				},
			},
		}
	end

	----------------------------------------------------------------------------------
	-- TILE CONFIG — add a menu item by adding a row here (the whole point of the grid).
	-- Each row: id (unique), label (under the tile), image (icon asset id), color
	-- (distinct friendly tint), onClick (what the tile does). The cross-module actions go
	-- through ctx.services (late-bound) so this module doesn't depend on the others' order.
	----------------------------------------------------------------------------------
	local MENU_TILES = {
		{ id = "Worlds", label = "Worlds", image = "rbxassetid://17368164592", color = Color3.fromRGB(70, 135, 205), onClick = function()
			ctx.services.openWorlds()
		end },
		-- Daily login rewards. Reuses the gift/codes icon as a PLACEHOLDER — swap `image` for a
		-- calendar/daily icon when you have one. Opens the server-authoritative Daily Rewards popup.
		{ id = "Daily", label = "Daily", image = "rbxassetid://126509665306664", color = Color3.fromRGB(235, 190, 60), onClick = function()
			ctx.services.openDailyRewards()
		end },
		{ id = "Pets", label = "Pets", image = "rbxassetid://16697439085", color = Color3.fromRGB(235, 150, 60), onClick = function()
			ctx.services.showComingSoon("Pets")
		end },
		{ id = "Codes", label = "Codes", image = "rbxassetid://126509665306664", color = Color3.fromRGB(120, 195, 95), onClick = function()
			ctx.services.showComingSoon("Codes")
		end },
		-- PLACEHOLDER: the inventory system doesn't exist yet, so this tile just opens the
		-- shared "Coming Soon" popup. TODO: wire onClick to the real inventory UI once built.
		{ id = "Inventory", label = "Inventory", image = "rbxassetid://15402958715", color = Color3.fromRGB(190, 130, 235), onClick = function()
			ctx.services.showComingSoon("Inventory")
		end },
		-- PLACEHOLDER: no settings menu yet — opens "Coming Soon". TODO: wire to the real
		-- settings UI later. (Lives in the grid alongside the other tiles for consistency.)
		{ id = "Settings", label = "Settings", image = "rbxassetid://17368089841", color = Color3.fromRGB(150, 160, 180), onClick = function()
			ctx.services.showComingSoon("Settings")
		end },
	}

	-- Build the tile instances from the config (Fusion flattens this nested list into the
	-- grid's Children below).
	local tileInstances = {}
	for index, cfg in ipairs(MENU_TILES) do
		table.insert(tileInstances, menuTile(cfg, index))
	end

	----------------------------------------------------------------------------------
	-- BUILD the grid: LEFT side, BELOW the Chi pill, clear of Roblox's core buttons.
	-- A UIGridLayout flows the tiles into 2 columns then wraps.
	----------------------------------------------------------------------------------
	scope:New "ScreenGui" {
		Name = "MenuGrid",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		[Children] = {
			scope:New "Frame" {
				Name = "Grid",
				AnchorPoint = Vector2.new(0, 0),
				-- The Chi display sits at y=96 and is 52 tall (bottom ≈ 148); start below that.
				-- Layout math with the bigger tiles: cell = 96 wide × 122 tall (TILE+8 ×
				-- TILE+PEDESTAL_DROP+24); 6 tiles → 3 rows × 2 cols with 6px vertical padding ⇒
				-- grid height 3*122 + 2*6 = 378, spanning y≈162..540 — still well within the
				-- screen (the click multiplier moved to the bottom row, so this column fits).
				Position = UDim2.fromOffset(16, 162),
				Size = UDim2.fromOffset(208, 378),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New "UIGridLayout" {
						-- Cell = the menuTile's Cell size (icon area + pedestal peek + label).
						CellSize = UDim2.fromOffset(TILE + 8, TILE + PEDESTAL_DROP + 24),
						CellPadding = UDim2.fromOffset(16, 6), -- tightened vertical gap so the bigger tiles still fit
						FillDirectionMaxCells = 2, -- 2 columns, then wrap
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
					},
					tileInstances, -- nested list; Fusion flattens it into the grid's children
				},
			},
		},
	}
end
