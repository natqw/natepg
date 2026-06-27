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
local SPAWN_POS = Vector3.new(7.0, 21.3, 110.1)

-- ── IRIS LOAD ───────────────────────────────────────────
local Iris = nil
local irisOk, irisErr = pcall(function()
	local src = game:HttpGet("https://raw.githubusercontent.com/x0581/Iris-Exploit-Bundle/main/bundle.lua", true)
	Iris = loadstring(src)().Init(game.CoreGui)
end)
if not irisOk then warn("[Autofarm] Iris failed: " .. tostring(irisErr)) end

-- ── TOGGLE STATES ───────────────────────────────────────
local toggles = {
	farm    = true,
	anti    = true,
	hazard  = true,
	obby    = true,
	bless   = false,
	curse   = false,
	heal    = true,
	airdrop = true,
}

local irisStates = {}
if Iris then
	irisStates.farm    = Iris.State(true)
	irisStates.anti    = Iris.State(true)
	irisStates.hazard  = Iris.State(true)
	irisStates.obby    = Iris.State(true)
	irisStates.bless   = Iris.State(false)
	irisStates.curse   = Iris.State(false)
	irisStates.heal    = Iris.State(true)
	irisStates.airdrop = Iris.State(true)
end

local function syncToggles()
	if not Iris then return end
	toggles.farm    = irisStates.farm:get()
	toggles.anti    = irisStates.anti:get()
	toggles.hazard  = irisStates.hazard:get()
	toggles.obby    = irisStates.obby:get()
	toggles.bless   = irisStates.bless:get()
	toggles.curse   = irisStates.curse:get()
	toggles.heal    = irisStates.heal:get()
	toggles.airdrop = irisStates.airdrop:get()
	_G.FARM_ACTIVE  = toggles.farm
end

local stats = {
	bombsPassed    = 0,
	obbysRun       = 0,
	hazardsAvoided = 0,
	staffDetected  = 0,
	blessCount     = 0,
	curseCount     = 0,
	healsUsed      = 0,
	airdropsOpened = 0,
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
	if not rootPart then return end
	rootPart.CFrame = CFrame.new(SPAWN_POS)
	freezeRig()
end

local function formatTime(s)
	return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60))
end

local function getHealth()
	local hum = humanoid or (character and character:FindFirstChildOfClass("Humanoid"))
	if not hum then return 100, 100 end
	return hum.Health, hum.MaxHealth
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

-- ── PLATE DETECTION ──────────────────────────────────────
local function rayForPlate(origin, dir, filterChar)
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = {filterChar}
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(origin, dir, rp)
	return hit and hit.Instance and hit.Instance.Name:lower():find("plate") ~= nil
end

local function isOnPlate()
	if not character or not rootPart then return false end
	local pos = rootPart.Position
	local offsets = {
		Vector3.new(0,0,0),
		Vector3.new(1,0,0), Vector3.new(-1,0,0),
		Vector3.new(0,0,1), Vector3.new(0,0,-1),
	}
	for _, off in ipairs(offsets) do
		if rayForPlate(pos + off, Vector3.new(0,-8,0), character) then return true end
	end
	return false
end

local function playerOnPlate(player)
	if not player.Character then return false end
	local pRoot = player.Character:FindFirstChild("HumanoidRootPart")
	if not pRoot then return false end
	return rayForPlate(pRoot.Position, Vector3.new(0,-8,0), player.Character)
end

-- Returns the actual plate BasePart under local player, or nil
local function getMyPlate()
	if not character or not rootPart then return nil end
	local pos = rootPart.Position
	local offsets = {
		Vector3.new(0,0,0),
		Vector3.new(1,0,0), Vector3.new(-1,0,0),
		Vector3.new(0,0,1), Vector3.new(0,0,-1),
	}
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = {character}
	rp.FilterType = Enum.RaycastFilterType.Exclude
	for _, off in ipairs(offsets) do
		local hit = Workspace:Raycast(pos + off, Vector3.new(0,-8,0), rp)
		if hit and hit.Instance and hit.Instance.Name:lower():find("plate") then
			return hit.Instance
		end
	end
	return nil
end

local plateStuckTimer = 0
local PLATE_STUCK_LIMIT = 3.0

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
		if not toggles.farm then return end
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

-- ── HEALING ──────────────────────────────────────────────
local HEAL_THRESHOLD = 0.50  -- use heal below 50% hp
local HEAL_KEYWORDS  = {"medkit", "med kit", "heal", "health", "jar", "potion", "bandage", "kit"}
local lastHealTime   = 0
local HEAL_COOLDOWN  = 3  -- don't spam heals

local function findHealTool()
	local function check(item)
		if not item then return nil end
		local n = item.Name:lower()
		for _, kw in ipairs(HEAL_KEYWORDS) do
			if n:find(kw) then return item end
		end
		return nil
	end
	local bp = localPlayer:FindFirstChildOfClass("Backpack")
	if bp then for _, i in ipairs(bp:GetChildren()) do local r = check(i); if r then return r end end end
	for _, i in ipairs(character:GetChildren()) do
		if i:IsA("Tool") then local r = check(i); if r then return r end end
	end
	return nil
end

local function tryHeal()
	if not toggles.heal then return end
	if tick() - lastHealTime < HEAL_COOLDOWN then return end
	local hp, maxHp = getHealth()
	if hp <= 0 or maxHp <= 0 then return end
	if (hp / maxHp) >= HEAL_THRESHOLD then return end

	local tool = findHealTool()
	if not tool then return end

	lastHealTime = tick()
	stats.lastEvent = string.format("Using heal (HP: %d/%d)", math.floor(hp), math.floor(maxHp))

	-- Equip, activate, unequip
	humanoid:EquipTool(tool)
	task.wait(0.15)

	-- Try RemoteEvent first, then Activate
	local equipped = character:FindFirstChildOfClass("Tool")
	if equipped then
		local fired = false
		for _, ev in ipairs(equipped:GetDescendants()) do
			if ev:IsA("RemoteEvent") then
				pcall(function() ev:FireServer() end)
				fired = true; break
			end
		end
		if not fired then
			pcall(function() equipped:Activate() end)
		end
	end

	task.wait(0.3)
	humanoid:UnequipTools()
	stats.healsUsed += 1
	stats.lastEvent = "Heal used!"
end

-- Passive health watcher — heals immediately when HP drops below threshold
task.spawn(function()
	while true do
		task.wait(0.5)
		if not character or not rootPart then continue end
		tryHeal()
	end
end)

-- ── AIRDROP ──────────────────────────────────────────────
-- Airdrops are Models/Parts that land on your plate.
-- We detect them by name and proximity to your plate, then touch/interact with them.
local AIRDROP_KEYWORDS  = {"airdrop", "crate", "supply", "drop", "box", "chest", "loot"}
local AIRDROP_RADIUS    = 12  -- studs from plate center to count as "on your plate"
local lastAirdropTime   = 0
local AIRDROP_COOLDOWN  = 5
local openedAirdrops    = {}  -- track already-opened ones so we don't re-open

local function findAirdropOnPlate()
	local plate = getMyPlate()
	if not plate then return nil end
	local platePos = plate.Position

	for _, obj in ipairs(Workspace:GetChildren()) do
		-- Check models and parts
		local checkPart = nil
		if obj:IsA("Model") then
			checkPart = obj:FindFirstChildOfClass("BasePart") or obj.PrimaryPart
		elseif obj:IsA("BasePart") then
			checkPart = obj
		end
		if not checkPart then continue end

		-- Skip already opened
		if openedAirdrops[obj] then continue end

		-- Name check
		local nameLow = obj.Name:lower()
		local isAirdrop = false
		for _, kw in ipairs(AIRDROP_KEYWORDS) do
			if nameLow:find(kw) then isAirdrop = true; break end
		end
		if not isAirdrop then continue end

		-- Distance from our plate
		local dist = (checkPart.Position - platePos).Magnitude
		if dist <= AIRDROP_RADIUS then
			return obj, checkPart
		end
	end
	return nil, nil
end

local function tryOpenAirdrop()
	if not toggles.airdrop then return end
	if tick() - lastAirdropTime < AIRDROP_COOLDOWN then return end
	if not isOnPlate() then return end  -- only open airdrops while on your plate

	local airdrop, part = findAirdropOnPlate()
	if not airdrop or not part then return end

	lastAirdropTime = tick()
	openedAirdrops[airdrop] = true
	stats.lastEvent = "Airdrop found: " .. airdrop.Name

	-- Method 1: teleport to touch it
	local savedPos = rootPart.CFrame
	rootPart.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
	task.wait(0.1)

	-- Method 2: fire any ProximityPrompt on it
	for _, obj in ipairs(airdrop:GetDescendants()) do
		if obj:IsA("ProximityPrompt") then
			pcall(function()
				fireproximityprompt(obj)  -- executor function
			end)
			pcall(function()
				obj.Triggered:Fire(localPlayer)
			end)
		end
	end

	-- Method 3: fire any RemoteEvent with open/collect keywords
	for _, obj in ipairs(airdrop:GetDescendants()) do
		if obj:IsA("RemoteEvent") then
			local n = obj.Name:lower()
			if n:find("open") or n:find("collect") or n:find("claim") or n:find("use") or n:find("touch") then
				pcall(function() obj:FireServer() end)
				pcall(function() obj:FireServer(localPlayer) end)
			end
		end
	end

	-- Method 4: search ReplicatedStorage for open/airdrop remotes
	local RS = game:GetService("ReplicatedStorage")
	for _, obj in ipairs(RS:GetDescendants()) do
		if obj:IsA("RemoteEvent") then
			local n = obj.Name:lower()
			if n:find("airdrop") or n:find("crate") or n:find("open") or n:find("collect") then
				pcall(function() obj:FireServer(airdrop) end)
				pcall(function() obj:FireServer(part) end)
				pcall(function() obj:FireServer() end)
			end
		end
	end

	-- Go back to saved position
	task.wait(0.2)
	rootPart.CFrame = savedPos
	freezeRig()

	stats.airdropsOpened += 1
	stats.lastEvent = "Airdrop opened!"
	notify("AIRDROP", "Opened " .. airdrop.Name)

	-- Clean up reference after 30s so we could re-detect if a new one spawns
	task.delay(30, function() openedAirdrops[airdrop] = nil end)
end

-- Watch for new airdrops landing
Workspace.ChildAdded:Connect(function(obj)
	if not toggles.airdrop then return end
	local nameLow = obj.Name:lower()
	for _, kw in ipairs(AIRDROP_KEYWORDS) do
		if nameLow:find(kw) then
			-- Wait for it to settle then try to open
			task.delay(2, function()
				tryOpenAirdrop()
			end)
			break
		end
	end
end)

-- ── CHASER / HAZARD AVOIDANCE ────────────────────────────
local HAZARD_DETECT_RADIUS = 25
local HAZARD_FLEE_DIST     = 40
local HAZARD_CHECK_RATE    = 0.2
local lastFlee             = 0
local HAZARD_FLEE_COOLDOWN = 0.5

local CHASER_NAMES = {"chaser", "ghost", "monster", "entity", "creature", "hunter", "shadow"}
local hazardParts  = {}

local HAZARD_COLORS = {
	Color3.fromRGB(0,0,255), Color3.fromRGB(0,120,255),
	Color3.fromRGB(0,170,255), Color3.fromRGB(30,80,220), Color3.fromRGB(0,200,255),
}
local function colorDist(a,b) return math.abs(a.R-b.R)+math.abs(a.G-b.G)+math.abs(a.B-b.B) end
local function isBlue(c) for _,h in ipairs(HAZARD_COLORS) do if colorDist(c,h)<0.35 then return true end end return false end
local function ownedByPlayer(part)
	for _,p in ipairs(Players:GetPlayers()) do
		if p.Character and part:IsDescendantOf(p.Character) then return true end
	end
	return false
end

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

local function findChaser()
	local nearest, nearDist = nil, math.huge
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj ~= character then
			local nameLow = obj.Name:lower()
			local isChaser = false
			for _, keyword in ipairs(CHASER_NAMES) do
				if nameLow:find(keyword) then isChaser = true; break end
			end
			if isChaser then
				local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildOfClass("BasePart")
				if root and rootPart then
					local d = (rootPart.Position - root.Position).Magnitude
					if d < nearDist then nearDist = d; nearest = root end
				end
			end
		end
	end
	return nearest, nearDist
end

local function findNearestStaticHazard()
	local nearest, nearDist = nil, math.huge
	for part in pairs(hazardParts) do
		if not part.Parent then hazardParts[part]=nil; continue end
		local ok,d = pcall(function() return (rootPart.Position-part.Position).Magnitude end)
		if ok and d < nearDist then nearDist=d; nearest=part end
	end
	return nearest, nearDist
end

task.spawn(function()
	while true do
		task.wait(HAZARD_CHECK_RATE)
		if not rootPart or not toggles.hazard then continue end
		if tick() - lastFlee < HAZARD_FLEE_COOLDOWN then continue end

		local threatPos, threatDist = nil, math.huge

		local chaserRoot, chaserDist = findChaser()
		if chaserRoot and chaserDist < HAZARD_DETECT_RADIUS then
			threatPos = chaserRoot.Position; threatDist = chaserDist
		end

		if not threatPos then
			local bluePart, blueDist = findNearestStaticHazard()
			if bluePart and blueDist < HAZARD_DETECT_RADIUS then
				threatPos = bluePart.Position; threatDist = blueDist
			end
		end

		if threatPos then
			lastFlee = tick()
			local fd = (rootPart.Position - threatPos)
			fd = Vector3.new(fd.X,0,fd.Z).Unit
			local fp = rootPart.Position + fd * HAZARD_FLEE_DIST
			rootPart.CFrame = CFrame.new(Vector3.new(fp.X, rootPart.Position.Y, fp.Z))
			freezeRig()
			stats.hazardsAvoided += 1
			stats.lastEvent = "Chaser fled! (" .. math.floor(threatDist) .. " studs)"
		end
	end
end)

-- ── BLESS / CURSE ────────────────────────────────────────
local function getOtherPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then table.insert(list, p) end
	end
	return list
end

local function findRemote(keywords)
	local storages = {game:GetService("ReplicatedStorage"), Workspace}
	for _, storage in ipairs(storages) do
		for _, obj in ipairs(storage:GetDescendants()) do
			if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
				local n = obj.Name:lower()
				for _, kw in ipairs(keywords) do
					if n:find(kw) then return obj end
				end
			end
		end
	end
	return nil
end

local function tryCurseBless(mode)
	local others = getOtherPlayers()
	if #others == 0 then return end
	local target = others[math.random(1, #others)]
	local keywords = mode == "bless" and {"bless"} or {"curse"}
	local remote = findRemote(keywords)

	if remote then
		pcall(function() remote:FireServer(target) end)
		pcall(function() remote:FireServer(target.UserId) end)
		pcall(function() remote:FireServer(target.Name) end)
		stats.lastEvent = mode:sub(1,1):upper() .. mode:sub(2) .. "d " .. target.Name
		if mode == "bless" then stats.blessCount += 1 else stats.curseCount += 1 end
		notify(mode:upper(), "→ " .. target.Name)
	else
		local function findButton(parent, kw)
			for _, obj in ipairs(parent:GetDescendants()) do
				if (obj:IsA("TextButton") or obj:IsA("ImageButton")) then
					if obj.Name:lower():find(kw) or (obj:IsA("TextButton") and obj.Text:lower():find(kw)) then
						return obj
					end
				end
			end
			return nil
		end
		local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
		if pg then
			local btn = findButton(pg, mode)
			if btn then
				local fire = btn.MouseButton1Click or btn.Activated
				if fire then
					pcall(function() fire:Fire() end)
					stats.lastEvent = mode .. " button clicked → " .. target.Name
					if mode == "bless" then stats.blessCount += 1 else stats.curseCount += 1 end
				end
			end
		end
	end
end

local lastPlayerCount = 0
local roundStarted = false

task.spawn(function()
	while true do
		task.wait(2)
		local count = #Players:GetPlayers()
		if count > lastPlayerCount and lastPlayerCount > 0 and count >= 3 then
			roundStarted = true
		end
		lastPlayerCount = count

		if roundStarted then
			roundStarted = false
			task.wait(3)
			if toggles.bless and not toggles.curse then
				tryCurseBless("bless")
			elseif toggles.curse and not toggles.bless then
				tryCurseBless("curse")
			elseif toggles.bless and toggles.curse then
				tryCurseBless(math.random() > 0.5 and "bless" or "curse")
			end
		end
	end
end)

-- ── OBBY ─────────────────────────────────────────────────
local function runObby()
	if obbyCooldown or not toggles.obby or not toggles.farm then return end
	obbyCooldown = true
	stats.lastEvent = "Running obby..."

	local sp = rootPart.Position
	local el = OBBY_START_POS + Vector3.new(0,4,0)
	rootPart.CFrame = CFrame.lookAt(sp, Vector3.new(OBBY_START_POS.X,sp.Y,OBBY_START_POS.Z))
	task.wait(0.05)

	for i=1,12 do
		if not toggles.farm or not toggles.obby then obbyCooldown = false; return end
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
		syncToggles()

		local hp, maxHp = getHealth()
		local hpPct = maxHp > 0 and math.floor((hp/maxHp)*100) or 0

		Iris.Window({"Autofarm"})

			Iris.Tree({"[ Status ]"})
				Iris.Text({"Session:         " .. formatTime(tick() - sessionStart)})
				Iris.Text({"Players in game: " .. getAlivePlayers()})
				Iris.Text({"Health:          " .. math.floor(hp) .. "/" .. math.floor(maxHp) .. " (" .. hpPct .. "%)"})
				Iris.Text({"Has bomb:        " .. (hasBomb() and "YES!" or "no")})
				Iris.Text({"On plate:        " .. (isOnPlate() and "YES" or "no")})
				Iris.Text({"Heal item:       " .. (findHealTool() and findHealTool().Name or "none")})
				Iris.Text({"Last event:      " .. stats.lastEvent})
			Iris.End()

			Iris.Tree({"[ Modules ]"})
				Iris.Checkbox({"Autofarm active"}, {isChecked = irisStates.farm})
				Iris.Checkbox({"Anti-staff"},       {isChecked = irisStates.anti})
				Iris.Checkbox({"Hazard/Chaser"},    {isChecked = irisStates.hazard})
				Iris.Checkbox({"Obby farm"},        {isChecked = irisStates.obby})
				Iris.Checkbox({"Auto Heal (<50%)"}, {isChecked = irisStates.heal})
				Iris.Checkbox({"Auto Airdrop"},     {isChecked = irisStates.airdrop})
			Iris.End()

			Iris.Tree({"[ Bless / Curse ]"})
				Iris.Text({"(auto-fires each round)"})
				Iris.Checkbox({"Auto Bless (green)"}, {isChecked = irisStates.bless})
				Iris.Checkbox({"Auto Curse (red)"},   {isChecked = irisStates.curse})
				Iris.Text({"Blessed: " .. stats.blessCount .. "  Cursed: " .. stats.curseCount})
				if Iris.Button({"Bless Now"}).clicked() then task.spawn(function() tryCurseBless("bless") end) end
				if Iris.Button({"Curse Now"}).clicked() then task.spawn(function() tryCurseBless("curse") end) end
			Iris.End()

			Iris.Tree({"[ Stats ]"})
				Iris.Text({"Bombs passed:    " .. stats.bombsPassed})
				Iris.Text({"Obbys done:      " .. stats.obbysRun})
				Iris.Text({"Hazards dodged:  " .. stats.hazardsAvoided})
				Iris.Text({"Heals used:      " .. stats.healsUsed})
				Iris.Text({"Airdrops opened: " .. stats.airdropsOpened})
				Iris.Text({"Staff detected:  " .. stats.staffDetected})
			Iris.End()

			Iris.Tree({"[ Actions ]"})
				if Iris.Button({"Teleport to Spawn"}).clicked() then
					teleportToSpawn(); stats.lastEvent = "Manual spawn tp"
				end
				if Iris.Button({"Open Airdrop Now"}).clicked() then
					task.spawn(tryOpenAirdrop); stats.lastEvent = "Manual airdrop attempt"
				end
				if Iris.Button({"Heal Now"}).clicked() then
					task.spawn(function()
						local old = toggles.heal
						toggles.heal = true
						lastHealTime = 0
						tryHeal()
						toggles.heal = old
					end)
				end
				if Iris.Button({"Server Hop Now"}).clicked() then
					stats.lastEvent = "Manual server hop..."
					task.spawn(function()
						task.wait(0.5)
						local ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer) end)
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

		if not toggles.farm then
			stats.lastEvent = "Paused"
			plateStuckTimer = 0
			continue
		end

		character = localPlayer.Character
		if not character then continue end
		rootPart = character:FindFirstChild("HumanoidRootPart")
		humanoid = character:FindFirstChildOfClass("Humanoid")
		if not rootPart or not humanoid then continue end

		-- Bomb takes highest priority
		if hasBomb() then
			plateStuckTimer = 0
			passBomb()
			continue
		end

		-- Plate stuck detection & escape
		if isOnPlate() and getAlivePlayers() > 1 then
			plateStuckTimer += 0.3
			stats.lastEvent = "On plate! Escaping... (" .. math.floor(plateStuckTimer) .. "s)"
			teleportToSpawn()
			if plateStuckTimer >= PLATE_STUCK_LIMIT then
				local bv = Instance.new("BodyVelocity")
				bv.Velocity = Vector3.new(0, 80, 0)
				bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
				bv.Parent = rootPart
				task.wait(0.1); bv:Destroy()
				task.wait(0.05)
				teleportToSpawn()
				plateStuckTimer = 0
				stats.lastEvent = "Force-escaped plate!"
			end
			continue
		else
			plateStuckTimer = 0
		end

		-- Check for airdrop on our plate
		tryOpenAirdrop()

		-- Obby
		if toggles.obby then runObby() end
	end
end)
