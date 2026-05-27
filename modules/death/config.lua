Config = Config or {}
Config.Death = Config.Death or {}
local Config = Config.Death
Config.Enabled = Config.Enabled ~= false

Config.Debug = Config.Debug == true

Config.EnableNui = (Config.EnableNui ~= false)

Config.ReviveTime = Config.ReviveTime or 60
Config.BleedoutTime = Config.BleedoutTime or 300
Config.RespawnDelay = Config.RespawnDelay or 10

Config.AllowEarlyRespawn = (Config.AllowEarlyRespawn ~= false)
Config.EarlyRespawnKey = Config.EarlyRespawnKey or 38
Config.EarlyRespawnHoldMs = Config.EarlyRespawnHoldMs or 2500

Config.RespawnLocations = Config.RespawnLocations or {
  {
    label = "Pillbox Medical",
    coords = vector3(306.39, -1433.61, 29.97),
    heading = 45.0
  }
}

Config.EMSJobs = Config.EMSJobs or { 'ambulance', 'ems', 'safd' }
Config.ReviveItem = Config.ReviveItem or 'medkit'
Config.BandageItem = Config.BandageItem or 'bandage'

Config.Framework = Config.Framework or 'azfw'

Config.Debug = (Config.Debug == true)
Config.EnableNui = true

Config.CommandInjuries = "injuries"
Config.CommandBackup   = "azinjuries"
Config.CommandClear    = "injuriesclear"

Config.RebindScheduleMs = { 0, 250, 1000, 3000, 8000, 15000 }
Config.RebindEveryMs = 30000

Config.MaxWoundsPerRegion = 12
Config.MaxBleed = 8.0

Config.BleedTickMs = 1000
Config.BleedHpPerSecondMin = 0
Config.BleedHpPerSecondMax = 6

Config.Thresholds = {
  Limp         = 25,
  NoSprint     = 55,
  NoJump       = 70,

  AimPenalty   = 40,
  NoAim        = 80,

  HeadBlur     = 30,
  HeadBlackout = 75,

  TorsoSlow    = 40,
  TorsoNoSprint= 70,
}

Config.UseInjuredClipset = true
Config.InjuredClipset = "move_m@injured"

Config.Blackout = {
  Enabled = true,
  CooldownMs = 12000,
  FadeOutMs = 400,
  RagMs = 1600,
  FadeInMs = 600,
}

Config.VehicleImpact = {
  Enabled = true,

  HealthDropPollMs = 150,
  MinDeltaToConsider = 2,
  CooldownMs = 750,
}


Config.TeleportGuard = Config.TeleportGuard or {
  Enabled = true,
  CheckMs = 250,
  Distance = 45.0,
  VerticalDistance = 20.0,
  SuppressMs = 9000,
  RestoreHealthDuringSuppression = true,
}

Config.Stumble = {
  Enabled = true,
  CooldownMs = 8000,

  BaseChance = 0.02,
  MaxChance  = 0.12,
}

Config.MedDept = Config.MedDept or Config.EMSJobs or { 'ambulance', 'ems', 'safd' }

Config.Downed = Config.Downed or {
  Enabled = true,
  HealthOnDown = 110,
  ReviveHealth = 150,
  NotifyEMS = true,
  DisableFriendlyFire = true,
  DisableControls = true,
  DisableVehicleExit = true,
  PlayLoopAnim = true,
  AnimDict = 'dead',
  AnimName = 'dead_a',
}

Config.Hospital = Config.Hospital or {
  CheckInCost = 500,
  VisitHealCost = 250,
  TreatmentSeconds = 3,
  RespawnSeconds = 3,
  UseBankFirst = true,
}

Config.RespawnLocations = Config.RespawnLocations or {
  {
    label = 'Pillbox Medical',
    coords = vector3(329.28, -575.33, 43.28),
    heading = 160.0
  },
  {
    label = 'Sandy Shores Medical',
    coords = vector3(1841.81, 3668.18, 34.28),
    heading = 30.0
  },
  {
    label = 'Paleto Medical',
    coords = vector3(-252.52, 6334.64, 32.43),
    heading = 225.0
  }
}

Config.DropWeaponOnDowned = (Config.DropWeaponOnDowned ~= false)
Config.SearchDownedPlayers = (Config.SearchDownedPlayers ~= false)
Config.SearchDistance = tonumber(Config.SearchDistance or 2.0) or 2.0

Config.Drag = Config.Drag or {
  Enabled = true,
  Distance = 2.0,
  DropKey = 73,
  AllowPlayerDrag = true,
  AllowNpcDrag = true,
}
