-- Ancient Spirit Simulator — shared client CONTEXT.
--
-- The client UI used to be one ~2300-line script whose single scope blew Luau's
-- 200-locals-per-scope limit. It's now split into one child ModuleScript per feature.
-- This module resolves everything the feature modules share — services, the Fusion
-- library, the reusable helpers/style constants, every RemoteEvent/RemoteFunction, and the
-- read-only currency values — into ONE `ctx` table that the entry script passes to each
-- module. Building it here (a separate scope) is also part of how we stay under the limit.
--
-- `ctx.services` is a small registry for the FEW cross-module functions (a module attaches
-- the functions it owns; another reads them at CALL time). This late binding mirrors the
-- old monolith's shared upvalues without coupling the modules to each other's internals:
--   • CurrencyHud  → updateHudSpirit / updateHudChi / updateHudRank / setJarCapacity
--   • Shop         → refreshZen
--   • WorldsMenu   → openWorlds
--   • ComingSoon   → showComingSoon
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UiHelpers = require(script.Parent.UiHelpers)
local PopupManager = require(script.Parent.PopupManager)

local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NumberFormat"))
local Juicy3D = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Juicy3D"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Live currency values (read-only on the client; the server owns them).
local statsFolder = player:WaitForChild("leaderstats")
local spiritPowerValue = statsFolder:WaitForChild("Spirit Power")
local chiValue = player:WaitForChild("Chi") -- second currency, parented to the Player

local function remote(name)
	return ReplicatedStorage:WaitForChild(name)
end

local ctx = {
	-- Services / engine
	Players = Players,
	ReplicatedStorage = ReplicatedStorage,
	Workspace = game:GetService("Workspace"),
	UserInputService = game:GetService("UserInputService"),
	TweenService = game:GetService("TweenService"),
	GuiService = game:GetService("GuiService"),

	-- Player
	player = player,
	playerGui = playerGui,

	-- Fusion + reusable libraries
	Fusion = Fusion,
	Children = Fusion.Children,
	OnEvent = Fusion.OnEvent,
	Juicy3D = Juicy3D,
	abbreviate = NumberFormat.abbreviate,
	PopupManager = PopupManager,

	-- Style constants + helpers (from UiHelpers)
	FONT = UiHelpers.FONT,
	OUTLINE = UiHelpers.OUTLINE,
	GOLD = UiHelpers.GOLD,
	SPIRIT_FILL = UiHelpers.SPIRIT_FILL,
	round = UiHelpers.round,
	stroke = UiHelpers.stroke,
	lighten = UiHelpers.lighten,
	darken = UiHelpers.darken,
	candyGradient = UiHelpers.candyGradient,
	commafy = UiHelpers.commafy,
	fmtMult = UiHelpers.fmtMult,
	getRankTitle = UiHelpers.getRankTitle,
	getRankColor = UiHelpers.getRankColor,

	-- Read-only currency state
	statsFolder = statsFolder,
	spiritPowerValue = spiritPowerValue,
	chiValue = chiValue,

	-- Shop tabs
	TABS = { "Zen", "Soul Jar" },
	DEFAULT_TAB = "Zen",

	-- Remotes (resolved once here, shared by the feature modules)
	openShopEvent = remote("OpenShop"),
	clickEarnEvent = remote("ClickEarn"),
	getZenStateFunc = remote("GetZenState"),
	buyZenFunc = remote("BuyZen"),
	getAscendStateFunc = remote("GetAscendState"),
	ascendFunc = remote("Ascend"),
	openAscendEvent = remote("OpenAscend"),
	getSoulJarStateFunc = remote("GetSoulJarState"),
	buySoulJarFunc = remote("BuySoulJar"),
	requestTravelEvent = remote("RequestTravel"),
	getWorldsStateFunc = remote("GetWorldsState"),
	openGroupRewardsEvent = remote("OpenGroupRewards"),
	getGroupRewardStateFunc = remote("GetGroupRewardState"),
	claimGroupRewardFunc = remote("ClaimGroupReward"),
	altarTouchedEvent = remote("AltarTouched"),
	convertSpiritToChiFunc = remote("ConvertSpiritToChi"),

	-- Late-bound cross-module functions (attached by the owning module, read at call time).
	services = {},
}

return ctx
