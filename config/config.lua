Config = Config or {}

Config.Server = {
  Name = "Azure Framework",
  UpdateInterval = 5,
}

Config.FrameworkBridge = {
  Enabled = true,
  InventoryResource = "auto",
  InventoryDebug = false,
}

Config.Admin = {
  RoleId = "1237275526255607858",
  AcePermission = "adminmenu.use",
}

Config.Modules = {
  Economy         = true,
  HUD             = true,
  Parking         = true,
  Departments     = true,
  Paychecks       = true,
  CharacterSystem = true,
  CharacterUI     = true,
  AdminMenu       = true,
  DiscordPresence = true,
  DMV             = true,
  Fuel            = true,
  IDCards         = true,
  Banking         = true,
  Chat            = true,
  Immersion       = true,
SummerActivities  = true,
  Insurance       = true,
  Plates          = true,
  MorsDelivery    = true,
  DailyRewards    = true,
  DeathSystem     = true,
  Housing         = true,
  ImperialCAD     = false,
  DisableWanted   = true,
}

Config.Character = {

  Mode = "ui",

  AppearanceBeforeFirstSpawn = true,

  AutoCreateDiscordCharacter = true,
  DefaultCharacterId = "main",
  DefaultFirstName = "Discord",
  DefaultLastName = "Player",
  DefaultLastNameFrom = "player",
}

Config.IntroCutscene = {
  Enabled = true,

  OnlyFirstJoinPerDiscord = true,
  StateFile = "characterui/cutscene_seen.json",

  RequireNewCharacterInCharacterUi = true,

  AllowInDiscordMode = true,

  ShowSpawnDeathScreenAfter = true,

  Debug = false,
  WeatherType = "EXTRASUNNY",
  RandomPassengersClothes = true,

  UseNativeGtaCutscene = true,
  ScriptedDurationMs = 14000,

  Cutscene = {
    Name = "MP_INTRO_CONCAT",
    MalePlaybackList = 31,
    FemalePlaybackList = 103,
    Flags = 8,
    StartFlags = 4,
    SceneX = -1212.79,
    SceneY = -1673.52,
    SceneZ = 7.0,
    SceneRadius = 1000.0,
    DurationMs = 31520,

    ForceStopAtDurationMs = 0,

    MaxWaitMs = 90000,
    LoadTimeoutMs = 15000,

    StartWaitMs = 12000,
  }
}

Config.Insurance = Config.Insurance or { Enabled = Config.Modules.Insurance ~= false }
Config.Plates = Config.Plates or { Enabled = Config.Modules.Plates ~= false }
Config.MorsDelivery = Config.MorsDelivery or { Enabled = Config.Modules.MorsDelivery ~= false }
Config.DailyRewards = Config.DailyRewards or { Enabled = Config.Modules.DailyRewards ~= false }
Config.Death = Config.Death or { Enabled = Config.Modules.DeathSystem ~= false }
Config.Housing = Config.Housing or { Enabled = Config.Modules.Housing ~= false }

Config.Plates.Enabled = Config.Plates.Enabled ~= false and Config.Modules.Plates ~= false
Config.Plates.UseOxTarget = Config.Plates.UseOxTarget ~= false
Config.Plates.TargetDistance = tonumber(Config.Plates.TargetDistance or 2.0) or 2.0
Config.Plates.BlankPlateText = tostring(Config.Plates.BlankPlateText or 'NO PLATE')
Config.Plates.AllowSwap = Config.Plates.AllowSwap ~= false

Config.MorsDelivery.Enabled = Config.MorsDelivery.Enabled ~= false and Config.Modules.MorsDelivery ~= false
Config.MorsDelivery.Command = tostring(Config.MorsDelivery.Command or 'mors')
Config.MorsDelivery.Command2 = tostring(Config.MorsDelivery.Command2 or 'mors2')

Config.Licenses = {
  UseHuntingLicense = false,
  DefaultHuntingLicense = false,
}

Config.DepartmentsConfig = {
  UseSimpleList = true,
  Command = "jobs",
  ValidateSelection = true,
  RuntimeFile = "config/departments_runtime.json",
  List = {
    { id = "civ",     label = "Civilian",          paycheck = 0,    canUseAOP = false, canUsePrio = false },
    { id = "police",  label = "Police",            paycheck = 1250, canUseAOP = true,  canUsePrio = true  },
    { id = "bcso",    label = "BCSO",              paycheck = 1250, canUseAOP = true,  canUsePrio = true  },
    { id = "state",   label = "State Police",      paycheck = 1350, canUseAOP = true,  canUsePrio = true  },
    { id = "sast",    label = "SAST",              paycheck = 1350, canUseAOP = true,  canUsePrio = true  },
    { id = "ems",     label = "EMS",               paycheck = 1100, canUseAOP = true,  canUsePrio = true  },
    { id = "fire",    label = "Fire",              paycheck = 1100, canUseAOP = true,  canUsePrio = true  },
    { id = "dispatch",label = "Dispatch",          paycheck = 900,  canUseAOP = true,  canUsePrio = true  },
    { id = "dot",     label = "Department of Transportation", paycheck = 850, canUseAOP = false, canUsePrio = false },
    { id = "park",    label = "Park Ranger",       paycheck = 950,  canUseAOP = true,  canUsePrio = false },
    { id = "ranger",  label = "Park Ranger",       paycheck = 950,  canUseAOP = true,  canUsePrio = false },
  }
}

Config.Paychecks = {
  Enabled = true,
  IntervalMinutes = 30,
  UseConfiguredDepartmentsFirst = true,
  UseDatabaseFallback = true,
}

Config.HUD = {
  CombineStatusCard = true,
  PresetFile = "config/hud_preset.json",
  StateFile = "config/hud_state.json",

  Features = {
    compass = true,
    postal  = true,
    aop     = true,
    prio    = true,
  },

  DefaultAOP = "Los Santos",
  DefaultPrio = "No Active Priority",

  DefaultAOPStrategy = "last_or_random",
  DefaultPrioStrategy = "last_or_random",

  AOPChoices = {
    "Los Santos",
    "Blaine County",
  },

  PrioChoices = {
    "No Active Priority",
    "Priority Cooldown",
    "Priority Available",
  },

  CommandJobs = {
    aop  = { "police", "bcso", "state", "sast", "ems", "fire", "dispatch", "park", "ranger", "mod" },
    prio = { "police", "bcso", "state", "sast", "ems", "fire", "dispatch", "mod" },
  },

  Postal = {
    ResourceNames = { "nearest-postal", "nearest_postal", "postals", "new-postals" },
    ExportNames   = { "getPostal", "GetPostal", "getCurrentPostal", "GetCurrentPostal" },
    RefreshMs     = 1000,
  },

  NavRefreshMs = 350,
}

Config.Discord = Config.Discord or {}
Config.DISCORD_APP_ID = Config.DISCORD_APP_ID or "1259656710306660402"

Config.Imperial = {
  resource           = "ImperialCAD",
  use_convars        = true,
  api_convar         = "imperialAPI",
  community_convar   = "imperial_community_id",
  debug_convar       = "imperial_debug",
  auto_save_response = false,
}

Config.EMOJIS = {
  location   = "📍",
  driving    = "🚗",
  walking    = "🚶",
  running    = "🏃",
  idle       = "🧍",
  lights_on  = "🚨",
  lights_off = "🔕",
  zone       = "📌",
  speed      = "💨"
}

Config.SHOW_JOB = false
Config.FRAMEWORK = nil

Config.SERVER_NAME = Config.Server.Name
Config.UPDATE_INTERVAL = tonumber(Config.Server.UpdateInterval) or 5
Config.AdminRoleId = tostring(Config.Admin.RoleId or "")
Config.AdminAcePermission = tostring(Config.Admin.AcePermission or "adminmenu.use")

Config.Parking = Config.Modules.Parking == true
Config.DisableWanted = Config.Modules.DisableWanted ~= false
Config.Departments = Config.Modules.Departments == true
Config.PaycheckIntervalMinutes = tonumber((Config.Paychecks or {}).IntervalMinutes) or 30
Config.UseImperial = Config.Modules.ImperialCAD == true

Config.HUD = Config.HUD or {}
Config.HUD.Features = Config.HUD.Features or {}
Config.HUD.DefaultAOP = tostring(Config.HUD.DefaultAOP or "Los Santos")
Config.HUD.DefaultPrio = tostring(Config.HUD.DefaultPrio or "No Active Priority")
Config.HUD.PresetFile = tostring(Config.HUD.PresetFile or "config/hud_preset.json")
Config.HUD.StateFile = tostring(Config.HUD.StateFile or "config/hud_state.json")

Config.DMV = Config.DMV or { Enabled = Config.Modules.DMV == true }
Config.Fuel = Config.Fuel or { Enabled = Config.Modules.Fuel == true }
Config.IDCard = Config.IDCard or { Enabled = Config.Modules.IDCards == true }
Config.Banking = Config.Banking or { Enabled = Config.Modules.Banking == true }
Config.Chat = Config.Chat or { Enabled = Config.Modules.Chat == true }
Config.Chat.UseOpenControlFallback = Config.Chat.UseOpenControlFallback == true

Config.Immersion = Config.Immersion or {
  Enabled = Config.Modules.Immersion == true,
  Debug = false,
  UseOxTarget = true,
  EnablePropInteractions = true,
  EnableNPCSocial = true,
  ManualReports = true,
  TargetDistance = 1.9,
  NPCDistance = 2.2,
  ActionDistance = 3.5,
  SaveIntervalSeconds = 45,
  ActionCooldownMs = 3500,
  SearchCooldownSeconds = 75,
  SocialCooldownSeconds = 25,
  MaxNoteLength = 180,
  MaxReasonLength = 240,
  AutoReport = {
    Enabled = true,
    SuspicionThreshold = 36,
    HarassmentThreshold = 55,
    WindowSeconds = 600,
  },
  Persistence = {
    PropsFile = 'modules/immersion/data/props_state.json',
    RelationshipsFile = 'modules/immersion/data/relationships.json',
    ComplaintsFile = 'modules/immersion/data/complaints.json',
  },
  LawJobs = {
    police = true,
    bcso = true,
    state = true,
    sast = true,
    park = true,
    ranger = true,
  }
}

Config.Immersion.Summer = Config.Immersion.Summer or {
  Enabled = Config.Modules.SummerActivities == true,
  Beach = true,
  Water = true,
  Games = true,
  Picnic = true,
  Camp = true,
  Boardwalk = true,
  Pool = true,
  Vendors = true,
  Backyard = true,
  Seating = true,
  Playground = true,
  Cleanup = true,
  RelationshipFlavor = true,
  RentalStockDefault = 3,
  CoolerStockDefault = 4,
  GrillFuelDefault = 3,
  BonfireFuelDefault = 2,
  FloatStockDefault = 3,
  SnackStockDefault = 5,
  FoodStockDefault = 5,
}
