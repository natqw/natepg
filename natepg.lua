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
local OBBY_COOLDOWN = 125

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

-- ── ALIVE DETECTION ──────────────────────────────────────
local function isPlayerAlive(player)
	if player == localPlayer then return false end
	if not player.Character then return false end
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	local pRoot = player.Character:FindFirstChild("HumanoidRootPart")
	if not pRoot then return false end
	if pRoot.Anchored then return false end
	if pRoot.Position.Y < -10 then return false end
	return true
end

local function getAlivePlayers()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if isPlayerAlive(player) then count = count + 1 end
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

local function passBomb()
	local nearest, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if not isPlayerAlive(player) then continue end
		if player.Character then
			local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				local dist = (rootPart.Position - targetRoot.Position).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearest = player
				end
			end
		end
	end

	if not nearest or not nearest.Character then return end
	local targetRoot = nearest.Character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	local bombTool = nil
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			local n = item.Name:lower()
			if n:find("bomb") or n:find("potato") or n:find("hot") then
				bombTool = item
				break
			end
		end
	end
	if not bombTool then
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Tool") then
				local n = item.Name:lower()
				if n:find("bomb") or n:find("potato") or n:find("hot") then
					bombTool = item
					break
				end
			end
		end
	end

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
		if fireEvent then fireEvent:FireServer() else tool:Activate() end
	end

	task.wait(0.15)
	humanoid:UnequipTools()
	task.wait(0.1)
	teleportToSpawn()
end

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
