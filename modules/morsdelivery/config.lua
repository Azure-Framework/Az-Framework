Config = Config or {}
Config.MorsDelivery = Config.MorsDelivery or {}
local Config = Config.MorsDelivery
Config.Enabled = Config.Enabled ~= false
Config.DB_TABLE = Config.DB_TABLE or 'user_vehicles'
Config.DB_OWNER_COLUMN = Config.DB_OWNER_COLUMN or 'discordid'
Config.IdentifierType = Config.IdentifierType or 'discord'
Config.MySQL = Config.MySQL or 'oxmysql'
Config.Command = Config.Command or 'mors'
Config.Command2 = Config.Command2 or 'mors2'
Config.CooldownSeconds = tonumber(Config.CooldownSeconds or 60) or 60
Config.CallSeconds = tonumber(Config.CallSeconds or 9) or 9
Config.DriverPedModel = Config.DriverPedModel or 's_m_y_valet_01'
Config.DriveSpeed = tonumber(Config.DriveSpeed or 20.0) or 20.0
Config.DrivingStyle = tonumber(Config.DrivingStyle or 786603) or 786603
Config.StopDistance = tonumber(Config.StopDistance or 8.0) or 8.0
Config.SpawnDistanceMin = tonumber(Config.SpawnDistanceMin or 280.0) or 280.0
Config.SpawnDistanceMax = tonumber(Config.SpawnDistanceMax or 520.0) or 520.0

Config.Theme = Config.Theme or { accent = '#2fb7ff' }
Config.OperatorVoice = Config.OperatorVoice or {
  enable = true,
  voiceName = 'mp_f_stripperlite',
  speechName = 'GENERIC_HI',
  speechParam = 'SPEECH_PARAMS_FORCE_NORMAL',
  delayMs = 2300,
}
Config.RoadSearchAttempts = tonumber(Config.RoadSearchAttempts or 40) or 40
Config.RoadNodeType = tonumber(Config.RoadNodeType or 1) or 1
Config.RoadNodeRadius = tonumber(Config.RoadNodeRadius or 3.0) or 3.0
Config.StuckSeconds = tonumber(Config.StuckSeconds or 8) or 8
Config.StuckTeleportAfter = tonumber(Config.StuckTeleportAfter or 3) or 3
Config.TeleportDistMin = tonumber(Config.TeleportDistMin or 120.0) or 120.0
Config.TeleportDistMax = tonumber(Config.TeleportDistMax or 180.0) or 180.0
Config.PhoneCallAnim = Config.PhoneCallAnim or {
  enable = true,
  dict = 'cellphone@',
  anim = 'cellphone_call_listen_base',
  flags = 49,
  prop = 'prop_npc_phone_02',
  bone = 28422,
  pos = { x = 0.02, y = 0.01, z = 0.02 },
  rot = { x = 0.0, y = 0.0, z = 0.0 },
}
