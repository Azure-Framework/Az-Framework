Config = {}
-- ---------------------
-- Basic server settings
-- ---------------------
Config.SERVER_NAME = "YOUR_SERVER_NAME"  -- shown in presence text
Config.UPDATE_INTERVAL = 5                       -- presence update interval (seconds)

-- Emojis used in presence / messages. Change to your taste.
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

-- ---------------------
-- Admin / permissioning
-- ---------------------
-- Discord role ID that grants admin access to the resource's admin commands.
-- Keep it as a string (Discord snowflake).
Config.AdminRoleId = "YOUR_DISCORD_ADMIN_ROLE"

-- ---------------------
-- Feature toggles
-- ---------------------
-- Parking: Shift + F park/unpark vehicles (when implemented)
Config.Parking = true

-- Departments & paychecks (paychecks only distributed if enabled)
Config.Departments = true

-- Paycheck distribution interval (minutes). 60 = 1 hour.
Config.PaycheckIntervalMinutes = 5

-- ---------------------
-- Presence / job settings
-- ---------------------
-- Show job framework presence (ESX or QBCore). If false, don't attempt to fetch job.
Config.SHOW_JOB = false
-- If using ESX/QB set this to "esx" or "qb" (string). Leave nil if not using either.
Config.FRAMEWORK = nil -- "esx" / "qb" / nil

-- ---------------------
-- Discord / OAuth settings
-- ---------------------
-- Your Discord App ID (string). Put your app id here if using Discord OAuth/presence.
Config.DISCORD_APP_ID = "YOUR_DISCORD_APP_ID"


-- ---------------------
-- ImperialCAD integration
-- ---------------------
-- Set to true to automatically create ImperialCAD characters when players register characters.
Config.UseImperial = false

Config.Imperial = {
  resource           = "ImperialCAD",           -- resource name that exposes ImperialCAD exports
  use_convars        = true,                    -- read API key / community id from convars if true
  api_convar         = "imperialAPI",           -- convar that stores API secret (for server -> Imperial POSTs)
  community_convar   = "imperial_community_id", -- convar for community id
  debug_convar       = "imperial_debug",        -- optional convar to enable Imperial debug prints
  auto_save_response = false                    -- if true will attempt to save SSN/DLN returned (DB changes required)
}