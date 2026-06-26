_G.FARM_ACTIVE = true

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

local GROUP_ID = 1063978185
local CHECK_INTERVAL = 3
local OBBY_START_POS = Vector3.new(122.9, 14.0, 168.8)
local OBBY_END_POS   = Vector3.new(175.4, 14.3, 246.0)
local obbyCooldown = false
local OBBY_COOLDOWN = 150

local PLAYING_MIN_Y = 5
local PLAYING_MAX_Y = 200

StarterGui:SetCore("SendNotification", {
	Title = "AUTOFARM + ANTI STAFF";
	Text = "ACTIVE";
	Duration = 4;
})

-- ── CHARACTER REFRESH ────────────────────────────────────
localPlayer.CharacterAdded:Connect(function(char)
	character = char
	rootPart = char:WaitForChild("HumanoidRootPart")
	humanoid = char:WaitForChild("Humanoid")
end)

-- ── UTILS ────────────────────────────────────────────────
local function freezeRig()
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = true
		task.wait(0.1)
		hum.PlatformStand = false
	end
end

local function teleportToSpawn()
	rootPart.CFrame = CFrame.new(Vector3.new(64.0, 21.3, 177.9))
	freezeRig()
end

-- ── ANTI STAFF ───────────────────────────────────────────
local function isInTargetGroup(player)
	local success, result = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	return success and result
end

local function leaveServer()
	StarterGui:SetCore("SendNotification", {
		Title = "ANTI STAFF";
		Text = "Staff detected — rejoining";
		Duration = 4;
	})
	task.wait(1)
	local success = pcall(function()
		TeleportService:Teleport(game.PlaceId, localPlayer)
	end)
	if not success then
		pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	if player.UserId == localPlayer.UserId then return end
	task.wait(2)
	if isInTargetGroup(player) then leaveServer() end
end)

task.spawn(function()
	while _G.FARM_ACTIVE do
		for _, player in ipairs(Players:GetPlayers()) do
			if player.UserId ~= localPlayer.UserId and isInTargetGroup(player) then
				leaveServer()
				return
			end
		end
		task.wait(CHECK_INTERVAL)
	end
end)

-- ── ALIVE + PLAYING DETECTION ────────────────────────────
local function isPlayerInGame(player)
	if player == localPlayer then return false end
	if not player.Character then return false end

	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end

	local pRoot = player.Character:FindFirstChild("HumanoidRootPart")
	if not pRoot then return false end
	if pRoot.Anchored then return false end

	local y = pRoot.Position.Y
	if y < PLAYING_MIN_Y or y > PLAYING_MAX_Y then return false end
	if hum.PlatformStand then return false end
	if y < -10 then return false end

	return true
end

local function isPlayerAlive(player)
	return isPlayerInGame(player)
end

local function getAlivePlayers()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if isPlayerInGame(player) then count = count + 1 end
	end
	return count
end

-- ── PLATE ────────────────────────────────────────────────
local function isOnPlate()
	local ray = RaycastParams.new()
	ray.FilterDescendantsInstances = {character}
	ray.FilterType = Enum.RaycastFilterType.Exclude
	local result = Workspace:Raycast(rootPart.Position, Vector3.new(0, -5, 0), ray)
	if result and result.Instance then
		return result.Instance.Name:lower():find("plate") ~= nil
	end
	return false
end

-- ── BOMB ─────────────────────────────────────────────────
local function hasBomb()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			local n = item.Name:lower()
			if n:find("bomb") or n:find("potato") or n:find("hot") then return true end
		end
	end
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Tool") then
			local n = item.Name:lower()
			if n:find("bomb") or n:find("potato") or n:find("hot") then return true end
		end
	end
	return false
end

local function findBombTool()
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			local n = item.Name:lower()
			if n:find("bomb") or n:find("potato") or n:find("hot") then return item end
		end
	end
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Tool") then
			local n = item.Name:lower()
			if n:find("bomb") or n:find("potato") or n:find("hot") then return item end
		end
	end
	return nil
end

local function passBomb()
	local nearest, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == localPlayer.UserId then continue end
		if not isPlayerInGame(player) then continue end

		local targetRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not targetRoot then continue end

		local dist = (rootPart.Position - targetRoot.Position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = player
		end
	end

	if not nearest or not nearest.Character then return end

	local targetRoot = nearest.Character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	local bombTool = findBombTool()
	if not bombTool then return end

	humanoid:EquipTool(bombTool)
	task.wait(0.2)

	local startPos = rootPart.Position
	local targetPos = targetRoot.Position
	local steps = 8
	for i = 1, steps do
		if not _G.FARM_ACTIVE then return end
		rootPart.CFrame = CFrame.new(startPos:Lerp(targetPos, i / steps))
		task.wait(0.03)
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		local fireEvent = tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("ActivateEvent")
		if fireEvent then
			fireEvent:FireServer()
		else
			tool:Activate()
		end
	end

	task.wait(0.15)
	humanoid:UnequipTools()
	task.wait(0.1)
	teleportToSpawn()
end

-- ── BLUE HAZARD AVOIDANCE (event-driven, zero per-frame scanning) ──
local HAZARD_DETECT_RADIUS = 20
local HAZARD_FLEE_DIST     = 35
local HAZARD_CHECK_RATE    = 0.5   -- only poll position, no part scanning
local lastFlee             = 0
local HAZARD_FLEE_COOLDOWN = 0.8

-- Cached set of blue hazard parts — built once, kept up to date by events
local hazardParts = {}

local HAZARD_COLORS = {
	Color3.fromRGB(0,   0,   255),
	Color3.fromRGB(0,   120, 255),
	Color3.fromRGB(0,   170, 255),
	Color3.fromRGB(30,  80,  220),
	Color3.fromRGB(0,   200, 255),
}

local function colorDistance(a, b)
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
end

local function isBlueColor(color)
	for _, c in ipairs(HAZARD_COLORS) do
		if colorDistance(color, c) < 0.35 then return true end
	end
	return false
end

local function isOwnedByPlayer(part)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and part:IsDescendantOf(p.Character) then
			return true
		end
	end
	return false
end

local function tryRegisterHazard(part)
	if not part:IsA("BasePart") then return end
	local lower = part.Name:lower()
	if lower == "baseplate" or lower == "terrain" or lower == "spawn" then return end
	if isOwnedByPlayer(part) then return end
	if isBlueColor(part.Color) then
		hazardParts[part] = true
	end
end

-- Build cache from existing workspace contents once at start
-- Do this in a task so it doesn't block script startup
task.spawn(function()
	for _, obj in ipairs(Workspace:GetDescendants()) do
		tryRegisterHazard(obj)
	end
end)

-- Keep cache up to date via events — zero cost during gameplay
Workspace.DescendantAdded:Connect(function(obj)
	tryRegisterHazard(obj)
end)

Workspace.DescendantRemoving:Connect(function(obj)
	hazardParts[obj] = nil
end)

-- Cheap position-only loop — just iterates the small hazard set
local function getNearestHazard()
	local nearest, nearestDist = nil, math.huge
	for part in pairs(hazardParts) do
		-- part may have been removed from workspace without firing DescendantRemoving
		if not part.Parent then
			hazardParts[part] = nil
			continue
		end
		local ok, dist = pcall(function()
			return (rootPart.Position - part.Position).Magnitude
		end)
		if ok and dist < nearestDist then
			nearestDist = dist
			nearest = part
		end
	end
	return nearest, nearestDist
end

task.spawn(function()
	while _G.FARM_ACTIVE do
		task.wait(HAZARD_CHECK_RATE)
		if not rootPart then continue end

		local now = tick()
		if now - lastFlee < HAZARD_FLEE_COOLDOWN then continue end

		local hazard, dist = getNearestHazard()
		if hazard and dist < HAZARD_DETECT_RADIUS then
			lastFlee = now

			local fleeDir = (rootPart.Position - hazard.Position)
			fleeDir = Vector3.new(fleeDir.X, 0, fleeDir.Z).Unit
			local fleePos = rootPart.Position + fleeDir * HAZARD_FLEE_DIST

			rootPart.CFrame = CFrame.new(
				Vector3.new(fleePos.X, rootPart.Position.Y, fleePos.Z)
			)
			freezeRig()

			StarterGui:SetCore("SendNotification", {
				Title = "HAZARD";
				Text = "Blue hazard avoided!";
				Duration = 1;
			})
		end
	end
end)

-- ── OBBY ─────────────────────────────────────────────────
local function walkAndJumpToBlock(targetPos)
	local startPos = rootPart.Position
	local elevated = targetPos + Vector3.new(0, 4, 0)
	rootPart.CFrame = CFrame.lookAt(startPos, Vector3.new(targetPos.X, startPos.Y, targetPos.Z))
	task.wait(0.05)
	local steps = 12
	for i = 1, steps do
		if not _G.FARM_ACTIVE then return end
		rootPart.CFrame = CFrame.new(startPos:Lerp(elevated, i / steps))
		task.wait(0.05)
	end
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.new(0, 50, 0)
	bv.MaxForce = Vector3.new(0, math.huge, 0)
	bv.Parent = rootPart
	task.wait(0.15)
	bv:Destroy()
	rootPart.CFrame = CFrame.new(elevated)
	freezeRig()
end

local function runObby()
	if obbyCooldown then return end
	obbyCooldown = true

	walkAndJumpToBlock(OBBY_START_POS)
	task.wait(2)
	rootPart.CFrame = CFrame.new(OBBY_END_POS + Vector3.new(0, 4, 0))
	freezeRig()
	task.wait(3)
	teleportToSpawn()

	StarterGui:SetCore("SendNotification", {
		Title = "OBBY";
		Text = "Completed — 300 shards";
		Duration = 3;
	})

	task.delay(OBBY_COOLDOWN, function()
		obbyCooldown = false
	end)
end

-- ── AUTO SERVER HOP (every 10 minutes) ──────────────────
task.spawn(function()
	task.wait(600) -- 10 minutes
	if not _G.FARM_ACTIVE then return end
	StarterGui:SetCore("SendNotification", {
		Title = "SERVER HOP";
		Text = "10 minutes up — joining new server";
		Duration = 4;
	})
	task.wait(1)
	local success = pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
	end)
	if not success then
		pcall(function()
			TeleportService:Teleport(game.PlaceId, localPlayer)
		end)
	end
end)

-- ── MAIN LOOP ────────────────────────────────────────────
task.spawn(function()
	while _G.FARM_ACTIVE do
		task.wait(0.5)
		character = localPlayer.Character
		if not character then continue end
		rootPart = character:FindFirstChild("HumanoidRootPart")
		humanoid = character:FindFirstChildOfClass("Humanoid")
		if not rootPart or not humanoid then continue end

		if hasBomb() then
			passBomb()
			continue
		end

		runObby()

		if isOnPlate() then
			if getAlivePlayers() > 1 then
				teleportToSpawn()
			end
		end
	end

	StarterGui:SetCore("SendNotification", {
		Title = "AUTOFARM";
		Text = "Unloaded";
		Duration = 3;
	})
end)