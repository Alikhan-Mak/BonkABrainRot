local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local timingRemote = Remotes:WaitForChild("StartTimingMeter")
local hitRemote = Remotes:WaitForChild("ExecuteHit")
local BAT_SWING_ANIMATION_ID = "rbxassetid://522635514"
local swingAnimation = Instance.new("Animation")
swingAnimation.AnimationId = BAT_SWING_ANIMATION_ID
local swingTracks = setmetatable({}, { __mode = "k" })

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
local timeRemaining = 0

-- Функция вызова шкалы при подбрасывании BrainRot
local function startTimingMeter(isActive: boolean, result: any)
	if not isActive then
		isRunning = false
		isCooldown = false
		player:SetAttribute("BonkTimingActive", false)
		meterFrame.Visible = false
		if result == "timeout" then
			statusLabel.Text = "ВРЕМЯ ВЫШЛО"
		end
		return
	end

	if isCooldown then
		return
	end

	player:SetAttribute("BonkTimingActive", true)
	meterValue = 0
	direction = 1
	isRunning = true
	timeRemaining = if typeof(result) == "number" then result else 10
	meterFrame.Visible = true
	statusLabel.Text = "КЛИКНИ ДЛЯ УДАРА!"
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
end

timingRemote.OnClientEvent:Connect(startTimingMeter)

RunService.RenderStepped:Connect(function(dt)
	if not isRunning or isCooldown then return end
	timeRemaining = math.max(0, timeRemaining - dt)
	statusLabel.Text = string.format("КЛИКНИ ДЛЯ УДАРА! %d", math.ceil(timeRemaining))
	if timeRemaining <= 0 then
		isRunning = false
		return
	end
	
	meterValue = meterValue + (dt * speed * direction)
	if meterValue >= 1 then meterValue = 1; direction = -1 end
	if meterValue <= 0 then meterValue = 0; direction = 1 end
	pointer.Position = UDim2.new(meterValue * 0.98, 0, -0.1, 0)
end)

local function calculateMultiplier(val)
	if val <= 0.04 or val >= 0.96 then
		return 1, "EDGE HIT: 1X", Color3.fromRGB(255, 255, 255)
	end
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

local function playBatSwing()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local track = swingTracks[animator]
	if not track then
		local success, loadedTrack = pcall(function()
			return animator:LoadAnimation(swingAnimation)
		end)
		if not success then return end
		track = loadedTrack
		track.Priority = Enum.AnimationPriority.Action
		swingTracks[animator] = track
	end

	track:Play(0.05, 1, 1)
end

local function onCharacterAdded(char)
	isCooldown = false
	isRunning = false
	meterValue = 0
	player:SetAttribute("BonkTimingActive", false)
	meterFrame.Visible = false
end

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

-- === ОБРАБОТКА КЛИКА ===
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or isCooldown or not isRunning then return end
	if input.KeyCode == Enum.KeyCode.E
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		
		isCooldown = true
		isRunning = false
		
		local mult, text, color = calculateMultiplier(meterValue)
		statusLabel.Text = text
		statusLabel.TextColor3 = color
		playBatSwing()
		hitRemote:FireServer(mult)
	end
end)