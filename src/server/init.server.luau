-- Ancient Spirit Simulator
-- Feature 1: Core meditation loop
--
-- Players earn the "Spirit Power" stat by standing on a meditation pad.
-- Everything here runs on the SERVER, so the game is server-authoritative:
-- the client can never directly change a player's Spirit Power.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- How much Spirit Power to grant for each full second spent meditating.
local POWER_PER_SECOND = 5

--------------------------------------------------------------------------------
-- 1. Build the meditation pad
--------------------------------------------------------------------------------
-- We create the pad from code so nothing has to be placed manually in Studio.
-- It's an anchored, glowing (Neon) part sitting at the world origin, resting on
-- top of the baseplate so players can walk onto it.

local pad = Instance.new("Part")
pad.Name = "MeditationPad"
pad.Size = Vector3.new(12, 1, 12)
-- Position so the pad's bottom sits on the baseplate top (y = 0) and its
-- walkable surface is at y = 1. Centered on the world origin.
pad.Position = Vector3.new(0, 0.5, 0)
pad.Anchored = true -- never falls or gets pushed around
pad.Material = Enum.Material.Neon -- makes it glow
pad.Color = Color3.fromRGB(120, 220, 255) -- soft spirit-blue
pad.TopSurface = Enum.SurfaceType.Smooth
pad.BottomSurface = Enum.SurfaceType.Smooth
pad.Parent = Workspace

-- Precompute the pad's top surface height and horizontal half-size once.
-- We use these every frame to test whether a player is standing on the pad.
local padTopY = pad.Position.Y + pad.Size.Y / 2
local padHalfX = pad.Size.X / 2
local padHalfZ = pad.Size.Z / 2

--------------------------------------------------------------------------------
-- 2. Give every player a leaderstats folder
--------------------------------------------------------------------------------
-- Roblox automatically shows any IntValue/NumberValue inside a "leaderstats"
-- folder on the in-game leaderboard. We create one Spirit Power value per player.

local function setupLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local spiritPower = Instance.new("IntValue")
	spiritPower.Name = "Spirit Power"
	spiritPower.Value = 0 -- everyone starts with zero
	spiritPower.Parent = leaderstats

	leaderstats.Parent = player
end

-- Handle players who join after this script runs...
Players.PlayerAdded:Connect(setupLeaderstats)
-- ...and any players who somehow already exist (e.g. fast Studio start).
for _, player in ipairs(Players:GetPlayers()) do
	setupLeaderstats(player)
end

--------------------------------------------------------------------------------
-- 3. Decide whether a player is standing on the pad
--------------------------------------------------------------------------------
-- We check the player's HumanoidRootPart against the pad's bounds rather than
-- relying on Touched events, which can be unreliable. A player counts as "on
-- the pad" if they are alive, horizontally within the pad, and resting near its
-- top surface.

local function isStandingOnPad(player)
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end

	local position = root.Position

	-- Horizontal check: are they over the pad footprint?
	if math.abs(position.X - pad.Position.X) > padHalfX then
		return false
	end
	if math.abs(position.Z - pad.Position.Z) > padHalfZ then
		return false
	end

	-- Vertical check: are they roughly at pad level (not flying overhead or
	-- standing under it)? The root part floats a few studs above the feet.
	if position.Y < padTopY or position.Y > padTopY + 6 then
		return false
	end

	return true
end

--------------------------------------------------------------------------------
-- 4. The meditation loop (Heartbeat-based per-second timer)
--------------------------------------------------------------------------------
-- Heartbeat fires every frame and hands us the time since the last frame (dt).
-- We accumulate that time and, once a full second has passed, grant Spirit Power
-- to every player currently standing on the pad. This avoids wait() loops and
-- keeps the timing accurate regardless of frame rate.

local accumulator = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt

	-- Award once per whole second. A "while" handles the rare case where a
	-- frame hitch makes more than one second pass at once.
	while accumulator >= 1 do
		accumulator -= 1

		for _, player in ipairs(Players:GetPlayers()) do
			if isStandingOnPad(player) then
				local leaderstats = player:FindFirstChild("leaderstats")
				local spiritPower = leaderstats and leaderstats:FindFirstChild("Spirit Power")
				if spiritPower then
					spiritPower.Value += POWER_PER_SECOND
				end
			end
		end
	end
end)
