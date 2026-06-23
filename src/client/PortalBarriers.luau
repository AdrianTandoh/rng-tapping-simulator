-- Ancient Spirit Simulator — locked-world portal barriers (W3, per-player, client-local).
--
-- The unlock GATE itself is server-authoritative: the server refuses travel to a world the
-- player hasn't unlocked (that logic is untouched). This module is the PHYSICAL/UX half. For
-- every world this player hasn't unlocked, it puts a SOLID, semi-transparent "locked" barrier
-- with a padlock across that world's HUB portal, so the player visibly bumps into it instead
-- of walking through dead space and wondering why nothing happened.
--
-- WHY CLIENT-LOCAL: unlock state is PER-PLAYER (one player may have World 2 unlocked while
-- another doesn't), but a single shared server Part with CanCollide would block EVERYONE. A
-- Part created on the client collides only with the LOCAL character and is invisible to other
-- players — exactly the per-player blocking we need. This is a UX aid only: a hacked client
-- could delete its own barrier, but the SERVER still refuses the teleport, so nothing is
-- gained by doing so.
--
-- The requirement message shows on BUMP (Touched) and on CLICK (ClickDetector). When a world
-- unlocks mid-session (the server's WorldUnlocked push), its barrier + padlock are removed
-- LIVE — the portal becomes a normal walk-through with no rejoin required. Unlocked worlds
-- never get a barrier in the first place.
return function(ctx)
	local Workspace = ctx.Workspace
	local player = ctx.player
	local getWorldsStateFunc = ctx.getWorldsStateFunc
	local worldUnlockedEvent = ctx.worldUnlockedEvent

	local LOCK_MSG_COLOR = Color3.fromRGB(150, 160, 180) -- matches the menu's muted "locked" text
	local BARRIER_TINT = Color3.fromRGB(210, 80, 80) -- reddish "locked" energy field

	local barriers = {} -- [index] = barrier Part (absent once unlocked / removed)
	local reqByIndex = {} -- [index] = { name, reqAscend, reqChi }

	-- Show the locked requirement via the shared travel toast owned by WorldsMenu (one feedback
	-- system for both the menu and the physical portals). Read at call time, so it's fine that
	-- WorldsMenu registered these services during its own init (it runs before this module).
	local function showRequirement(index)
		local r = reqByIndex[index]
		local toast = ctx.services.showTravelToast
		local fmt = ctx.services.requirementText
		if r and toast and fmt then
			toast(r.name .. " — " .. fmt(r.reqAscend, r.reqChi), LOCK_MSG_COLOR)
		end
	end

	local function removeBarrier(index)
		local b = barriers[index]
		if b then
			b:Destroy() -- takes the padlock BillboardGui + ClickDetector with it
			barriers[index] = nil
		end
	end

	-- Build the barrier across a (still-locked) world's hub portal, matching the portal's place
	-- and slightly overlapping it so the opening is fully covered (no slipping around an edge).
	local function createBarrier(index, portal)
		if barriers[index] then
			return
		end
		local barrier = Instance.new("Part")
		barrier.Name = "PortalBarrier" .. index
		barrier.Anchored = true
		barrier.CanCollide = true -- the whole point: physically blocks the local character
		barrier.CastShadow = false
		barrier.Size = portal.Size + Vector3.new(1.5, 2, 0.6) -- fully cover the portal opening
		barrier.CFrame = portal.CFrame
		barrier.Material = Enum.Material.ForceField -- shimmering + semi-transparent: clearly "blocked"
		barrier.Color = BARRIER_TINT
		barrier.Parent = Workspace

		-- Padlock on the barrier (matches the menu's 🔒), always camera-facing and on top.
		local badge = Instance.new("BillboardGui")
		badge.Name = "LockBadge"
		badge.Size = UDim2.fromScale(5, 5)
		badge.AlwaysOnTop = true
		badge.Adornee = barrier
		badge.Parent = barrier

		local lock = Instance.new("TextLabel")
		lock.BackgroundTransparency = 1
		lock.Size = UDim2.fromScale(1, 1)
		lock.Text = "🔒"
		lock.Font = Enum.Font.FredokaOne
		lock.TextScaled = true
		lock.TextColor3 = Color3.fromRGB(255, 255, 255)
		lock.TextStrokeTransparency = 0.3
		lock.TextStrokeColor3 = Color3.fromRGB(40, 10, 10)
		lock.Parent = badge

		-- Message on BUMP. Debounced so holding against the barrier doesn't spam the toast.
		local bumpDebounce = false
		barrier.Touched:Connect(function(hit)
			local char = player.Character
			if not char or not hit:IsDescendantOf(char) or bumpDebounce then
				return
			end
			bumpDebounce = true
			showRequirement(index)
			task.delay(1.5, function()
				bumpDebounce = false
			end)
		end)

		-- Message on CLICK / interact (the player may click the barrier instead of bumping it).
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 28
		click.Parent = barrier
		click.MouseClick:Connect(function()
			showRequirement(index)
		end)

		barriers[index] = barrier
	end

	-- Initial build: a barrier for every currently-locked world that has a hub portal. World 1
	-- (the starter) is always unlocked, so it's skipped by the `not w.unlocked` check.
	local state = getWorldsStateFunc:InvokeServer()
	if state then
		for _, w in ipairs(state.worlds) do
			reqByIndex[w.index] = { name = w.name, reqAscend = w.reqAscend, reqChi = w.reqChi }
			if not w.unlocked then
				local portal = Workspace:WaitForChild("HubPortal" .. w.index, 15)
				if portal then
					createBarrier(w.index, portal)
				end
			end
		end
	end

	-- Reactive: when a world unlocks, drop its barrier + padlock immediately (no rejoin), so the
	-- portal becomes a normal walk-through right away.
	worldUnlockedEvent.OnClientEvent:Connect(function(index)
		removeBarrier(index)
	end)
end
