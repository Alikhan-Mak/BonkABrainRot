local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local launchRemote = Remotes and Remotes:WaitForChild("LaunchRemote", 10)

-- === UI ТАЙМИНГА ===
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BrainrotTimingGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local meterFrame = Instance.new("Frame")
meterFrame.Name = "MeterFrame"
meterFrame.Size = UDim2.new(0, 360, 0, 36)
meterFrame.Position = UDim2.new(0.5, -180, 0.8, 0)
meterFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
meterFrame.Visible = false
meterFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = meterFrame

local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Parent = meterFrame

local function createZone(size, pos, color)
	local z = Instance.new("Frame")
	z.Size = size
	z.Position = pos
	z.BackgroundColor3 = color
	z.BorderSizePixel = 0
	z.Parent = meterFrame
	local zC = Instance.new("UICorner")
	zC.CornerRadius = UDim.new(0, 4)
	zC.Parent = z
end

createZone(UDim2.new(0.4, 0, 0.8, 0), UDim2.new(0, 4, 0.1, 0), Color3.fromRGB(220, 50, 50))
createZone(UDim2.new(0.3, 0, 0.8, 0), UDim2.new(0.4, 2, 0.1, 0), Color3.fromRGB(240, 160, 40))
createZone(UDim2.new(0.2, 0, 0.8, 0), UDim2.new(0.7, 2, 0.1, 0), Color3.fromRGB(50, 200, 80))
createZone(UDim2.new(0.1, -6, 0.8, 0), UDim2.new(0.9, 2, 0.1, 0), Color3.fromRGB(180, 50, 255))

local pointer = Instance.new("Frame")
pointer.Name = "Pointer"
pointer.Size = UDim2.new(0, 6, 1.2, 0)
pointer.Position = UDim2.new(0, 0, -0.1, 0)
pointer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
pointer.Parent = meterFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 40)
statusLabel.Position = UDim2.new(0, 0, -1.2, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.FredokaOne
statusLabel.TextSize = 28
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Text = "КЛИКНИ ДЛЯ УДАРА!"
statusLabel.Parent = meterFrame

-- === СОСТОЯНИЕ ===
local meterValue = 0
local speed = 2.5
local direction = 1
local isRunning = false
local isCooldown = false
local isToolEquipped = false

RunService.RenderStepped:Connect(function(dt)
	if not isRunning or not isToolEquipped or isCooldown then return end
	
	meterValue = meterValue + (dt * speed * direction)
	if meterValue >= 1 then meterValue = 1; direction = -1 end
	if meterValue <= 0 then meterValue = 0; direction = 1 end
	pointer.Position = UDim2.new(meterValue * 0.98, 0, -0.1, 0)
end)

local function calculateMultiplier(val)
	if val >= 0.90 then
		return 3.5, "PERFECT BONK!", Color3.fromRGB(180, 50, 255)
	elseif val >= 0.70 then
		return 2.0, "GREAT!", Color3.fromRGB(50, 200, 80)
	elseif val >= 0.40 then
		return 1.2, "GOOD", Color3.fromRGB(240, 160, 40)
	else
		return 0.3, "MISS...", Color3.fromRGB(220, 50, 50)
	end
end

local function checkEquippedTool()
	local character = player.Character
	if not character then 
		isToolEquipped = false
		meterFrame.Visible = false
		isRunning = false
		return 
	end
	
	local currentTool = character:FindFirstChildOfClass("Tool")
	if currentTool then
		if not isToolEquipped then
			isToolEquipped = true
			meterFrame.Visible = true
			if not isCooldown then
				isRunning = true
				meterValue = 0
				direction = 1
				statusLabel.Text = "КЛИКНИ ДЛЯ УДАРА!"
				statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	else
		isToolEquipped = false
		meterFrame.Visible = false
		isRunning = false
	end
end

RunService.Heartbeat:Connect(checkEquippedTool)

local function onCharacterAdded(char)
	isCooldown = false
	isRunning = false
	meterValue = 0
end

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

-- === ОБРАБОТКА КЛИКА ===
UserInputService.InputBegan:Connect(function(input, gpe)
	-- ЗАПОР КЛИКОВ В ПОЛЁТЕ
	if gpe or isCooldown or not isToolEquipped or not isRunning then return end
	
	if input.UserInputType == Enum.UserInputType.MouseButton1 
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.Space then
		
		-- Блокируем повторный ввод
		isCooldown = true
		isRunning = false
		
		local mult, text, color = calculateMultiplier(meterValue)
		statusLabel.Text = text
		statusLabel.TextColor3 = color
		
		if launchRemote then
			launchRemote:FireServer(mult)
		end
		
		task.delay(0.2, function()
			if isCooldown and isToolEquipped then
				statusLabel.Text = "В ПОЛЁТЕ..."
				statusLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
			end
		end)
	end
end)

-- === ОБРАБОТКА ПОЛЁТА И ПРИЗЕМЛЕНИЯ ===
if launchRemote then
	launchRemote.OnClientEvent:Connect(function(targetHrp: BasePart, launchVelocity: Vector3)
		if not targetHrp or not targetHrp:IsA("BasePart") then return end
		
		local targetModel = targetHrp.Parent
		if not targetModel then return end
		local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
		
		if humanoid then
			humanoid.Sit = false
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		
		targetHrp.CFrame = targetHrp.CFrame + Vector3.new(0, 1.5, 0)
		targetHrp.AssemblyLinearVelocity = launchVelocity
		
		local startTime = os.clock()
		local finished = false
		local flightConn
		
		local function finishFlight()
			if finished then return end
			finished = true
			
			if flightConn then flightConn:Disconnect(); flightConn = nil end
			
			if humanoid and humanoid.Parent and humanoid.Health > 0 then
				humanoid.Sit = false
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				task.defer(function()
					if humanoid and humanoid.Parent then
						humanoid:ChangeState(Enum.HumanoidStateType.Running)
					end
				end)
			end
			
			-- Сигнал о приземлении
			if launchRemote then
				launchRemote:FireServer("Landed")
			end
			
			-- Разблокировка только через 0.5с ПОСЛЕ ПРИЗЕМЛЕНИЯ
			task.delay(0.5, function()
				isCooldown = false
				if isToolEquipped then
					meterValue = 0
					direction = 1
					isRunning = true
					statusLabel.Text = "КЛИКНИ ДЛЯ УДАРА!"
					statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end)
		end
		
		-- Отслеживание земли
		flightConn = RunService.Heartbeat:Connect(function()
			if not targetHrp or not targetHrp.Parent then
				finishFlight()
				return
			end
			
			local timeInAir = os.clock() - startTime
			
			-- ВНИМАНИЕ: Проверка земли начинается ТОЛЬКО СПУСТЯ 1.2 СЕКУНДЫ В ПОЛЕТЕ!
			if timeInAir > 1.2 then
				local raycast = Workspace:Raycast(targetHrp.Position, Vector3.new(0, -4.5, 0))
				local onFloor = humanoid and humanoid.FloorMaterial ~= Enum.Material.Air
				local speedMagnitude = targetHrp.AssemblyLinearVelocity.Magnitude
				
				if raycast or onFloor or (timeInAir > 1.5 and speedMagnitude < 2) then
					finishFlight()
					return
				end
			end
			
			if timeInAir > 12 then
				finishFlight()
				return
			end
		end)
	end)
end