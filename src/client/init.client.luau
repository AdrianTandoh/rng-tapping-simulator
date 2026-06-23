-- Ancient Spirit Simulator — CLIENT entry point.
--
-- This file used to be a single ~2300-line LocalScript. Its one script scope accumulated
-- 200+ top-level locals and tripped Luau's hard "200 local registers per scope" limit
-- ("Out of local registers when trying to allocate trackPlayer"), which stopped the whole
-- client — and therefore the entire HUD — from compiling.
--
-- The real fix: the UI is now split into one child ModuleScript per feature (each its own
-- scope, each well under the limit). This entry script does only two things:
--   1. Build a shared CONTEXT (services, Fusion, helpers, remotes, currency values) once.
--   2. Initialize each feature module, passing it the context.
--
-- A small `ctx.services` registry carries the FEW cross-module functions (HUD updates,
-- refreshZen, openWorlds, showComingSoon). Modules read those at call time, so the only
-- ordering rule is: a provider must initialize before another module CALLS its service at
-- init time. The order below satisfies that:
--   • CurrencyHud first  — it owns updateHud*/setJarCapacity, which Shop + Ascend call.
--   • ComingSoon + WorldsMenu — provide showComingSoon / openWorlds for the menu tiles.
--   • Shop before Ascend/Group — it owns refreshZen.
--
-- (StatsPanel — the right-side panel + bottom-left click multiplier — is a separate
-- always-on LocalScript, StatsPanel.client.luau, and is unaffected by this split.)

local ctx = require(script.Context)

require(script.CurrencyHud)(ctx) -- Chi pill + Spirit Power bar + rank (owns HUD updates)
require(script.ComingSoon)(ctx) -- shared "Coming Soon" popup (owns showComingSoon)
require(script.WorldsMenu)(ctx) -- travel popup (owns openWorlds)
require(script.Shop)(ctx) -- Spirit Shop: Zen + Soul Jar tabs (owns refreshZen)
require(script.AscendPopup)(ctx) -- prestige popup
require(script.GroupRewards)(ctx) -- group-reward popup
require(script.DailyRewards)(ctx) -- daily login rewards popup (owns openDailyRewards)
require(script.AltarToast)(ctx) -- altar conversion feedback toast
require(script.MenuGrid)(ctx) -- left-side icon-tile menu grid
require(script.WorldVisibility)(ctx) -- per-player world/character rendering
require(script.PortalBarriers)(ctx) -- W3: physical locked-portal barriers (needs WorldsMenu's toast)
require(script.WandTestButton)(ctx) -- TEMP: throwaway equip/unequip test button (remove with inventory)
require(script.ClickEarn)(ctx) -- world-click → Spirit Power
