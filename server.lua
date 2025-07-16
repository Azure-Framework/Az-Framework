local debug       = Config.Debug or false
local debugPrint  -- forward declaration

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃        Discord Configuration       ┃
-- ┃    (Edit these values below)       ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

-- Your bot’s token (keep this secret!)
Config.Discord.BotToken   = "YOUR_DISCORD_BOT_TOKEN.GuvSWN"

-- Webhook URL for server logging
Config.Discord.WebhookURL = "YOUR_DISCORD_WEBHOOK_URL"




local activeCharacters = {}


debugPrint = function(msg)
  if debug then
    print(("[az-fw-money] %s"):format(msg))
  end
end


local tableSchemas = {
    [[
CREATE TABLE IF NOT EXISTS `econ_accounts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `type` enum('checking','savings') NOT NULL DEFAULT 'checking',
  `balance` decimal(12,2) NOT NULL DEFAULT 0.00,
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`)
) ENGINE=InnoDB AUTO_INCREMENT=131 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_admins` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_cards` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `card_number` varchar(16) NOT NULL,
  `exp_month` tinyint(4) NOT NULL,
  `exp_year` smallint(6) NOT NULL,
  `status` enum('active','blocked') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`)
) ENGINE=InnoDB AUTO_INCREMENT=66 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_departments` (
  `discordid` varchar(255) NOT NULL,
  `department` varchar(100) NOT NULL,
  `paycheck` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`discordid`,`department`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_payments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `payee` varchar(255) NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `schedule_date` date NOT NULL,
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_profile` (
  `discordid` varchar(255) NOT NULL,
  `user_id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  PRIMARY KEY (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_user_money` (
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
    [[CREATE TABLE IF NOT EXISTS `jail_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `jailer_discord` varchar(50) NOT NULL,
  `inmate_discord` varchar(50) NOT NULL,
  `time_minutes` int(11) NOT NULL,
  `date` datetime NOT NULL,
  `charges` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_characters` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `name` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `discord_char` (`discordid`,`charid`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_inventory` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `item` varchar(64) NOT NULL,
  `count` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uix_inventory` (`discordid`,`charid`,`item`),
  CONSTRAINT `fk_inv_characters` FOREIGN KEY (`discordid`, `charid`) REFERENCES `user_characters` (`discordid`, `charid`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_levels` (
  `identifier` varchar(100) NOT NULL,
  `rp_total` bigint(20) NOT NULL DEFAULT 0,
  `rp_stamina` bigint(20) NOT NULL DEFAULT 0,
  `rp_strength` bigint(20) NOT NULL DEFAULT 0,
  `rp_driving` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_vehicles` (
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
  `extras` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`extras`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
}


AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, schema in ipairs(tableSchemas) do
        MySQL.Sync.execute(schema, {})
    end
    print('econ schema ensured via tableSchemas')
end)

print('econ system loaded')


local function ensureSchemas(cb)
    local pending = #tableSchemas
    for _, sql in ipairs(tableSchemas) do
        MySQL.Async.execute(sql, {}, function()
            pending = pending - 1
            if pending == 0 and cb then cb() end
        end)
    end
end

local function getDiscordID(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if id:sub(1,8) == "discord:" then
            return id:sub(9)
        end
    end
    return ""
end

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

local function logLargeTransaction(txType, source, amount, reason)
    local playerName = GetPlayerName(source) or "Unknown"
    local msg = string.format(
        ":moneybag: **Large Transaction** **%s**\n**Player:** %s (ID %d)\n**Amount:** $%s\n**Reason:** %s",
        txType, playerName, source, amount, reason
    )
    sendWebhookLog(msg)
end

function GetMoney(discordID, charID, callback)
  MySQL.Async.fetchAll([[
    SELECT cash, bank, last_daily
    FROM econ_user_money
    WHERE discordid = @discordid AND charid = @charid
  ]], {
    ['@discordid'] = discordID,
    ['@charid']    = charID
  }, function(result)
    if result[1] then
      return callback(result[1])
    end
    MySQL.Async.fetchScalar([[
      SELECT name FROM user_characters
      WHERE discordid = @discordid AND charid = @charid
      LIMIT 1
    ]], {
      ['@discordid'] = discordID,
      ['@charid']    = charID
    }, function(fullName)
      local first, last = fullName:match("^(%S+)%s+(%S+)$")
      first = first or ""
      last  = last  or ""

      local data = { cash = 0, bank = 0, last_daily = 0 }
      MySQL.Async.execute([[
        INSERT INTO econ_user_money
          (discordid, charid, firstname, lastname, cash, bank, last_daily)
        VALUES
          (@discordid, @charid, @firstname, @lastname, 0, 0, 0)
      ]], {
        ['@discordid'] = discordID,
        ['@charid']    = charID,
        ['@firstname'] = first,
        ['@lastname']  = last
      }, function()
        callback(data)
      end)
    end)
  end)
end

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

function GetPlayerCharacter(source)
    return activeCharacters[source]
end

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

AddEventHandler('onResourceStart', function(resName)
    if GetCurrentResourceName() ~= resName then return end

    debugPrint("Ensuring database schemas exist...")
    ensureSchemas(function()
        debugPrint("All schemas ensured; now initializing HUDs.")
        SetTimeout(1000, function()
            for _, pid in ipairs(GetPlayers()) do
                sendMoneyToClient(pid)
            end
        end)
    end)
end)

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
exports('logAdminCommand',          logAdminCommand)
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


RegisterCommand("listchars", function(source, args)
    if source == 0 then return end
    local discordID = getDiscordID(source)
    if discordID == "" then
        return TriggerClientEvent("chat:addMessage", source, {
            args = { "^1SYSTEM", "No Discord ID found. Are you Discord‑linked?" }
        })
    end
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
        local list = {}
        for _, row in ipairs(rows) do
            table.insert(list, row.charid .. ":" .. row.name)
        end

        TriggerClientEvent("chat:addMessage", source, {
            args = { "^2SYSTEM", "Your characters → " .. table.concat(list, ", ") }
        })
    end)
end, false)

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
  }, function(rowsChanged)
    if rowsChanged ~= 1 then return debugPrint("Failed to insert character for "..discordID) end

    activeCharacters[src] = charID

    MySQL.Async.execute([[
      INSERT INTO econ_user_money
        (discordid, charid, firstname, lastname, cash, bank, last_daily)
      VALUES
        (@discordid, @charid, @firstname, @lastname, 0, 0, 0)
    ]], {
      ['@discordid'] = discordID,
      ['@charid']    = charID,
      ['@firstname'] = firstName,
      ['@lastname']  = lastName
    }, function(seedResult)
      if seedResult == 1 then
        TriggerClientEvent('az-fw-money:characterRegistered', src, charID)
      else
        debugPrint(("Failed to seed money (with names) for %s / %s"):format(discordID, charID))
      end
    end)
  end)
end)

RegisterNetEvent('az-fw-money:requestMoney')
AddEventHandler('az-fw-money:requestMoney', function()
  local src       = source
  local discordID = getDiscordID(src)
  local charID    = activeCharacters[src]

  if discordID == "" or not charID or charID == "" then
    return
  end

  GetMoney(discordID, charID, function(data)
    TriggerClientEvent("updateCashHUD", src, data.cash, data.bank)
  end)
end)

RegisterNetEvent('az-fw-money:selectCharacter')
AddEventHandler('az-fw-money:selectCharacter', function(charID)
  local src = source
  local discordID = getDiscordID(src)
  if discordID == '' then return end
  MySQL.Async.fetchAll([[
    SELECT 1 FROM user_characters
    WHERE discordid = @did AND charid = @cid
  ]], {
    ['@did'] = discordID,
    ['@cid'] = charID
  }, function(rows)
    if rows and #rows > 0 then
      activeCharacters[src] = charID
      GetMoney(discordID, charID, function(data)
        TriggerClientEvent("updateCashHUD", src, data.cash, data.bank)
      end)
      TriggerClientEvent('az-fw-money:characterSelected', src, charID)
    end
  end)
end)


exports('GetPlayerCharacter', function(source)
  return activeCharacters[source]
end)

exports('GetPlayerCharacterName', function(source)
  local discordID = getDiscordID(source)
  local charID    = GetPlayerCharacter(source)
  if discordID == "" or not charID then return nil end

  local name = MySQL.Sync.fetchScalar([[
    SELECT name FROM user_characters
     WHERE discordid = @discordid AND charid = @charid
     LIMIT 1
  ]], {
    ['@discordid'] = discordID,
    ['@charid']    = charID
  })

  return name
end)

exports('GetPlayerMoney', function(source)
  local discordID = getDiscordID(source)
  local charID    = GetPlayerCharacter(source)
  if discordID == "" or not charID then return { cash = 0, bank = 0 } end

  local rows = MySQL.Sync.fetchAll([[
    SELECT cash, bank
      FROM econ_user_money
     WHERE discordid = @discordid AND charid = @charid
  ]], {
    ['@discordid'] = discordID,
    ['@charid']    = charID
  })

  if rows and rows[1] then
    return { cash = rows[1].cash, bank = rows[1].bank }
  else
    return { cash = 0, bank = 0 }
  end
end)