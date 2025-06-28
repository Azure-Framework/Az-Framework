Config = {}

Config.AdminRoleId = "YOUR_DISCORD_ADMIN_ROLE_ID"

-- Set to true to enable park-anywhere functionality (Shift + F to park/unpark vehicles)
Config.Parking = true

-- Set to true to enable departments and department paychecks
Config.Departments = true

-- How often to run distributePaychecks (in milliseconds)
Config.paycheckInterval = 3600000  -- 1 hour

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
--┃       Discord Configuration Guide    ┃
--┃  (Bot token & webhook live in       ┃
--┃        server.lua – edit there)     ┃
--┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
Config.Discord = {
    -- Your Discord server (guild) ID
    GuildId     = "YOUR_DISCORD_ADMIN_ROLE_ID",

    -- BotToken & WebhookURL: see top of server.lua to configure
    --   Config.Discord.BotToken   = "YOUR_BOT_TOKEN"
    --   Config.Discord.WebhookURL = "YOUR_DISCORD_WEBHOOK_URL"
}