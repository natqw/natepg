_G.FARM_ACTIVE = true

local Players      = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local StarterGui   = game:GetService("StarterGui")
local Workspace    = game:GetService("Workspace")

local localPlayer  = Players.LocalPlayer
local character    = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local rootPart     = character:WaitForChild("HumanoidRootPart")
local humanoid     = character:WaitForChild("Humanoid")

local GROUP_ID        = 1063978185
local CHECK_INTERVAL  = 3
local OBBY_START_POS  = Vector3.new(122.9, 14.0, 168.8)
local OBBY_END_POS    = Vector3.new(175.4, 14.3, 246.0)
local obbyCooldown    = false
local OBBY_COOLDOWN   = 150
local PLAYING_MIN_Y   = 5
local PLAYING_MAX_Y   = 200
local SPAWN_POS       = Vector3.new(7.0, 21.3, 110.1)
local SETTINGS_FILE   = "autofarm_settings.json"

-- ── IRIS LOAD ────────────────────────────────────────────
local Iris = nil
pcall(function()
	local src = game:HttpGet("https://raw.githubusercontent.com/x0581/Iris-Exploit-Bundle/main/bundle.lua", true)
	Iris = loadstring(src)().Init(game.CoreGui)
end)

-- ── SETTINGS SAVE / LOAD ─────────────────────────────────
local function saveSettings(t)
	pcall(function()
		writefile(SETTINGS_FILE, game:GetService("HttpService"):JSONEncode(t))
	end)
end

local function loadSettings()
	local ok, data = pcall(function()
		return game:GetService("HttpService"):JSONDecode(readfile(SETTINGS_FILE))
	end)
	return ok and data or {}
end

local saved = loadSettings()

-- ── TOGGLE STATES ────────────────────────────────────────
local toggles = {
	farm    = saved.farm    ~= nil and saved.farm    or true,
	anti    = saved.anti    ~= nil and saved.anti    or true,
	hazard  = saved.hazard  ~= nil and saved.hazard  or true,
	obby    = saved.obby    ~= nil and saved.obby    or true,
	bless   = saved.bless   ~= nil and saved.bless   or false,
	curse   = saved.curse   ~= nil and saved.curse   or false,
	heal    = saved.heal    ~= nil and saved.heal    or true,
	airdrop = saved.airdrop ~= nil and saved.airdrop or true,
}

local irisStates = {}
if Iris then
	irisStates.farm    = Iris.State(toggles.farm)
	irisStates.anti    = Iris.State(toggles.anti)
	irisStates.hazard  = Iris.State(toggles.hazard)
	irisStates.obby    = Iris.State(toggles.obby)
	irisStates.bless   = Iris.State(toggles.bless)
	irisStates.curse   = Iris.State(toggles.curse)
	irisStates.heal    = Iris.State(toggles.heal)
	irisStates.airdrop = Iris.State(toggles.airdrop)
end

local lastSaveTime = 0
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
	-- Save settings every 5s at most
	if tick() - lastSaveTime > 5 then
		lastSaveTime = tick()
		saveSettings(toggles)
	end
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

notify("AUTOFARM", "Active" .. (Iris and " + UI" or " (no UI)") .. " | Settings loaded")

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

-- ── PLATE ZONE SYSTEM ────────────────────────────────────
-- When we successfully land on our plate we record its centre + bounds.
-- From that point on, if we're EVER inside those bounds (±5 studs XZ, ±10 Y)
-- we teleport to spawn immediately — even if the plate itself has disappeared.

local plateZone = nil   -- { center = Vector3, minX, maxX, minZ, maxZ, minY, maxY }
local ZONE_PAD_XZ = 5
local ZONE_PAD_Y  = 10

local function recordPlateZone(platePart)
	if not platePart then return end
	local s = platePart.Size
	local c = platePart.Position
	plateZone = {
		center = c,
		minX = c.X - s.X/2 - ZONE_PAD_XZ,
		maxX = c.X + s.X/2 + ZONE_PAD_XZ,
		minZ = c.Z - s.Z/2 - ZONE_PAD_XZ,
		maxZ = c.Z + s.Z/2 + ZONE_PAD_XZ,
		minY = c.Y - ZONE_PAD_Y,
		maxY = c.Y + ZONE_PAD_Y,
	}
end

local function isInPlateZone()
	if not plateZone or not rootPart then return false end
	local p = rootPart.Position
	return p.X >= plateZone.minX and p.X <= plateZone.maxX
	   and p.Z >= plateZone.minZ and p.Z <= plateZone.maxZ
	   and p.Y >= plateZone.minY and p.Y <= plateZone.maxY
end

-- Raycast plate detection (used to FIND the plate and record its zone)
local function rayForPlate(origin, dir, filterChar)
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = {filterChar}
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(origin, dir, rp)
	if hit and hit.Instance and hit.Instance.Name:lower():find("plate") then
		return hit.Instance
	end
	return nil
end

local function getMyPlatePart()
	if not character or not rootPart then return nil end
	local pos = rootPart.Position
	local rp  = RaycastParams.new()
	rp.FilterDescendantsInstances = {character}
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local offsets = {
		Vector3.new(0,0,0),
		Vector3.new(1,0,0), Vector3.new(-1,0,0),
		Vector3.new(0,0,1), Vector3.new(0,0,-1),
	}
	for _, off in ipairs(offsets) do
		local hit = Workspace:Raycast(pos + off, Vector3.new(0,-8,0), rp)
		if hit and hit.Instance and hit.Instance.Name:lower():find("plate") then
			return hit.Instance
		end
	end
	return nil
end

local function isOnPlate()
	return getMyPlatePart() ~= nil
end

local function playerOnPlate(player)
	if not player.Character then return false end
	local pRoot = player.Character:FindFirstChild("HumanoidRootPart")
	if not pRoot then return false end
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = {player.Character}
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(pRoot.Position, Vector3.new(0,-8,0), rp)
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
	local fallback,    fallDist  = nil, math.huge

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
local HEAL_THRESHOLD = 0.50
local HEAL_KEYWORDS  = {"medkit","med kit","heal","health","jar","potion","bandage","kit"}
local lastHealTime   = 0
local HEAL_COOLDOWN  = 3

local function findHealTool()
	local function check(item)
		if not item then return nil end
		local n = item.Name:lower()
		for _, kw in ipairs(HEAL_KEYWORDS) do if n:find(kw) then return item end end
	end
	local bp = localPlayer:FindFirstChildOfClass("Backpack")
	if bp then for _, i in ipairs(bp:GetChildren()) do local r = check(i); if r then return r end end end
	for _, i in ipairs(character:GetChildren()) do if i:IsA("Tool") then local r = check(i); if r then return r end end end
	return nil
end

local function tryHeal(force)
	if not toggles.heal and not force then return end
	if tick() - lastHealTime < HEAL_COOLDOWN then return end
	local hp, maxHp = getHealth()
	if hp <= 0 or maxHp <= 0 then return end
	if not force and (hp / maxHp) >= HEAL_THRESHOLD then return end
	local tool = findHealTool()
	if not tool then return end
	lastHealTime = tick()
	stats.lastEvent = string.format("Using heal (HP: %d/%d)", math.floor(hp), math.floor(maxHp))
	humanoid:EquipTool(tool)
	task.wait(0.15)
	local equipped = character:FindFirstChildOfClass("Tool")
	if equipped then
		local fired = false
		for _, ev in ipairs(equipped:GetDescendants()) do
			if ev:IsA("RemoteEvent") then pcall(function() ev:FireServer() end); fired = true; break end
		end
		if not fired then pcall(function() equipped:Activate() end) end
	end
	task.wait(0.3)
	humanoid:UnequipTools()
	stats.healsUsed += 1
	stats.lastEvent = "Heal used!"
end

task.spawn(function()
	while true do
		task.wait(0.5)
		if character and rootPart then tryHeal(false) end
	end
end)

-- ── AIRDROP ──────────────────────────────────────────────
local AIRDROP_KEYWORDS = {"airdrop","crate","supply","drop","box","chest","loot"}
local AIRDROP_RADIUS   = 12
local lastAirdropTime  = 0
local AIRDROP_COOLDOWN = 5
local openedAirdrops   = {}

local function findAirdropOnPlate()
	local plate = getMyPlatePart()
	if not plate then return nil, nil end
	local platePos = plate.Position
	for _, obj in ipairs(Workspace:GetChildren()) do
		local checkPart = nil
		if obj:IsA("Model") then checkPart = obj:FindFirstChildOfClass("BasePart") or obj.PrimaryPart
		elseif obj:IsA("BasePart") then checkPart = obj end
		if not checkPart then continue end
		if openedAirdrops[obj] then continue end
		local nameLow = obj.Name:lower()
		local isAirdrop = false
		for _, kw in ipairs(AIRDROP_KEYWORDS) do if nameLow:find(kw) then isAirdrop = true; break end end
		if not isAirdrop then continue end
		if (checkPart.Position - platePos).Magnitude <= AIRDROP_RADIUS then return obj, checkPart end
	end
	return nil, nil
end

local function tryOpenAirdrop()
	if not toggles.airdrop then return end
	if tick() - lastAirdropTime < AIRDROP_COOLDOWN then return end
	if not isOnPlate() then return end
	local airdrop, part = findAirdropOnPlate()
	if not airdrop or not part then return end
	lastAirdropTime = tick()
	openedAirdrops[airdrop] = true
	stats.lastEvent = "Airdrop found: " .. airdrop.Name
	local savedPos = rootPart.CFrame
	rootPart.CFrame = CFrame.new(part.Position + Vector3.new(0,3,0))
	task.wait(0.1)
	for _, obj in ipairs(airdrop:GetDescendants()) do
		if obj:IsA("ProximityPrompt") then
			pcall(function() fireproximityprompt(obj) end)
			pcall(function() obj.Triggered:Fire(localPlayer) end)
		end
	end
	for _, obj in ipairs(airdrop:GetDescendants()) do
		if obj:IsA("RemoteEvent") then
			local n = obj.Name:lower()
			if n:find("open") or n:find("collect") or n:find("claim") or n:find("use") then
				pcall(function() obj:FireServer() end)
				pcall(function() obj:FireServer(localPlayer) end)
			end
		end
	end
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
	task.wait(0.2)
	rootPart.CFrame = savedPos
	freezeRig()
	stats.airdropsOpened += 1
	stats.lastEvent = "Airdrop opened!"
	notify("AIRDROP", "Opened " .. airdrop.Name)
	task.delay(30, function() openedAirdrops[airdrop] = nil end)
end

Workspace.ChildAdded:Connect(function(obj)
	if not toggles.airdrop then return end
	local n = obj.Name:lower()
	for _, kw in ipairs(AIRDROP_KEYWORDS) do
		if n:find(kw) then task.delay(2, tryOpenAirdrop); break end
	end
end)

-- ── CHASER / HAZARD ──────────────────────────────────────
local HAZARD_DETECT_RADIUS = 25
local HAZARD_FLEE_DIST     = 40
local HAZARD_CHECK_RATE    = 0.2
local lastFlee             = 0
local HAZARD_FLEE_COOLDOWN = 0.5
local CHASER_NAMES = {"chaser","ghost","monster","entity","creature","hunter","shadow"}
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
			local nl = obj.Name:lower()
			local ok = false
			for _, kw in ipairs(CHASER_NAMES) do if nl:find(kw) then ok=true; break end end
			if ok then
				local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildOfClass("BasePart")
				if root and rootPart then
					local d = (rootPart.Position - root.Position).Magnitude
					if d < nearDist then nearDist=d; nearest=root end
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
		local cr, cd = findChaser()
		if cr and cd < HAZARD_DETECT_RADIUS then threatPos=cr.Position; threatDist=cd end
		if not threatPos then
			local bp, bd = findNearestStaticHazard()
			if bp and bd < HAZARD_DETECT_RADIUS then threatPos=bp.Position; threatDist=bd end
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
-- Correct flow (from screenshots):
--   1. A horizontal bar appears with red (curse) left side and green (bless) right side
--   2. Clicking a side opens a player list with "Bless" buttons next to each name
--   3. Click a "Bless" button to bless that player
-- We simulate this by: clicking the correct side of the bar, waiting for the list,
-- then clicking a random "Bless" button from the list.

local lastBlessCurseTime = 0
local BLESS_CURSE_LOCKOUT = 15   -- wait 15s after round bar appears

local function clickBtn(btn)
	pcall(function() btn.MouseButton1Down:Fire() end)
	pcall(function() btn.MouseButton1Up:Fire() end)
	pcall(function() btn.MouseButton1Click:Fire() end)
	pcall(function() btn.Activated:Fire() end)
end

local function findVisibleButtons(parent, textMatch)
	local found = {}
	for _, obj in ipairs(parent:GetDescendants()) do
		if obj:IsA("TextButton") or obj:IsA("ImageButton") then
			if not obj.Visible then continue end
			local t = obj:IsA("TextButton") and obj.Text:lower() or ""
			local n = obj.Name:lower()
			if t:find(textMatch) or n:find(textMatch) then
				table.insert(found, obj)
			end
		end
	end
	return found
end

local function tryCurseBless(mode)
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end

	-- Step 1: find and click the correct side of the bar
	-- Green = bless keywords, Red = curse keywords
	local sideKeywords = mode == "bless"
		and {"green", "bless", "blessing", "right"}
		or  {"red", "curse", "cursing", "left"}

	local clickedSide = false
	for _, kw in ipairs(sideKeywords) do
		local btns = findVisibleButtons(pg, kw)
		if #btns > 0 then
			clickBtn(btns[1])
			clickedSide = true
			break
		end
	end

	-- Wait for player list to appear after clicking
	task.wait(0.5)

	-- Step 2: find all visible "Bless" buttons (the per-player ones)
	-- and click a random one
	local blessButtons = findVisibleButtons(pg, "bless")

	if #blessButtons == 0 then
		stats.lastEvent = "No Bless buttons visible yet"
		return false
	end

	-- Click a random player's button
	local chosen = blessButtons[math.random(1, #blessButtons)]
	clickBtn(chosen)

	if mode == "bless" then
		stats.blessCount += 1
		stats.lastEvent = "Blessed a player!"
		notify("BLESS", "Blessed a random player")
	else
		stats.curseCount += 1
		stats.lastEvent = "Cursed a player!"
		notify("CURSE", "Cursed a random player")
	end
	return true
end

-- Watch for the bless/curse bar to appear in PlayerGui (signals round start)
local roundBarSeen    = false
local roundBarSeenAt  = 0

local function checkForRoundBar()
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	for _, obj in ipairs(pg:GetDescendants()) do
		if not obj.Visible then continue end
		local n = obj.Name:lower()
		if n:find("bless") or n:find("curse") or n:find("bar") then
			return true
		end
		if obj:IsA("TextLabel") then
			local t = obj.Text:lower()
			if t:find("bless") or t:find("curse") or t:find("place a") then
				return true
			end
		end
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(1)
		if not toggles.bless and not toggles.curse then
			roundBarSeen = false
			continue
		end

		local barVisible = checkForRoundBar()

		if barVisible and not roundBarSeen then
			-- Bar just appeared — round started
			roundBarSeen   = true
			roundBarSeenAt = tick()
		elseif not barVisible then
			roundBarSeen = false
		end

		if roundBarSeen then
			local elapsed = tick() - roundBarSeenAt
			if elapsed < BLESS_CURSE_LOCKOUT then
				stats.lastEvent = string.format("Bless/curse in %.0fs", BLESS_CURSE_LOCKOUT - elapsed)
				continue
			end
			-- Only fire once per bar appearance (20s debounce)
			if tick() - lastBlessCurseTime < 20 then continue end
			lastBlessCurseTime = tick()
			roundBarSeen = false  -- reset so we don't fire again this round

			local mode
			if toggles.bless and not toggles.curse then mode = "bless"
			elseif toggles.curse and not toggles.bless then mode = "curse"
			elseif toggles.bless and toggles.curse then
				mode = math.random() > 0.5 and "bless" or "curse"
			end
			if mode then task.spawn(function() tryCurseBless(mode) end) end
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
		if not toggles.farm or not toggles.obby then obbyCooldown=false; return end
		rootPart.CFrame = CFrame.new(sp:Lerp(el, i/12))
		task.wait(0.05)
	end
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.new(0,50,0); bv.MaxForce = Vector3.new(0,math.huge,0); bv.Parent = rootPart
	task.wait(0.15); bv:Destroy()
	rootPart.CFrame = CFrame.new(el); freezeRig()
	task.wait(2)
	if not toggles.farm or not toggles.obby then obbyCooldown=false; return end
	rootPart.CFrame = CFrame.new(OBBY_END_POS + Vector3.new(0,4,0)); freezeRig()
	task.wait(3)
	if not toggles.farm or not toggles.obby then obbyCooldown=false; return end
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
		local onPlate = isOnPlate()
		local inZone  = isInPlateZone()

		Iris.Window({"Autofarm"})

			Iris.Tree({"[ Status ]"})
				Iris.Text({"Session:         " .. formatTime(tick() - sessionStart)})
				Iris.Text({"Players in game: " .. getAlivePlayers()})
				Iris.Text({"Health:          " .. math.floor(hp) .. "/" .. math.floor(maxHp) .. " (" .. hpPct .. "%)"})
				Iris.Text({"Has bomb:        " .. (hasBomb() and "YES!" or "no")})
				Iris.Text({"On plate:        " .. (onPlate and "YES" or (inZone and "ZONE" or "no"))})
				Iris.Text({"Plate zone:      " .. (plateZone and string.format("(%.0f,%.0f,%.0f)", plateZone.center.X, plateZone.center.Y, plateZone.center.Z) or "not recorded")})
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
				Iris.Text({"Fires 15s after round bar appears"})
				Iris.Checkbox({"Auto Bless (green)"}, {isChecked = irisStates.bless})
				Iris.Checkbox({"Auto Curse (red)"},   {isChecked = irisStates.curse})
				Iris.Text({"Blessed: " .. stats.blessCount .. "  Cursed: " .. stats.curseCount})
				if Iris.Button({"Bless Now"}).clicked() then
					task.spawn(function() tryCurseBless("bless") end)
				end
				if Iris.Button({"Curse Now"}).clicked() then
					task.spawn(function() tryCurseBless("curse") end)
				end
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
				if Iris.Button({"Clear Plate Zone"}).clicked() then
					plateZone = nil; stats.lastEvent = "Plate zone cleared"
				end
				if Iris.Button({"Open Airdrop Now"}).clicked() then
					task.spawn(tryOpenAirdrop)
				end
				if Iris.Button({"Heal Now"}).clicked() then
					task.spawn(function() tryHeal(true) end)
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
local plateStuckTimer = 0
local PLATE_STUCK_LIMIT = 3.0

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

		local onPlate = isOnPlate()

		-- If currently on plate: record zone, then escape
		if onPlate then
			-- Record zone while we can still detect the plate
			local plate = getMyPlatePart()
			if plate then recordPlateZone(plate) end

			if getAlivePlayers() > 1 then
				plateStuckTimer += 0.3
				stats.lastEvent = "On plate! Escaping... (" .. math.floor(plateStuckTimer) .. "s)"
				teleportToSpawn()
				if plateStuckTimer >= PLATE_STUCK_LIMIT then
					-- Force escape with velocity burst
					local bv = Instance.new("BodyVelocity")
					bv.Velocity = Vector3.new(0, 80, 0)
					bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
					bv.Parent = rootPart
					task.wait(0.1); bv:Destroy(); task.wait(0.05)
					teleportToSpawn()
					plateStuckTimer = 0
					stats.lastEvent = "Force-escaped plate!"
				end
			end
			continue

		-- If plate disappeared but we're in the recorded zone: escape
		elseif isInPlateZone() and getAlivePlayers() > 1 then
			plateStuckTimer += 0.3
			stats.lastEvent = "In plate zone (plate gone)! Escaping..."
			teleportToSpawn()
			if plateStuckTimer >= PLATE_STUCK_LIMIT then
				local bv = Instance.new("BodyVelocity")
				bv.Velocity = Vector3.new(0, 80, 0)
				bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
				bv.Parent = rootPart
				task.wait(0.1); bv:Destroy(); task.wait(0.05)
				teleportToSpawn()
				plateStuckTimer = 0
				plateZone = nil  -- clear zone after force escape
				stats.lastEvent = "Force-escaped plate zone!"
			end
			continue

		else
			plateStuckTimer = 0
		end

		-- Airdrop check
		tryOpenAirdrop()

		-- Obby
		if toggles.obby then runObby() end
	end
end)
