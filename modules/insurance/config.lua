Config = Config or {}
Config.Insurance = Config.Insurance or {}
local Config = Config.Insurance
Config.Enabled = Config.Enabled ~= false

Config.Debug = (Config.Debug == true)

Config.PremiumIntervalMinutes = 10

Config.DefaultPremium    = 250
Config.DefaultDeductible = 1000

Config.ClaimSpawnOffset = vector3(0.0, 5.0, 0.0)

Config.OpenCommand = 'insurance'

Config.PolicyTypes = {
    basic = {
        label             = "Basic coverage",
        description       = "Cheapest plan with high deductible.",
        premiumMultiplier = 0.6,
        deductible        = 2000
    },
    standard = {
        label             = "Standard coverage",
        description       = "Balanced premium and deductible.",
        premiumMultiplier = 1.0,
        deductible        = 1000
    },
    full = {
        label             = "Full coverage",
        description       = "0 deductible theft replacement. Highest premium.",
        premiumMultiplier = 1.8,
        deductible        = 0
    }
}

Config.CharacterScoped = true

Config.WreckSystem = Config.WreckSystem or {}
Config.WreckSystem.Enabled = Config.WreckSystem.Enabled ~= false
Config.WreckSystem.ImpactSpeedMph = tonumber(Config.WreckSystem.ImpactSpeedMph or 25.0) or 25.0
Config.WreckSystem.BodyHealthDelta = tonumber(Config.WreckSystem.BodyHealthDelta or 20.0) or 20.0
Config.WreckSystem.ScanRadius = tonumber(Config.WreckSystem.ScanRadius or 12.0) or 12.0
Config.WreckSystem.ExchangeDistance = tonumber(Config.WreckSystem.ExchangeDistance or 3.0) or 3.0
Config.WreckSystem.SightSecondsMin = tonumber(Config.WreckSystem.SightSecondsMin or 3.0) or 3.0
Config.WreckSystem.SightSecondsMax = tonumber(Config.WreckSystem.SightSecondsMax or 5.0) or 5.0
Config.WreckSystem.ReportDepartment = tostring(Config.WreckSystem.ReportDepartment or 'police')
Config.WreckSystem.AutoRepairOnExchange = Config.WreckSystem.AutoRepairOnExchange ~= false

Config.WreckSystem.TrafficZoneRadius = tonumber(Config.WreckSystem.TrafficZoneRadius or 35.0) or 35.0
Config.WreckSystem.TrafficZoneSpeed = tonumber(Config.WreckSystem.TrafficZoneSpeed or 8.0) or 8.0
Config.WreckSystem.TrafficZoneVisible = Config.WreckSystem.TrafficZoneVisible ~= false
Config.WreckSystem.ExchangePromptDistance = tonumber(Config.WreckSystem.ExchangePromptDistance or 4.0) or 4.0
