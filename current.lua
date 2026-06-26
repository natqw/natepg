_G.FARM_ACTIVE = true

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

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

-- ── IRIS LOAD ────────────────────────────────────────────
local Iris = nil
local irisOk, irisErr = pcall(function()
	local src = game:HttpGet("https://raw.githubusercontent.com/x0581/Iris-Exploit-Bundle/main/bundle.lua", true)
	Iris = loadstring(src)().Init(game.CoreGui)
end)
if not irisOk then
	warn("[Autofarm] Iris failed: " .. tostring(irisErr))
end

-- ── TOGGLE STATES ────────────────────────────────────────
-- These are the single source of truth for every toggle.
-- Iris checkboxes write into these. The farm loops read from these.
local toggles = {
	farm   = true,
	anti   = true,
	hazard = true,
	obby   = true,
}

-- Iris state objects (only created if Iris loaded)
local irisStates = {}
if Iris then
	irisStates.farm   = Iris.State(true)
	irisStates.anti   = Iris.State(true)
	irisStates.hazard = Iris.State(true)
	irisStates.obby   = Iris.State(true)
end

-- Called every frame by Iris to sync state → toggles table
local function syncToggles()
	if not Iris then return end
	toggles.farm   = irisStates.farm:get()
	toggles.anti   = irisStates.anti:get()
	toggles.hazard = irisStates.hazard:get()
	toggles.obby   = irisStates.obby:get()
	_G.FARM_ACTIVE = toggles.farm
end

-- Stats
local stats = {
	bombsPassed    = 0,
	obbysRun       = 0,
	hazardsAvoided = 0,
	staffDetected  = 0,
	lastEvent      = "Starting...",
}
local sessionStart = tick()

local function notify(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title=title; Text=text; Duration=3})
	end)
end

notify("AUTOFARM", "Active" .. (Iris and " + UI" or " (no UI)"))

-- ── CHARACTER REFRESH ────────────────────────────────────
localPlayer.CharacterAdded:Connect(function(char)
	character = char
	rootPart  = char:WaitForChild("HumanoidRootPart")
	humanoid  = char:WaitForChild("Humanoid")
end)

-- ── UTILS ────────────────────────────────────────────────
local function freezeRig()
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = true; task.wait(0.1); hum.PlatformStand = false end
end

local function teleportToSpawn()
	rootPart.CFrame = CFrame.new(Vector3.new(64.0, 21.3, 177.9))
	freezeRig()
end

local function formatTime(s)
	return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60))
end

-- ── ANTI STAFF ───────────────────────────────────────────
local function isInTargetGroup(player)
	local ok, res = pcall(function() return player:IsInGroup(GROUP_ID) end)
	return ok and res
end

local function leaveServer()
	stats.staffDetected += 1
	stats.lastEvent = "Staff detected — rejoining"
	notify("ANTI STAFF", "Staff detected — rejoining")
	task.wait(1)
	local ok = pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
	if not ok then pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer) end) end
end

Players.PlayerAdded:Connect(function(player)
	if player.UserId == localPlayer.UserId then return end
	task.wait(2)
	if toggles.anti and isInTargetGroup(player) then leaveServer() end
end)

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		if not toggles.anti then continue end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId ~= localPlayer.UserId and isInTargetGroup(p) then
				leaveServer(); break
			end
		end
	end
end)

-- ── PLAYER DETECTION ─────────────────────────────────────
local function isPlayerInGame(player)
	if player == localPlayer then return false end
	if not player.Character then return false end
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	local pRoot = player.Character:FindFirstChild("HumanoidRootPart")
	if not pRoot or pRoot.Anchored then return false end
	local y = pRoot.Position.Y
	if y < PLAYING_MIN_Y or y > PLAYING_MAX_Y or y < -10 then return false end
	if hum.PlatformStand then return false end
	return true
end

local function getAlivePlayers()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do if isPlayerInGame(p) then n += 1 end end
	return n
end

-- ── PLATE ────────────────────────────────────────────────
local function playerOnPlate(player)
	local pRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not pRoot then return false end
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = {player.Character}
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(pRoot.Position, Vector3.new(0,-5,0), rp)
	return hit and hit.Instance and hit.Instance.Name:lower():find("plate") ~= nil
end

local function isOnPlate()
	if not character or not rootPart then return false end
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = {character}
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(rootPart.Position, Vector3.new(0,-5,0), rp)
	return hit and hit.Instance and hit.Instance.Name:lower():find("plate") ~= nil
end

-- ── BOMB ─────────────────────────────────────────────────
local function findBombTool()
	local function check(item)
		if not item then return nil end
		local n = item.Name:lower()
		if n:find("bomb") or n:find("potato") or n:find("hot") then return item end
	end
	local bp = localPlayer:FindFirstChildOfClass("Backpack")
	if bp then for _, i in ipairs(bp:GetChildren()) do local r = check(i); if r then return r end end end
	for _, i in ipairs(character:GetChildren()) do if i:IsA("Tool") then local r = check(i); if r then return r end end end
	return nil
end

local function hasBomb() return findBombTool() ~= nil end

local function passBomb()
	local plateTarget, plateDist = nil, math.huge
	local fallback, fallDist = nil, math.huge

	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == localPlayer.UserId or not isPlayerInGame(p) then continue end
		local tr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if not tr then continue end
		local d = (rootPart.Position - tr.Position).Magnitude
		if playerOnPlate(p) then
			if d < plateDist then plateDist = d; plateTarget = p end
		else
			if d < fallDist then fallDist = d; fallback = p end
		end
	end

	local target = plateTarget or fallback
	if not target or not target.Character then return end
	local tr = target.Character:FindFirstChild("HumanoidRootPart")
	if not tr then return end
	local tool = findBombTool()
	if not tool then return end

	stats.lastEvent = "Passing bomb → " .. target.Name
	humanoid:EquipTool(tool)
	task.wait(0.2)

	local sp, tp = rootPart.Position, tr.Position
	for i = 1, 8 do
		if not toggles.farm then return end  -- stop mid-pass if toggled off
		rootPart.CFrame = CFrame.new(sp:Lerp(tp, i/8))
		task.wait(0.03)
	end

	local equipped = character:FindFirstChildOfClass("Tool")
	if equipped then
		local ev = equipped:FindFirstChild("RemoteEvent") or equipped:FindFirstChild("ActivateEvent")
		if ev then ev:FireServer() else equipped:Activate() end
	end

	task.wait(0.15)
	humanoid:UnequipTools()
	task.wait(0.1)
	teleportToSpawn()
	stats.bombsPassed += 1
	stats.lastEvent = "Bomb passed to " .. target.Name
end

-- ── HAZARD AVOIDANCE ─────────────────────────────────────
local HAZARD_DETECT_RADIUS = 20
local HAZARD_FLEE_DIST     = 35
local HAZARD_CHECK_RATE    = 0.5
local lastFlee             = 0
local HAZARD_FLEE_COOLDOWN = 0.8
local hazardParts          = {}

local HAZARD_COLORS = {
	Color3.fromRGB(0,0,255), Color3.fromRGB(0,120,255),
	Color3.fromRGB(0,170,255), Color3.fromRGB(30,80,220), Color3.fromRGB(0,200,255),
}
local function colorDist(a,b) return math.abs(a.R-b.R)+math.abs(a.G-b.G)+math.abs(a.B-b.B) end
local function isBlue(c) for _,h in ipairs(HAZARD_COLORS) do if colorDist(c,h)<0.35 then return true end end return false end
local function ownedByPlayer(part) for _,p in ipairs(Players:GetPlayers()) do if p.Character and part:IsDescendantOf(p.Character) then return true end end return false end

local function tryRegister(part)
	if not part:IsA("BasePart") then return end
	local n = part.Name:lower()
	if n=="baseplate" or n=="terrain" or n=="spawn" then return end
	if ownedByPlayer(part) then return end
	if isBlue(part.Color) then hazardParts[part] = true end
end

task.spawn(function() for _,o in ipairs(Workspace:GetDescendants()) do tryRegister(o) end end)
Workspace.DescendantAdded:Connect(tryRegister)
Workspace.DescendantRemoving:Connect(function(o) hazardParts[o] = nil end)

task.spawn(function()
	while true do
		task.wait(HAZARD_CHECK_RATE)
		if not rootPart or not toggles.hazard then continue end
		if tick() - lastFlee < HAZARD_FLEE_COOLDOWN then continue end
		local nearest, nearDist = nil, math.huge
		for part in pairs(hazardParts) do
			if not part.Parent then hazardParts[part]=nil; continue end
			local ok,d = pcall(function() return (rootPart.Position-part.Position).Magnitude end)
			if ok and d < nearDist then nearDist=d; nearest=part end
		end
		if nearest and nearDist < HAZARD_DETECT_RADIUS then
			lastFlee = tick()
			local fd = (rootPart.Position - nearest.Position)
			fd = Vector3.new(fd.X,0,fd.Z).Unit
			local fp = rootPart.Position + fd * HAZARD_FLEE_DIST
			rootPart.CFrame = CFrame.new(Vector3.new(fp.X, rootPart.Position.Y, fp.Z))
			freezeRig()
			stats.hazardsAvoided += 1
			stats.lastEvent = "Hazard avoided!"
		end
	end
end)

-- ── OBBY ─────────────────────────────────────────────────
local function runObby()
	-- Check obby toggle AND farm toggle before starting
	if obbyCooldown or not toggles.obby or not toggles.farm then return end
	obbyCooldown = true
	stats.lastEvent = "Running obby..."

	local sp = rootPart.Position
	local el = OBBY_START_POS + Vector3.new(0,4,0)
	rootPart.CFrame = CFrame.lookAt(sp, Vector3.new(OBBY_START_POS.X,sp.Y,OBBY_START_POS.Z))
	task.wait(0.05)

	for i=1,12 do
		-- Bail out mid-obby if either toggle is turned off
		if not toggles.farm or not toggles.obby then
			obbyCooldown = false
			return
		end
		rootPart.CFrame = CFrame.new(sp:Lerp(el, i/12))
		task.wait(0.05)
	end

	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.new(0,50,0); bv.MaxForce = Vector3.new(0,math.huge,0); bv.Parent = rootPart
	task.wait(0.15); bv:Destroy()
	rootPart.CFrame = CFrame.new(el); freezeRig()

	task.wait(2)
	if not toggles.farm or not toggles.obby then obbyCooldown = false; return end

	rootPart.CFrame = CFrame.new(OBBY_END_POS + Vector3.new(0,4,0)); freezeRig()
	task.wait(3)
	if not toggles.farm or not toggles.obby then obbyCooldown = false; return end

	teleportToSpawn()
	stats.obbysRun += 1
	stats.lastEvent = "Obby done (+300 shards)"
	notify("OBBY", "Completed — 300 shards")
	task.delay(OBBY_COOLDOWN, function() obbyCooldown = false end)
end

-- ── SERVER HOP ───────────────────────────────────────────
task.spawn(function()
	task.wait(600)
	if not toggles.farm then return end
	stats.lastEvent = "Server hopping..."
	notify("SERVER HOP", "10 minutes — joining new server")
	task.wait(1)
	local ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer) end)
	if not ok then pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end) end
end)

-- ── IRIS UI ──────────────────────────────────────────────
if Iris then
	Iris:Connect(function()
		-- Sync Iris checkboxes → toggles table every frame
		syncToggles()

		Iris.Window({"Autofarm"})

			Iris.Tree({"[ Status ]"})
				Iris.Text({"Session:         " .. formatTime(tick() - sessionStart)})
				Iris.Text({"Players in game: " .. getAlivePlayers()})
				Iris.Text({"Has bomb:        " .. (hasBomb() and "YES!" or "no")})
				Iris.Text({"On plate:        " .. (isOnPlate() and "YES" or "no")})
				Iris.Text({"Last event:      " .. stats.lastEvent})
			Iris.End()

			Iris.Tree({"[ Modules ]"})
				Iris.Checkbox({"Autofarm active"}, {isChecked = irisStates.farm})
				Iris.Checkbox({"Anti-staff"},       {isChecked = irisStates.anti})
				Iris.Checkbox({"Hazard avoidance"}, {isChecked = irisStates.hazard})
				Iris.Checkbox({"Obby farm"},        {isChecked = irisStates.obby})
			Iris.End()

			Iris.Tree({"[ Stats ]"})
				Iris.Text({"Bombs passed:   " .. stats.bombsPassed})
				Iris.Text({"Obbys done:     " .. stats.obbysRun})
				Iris.Text({"Hazards dodged: " .. stats.hazardsAvoided})
				Iris.Text({"Staff detected: " .. stats.staffDetected})
			Iris.End()

			Iris.Tree({"[ Actions ]"})
				if Iris.Button({"Teleport to Spawn"}).clicked() then
					teleportToSpawn()
					stats.lastEvent = "Manual spawn tp"
				end
				if Iris.Button({"Server Hop Now"}).clicked() then
					stats.lastEvent = "Manual server hop..."
					task.spawn(function()
						task.wait(0.5)
						local ok = pcall(function()
							TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
						end)
						if not ok then pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end) end
					end)
				end
			Iris.End()

		Iris.End()
	end)
end

-- ── MAIN LOOP ────────────────────────────────────────────
task.spawn(function()
	while true do
		task.wait(0.3)

		-- If farm is off, just idle and keep checking
		if not toggles.farm then
			stats.lastEvent = "Paused"
			continue
		end

		character = localPlayer.Character
		if not character then continue end
		rootPart = character:FindFirstChild("HumanoidRootPart")
		humanoid = character:FindFirstChildOfClass("Humanoid")
		if not rootPart or not humanoid then continue end

		-- Bomb always takes priority when farm is on
		if hasBomb() then
			passBomb()
			continue
		end

		-- Obby only runs if its toggle is on
		if toggles.obby then
			runObby()
		end

		-- Get off plate to avoid elimination
		if isOnPlate() and getAlivePlayers() > 1 then
			teleportToSpawn()
		end
	end
end)