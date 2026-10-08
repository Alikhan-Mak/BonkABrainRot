local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local KNOCKDOWN_SECONDS = 3
local ATTACK_COOLDOWN_SECONDS = 0.65
local HITBOX_SIZE = Vector3.new(7, 7, 9)
local HITBOX_FORWARD_OFFSET = 4

local boundTools = setmetatable({}, { __mode = "k" })
local lastAttackAt = {} -- [Player]
local knockedDown = setmetatable({}, { __mode = "k" }) -- [character Model] (works for players AND NPCs)

local function isInsideSafeZone(position: Vector3): boolean
	local zonesFolder = Workspace:FindFirstChild("Zones")
	local safeZone = zonesFolder and zonesFolder:FindFirstChild("SafeZone")
	if not safeZone or not safeZone:IsA("BasePart") then
		return true -- no SafeZone in the map: allow attacks
	end

	local localPosition = safeZone.CFrame:PointToObjectSpace(position)
	local halfSize = safeZone.Size / 2
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function findTarget(character: Model, root: BasePart): (Model?, Humanoid?, BasePart?)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local hitboxCFrame = root.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD_OFFSET)
	local hitParts = Workspace:GetPartBoundsInBox(hitboxCFrame, HITBOX_SIZE, overlapParams)

	local nearestCharacter, nearestHumanoid, nearestRoot = nil, nil, nil
	local nearestDistance = math.huge

	for _, hitPart in ipairs(hitParts) do
		local targetCharacter = hitPart:FindFirstAncestorOfClass("Model")
		if targetCharacter and targetCharacter ~= character then
			local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
			if targetHumanoid and targetRoot and targetRoot:IsA("BasePart") and targetHumanoid.Health > 0 then
				local distance = (targetRoot.Position - root.Position).Magnitude
				if distance < nearestDistance then
					nearestCharacter, nearestHumanoid, nearestRoot = targetCharacter, targetHumanoid, targetRoot
					nearestDistance = distance
				end
			end
		end
	end

	return nearestCharacter, nearestHumanoid, nearestRoot
end

local function knockDown(targetCharacter: Model, targetHumanoid: Humanoid, targetRoot: BasePart, direction: Vector3)
	if knockedDown[targetCharacter] or targetHumanoid.Health <= 0 then
		return
	end

	local state = {
		walkSpeed = targetHumanoid.WalkSpeed,
		jumpPower = targetHumanoid.JumpPower,
		jumpHeight = targetHumanoid.JumpHeight,
		autoRotate = targetHumanoid.AutoRotate,
		rootAnchored = targetRoot.Anchored,
	}
	knockedDown[targetCharacter] = state

	local knockDirection = if direction.Magnitude > 0 then direction.Unit else Vector3.new(0, 1, 0)

	targetHumanoid.WalkSpeed = 0
	targetHumanoid.JumpPower = 0
	targetHumanoid.JumpHeight = 0
	targetHumanoid.AutoRotate = false
	targetHumanoid.PlatformStand = true
	targetHumanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	targetRoot.Anchored = false
	targetRoot:ApplyImpulse((knockDirection * 1000 + Vector3.new(0, 500, 0)) * targetRoot.AssemblyMass)
	targetRoot.AssemblyAngularVelocity = Vector3.new(knockDirection.Z * 3, 0, -knockDirection.X * 3)

	task.delay(KNOCKDOWN_SECONDS, function()
		if knockedDown[targetCharacter] ~= state then
			return
		end
		knockedDown[targetCharacter] = nil

		if targetHumanoid.Parent and targetHumanoid.Health > 0 then
			targetHumanoid.WalkSpeed = state.walkSpeed
			targetHumanoid.JumpPower = state.jumpPower
			targetHumanoid.JumpHeight = state.jumpHeight
			targetHumanoid.AutoRotate = state.autoRotate
			targetHumanoid.PlatformStand = false
			if targetRoot.Parent then
				targetRoot.Anchored = state.rootAnchored
				targetRoot.AssemblyAngularVelocity = Vector3.zero
			end
			targetHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function onToolActivated(tool: Tool)
	local character = tool.Parent
	local attacker = character and Players:GetPlayerFromCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (attacker and humanoid and root) or humanoid.Health <= 0 or not root:IsA("BasePart") then
		return
	end
	if not isInsideSafeZone(root.Position) then
		return
	end

	local now = os.clock()
	if lastAttackAt[attacker] and now - lastAttackAt[attacker] < ATTACK_COOLDOWN_SECONDS then
		return
	end
	lastAttackAt[attacker] = now

	local targetCharacter, targetHumanoid, targetRoot = findTarget(character, root)
	if not (targetCharacter and targetHumanoid and targetRoot) then
		return
	end

	local direction = targetRoot.Position - root.Position
	direction = if direction.Magnitude <= 0.001 then root.CFrame.LookVector else direction.Unit

	knockDown(targetCharacter, targetHumanoid, targetRoot, direction)
end

local function bindTool(tool: Instance)
	if not tool:IsA("Tool") or boundTools[tool] then
		return
	end
	boundTools[tool] = true
	tool.Activated:Connect(function()
		onToolActivated(tool)
	end)
end

local function bindBackpack(backpack: Instance)
	if not backpack:IsA("Backpack") then
		return
	end
	for _, child in ipairs(backpack:GetChildren()) do
		bindTool(child)
	end
	backpack.ChildAdded:Connect(bindTool)
end

local function setupPlayer(player: Player)
	local function setupCharacter(character: Model)
		for _, child in ipairs(character:GetChildren()) do
			bindTool(child)
		end
		character.ChildAdded:Connect(bindTool)
	end

	-- the Backpack is re-created on every respawn, so watch for new ones
	player.ChildAdded:Connect(bindBackpack)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		bindBackpack(backpack)
	end

	if player.Character then
		setupCharacter(player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end
Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	lastAttackAt[player] = nil
end)