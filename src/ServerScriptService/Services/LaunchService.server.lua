local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local launchRemote = Remotes:FindFirstChild("LaunchRemote")
if not launchRemote then
	launchRemote = Instance.new("RemoteEvent")
	launchRemote.Name = "LaunchRemote"
	launchRemote.Parent = Remotes
end

local isPlayerFlying = {}
local lastLaunchTime = {}
local launchStartPositions = {}

local function getTargetToLaunch(player: Player): (Model?, BasePart?)
	local char = player.Character
	if not char then return nil, nil end
	
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, obj in Workspace:GetChildren() do
			if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj ~= char then
				local npcHrp = obj:FindFirstChild("HumanoidRootPart")
				if npcHrp and (npcHrp.Position - hrp.Position).Magnitude < 12 then
					return obj, npcHrp
				end
			end
		end
	end
	
	return char, hrp
end

local function spawnDistanceBillBoard(position: Vector3, distanceStuds: number, coinsEarned: number)
	local part = Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position + Vector3.new(0, 3, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 80)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 215, 0)
	label.TextStrokeTransparency = 0
	label.Text = string.format("%d Studs!\n(+%d 🪙)", distanceStuds, coinsEarned)
	label.Parent = bb

	task.spawn(function()
		for i = 1, 30 do
			task.wait(0.05)
			part.Position = part.Position + Vector3.new(0, 0.1, 0)
			label.TextTransparency = i / 30
			label.TextStrokeTransparency = i / 30
		end
		part:Destroy()
	end)
end

launchRemote.OnServerEvent:Connect(function(player: Player, multiplier: any)
	local now = os.clock()

	-- === ОБРАБОТКА ПРИЗЕМЛЕНИЯ ===
	if multiplier == "Landed" then
		if not isPlayerFlying[player.UserId] then return end
		
		-- Защита: нельзя приземлиться раньше чем через 0.8 секунды после старта
		if lastLaunchTime[player.UserId] and (now - lastLaunchTime[player.UserId]) < 0.8 then
			return
		end

		local startPos = launchStartPositions[player.UserId]
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		
		if startPos and hrp then
			local flatStart = Vector3.new(startPos.X, 0, startPos.Z)
			local flatEnd = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
			local distance = math.floor((flatEnd - flatStart).Magnitude)

			if distance > 2 then
				local coinsEarned = math.floor(distance * 1.5)
				
				local leaderstats = player:FindFirstChild("leaderstats")
				if leaderstats then
					local coins = leaderstats:FindFirstChild("Coins")
					local best = leaderstats:FindFirstChild("Best")
					
					if coins then coins.Value += coinsEarned end
					if best and distance > best.Value then
						best.Value = distance
					end
				end
				
				spawnDistanceBillBoard(hrp.Position, distance, coinsEarned)
			end
		end
		
		isPlayerFlying[player.UserId] = nil
		launchStartPositions[player.UserId] = nil
		return
	end
	
	-- === БЛОКИРОВКА СЕРВЕРА (МИН. 1.5 СЕК ИЛИ ПОКА В ПОЛЁТЕ) ===
	if isPlayerFlying[player.UserId] then return end
	if lastLaunchTime[player.UserId] and (now - lastLaunchTime[player.UserId]) < 1.5 then return end

	local targetModel, targetHrp = getTargetToLaunch(player)
	if not targetModel or not targetHrp then return end
	
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	
	-- Фиксируем старт и время
	isPlayerFlying[player.UserId] = true
	lastLaunchTime[player.UserId] = now
	launchStartPositions[player.UserId] = targetHrp.Position

	local multNumber = if typeof(multiplier) == "number" then multiplier else 1
	multNumber = math.clamp(multNumber, 0.1, 5.0)

	-- 1. Снимаем якорь
	for _, part in targetModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CustomPhysicalProperties = nil
		end
	end

	-- 2. Переводим в Freefall
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	-- 3. Рассчитываем импульс
	local charHrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local lookDir = charHrp and charHrp.CFrame.LookVector or targetHrp.CFrame.LookVector
	local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
	local flatLookDir = if flatLook.Magnitude > 0.001 then flatLook.Unit else Vector3.new(0, 0, -1)
	
	local launchDirection = (flatLookDir + Vector3.new(0, 1, 0)).Unit
	local baseSpeed = 220
	local launchVelocity = launchDirection * (baseSpeed * multNumber)
	
	-- 4. Запуск
	targetHrp.CFrame = targetHrp.CFrame + Vector3.new(0, 1.5, 0)
	targetHrp.AssemblyLinearVelocity = launchVelocity
	targetHrp.AssemblyAngularVelocity = Vector3.zero
	targetHrp:ApplyImpulse(launchVelocity * targetHrp.AssemblyMass)
	
	if targetHrp:CanSetNetworkOwnership() then
		pcall(function()
			targetHrp:SetNetworkOwner(player)
		end)
	end
	
	launchRemote:FireClient(player, targetHrp, launchVelocity)
	
	-- Страховочный таймаут
	task.delay(12, function()
		if isPlayerFlying[player.UserId] then
			isPlayerFlying[player.UserId] = nil
			launchStartPositions[player.UserId] = nil
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	isPlayerFlying[player.UserId] = nil
	lastLaunchTime[player.UserId] = nil
	launchStartPositions[player.UserId] = nil
end)