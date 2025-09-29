Config = {}

Config.AdminRoleId = "YOUR_DISCORD_ADMIN_ROLE"

-- Set to true to enable park-anywhere functionality (Shift + F to park/unpark vehicles)
Config.Parking = true

-- Set to true to enable departments and department paychecks
Config.Departments = true

-- How often to run distributePaychecks (in minutes)
Config.PaycheckIntervalMinutes  = 1  -- 60 = 1 hour.

-- Your Discord App ID (string). Put your app id here.
Config.DISCORD_APP_ID = "YOUR_DISCORD_BOT_APPID"

-- Update interval in seconds
Config.UPDATE_INTERVAL = 5

-- Server name shown in presence text
Config.SERVER_NAME = "Azure Framework Showcase"

-- Emoji set (customize if you like)
Config.EMOJIS = {
  location = "📍",
  driving  = "🚗",
  walking  = "🚶",
  running  = "🏃",
  idle     = "🧍",
  lights_on = "🚨",
  lights_off = "🔕",
  zone     = "📌",
  speed    = "💨"
}

-- Show job (ESX/QBCore) in presence? false => don't attempt to fetch job
Config.SHOW_JOB = false
-- If you use ESX/QBCore, set framework: "esx" or "qb" or leave nil
Config.FRAMEWORK = nil

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃       Discord Configuration Guide    ┃
-- ┃  (Bot token & webhook link & Guild ID┃
-- ┃        inside your server.cfg )      ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛


Config.UseImperial = false -- set to true to enable ImperialCAD integration

Config.Imperial = {
  resource = "ImperialCAD",        -- resource name that exposes the ImperialCAD exports
  use_convars = true,              -- read API key / community id from convars if true
  api_convar = "imperialAPI",      -- convar that holds the API key (POST header)
  community_convar = "imperial_community_id", -- convar for community id
  debug_convar = "imperial_debug", -- optional convar to enable debug prints for Imperial calls
  auto_save_response = false       -- if true, will attempt to save returned SSN/DLN into DB (you must add DB columns)
}