local debug       = Config.Debug or false
local debugPrint  -- forward declaration

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃        Discord Configuration       ┃
-- ┃    (Edit these values below)       ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

-- Your bot’s token (keep this secret!)
Config.Discord.BotToken   = "YOUR_BOT_TOKEN"

-- Webhook URL for server logging
Config.Discord.WebhookURL = "YOUR_DISCORD_WEBHOOK_URL"




local activeCharacters = {}


debugPrint = function(msg)
  if debug then
    print(("[az-fw-money] %s"):format(msg))
  end
end

-- Table schemas, including new user_characters, per-character money, and schema migration
local tableSchemas = {
    [[
    CREATE TABLE IF NOT EXISTS `econ_accounts` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `discordid` varchar(255) NOT NULL,
      `type` enum('checking','savings') NOT NULL DEFAULT 'checking',
      `balance` decimal(12,2) NOT NULL DEFAULT 0.00,
      PRIMARY KEY (`id`),
      KEY `discordid` (`discordid`)
    ) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `econ_admins` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `username` varchar(50) NOT NULL,
      `password` varchar(255) NOT NULL,
      PRIMARY KEY (`id`),
      UNIQUE KEY `username` (`username`)
    ) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `econ_cards` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `discordid` varchar(255) NOT NULL,
      `card_number` varchar(16) NOT NULL,
      `exp_month` tinyint(4) NOT NULL,
      `exp_year` smallint(6) NOT NULL,
      `status` enum('active','blocked') NOT NULL DEFAULT 'active',
      PRIMARY KEY (`id`),
      KEY `discordid` (`discordid`)
    ) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `econ_departments` (
      `discordid` varchar(255) NOT NULL,
      `department` varchar(100) NOT NULL,
      `paycheck` int(11) NOT NULL DEFAULT 0,
      PRIMARY KEY (`discordid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `econ_payments` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `discordid` varchar(255) NOT NULL,
      `payee` varchar(255) NOT NULL,
      `amount` decimal(12,2) NOT NULL,
      `schedule_date` date NOT NULL,
      PRIMARY KEY (`id`),
      KEY `discordid` (`discordid`)
    ) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `econ_profile` (
      `discordid` varchar(255) NOT NULL,
      `user_id` int(11) NOT NULL,
      `name` varchar(100) NOT NULL,
      PRIMARY KEY (`discordid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    -- NEW: characters table
    [[
    CREATE TABLE IF NOT EXISTS `user_characters` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `discordid` varchar(255) NOT NULL,
      `charid` varchar(100) NOT NULL,
      `name` varchar(100) NOT NULL,
      PRIMARY KEY (`id`),
      UNIQUE KEY `discord_char` (`discordid`,`charid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    -- UPDATED: per-character money table
    [[
    CREATE TABLE IF NOT EXISTS `econ_user_money` (
      `discordid` varchar(255) NOT NULL,
      `charid` varchar(100) NOT NULL,
      `firstname` varchar(100) NOT NULL DEFAULT '',
      `lastname` varchar(100) NOT NULL DEFAULT '',
      `profile_picture` varchar(255) DEFAULT NULL,
      `cash` int(11) NOT NULL DEFAULT 0,
      `bank` int(11) NOT NULL DEFAULT 0,
      `last_daily` bigint(20) NOT NULL DEFAULT 0,
      `card_number` varchar(16) DEFAULT NULL,
      `exp_month` tinyint(4) DEFAULT NULL,
      `exp_year` smallint(6) DEFAULT NULL,
      `card_status` enum('active','blocked') NOT NULL DEFAULT 'active',
      PRIMARY KEY (`discordid`,`charid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    -- MIGRATION: ensure existing table has new columns
    [[
    ALTER TABLE `econ_user_money`
      ADD COLUMN IF NOT EXISTS `firstname` varchar(100) NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS `lastname` varchar(100) NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS `profile_picture` varchar(255) DEFAULT NULL,
      ADD COLUMN IF NOT EXISTS `card_number` varchar(16) DEFAULT NULL,
      ADD COLUMN IF NOT EXISTS `exp_month` tinyint(4) DEFAULT NULL,
      ADD COLUMN IF NOT EXISTS `exp_year` smallint(6) DEFAULT NULL,
      ADD COLUMN IF NOT EXISTS `card_status` enum('active','blocked') NOT NULL DEFAULT 'active';
    ]],
    -- LEVELS table
    [[
    CREATE TABLE IF NOT EXISTS `user_levels` (
      `identifier` varchar(100) NOT NULL,
      `rp_total` bigint(20) NOT NULL DEFAULT 0,
      `rp_stamina` bigint(20) NOT NULL DEFAULT 0,
      `rp_strength` bigint(20) NOT NULL DEFAULT 0,
      `rp_driving` bigint(20) NOT NULL DEFAULT 0,
      PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    ]],
    -- VEHICLES table
    [[
    CREATE TABLE IF NOT EXISTS `user_vehicles` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `discordid` varchar(255) NOT NULL,
      `plate` varchar(20) NOT NULL,
      `model` varchar(50) NOT NULL,
      `x` double NOT NULL,
      `y` double NOT NULL,
      `z` double NOT NULL,
      `h` double NOT NULL,
      `color1` int(11) NOT NULL,
      `color2` int(11) NOT NULL,
      `pearlescent` int(11) NOT NULL,
      `wheelColor` int(11) NOT NULL,
      `wheelType` int(11) NOT NULL,
      `windowTint` int(11) NOT NULL,
      `mods` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`mods`)),
      `extras` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`extras`)),
      PRIMARY KEY (`id`),
      UNIQUE KEY `uq_vehicle` (`discordid`,`plate`),
      KEY `idx_discord` (`discordid`)
    ) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4;
    ]]
}



-- helper to run all schemas
local function ensureSchemas(cb)
    local pending = #tableSchemas
    for _, sql in ipairs(tableSchemas) do
        MySQL.Async.execute(sql, {}, function()
            pending = pending - 1
            if pending == 0 and cb then cb() end
        end)
    end
end

-- Extract Discord ID (or return empty string)
local function getDiscordID(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if id:sub(1,8) == "discord:" then
            return id:sub(9)
        end
    end
    return ""
end

-- Fetch Discord roles for a member
local function getDiscordRoleList(playerSrc, cb)
    assert(type(cb) == "function", "getDiscordRoleList requires a callback")

    local discordID = getDiscordID(playerSrc)
    if discordID == "" then
        debugPrint(("Player %d has no Discord ID"):format(playerSrc))
        return cb("no_discord_id", nil)
    end

    local guildId  = Config.Discord.GuildId
    local botToken = Config.Discord.BotToken

    if not guildId or not botToken then
        debugPrint("Missing GuildId or BotToken in config")
        return cb("config_error", nil)
    end

    local url = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(guildId, discordID)
    debugPrint("Fetching roles via: " .. url)

    PerformHttpRequest(url, function(statusCode, body)
        debugPrint(("Discord API HTTP %d"):format(statusCode))
        if statusCode ~= 200 then
            return cb("http_"..statusCode, nil)
        end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data.roles) ~= "table" then
            debugPrint("Invalid roles payload")
            return cb("no_roles", nil)
        end

        cb(nil, data.roles)
    end, 'GET', '', {
        ["Authorization"] = "Bot " .. botToken,
        ["Content-Type"]  = "application/json"
    })
end

-- Check if player has the admin role
local function isAdmin(playerSrc, cb)
    getDiscordRoleList(playerSrc, function(err, roles)
        if err then
            debugPrint(("isAdmin error for %d: %s"):format(playerSrc, err))
            return cb(false)
        end
        for _, role in ipairs(roles) do
            if role == Config.AdminRoleId then
                return cb(true)
            end
        end
        cb(false)
    end)
end

-- Helper to send a message to Discord via webhook
local function sendWebhookLog(message)
    if not Config.Discord.WebhookURL or Config.Discord.WebhookURL == "" then
        debugPrint("Webhook URL not configured; skipping Discord log.")
        return
    end

    local payload = {
        username = "Server Logger",
        content  = message,
    }

    PerformHttpRequest(Config.Discord.WebhookURL, function(statusCode)
        if statusCode ~= 204 and statusCode ~= 200 then
            debugPrint("Discord webhook error: " .. tostring(statusCode))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

-- Log an admin command attempt
local function logAdminCommand(commandName, source, args, success)
    local playerName = GetPlayerName(source) or "Unknown"
    local statusIcon = success and "✅ Allowed" or "❌ Denied"
    local argsStr    = args and table.concat(args, " ") or ""
    local msg = string.format(
        "**Admin Command:** `%s`\n**Player:** %s (ID %d)\n**Status:** %s\n**Args:** %s",
        commandName, playerName, source, statusIcon, argsStr
    )
    sendWebhookLog(msg)
end

-- Log large transactions (>= 1,000,000)
local function logLargeTransaction(txType, source, amount, reason)
    local playerName = GetPlayerName(source) or "Unknown"
    local msg = string.format(
        ":moneybag: **Large Transaction** **%s**\n**Player:** %s (ID %d)\n**Amount:** $%s\n**Reason:** %s",
        txType, playerName, source, amount, reason
    )
    sendWebhookLog(msg)
end


-- -- Character selection: switch active character and update HUD
-- RegisterNetEvent('az-fw-money:selectCharacter')
-- AddEventHandler('az-fw-money:selectCharacter', function(charID)
--     local src = source
--     activeCharacters[src] = charID

--     local discordID = getDiscordID(src)
--     if discordID == "" then return end

--     -- reload money for the selected character
--     GetMoney(discordID, charID, function(data)
--         TriggerClientEvent("updateCashHUD", src, data.cash, data.bank)
--     end)
-- end)

-- Fetch money row for a specific discordID + charID, creating if missing
function GetMoney(discordID, charID, callback)
    MySQL.Async.fetchAll([[
      SELECT cash, bank, last_daily
      FROM econ_user_money
      WHERE discordid = @discordid AND charid = @charid
    ]], {
      ['@discordid'] = discordID,
      ['@charid']    = charID
    }, function(result)
        if not result[1] then
            local data = { cash = 0, bank = 0, last_daily = 0 }
            MySQL.Async.execute([[
              INSERT INTO econ_user_money (discordid, charid, cash, bank, last_daily)
              VALUES (@discordid, @charid, 0, 0, 0)
            ]], {
              ['@discordid'] = discordID,
              ['@charid']    = charID
            })
            callback(data)
        else
            callback(result[1])
        end
    end)
end

-- Update money row for discordID + charID
function UpdateMoney(discordID, charID, data, cb)
    MySQL.Async.execute([[
      UPDATE econ_user_money
      SET cash = @cash,
          bank = @bank,
          last_daily = @last_daily
      WHERE discordid = @discordid AND charid = @charid
    ]], {
      ['@cash']       = data.cash,
      ['@bank']       = data.bank,
      ['@last_daily'] = data.last_daily,
      ['@discordid']  = discordID,
      ['@charid']     = charID
    }, cb)
end

-- Send current cash/bank to client for active character
local function sendMoneyToClient(playerId)
    local discordID = getDiscordID(playerId)
    local charID    = activeCharacters[playerId]
    if discordID == "" or not charID then return end

    MySQL.Async.fetchAll([[
      SELECT cash, bank
      FROM econ_user_money
      WHERE discordid = @discordid AND charid = @charid
    ]], {
      ['@discordid'] = discordID,
      ['@charid']    = charID
    }, function(rows)
        if rows[1] then
            TriggerClientEvent('updateCashHUD', playerId, rows[1].cash, rows[1].bank)
        end
    end)
end

-- Utility: wrap money operations to automatically use active character
local function withMoney(src, fn)
    local discordID = getDiscordID(src)
    local charID    = activeCharacters[src]
    if discordID == "" or not charID then
        return TriggerClientEvent("chat:addMessage", src, { args = {"^1SYSTEM","No character selected."} })
    end
    GetMoney(discordID, charID, function(data)
        fn(discordID, charID, data)
    end)
end

-- Core economy functions now per-character
function addMoney(source, amount)
    withMoney(source, function(dID, cID, data)
        data.cash = data.cash + amount
        UpdateMoney(dID, cID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then logLargeTransaction("addMoney", source, amount, "addMoney() export") end
        end)
    end)
end

function deductMoney(source, amount)
    withMoney(source, function(dID, cID, data)
        data.cash = math.max(0, data.cash - amount)
        UpdateMoney(dID, cID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then logLargeTransaction("deductMoney", source, amount, "deductMoney() export") end
        end)
    end)
end

function depositMoney(source, amount)
    withMoney(source, function(dID, cID, data)
        if data.cash < amount then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Not enough cash to deposit."} })
        end
        data.cash = data.cash - amount
        data.bank = data.bank + amount
        UpdateMoney(dID, cID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then logLargeTransaction("depositMoney", source, amount, "depositMoney() export") end
        end)
    end)
end

function withdrawMoney(source, amount)
    withMoney(source, function(dID, cID, data)
        if data.bank < amount then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Not enough bank funds to withdraw."} })
        end
        data.bank = data.bank - amount
        data.cash = data.cash + amount
        UpdateMoney(dID, cID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then logLargeTransaction("withdrawMoney", source, amount, "withdrawMoney() export") end
        end)
    end)
end

function transferMoney(source, target, amount)
    local senderID = getDiscordID(source)
    local senderChar = activeCharacters[source]
    local targetID = getDiscordID(target)
    local targetChar = activeCharacters[target]
    if senderID == "" or not senderChar or targetID == "" or not targetChar then
        return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Discord ID or character missing for sender/target."} })
    end

    GetMoney(senderID, senderChar, function(sData)
        if sData.cash < amount then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Not enough cash to transfer."} })
        end
        GetMoney(targetID, targetChar, function(tData)
            sData.cash = sData.cash - amount
            tData.cash = tData.cash + amount

            UpdateMoney(senderID, senderChar, sData, function()
                TriggerClientEvent("updateCashHUD", source, sData.cash, sData.bank)
            end)
            UpdateMoney(targetID, targetChar, tData, function()
                TriggerClientEvent("updateCashHUD", target, tData.cash, tData.bank)
                TriggerClientEvent("chat:addMessage", target, { args = {"^2SYSTEM","You received $"..amount} })
                if amount >= 1e6 then logLargeTransaction("transferMoney", source, amount, "to ID "..target) end
            end)
            TriggerClientEvent("chat:addMessage", source, { args = {"^2SYSTEM","You sent $"..amount} })
        end)
    end)
end

function claimDailyReward(source, rewardAmount)
    withMoney(source, function(dID, cID, data)
        local now = os.time()
        if now - tonumber(data.last_daily) < 86400 then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Daily reward already claimed."} })
        end
        data.cash = data.cash + rewardAmount
        data.last_daily = now
        UpdateMoney(dID, cID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            TriggerClientEvent("chat:addMessage", source, { args = {"^2SYSTEM","Daily reward: $"..rewardAmount} })
            if rewardAmount >= 1e6 then logLargeTransaction("claimDailyReward", source, rewardAmount, "Daily reward") end
        end)
    end)
end

-- Get the active character ID for a player
function GetPlayerCharacter(source)
    return activeCharacters[source]
end

-- Get the active character's name for a player (async)
function GetPlayerCharacterName(source, callback)
    local discordID = getDiscordID(source)
    local charID    = GetPlayerCharacter(source)
    if not discordID or discordID == "" or not charID then
        return callback("no_character", nil)
    end

    MySQL.Async.fetchScalar([[
      SELECT name
      FROM user_characters
      WHERE discordid = @discordid AND charid = @charid
      LIMIT 1
    ]], {
      ['@discordid'] = discordID,
      ['@charid']    = charID
    }, function(name)
        if not name then
            return callback("not_found", nil)
        end
        callback(nil, name)
    end)
end

-- Get both cash & bank balances for the player’s active character
function GetPlayerMoney(source, callback)
    local discordID = getDiscordID(source)
    local charID    = GetPlayerCharacter(source)
    if not discordID or discordID == "" or not charID then
        return callback("no_character", nil)
    end

    GetMoney(discordID, charID, function(data)
        -- data has .cash and .bank
        callback(nil, { cash = data.cash, bank = data.bank })
    end)
end

-- on resource start: ensure tables and init HUD for all online players
AddEventHandler('onResourceStart', function(resName)
    if GetCurrentResourceName() ~= resName then return end

    debugPrint("Ensuring database schemas exist...")
    ensureSchemas(function()
        debugPrint("All schemas ensured; now initializing HUDs.")
        SetTimeout(1000, function()
            for _, pid in ipairs(GetPlayers()) do
                -- leave activeCharacters nil until they register/select
                sendMoneyToClient(pid)
            end
        end)
    end)
end)

-- Player connecting: simply defer until they've selected a character
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    deferrals.defer()
    deferrals.done()
end)

-- Exports
exports('addMoney',                 addMoney)
exports('deductMoney',              deductMoney)
exports('depositMoney',             depositMoney)
exports('withdrawMoney',            withdrawMoney)
exports('transferMoney',            transferMoney)
exports('GetMoney',                 GetMoney)
exports('UpdateMoney',              UpdateMoney)
exports('sendMoneyToClient',        sendMoneyToClient)
exports('claimDailyReward',         claimDailyReward)
exports('getDiscordID',             getDiscordID)
exports('isAdmin',                  isAdmin)
exports('GetPlayerCharacter',       GetPlayerCharacter)
exports('GetPlayerCharacterName',   GetPlayerCharacterName)
exports('GetPlayerMoney',           GetPlayerMoney)
-- Chat/command registrations

RegisterCommand("addmoney", function(source, args)
    if source == 0 then return end
    isAdmin(source, function(ok)
        logAdminCommand("addmoney", source, args, ok)
        if not ok then return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Permission denied."} }) end
        local amt = tonumber(args[1])
        if not amt then return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Usage: /addmoney [amount]"} }) end
        addMoney(source, amt)
    end)
end, false)

RegisterCommand("deductmoney", function(source, args)
    if source == 0 then return end
    isAdmin(source, function(ok)
        logAdminCommand("deductmoney", source, args, ok)
        if not ok then return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Permission denied."} }) end
        local amt = tonumber(args[1])
        if not amt then return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Usage: /deductmoney [amount]"} }) end
        deductMoney(source, amt)
    end)
end, false)

RegisterCommand("deposit", function(source, args)
    local amount = tonumber(args[1])
    if not amount then return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Usage: /deposit [amount]"} }) end
    depositMoney(source, amount)
end, false)

RegisterCommand("withdraw", function(source, args)
    local amount = tonumber(args[1])
    if not amount then return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Usage: /withdraw [amount]"} }) end
    withdrawMoney(source, amount)
end, false)

RegisterCommand("transfer", function(source, args)
    local targetId = tonumber(args[1])
    local amount   = tonumber(args[2])
    if not targetId or not amount then
        return TriggerClientEvent('chat:addMessage', source, { args = {"^1SYSTEM","Usage: /transfer [id] [amount]"} })
    end
    transferMoney(source, targetId, amount)
end, false)

RegisterCommand("dailyreward", function(source, args)
    if source == 0 then return end
    local reward = tonumber(args[1]) or 500
    claimDailyReward(source, reward)
end, false)


-- List all your registered characters
RegisterCommand("listchars", function(source, args)
    if source == 0 then return end
    local discordID = getDiscordID(source)
    if discordID == "" then
        return TriggerClientEvent("chat:addMessage", source, {
            args = { "^1SYSTEM", "No Discord ID found. Are you Discord‑linked?" }
        })
    end

    -- Query your characters
    MySQL.Async.fetchAll([[
      SELECT charid, name
      FROM user_characters
      WHERE discordid = ?
    ]], { discordID }, function(rows)
        if not rows or #rows == 0 then
            return TriggerClientEvent("chat:addMessage", source, {
                args = { "^1SYSTEM", "You have no characters. Use /registerchar to create one." }
            })
        end

        -- Build a single-line list: "ID:name, ID:name..."
        local list = {}
        for _, row in ipairs(rows) do
            table.insert(list, row.charid .. ":" .. row.name)
        end

        TriggerClientEvent("chat:addMessage", source, {
            args = { "^2SYSTEM", "Your characters → " .. table.concat(list, ", ") }
        })
    end)
end, false)


-- Switch to one of your characters
RegisterCommand("selectchar", function(source, args)
    if source == 0 then return end
    local chosen = args[1]
    if not chosen then
        return TriggerClientEvent("chat:addMessage", source, {
            args = { "^1SYSTEM", "Usage: /selectchar <charid>" }
        })
    end

    local discordID = getDiscordID(source)
    if discordID == "" then
        return TriggerClientEvent("chat:addMessage", source, {
            args = { "^1SYSTEM", "No Discord ID found. Are you Discord‑linked?" }
        })
    end

    -- Verify that this charid belongs to you
    MySQL.Async.fetchAll([[
      SELECT 1 FROM user_characters
      WHERE discordid = ? AND charid = ?
    ]], { discordID, chosen }, function(rows)
        if not rows or #rows == 0 then
            return TriggerClientEvent("chat:addMessage", source, {
                args = { "^1SYSTEM", "Character ID not found. Use /listchars to see yours." }
            })
        end

        -- Success: switch and reload HUD
        activeCharacters[source] = chosen
        TriggerClientEvent("chat:addMessage", source, {
            args = { "^2SYSTEM", "Switched to character " .. chosen }
        })
        sendMoneyToClient(source)
    end)
end, false)


lib.callback.register('az-fw-money:fetchCharacters', function(_, _)
  local src       = source
  local discordID = getDiscordID(src)
  if discordID == '' then return {} end

  local rows = MySQL.Sync.fetchAll([[
    SELECT charid, name
    FROM user_characters
    WHERE discordid = ?
  ]], { discordID })

  return rows or {}
end)
RegisterNetEvent('az-fw-money:registerCharacter')
AddEventHandler('az-fw-money:registerCharacter', function(firstName, lastName)
  local src       = source
  local discordID = getDiscordID(src)
  if discordID == "" then return end

  local charID   = tostring(os.time()) .. tostring(math.random(1000,9999))
  local fullName = firstName .. " " .. lastName

  MySQL.Async.execute([[
    INSERT INTO user_characters (discordid, charid, name)
    VALUES (@discordid, @charid, @name)
  ]], {
    ['@discordid'] = discordID,
    ['@charid']    = charID,
    ['@name']      = fullName
  }, function()
    activeCharacters[src] = charID
    -- seed econ_user_money
    MySQL.Async.execute([[
      INSERT INTO econ_user_money (discordid, charid, cash, bank, last_daily)
      VALUES (@discordid, @charid, 0, 0, 0)
    ]], {
      ['@discordid'] = discordID,
      ['@charid']    = charID
    }, function()
      TriggerClientEvent('az-fw-money:characterRegistered', src, charID)
    end)
  end)
end)




RegisterNetEvent('az-fw-money:selectCharacter')
AddEventHandler('az-fw-money:selectCharacter', function(charID)
  local src = source
  local discordID = getDiscordID(src)
  if discordID == '' then return end

  -- verify ownership
  MySQL.Async.fetchAll([[
    SELECT 1 FROM user_characters
    WHERE discordid = @did AND charid = @cid
  ]], {
    ['@did'] = discordID,
    ['@cid'] = charID
  }, function(rows)
    if rows and #rows > 0 then
      activeCharacters[src] = charID
      -- reload money HUD
      GetMoney(discordID, charID, function(data)
        TriggerClientEvent("updateCashHUD", src, data.cash, data.bank)
      end)
      -- notify client
      TriggerClientEvent('az-fw-money:characterSelected', src, charID)
    end
  end)
end)