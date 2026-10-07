local Config = {}

-- Cooldown between launches (seconds). Counted from the END of the previous flight.
Config.COOLDOWN = 3.0

-- Power multiplier per timing zone. The client only sends the zone NAME, the server looks the number up here.
Config.TimingMultipliers = {
	Red = 1.0,
	Yellow = 1.2,
	Green = 1.35,
	Perfect = 1.5,
}

-- Zone widths as a share of the whole meter (sum = 1.0).
-- Perfect is in the CENTER, Red is on both EDGES (see ТЗ section 3).
Config.TimingZoneWidths = {
	Perfect = 0.05,
	Green = 0.20,
	Yellow = 0.35,
	Red = 0.40,
}
Config.TimingZoneOrder = { "Perfect", "Green", "Yellow", "Red" } -- from center to edges

-- pointerPosition: 0..1 across the meter
function Config.GetTimingZone(pointerPosition: number): string
	local fromCenter = math.abs(pointerPosition - 0.5) * 2
	local edge = 0
	for _, name in ipairs(Config.TimingZoneOrder) do
		edge += Config.TimingZoneWidths[name]
		if fromCenter <= edge + 1e-6 then
			return name
		end
	end
	return "Red"
end

-- Meter
Config.HIT_WINDOW_SECONDS = 10 -- time the player has to hit before an auto-launch
Config.POINTER_SPEED = 1.0 -- meter lengths per second (2.5 was far too fast for a 5% Perfect zone)

-- Bonk zone
Config.BONK_ZONE_MARGIN = 15 -- studs around the BonkZone part where launching is allowed
Config.REQUIRE_BONK_ZONE = false -- false = if no part named "BonkZone" exists in Workspace, allow launching anywhere. Set true for release.

-- Flight
Config.LAUNCH_ANGLE_DEGREES = 40
Config.MAX_FLIGHT_SECONDS = 20
Config.COINS_PER_STUD = 1.5

-- Bat
Config.BAT_HITBOX_SIZE = Vector3.new(7, 7, 9)
Config.BAT_HITBOX_FORWARD_OFFSET = 4
Config.BAT_ATTACK_COOLDOWN = 0.35
Config.KNOCKDOWN_SECONDS = 2
Config.PVP_ENABLED = false -- ТЗ: PvP sabotage is postponed until after soft launch

-- Bat power by level
function Config.GetBatPower(batLevel: number): number
	return 120 * (1.06 ^ (batLevel - 1))
end

return Config