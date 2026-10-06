local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local triggerRemote = Remotes:WaitForChild("TriggerBonkSequence")

-- Подбрасываем BrainRot при нажатии на клавишу E
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.E then
		local character = player.Character
		local equippedTool = character and character:FindFirstChildOfClass("Tool")

		if equippedTool and player:GetAttribute("BonkTimingActive") ~= true then
			triggerRemote:FireServer()
		end
	end
end)