local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ZoneUtil = require(Shared:WaitForChild("ZoneUtil"))

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

local activeSequences = {}
local activeFlights = {}
local lastFlightEndedAt = {}
local lastSteerAt = {}
local warnedNoZone = false

local function isInBonkZone(position: Vector3): boolean
	local zone = ZoneUtil.find("BonkZone")
	if not zone then
		if Config.REQUIRE_BONK_ZONE then
			warn("[BrainRot] No part named 'BonkZone' found in Workspace - launching is disabled.")
			return false
		end
		if not warnedNoZone then
			warnedNoZone = true
			warn("[BrainRot] No part named 'BonkZone' found in Workspace - allowing launch anywhere (Config.REQUIRE_BONK_ZONE = false).")
		end
		return true
	end
	return ZoneUtil.isInside(zone, position, Config.BONK_ZONE_MARGIN)
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
	if activeSequences[player] ~= sequence then
		return
	end
	activeSequences[player] = nil
	restoreCharacter(sequence)
	if destroyBrainRot and sequence.brainRot.Parent then
		sequence.brainRot:Destroy()
	end
	timingRemote:FireClient(player, false, reason)
end

local function completeFlight(player: Player, flight)
	if activeFlights[player] ~= flight then
		return
	end
	activeFlights[player] = nil
	lastFlightEndedAt[player] = os.clock()

	local part = flight.brainRot
	local finalPosition = if part.Parent then part.Position else flight.lastPosition
	-- horizontal distance only: height should not count as "distance"
	local offset = finalPosition - flight.startPosition
	local distance = math.floor(Vector3.new(offset.X, 0, offset.Z).Magnitude)
	local coinsEarned = math.floor(distance * Config.COINS_PER_STUD)

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

local function launchBrainRot(player: Player, sequence, zoneName: string, reason: string)
	if activeSequences[player] ~= sequence then
		return
	end
	local brainRot = sequence.brainRot
	if not brainRot.Parent or player.Character ~= sequence.character or sequence.humanoid.Health <= 0 then
		finishSequence(player, sequence, "cancelled", true)
		return
	end

	-- Everything below is computed on the server from the server's own tables
	local timing = Config.TimingMultipliers[zoneName] or Config.TimingMultipliers.Red
	local batLevel = player:GetAttribute("BatLevel")
	if typeof(batLevel) ~= "number" then
		batLevel = 1
	end
	local power = Config.GetBatPower(batLevel) * timing

	local look = sequence.root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 0.001 then flatLook.Unit else Vector3.new(0, 0, -1)
	local angle = math.rad(Config.LAUNCH_ANGLE_DEGREES)
	local launchDirection = flatLook * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)

	brainRot.Anchored = false
	pcall(function()
		brainRot:SetNetworkOwner(nil)
	end)
	brainRot.AssemblyLinearVelocity = launchDirection * power
	brainRot.AssemblyAngularVelocity = Vector3.new(0, 8, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { brainRot, sequence.character }

	local now = os.clock()
	activeFlights[player] = {
		brainRot = brainRot,
		startPosition = brainRot.Position,
		lastPosition = brainRot.Position,
		startedAt = now,
		lastMovedAt = now,
		nextGroundCheck = now,
		raycastParams = raycastParams,
		steer = 0,
		dive = false,
	}
	local flight = activeFlights[player]
	finishSequence(player, sequence, reason, false)
	flightRemote:FireClient(player, "Started", brainRot)
	print(string.format("[BrainRot] %s launched: zone=%s power=%.1f", player.Name, zoneName, power))
	return flight
end

local function startSequence(player: Player)
	if activeSequences[player] or activeFlights[player] then
		return
	end
	local lastEnd = lastFlightEndedAt[player]
	if lastEnd and os.clock() - lastEnd < Config.COOLDOWN then
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
		return
	end
	if not isInBonkZone(root.Position) then
		return
	end

	local brainRot = Instance.new("Part")
	brainRot.Name = "CurrentBrainRot"
	brainRot.Size = Vector3.new(2, 2, 2)
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
	timingRemote:FireClient(player, true, Config.HIT_WINDOW_SECONDS)

	humanoid.Died:Connect(function()
		finishSequence(player, sequence, "cancelled", true)
	end)

	task.delay(Config.HIT_WINDOW_SECONDS, function()
		if activeSequences[player] == sequence then
			launchBrainRot(player, sequence, "Red", "timeout")
		end
	end)
end

triggerRemote.OnServerEvent:Connect(startSequence)

hitRemote.OnServerEvent:Connect(function(player: Player, zone: any)
	local sequence = activeSequences[player]
	if not sequence then
		return
	end
	if os.clock() - sequence.startedAt >= Config.HIT_WINDOW_SECONDS then
		launchBrainRot(player, sequence, "Red", "timeout")
		return
	end
	-- the client sends only a zone NAME; anything unknown counts as the weakest zone
	if typeof(zone) ~= "string" or Config.TimingMultipliers[zone] == nil then
		zone = "Red"
	end
	launchBrainRot(player, sequence, zone, "hit")
end)

steerRemote.OnServerEvent:Connect(function(player: Player, steer: any, dive: any)
	local flight = activeFlights[player]
	if not flight then
		return
	end
	local now = os.clock()
	if lastSteerAt[player] and now - lastSteerAt[player] < 0.03 then
		return -- rate limit
	end
	lastSteerAt[player] = now

	if typeof(steer) == "number" and steer == steer then
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
			local groundHit = Workspace:Raycast(
				brainRot.Position,
				Vector3.new(0, -(brainRot.Size.Y / 2 + 0.35), 0),
				flight.raycastParams
			)
			local flightTime = now - flight.startedAt
			if (flightTime > 0.4 and groundHit)
				or (flightTime > 0.8 and now - flight.lastMovedAt > 0.8)
				or flightTime > Config.MAX_FLIGHT_SECONDS then
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
	lastFlightEndedAt[player] = nil
	lastSteerAt[player] = nil
end)