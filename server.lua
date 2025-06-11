local debug = Config.Debug or false
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
      PRIMARY KEY (`discordid`
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `econ_user_money` (
      `discordid` varchar(255) NOT NULL,
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
      PRIMARY KEY (`discordid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    ]],
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

local function debugPrint(msg)
    if debug then
        print(("[az-fw-money] %s"):format(msg))
    end
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

-- Database helpers
local function GetMoney(discordID, callback)
    MySQL.Async.fetchAll([[
        SELECT cash, bank, last_daily
        FROM econ_user_money
        WHERE discordid = @discordid
    ]], { ['@discordid'] = discordID }, function(result)
        if not result[1] then
            local data = { cash = 0, bank = 0, last_daily = 0 }
            MySQL.Async.execute([[
                INSERT INTO econ_user_money (discordid, cash, bank, last_daily)
                VALUES (@discordid, 0, 0, 0)
            ]], { ['@discordid'] = discordID })
            callback(data)
        else
            callback(result[1])
        end
    end)
end

-- Send cash+bank to a single client
local function sendMoneyToClient(playerId, discordid)
    MySQL.Async.fetchAll(
      'SELECT cash, bank FROM econ_user_money WHERE discordid = @id',
      { ['@id'] = discordid },
      function(rows)
        if rows[1] then
          TriggerClientEvent('updateCashHUD', playerId, rows[1].cash, rows[1].bank)
        end
      end
    )
end
-- handle client asking “what’s my money?”
RegisterServerEvent('az-fw-money:requestMoney')
AddEventHandler('az-fw-money:requestMoney', function()
  local src = source
  local discordid = getDiscordId(src)
  if not discordid then return end
    sendMoneyToClient(src, discordid)
end)

local function UpdateMoney(discordID, data, cb)
    MySQL.Async.execute([[
        UPDATE econ_user_money
        SET cash = @cash,
            bank = @bank,
            last_daily = @last_daily
        WHERE discordid = @discordid
    ]], {
        ['@cash']       = data.cash,
        ['@bank']       = data.bank,
        ['@last_daily'] = data.last_daily,
        ['@discordid']  = discordID
    }, cb)
end

-- on resource start, create all tables then initialize HUD
AddEventHandler('onResourceStart', function(resName)
    if GetCurrentResourceName() ~= resName then return end

    debugPrint("Ensuring database schemas exist...")
    ensureSchemas(function()
        debugPrint("All schemas ensured; now updating HUD for online players.")
        -- small delay to let DB settle
        SetTimeout(1000, function()
            for _, pid in ipairs(GetPlayers()) do
                local dID = getDiscordID(pid)
                if dID ~= "" then
                    GetMoney(dID, function(data)
                        TriggerClientEvent("updateCashHUD", pid, data.cash, data.bank)
                    end)
                end
            end
        end)
    end)
end)


--------------------------------------
-- Core economy functions
--------------------------------------
function addMoney(source, amount)
    local dID = getDiscordID(source); if dID == "" then return end
    GetMoney(dID, function(data)
        data.cash = data.cash + amount
        UpdateMoney(dID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then
                logLargeTransaction("addMoney", source, amount, "addMoney() export")
            end
        end)
    end)
end

function deductMoney(source, amount)
    local dID = getDiscordID(source); if dID == "" then return end
    GetMoney(dID, function(data)
        data.cash = math.max(0, data.cash - amount)
        UpdateMoney(dID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then
                logLargeTransaction("deductMoney", source, amount, "deductMoney() export")
            end
        end)
    end)
end

function modifyMoney(source, amount)
    local dID = getDiscordID(source); if dID == "" then return end
    GetMoney(dID, function(data)
        data.cash = amount
        UpdateMoney(dID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then
                logLargeTransaction("modifyMoney", source, amount, "modifyMoney() export")
            end
        end)
    end)
end

function depositMoney(source, amount)
    local dID = getDiscordID(source); if dID == "" then return end
    GetMoney(dID, function(data)
        if data.cash < amount then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Not enough cash to deposit."} })
        end
        data.cash = data.cash - amount
        data.bank = data.bank + amount
        UpdateMoney(dID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then
                logLargeTransaction("depositMoney", source, amount, "depositMoney() export")
            end
        end)
    end)
end

function withdrawMoney(source, amount)
    local dID = getDiscordID(source); if dID == "" then return end
    GetMoney(dID, function(data)
        if data.bank < amount then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Not enough bank funds to withdraw."} })
        end
        data.bank = data.bank - amount
        data.cash = data.cash + amount
        UpdateMoney(dID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            if amount >= 1e6 then
                logLargeTransaction("withdrawMoney", source, amount, "withdrawMoney() export")
            end
        end)
    end)
end

function transferMoney(source, target, amount)
    local senderID = getDiscordID(source)
    local targetID = getDiscordID(target)
    if senderID == "" or targetID == "" then
        return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Discord ID missing for sender/target."} })
    end

    GetMoney(senderID, function(sData)
        if sData.cash < amount then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Not enough cash to transfer."} })
        end
        GetMoney(targetID, function(tData)
            sData.cash = sData.cash - amount
            tData.cash = tData.cash + amount
            UpdateMoney(senderID, sData, function()
                TriggerClientEvent("updateCashHUD", source, sData.cash, sData.bank)
            end)
            UpdateMoney(targetID, tData, function()
                TriggerClientEvent("updateCashHUD", target, tData.cash, tData.bank)
                TriggerClientEvent("chat:addMessage", target, { args = {"^2SYSTEM","You received $"..amount} })
                if amount >= 1e6 then
                    logLargeTransaction("transferMoney", source, amount, "to ID "..target)
                end
            end)
            TriggerClientEvent("chat:addMessage", source, { args = {"^2SYSTEM","You sent $"..amount} })
        end)
    end)
end

function claimDailyReward(source, rewardAmount)
    local dID = getDiscordID(source); if dID == "" then return end
    local now = os.time()
    GetMoney(dID, function(data)
        if now - tonumber(data.last_daily) < 86400 then
            return TriggerClientEvent("chat:addMessage", source, { args = {"^1SYSTEM","Daily reward already claimed."} })
        end
        data.cash = data.cash + rewardAmount
        data.last_daily = now
        UpdateMoney(dID, data, function()
            TriggerClientEvent("updateCashHUD", source, data.cash, data.bank)
            TriggerClientEvent("chat:addMessage", source, { args = {"^2SYSTEM","Daily reward: $"..rewardAmount} })
            if rewardAmount >= 1e6 then
                logLargeTransaction("claimDailyReward", source, rewardAmount, "Daily reward")
            end
        end)
    end)
end

--------------------------------------
-- Exports
--------------------------------------
exports('addMoney',           addMoney)
exports('deductMoney',        deductMoney)
exports('modifyMoney',        modifyMoney)
exports('depositMoney',       depositMoney)
exports('withdrawMoney',      withdrawMoney)
exports('transferMoney',      transferMoney)
exports('GetMoney',           GetMoney)
exports('sendMoneyToClient',  sendMoneyToClient)
exports('claimDailyReward',   claimDailyReward)
exports('getDiscordID',       getDiscordID)
exports('getDiscordRoleList', getDiscordRoleList)
exports('isAdmin',            isAdmin)
exports('getMoney',           GetMoney)
exports('updateMoney',        UpdateMoney)
exports('logAdminCommand',    logAdminCommand)
--------------------------------------
-- Player Connecting: Update HUD on join
--------------------------------------
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()

    debugPrint(("Player connecting: source = %s"):format(src))

    Wait(0) -- just to be safe

    local dID = getDiscordID(src)
    debugPrint(("Retrieved Discord ID: %s"):format(dID))

    if dID ~= "" then
        debugPrint("Valid Discord ID found, fetching money data...")

        GetMoney(dID, function(data)
            if data then
                debugPrint(("Money data received: cash = %s, bank = %s"):format(data.cash, data.bank))
                TriggerClientEvent("updateCashHUD", src, data.cash, data.bank)
                debugPrint(("updateCashHUD event triggered for player %s"):format(src))
            else
                debugPrint(("No money data found for Discord ID: %s"):format(dID))
            end

            deferrals.done()
        end)
    else
        debugPrint(("No valid Discord ID found for source %s"):format(src))
        deferrals.done()
    end
end)


-- New: respond to client’s “give me my money” request
RegisterNetEvent('az-fw-money:requestMoney')
AddEventHandler('az-fw-money:requestMoney', function()
    local src = source
    local dID = getDiscordID(src)
    if dID ~= "" then
        GetMoney(dID, function(data)
            if data then
                TriggerClientEvent("updateCashHUD", src, data.cash, data.bank)
                debugPrint(("[onJoin] updateCashHUD → %s: cash=%s bank=%s")
                    :format(src, data.cash, data.bank))
            else
                debugPrint(("[onJoin] no money row for %s"):format(dID))
            end
        end)
    else
        debugPrint(("[onJoin] no Discord ID for %s"):format(src))
    end
end)


--------------------------------------
-- Debug/Admin Commands
--------------------------------------

-- /addmoney
RegisterCommand("addmoney", function(source, args)
    if source == 0 then return end

    isAdmin(source, function(ok)
        logAdminCommand("addmoney", source, args, ok)
        if not ok then
            return TriggerClientEvent("chat:addMessage", source, {
                args = {"^1SYSTEM","You do not have permission."}
            })
        end

        local amt = tonumber(args[1])
        if not amt then
            return TriggerClientEvent("chat:addMessage", source, {
                args = {"^1SYSTEM","Usage: /addmoney [amount]"}
            })
        end

        addMoney(source, amt)
    end)
end, false)

-- /deductmoney
RegisterCommand("deductmoney", function(source, args)
    if source == 0 then return end

    isAdmin(source, function(ok)
        logAdminCommand("deductmoney", source, args, ok)
        if not ok then
            return TriggerClientEvent("chat:addMessage", source, {
                args = {"^1SYSTEM","Permission denied."}
            })
        end

        local amt = tonumber(args[1])
        if not amt then
            return TriggerClientEvent("chat:addMessage", source, {
                args = {"^1SYSTEM","Usage: /deductmoney [amount]"}
            })
        end

        deductMoney(source, amt)
    end)
end, false)

-- /setmoney
RegisterCommand("setmoney", function(source, args)
    if source == 0 then return end

    isAdmin(source, function(ok)
        logAdminCommand("setmoney", source, args, ok)
        if not ok then
            return TriggerClientEvent("chat:addMessage", source, {
                args = {"^1SYSTEM","Permission denied."}
            })
        end

        local amt = tonumber(args[1])
        if not amt then
            return TriggerClientEvent("chat:addMessage", source, {
                args = {"^1SYSTEM","Usage: /setmoney [amount]"}
            })
        end

        modifyMoney(source, amt)
    end)
end, false)

RegisterCommand("transfer", function(source, args, rawCommand)
    local targetId = tonumber(args[1])
    local amount = tonumber(args[2])
    if not targetId or not amount then
        TriggerClientEvent('chat:addMessage', source, { args = {"^1Usage: /transfer [id] [amount]"}})
        return
    end

    transferMoney(source, targetId, amount)
    debugPrint(("Player ID %d transferred $%s to %d"):format(source, amount, targetId))

    if amount >= 1000000 then
        logLargeTransaction("Transfer", source, amount, "Bank transfer to ID " .. targetId)
    end
end, false)

-- Example banking commands: deposit, withdraw, transfer
RegisterCommand("deposit", function(source, args, rawCommand)
    local amount = tonumber(args[1])
    if not amount then
        TriggerClientEvent('chat:addMessage', source, { args = {"^1Usage: /deposit [amount]"}})
        return
    end

    depositMoney(source, amount)
    debugPrint(("Player ID %d deposited $%s"):format(source, amount))

    if amount >= 1000000 then
        logLargeTransaction("Deposit", source, amount, "Bank deposit")
    end
end, false)

RegisterCommand("withdraw", function(source, args, rawCommand)
    local amount = tonumber(args[1])
    if not amount then
        TriggerClientEvent('chat:addMessage', source, { args = {"^1Usage: /withdraw [amount]"}})
        return
    end

    withdrawMoney(source, amount)
    debugPrint(("Player ID %d withdrew $%s"):format(source, amount))

    if amount >= 1000000 then
        logLargeTransaction("Withdraw", source, amount, "Bank withdrawal")
    end
end, false)

RegisterCommand("dailyreward", function(source, args)
    if source == 0 then return end
    local reward = tonumber(args[1]) or 500
    claimDailyReward(source, reward)
end, false)
