local Config = {}

-- Время перезарядки между запусками (в секундах)
Config.COOLDOWN = 3.0

-- Множители силы в зависимости от попавшей зоны
Config.TimingMultipliers = {
    Red = 1.0,
    Yellow = 1.2,
    Green = 1.35,
    Perfect = 1.5,
}

-- Формула силы биты от уровня
function Config.GetBatPower(batLevel: number): number
    return 120 * (1.06 ^ (batLevel - 1))
end

return Config