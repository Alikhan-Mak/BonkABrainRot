-- Finds zone parts (e.g. "BonkZone") anywhere in Workspace and tests if a position is in/near them.
-- Used by BOTH the client and the server, so they can never disagree about where the zone is.
local Workspace = game:GetService("Workspace")

local ZoneUtil = {}

local cache: { [string]: BasePart } = {}

function ZoneUtil.find(name: string): BasePart?
	local cached = cache[name]
	if cached and cached:IsDescendantOf(Workspace) then
		return cached
	end
	cache[name] = nil

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst.Name == name and inst:IsA("BasePart") then
			cache[name] = inst
			return inst
		end
	end
	return nil
end

-- True if position is inside the zone's box, expanded by `margin` studs.
-- Works for big flat pads too (the old code measured distance to the part CENTER).
function ZoneUtil.isInside(zone: BasePart, position: Vector3, margin: number): boolean
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X + margin
		and math.abs(localPos.Y) <= half.Y + margin + 10
		and math.abs(localPos.Z) <= half.Z + margin
end

return ZoneUtil