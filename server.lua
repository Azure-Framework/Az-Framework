Config = Config or {}
Config.Debug = Config.Debug or false
Config.Discord = Config.Discord or {}
Config.PaycheckIntervalMinutes = Config.PaycheckIntervalMinutes or 60
local debug = Config.Debug
local debugPrint

local M = {
    money = "econ_user_money",
    accts = "econ_accounts",
    pays = "econ_payments",
    cards = "econ_cards",
    dept = "econ_departments"
}

local SAVINGS_APR = 0.05

Config.Discord.BotToken = GetConvar("DISCORD_BOT_TOKEN", "")
Config.Discord.WebhookURL = GetConvar("DISCORD_WEBHOOK_URL", "")
Config.Discord.GuildId = GetConvar("DISCORD_GUILD_ID", "")

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


local function safeCb(cb, ...)
    if type(cb) == "function" then
        cb(...)
    end
end


local function dbQuery(query, params, cb)
    if not exports.oxmysql or not exports.oxmysql.query then
        debugPrint("oxmysql not available for dbQuery")
        return safeCb(cb, {})
    end
    exports.oxmysql:query(query, params or {}, function(res)
        safeCb(cb, res or {})
    end)
end

local function dbExecute(query, params, cb)
    if not exports.oxmysql or not exports.oxmysql.execute then
        debugPrint("oxmysql not available for dbExecute")
        return safeCb(cb, 0)
    end
    exports.oxmysql:execute(query, params or {}, function(res)
        safeCb(cb, res or 0)
    end)
end

local function dbInsert(query, params, cb)
    if not exports.oxmysql or not exports.oxmysql.insert then
        debugPrint("oxmysql not available for dbInsert")
        return safeCb(cb, nil)
    end
    exports.oxmysql:insert(query, params or {}, function(insertId)
        safeCb(cb, insertId)
    end)
end

local function dbFetchScalar(query, params, cb)
    dbQuery(query, params, function(rows)
        if rows and rows[1] then
            for _, v in pairs(rows[1]) do
                return safeCb(cb, v)
            end
        end
        safeCb(cb, nil)
    end)
end

local function getDiscordID(source)
    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        if type(id) == 'string' and id:sub(1, 8) == "discord:" then
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

    local guildId = GetConvar("DISCORD_GUILD_ID", "")
    local botToken = GetConvar("DISCORD_BOT_TOKEN", "")

    if not guildId or not botToken then
        debugPrint("Missing GuildId or BotToken in config")
        return cb("config_error", nil)
    end

    local url = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(guildId, discordID)
    debugPrint("Fetching roles via: " .. url)

    PerformHttpRequest(
        url,
        function(statusCode, body)
            debugPrint(("Discord API HTTP %d"):format(statusCode))
            if statusCode ~= 200 then
                return cb("http_" .. statusCode, nil)
            end

            local ok, data = pcall(json.decode, body)
            if not ok or type(data.roles) ~= "table" then
                debugPrint("Invalid roles payload")
                return cb("no_roles", nil)
            end

            cb(nil, data.roles)
        end,
        "GET",
        "",
        {
            ["Authorization"] = "Bot " .. botToken,
            ["Content-Type"] = "application/json"
        }
    )
end

local function isAdmin(playerSrc, cb)
    debugPrint(
        ("isAdmin: checking player %d against Config.AdminRoleId = %s"):format(playerSrc, tostring(Config.AdminRoleId))
    )

    getDiscordRoleList(
        playerSrc,
        function(err, roles)
            if err then
                debugPrint(("isAdmin error for %d: %s"):format(playerSrc, tostring(err)))
                return cb(false)
            end

            debugPrint(("isAdmin: got roles for %d → %s"):format(playerSrc, json.encode(roles)))

            for _, roleID in ipairs(roles) do
                debugPrint(("isAdmin: comparing role %s to %s"):format(tostring(roleID), tostring(Config.AdminRoleId)))
                if tostring(roleID) == tostring(Config.AdminRoleId) then
                    debugPrint(("isAdmin: match! %s is admin role"):format(roleID))
                    return cb(true)
                end
            end

            debugPrint(("isAdmin: no match found, denying admin for %d"):format(playerSrc))
            cb(false)
        end
    )
end

local function sendWebhookLog(message)
    if not Config.Discord.WebhookURL or Config.Discord.WebhookURL == "" then
        debugPrint("Webhook URL not configured; skipping Discord log.")
        return
    end

    local payload = {
        username = "Server Logger",
        content = message
    }

    PerformHttpRequest(
        Config.Discord.WebhookURL,
        function(statusCode)
            if statusCode ~= 204 and statusCode ~= 200 then
                debugPrint("Discord webhook error: " .. tostring(statusCode))
            end
        end,
        "POST",
        json.encode(payload),
        {
            ["Content-Type"] = "application/json"
        }
    )
end

local function logAdminCommand(commandName, source, args, success)
    local playerName = GetPlayerName(source) or "Unknown"
    local statusIcon = success and "✅ Allowed" or "❌ Denied"
    local argsStr = args and table.concat(args, " ") or ""
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
        txType, playerName, source, tostring(amount), reason
    )
    sendWebhookLog(msg)
end


function GetMoney(discordID, charID, callback)
    if type(callback) ~= "function" then
        debugPrint("GetMoney requires a callback")
        return
    end

    dbQuery(
        string.format("SELECT cash, bank, last_daily FROM `%s` WHERE discordid = ? AND charid = ? LIMIT 1", M.money),
        {discordID, charID},
        function(result)
            if result and result[1] then
                return callback(result[1])
            end

            
            dbFetchScalar(
                "SELECT name FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1",
                {discordID, charID},
                function(fullName)
                    local first, last = "", ""
                    if fullName and type(fullName) == "string" then
                        local f, l = fullName:match("^(%S+)%s+(%S+)$")
                        first = f or ""
                        last = l or ""
                    end

                    local data = {cash = 0, bank = 0, last_daily = 0}
                    dbInsert(
                        string.format(
                            "INSERT INTO `%s` (discordid, charid, firstname, lastname, cash, bank, last_daily) VALUES (?,?,?,?,?,?,?)",
                            M.money
                        ),
                        {discordID, charID, first, last, 0, 0, 0},
                        function(_insertId)
                            safeCb(callback, data)
                        end
                    )
                end
            )
        end
    )
end

function UpdateMoney(discordID, charID, data, cb)
    dbExecute(
        string.format(
            "UPDATE `%s` SET cash = ?, bank = ?, last_daily = ? WHERE discordid = ? AND charid = ?",
            M.money
        ),
        {data.cash, data.bank, data.last_daily, discordID, charID},
        function(affected)
            safeCb(cb, affected)
        end
    )
end

local function sendMoneyToClient(playerId)
    local did = getDiscordID(playerId)
    local charID = activeCharacters[playerId]
    if not charID or charID == "" then
        return
    end

    GetMoney(
        did,
        charID,
        function(m)
            dbQuery(
                string.format("SELECT id,balance FROM `%s` WHERE charid = ? AND type = 'checking' LIMIT 1", M.accts),
                {charID},
                function(rows)
                    local checkingBalance = nil
                    if rows and rows[1] and rows[1].balance ~= nil then
                        checkingBalance = tonumber(rows[1].balance) or 0
                    end

                    local function finishSend()
                        dbFetchScalar(
                            "SELECT name FROM user_characters WHERE charid = ? LIMIT 1",
                            {charID},
                            function(fullName)
                                local playerName = fullName or GetPlayerName(playerId) or "No Name"
                                TriggerClientEvent(
                                    "updateCashHUD",
                                    playerId,
                                    tonumber(m.cash) or 0,
                                    checkingBalance or 0,
                                    playerName
                                )
                            end
                        )
                    end

                    if checkingBalance == nil then
                        dbInsert(
                            string.format("INSERT INTO `%s` (discordid,charid,type,balance) VALUES (?,?,?,?),(?,?,?,?)", M.accts),
                            {did or "", charID, "checking", 0, did or "", charID, "savings", 0},
                            function()
                                checkingBalance = 0
                                finishSend()
                            end
                        )
                    else
                        finishSend()
                    end
                end
            )
        end
    )
end

local function withMoney(src, fn)
    local discordID = getDiscordID(src)
    local charID = activeCharacters[src]
    if discordID == "" or not charID then
        return TriggerClientEvent("chat:addMessage", src, {args = {"^1SYSTEM", "No character selected."}})
    end
    GetMoney(
        discordID,
        charID,
        function(data)
            fn(discordID, charID, data)
        end
    )
end

function addMoney(source, amount)
    if not source or not amount then return end
    withMoney(
        source,
        function(dID, cID, data)
            data.cash = (tonumber(data.cash) or 0) + tonumber(amount)
            UpdateMoney(
                dID,
                cID,
                data,
                function()
                    sendMoneyToClient(source)
                    if tonumber(amount) and amount >= 1e6 then
                        logLargeTransaction("addMoney", source, amount, "addMoney() export")
                    end
                end
            )
        end
    )
end

function deductMoney(source, amount)
    if not source or not amount then return end
    withMoney(
        source,
        function(dID, cID, data)
            data.cash = math.max(0, (tonumber(data.cash) or 0) - tonumber(amount))
            UpdateMoney(
                dID,
                cID,
                data,
                function()
                    sendMoneyToClient(source)
                    if tonumber(amount) and amount >= 1e6 then
                        logLargeTransaction("deductMoney", source, amount, "deductMoney() export")
                    end
                end
            )
        end
    )
end

function depositMoney(source, amount)
    if not amount then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Invalid amount."}})
    end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Amount must be greater than 0."}})
    end

    withMoney(
        source,
        function(dID, cID, data)
            if (tonumber(data.cash) or 0) < amount then
                return TriggerClientEvent(
                    "chat:addMessage",
                    source,
                    {args = {"^1SYSTEM", "Not enough cash to deposit."}}
                )
            end

            dbQuery(
                string.format("SELECT id,type,balance FROM `%s` WHERE (charid = ? OR discordid = ?) ORDER BY (charid = ?) DESC", M.accts),
                {cID, dID, cID},
                function(accts)
                    local function createAndDeposit()
                        dbInsert(
                            string.format("INSERT INTO `%s` (discordid,charid,type,balance) VALUES (?,?,?,?),(?,?,?,?)", M.accts),
                            {dID, cID, "checking", 0, dID, cID, "savings", 0},
                            function()
                                
                                dbQuery(
                                    string.format("SELECT id,type,balance FROM `%s` WHERE (charid = ? OR discordid = ?) ORDER BY (charid = ?) DESC", M.accts),
                                    {cID, dID, cID},
                                    function(accts2)
                                        if not accts2 or #accts2 == 0 then
                                            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No accounts found after creation."}})
                                        end
                                        local checking = nil
                                        for _, a in ipairs(accts2) do
                                            if tostring(a.type) == "checking" then
                                                checking = a
                                                break
                                            end
                                        end
                                        if not checking then
                                            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No checking account found (internal error)."}})
                                        end
                                        local newBalance = (tonumber(checking.balance) or 0) + amount
                                        dbExecute(
                                            string.format("UPDATE `%s` SET balance = ?, discordid = ?, charid = ? WHERE id = ?", M.accts),
                                            {newBalance, dID, cID, checking.id},
                                            function()
                                                data.cash = (tonumber(data.cash) or 0) - amount
                                                data.bank = newBalance
                                                UpdateMoney(
                                                    dID,
                                                    cID,
                                                    data,
                                                    function()
                                                        sendMoneyToClient(source)
                                                        TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "Deposited $" .. amount .. " to checking."}})
                                                        if amount >= 1e6 then
                                                            logLargeTransaction("depositMoney", source, amount, "depositMoney() export")
                                                        end
                                                    end
                                                )
                                            end
                                        )
                                    end
                                )
                            end
                        )
                    end

                    if not accts or #accts == 0 then
                        createAndDeposit()
                    else
                        local checking = nil
                        for _, a in ipairs(accts) do
                            if tostring(a.type) == "checking" then
                                checking = a
                                break
                            end
                        end
                        if not checking then
                            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No checking account found (internal error)."}})
                        end
                        local newBalance = (tonumber(checking.balance) or 0) + amount
                        dbExecute(
                            string.format("UPDATE `%s` SET balance = ?, discordid = ?, charid = ? WHERE id = ?", M.accts),
                            {newBalance, dID, cID, checking.id},
                            function()
                                data.cash = (tonumber(data.cash) or 0) - amount
                                data.bank = newBalance
                                UpdateMoney(
                                    dID,
                                    cID,
                                    data,
                                    function()
                                        sendMoneyToClient(source)
                                        TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "Deposited $" .. amount .. " to checking."}})
                                        if amount >= 1e6 then
                                            logLargeTransaction("depositMoney", source, amount, "depositMoney() export")
                                        end
                                    end
                                )
                            end
                        )
                    end
                end
            )
        end
    )
end

function withdrawMoney(source, amount)
    if not amount then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Invalid amount."}})
    end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Amount must be greater than 0."}})
    end

    local discordID = getDiscordID(source)
    local charID = activeCharacters[source]
    if not discordID or discordID == "" or not charID then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No character selected."}})
    end

    dbQuery(
        string.format("SELECT id,type,balance FROM `%s` WHERE (charid = ? OR discordid = ?) ORDER BY (charid = ?) DESC", M.accts),
        {charID, discordID, charID},
        function(accts)
            local function createAndWithdraw()
                dbInsert(
                    string.format("INSERT INTO `%s` (discordid,charid,type,balance) VALUES (?,?,?,?),(?,?,?,?)", M.accts),
                    {discordID, charID, "checking", 0, discordID, charID, "savings", 0},
                    function()
                        
                        dbQuery(
                            string.format("SELECT id,type,balance FROM `%s` WHERE (charid = ? OR discordid = ?) ORDER BY (charid = ?) DESC", M.accts),
                            {charID, discordID, charID},
                            function(accts2)
                                if not accts2 or #accts2 == 0 then
                                    return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No accounts found after creation."}})
                                end
                                local checking = nil
                                for _, a in ipairs(accts2) do
                                    if tostring(a.type) == "checking" then
                                        checking = a
                                        break
                                    end
                                end
                                if not checking then
                                    return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No checking account found (internal error)."}})
                                end
                                local current = tonumber(checking.balance) or 0
                                if current < amount then
                                    return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Not enough bank funds to withdraw."}})
                                end
                                local newBalance = current - amount
                                dbExecute(
                                    string.format("UPDATE `%s` SET balance = ?, discordid = ?, charid = ? WHERE id = ?", M.accts),
                                    {newBalance, discordID, charID, checking.id},
                                    function()
                                        withMoney(
                                            source,
                                            function(dID, cID, data)
                                                data.bank = newBalance
                                                data.cash = (tonumber(data.cash) or 0) + amount
                                                UpdateMoney(
                                                    dID,
                                                    cID,
                                                    data,
                                                    function()
                                                        sendMoneyToClient(source)
                                                        TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "Withdrew $" .. amount .. " from checking."}})
                                                        if amount >= 1e6 then
                                                            logLargeTransaction("withdrawMoney", source, amount, "withdrawMoney() export")
                                                        end
                                                    end
                                                )
                                            end
                                        )
                                    end
                                )
                            end
                        )
                    end
                )
            end

            if not accts or #accts == 0 then
                createAndWithdraw()
            else
                local checking = nil
                for _, a in ipairs(accts) do
                    if tostring(a.type) == "checking" then
                        checking = a
                        break
                    end
                end
                if not checking then
                    return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No checking account found (internal error)."}})
                end
                local current = tonumber(checking.balance) or 0
                if current < amount then
                    return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Not enough bank funds to withdraw."}})
                end
                local newBalance = current - amount
                dbExecute(
                    string.format("UPDATE `%s` SET balance = ?, discordid = ?, charid = ? WHERE id = ?", M.accts),
                    {newBalance, discordID, charID, checking.id},
                    function()
                        withMoney(
                            source,
                            function(dID, cID, data)
                                data.bank = newBalance
                                data.cash = (tonumber(data.cash) or 0) + amount
                                UpdateMoney(
                                    dID,
                                    cID,
                                    data,
                                    function()
                                        sendMoneyToClient(source)
                                        TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "Withdrew $" .. amount .. " from checking."}})
                                        if amount >= 1e6 then
                                            logLargeTransaction("withdrawMoney", source, amount, "withdrawMoney() export")
                                        end
                                    end
                                )
                            end
                        )
                    end
                )
            end
        end
    )
end

function transferMoney(source, target, amount)
    local senderID = getDiscordID(source)
    local senderChar = activeCharacters[source]
    local targetID = getDiscordID(target)
    local targetChar = activeCharacters[target]
    if senderID == "" or not senderChar or targetID == "" or not targetChar then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Discord ID or character missing for sender/target."}})
    end

    GetMoney(
        senderID,
        senderChar,
        function(sData)
            if (tonumber(sData.cash) or 0) < tonumber(amount) then
                return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Not enough cash to transfer."}})
            end
            GetMoney(
                targetID,
                targetChar,
                function(tData)
                    sData.cash = (tonumber(sData.cash) or 0) - tonumber(amount)
                    tData.cash = (tonumber(tData.cash) or 0) + tonumber(amount)

                    UpdateMoney(
                        senderID,
                        senderChar,
                        sData,
                        function()
                            sendMoneyToClient(source)
                        end
                    )
                    UpdateMoney(
                        targetID,
                        targetChar,
                        tData,
                        function()
                            sendMoneyToClient(target)
                            TriggerClientEvent("chat:addMessage", target, {args = {"^2SYSTEM", "You received $" .. amount}})
                            if amount >= 1e6 then
                                logLargeTransaction("transferMoney", source, amount, "to ID " .. tostring(target))
                            end
                        end
                    )
                    TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "You sent $" .. amount}})
                end
            )
        end
    )
end

function claimDailyReward(source, rewardAmount)
    withMoney(
        source,
        function(dID, cID, data)
            local now = os.time()
            if now - tonumber(data.last_daily or 0) < 86400 then
                return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Daily reward already claimed."}})
            end
            data.cash = (tonumber(data.cash) or 0) + tonumber(rewardAmount)
            data.last_daily = now
            UpdateMoney(
                dID,
                cID,
                data,
                function()
                    sendMoneyToClient(source)
                    TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "Daily reward: $" .. rewardAmount}})
                    if rewardAmount >= 1e6 then
                        logLargeTransaction("claimDailyReward", source, rewardAmount, "Daily reward")
                    end
                end
            )
        end
    )
end

function GetPlayerCharacter(source)
    return activeCharacters[source]
end

function GetPlayerCharacterName(source, callback)
    local discordID = getDiscordID(source)
    local charID = GetPlayerCharacter(source)
    if not discordID or discordID == "" or not charID then
        return callback("no_character", nil)
    end

    dbFetchScalar(
        "SELECT name FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1",
        {discordID, charID},
        function(name)
            if not name then
                return callback("not_found", nil)
            end
            callback(nil, name)
        end
    )
end

function GetPlayerMoney(source, callback)
    local discordID = getDiscordID(source)
    local charID = GetPlayerCharacter(source)
    if not discordID or discordID == "" or not charID then
        return callback("no_character", nil)
    end

    GetMoney(
        discordID,
        charID,
        function(data)
            callback(nil, {cash = data.cash or 0, bank = data.bank or 0})
        end
    )
end

AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    deferrals.defer()
    deferrals.done()
end)




RegisterCommand("addmoney", function(source, args)
    if source == 0 then return end
    isAdmin(source, function(ok)
        logAdminCommand("addmoney", source, args, ok)
        if not ok then
            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Permission denied."}})
        end
        local amt = tonumber(args[1])
        if not amt then
            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Usage: /addmoney [amount]"}})
        end
        addMoney(source, amt)
    end)
end, false)

RegisterCommand("deductmoney", function(source, args)
    if source == 0 then return end
    isAdmin(source, function(ok)
        logAdminCommand("deductmoney", source, args, ok)
        if not ok then
            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Permission denied."}})
        end
        local amt = tonumber(args[1])
        if not amt then
            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Usage: /deductmoney [amount]"}})
        end
        deductMoney(source, amt)
    end)
end, false)

RegisterCommand("deposit", function(source, args)
    local amount = tonumber(args[1])
    if not amount then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Usage: /deposit [amount]"}})
    end
    depositMoney(source, amount)
end, false)

RegisterCommand("withdraw", function(source, args)
    local amount = tonumber(args[1])
    if not amount then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Usage: /withdraw [amount]"}})
    end
    withdrawMoney(source, amount)
end, false)

RegisterCommand("transfer", function(source, args)
    local targetId = tonumber(args[1])
    local amount = tonumber(args[2])
    if not targetId or not amount then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Usage: /transfer [id] [amount]"}})
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
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No Discord ID found. Are you Discord-linked?"}})
    end
    dbQuery("SELECT charid, name FROM user_characters WHERE discordid = ?", {discordID}, function(rows)
        if not rows or #rows == 0 then
            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "You have no characters. Use /registerchar to create one."}})
        end
        local list = {}
        for _, row in ipairs(rows) do
            table.insert(list, row.charid .. ":" .. row.name)
        end
        TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "Your characters → " .. table.concat(list, ", ")}})
    end)
end, false)

RegisterCommand("selectchar", function(source, args)
    if source == 0 then return end
    local chosen = args[1]
    if not chosen then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Usage: /selectchar <charid>"}})
    end

    local discordID = getDiscordID(source)
    if discordID == "" then
        return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "No Discord ID found. Are you Discord-linked?"}})
    end

    dbQuery("SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ?", {discordID, chosen}, function(rows)
        if not rows or #rows == 0 then
            return TriggerClientEvent("chat:addMessage", source, {args = {"^1SYSTEM", "Character ID not found. Use /listchars to see yours."}})
        end

        activeCharacters[source] = chosen
        TriggerClientEvent("chat:addMessage", source, {args = {"^2SYSTEM", "Switched to character " .. chosen}})
        sendMoneyToClient(source)

        dbFetchScalar("SELECT active_department FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1", {discordID, chosen}, function(active_dept)
            TriggerClientEvent("hud:setDepartment", source, active_dept or "")
        end)
    end)
end, false)


lib = lib or {}
if lib and lib.callback and lib.callback.register then

lib.callback.register("az-fw-money:fetchCharacters", function(source)
    local ids = GetPlayerIdentifiers(source)
    local discordId
    for _, id in ipairs(ids) do
        if id:find("discord:") then
            discordId = id:gsub("discord:", "")
            break
        end
    end

    if not discordId then
        print(("[az-fw-money] No Discord ID found for src=%s"):format(source))
        return {}
    end

    local p = promise.new()
    MySQL.Async.fetchAll(
        "SELECT * FROM user_characters WHERE discordid = @discordid",
        {["@discordid"] = discordId},
        function(result)
            p:resolve(result or {})
        end
    )
    return Citizen.Await(p)
end)

end

RegisterNetEvent("az-fw-money:registerCharacter")
AddEventHandler("az-fw-money:registerCharacter", function(firstName, lastName)
    local src = source
    local discordID = getDiscordID(src)
    if discordID == "" then
        TriggerClientEvent("chat:addMessage", src, {args = {"^1SYSTEM", "Could not register character: no Discord ID found."}})
        return
    end

    local charID = tostring(os.time()) .. tostring(math.random(1000, 9999))
    local fullName = tostring(firstName) .. " " .. tostring(lastName or "")

    debugPrint(("registerCharacter: creating char %s for discord %s (player %d) name='%s'"):format(charID, discordID, src, fullName))

    dbInsert("INSERT INTO user_characters (discordid, charid, name, active_department) VALUES (?,?,?,?)", {discordID, charID, fullName, ""}, function(insertId)
        if not insertId then
            debugPrint(("registerCharacter: failed to INSERT user_characters for %s / %s"):format(discordID, charID))
            TriggerClientEvent("chat:addMessage", src, {args = {"^1SYSTEM", "Failed to register character. Check server logs."}})
            return
        end

        debugPrint(("registerCharacter: inserted user_characters (%s / %s)"):format(discordID, charID))

        dbInsert(
            string.format("INSERT INTO %s (discordid, charid, firstname, lastname, cash, bank, last_daily, card_status) VALUES (?,?,?,?,?,?,?,?)", M.money),
            {discordID, charID, firstName or "", lastName or "", 0, 0, 0, "active"},
            function(insertId2)
                if not insertId2 then
                    debugPrint(("registerCharacter: failed to INSERT econ_user_money for %s / %s"):format(discordID, charID))
                    TriggerClientEvent("chat:addMessage", src, {args = {"^1SYSTEM", "Failed to initialize character economy. Check server logs."}})
                    return
                end

                debugPrint(("registerCharacter: inserted econ_user_money for %s / %s"):format(discordID, charID))

                activeCharacters[src] = charID
                TriggerClientEvent("az-fw-money:characterRegistered", src, charID)
                sendMoneyToClient(src)
                TriggerClientEvent("hud:setDepartment", src, "")
                TriggerClientEvent("chat:addMessage", src, {args = {"^2SYSTEM", ("Character '%s' registered (ID %s)."):format(fullName, charID)}})

                if Config and Config.UseImperial == true then
                    local cadPayload = {
                        users_discordID = discordID,
                        Fname = firstName or "",
                        Mname = "",
                        Lname = lastName or "",
                        Birthdate = "2000-01-01",
                        gender = "Unknown",
                        race = "",
                        hairC = "",
                        eyeC = "",
                        height = "",
                        weight = "",
                        postal = "",
                        address = "",
                        city = "",
                        county = "",
                        phonenum = "",
                        dlstatus = "",
                        citizenid = charID
                    }

                    local ok, err = pcall(function()
                        if exports["ImperialCAD"] and type(exports["ImperialCAD"].NewCharacter) == "function" then
                            exports["ImperialCAD"]:NewCharacter(cadPayload, function(success, res)
                                if success then
                                    debugPrint(("ImperialCAD: NewCharacter succeeded for %s -> %s"):format(charID, json.encode(res)))
                                else
                                    debugPrint(("ImperialCAD: NewCharacter failed for %s -> %s"):format(charID, json.encode(res)))
                                end
                            end)
                        else
                            debugPrint("ImperialCAD export not found or resource unavailable; skipping CAD creation.")
                        end
                    end)

                    if not ok then
                        debugPrint("Error while attempting to call ImperialCAD NewCharacter export: " .. tostring(err or "unknown"))
                    end
                else
                    debugPrint("Config.UseImperial is false or not set => skipping ImperialCAD creation")
                end
            end
        )
    end)
end)

RegisterNetEvent("az-fw-money:requestMoney")
AddEventHandler("az-fw-money:requestMoney", function()
    local src = source
    sendMoneyToClient(src)
end)

local function fetchMoney(did, cid, cb)
    dbQuery(string.format("SELECT * FROM `%s` WHERE discordid = ? AND charid = ?", M.money), {did, cid}, function(res)
        if res and res[1] then
            return safeCb(cb, res[1])
        end

        dbInsert(string.format("INSERT INTO `%s` (discordid,charid,cash,bank,profile_picture) VALUES (?,?,?,?, '')", M.money), {did, cid, 0, 0}, function(_)
            dbQuery(string.format("SELECT * FROM `%s` WHERE discordid = ? AND charid = ?", M.money), {did, cid}, function(res2)
                safeCb(cb, res2 and res2[1] or {cash = 0, bank = 0})
            end)
        end)
    end)
end

local function fetchAccounts(did, cb)
    dbQuery(string.format("SELECT id,type,balance FROM `%s` WHERE discordid = ?", M.accts), {did}, function(accts)
        if not accts or #accts == 0 then
            dbInsert(string.format("INSERT INTO `%s` (discordid,type,balance) VALUES (?,?,?),(?,?,?)", M.accts),
                {did, "checking", 0, did, "savings", 0},
                function()
                    dbQuery(string.format("SELECT id,type,balance FROM `%s` WHERE discordid = ?", M.accts), {did}, function(accts2)
                        safeCb(cb, accts2 or {})
                    end)
                end
            )
        else
            for _, acct in ipairs(accts) do
                if acct.type == "savings" then
                    local rate = SAVINGS_APR / 365
                    acct.apr = SAVINGS_APR
                    acct.daily_interest = (tonumber(acct.balance) or 0) * rate
                end
            end
            safeCb(cb, accts)
        end
    end)
end

RegisterNetEvent("az-fw-money:selectCharacter")
AddEventHandler("az-fw-money:selectCharacter", function(charID)
    local src = source
    local did = getDiscordID(src)
    if not did or did == "" then
        return
    end

    dbQuery("SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ?", {did, charID}, function(rows)
        if rows and #rows > 0 then
            activeCharacters[src] = charID
            sendMoneyToClient(src)
            dbFetchScalar("SELECT active_department FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1", {did, charID}, function(active_dept)
                TriggerClientEvent("hud:setDepartment", src, active_dept or "")
            end)
            TriggerClientEvent("az-fw-money:characterSelected", src, charID)
        end
    end)
end)

exports("getPlayerJob", function(source)
    if not source or source == 0 then
        return nil
    end

    local discordID = getDiscordID(source)
    local charID = activeCharacters[source]

    if not discordID or discordID == "" or not charID then
        return nil
    end

    local jobValue = nil
    local done = false
    dbFetchScalar("SELECT active_department FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1", {discordID, charID}, function(val)
        jobValue = val
        done = true
    end)
    local tick = 0
    while not done and tick < 50 do
        Citizen.Wait(10)
        tick = tick + 1
    end
    return jobValue or nil
end)

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

                dbFetchScalar("SELECT active_department FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1", {discordID, charID}, function(active_department)
                    if not active_department or active_department == "" then
                        print((" → char %s has no active_department set, skipping"):format(charID))
                        return
                    end
                    local dept = active_department

                    local lookupIds = {discordID}
                    for _, rid in ipairs(roles) do
                        table.insert(lookupIds, rid)
                    end

                    local placeholders = table.concat((function()
                        local t = {}
                        for i = 1, #lookupIds do t[i] = "?" end
                        return t
                    end)(), ",")

                    local sql = ([[ 
                        SELECT paycheck 
                          FROM econ_departments 
                         WHERE department = ? 
                           AND discordid IN (%s) 
                         LIMIT 1
                    ]]):format(placeholders)

                    local params = {dept}
                    for _, id in ipairs(lookupIds) do table.insert(params, id) end

                    dbFetchScalar(sql, params, function(paycheck)
                        print(("  ↳ lookup dept='%s' ids=[%s] → %s"):format(dept, table.concat(lookupIds, ","), tostring(paycheck)))
                        local amt = tonumber(paycheck) or 0
                        if amt > 0 then
                            print(("  ↳ Paying $%d to %d"):format(amt, src))
                            addMoney(src, amt)
                            TriggerClientEvent("chat:addMessage", src, {args = {"^2PAYCHECK", "Hourly pay: $" .. amt}})
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

AddEventHandler("playerDropped", function(reason)
    if activeCharacters[source] ~= nil then
        activeCharacters[source] = nil
    end
end)




exports("addMoney", addMoney)
exports("deductMoney", deductMoney)
exports("depositMoney", depositMoney)
exports("withdrawMoney", withdrawMoney)
exports("transferMoney", transferMoney)
exports("GetMoney", GetMoney)
exports("UpdateMoney", UpdateMoney)
exports("sendMoneyToClient", sendMoneyToClient)
exports("claimDailyReward", claimDailyReward)
exports("getDiscordID", getDiscordID)
exports("isAdmin", isAdmin)
exports("GetPlayerCharacter", GetPlayerCharacter)
exports("GetPlayerCharacterName", GetPlayerCharacterName)
exports("GetPlayerMoney", GetPlayerMoney)
exports("logAdminCommand", logAdminCommand)