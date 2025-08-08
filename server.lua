Config = Config or {}
Config.Debug = Config.Debug or false
Config.Discord = Config.Discord or {}
Config.PaycheckIntervalMinutes = Config.PaycheckIntervalMinutes or 60
local debug       = Config.Debug
local debugPrint  -- forward declaration

-- GetConvar(varName, defaultValue)
Config.Discord.BotToken   = GetConvar("DISCORD_BOT_TOKEN", "")
Config.Discord.WebhookURL = GetConvar("DISCORD_WEBHOOK_URL", "")
-- sanity check
if Config.Discord.BotToken == "" then
  print("^1[Discord]^0 DISCORD_BOT_TOKEN not set! Check server.cfg")
end
if Config.Discord.WebhookURL == "" then
  print("^1[Discord]^0 DISCORD_WEBHOOK_URL not set! Check server.cfg")
end


local activeCharacters = {}


debugPrint = function(msg)
  if debug then
    print(("[az-fw-money] %s"):format(msg))
  end
end

-- Table schemas, including new user_characters, per-character money, and schema migration
-- Schema definitions from external dump
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

-- On resource start, apply schema if needed
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, schema in ipairs(tableSchemas) do
        MySQL.Sync.execute(schema, {})
    end
    print('econ schema ensured via tableSchemas')
end)

-- (Existing handlers remain unchanged)
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

    local guildId  = GetConvar("DISCORD_GUILD_ID", "")
    local botToken = GetConvar("DISCORD_BOT_TOKEN", "")

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
  -- 1) Log what AdminRoleId we’re expecting
  debugPrint(("isAdmin: checking player %d against Config.AdminRoleId = %s"):format(
    playerSrc, tostring(Config.AdminRoleId)
  ))

  getDiscordRoleList(playerSrc, function(err, roles)
    -- 2) Error fetching? log and deny
    if err then
      debugPrint(("isAdmin error for %d: %s"):format(playerSrc, tostring(err)))
      return cb(false)
    end

    -- 3) Log the raw roles array we got back
    debugPrint(("isAdmin: got roles for %d → %s"):format(
      playerSrc, json.encode(roles)
    ))

    -- 4) Compare each role (string-casted) against the expected ID
    for _, roleID in ipairs(roles) do
      debugPrint(("isAdmin: comparing role %s to %s"):format(
        tostring(roleID), tostring(Config.AdminRoleId)
      ))
      if tostring(roleID) == tostring(Config.AdminRoleId) then
        debugPrint(("isAdmin: match! %s is admin role"):format(roleID))
        return cb(true)
      end
    end

    -- 5) Nothing matched
    debugPrint(("isAdmin: no match found, denying admin for %d"):format(playerSrc))
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

MySQL.Async.fetchAll([[
    SELECT
      uc.active_department AS dept,
      ed.paycheck              AS pay
    FROM user_characters uc
    LEFT JOIN econ_departments ed
      ON ed.discordid  = uc.discordid
     AND ed.department = uc.active_department
    WHERE uc.discordid = @discordid
      AND uc.charid     = @charid
    LIMIT 1
]], {
    ['@discordid'] = discordID,
    ['@charid']    = charID
}, function(rows)
    if not rows or not rows[1] then
        debugPrint(("  ↳ No user_characters row for %s / %s"):format(discordID, charID))
        return
    end

    local dept = rows[1].dept or "<nil>"
    local pay  = rows[1].pay

    debugPrint(("  ↳ Active department = '%s'"):format(dept))
    debugPrint(("  ↳ econ_departments.paycheck = '%s'"):format(tostring(pay)))

    local amt = tonumber(pay) or 0
    if amt > 0 then
        debugPrint(("  ↳ Paying $%d to player %d"):format(amt, src))
        addMoney(src, amt)
        TriggerClientEvent('chat:addMessage', src, {
            args = { "^2PAYCHECK", "You received your hourly paycheck of $" .. amt }
        })
    else
        debugPrint(("  ↳ No paycheck for player %d (dept '%s' → amount %s)"):format(src, dept, tostring(pay)))
    end
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


RegisterNetEvent("az-fw-departments:setActive")
AddEventHandler("az-fw-departments:setActive", function(dept)
    local src       = source
    local discordID = getDiscordID(src)
    local charID    = activeCharacters[src]

    if not discordID or discordID == "" or not charID then
        debugPrint(("setActive: missing discordID/charID for player %d"):format(src))
        return
    end

    debugPrint(("setActive: %s / %s → '%s'"):format(discordID, charID, dept))

    MySQL.Async.execute([[
        UPDATE user_characters
           SET active_department = @dept
         WHERE discordid         = @discordid
           AND charid            = @charid
    ]], {
        ['@dept']      = dept,
        ['@discordid'] = discordID,
        ['@charid']    = charID,
    }, function(affected)
        debugPrint(("  ↳ user_characters rows updated: %d"):format(affected))
    end)
end)

-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃    HOURLY PAYCHECK THREAD w/ ROLES   ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Citizen.CreateThread(function()
    print("Hourly-paycheck thread starting. Interval = " .. tostring(Config.PaycheckIntervalMinutes or 60) .. " minutes.")
    local interval = (Config.PaycheckIntervalMinutes or 60) * 60 * 1000

    while true do
        Citizen.Wait(interval)
        print("Paycheck pulse triggered!")

        for src, charID in pairs(activeCharacters) do
            print(("Processing player %d → charID '%s'"):format(src, tostring(charID)))
            local discordID = getDiscordID(src)
            if discordID == "" then
                print(" → no Discord ID, skipping")
                goto continue
            end

            getDiscordRoleList(src, function(err, roles)
                if err then
                    print((" → could not fetch roles for %d (%s), skipping"):format(src, err))
                    return
                end
         
            local dept = ""  -- fetch active_department from user_characters
                MySQL.Async.fetchScalar([[
                    SELECT active_department
                      FROM user_characters
                     WHERE discordid = @discordid
                       AND charid    = @charid
                     LIMIT 1
                ]], {
                    ['@discordid'] = discordID,
                    ['@charid']    = charID
                }, function(active_department)
                    if not active_department or active_department == "" then
                        print((" → char %s has no active_department set, skipping"):format(charID))
                        return
                    end
                    dept = active_department

                    -- combine userID + roles
                    local lookupIds = { discordID }
                    for _, rid in ipairs(roles) do table.insert(lookupIds, rid) end

                    -- generate placeholders ?,?,…
                    local placeholders = table.concat((function()
                        local t = {}
                        for i=1,#lookupIds do t[i] = "?" end
                        return t
                    end)(), ",")

                    -- run the paycheck lookup
                    local sql = ([[ 
                        SELECT paycheck 
                          FROM econ_departments 
                         WHERE department = ? 
                           AND discordid IN (%s) 
                         LIMIT 1
                    ]]):format(placeholders)

                    -- build params: first the dept, then all IDs
                    local params = { dept }
                    for _, id in ipairs(lookupIds) do table.insert(params, id) end

                    MySQL.Async.fetchScalar(sql, params, function(paycheck)
                        print(("  ↳ lookup dept='%s' ids=[%s] → %s")
                            :format(dept, table.concat(lookupIds,","), tostring(paycheck)))
                        local amt = tonumber(paycheck) or 0
                        if amt > 0 then
                            print(("  ↳ Paying $%d to %d"):format(amt, src))
                            addMoney(src, amt)
                            TriggerClientEvent('chat:addMessage', src, {
                                args = { "^2PAYCHECK", "Hourly pay: $" .. amt }
                            })
                        else
                            print(("  ↳ No matching paycheck row, or amount=0"))
                        end
                    end)
                end)
            end)

            ::continue::
        end
    end
end)
