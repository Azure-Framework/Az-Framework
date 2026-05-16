Config = Config or {}

local modules = Config.Modules or {}
local charCfg = Config.Character or {}

Config.Debug = Config.Debug == true
Config.StartingCash = tonumber(Config.StartingCash) or 500000
Config.AdminRoleId = tostring(Config.AdminRoleId or (((Config.Admin or {}).RoleId) or ""))
Config.AdminAcePermission = tostring(Config.AdminAcePermission or (((Config.Admin or {}).AcePermission) or "adminmenu.use"))
Config.Parking = modules.Parking ~= false
Config.Departments = modules.Departments ~= false
Config.PaycheckIntervalMinutes = tonumber(Config.PaycheckIntervalMinutes or ((Config.Paychecks or {}).IntervalMinutes) or 30)
Config.UIKeybind = tostring(Config.UIKeybind or "F3")
Config.UseAppearance = (Config.UseAppearance ~= false)
Config.DISCORD_APP_ID = tostring(Config.DISCORD_APP_ID or "1259656710306660402")
Config.UPDATE_INTERVAL = tonumber(Config.UPDATE_INTERVAL or ((Config.Server or {}).UpdateInterval) or 5)
Config.SERVER_NAME = tostring(Config.SERVER_NAME or ((Config.Server or {}).Name) or "Azure Framework")
Config.EnableLastLocation = (Config.EnableLastLocation ~= false)
Config.LastLocationUpdateIntervalMs = tonumber(Config.LastLocationUpdateIntervalMs) or 10000
Config.EnableFiveAppearance = (Config.EnableFiveAppearance ~= false)
Config.MugshotEnabled = (Config.MugshotEnabled ~= false)
Config.MugshotRefreshMs = tonumber(Config.MugshotRefreshMs) or 700
Config.EnableOpenCommand = (Config.EnableOpenCommand ~= false)
Config.OpenCommand = tostring(Config.OpenCommand or "characters")
Config.EnableSpawnMenuCommand = (Config.EnableSpawnMenuCommand ~= false)
Config.SpawnMenuCommand = tostring(Config.SpawnMenuCommand or "spawnmenu")
Config.SpawnMenuAdminOnly = (Config.SpawnMenuAdminOnly ~= false)
Config.SpawnFile = tostring(Config.SpawnFile or "characterui/spawns.json")
Config.MapBounds = Config.MapBounds or { minX = -3000.0, maxX = 3000.0, minY = -6300.0, maxY = 7000.0 }
Config.RequireAzAdminForEdit = (Config.RequireAzAdminForEdit ~= false)
Config.Character = Config.Character or {}
Config.Character.Mode = tostring(Config.Character.Mode or charCfg.Mode or "ui")
Config.Character.AppearanceBeforeFirstSpawn = (Config.Character.AppearanceBeforeFirstSpawn ~= false)

Config.Preview = Config.Preview or {
  Enabled = true,
  Scene = vector4(402.92, -996.82, -99.00, 180.0),
  PedOffset = vector3(0.0, 0.0, 0.3),
  CamFov = 50.0,
  CamInterpMs = 250,
  Camera = {
    Enabled = true,
    Forward = 2.80,
    Right = -0.15,
    Up = 0.00,
    TargetUp = -0.35
  },
  PrefetchAppearances = true,
  PrefetchLimit = 16,
  FetchAttempts = 10,
  FetchWaitMs = 250,
  NegativeCacheMs = 4000,
  Mugshot = {
    Enabled = true,
    DeptText = tostring(Config.SERVER_NAME or "Azure Framework"),
    BoardProp = "prop_police_id_board",
    TextProp = "prop_police_id_text",
    HandBone = 28422
  }
}
Config.Preview.Camera = Config.Preview.Camera or {
  Enabled = true,
  Forward = 2.80,
  Right = -0.15,
  Up = 0.00,
  TargetUp = -0.35
}
Config.Preview.Mugshot = Config.Preview.Mugshot or {
  Enabled = true,
  DeptText = tostring(Config.SERVER_NAME or "Azure Framework"),
  BoardProp = "prop_police_id_board",
  TextProp = "prop_police_id_text",
  HandBone = 28422
}

Config.SpawnDeathScreen = Config.SpawnDeathScreen or {
  Enabled = true,
  DurationMs = 4200,
  ShowShard = true,
  Title = tostring(Config.SERVER_NAME or "Azure Framework"),
  Subtitle = "~r~Welcome to the server.~s~",
  ShardBgColor = 2,
  ScreenEffect = "DeathFailOut",
  UseTimecycle = true,
  Timecycle = "REDMIST_blend",
  TimecycleStrength = 0.70,
  ExtraTimecycle = "fp_vig_red",
  ExtraTimecycleStrength = 1.0,
  MotionBlur = true,
  HideRadarDuring = true,
  PlaySound = true,
  SoundName = "Bed",
  SoundSet = "WastedSounds"
}

Config.Housing = Config.Housing or {
  Enabled = true,
  Custom = {
    Resource = "az_housing",
    Export = "GetPlayerHouses"
  },
  SpawnName = "My House",
  SpawnDesc = "Spawn at your house"
}

Config.UseFirstJoin = (Config.UseFirstJoin ~= false)
Config.FirstJoin = Config.FirstJoin or {
  Welcome = {
    PersistOncePerPlayer = true,
    ShowEverySession = true,
    Header = "Welcome to the Server",
    Content = [[
**Quick Start Guide**

- Use **/firstcar** to claim your first vehicle.
- **You only get 1 free car every 24 hours.**
- To save your vehicle's parking spot:
  **Press SHIFT + F** while parked.

If your car isn't where you left it, make sure you parked it properly.
Enjoy your stay!
]],
    Centered = true,
    Size = "md"
  },
  FirstCar = {
    CooldownSeconds = 24 * 60 * 60,
    SedanModels = { "asea", "asterope", "emperor", "fugitive", "glendale", "ingot", "intruder", "premier", "primo", "regina" },
    WarpIntoVehicle = true,
    ShowCooldownChatMessage = true
  }
}

Config.EMOJIS = Config.EMOJIS or {
  location = "📍",
  driving = "🚗",
  walking = "🚶",
  running = "🏃",
  idle = "🧍",
  lights_on = "🚨",
  lights_off = "🔕",
  zone = "📌",
  speed = "💨"
}

Config.AutoOpenFree = (Config.AutoOpenFree ~= false)
Config.EnableCustomizationCommand = (Config.EnableCustomizationCommand ~= false)
Config.CustomizationCommand = tostring(Config.CustomizationCommand or "customize")
Config.InteractDistance = tonumber(Config.InteractDistance) or 2.0
Config.Key = tonumber(Config.Key) or 38
Config.MarkerDistance = tonumber(Config.MarkerDistance) or 15.0
Config.MarkerType = tonumber(Config.MarkerType) or 1
Config.MarkerScale = Config.MarkerScale or vector3(1.0, 1.0, 1.0)
Config.MarkerColor = Config.MarkerColor or { r = 255, g = 92, b = 31, a = 140 }
Config.TextZOffset = tonumber(Config.TextZOffset) or 1.0
Config.Price = tonumber(Config.Price) or 0
Config.Blips = (Config.Blips ~= false)
Config.Shops = Config.Shops or {}
