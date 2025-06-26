Config = {}

Config.AdminRoleId = "YOUR_DISCORD_ADMIN_ROLE"

-- Set to true to enable park-anywhere functionality (Shift + F to park/unpark vehicles)
Config.Parking = true

-- Set to true to enable departments and department paychecks
Config.Departments = true

-- How often to run distributePaychecks (in milliseconds)
Config.paycheckInterval = 3600000  -- 1 hour

-- Discord bot configuration
Config.Discord = {
    -- The ID of the guild (server) you want to query
    GuildId = "YOUR_DISCORD_GUILD_ID",
    
    -- NOTE: Bot token and webhook URL now live in server.lua
    -- Edit your BotToken there:
    --   BotToken = "YOUR_BOT_TOKEN"
    --
    -- And your WebhookURL there:
    --   WebhookURL = "YOUR_DISCORD_WEBHOOK_URL"
}
