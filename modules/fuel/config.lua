Config = Config or {}
Config.Fuel = Config.Fuel or {}
local Config = Config.Fuel
Config.Enabled = Config.Enabled ~= false

Config.Debug = false

Config.MaxFuel = 100.0
Config.MinFuelToStart = 1.0

Config.FuelDrainIdle       = 0.003
Config.FuelDrainDriving    = 0.025
Config.FuelDrainHighSpeed  = 0.05

Config.FuelTickInterval = 1000

Config.FuelPerSecondAtPump   = 2.0
Config.EVChargePerSecond     = 2.0
Config.MaxPumpDistance       = 2.2
Config.MaxVehicleDistance    = 3.0
Config.MaxHoseStretch        = 12.0

Config.UseBilling            = true
Config.PricePerUnitFuel      = 2.0
Config.PricePerUnitElectric  = 1.5

Config.EnableHUD = true
Config.HUD = {
    alignRight = true,
    offsetX    = 0.0,
    offsetY    = 0.0,
}

Config.HUD.offsetX = -0.050
Config.HUD.offsetY =  0.002

Config.DrawHoseRope = true

Config.HoseModel = `prop_cs_fuel_nozle`

Config.ElectricModels = {

}

Config.PumpModels = {

    `prop_gas_pump_1a`,
    `prop_gas_pump_1b`,
    `prop_gas_pump_1c`,
    `prop_gas_pump_1d`,
    `prop_gas_pump_old2`,
    `prop_gas_pump_old3`,
    `prop_vintage_pump`,

    `denis3d_prop_gas_pump`,
    `amb_rox_caspump_pf`

}

Config.Pumps = {
    { coords = vector3(265.0, -1261.3, 29.2), heading = 90.0 },
    { coords = vector3(273.0, -1261.3, 29.2), heading = 90.0 },
    { coords = vector3(281.0, -1261.3, 29.2), heading = 90.0 },
    { coords = vector3(289.0, -1261.3, 29.2), heading = 90.0 },

    { coords = vector3(1179.1, -330.7, 69.1), heading = 100.0 },
    { coords = vector3(1184.8, -324.2, 69.1), heading = 100.0 },
    { coords = vector3(1190.7, -317.4, 69.1), heading = 100.0 },

    { coords = vector3(1180.5, -1400.7, 35.3), heading = 180.0 },
    { coords = vector3(1180.5, -1393.2, 35.3), heading = 180.0 },
    { coords = vector3(1180.5, -1385.7, 35.3), heading = 180.0 },

    { coords = vector3(2001.1, 3774.6, 32.4), heading = 119.0 },
    { coords = vector3(2005.8, 3779.9, 32.4), heading = 119.0 },
    { coords = vector3(2010.6, 3785.3, 32.4), heading = 119.0 },

    { coords = vector3(176.6, 6604.9, 31.8), heading = 180.0 },
    { coords = vector3(168.9, 6604.9, 31.8), heading = 180.0 },
    { coords = vector3(161.1, 6604.9, 31.8), heading = 180.0 },
}

Config.ShowPumpMarkers = false
Config.PumpMarker = {
    type      = 1,
    scale     = vector3(0.4, 0.4, 0.4),
    rgba      = {0, 150, 255, 140},
}

Config.PumpMarkerDrawDistance = 20.0
Config.CacheRefreshNear      = 300
Config.CacheRefreshFar       = 1250
Config.CacheRefreshActive    = 250
Config.HologramRefreshMs     = 100

Config.Keys = {
    Use   = "~INPUT_CONTEXT~",
    Start = "~INPUT_JUMP~",
}
