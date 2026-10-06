local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local flightRemote = remotes:WaitForChild("BrainRotFlight")
local steerRemote = remotes:WaitForChild("SteerBrainRot")

local rewardGui = Instance.new("ScreenGui")
rewardGui.Name = "BrainRotFlightGui"
rewardGui.ResetOnSpawn = false
rewardGui.Parent = playerGui

local rewardLabel = Instance.new("TextLabel")
rewardLabel.Name = "FlightResult"
rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
rewardLabel.Position = UDim2.fromScale(0.5, 0.35)
rewardLabel.Size = UDim2.fromOffset(360, 88)
rewardLabel.BackgroundColor3 = Color3.fromRGB(24, 31, 38)
rewardLabel.BackgroundTransparency = 0.1
rewardLabel.BorderSizePixel = 0
rewardLabel.Font = Enum.Font.FredokaOne
rewardLabel.TextColor3 = Color3.fromRGB(255, 231, 112)
rewardLabel.TextSize = 28
rewardLabel.TextStrokeTransparency = 0.7
rewardLabel.TextWrapped = true
rewardLabel.Visible = false
rewardLabel.Parent = rewardGui

local rewardCorner = Instance.new("UICorner")
rewardCorner.CornerRadius = UDim.new(0, 8)
rewardCorner.Parent = rewardLabel

local camera = workspace.CurrentCamera
local flyingPart: BasePart? = nil
local steeringLeft = false
local steeringRight = false
local diving = false
local lastControlSend = 0
local previousSteer = 0
local previousDive = false
local flightToken = 0

local function setCameraToCharacter()
	camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

local function startFlight(part: BasePart)
	if not part:IsA("BasePart") then return end
	flightToken += 1
	flyingPart = part
	steeringLeft = false
	steeringRight = false
	diving = false
	previousSteer = 0
	previousDive = false
	rewardLabel.Visible = false

	camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = part
	end
end

local function endFlight(distance: number, coinsEarned: number)
	flightToken += 1
	flyingPart = nil
	steeringLeft = false
	steeringRight = false
	diving = false
	steerRemote:FireServer(0, false)
	setCameraToCharacter()

	rewardLabel.Text = string.format("%d studs  |  +%d coins", distance, coinsEarned)
	rewardLabel.Visible = true
	local token = flightToken
	task.delay(3, function()
		if flightToken == token then
			rewardLabel.Visible = false
		end
	end)
end

flightRemote.OnClientEvent:Connect(function(action: string, firstValue: any, secondValue: any)
	if action == "Started" and typeof(firstValue) == "Instance" and firstValue:IsA("BasePart") then
		startFlight(firstValue)
	elseif action == "Ended" then
		local distance = if typeof(firstValue) == "number" then firstValue else 0
		local coinsEarned = if typeof(secondValue) == "number" then secondValue else 0
		endFlight(distance, coinsEarned)
	end
end)

local function setInput(input: InputObject, isPressed: boolean)
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
		steeringLeft = isPressed
	elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
		steeringRight = isPressed
	elseif input.KeyCode == Enum.KeyCode.S
		or input.KeyCode == Enum.KeyCode.Down
		or input.KeyCode == Enum.KeyCode.Space then
		diving = isPressed
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not flyingPart or gameProcessed then return end
	setInput(input, true)
end)

UserInputService.InputEnded:Connect(function(input)
	if not flyingPart then return end
	setInput(input, false)
end)

RunService.RenderStepped:Connect(function()
	if not flyingPart then return end
	if not flyingPart.Parent then
		setCameraToCharacter()
		flyingPart = nil
		return
	end

	local steer = (if steeringRight then 1 else 0) - (if steeringLeft then 1 else 0)
	local now = os.clock()
	if steer ~= previousSteer or diving ~= previousDive or now - lastControlSend >= 0.1 then
		steerRemote:FireServer(steer, diving)
		previousSteer = steer
		previousDive = diving
		lastControlSend = now
	end
end)

player.CharacterAdded:Connect(function()
	if not flyingPart then
		setCameraToCharacter()
	end
end)
