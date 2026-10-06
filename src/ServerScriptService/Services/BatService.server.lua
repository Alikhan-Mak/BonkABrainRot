local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local KNOCKDOWN_SECONDS = 5
local ATTACK_COOLDOWN_SECONDS = 0.65
local HITBOX_SIZE = Vector3.new(7, 7, 9)
local HITBOX_FORWARD_OFFSET = 4
local KNOCKBACK_SPEED = 16
local UPWARD_SPEED = 5

local boundTools = {}
local lastAttackAt = {}
local knockedDown = {}

local function isInsideSafeZone(position: Vector3): boolean
	local zonesFolder = Workspace:FindFirstChild("Zones")
	local safeZone = zonesFolder and zonesFolder:FindFirstChild("SafeZone")
	if not safeZone or not safeZone:IsA("BasePart") then
		return false
	end

	local localPosition = safeZone.CFrame:PointToObjectSpace(position)
	local halfSize = safeZone.Size / 2
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function findTarget(attacker: Player, character: Model, root: BasePart): (Player?, Model?, Humanoid?, BasePart?)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local hitboxCFrame = root.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD_OFFSET)
	local hitParts = Workspace:GetPartBoundsInBox(hitboxCFrame, HITBOX_SIZE, overlapParams)
	local nearestPlayer = nil
	local nearestCharacter = nil
	local nearestHumanoid = nil
	local nearestRoot = nil
	local nearestDistance = math.huge

	for _, hitPart in ipairs(hitParts) do
		local targetCharacter = hitPart:FindFirstAncestorOfClass("Model")
		if targetCharacter and targetCharacter ~= character then
			local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
			local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
			if targetPlayer and targetHumanoid and targetRoot and targetHumanoid.Health > 0 then
				local distance = (targetRoot.Position - root.Position).Magnitude
				if distance < nearestDistance then
					nearestPlayer = targetPlayer
					nearestCharacter = targetCharacter
					nearestHumanoid = targetHumanoid
					nearestRoot = targetRoot
					nearestDistance = distance
				end
			end
		end
	end

	return nearestPlayer, nearestCharacter, nearestHumanoid, nearestRoot
end

local function knockDown(targetPlayer: Player, targetHumanoid: Humanoid, targetRoot: BasePart, direction: Vector3)
	if knockedDown[targetPlayer] or targetHumanoid.Health <= 0 then return end

	local state = {
		token = {},
		humanoid = targetHumanoid,
		root = targetRoot,
		walkSpeed = targetHumanoid.WalkSpeed,
		jumpPower = targetHumanoid.JumpPower,
		jumpHeight = targetHumanoid.JumpHeight,
		autoRotate = targetHumanoid.AutoRotate,
		rootAnchored = targetRoot.Anchored,
	}
	knockedDown[targetPlayer] = state

	targetHumanoid.WalkSpeed = 0
	targetHumanoid.JumpPower = 0
	targetHumanoid.JumpHeight = 0
	targetHumanoid.AutoRotate = false
	targetHumanoid.PlatformStand = true
	targetHumanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	targetRoot.Anchored = false
	targetRoot:ApplyImpulse(
		(direction * KNOCKBACK_SPEED + Vector3.new(0, UPWARD_SPEED, 0)) * targetRoot.AssemblyMass
	)
	targetRoot.AssemblyAngularVelocity = Vector3.new(direction.Z * 3, 0, -direction.X * 3)

	task.delay(KNOCKDOWN_SECONDS, function()
		if knockedDown[targetPlayer] ~= state then return end
		knockedDown[targetPlayer] = nil

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
	if not (attacker and humanoid and root) or humanoid.Health <= 0 then return end
	if not isInsideSafeZone(root.Position) then return end

	local now = os.clock()
	if lastAttackAt[attacker] and now - lastAttackAt[attacker] < ATTACK_COOLDOWN_SECONDS then return end
	lastAttackAt[attacker] = now

	local targetPlayer, _, targetHumanoid, targetRoot = findTarget(attacker, character, root)
	if not (targetPlayer and targetHumanoid and targetRoot) then return end

	local direction = targetRoot.Position - root.Position
	if direction.Magnitude <= 0.001 then
		direction = root.CFrame.LookVector
	else
		direction = direction.Unit
	end

	knockDown(targetPlayer, targetHumanoid, targetRoot, direction)
end

local function bindTool(tool: Instance)
	if not tool:IsA("Tool") or boundTools[tool] then return end
	boundTools[tool] = true
	tool.Activated:Connect(function()
		onToolActivated(tool)
	end)
end

local function setupPlayer(player: Player)
	local function setupCharacter(character: Model)
		for _, child in ipairs(character:GetChildren()) do
			bindTool(child)
		end
		character.ChildAdded:Connect(bindTool)
	end

	if player.Character then
		setupCharacter(player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)

	local backpack = player:WaitForChild("Backpack")
	for _, child in ipairs(backpack:GetChildren()) do
		bindTool(child)
	end
	backpack.ChildAdded:Connect(bindTool)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end
Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	lastAttackAt[player] = nil
	knockedDown[player] = nil
end)