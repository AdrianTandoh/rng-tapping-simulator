--!strict
-- Ancient Spirit Simulator — shared number formatting helpers.
--
-- Lives in ReplicatedStorage.Shared so ANY script (client UI now, server/other UI later)
-- can require it. The headline helper is `abbreviate`, which shortens big numbers with
-- suffixes (612436 → "612K", 1406501 → "1.4M", 10000000 → "10M"). This game produces huge
-- Ascend-inflated values, so the suffix chain is long and the function clamps gracefully
-- instead of breaking at extreme magnitudes.

local NumberFormat = {}

-- Short-scale suffixes, one per power of 1000. Index 1 (= tier 0) is the empty suffix used
-- for values below 1,000. After the familiar K/M/B/T we use standard idle-game shorthand
-- (Qa, Qi, Sx, Sp, Oc, No, Dc...) and keep going well past anything the game can reach, so
-- `abbreviate` never runs off the end. The final tier is the clamp: absurdly large values
-- just keep that suffix with a bigger mantissa rather than erroring.
local SUFFIXES = {
	"", -- < 1,000
	"K", -- 10^3  thousand
	"M", -- 10^6  million
	"B", -- 10^9  billion
	"T", -- 10^12 trillion
	"Qa", -- 10^15 quadrillion
	"Qi", -- 10^18 quintillion
	"Sx", -- 10^21 sextillion
	"Sp", -- 10^24 septillion
	"Oc", -- 10^27 octillion
	"No", -- 10^30 nonillion
	"Dc", -- 10^33 decillion
	"UDc", -- 10^36
	"DDc", -- 10^39
	"TDc", -- 10^42
	"QaDc", -- 10^45
	"QiDc", -- 10^48
	"SxDc", -- 10^51
	"SpDc", -- 10^54
	"OcDc", -- 10^57
	"NoDc", -- 10^60
	"Vg", -- 10^63 vigintillion
	"UVg", -- 10^66
	"DVg", -- 10^69
	"TVg", -- 10^72
	"QaVg", -- 10^75
	"QiVg", -- 10^78
	"SxVg", -- 10^81
	"SpVg", -- 10^84
	"OcVg", -- 10^87
	"NoVg", -- 10^90
	"Tg", -- 10^93 trigintillion
}

-- abbreviate(value) → short display string.
--   612436   → "612K"   (3-digit mantissa: no decimals)
--   1406501  → "1.4M"   (~1 decimal of precision)
--   10000000 → "10M"    (a trailing ".0" is trimmed)
--   < 1000   → plain rounded integer ("0", "999")
-- Negative values keep a leading "-". nil/garbage is treated as 0.
function NumberFormat.abbreviate(value: number?): string
	local n = tonumber(value) or 0
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end

	-- Walk down by factors of 1000 to find the tier. A loop (not math.log) avoids
	-- floating-point edge cases at exact powers, and the tier cap clamps huge values.
	local tier = 0
	while n >= 1000 and tier < #SUFFIXES - 1 do
		n = n / 1000
		tier = tier + 1
	end

	-- Below 1,000: no suffix, just a rounded integer.
	if tier == 0 then
		return sign .. tostring(math.floor(n + 0.5))
	end

	-- ~1 decimal of precision, but drop decimals once the mantissa has 3 digits (612K).
	local decimals = (n < 100) and 1 or 0

	-- Rounding can push the mantissa up to 1000 (e.g. 999,999 → "1000K"); when it does,
	-- roll over into the next tier so it reads "1M" instead.
	local rounded = tonumber(string.format("%." .. decimals .. "f", n)) or n
	if rounded >= 1000 and tier < #SUFFIXES - 1 then
		n = rounded / 1000
		tier = tier + 1
		decimals = (n < 100) and 1 or 0
		rounded = tonumber(string.format("%." .. decimals .. "f", n)) or n
	end

	local mantissa = string.format("%." .. decimals .. "f", rounded)
	-- Trim a trailing ".0" so exact powers read cleanly (10.0M → 10M).
	if decimals == 1 and string.sub(mantissa, -2) == ".0" then
		mantissa = string.sub(mantissa, 1, -3)
	end

	return sign .. mantissa .. SUFFIXES[tier + 1]
end

return NumberFormat
