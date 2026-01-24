local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
Config.Debug = Config.Debug or false
Config.Discord = Config.Discord or {}
Config.PaycheckIntervalMinutes = Config.PaycheckIntervalMinutes or 60

Config.Discord.BotToken   = Config.Discord.BotToken   or GetConvar("DISCORD_BOT_TOKEN", "")
Config.Discord.WebhookURL = Config.Discord.WebhookURL or GetConvar("DISCORD_WEBHOOK_URL", "")
Config.Discord.GuildId    = Config.Discord.GuildId    or GetConvar("DISCORD_GUILD_ID", "")

Config.AdminRoleId        = tostring(Config.AdminRoleId or GetConvar("AZFW_ADMIN_ROLE_ID", "") or "")
Config.AdminAcePermission = Config.AdminAcePermission or "adminmenu.use"

local T = {
  money = "econ_user_money",
  accts = "econ_accounts",
  dept  = "econ_departments",
}

local SAVINGS_APR = 0.05

local activeCharacters = {}
local activeCharByDiscord = {}

local function dprint(...)
  if not Config.Debug then return end
  local args = { ... }
  for i=1,#args do args[i] = tostring(args[i]) end
  print(("^3[%s]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local function safeCb(cb, ...)
  if type(cb) == "function" then
    return cb(...)
  end
end

local function trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function resolveSourceId(arg)
  local s = tonumber(arg)
  if s and s > 0 then return s end
  local g = tonumber(_G.source)
  if g and g > 0 then return g end
  return nil
end

local function stripSelf(...)
  local a = { ... }
  local t = type(a[1])
  if t == "table" or t == "userdata" then
    table.remove(a, 1)
  end
  return table.unpack(a)
end

local function hasOx()
  return exports.oxmysql ~= nil
end

local function oxQuery(query, params, cb)
  params = params or {}
  if not hasOx() or not exports.oxmysql.query then
    dprint("oxmysql not available: query")
    return safeCb(cb, {})
  end
  exports.oxmysql:query(query, params, function(res)
    safeCb(cb, res or {})
  end)
end

local function oxExecute(query, params, cb)
  params = params or {}
  if not hasOx() or not exports.oxmysql.execute then
    dprint("oxmysql not available: execute")
    return safeCb(cb, 0)
  end
  exports.oxmysql:execute(query, params, function(res)
    safeCb(cb, res or 0)
  end)
end

local function oxInsert(query, params, cb)
  params = params or {}
  if not hasOx() or not exports.oxmysql.insert then
    dprint("oxmysql not available: insert")
    return safeCb(cb, nil)
  end
  exports.oxmysql:insert(query, params, function(insertId)
    safeCb(cb, insertId)
  end)
end

local function oxScalar(query, params, cb)
  oxQuery(query, params, function(rows)
    if rows and rows[1] then
      for _, v in pairs(rows[1]) do
        return safeCb(cb, v)
      end
    end
    safeCb(cb, nil)
  end)
end

if MySQL == nil then MySQL = {} end
if MySQL.Async == nil then MySQL.Async = {} end
if type(MySQL.Async.fetchAll) ~= "function" then
  MySQL.Async.fetchAll = function(query, params, cb)
    oxQuery(query, params, cb)
  end
end
if type(MySQL.Async.execute) ~= "function" then
  MySQL.Async.execute = function(query, params, cb)
    oxExecute(query, params, cb)
  end
end
if type(MySQL.Async.insert) ~= "function" then
  MySQL.Async.insert = function(query, params, cb)
    oxInsert(query, params, cb)
  end
end
if type(MySQL.Async.scalar) ~= "function" then
  MySQL.Async.scalar = function(query, params, cb)
    oxScalar(query, params, cb)
  end
end

local function getDiscordID(src)
  src = tonumber(src or 0) or 0
  if src <= 0 then return "" end

  local ids = GetPlayerIdentifiers(src)
  if type(ids) ~= "table" then return "" end

  for _, id in ipairs(ids) do
    if type(id) == "string" and id:sub(1,8) == "discord:" then
      return id:sub(9)
    end
  end
  return ""
end

local roleCache = {}
local ROLE_TTL_MS = 60 * 1000

local function getDiscordRoleList(src, cb)
  if type(cb) ~= "function" then return end

  src = resolveSourceId(src)
  if not src then return cb("invalid_source", nil) end

  local discordID = getDiscordID(src)
  if discordID == "" then return cb("no_discord_id", nil) end

  local now = GetGameTimer()
  local c = roleCache[discordID]
  if c and c.exp and c.exp > now and type(c.roles) == "table" then
    return cb(nil, c.roles)
  end

  local guildId  = Config.Discord.GuildId or ""
  local botToken = Config.Discord.BotToken or ""
  if guildId == "" or botToken == "" then
    return cb("config_error", nil)
  end

  local url = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(guildId, discordID)

  PerformHttpRequest(url, function(status, body)
    if status ~= 200 or not body or body == "" then
      return cb("http_" .. tostring(status), nil)
    end
    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" or type(data.roles) ~= "table" then
      return cb("bad_json", nil)
    end

    roleCache[discordID] = { roles = data.roles, exp = GetGameTimer() + ROLE_TTL_MS }
    cb(nil, data.roles)
  end, "GET", "", {
    ["Authorization"] = "Bot " .. botToken,
    ["Content-Type"]  = "application/json"
  })
end

local function isAdmin_impl(playerSrc, cb)
  playerSrc = resolveSourceId(playerSrc)
  if not playerSrc then
    return safeCb(cb, false, "invalid_source")
  end

  if playerSrc == 0 then
    return safeCb(cb, true, "console")
  end

  local acePerm = Config.AdminAcePermission or "adminmenu.use"
  local aceAllowed = IsPlayerAceAllowed(playerSrc, acePerm)
  if aceAllowed then
    return safeCb(cb, true, "ace")
  end

  local wanted = tostring(Config.AdminRoleId or "")
  if wanted == "" or wanted == "nil" then
    return safeCb(cb, false, "no_role_config")
  end

  getDiscordRoleList(playerSrc, function(err, roles)
    if err or type(roles) ~= "table" then
      return safeCb(cb, false, err or "role_fetch_failed")
    end
    for _, roleId in ipairs(roles) do
      if tostring(roleId) == wanted then
        return safeCb(cb, true, "role")
      end
    end
    return safeCb(cb, false, "no_match")
  end)
end

local function isAdmin_export(...)
  local src, cb = stripSelf(...)

  if type(src) == "function" then
    cb = src
    src = resolveSourceId(nil)
  end

  if src == nil and cb == nil then
    src = resolveSourceId(nil)
  end

  if type(cb) == "function" then
    return isAdmin_impl(src, cb)
  end

  local p = promise.new()
  local done = false
  isAdmin_impl(src, function(ok)
    if done then return end
    done = true
    p:resolve(ok == true)
  end)

  SetTimeout(1500, function()
    if done then return end
    done = true

    local s = resolveSourceId(src)
    if s and s > 0 then
      local acePerm = Config.AdminAcePermission or "adminmenu.use"
      return p:resolve(IsPlayerAceAllowed(s, acePerm) == true)
    end
    p:resolve(false)
  end)

  return Citizen.Await(p)
end

local function sendWebhookLog(message)
  local url = Config.Discord.WebhookURL or ""
  if url == "" then return end

  local payload = { username = "Azure Logger", content = tostring(message) }
  PerformHttpRequest(url, function(statusCode)
    if Config.Debug and statusCode ~= 204 and statusCode ~= 200 then
      dprint("Webhook error:", statusCode)
    end
  end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

local function logAdminCommand(commandName, src, args, success)
  local playerName = (type(src) == "number" and GetPlayerName(src)) or "Unknown"
  local statusIcon = success and "✅ Allowed" or "❌ Denied"
  local argsStr = (type(args) == "table" and table.concat(args, " ")) or tostring(args or "")
  local msg = ("**Admin Command:** `%s`\n**Player:** %s (ID %s)\n**Status:** %s\n**Args:** %s"):format(
    tostring(commandName), tostring(playerName), tostring(src), statusIcon, argsStr
  )
  sendWebhookLog(msg)
end

local function logLargeTransaction(txType, src, amount, reason)
  local playerName = (type(src) == "number" and GetPlayerName(src)) or "Unknown"
  local msg = (":moneybag: **Large Transaction** `%s`\n**Player:** %s (ID %s)\n**Amount:** $%s\n**Reason:** %s"):format(
    tostring(txType), tostring(playerName), tostring(src), tostring(amount), tostring(reason or "")
  )
  sendWebhookLog(msg)
end

local function GetMoney(discordID, charID, callback)
  if type(callback) ~= "function" then return end

  oxQuery(("SELECT cash, bank, last_daily FROM `%s` WHERE discordid=? AND charid=? LIMIT 1"):format(T.money),
    { discordID, charID },
    function(rows)
      if rows and rows[1] then
        return callback(rows[1])
      end

      oxScalar("SELECT name FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
        { discordID, charID },
        function(fullName)
          local first, last = "", ""
          if type(fullName) == "string" then
            local f, l = fullName:match("^(%S+)%s+(%S+)$")
            first, last = f or "", l or ""
          end

          oxInsert(("INSERT INTO `%s` (discordid,charid,firstname,lastname,cash,bank,last_daily) VALUES (?,?,?,?,?,?,?)"):format(T.money),
            { discordID, charID, first, last, 0, 0, 0 },
            function()
              callback({ cash = 0, bank = 0, last_daily = 0 })
            end
          )
        end
      )
    end
  )
end

local function UpdateMoney(discordID, charID, data, cb)
  oxExecute(("UPDATE `%s` SET cash=?, bank=?, last_daily=? WHERE discordid=? AND charid=?"):format(T.money),
    { tonumber(data.cash) or 0, tonumber(data.bank) or 0, tonumber(data.last_daily) or 0, discordID, charID },
    function(affected)
      safeCb(cb, affected)
    end
  )
end

local function ensureChecking(discordID, charID, cb)

  oxQuery(("SELECT id, balance FROM `%s` WHERE charid=? AND type='checking' LIMIT 1"):format(T.accts),
    { charID },
    function(rows)
      if rows and rows[1] and rows[1].id then
        return cb(rows[1].id, tonumber(rows[1].balance) or 0)
      end

      oxInsert(("INSERT INTO `%s` (discordid,charid,type,balance) VALUES (?,?,?,?),(?,?,?,?)"):format(T.accts),
        { discordID, charID, "checking", 0, discordID, charID, "savings", 0 },
        function()
          oxQuery(("SELECT id, balance FROM `%s` WHERE charid=? AND type='checking' LIMIT 1"):format(T.accts),
            { charID },
            function(rows2)
              if rows2 and rows2[1] and rows2[1].id then
                return cb(rows2[1].id, tonumber(rows2[1].balance) or 0)
              end
              cb(nil, 0)
            end
          )
        end
      )
    end
  )
end

local function getFullName(charID, fallbackSrc, cb)
  oxScalar("SELECT name FROM user_characters WHERE charid=? LIMIT 1", { charID }, function(name)
    if name and name ~= "" then return cb(name) end
    cb((fallbackSrc and GetPlayerName(fallbackSrc)) or "No Name")
  end)
end

local function sendMoneyToClient(playerId)
  local src = resolveSourceId(playerId)
  if not src then return end

  local did = getDiscordID(src)
  local charID = activeCharacters[src]
  if not charID or charID == "" or did == "" then return end

  GetMoney(did, charID, function(m)
    ensureChecking(did, charID, function(_checkingId, checkingBalance)
      getFullName(charID, src, function(playerName)
        TriggerClientEvent("updateCashHUD", src, tonumber(m.cash) or 0, tonumber(checkingBalance) or 0, playerName)
      end)
    end)
  end)
end

local function withMoney(src, fn)
  src = resolveSourceId(src)
  if not src then return end

  local discordID = getDiscordID(src)
  local charID = activeCharacters[src]
  if discordID == "" or not charID then
    TriggerClientEvent('ox_lib:notify', src, { title="Account", description="No character selected.", type="error" })
    return
  end

  GetMoney(discordID, charID, function(data)
    fn(discordID, charID, data, src)
  end)
end

local function addMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = tonumber(amount)
  if not src or not amount then return false end

  withMoney(src, function(dID, cID, data)
    data.cash = (tonumber(data.cash) or 0) + amount
    UpdateMoney(dID, cID, data, function()
      sendMoneyToClient(src)
      if amount >= 1e6 then logLargeTransaction("addMoney", src, amount, "addMoney() export") end
    end)
  end)

  return true
end

local function deductMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = tonumber(amount)
  if not src or not amount then return false end

  withMoney(src, function(dID, cID, data)
    data.cash = math.max(0, (tonumber(data.cash) or 0) - amount)
    UpdateMoney(dID, cID, data, function()
      sendMoneyToClient(src)
      if amount >= 1e6 then logLargeTransaction("deductMoney", src, amount, "deductMoney() export") end
    end)
  end)

  return true
end

local function depositMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = math.floor(tonumber(amount) or 0)
  if not src or amount <= 0 then return false end

  withMoney(src, function(dID, cID, data)
    if (tonumber(data.cash) or 0) < amount then
      TriggerClientEvent('ox_lib:notify', src, { title="Bank", description="Not enough cash to deposit.", type="error" })
      return
    end

    ensureChecking(dID, cID, function(checkId, bal)
      if not checkId then
        TriggerClientEvent('ox_lib:notify', src, { title="Bank", description="Checking account missing.", type="error" })
        return
      end

      local newBalance = (tonumber(bal) or 0) + amount
      oxExecute(("UPDATE `%s` SET balance=?, discordid=?, charid=? WHERE id=?"):format(T.accts),
        { newBalance, dID, cID, checkId },
        function()
          data.cash = (tonumber(data.cash) or 0) - amount
          data.bank = newBalance
          UpdateMoney(dID, cID, data, function()
            sendMoneyToClient(src)
            if amount >= 1e6 then logLargeTransaction("depositMoney", src, amount, "depositMoney() export") end
          end)
        end
      )
    end)
  end)

  return true
end

local function withdrawMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = math.floor(tonumber(amount) or 0)
  if not src or amount <= 0 then return false end

  local did = getDiscordID(src)
  local cid = activeCharacters[src]
  if did == "" or not cid then return false end

  ensureChecking(did, cid, function(checkId, bal)
    if not checkId then return false end
    local current = tonumber(bal) or 0
    if current < amount then
      TriggerClientEvent('ox_lib:notify', src, { title="Bank", description="Not enough bank funds to withdraw.", type="error" })
      return
    end

    local newBalance = current - amount
    oxExecute(("UPDATE `%s` SET balance=?, discordid=?, charid=? WHERE id=?"):format(T.accts),
      { newBalance, did, cid, checkId },
      function()
        withMoney(src, function(dID, cID, data)
          data.bank = newBalance
          data.cash = (tonumber(data.cash) or 0) + amount
          UpdateMoney(dID, cID, data, function()
            sendMoneyToClient(src)
            if amount >= 1e6 then logLargeTransaction("withdrawMoney", src, amount, "withdrawMoney() export") end
          end)
        end)
      end
    )
  end)

  return true
end

local function transferMoney_export(...)
  local a, b, c = stripSelf(...)
  local src, target, amount

  if c == nil then

    src = resolveSourceId(nil)
    target = resolveSourceId(a)
    amount = b
  else

    src = resolveSourceId(a)
    target = resolveSourceId(b)
    amount = c
  end

  amount = tonumber(amount)
  if not src or not target or not amount or amount <= 0 then return false end

  local senderID = getDiscordID(src)
  local senderChar = activeCharacters[src]
  local targetID = getDiscordID(target)
  local targetChar = activeCharacters[target]
  if senderID == "" or not senderChar or targetID == "" or not targetChar then
    return false
  end

  GetMoney(senderID, senderChar, function(sData)
    if (tonumber(sData.cash) or 0) < amount then
      TriggerClientEvent('ox_lib:notify', src, { title="Transfer", description="Not enough cash to transfer.", type="error" })
      return
    end

    GetMoney(targetID, targetChar, function(tData)
      sData.cash = (tonumber(sData.cash) or 0) - amount
      tData.cash = (tonumber(tData.cash) or 0) + amount

      UpdateMoney(senderID, senderChar, sData, function()
        sendMoneyToClient(src)
      end)
      UpdateMoney(targetID, targetChar, tData, function()
        sendMoneyToClient(target)
      end)

      if amount >= 1e6 then
        logLargeTransaction("transferMoney", src, amount, "to ID " .. tostring(target))
      end
    end)
  end)

  return true
end

local function claimDailyReward_export(...)
  local a, b = stripSelf(...)
  local src, reward

  if b == nil then
    src = resolveSourceId(nil)
    reward = a
  else
    src = resolveSourceId(a)
    reward = b
  end

  reward = tonumber(reward) or 500
  if not src then return false end

  withMoney(src, function(dID, cID, data)
    local now = os.time()
    if (now - tonumber(data.last_daily or 0)) < 86400 then
      TriggerClientEvent("chat:addMessage", src, { args = {"^1SYSTEM", "Daily reward already claimed."} })
      return
    end

    data.cash = (tonumber(data.cash) or 0) + reward
    data.last_daily = now

    UpdateMoney(dID, cID, data, function()
      sendMoneyToClient(src)
      if reward >= 1e6 then logLargeTransaction("claimDailyReward", src, reward, "Daily reward") end
    end)
  end)

  return true
end

local function GetPlayerCharacter_export(...)
  local playerId = stripSelf(...)
  local id = resolveSourceId(playerId)
  if not id then return nil end
  return activeCharacters[id] or nil
end
local function GetPlayerCharacterName_export(...)
  local a, b = stripSelf(...)
  local src, cb

  if type(a) == "function" and b == nil then

    src = resolveSourceId(nil)
    cb = a
  else
    src = resolveSourceId(a)
    cb = b
  end

  if type(cb) ~= "function" then return end

  if not src then
    return safeCb(cb, "invalid_source", nil)
  end

  local did = getDiscordID(src)
  local cid = activeCharacters[src]

  if did == "" or not cid then
    return safeCb(cb, "no_character", nil)
  end

  local ok, perr = pcall(function()
    oxScalar(
      "SELECT name FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
      { did, cid },
      function(name)
        if not name then
          return safeCb(cb, "not_found", nil)
        end
        return safeCb(cb, nil, name)
      end
    )
  end)

  if not ok then
    return safeCb(cb, "db_error", nil)
  end
end

local function GetPlayerCharacterNameSync_export(...)
  local src = stripSelf(...)
  src = resolveSourceId(src)
  if not src then return nil, "invalid_source" end

  local did = getDiscordID(src)
  local cid = activeCharacters[src]
  if did == "" or not cid then
    return nil, "no_character"
  end

  local p = promise.new()
  local done = false

  oxScalar(
    "SELECT name FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
    { did, cid },
    function(name)
      if done then return end
      done = true
      p:resolve(name)
    end
  )

  SetTimeout(1500, function()
    if done then return end
    done = true
    p:resolve(nil)
  end)

  local name = Citizen.Await(p)
  if not name or tostring(name) == "" then
    return nil, "not_found"
  end

  return tostring(name), nil
end

exports("GetPlayerCharacterNameSync", GetPlayerCharacterNameSync_export)

local function GetPlayerMoney_export(...)
  local a, b = stripSelf(...)
  local src, cb
  if type(a) == "function" and b == nil then
    src = resolveSourceId(nil)
    cb = a
  else
    src = resolveSourceId(a)
    cb = b
  end

  if not src then return safeCb(cb, "invalid_source", nil) end

  local did = getDiscordID(src)
  local cid = activeCharacters[src]
  if did == "" or not cid then
    return safeCb(cb, "no_character", nil)
  end

  GetMoney(did, cid, function(data)
    if not data then
      return safeCb(cb, "no_data", { cash=0, bank=0 })
    end
    safeCb(cb, nil, { cash = data.cash or 0, bank = data.bank or 0 })
  end)
end

local function GetPlayerJob_async(src, cb)
  src = resolveSourceId(src)
  if not src then return safeCb(cb, "invalid_source", nil) end

  local did = getDiscordID(src)
  local cid = activeCharacters[src]
  if did == "" or not cid then
    return safeCb(cb, "no_character", nil)
  end

  oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
    { did, cid },
    function(job)
      safeCb(cb, nil, job or "")
    end
  )
end

local function getPlayerJob_export(...)
  local src = stripSelf(...)
  src = resolveSourceId(src)
  if not src then return nil end

  local p = promise.new()
  local done = false

  GetPlayerJob_async(src, function(_err, job)
    done = true
    p:resolve(job)
  end)

  SetTimeout(800, function()
    if done then return end
    done = true
    p:resolve(nil)
  end)

  return Citizen.Await(p)
end

RegisterCommand("addmoney", function(src, args)
  if src == 0 then return end
  isAdmin_export(src, function(ok)
    logAdminCommand("addmoney", src, args, ok)
    if not ok then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Permission denied."} }) end
    local amt = tonumber(args[1])
    if not amt then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /addmoney [amount]"} }) end
    addMoney_export(src, amt)
  end)
end, false)

RegisterCommand("deductMoney", function(src, args)
  if src == 0 then return end
  isAdmin_export(src, function(ok)
    logAdminCommand("deductMoney", src, args, ok)
    if not ok then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Permission denied."} }) end
    local amt = tonumber(args[1])
    if not amt then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /deductMoney [amount]"} }) end
    deductMoney_export(src, amt)
  end)
end, false)

RegisterCommand("deposit", function(src, args)
  local amount = tonumber(args[1])
  if not amount then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /deposit [amount]"} }) end
  depositMoney_export(src, amount)
end, false)

RegisterCommand("withdraw", function(src, args)
  local amount = tonumber(args[1])
  if not amount then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /withdraw [amount]"} }) end
  withdrawMoney_export(src, amount)
end, false)

RegisterCommand("transfer", function(src, args)
  local targetId = tonumber(args[1])
  local amount = tonumber(args[2])
  if not targetId or not amount then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /transfer [id] [amount]"} })
  end
  transferMoney_export(src, targetId, amount)
end, false)

RegisterCommand("dailyreward", function(src, args)
  if src == 0 then return end
  local reward = tonumber(args[1]) or 500
  claimDailyReward_export(src, reward)
end, false)

RegisterCommand("listchars", function(src)
  if src == 0 then return end
  local did = getDiscordID(src)
  if did == "" then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","No Discord ID found. Are you Discord-linked?"} })
  end

  oxQuery("SELECT charid, name FROM user_characters WHERE discordid=?", { did }, function(rows)
    if not rows or #rows == 0 then
      return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","You have no characters. Use /registerchar to create one."} })
    end
    local list = {}
    for _, r in ipairs(rows) do list[#list+1] = (tostring(r.charid) .. ":" .. tostring(r.name)) end
    TriggerClientEvent("chat:addMessage", src, { args={"^2SYSTEM","Your characters → " .. table.concat(list, ", ")} })
  end)
end, false)

RegisterCommand("selectchar", function(src, args)
  if src == 0 then return end
  local chosen = args[1]
  if not chosen then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /selectchar <charid>"} })
  end

  local did = getDiscordID(src)
  if did == "" then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","No Discord ID found. Are you Discord-linked?"} })
  end

  oxQuery("SELECT 1 FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, chosen }, function(rows)
    if not rows or #rows == 0 then
      return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Character ID not found. Use /listchars to see yours."} })
    end

    activeCharacters[src] = chosen
    activeCharByDiscord[did] = chosen
    sendMoneyToClient(src)

    oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, chosen }, function(active_dept)
      TriggerClientEvent("hud:setDepartment", src, active_dept or "")
    end)

    TriggerClientEvent("chat:addMessage", src, { args={"^2SYSTEM","Switched to character " .. tostring(chosen)} })
  end)
end, false)

RegisterNetEvent("az-fw-money:registerCharacter", function(firstName, lastName)
  local src = source
  local did = getDiscordID(src)
  if did == "" then
    TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Could not register character: no Discord ID found."} })
    return
  end

  local charID = tostring(os.time()) .. tostring(math.random(1000, 9999))
  local fullName = trim(firstName) .. " " .. trim(lastName)

  oxInsert("INSERT INTO user_characters (discordid,charid,name,active_department) VALUES (?,?,?,?)",
    { did, charID, trim(fullName), "" },
    function(ok)
      if not ok then
        TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Failed to register character. Check server logs."} })
        return
      end

      oxInsert(("INSERT INTO `%s` (discordid,charid,firstname,lastname,cash,bank,last_daily,card_status) VALUES (?,?,?,?,?,?,?,?)"):format(T.money),
        { did, charID, trim(firstName), trim(lastName), 0, 0, 0, "active" },
        function()
          activeCharacters[src] = charID
          activeCharByDiscord[did] = charID
          TriggerClientEvent("az-fw-money:characterRegistered", src, charID)
          sendMoneyToClient(src)
          TriggerClientEvent("hud:setDepartment", src, "")
          TriggerClientEvent("chat:addMessage", src, { args={"^2SYSTEM", ("Character '%s' registered (ID %s)."):format(trim(fullName), charID)} })
        end
      )
    end
  )
end)

RegisterNetEvent("az-fw-money:requestMoney", function()
  sendMoneyToClient(source)
end)

RegisterNetEvent("az-fw-money:selectCharacter", function(charID)
  local src = source
  local did = getDiscordID(src)
  if did == "" then return end

  oxQuery("SELECT 1 FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, charID }, function(rows)
    if rows and #rows > 0 then
      activeCharacters[src] = charID
      activeCharByDiscord[did] = charID
      sendMoneyToClient(src)

      oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, charID }, function(active_dept)
        TriggerClientEvent("hud:setDepartment", src, active_dept or "")
      end)

      TriggerClientEvent("az-fw-money:characterSelected", src, charID)
    end
  end)
end)

RegisterNetEvent("az-fw-money:RequestPlayerCharacter", function()
  local src = source
  TriggerClientEvent("az-fw-money:ReceivePlayerCharacter", src, activeCharacters[src] or nil)
end)

AddEventHandler("playerDropped", function()
  local src = source
  local did = getDiscordID(src)
  if did ~= "" and activeCharByDiscord[did] == activeCharacters[src] then
    activeCharByDiscord[did] = nil
  end
  activeCharacters[src] = nil
end)

CreateThread(function()
  local interval = (tonumber(Config.PaycheckIntervalMinutes) or 60) * 60 * 1000
  print(("[Az-Framework] Paycheck thread started. Interval=%s minutes."):format(tostring(Config.PaycheckIntervalMinutes or 60)))

  while true do
    Wait(interval)

    for src, charID in pairs(activeCharacters) do
      local discordID = getDiscordID(src)
      if discordID == "" then goto continue end

      getDiscordRoleList(src, function(err, roles)
        if err or type(roles) ~= "table" then return end

        oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
          { discordID, charID },
          function(active_department)
            if not active_department or active_department == "" then return end

            local lookupIds = { discordID }
            for _, rid in ipairs(roles) do lookupIds[#lookupIds+1] = rid end

            local marks = {}
            for i=1,#lookupIds do marks[i] = "?" end

            local sql = (("SELECT paycheck FROM `%s` WHERE department=? AND discordid IN (%s) LIMIT 1")
              :format(T.dept, table.concat(marks, ",")))

            local params = { active_department }
            for _, id in ipairs(lookupIds) do params[#params+1] = id end

            oxScalar(sql, params, function(paycheck)
              local amt = tonumber(paycheck) or 0
              if amt > 0 then
                addMoney_export(src, amt)
                TriggerClientEvent("chat:addMessage", src, { args={"^2PAYCHECK","Hourly pay: $" .. tostring(amt)} })
              end
            end)
          end
        )
      end)

      ::continue::
    end
  end
end)

lib = lib or {}
if lib.callback and lib.callback.register then
  lib.callback.register("az-fw-money:fetchCharacters", function(source)
    local discordId = getDiscordID(source)
    if discordId == "" then return {} end

    local p = promise.new()
    MySQL.Async.fetchAll("SELECT * FROM user_characters WHERE discordid = ?", { discordId }, function(result)
      p:resolve(result or {})
    end)
    return Citizen.Await(p)
  end)

  lib.callback.register("az-fw-money:GetPlayerCharacterForSource", function(source)
    return activeCharacters[source] or nil
  end)

  lib.callback.register("az-fw-money:GetPlayerCharacterByDiscord", function(_, discordId)
    discordId = tostring(discordId or "")
    if discordId == "" then return nil end
    if activeCharByDiscord[discordId] then return activeCharByDiscord[discordId] end

    local p = promise.new()
    MySQL.Async.fetchAll("SELECT charid FROM user_characters WHERE discordid = ? LIMIT 1", { discordId }, function(rows)
      if rows and rows[1] and rows[1].charid then
        p:resolve(rows[1].charid)
      else
        p:resolve(nil)
      end
    end)
    return Citizen.Await(p)
  end)
end

exports("addMoney", addMoney_export)
exports("deductMoney", deductMoney_export)
exports("depositMoney", depositMoney_export)
exports("withdrawMoney", withdrawMoney_export)
exports("transferMoney", transferMoney_export)
exports("claimDailyReward", claimDailyReward_export)

exports("GetMoney", GetMoney)
exports("UpdateMoney", UpdateMoney)
exports("sendMoneyToClient", function(...) local src = stripSelf(...) return sendMoneyToClient(src) end)

exports("getDiscordID", function(...) local src = stripSelf(...) return getDiscordID(resolveSourceId(src) or src) end)
exports("isAdmin", isAdmin_export)

exports("GetPlayerCharacter", GetPlayerCharacter_export)
exports("GetPlayerCharacterName", GetPlayerCharacterName_export)
exports("GetPlayerMoney", GetPlayerMoney_export)

exports("logAdminCommand", function(...) local a,b,c,d = stripSelf(...) return logAdminCommand(a,b,c,d) end)

exports("getPlayerJob", getPlayerJob_export)
