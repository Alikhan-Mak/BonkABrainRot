local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local timingRemote = Remotes:WaitForChild("StartTimingMeter")
local hitRemote = Remotes:WaitForChild("ExecuteHit")

local BAT_SWING_ANIMATION_ID = "rbxassetid://522635514"
local swingAnimation = Instance.new("Animation")
swingAnimation.AnimationId = BAT_SWING_ANIMATION_ID
local swingTracks = setmetatable({}, { __mode = "k" })

local ZONE_COLORS = {
	Red = Color3.fromRGB(220, 50, 50),
	Yellow = Color3.fromRGB(240, 160, 40),
	Green = Color3.fromRGB(50, 200, 80),
	Perfect = Color3.fromRGB(180, 50, 255),
}
local ZONE_TEXT = {
	Red = "WEAK",
	Yellow = "GOOD",
	Green = "GREAT!",
	Perfect = "PERFECT BONK!",
}

-- === UI ===
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

-- Zones are drawn from the SAME Config the zone detection uses: red edges, perfect in the center.
local zoneHolder = Instance.new("Frame")
zoneHolder.Name = "Zones"
zoneHolder.Size = UDim2.new(1, -8, 0.7, 0)
zoneHolder.Position = UDim2.new(0, 4, 0.15, 0)
zoneHolder.BackgroundTransparency = 1
zoneHolder.ClipsDescendants = true
zoneHolder.Parent = meterFrame

local holderCorner = Instance.new("UICorner")
holderCorner.CornerRadius = UDim.new(0, 6)
holderCorner.Parent = zoneHolder

do
	local order = Config.TimingZoneOrder
	local widths = Config.TimingZoneWidths
	local segments = {}
	for i = #order, 2, -1 do -- left side, edge -> center
		table.insert(segments, { order[i], widths[order[i]] / 2 })
	end
	table.insert(segments, { order[1], widths[order[1]] }) -- center
	for i = 2, #order do -- right side, center -> edge
		table.insert(segments, { order[i], widths[order[i]] / 2 })
	end

	local x = 0
	for _, segment in ipairs(segments) do
		local zone = Instance.new("Frame")
		zone.Name = segment[1]
		zone.Size = UDim2.fromScale(segment[2], 1)
		zone.Position = UDim2.fromScale(x, 0)
		zone.BackgroundColor3 = ZONE_COLORS[segment[1]]
		zone.BorderSizePixel = 0
		zone.Parent = zoneHolder
		x += segment[2]
	end
end

local pointer = Instance.new("Frame")
pointer.Name = "Pointer"
pointer.AnchorPoint = Vector2.new(0.5, 0)
pointer.Size = UDim2.new(0, 6, 1.2, 0)
pointer.Position = UDim2.new(0, 4, -0.1, 0)
pointer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
pointer.BorderSizePixel = 0
pointer.ZIndex = 2
pointer.Parent = meterFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 40)
statusLabel.Position = UDim2.new(0, 0, -1.3, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.FredokaOne
statusLabel.TextSize = 28
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextStrokeTransparency = 0.5
statusLabel.Text = "КЛИКНИ ДЛЯ УДАРА!"
statusLabel.Parent = meterFrame

-- === STATE ===
local meterValue = 0
local direction = 1
local isRunning = false
local isCooldown = false
local timeRemaining = 0
local meterStartedAt = 0
local hideToken = 0

local function setPointer(value: number)
	-- zoneHolder has 4px padding on each side; keep the pointer aligned with it
	pointer.Position = UDim2.new(value, 4 - 8 * value, -0.1, 0)
end

-- Server -> client: (true, seconds) starts the meter; (false, reason) ends it
local function startTimingMeter(isActive: boolean, result: any)
	hideToken += 1
	local token = hideToken

	if not isActive then
		isRunning = false
		isCooldown = false
		player:SetAttribute("BonkTimingActive", false)
		if result == "timeout" then
			statusLabel.Text = "ВРЕМЯ ВЫШЛО"
			statusLabel.TextColor3 = Color3.fromRGB(220, 50, 50)
		end
		-- keep the result text ("PERFECT BONK!") on screen for a moment instead of hiding it instantly
		if result == "hit" or result == "timeout" then
			task.delay(0.8, function()
				if hideToken == token then
					meterFrame.Visible = false
				end
			end)
		else
			meterFrame.Visible = false
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
	meterStartedAt = os.clock()
	timeRemaining = if typeof(result) == "number" then result else Config.HIT_WINDOW_SECONDS
	setPointer(0)
	meterFrame.Visible = true
	statusLabel.Text = "КЛИКНИ ДЛЯ УДАРА!"
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
end

timingRemote.OnClientEvent:Connect(startTimingMeter)

RunService.RenderStepped:Connect(function(dt)
	if not isRunning or isCooldown then
		return
	end
	timeRemaining = math.max(0, timeRemaining - dt)
	statusLabel.Text = string.format("КЛИКНИ ДЛЯ УДАРА! %d", math.ceil(timeRemaining))
	if timeRemaining <= 0 then
		isRunning = false -- the server launches automatically on timeout
		return
	end

	meterValue += dt * Config.POINTER_SPEED * direction
	if meterValue >= 1 then
		meterValue = 1
		direction = -1
	elseif meterValue <= 0 then
		meterValue = 0
		direction = 1
	end
	setPointer(meterValue)
end)

local function playBatSwing()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

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
		if not success then
			return
		end
		track = loadedTrack
		track.Priority = Enum.AnimationPriority.Action
		swingTracks[animator] = track
	end

	track:Play(0.05, 1, 1)
end

local function onCharacterAdded()
	isCooldown = false
	isRunning = false
	meterValue = 0
	player:SetAttribute("BonkTimingActive", false)
	meterFrame.Visible = false
end

if player.Character then
	onCharacterAdded()
end
player.CharacterAdded:Connect(onCharacterAdded)

-- === SWING INPUT ===
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or isCooldown or not isRunning then
		return
	end
	-- ignore input right after the meter appears so the E press that STARTED it doesn't also swing
	if os.clock() - meterStartedAt < 0.25 then
		return
	end

	if input.KeyCode == Enum.KeyCode.E
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		isCooldown = true
		isRunning = false

		-- Only the zone NAME goes to the server; the server owns the multiplier table.
		local zone = Config.GetTimingZone(meterValue)
		statusLabel.Text = ZONE_TEXT[zone]
		statusLabel.TextColor3 = ZONE_COLORS[zone]
		playBatSwing()
		hitRemote:FireServer(zone)
	end
end)