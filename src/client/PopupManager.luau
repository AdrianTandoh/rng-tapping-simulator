-- Ancient Spirit Simulator — single-popup-at-a-time manager.
--
-- Every popup (Shop, Ascend, Group Rewards, Worlds, Coming Soon) registers its ScreenGui
-- here. Opening one through PopupManager.open() automatically disables every other
-- registered popup, so two can never be open at once. Adding a new popup is just:
-- register(gui) once, then open(gui) / close(gui).
--
-- A singleton shared across all the client modules (extracted verbatim from the old
-- monolithic client script during the module split).
local PopupManager = {}
PopupManager._registered = {} -- list of ScreenGuis

function PopupManager.register(gui)
	table.insert(PopupManager._registered, gui)
end

function PopupManager.open(gui)
	-- Enable the requested popup, disable all the others.
	for _, other in ipairs(PopupManager._registered) do
		other.Enabled = (other == gui)
	end
end

function PopupManager.close(gui)
	gui.Enabled = false
end

return PopupManager
