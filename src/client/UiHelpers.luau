-- Ancient Spirit Simulator — shared client UI helpers + style constants.
--
-- Pure, dependency-free helpers (number/​rank formatting, the candy gloss gradient, the
-- rounded-corner / stroke instance helpers) plus the common style constants. No Fusion
-- scope and no remotes live here, so ANY client module can require + reuse it. (The 3D
-- recipe lives in ReplicatedStorage.Shared.Juicy3D; big-number abbreviation in
-- ReplicatedStorage.Shared.NumberFormat.)
--
-- Extracted verbatim from the old monolithic client script during the module split — the
-- behavior of every helper is unchanged.
local UiHelpers = {}

-- Playful UI font used everywhere (HUD + shop). FredokaOne is the closest guaranteed
-- built-in rounded, playful font; swap this one constant if a custom FontFace is uploaded.
UiHelpers.FONT = Enum.Font.FredokaOne
UiHelpers.OUTLINE = Color3.fromRGB(18, 14, 28) -- thick dark cartoon border
-- Warm GOLD used for the Spirit Power bar's number + fill (the glossy "spirit energy" look).
UiHelpers.GOLD = Color3.fromRGB(255, 205, 70)
UiHelpers.SPIRIT_FILL = Color3.fromRGB(255, 190, 64) -- the bar's gold energy fill

-- Adds rounded corners to any GUI object.
function UiHelpers.round(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = instance
	return corner
end

-- Adds a colored outline (stroke) to any GUI object.
function UiHelpers.stroke(instance, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = instance
	return s
end

function UiHelpers.lighten(c, t)
	return c:Lerp(Color3.new(1, 1, 1), t)
end
function UiHelpers.darken(c, t)
	return c:Lerp(Color3.new(0, 0, 0), t)
end

-- Glossy vertical "candy" gradient: bright top sheen, crisp midpoint reflection, richer
-- bottom — the static shine used on the chunky numbers + rank.
function UiHelpers.candyGradient(base)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, UiHelpers.lighten(base, 0.65)),
		ColorSequenceKeypoint.new(0.48, UiHelpers.lighten(base, 0.10)),
		ColorSequenceKeypoint.new(0.50, base),
		ColorSequenceKeypoint.new(1.00, UiHelpers.darken(base, 0.28)),
	})
end

--------------------------------------------------------------------------------
-- Rank titles & colors (edit these freely to rename / recolor ranks)
--------------------------------------------------------------------------------
-- Ordered ladder: AscendCount 0 = first title; anything past the last title stays final.
UiHelpers.RANK_TITLES = {
	"Seeker", "Disciple", "Adept", "Mystic", "Sage",
	"Ascendant", "Immortal", "Celestial", "Transcendent", "Eternal",
}

-- Colors escalate in grandeur: gray/white/blue -> purple -> gold/glowing.
UiHelpers.RANK_COLORS = {
	Seeker = Color3.fromRGB(170, 175, 185), -- gray
	Disciple = Color3.fromRGB(240, 240, 245), -- white
	Adept = Color3.fromRGB(90, 170, 255), -- blue
	Mystic = Color3.fromRGB(120, 110, 245), -- indigo
	Sage = Color3.fromRGB(175, 95, 235), -- purple
	Ascendant = Color3.fromRGB(225, 90, 205), -- magenta
	Immortal = Color3.fromRGB(255, 115, 90), -- ember orange
	Celestial = Color3.fromRGB(255, 185, 65), -- amber
	Transcendent = Color3.fromRGB(255, 215, 60), -- gold
	Eternal = Color3.fromRGB(255, 245, 170), -- glowing pale gold
}

function UiHelpers.getRankTitle(count)
	return UiHelpers.RANK_TITLES[math.min(count + 1, #UiHelpers.RANK_TITLES)]
end

function UiHelpers.getRankColor(count)
	return UiHelpers.RANK_COLORS[UiHelpers.getRankTitle(count)]
end

-- "12345" -> "12,345"
function UiHelpers.commafy(n)
	local s = tostring(math.floor(n))
	while true do
		local replaced, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = replaced
		if count == 0 then
			break
		end
	end
	return s
end

-- 1.5 -> "x1.5", 1 -> "x1", 2.25 -> "x2.25"
function UiHelpers.fmtMult(m)
	local s = string.format("%.2f", m)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return "x" .. s
end

return UiHelpers
