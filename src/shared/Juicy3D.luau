-- Ancient Spirit Simulator — Juicy3D: a REUSABLE "candy / Pet-Simulator" 3D UI recipe.
--
-- Pure Roblox-UI techniques (no image assets). Compose these helpers onto any rounded
-- frame to get the heavy beveled, glossy, layered look. Written for Fusion 0.3: every
-- helper takes the CALLER's `scope`, so the instances it creates are tracked and cleaned
-- up together with the rest of that UI. Reuse this on the currency pills, the Spirit
-- Power bar, the stats panel, etc. — call `Juicy3D.surface(scope, {...})` and drop your
-- content in; for interactive things, overlay your own transparent hitbox (so this stays
-- purely cosmetic and works on non-interactive UI too).
--
-- ── HOW THE 3D ILLUSION IS BUILT (layers, bottom → top) ───────────────────────────────
--   0. Pedestal     — a darker, slightly larger frame BEHIND/below the body → chunky depth.
--   1. Lit gradient — the body is WHITE and a vertical gradient paints it lighter-at-top →
--                     richer-at-bottom, so the surface looks LIT, not flat. (The gradient
--                     supplies the actual color; that's why the body frame is white.)
--   2. Bevel shadow — a black overlay concentrated on the BOTTOM-RIGHT inner edge.
--   3. Bevel light  — a white overlay concentrated on the TOP-LEFT inner edge.
--                     (2)+(3) together read as a domed / beveled surface.
--   4. Gloss pill   — a DEFINED rounded "lozenge" highlight inset in the TOP third: a
--                     bright, contained reflection sitting ON the surface (like the sheen
--                     on glossy candy/plastic), NOT a gradient that fades into the fill.
--   5. Shaded outline— a thick UIStroke whose color is a DARKER SHADE OF THE SURFACE'S
--                     OWN color (not flat black), so the edge reads as natural 3D depth
--                     rather than a hard cartoon border. Tunable via Juicy3D.OUTLINE_SHADE.
--   6. Content      — your icon / text, on top of everything.
--
-- ── REACTIVE KNOBS ────────────────────────────────────────────────────────────────────
-- Each "knob" below accepts EITHER a Fusion state object OR a plain number/Color3, because
-- Fusion's `use()` returns plain values unchanged. So hover/press springs can animate them:
--   • color      — body tint (brighten it on hover).
--   • glossBoost — 0..~0.3, intensifies the gloss (raise on hover).
--   • bevel      — 0..1 bevel strength; LOWER it on press so the bevel FLATTENS ("pushed in").
--   • scale      — a UIScale value; drive it with a Spring for the hover/press pop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Children = Fusion.Children

local Juicy3D = {}

-- Fallback outline color, only used if a surface is built without a body color.
Juicy3D.OUTLINE = Color3.fromRGB(16, 12, 26)

-- OUTLINE SHADING (tunable) — by default the outline is a darker shade of the surface's
-- OWN color, which reads as depth instead of a harsh black border. This is the factor:
--   • POSITIVE darkens toward black (0.55 ≈ a rich, deep edge of the tile's hue),
--   • NEGATIVE lightens toward white (flip it lighter for a soft/rim-lit edge).
-- Tweak this one number to taste; it applies everywhere the recipe is used.
Juicy3D.OUTLINE_SHADE = 0.55

local function lighten(c, t)
	return c:Lerp(Color3.new(1, 1, 1), t)
end
local function darken(c, t)
	return c:Lerp(Color3.new(0, 0, 0), t)
end

-- Shade a color by a SIGNED factor: >0 darkens toward black, <0 lightens toward white.
local function shade(c, factor)
	if factor >= 0 then
		return darken(c, factor)
	end
	return lighten(c, -factor)
end

-- Build the UIStroke color for a surface/pedestal: an explicit override if given
-- (Color3 or Fusion state, passed straight through), else a shaded version of the body
-- color (reactive — re-derives if the body color animates, e.g. hover brighten).
local function outlineColorFor(scope, color, override)
	if override ~= nil then
		return override
	end
	if color == nil then
		return Juicy3D.OUTLINE -- no body color to shade → fall back to the default outline
	end
	return scope:Computed(function(use)
		return shade(use(color), Juicy3D.OUTLINE_SHADE)
	end)
end

-- Rounded-corner helper. We give EACH layer its own UICorner (instead of putting
-- ClipsDescendants on the body) because ClipsDescendants clips to a RECTANGLE — it would
-- let square corners poke past the rounded body. Matching UICorners nest cleanly.
local function corner(scope, radius)
	return scope:New "UICorner" { CornerRadius = UDim.new(0, radius) }
end

--------------------------------------------------------------------------------------------
-- (1) LIT GRADIENT — host frame MUST be white; this gradient supplies the real color,
-- lighter at the top and richer/darker at the bottom, so the surface reads as "lit".
--------------------------------------------------------------------------------------------
function Juicy3D.litGradient(scope, color)
	return scope:New "UIGradient" {
		Rotation = 90, -- vertical: offset 0 = top, 1 = bottom
		Color = scope:Computed(function(use)
			local c = use(color)
			return ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, lighten(c, 0.36)), -- lit top
				ColorSequenceKeypoint.new(0.50, c), -- true color in the middle
				ColorSequenceKeypoint.new(1.00, darken(c, 0.26)), -- rich bottom
			})
		end),
	}
end

--------------------------------------------------------------------------------------------
-- (2)+(3) BEVEL — two full-size overlays. A Rotation-45 gradient runs from the TOP-LEFT
-- (offset 0) to the BOTTOM-RIGHT (offset 1). The white overlay is only visible near the
-- top-left (inner highlight); the black overlay only near the bottom-right (inner shadow).
-- `strength` (0..1) scales how strong both are — press lowers it to FLATTEN the bevel.
-- We animate the gradient's Transparency NumberSequence (lower value = more visible).
-- Returns { shadow, highlight } so Fusion can flatten it into a children list.
--------------------------------------------------------------------------------------------
function Juicy3D.bevel(scope, radius, strength, zindex)
	local highlight = scope:New "Frame" {
		Name = "BevelHighlight",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zindex + 1, -- above the shadow
		[Children] = {
			corner(scope, radius),
			scope:New "UIGradient" {
				Rotation = 45,
				-- Visible (low transparency) at the top-left, faded out by the middle.
				Transparency = scope:Computed(function(use)
					local s = use(strength)
					local topVis = 0.12 + (1 - s) * 0.72 -- s=1 → 0.12 (bright); s=0 → ~0.84 (faint)
					return NumberSequence.new({
						NumberSequenceKeypoint.new(0.00, topVis),
						NumberSequenceKeypoint.new(0.45, 1),
						NumberSequenceKeypoint.new(1.00, 1),
					})
				end),
			},
		},
	}
	local shadow = scope:New "Frame" {
		Name = "BevelShadow",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = zindex,
		[Children] = {
			corner(scope, radius),
			-- Faded out until the middle, then visible (low transparency) at the bottom-right.
			scope:New "UIGradient" {
				Rotation = 45,
				Transparency = scope:Computed(function(use)
					local s = use(strength)
					local botVis = 0.18 + (1 - s) * 0.72 -- s=1 → 0.18 (dark); s=0 → faint
					return NumberSequence.new({
						NumberSequenceKeypoint.new(0.00, 1),
						NumberSequenceKeypoint.new(0.55, 1),
						NumberSequenceKeypoint.new(1.00, botVis),
					})
				end),
			},
		},
	}
	return { shadow, highlight }
end

--------------------------------------------------------------------------------------------
-- (4) GLOSS PILL — a DEFINED glossy highlight, not a soft top-fade. It's a separate,
-- rounded "lozenge" reflection that sits ON the surface (think the bright streak on glossy
-- candy or wet plastic), so it reads as a contained shine with its own clear shape/edge
-- rather than a tint of the body color.
--
-- HOW IT'S BUILT:
--   • A small WHITE frame, INSET from the tile's edges and parked in the TOP third. The
--     inset keeps it well clear of the tile's rounded corners, so it stays visually
--     "contained" without needing to clip against them.
--   • A near-full UICorner (CornerRadius scale 0.5) rounds its ends into a soft-cornered
--     pill/lozenge — the defining shape of the highlight.
--   • It's mostly OPAQUE (low transparency) so it punches as a real reflection; a gentle
--     vertical gradient only fades the BOTTOM edge a little, so the pill keeps a crisp top
--     edge but melts off softly underneath (like light rolling off a curved surface).
--
-- `fraction` scales the pill's height (carried over from the old "top fraction" knob, so
-- callers don't change). `boost` (0..~0.3) brightens it further on hover.
--------------------------------------------------------------------------------------------
-- Tunables (callers tweak brightness/size/position from the surface opts or here):
local GLOSS_TOP_TRANSPARENCY = 0.10 -- crisp, bright top edge of the pill (0 = solid white)
local GLOSS_BOTTOM_TRANSPARENCY = 0.45 -- softer bottom edge → reflection rolls off
local GLOSS_TOP_INSET = 0.12 -- distance from the tile top, as a fraction of tile height
-- These two control how SHORT/TIGHT the shine is. Bigger side inset = a shorter (less
-- wide) highlight; smaller height fraction = a thinner one. Tuned down so the gloss reads
-- as a small contained glint near the top, not a long streak across the tile.
local GLOSS_SIDE_INSET = 0.22 -- inset on EACH side → keeps the pill clear of the corners
local GLOSS_HEIGHT_OF_FRACTION = 0.46 -- pill height as a fraction of the passed `fraction`

function Juicy3D.gloss(scope, radius, fraction, boost, zindex)
	return scope:New "Frame" {
		Name = "Gloss",
		-- Centered horizontally, parked in the top third, inset on all sides so the pill
		-- floats inside the tile and never touches the rounded corners.
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, GLOSS_TOP_INSET),
		Size = UDim2.fromScale(1 - GLOSS_SIDE_INSET * 2, fraction * GLOSS_HEIGHT_OF_FRACTION),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zindex,
		[Children] = {
			-- Scale-0.5 corner = capsule ends → the soft-cornered "pill" shape.
			scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			-- Vertical gradient: keep the top crisp/opaque, only ease off the bottom edge so
			-- the highlight stays a defined shape instead of fading into the fill.
			scope:New "UIGradient" {
				Rotation = 90, -- 0 = pill top, 1 = pill bottom
				Transparency = scope:Computed(function(use)
					local b = use(boost) -- hover raises this → both edges get brighter
					local top = math.clamp(GLOSS_TOP_TRANSPARENCY - b, 0, 1)
					local bottom = math.clamp(GLOSS_BOTTOM_TRANSPARENCY - b * 0.7, 0, 1)
					return NumberSequence.new({
						NumberSequenceKeypoint.new(0.00, top),
						NumberSequenceKeypoint.new(0.65, top + (bottom - top) * 0.45), -- hold the shine, then fall
						NumberSequenceKeypoint.new(1.00, bottom),
					})
				end),
			},
		},
	}
end

--------------------------------------------------------------------------------------------
-- (0) PEDESTAL — a darker, (usually) larger frame to sit BEHIND the body so the element
-- reads like it's stacked on a little base. Caller positions it (anchor/position/size);
-- defaults to centered. Returns a Frame to place behind the surface (lower ZIndex).
--------------------------------------------------------------------------------------------
function Juicy3D.pedestal(scope, opts)
	local radius = opts.radius or 18
	return scope:New "Frame" {
		Name = "Pedestal",
		AnchorPoint = opts.anchor or Vector2.new(0.5, 0.5),
		Position = opts.position or UDim2.fromScale(0.5, 0.5),
		Size = opts.size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = opts.zindex or 0,
		[Children] = {
			corner(scope, radius),
			scope:New "UIStroke" {
				-- Same shaded-outline rule as the surface, so the pedestal edge matches.
				Color = outlineColorFor(scope, opts.color, opts.outlineColor),
				Thickness = opts.stroke or 4,
			},
			-- A darker, still slightly-lit version of the body color so the base looks
			-- solid and rounded, not like a flat dead slab.
			scope:New "UIGradient" {
				Rotation = 90,
				Color = scope:Computed(function(use)
					local c = darken(use(opts.color), 0.40)
					return ColorSequence.new(lighten(c, 0.10), darken(c, 0.16))
				end),
			},
		},
	}
end

--------------------------------------------------------------------------------------------
-- MAIN ENTRY — a fully-decorated glossy/beveled BODY frame. Drop your content in via
-- opts.content (an array of Fusion children). The returned Frame stacks every layer of the
-- recipe in the right order. opts:
--   name, anchor, position, size, layoutOrder, zindex   — standard layout
--   color (state|Color3)        — body tint
--   radius (number, default 18) — corner radius
--   stroke (number, default 4)  — dark outline thickness
--   padding (number, default 10)— internal padding around the content
--   glossFraction (default .42) — gloss height as a fraction of the tile
--   glossBoost (state|number)   — hover gloss intensity (default 0)
--   bevel (state|number)        — bevel strength 0..1 (default 1; press → lower)
--   scale (state|number)        — optional UIScale (drive with a Spring)
--   outlineColor (Color3|state) — FORCE an outline color; omit to use the default shaded
--                                 outline (a darker shade of `color`, see Juicy3D.OUTLINE_SHADE)
--------------------------------------------------------------------------------------------
function Juicy3D.surface(scope, opts)
	local radius = opts.radius or 18
	local zBody = opts.zindex or 1

	-- Layers, low → high (see the recipe header).
	local layers = {
		corner(scope, radius),
		scope:New "UIStroke" { -- (5) shaded outline = darker shade of the body color (depth)
			Color = outlineColorFor(scope, opts.color, opts.outlineColor),
			Thickness = opts.stroke or 4,
		},
		Juicy3D.litGradient(scope, opts.color), -- (1) lit body color
		Juicy3D.bevel(scope, radius, opts.bevel ~= nil and opts.bevel or 1, zBody + 1), -- (2)(3)
		Juicy3D.gloss(scope, radius, opts.glossFraction or 0.42, opts.glossBoost or 0, zBody + 3), -- (4)
		-- (6) content holder ON TOP of every decoration, padded so content clears the chunky edges.
		scope:New "Frame" {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = zBody + 5,
			[Children] = {
				scope:New "UIPadding" {
					PaddingTop = UDim.new(0, opts.padding or 10),
					PaddingBottom = UDim.new(0, opts.padding or 10),
					PaddingLeft = UDim.new(0, opts.padding or 10),
					PaddingRight = UDim.new(0, opts.padding or 10),
				},
				opts.content or {}, -- nested array; Fusion flattens it
			},
		},
	}

	-- Optional UIScale for the hover/press pop (pass a Spring-backed state).
	if opts.scale ~= nil then
		table.insert(layers, scope:New "UIScale" { Scale = opts.scale })
	end

	return scope:New "Frame" {
		Name = opts.name or "Surface",
		Size = opts.size,
		Position = opts.position,
		AnchorPoint = opts.anchor,
		LayoutOrder = opts.layoutOrder,
		BackgroundColor3 = Color3.new(1, 1, 1), -- WHITE: the lit gradient supplies the real color
		BorderSizePixel = 0,
		ZIndex = zBody,
		[Children] = layers,
	}
end

return Juicy3D
