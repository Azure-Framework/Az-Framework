Config = Config or {}
Config.DMV = Config.DMV or {}
local Config = Config.DMV
Config.Enabled = Config.Enabled ~= false

Config.RequireWrittenTest = true
Config.RequireDrivingTest = true

Config.WrittenPassScore = nil
Config.WrittenPassPercentage = 0.9

Config.PointsToFail = 5
Config.StopSpeedLimitMPH = 5.0
Config.DrivingSpeedLimitMPH = 50
Config.SpeedViolationPoints = 1
Config.SpeedViolationCooldown = 5
Config.CheckpointRadius = 7.5
Config.StopCheckTimeSeconds = 4
Config.Debug = false

Config.AllowCommandStart = true

Config.UseLibInputDialog = true

Config.DMVLocations = {
  {
    pos = vector3(240.706, -1379.409, 33.742),
    heading = 142.789,
    pedModel = "s_m_m_autoshop_02",
    blip = { sprite = 850, color = 5, name = "DMV" }
  }
}

Config.DrivingStart = {
    pos = vector3(-512.690, -262.885, 35.437),
    heading = 114.216,
    vehicleModel = "blista",
    spawnVehicle = true
}

Config.DrivingFinish = vector3(-499.150, -256.917, 36.074)

Config.DrivingRoute = {
  { pos = vector3(-550.505, -283.883, 35.437), mustStop = true },
  { pos = vector3(-613.745, -195.329, 37.593), mustStop = true  },
  { pos = vector3(-525.663, -143.424, 38.565), mustStop = true },
  { pos = vector3(-464.044, -231.067, 36.074), mustStop = true  },
}

Config.Questions = {
    {
        question = "What should you do if your car's engine overheats?",
        options = {
            { value = "turn_off", label = "Turn off the engine and wait for it to cool down" },
            { value = "cold_water", label = "Pour cold water on the engine" },
            { value = "keep_driving", label = "Keep driving until you reach a mechanic" }
        },
        correctOption = "turn_off"
    },
    {
        question = "When approaching a pedestrian crossing, what should you do?",
        options = {
            { value = "slow_down", label = "Slow down and be prepared to stop" },
            { value = "speed_up", label = "Speed up to pass quickly" },
            { value = "ignore_pedestrians", label = "Ignore pedestrians and continue driving" }
        },
        correctOption = "slow_down"
    },
    {
        question = "What does a yellow traffic light mean?",
        options = {
            { value = "slow_down", label = "Slow down and prepare to stop" },
            { value = "proceed_with_caution", label = "Proceed with caution" },
            { value = "stop", label = "Stop immediately" }
        },
        correctOption = "proceed_with_caution"
    },
    {
        question = "What does a red traffic light mean?",
        options = {
            { value = "stop", label = "Stop" },
            { value = "go", label = "Go" },
            { value = "yield", label = "Yield" }
        },
        correctOption = "stop"
    },

}
