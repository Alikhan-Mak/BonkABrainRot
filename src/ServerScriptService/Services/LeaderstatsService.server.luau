local Players = game:GetService("Players")

local function setupPlayer(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats

	local bestDistance = Instance.new("IntValue")
	bestDistance.Name = "Best"
	bestDistance.Value = 0
	bestDistance.Parent = leaderstats

	leaderstats.Parent = player -- parent last so the children are already there when it replicates
end

Players.PlayerAdded:Connect(setupPlayer)
-- Studio: the player can already be in the game before this script runs
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end