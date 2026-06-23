-- Ancient Spirit Simulator — per-player world visibility (W2b).
--
-- STATE comes from the server as replicated Player ATTRIBUTES (WorldAtHub / WorldIndex);
-- RENDERING is controlled LOCALLY via LocalTransparencyModifier (+ disabling Guis/Lights
-- and hiding face Decals). A player sees a WORLD iff it's the world they're in, and sees
-- another PLAYER iff that player shares their "view key" (both in the hub, or both in the
-- same world). We only manage RENDERING (never CanCollide) — areas are ~1600 studs apart.
--
-- Extracted verbatim from the old monolithic client script during the module split.
return function(ctx)
	local Players = ctx.Players
	local Workspace = ctx.Workspace
	local player = ctx.player
	local getWorldsStateFunc = ctx.getWorldsStateFunc

	-- Discover the server-built world models, using the authoritative world count.
	local worldsState = getWorldsStateFunc:InvokeServer()
	local worldModels = {} -- [index] = Model
	if worldsState then
		for _, w in ipairs(worldsState.worlds) do
			worldModels[w.index] = Workspace:WaitForChild("World" .. w.index, 15)
		end
	end

	local origDecalTransparency = {} -- [Decal/Texture] = original Transparency (for restore)

	-- Apply visibility to a single instance (client-local only).
	local function applyOne(d, visible)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = visible and 0 or 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if origDecalTransparency[d] == nil then
				origDecalTransparency[d] = d.Transparency
			end
			d.Transparency = visible and origDecalTransparency[d] or 1
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d.Enabled = visible
		elseif d:IsA("Light") then
			d.Enabled = visible
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
			or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
			d.Enabled = visible
		elseif d:IsA("Humanoid") then
			-- Hide the floating name/health bar when a character is hidden.
			d.NameDisplayDistance = visible and 100 or 0
			d.HealthDisplayDistance = visible and 100 or 0
		end
	end

	local function setRendered(root, visible)
		if not root then
			return
		end
		if root:IsA("BasePart") then
			applyOne(root, visible)
		end
		for _, d in ipairs(root:GetDescendants()) do
			applyOne(d, visible)
		end
	end

	-- "View key": who/what shares a space. Mirrors the server — hub players share "hub";
	-- world players share their world index.
	local function viewKeyOf(plr)
		local atHubAttr = plr:GetAttribute("WorldAtHub")
		if atHubAttr == nil then
			atHubAttr = true -- default to hub until the server publishes the real value
		end
		if atHubAttr then
			return "hub"
		end
		return "world" .. tostring(plr:GetAttribute("WorldIndex") or 1)
	end

	-- Show only the world we're in; hide the rest (hub geometry is never in a world model).
	local function updateGeometry()
		local myKey = viewKeyOf(player)
		for index, model in pairs(worldModels) do
			setRendered(model, myKey == ("world" .. index))
		end
	end

	-- Characters can load parts late (accessories), so we remember the desired visibility per
	-- character and re-apply to any descendant that streams in afterwards.
	local charVisible = {} -- [character] = desired visible bool
	local charConns = {} -- [character] = DescendantAdded connection

	local function applyCharacter(char, visible)
		charVisible[char] = visible
		setRendered(char, visible)
		if not charConns[char] then
			charConns[char] = char.DescendantAdded:Connect(function(d)
				applyOne(d, charVisible[char] ~= false)
			end)
		end
	end

	local function updatePlayer(other)
		if other == player then
			return -- we always see ourselves
		end
		local char = other.Character
		if char then
			applyCharacter(char, viewKeyOf(other) == viewKeyOf(player))
		end
	end

	local function updateAllPlayers()
		for _, other in ipairs(Players:GetPlayers()) do
			updatePlayer(other)
		end
	end

	-- Hook one player's signals: re-evaluate when they travel (attributes) or respawn.
	local function trackPlayer(other)
		local function onAttr()
			if other == player then
				-- OUR location changed (we traveled): re-render geometry + re-check everyone.
				updateGeometry()
				updateAllPlayers()
			else
				updatePlayer(other)
			end
		end
		other:GetAttributeChangedSignal("WorldAtHub"):Connect(onAttr)
		other:GetAttributeChangedSignal("WorldIndex"):Connect(onAttr)
		other.CharacterAdded:Connect(function()
			task.wait(0.1) -- let the core parts replicate before we hide/show
			updatePlayer(other)
		end)
		other.CharacterRemoving:Connect(function(char)
			if charConns[char] then
				charConns[char]:Disconnect()
				charConns[char] = nil
			end
			charVisible[char] = nil
		end)
	end

	for _, other in ipairs(Players:GetPlayers()) do
		trackPlayer(other)
	end
	Players.PlayerAdded:Connect(trackPlayer)

	-- Initial paint.
	updateGeometry()
	updateAllPlayers()
end
