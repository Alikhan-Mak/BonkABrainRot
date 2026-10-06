local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function getRemoteEvent(name: string): RemoteEvent
	local remote = remotesFolder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
	end
	return remote :: RemoteEvent
end

local triggerRemote = getRemoteEvent("TriggerBonkSequence")
local timingRemote = getRemoteEvent("StartTimingMeter")
local hitRemote = getRemoteEvent("ExecuteHit")
local flightRemote = getRemoteEvent("BrainRotFlight")
local steerRemote = getRemoteEvent("SteerBrainRot")

local HIT_WINDOW_SECONDS = 10
local BONK_ZONE_RADIUS = 15
local activeSequences = {}
local activeFlights = {}

print("[BrainRot] Service loaded; waiting for TriggerBonkSequence.")

local function getBonkZoneDistance(position: Vector3): number?
	local zonesFolder = Workspace:FindFirstChild("Zones")
	local bonkZone = zonesFolder and zonesFolder:FindFirstChild("BonkZone")
	if not bonkZone or not bonkZone:IsA("BasePart") then
		warn("[BrainRot] Cannot start: Workspace.Zones.BonkZone is missing or is not a BasePart.")
		return nil
	end

	return (position - bonkZone.Position).Magnitude
end

local function restoreCharacter(sequence)
	local humanoid = sequence.humanoid
	local root = sequence.root
	if humanoid.Parent then
		humanoid.WalkSpeed = sequence.walkSpeed
		humanoid.JumpPower = sequence.jumpPower
		humanoid.JumpHeight = sequence.jumpHeight
		humanoid.AutoRotate = sequence.autoRotate
	end
	if root.Parent then
		root.Anchored = sequence.rootAnchored
	end
end

local function finishSequence(player: Player, sequence, reason: string, destroyBrainRot: boolean)
	if activeSequences[player] ~= sequence then return end
	activeSequences[player] = nil
	restoreCharacter(sequence)
	if destroyBrainRot and sequence.brainRot.Parent then
		sequence.brainRot:Destroy()
	end
	timingRemote:FireClient(player, false, reason)
end

local function completeFlight(player: Player, flight)
	if activeFlights[player] ~= flight then return end
	activeFlights[player] = nil

	local part = flight.brainRot
	local finalPosition = if part.Parent then part.Position else flight.lastPosition
	local distance = math.floor((finalPosition - flight.startPosition).Magnitude)
	local coinsEarned = math.floor(distance * 1.5)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local coins = leaderstats:FindFirstChild("Coins")
		local best = leaderstats:FindFirstChild("Best")
		if coins and coins:IsA("IntValue") then
			coins.Value += coinsEarned
		end
		if best and best:IsA("IntValue") and distance > best.Value then
			best.Value = distance
		end
	end

	flightRemote:FireClient(player, "Ended", distance, coinsEarned)
	if part.Parent then
		task.delay(1, function()
			if part.Parent then
				part:Destroy()
			end
		end)
	end
end

local function launchBrainRot(player: Player, sequence, multiplier: number, reason: string)
	if activeSequences[player] ~= sequence then return end
	local brainRot = sequence.brainRot
	if not brainRot.Parent then
		finishSequence(player, sequence, "cancelled", false)
		return
	end

	local power = math.clamp(multiplier, 0.3, 3.5)
	local launchDirection = (sequence.root.CFrame.LookVector + Vector3.new(0, 0.8, 0)).Unit
	brainRot.Anchored = false
	brainRot.AssemblyLinearVelocity = launchDirection * (45 * power)
	brainRot.AssemblyAngularVelocity = Vector3.new(0, 8, 0)
	pcall(function()
		brainRot:SetNetworkOwner(nil)
	end)

	local now = os.clock()
	local flight = {
		brainRot = brainRot,
		startPosition = brainRot.Position,
		lastPosition = brainRot.Position,
		startedAt = now,
		lastMovedAt = now,
		nextGroundCheck = now,
		steer = 0,
		dive = false,
	}
	activeFlights[player] = flight
	finishSequence(player, sequence, reason, false)
	flightRemote:FireClient(player, "Started", brainRot)
end

local function startSequence(player: Player)
	print(string.format("[BrainRot] TriggerBonkSequence received from %s.", player.Name))
	if activeSequences[player] or activeFlights[player] then
		print(string.format("[BrainRot] Ignored request from %s: sequence or flight already active.", player.Name))
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local equippedTool = character and character:FindFirstChildOfClass("Tool")
	if not (character and humanoid and root and equippedTool) then
		warn(string.format("[BrainRot] Cannot start for %s: character, Humanoid, root, or equipped Tool is missing.", player.Name))
		return
	end
	if humanoid.Health <= 0 then
		warn(string.format("[BrainRot] Cannot start for %s: Humanoid is dead.", player.Name))
		return
	end

	local zoneDistance = getBonkZoneDistance(root.Position)
	if zoneDistance == nil then return end
	print(string.format("[BrainRot] %s is %.2f studs from BonkZone (limit: %d).", player.Name, zoneDistance, BONK_ZONE_RADIUS))
	if zoneDistance > BONK_ZONE_RADIUS then
		print(string.format("[BrainRot] Rejected %s: outside BonkZone launch radius.", player.Name))
		return
	end

	local brainRot = Instance.new("Part")
	brainRot.Name = "CurrentBrainRot"
	brainRot.Size = Vector3.new(2, 2, 2)
	brainRot.Shape = Enum.PartType.Block
	brainRot.BrickColor = BrickColor.new("Bright yellow")
	brainRot.Material = Enum.Material.SmoothPlastic
	brainRot.CanCollide = true
	brainRot.Anchored = true
	brainRot.CFrame = root.CFrame * CFrame.new(0, 4, -6)
	brainRot.Parent = Workspace

	local sequence = {
		character = character,
		humanoid = humanoid,
		root = root,
		brainRot = brainRot,
		startedAt = os.clock(),
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		rootAnchored = root.Anchored,
	}
	activeSequences[player] = sequence

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	root.Anchored = true
	timingRemote:FireClient(player, true, HIT_WINDOW_SECONDS)
	print(string.format("[BrainRot] Sequence started for %s; timing window is %d seconds.", player.Name, HIT_WINDOW_SECONDS))

	task.delay(HIT_WINDOW_SECONDS, function()
		if activeSequences[player] == sequence then
			launchBrainRot(player, sequence, 1, "timeout")
		end
	end)
end

triggerRemote.OnServerEvent:Connect(startSequence)

hitRemote.OnServerEvent:Connect(function(player: Player, multiplier: any)
	local sequence = activeSequences[player]
	if not sequence then return end
	if os.clock() - sequence.startedAt >= HIT_WINDOW_SECONDS then
		launchBrainRot(player, sequence, 1, "timeout")
		return
	end
	if player.Character ~= sequence.character or sequence.humanoid.Health <= 0 then
		finishSequence(player, sequence, "cancelled", true)
		return
	end
	if typeof(multiplier) ~= "number" then return end

	launchBrainRot(player, sequence, multiplier, "hit")
end)

steerRemote.OnServerEvent:Connect(function(player: Player, steer: any, dive: any)
	local flight = activeFlights[player]
	if not flight then return end
	if typeof(steer) == "number" then
		flight.steer = math.clamp(steer, -1, 1)
	end
	if typeof(dive) == "boolean" then
		flight.dive = dive
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	local now = os.clock()
	for player, flight in pairs(activeFlights) do
		local brainRot = flight.brainRot
		if not brainRot.Parent then
			completeFlight(player, flight)
			continue
		end

		local velocity = brainRot.AssemblyLinearVelocity
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		if flatVelocity.Magnitude > 0.1 and flight.steer ~= 0 then
			local yaw = math.rad(120) * flight.steer * deltaTime
			flatVelocity = CFrame.fromAxisAngle(Vector3.yAxis, yaw):VectorToWorldSpace(flatVelocity)
		end
		local verticalVelocity = velocity.Y
		if flight.dive then
			verticalVelocity = math.min(verticalVelocity - 65 * deltaTime, -35)
		end
		brainRot.AssemblyLinearVelocity = Vector3.new(flatVelocity.X, verticalVelocity, flatVelocity.Z)

		flight.lastPosition = brainRot.Position
		if brainRot.AssemblyLinearVelocity.Magnitude > 2 then
			flight.lastMovedAt = now
		end

		if now >= flight.nextGroundCheck then
			flight.nextGroundCheck = now + 0.1
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { brainRot, player.Character }
			local groundHit = Workspace:Raycast(
				brainRot.Position,
				Vector3.new(0, -(brainRot.Size.Y / 2 + 0.35), 0),
				raycastParams
			)
			local flightTime = now - flight.startedAt
			if (flightTime > 0.4 and groundHit)
				or (flightTime > 0.8 and now - flight.lastMovedAt > 0.8)
				or flightTime > 20 then
				completeFlight(player, flight)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local sequence = activeSequences[player]
	if sequence then
		finishSequence(player, sequence, "cancelled", true)
	end
	local flight = activeFlights[player]
	if flight then
		activeFlights[player] = nil
		if flight.brainRot.Parent then
			flight.brainRot:Destroy()
		end
	end
end)