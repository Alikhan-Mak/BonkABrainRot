local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ZoneUtil = require(Shared:WaitForChild("ZoneUtil"))

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local triggerRemote = Remotes:WaitForChild("TriggerBonkSequence")

local ACTION_NAME = "BonkStart"
local lastFireAt = 0

-- Client-side pre-check is only for UX; the server validates everything again.
local function tryStart()
	local now = os.clock()
	if now - lastFireAt < 0.5 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not root or not tool then
		return
	end
	if player:GetAttribute("BonkTimingActive") == true or player:GetAttribute("BrainRotFlying") == true then
		return
	end

	local zone = ZoneUtil.find("BonkZone")
	if zone and not ZoneUtil.isInside(zone, root.Position, Config.BONK_ZONE_MARGIN) then
		return
	end

	lastFireAt = now
	triggerRemote:FireServer()
end

-- E on keyboard + an on-screen "BONK" button on mobile.
-- Returning Pass keeps the E key visible to TimingController (it also uses E to swing).
ContextActionService:BindAction(ACTION_NAME, function(_, state)
	if state == Enum.UserInputState.Begin then
		tryStart()
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.E)
ContextActionService:SetTitle(ACTION_NAME, "BONK")
ContextActionService:SetPosition(ACTION_NAME, UDim2.new(1, -100, 1, -180))