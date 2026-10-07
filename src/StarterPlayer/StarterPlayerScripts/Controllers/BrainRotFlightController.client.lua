local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local flightRemote = remotes:WaitForChild("BrainRotFlight")
local steerRemote = remotes:WaitForChild("SteerBrainRot")

local STEER_ACTION = "BrainRotSteer"

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

-- A/D/Left/Right steer, S/Down/Space dive. Sinking these keys stops the character from
-- walking/jumping around while the brainrot is in the air.
local function onSteerAction(_, state: Enum.UserInputState, input: InputObject)
	local pressed = state == Enum.UserInputState.Begin
	local key = input.KeyCode
	if key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
		steeringLeft = pressed
	elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
		steeringRight = pressed
	elseif key == Enum.KeyCode.S or key == Enum.KeyCode.Down or key == Enum.KeyCode.Space then
		diving = pressed
	end
	return Enum.ContextActionResult.Sink
end

local function bindSteering()
	ContextActionService:BindActionAtPriority(
		STEER_ACTION,
		onSteerAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.A,
		Enum.KeyCode.D,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.S,
		Enum.KeyCode.Down,
		Enum.KeyCode.Space
	)
end

local function releaseFlight()
	flyingPart = nil
	steeringLeft = false
	steeringRight = false
	diving = false
	ContextActionService:UnbindAction(STEER_ACTION)
	player:SetAttribute("BrainRotFlying", false)
	setCameraToCharacter()
end

local function startFlight(part: BasePart)
	flightToken += 1
	flyingPart = part
	steeringLeft = false
	steeringRight = false
	diving = false
	previousSteer = 0
	previousDive = false
	rewardLabel.Visible = false
	player:SetAttribute("BrainRotFlying", true)
	bindSteering()

	camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = part
	end
end

local function endFlight(distance: number, coinsEarned: number)
	flightToken += 1
	releaseFlight()
	steerRemote:FireServer(0, false)

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

RunService.RenderStepped:Connect(function()
	if not flyingPart then
		return
	end
	if not flyingPart.Parent then
		releaseFlight()
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