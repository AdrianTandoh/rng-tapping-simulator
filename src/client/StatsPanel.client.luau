-- Ancient Spirit Simulator — LIVE STATS PANEL  (this game's FIRST Fusion UI)
--
-- A small, always-on-screen, DISPLAY-ONLY readout (no buttons, no interaction). The
-- right-side panel now shows just the current World name; the Click multiplier moved to
-- its own candy badge at the BOTTOM-CENTER (mouse icon + "x5"). BOTH read from the same
-- reactive Values and update automatically whenever the server pushes (e.g. travelling
-- worlds gives a different click multiplier).
--
-- CARTOONY "Pet Simulator"-style look: huge chunky numbers with a vertical gloss
-- gradient (a STATIC sheen — no animated streak), thick dark outlines, a per-number
-- drop shadow, the World name tinted to its world's theme color, and a bouncy
-- SCALE-PULSE. The stats float freely (no background box). All of it is pure
-- visual/animation polish — the reactive values and server→client wiring are unchanged.
--
-- This is a self-contained LocalScript. It does NOT touch any of the other UI (shop,
-- HUD, popups, world menu); those are built the old way in init.client.luau.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- THE FUSION IDEAS USED HERE (read this first):
--   * Value    — a reactive box holding one value. Write with `value:set(x)`.
--   * Computed — derives a value from other state. Inside it you read state with
--                `use(thing)`; Fusion remembers what you used and re-runs you when
--                it changes. `use(x)` also accepts a PLAIN value (returns it as-is),
--                which we lean on so colors can be either reactive or constant.
--   * Tween    — `scope:Tween(goal, info)` returns a state object that smoothly
--                EASES toward `goal` whenever `goal` changes (used for the breathing).
--   * Spring   — `scope:Spring(goal, speed, damping)` eases toward `goal` with
--                spring physics; damping < 1 OVERSHOOTS = bouncy (used for the pop).
--   So: change a Value → bound Computeds/Tweens/Springs recompute → the screen
--   updates itself. We never find or rewrite a label by hand.
-- ─────────────────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Fusion was installed via Wally and synced by Rojo into ReplicatedStorage.Packages
-- (see wally.toml + default.project.json). This require resolves to the Fusion module.
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))

-- The server's display-only push channel (created in init.server.luau, section 1).
local statsUpdateEvent = ReplicatedStorage:WaitForChild("StatsUpdate")

-- Match the rest of the game's playful styling (same font the HUD/shop use).
local FONT = Enum.Font.FredokaOne

-- The max on-screen size of a hero number. Values render at this size when short and
-- shrink below it (via TextScaled) only when a value is too long to fit the width.
local BIG_VALUE_SIZE = 42

--------------------------------------------------------------------------------
-- Fusion scope + handy references
--------------------------------------------------------------------------------
-- A "scope" is Fusion 0.3's memory bucket: everything we create through it (Values,
-- Computeds, Instances, Tweens, Springs) is tracked together. This panel lives for
-- the whole session so we never tear it down, but using a scope is the idiomatic
-- 0.3 way and gives us the tidy `scope:Value` / `scope:Computed` / `scope:New` /
-- `scope:Tween` / `scope:Spring` method syntax used below.
local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children -- special key used to nest child instances
local peek = Fusion.peek -- reads a state object's current value WITHOUT subscribing

--------------------------------------------------------------------------------
-- 1. THE FUSION STATE — the single source of truth the panel reads from
--------------------------------------------------------------------------------
-- We keep two reactive Values: worldName (shown in the right-side panel) and
-- clickMultiplier (shown in the bottom-center badge built in section 5). They start with
-- harmless placeholders; the first StatsUpdate from the server (we request one at the
-- bottom of this file) fills in the real values. After that, every server push calls
-- `:set()` and BOTH UI elements follow along automatically. (The server still sends
-- Convert/Ascend in its snapshot — we simply ignore those fields here.)
local worldName = scope:Value("Loading…") -- e.g. "Tranquil Grove"
local clickMultiplier = scope:Value(1) -- current world's click multiplier, e.g. 1

--------------------------------------------------------------------------------
-- 2. PALETTE + small color helpers
--------------------------------------------------------------------------------
-- Per-world theme colors. Keyed by the world's NAME so the lookup stays correct
-- even if world indices change. These mirror the in-world themes (Tranquil Grove =
-- green, Whispering Highlands = misty blue, Celestial Summit = purple). If you later
-- add a `color` to the server's WORLDS config and include it in the stats snapshot,
-- you could read it straight off the push instead of this map.
local WORLD_COLORS = {
	["Tranquil Grove"] = Color3.fromRGB(90, 215, 100), -- green
	["Whispering Highlands"] = Color3.fromRGB(120, 185, 235), -- misty blue
	["Celestial Summit"] = Color3.fromRGB(195, 135, 250), -- purple
}
local WORLD_COLOR_FALLBACK = Color3.fromRGB(245, 245, 255)

local OUTLINE = Color3.fromRGB(18, 14, 28) -- the cartoon dark border color

-- Lighten / darken by blending toward white / black (Color3:Lerp does the mixing).
local function lighten(c, t)
	return c:Lerp(Color3.new(1, 1, 1), t)
end
local function darken(c, t)
	return c:Lerp(Color3.new(0, 0, 0), t)
end

-- The glossy "candy" gradient for a big number. This is also our STATIC GLOSS (see the
-- shine note in section 3): a bright sheen across the TOP half, then a crisp step down
-- to the pure color at the midpoint, fading to a richer shade at the bottom. That hard
-- midpoint line is what reads as a glossy reflection — clean and readable at any size,
-- with none of the smear the old moving streak caused.
local function candyGradient(base)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, lighten(base, 0.70)), -- bright top sheen
		ColorSequenceKeypoint.new(0.46, lighten(base, 0.12)),
		ColorSequenceKeypoint.new(0.50, base), -- crisp gloss line at the midpoint
		ColorSequenceKeypoint.new(1.00, darken(base, 0.26)), -- rich bottom
	})
end

-- worldColor is a Computed: it re-derives whenever `worldName` changes, so when you
-- TRAVEL, the world-name number recolors itself to the new world automatically.
local worldColor = scope:Computed(function(use)
	return WORLD_COLORS[use(worldName)] or WORLD_COLOR_FALLBACK
end)


--------------------------------------------------------------------------------
-- 3. ANIMATION STATE — scale pulse (Spring + Tween)
--------------------------------------------------------------------------------

-- ── SHINE (decision) ─────────────────────────────────────────────────────────
-- The previous version animated a translucent streak Frame sweeping across each
-- number. It read as a smeary blur over the text rather than a clean gloss, so it's
-- GONE. Instead the shine is now a STATIC gloss baked into each number's vertical
-- gradient (see candyGradient in section 2): a bright top sheen with a crisp midpoint
-- reflection line. It's tasteful, always crisp, and costs nothing to animate.

-- ── SCALE PULSE ──────────────────────────────────────────────────────────────
-- Two layered effects, multiplied together onto one UIScale:
--   (a) a constant, very gentle "breathing" (a slow Tween ping-ponging 1.0↔1.02), and
--   (b) a bouncy "pop" whenever a value actually changes (a Spring with low damping
--       that overshoots past the target and wobbles back).

-- (a) breathing — a slow back-and-forth Tween keeps the panel feeling alive.
local breatheGoal = scope:Value(1)
local breathe = scope:Tween(breatheGoal, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
task.spawn(function()
	while true do
		breatheGoal:set(1.02)
		task.wait(1.8)
		breatheGoal:set(1.0)
		task.wait(1.8)
	end
end)

-- (b) pop — a Spring. speed = how fast it chases the goal; damping < 1 = bouncy.
local popGoal = scope:Value(1)
local pop = scope:Spring(popGoal, 16, 0.45) -- low damping → springy overshoot
-- Kick the spring upward briefly, then let it settle back to 1. Because the spring is
-- under-damped it overshoots on the way up AND on the way back = a juicy little bounce.
local function doPop()
	popGoal:set(1.12)
	task.delay(0.12, function()
		popGoal:set(1)
	end)
end

-- Final panel scale = breathing × pop. Both are state objects, so this Computed
-- re-runs whenever either animates, and the UIScale below follows it.
local panelScale = scope:Computed(function(use)
	return use(breathe) * use(pop)
end)

--------------------------------------------------------------------------------
-- 4. UI BUILDERS
--------------------------------------------------------------------------------

-- Builds ONE big "hero" number with the full cartoony treatment.
--   valueState — the reactive Value to display.
--   formatFn   — how to render it (identity for the World name; pass any formatter).
--   colorArg   — a Color3 OR a reactive Computed of Color3 (drives the gloss gradient).
-- The text is RIGHT-aligned: this panel hugs the right edge of the screen, so anchoring
-- every value to the right keeps short and long values lined up and growing LEFTWARD —
-- they can never push off the right edge, and TextScaled (below) stops them spilling off
-- the left. No ClipsDescendants here, so nothing ever gets cropped.
local function makeBigValue(valueState, formatFn, colorArg)
	-- One shared Computed for the text; both the drop-shadow copy and the real number
	-- read it, so they can never drift apart.
	local valueText = scope:Computed(function(use)
		return formatFn(use(valueState))
	end)

	return scope:New "Frame" {
		Name = "ValueArea",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,

		[Children] = {
			-- (1) DROP SHADOW: a dark copy of the number, nudged down-right and behind.
			-- TextScaled (capped at BIG_VALUE_SIZE) shrinks it to fit when a value is long —
			-- staying in lock-step with the real number below since they share text + size.
			scope:New "TextLabel" {
				Name = "Shadow",
				ZIndex = 1,
				Position = UDim2.fromOffset(2, 3),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = FONT,
				Text = valueText,
				TextScaled = true,
				TextColor3 = OUTLINE,
				TextTransparency = 0.45,
				TextXAlignment = Enum.TextXAlignment.Right,
				[Children] = {
					scope:New "UITextSizeConstraint" { MaxTextSize = BIG_VALUE_SIZE },
				},
			},

			-- (2) THE NUMBER: white text tinted by the vertical gloss gradient, wrapped in
			-- a thick dark UIStroke for that cartoon border.
			-- TextScaled + a max-size cap is the overflow fix: short values render at the
			-- full BIG_VALUE_SIZE, while long world names (e.g. "Whispering Highlands")
			-- automatically shrink to fit the width instead of being truncated.
			scope:New "TextLabel" {
				Name = "Value",
				ZIndex = 2,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = FONT,
				Text = valueText,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1), -- white base so the gradient shows true colors
				TextXAlignment = Enum.TextXAlignment.Right,
				[Children] = {
					-- Cap the scaled size so short values stay big and chunky, not giant.
					scope:New "UITextSizeConstraint" { MaxTextSize = BIG_VALUE_SIZE },
					-- Thick dark outline around the glyphs.
					scope:New "UIStroke" {
						Color = OUTLINE,
						Thickness = 3,
						LineJoinMode = Enum.LineJoinMode.Round,
					},
					-- Vertical gloss gradient (= our static shine; see candyGradient). When
					-- colorArg is reactive (the world color) this Computed re-runs on travel
					-- and recolors the number; for a fixed Color3 it just returns a constant.
					scope:New "UIGradient" {
						Rotation = 90, -- vertical: keypoint 0 = top, 1 = bottom
						Color = scope:Computed(function(use)
							return candyGradient(use(colorArg))
						end),
					},
				},
			},
		},
	}
end

-- Builds one full stat block: a small outlined caption stacked above its hero number.
-- Everything is right-aligned to match the right-hugging panel.
local function statBlock(order, caption, valueState, formatFn, colorArg)
	return scope:New "Frame" {
		Name = caption .. "Block",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 2),
			},
			-- Small caption (also outlined, so labels pop like the numbers).
			scope:New "TextLabel" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Font = FONT,
				Text = string.upper(caption),
				TextSize = 14,
				TextColor3 = Color3.fromRGB(225, 220, 240),
				TextXAlignment = Enum.TextXAlignment.Right,
				[Children] = {
					scope:New "UIStroke" { Color = OUTLINE, Thickness = 1.5 },
				},
			},
			-- The hero number with all the juice.
			(function()
				local v = makeBigValue(valueState, formatFn, colorArg)
				v.LayoutOrder = 2
				return v
			end)(),
		},
	}
end

--------------------------------------------------------------------------------
-- 5. BUILD THE FLOATING STATS (bottom-right corner, clear of the HUD + Worlds button)
--------------------------------------------------------------------------------
-- The HUD lives top-center and the "🌍 Worlds" button is bottom-LEFT, so we anchor
-- this to the bottom-RIGHT. There is NO panel background or drop-shadow box: the stats
-- float directly over the game world, relying on the thick dark text outline to stay
-- readable against anything. The "Root" frame is fully transparent — it exists only to
-- (a) carry the UIScale pulse, (b) hold the vertical layout, and (c) give the labels a
-- fixed WIDTH so long values know how much room they have to shrink into (TextScaled).
-- Sized to the content: title (30) + 1 stat block (74) + list padding (6) ≈ 110, so the
-- single World stat still hugs the bottom-right corner now that Click has moved out.
local PANEL_W, PANEL_H = 300, 116

scope:New "ScreenGui" {
	Name = "LiveStatsPanel",
	Parent = playerGui,
	ResetOnSpawn = false, -- survive respawns, like the other always-on GUIs
	IgnoreGuiInset = true,

	[Children] = {
		scope:New "Frame" {
			Name = "Root",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -16, 1, -16), -- 16px in from the bottom-right corner
			Size = UDim2.fromOffset(PANEL_W, PANEL_H),
			BackgroundTransparency = 1, -- no box: the stats float on screen

			[Children] = {
				-- The scale-pulse driver for the whole group (breathing × pop).
				scope:New "UIScale" { Scale = panelScale },

				-- Vertical stack for the title + the World stat, right-aligned to the edge.
				scope:New "UIListLayout" {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					Padding = UDim.new(0, 6),
				},

				-- Title (outlined, gold) — floats with the rest, no background.
				scope:New "TextLabel" {
					LayoutOrder = 0,
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
					Font = FONT,
					Text = "✦ ACTIVE STATS",
					TextSize = 22,
					TextColor3 = Color3.fromRGB(255, 224, 130),
					TextXAlignment = Enum.TextXAlignment.Right,
					[Children] = {
						scope:New "UIStroke" { Color = OUTLINE, Thickness = 2.5 },
					},
				},

				-- Just the World name now (recolors to the world's theme on travel). The
				-- Click multiplier moved to the bottom-center badge (section 5b); both stay
				-- reactive off the same Values.
				statBlock(1, "World", worldName, function(v)
					return v
				end, worldColor),
			},
		},
	},
}

--------------------------------------------------------------------------------
-- 5b. CLICK-MULTIPLIER (big mouse icon + number, UNDER THE LEFT MENU — no container)
--------------------------------------------------------------------------------
-- The click multiplier is now just a BIG mouse icon next to the multiplier value in big
-- chunky GOLD text — NO pill/background — so it reads as a bold standalone callout. It
-- reads the SAME `clickMultiplier` Value as before, via a Computed, so travelling to a
-- world with a different multiplier still updates it automatically — reactivity preserved.
--
-- PLACEMENT: the LEFT column, directly UNDER the menu grid. The grid (init.client.luau)
-- spans y≈162..496 at x=16, so we park this at (16, 506). The whole left column — Chi pill,
-- menu grid + Settings, then this — then fits on screen without running off the bottom.
local CLICK_GOLD = Color3.fromRGB(255, 205, 70) -- matches the Spirit Power bar's gold

-- The chunky outlined multiplier text. Text is a Computed off clickMultiplier → stays live.
local multiplierText = scope:New "TextLabel" {
	Name = "Multiplier",
	AutomaticSize = Enum.AutomaticSize.X, -- width grows to the value ("x5" vs "x100")
	Size = UDim2.fromScale(0, 1),
	BackgroundTransparency = 1,
	Font = FONT,
	-- Render as "x5" (prefix ×) to read as "mouse → ×5" next to the icon. Trims trailing
	-- zeros so 1.5 → "x1.5", 5 → "x5". Reads the same reactive Value the panel used.
	Text = scope:Computed(function(use)
		local s = string.format("%.2f", use(clickMultiplier)):gsub("0+$", ""):gsub("%.$", "")
		return "x" .. s
	end),
	TextSize = 44, -- BIG, noticeable chunky number
	TextColor3 = Color3.new(1, 1, 1), -- white base so the candy gradient shows true color
	TextYAlignment = Enum.TextYAlignment.Center,
	LayoutOrder = 2,
	[Children] = {
		scope:New "UIStroke" { Color = OUTLINE, Thickness = 4, LineJoinMode = Enum.LineJoinMode.Round },
		-- Same static candy gloss as the panel numbers, tinted GOLD to match the Spirit bar.
		scope:New "UIGradient" { Rotation = 90, Color = candyGradient(CLICK_GOLD) },
	},
}

scope:New "ScreenGui" {
	Name = "ClickMultiplier",
	Parent = playerGui,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	[Children] = {
		-- A transparent row holding the big mouse icon + the big gold multiplier — NO
		-- background/pill (per the redesign). It carries the shared scale-pulse so it breathes
		-- and pops in lock-step with the stats panel whenever the multiplier changes.
		scope:New "Frame" {
			Name = "Root",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(16, 506), -- LEFT column, directly under the menu grid (grid ends ≈496)
			Size = UDim2.fromOffset(180, 60),
			BackgroundTransparency = 1, -- NO container: just the icon + number
			[Children] = {
				scope:New "UIScale" { Scale = panelScale }, -- shared breathe + pop keeps it lively
				-- A left-aligned row (no background): the big mouse icon, then the big gold
				-- multiplier number — laid out by the horizontal list below.
				scope:New "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					Padding = UDim.new(0, 8),
				},
				-- Mouse icon (the requested asset). Fit keeps its aspect ratio.
				scope:New "ImageLabel" {
					Name = "MouseIcon",
					Size = UDim2.fromOffset(52, 52), -- BIG mouse icon
					BackgroundTransparency = 1,
					Image = "rbxassetid://17260727409",
					ScaleType = Enum.ScaleType.Fit,
					LayoutOrder = 1,
				},
				multiplierText,
			},
		},
	},
}

--------------------------------------------------------------------------------
-- 6. WIRE THE SERVER PUSH INTO THE FUSION STATE
--------------------------------------------------------------------------------
-- The ONLY imperative glue: when the server pushes a fresh snapshot, copy each field
-- into its matching Value with `:set()`. Each set that changes a value re-runs the
-- bound Computeds (numbers, colors, gradients) and repaints the affected row — and if
-- ANYTHING changed we trigger a bouncy pop. We never reference the labels here.
local function applyStats(stats)
	if typeof(stats) ~= "table" then
		return
	end

	-- Map the fields we display to their Values (Convert/Ascend are ignored now). peek()
	-- lets us notice real changes so the pop only fires when something actually moved
	-- (e.g. not when re-entering the hub in the same world, which pushes identical values).
	local incoming = {
		[worldName] = stats.worldName,
		[clickMultiplier] = stats.clickMultiplier,
	}

	local anyChanged = false
	for stateObject, newValue in pairs(incoming) do
		if newValue ~= nil and peek(stateObject) ~= newValue then
			stateObject:set(newValue)
			anyChanged = true
		end
	end

	if anyChanged then
		doPop() -- juicy little bounce whenever a stat updates
	end
end

statsUpdateEvent.OnClientEvent:Connect(applyStats)

-- Ask the server for the FIRST snapshot now that we're listening. The server replies
-- by firing StatsUpdate back to us with the real values, and then pushes on its own
-- whenever we travel or Ascend — so the panel stays live with no polling.
statsUpdateEvent:FireServer()
