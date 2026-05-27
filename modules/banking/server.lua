local Config = (Config and Config.Banking) or {}
if Config.Enabled == false then return end

local DEBUG = (GetConvarInt and (GetConvarInt('az_econ_debug', 1) == 1)) or true

local function parseAmount(x)
  local s = tostring(x or "")
  s = s:gsub("%s+", "")
       :gsub("[,%$€£_]", "")
       :gsub("[^%d%.]", "")
  local n = tonumber(s)
  return math.floor(n or 0)
end

local function _dump(val, depth, seen)
  depth = depth or 2
  seen = seen or {}
  local t = type(val)
  if t ~= "table" then
    if t == "string" then return string.format("%q", val) end
    return tostring(val)
  end
  if seen[val] then return "<rec>" end
  if depth <= 0 then return "{...}" end
  seen[val] = true
  local parts = {}
  for k, v in pairs(val) do
    local kk = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
    table.insert(parts, kk .. "=" .. _dump(v, depth - 1, seen))
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function dprint(fmt, ...)
  if not DEBUG then return end
  local ok, msg = pcall(string.format, fmt, ...)
  if not ok then msg = fmt end
  print(("^3[econ DEBUG]^7 %s"):format(msg))
end

local function dsql(tag, sql, params)
  if not DEBUG then return end
  dprint("%s SQL: %s | params=%s", tostring(tag), tostring(sql), _dump(params or {}, 3))
end

local T = {
  money = 'econ_user_money',
  accts = 'econ_accounts',
  pays  = 'econ_payments',
  cards = 'econ_cards',
  tx    = 'econ_transactions',
  inv   = 'econ_investments'
}

local function getDiscordID(src)
  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if id:sub(1, 8) == 'discord:' then
      return id:sub(9)
    end
  end
  return ''
end

local function getCharID(src)
  if exports['Az-Framework'] and exports['Az-Framework'].GetPlayerCharacter then
    local cid = exports['Az-Framework']:GetPlayerCharacter(src)
    if cid and cid ~= '' then return tostring(cid) end
  end
  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if id:match('^%d+$') then return id end
  end
  return ''
end

local function getPlayerDisplayName(src)
  local name = GetPlayerName(src)
  if name and name ~= '' then return name end
  return ('Player %s'):format(tostring(src))
end

local function findPlayerByCharId(targetCid)
  local needle = tostring(targetCid or '')
  if needle == '' then return nil end
  for _, playerId in ipairs(GetPlayers()) do
    local src = tonumber(playerId)
    if src and tostring(getCharID(src)) == needle then
      return src
    end
  end
  return nil
end

local function nui(src, action, payload)
  TriggerClientEvent('my-bank-ui:nui', src, { action = action, payload = payload })
end

local function notify(src, typ, text)
  nui(src, 'notify', { type = typ, text = text })
end

local function logTx(charid, discordid, typ, signedAmount, desc, account_id, counterparty)
  local sql = ("INSERT INTO `%s` (discordid,charid,type,amount,description,account_id,counterparty) VALUES (?,?,?,?,?,?,?)"):format(T.tx)
  local params = {
    tostring(discordid or ''),
    tostring(charid or ''),
    tostring(typ or ''),
    tonumber(signedAmount) or 0,
    tostring(desc or ''),
    tonumber(account_id) or 0,
    tostring(counterparty or '')
  }
  dsql('logTx', sql, params)
  exports.oxmysql:insert(sql, params)
end

local Lock = {}
local function with_lock(src, key, ms, fn)
  Lock[src] = Lock[src] or {}
  if Lock[src][key] then
    dprint('with_lock BLOCKED src=%s key=%s', tostring(src), tostring(key))
    return
  end
  Lock[src][key] = true
  local ok, err = pcall(fn)
  if not ok then print(('[econ] %s error: %s'):format(key, err)) end
  Citizen.SetTimeout(ms or 800, function()
    if Lock[src] then Lock[src][key] = false end
  end)
end

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end

  local sql1 = ([[CREATE TABLE IF NOT EXISTS `%s`(
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `discordid` varchar(64) DEFAULT '',
    `charid` varchar(100) NOT NULL,
    `firstname` varchar(100) DEFAULT '',
    `lastname` varchar(100) DEFAULT '',
    `profile_picture` varchar(255) DEFAULT NULL,
    `cash` BIGINT NOT NULL DEFAULT 0,
    `bank` BIGINT NOT NULL DEFAULT 0,
    `last_daily` BIGINT NOT NULL DEFAULT 0,
    `card_number` varchar(16) DEFAULT NULL,
    `exp_month` tinyint(4) DEFAULT NULL,
    `exp_year` smallint(6) DEFAULT NULL,
    `card_status` varchar(16) NOT NULL DEFAULT 'active',
    KEY (charid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]):format(T.money)
  exports.oxmysql:execute(sql1)

  local sql2 = ([[CREATE TABLE IF NOT EXISTS `%s`(
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `discordid` varchar(64) DEFAULT '',
    `charid` varchar(100) DEFAULT '',
    `type` ENUM('checking','savings') NOT NULL,
    `balance` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `account_number` varchar(32) DEFAULT '',
    INDEX (charid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]):format(T.accts)
  exports.oxmysql:execute(sql2)

  local sql3 = ([[CREATE TABLE IF NOT EXISTS `%s`(
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `discordid` varchar(64) DEFAULT '',
    `charid` varchar(100) DEFAULT '',
    `type` varchar(32) NOT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `counterparty` varchar(255) DEFAULT '',
    `account_id` INT DEFAULT NULL,
    `description` text,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (charid), INDEX(discordid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]):format(T.tx)
  exports.oxmysql:execute(sql3)

  local sql4 = ([[CREATE TABLE IF NOT EXISTS `%s`(
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `discordid` varchar(64) DEFAULT '',
    `charid` varchar(100) NOT NULL,
    `plan_code` varchar(32) NOT NULL,
    `plan_name` varchar(100) NOT NULL,
    `risk` varchar(24) NOT NULL DEFAULT 'Low',
    `return_rate` DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    `principal` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `payout` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `status` ENUM('active','closed') NOT NULL DEFAULT 'active',
    `notes` varchar(255) DEFAULT '',
    `started_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `matures_at` DATETIME NOT NULL,
    `closed_at` DATETIME NULL DEFAULT NULL,
    INDEX (charid),
    INDEX (status),
    INDEX (matures_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]):format(T.inv)
  exports.oxmysql:execute(sql4)

  print('^2[econ]^7 upgraded banking tables ensured (debug=' .. tostring(DEBUG) .. ')')
end)

local function fetchMoney(did, cid, cb)
  local sql1 = ("SELECT * FROM `%s` WHERE charid=? LIMIT 1"):format(T.money)
  local p1 = { cid }
  dsql('fetchMoney#charid', sql1, p1)
  exports.oxmysql:query(sql1, p1, function(r1)
    if r1 and r1[1] then return cb(r1[1]) end

    local sql2 = ("SELECT * FROM `%s` WHERE discordid=? OR discordid=CONCAT('discord:',?) ORDER BY cash DESC LIMIT 1"):format(T.money)
    local p2 = { did or cid, did or cid }
    dsql('fetchMoney#discord', sql2, p2)
    exports.oxmysql:query(sql2, p2, function(r2)
      if r2 and r2[1] then
        local row = r2[1]
        if not row.charid or row.charid == '' or row.charid == '0' then
          local up = ("UPDATE `%s` SET charid=? WHERE (discordid=? OR discordid=CONCAT('discord:',?)) AND (charid='' OR charid='0') ORDER BY cash DESC LIMIT 1"):format(T.money)
          local pu = { cid, did or cid, did or cid }
          dsql('fetchMoney repair', up, pu)
          exports.oxmysql:execute(up, pu)
          row.charid = cid
        end
        return cb(row)
      end

      local ins = ("INSERT INTO `%s` (discordid,charid,cash,bank,card_status) VALUES (?,?,?,?,?)"):format(T.money)
      local ip = { did or '', cid, 0, 0, 'active' }
      dsql('fetchMoney seed', ins, ip)
      exports.oxmysql:insert(ins, ip, function()
        fetchMoney(did, cid, cb)
      end)
    end)
  end)
end

local function fetchAccounts(did, cid, cb)
  local sql = ("SELECT * FROM `%s` WHERE charid=? ORDER BY id"):format(T.accts)
  local params = { cid }
  dsql('fetchAccounts', sql, params)
  exports.oxmysql:query(sql, params, function(rows)
    if rows and #rows > 0 then return cb(rows) end

    local stamp = tostring(os.time())
    local ins = ("INSERT INTO `%s` (discordid,charid,type,balance,account_number) VALUES (?,?,?,?,?),(?,?,?,?,?)"):format(T.accts)
    local ip = {
      did or '', cid, 'checking', 0, 'CHK' .. stamp,
      did or '', cid, 'savings', 0, 'SVG' .. stamp
    }
    dsql('fetchAccounts seed', ins, ip)
    exports.oxmysql:insert(ins, ip, function()
      fetchAccounts(did, cid, cb)
    end)
  end)
end

local function fetchTransactions(cid, limit, cb)
  local sql = ("SELECT id,type,amount,description,account_id,counterparty,UNIX_TIMESTAMP(created_at) AS ts FROM `%s` WHERE charid=? ORDER BY id DESC LIMIT %d"):format(T.tx, tonumber(limit) or 80)
  local params = { cid }
  dsql('fetchTransactions', sql, params)
  exports.oxmysql:query(sql, params, function(rows)
    cb(rows or {})
  end)
end

local function fetchInvestments(did, cid, cb)
  local sql = ([[SELECT id,plan_code,plan_name,risk,return_rate,principal,payout,status,notes,
    UNIX_TIMESTAMP(started_at) AS started_ts,
    UNIX_TIMESTAMP(matures_at) AS matures_ts,
    UNIX_TIMESTAMP(closed_at) AS closed_ts
    FROM `%s`
    WHERE charid=?
    ORDER BY id DESC
    LIMIT 50]]):format(T.inv)
  local params = { cid }
  dsql('fetchInvestments', sql, params)
  exports.oxmysql:query(sql, params, function(rows)
    cb(rows or {})
  end)
end

local function firstAccountIdOfType(accts, typ)
  for _, a in ipairs(accts or {}) do
    if a.type == typ then return tonumber(a.id) end
  end
  return nil
end

local function getAccountById(accts, id)
  for _, a in ipairs(accts or {}) do
    if tonumber(a.id) == tonumber(id) then return a end
  end
  return nil
end

local function resolveAccountId(accts, token)
  local value = tostring(token or '')
  if value == '' then return nil end
  if value:sub(1, 5) == 'acct:' then return tonumber(value:sub(6)) end
  if value == 'checking' or value == 'savings' then
    return firstAccountIdOfType(accts, value)
  end
  return nil
end

local function getSourceBalance(moneyRow, accts, token)
  local value = tostring(token or '')
  if value == 'cash' then return tonumber(moneyRow.cash) or 0 end
  local aid = resolveAccountId(accts, value)
  local acct = aid and getAccountById(accts, aid) or nil
  return acct and (tonumber(acct.balance) or 0) or 0
end

local function buildAccountUpdateQueue(charid, accts, token, amount, add)
  local value = tostring(token or '')
  local op = add and '+' or '-'
  if value == 'cash' then
    return {
      sql = ("UPDATE `%s` SET cash=cash%s? WHERE charid=?"):format(T.money, op),
      params = { amount, charid },
      accountId = nil,
      label = 'cash'
    }
  end

  local aid = resolveAccountId(accts, value)
  if not aid then return nil end
  return {
    sql = ("UPDATE `%s` SET balance=balance%s? WHERE id=?"):format(T.accts, op),
    params = { amount, aid },
    accountId = aid,
    label = value
  }
end

local function runStatements(queue, done, i)
  i = i or 1
  if i > #queue then return done(true) end
  local step = queue[i]
  dsql('statement ' .. tostring(i), step.sql, step.params)
  exports.oxmysql:execute(step.sql, step.params, function(_)
    runStatements(queue, done, i + 1)
  end)
end

local function getPlan(planCode)
  local plans = Config.InvestmentPlans or {}
  return plans[tostring(planCode or '')]
end

local function getPlanList()
  local out = {}
  for code, plan in pairs(Config.InvestmentPlans or {}) do
    out[#out + 1] = {
      code = code,
      label = plan.label or code,
      description = plan.description or '',
      risk = plan.risk or 'Low',
      min = tonumber(plan.min) or 0,
      max = tonumber(plan.max) or 0,
      durationHours = tonumber(plan.durationHours) or 1,
      returnRate = tonumber(plan.returnRate) or 0,
      color = plan.color or '#52c7ff'
    }
  end
  table.sort(out, function(a, b) return tostring(a.code) < tostring(b.code) end)
  return out
end

local function buildRecipientList(src)
  local out = {}
  local max = tonumber(Config.Transfer and Config.Transfer.maxOnlineRecipients) or 24
  for _, playerId in ipairs(GetPlayers()) do
    local pid = tonumber(playerId)
    if pid and pid ~= src then
      local cid = getCharID(pid)
      if cid ~= '' then
        out[#out + 1] = {
          serverId = pid,
          charid = tostring(cid),
          name = getPlayerDisplayName(pid)
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  while #out > max do table.remove(out) end
  return out
end

local function investmentSummary(rows)
  local now = os.time()
  local totalPrincipal, totalValue, activeCount, maturedCount = 0, 0, 0, 0
  local list = {}
  for _, row in ipairs(rows or {}) do
    local principal = tonumber(row.principal) or 0
    local payout = tonumber(row.payout) or principal
    local maturesTs = tonumber(row.matures_ts) or 0
    local isOpen = tostring(row.status or 'active') == 'active'
    local matured = isOpen and maturesTs > 0 and maturesTs <= now
    if isOpen then
      totalPrincipal = totalPrincipal + principal
      totalValue = totalValue + payout
      activeCount = activeCount + 1
      if matured then maturedCount = maturedCount + 1 end
    end
    list[#list + 1] = {
      id = tonumber(row.id),
      plan_code = row.plan_code,
      plan_name = row.plan_name,
      risk = row.risk,
      return_rate = tonumber(row.return_rate) or 0,
      principal = principal,
      payout = payout,
      status = row.status,
      matured = matured,
      notes = row.notes,
      started_ts = tonumber(row.started_ts) or 0,
      matures_ts = maturesTs,
      closed_ts = tonumber(row.closed_ts) or 0
    }
  end
  return {
    total_principal = totalPrincipal,
    total_value = totalValue,
    active_count = activeCount,
    matured_count = maturedCount,
    items = list
  }
end

local function pushData(src, err)
  local did, cid = getDiscordID(src), getCharID(src)
  if cid == '' then return end

  fetchMoney(did, cid, function(moneyRow)
    fetchAccounts(did, cid, function(accts)
      fetchTransactions(cid, 80, function(txs)
        fetchInvestments(did, cid, function(invRows)
          local checking, savings = 0, 0
          for _, a in ipairs(accts or {}) do
            if a.type == 'checking' then checking = checking + (tonumber(a.balance) or 0) end
            if a.type == 'savings' then savings = savings + (tonumber(a.balance) or 0) end
          end
          local bankTotal = checking + savings
          local moneyIn, moneyOut = 0, 0
          local tnow = os.date('*t')
          local monthStart = os.time({ year = tnow.year, month = tnow.month, day = 1, hour = 0, min = 0, sec = 0 })
          local neutralMonthly = {
            transfer_internal = true,
            transfer_in = true,
            transfer_out = true,
            deposit = true,
            withdraw = true,
            investment_open = true
          }

          for _, t in ipairs(txs or {}) do
            local amt = tonumber(t.amount) or 0
            if (tonumber(t.ts) or 0) >= monthStart and not neutralMonthly[t.type] then
              if amt > 0 then moneyIn = moneyIn + amt end
              if amt < 0 then moneyOut = moneyOut + math.abs(amt) end
            end
          end

          local portfolio = investmentSummary(invRows)
          local payload = {
            brand = Config.Brand,
            cash = tonumber(moneyRow.cash) or 0,
            checking = checking,
            savings = savings,
            bank = bankTotal,
            net_worth = (tonumber(moneyRow.cash) or 0) + bankTotal + (tonumber(portfolio.total_value) or 0),
            accounts = accts or {},
            transactions = txs or {},
            total_transactions = #(txs or {}),
            money_in = moneyIn,
            money_out = moneyOut,
            month_change = moneyIn - moneyOut,
            transferError = err,
            online_players = buildRecipientList(src),
            investment_plans = getPlanList(),
            investments = portfolio,
            player = {
              charid = tostring(cid),
              discordid = tostring(did or ''),
              name = getPlayerDisplayName(src)
            }
          }

          TriggerClientEvent('my-bank-ui:updateData', src, payload)
          TriggerClientEvent('updateCashHUD', src, payload.cash, payload.bank)
        end)
      end)
    end)
  end)
end

RegisterNetEvent('my-bank-ui:getData', function()
  pushData(source)
end)

RegisterNetEvent('my-bank-ui:deposit', function(data)
  local src = source
  with_lock(src, 'deposit', 900, function()
    local did, cid = getDiscordID(src), getCharID(src)
    local amount = parseAmount(data and data.amount)
    local target = tostring((data and data.to) or 'checking')
    local desc = tostring((data and data.description) or 'Deposit')

    if amount <= 0 or cid == '' then
      notify(src, 'error', 'Invalid deposit amount.')
      return pushData(src)
    end

    fetchMoney(did, cid, function(moneyRow)
      if (tonumber(moneyRow.cash) or 0) < amount then
        notify(src, 'error', 'Not enough cash in wallet.')
        return pushData(src)
      end

      fetchAccounts(did, cid, function(accts)
        local credit = buildAccountUpdateQueue(cid, accts, target, amount, true)
        if not credit or credit.label == 'cash' then
          notify(src, 'error', 'Choose a bank account to deposit into.')
          return pushData(src)
        end

        local debit = buildAccountUpdateQueue(cid, accts, 'cash', amount, false)
        runStatements({ debit, credit }, function()
          logTx(cid, did, 'deposit', amount, desc, credit.accountId, 'cash')
          notify(src, 'success', ('Deposited $%d to %s.'):format(amount, tostring(target)))
          pushData(src)
        end)
      end)
    end)
  end)
end)

RegisterNetEvent('my-bank-ui:withdraw', function(data)
  local src = source
  with_lock(src, 'withdraw', 900, function()
    local did, cid = getDiscordID(src), getCharID(src)
    local amount = parseAmount(data and data.amount)
    local sourceToken = tostring((data and data.from) or 'checking')
    local desc = tostring((data and data.description) or (data and data.reason) or 'Withdraw')

    if amount <= 0 or cid == '' then
      notify(src, 'error', 'Invalid withdrawal amount.')
      return pushData(src)
    end

    fetchMoney(did, cid, function(moneyRow)
      fetchAccounts(did, cid, function(accts)
        local balance = getSourceBalance(moneyRow, accts, sourceToken)
        if balance < amount then
          notify(src, 'error', 'Insufficient funds.')
          return pushData(src)
        end

        local debit = buildAccountUpdateQueue(cid, accts, sourceToken, amount, false)
        if not debit or debit.label == 'cash' then
          notify(src, 'error', 'Choose a bank account to withdraw from.')
          return pushData(src)
        end
        local credit = buildAccountUpdateQueue(cid, accts, 'cash', amount, true)
        runStatements({ debit, credit }, function()
          logTx(cid, did, 'withdraw', -amount, desc, debit.accountId, 'cash')
          notify(src, 'success', ('Withdrew $%d to wallet.'):format(amount))
          pushData(src)
        end)
      end)
    end)
  end)
end)

RegisterNetEvent('my-bank-ui:transferInternal', function(data)
  local src = source
  with_lock(src, 'transferInternal', 1100, function()
    local did, cid = getDiscordID(src), getCharID(src)
    local from = tostring((data and data.from) or '')
    local to = tostring((data and data.to) or '')
    local amount = parseAmount(data and data.amount)
    local desc = tostring((data and data.description) or ('Internal transfer %s → %s'):format(from, to))

    if cid == '' or amount <= 0 or from == '' or to == '' then
      notify(src, 'error', 'Invalid internal transfer.')
      nui(src, 'transferResult', { success = false, error = 'Invalid internal transfer' })
      return pushData(src)
    end
    if from == to then
      notify(src, 'error', 'Source and destination are the same.')
      nui(src, 'transferResult', { success = false, error = 'Same source and destination' })
      return pushData(src)
    end

    fetchMoney(did, cid, function(moneyRow)
      fetchAccounts(did, cid, function(accts)
        local balance = getSourceBalance(moneyRow, accts, from)
        if balance < amount then
          notify(src, 'error', 'Insufficient funds.')
          nui(src, 'transferResult', { success = false, error = 'Insufficient funds' })
          return pushData(src)
        end

        local debit = buildAccountUpdateQueue(cid, accts, from, amount, false)
        local credit = buildAccountUpdateQueue(cid, accts, to, amount, true)
        if not debit or not credit then
          notify(src, 'error', 'Invalid source or destination.')
          nui(src, 'transferResult', { success = false, error = 'Invalid source or destination' })
          return pushData(src)
        end

        runStatements({ debit, credit }, function()
          logTx(cid, did, 'transfer_internal', 0, desc, debit.accountId or credit.accountId, to)
          if from == 'cash' then
            logTx(cid, did, 'transfer_in', amount, desc, credit.accountId, 'cash')
          elseif to == 'cash' then
            logTx(cid, did, 'transfer_out', -amount, desc, debit.accountId, 'cash')
          else
            logTx(cid, did, 'transfer_out', -amount, desc, debit.accountId, tostring(to))
            logTx(cid, did, 'transfer_in', amount, desc, credit.accountId, tostring(from))
          end
          notify(src, 'success', ('Moved $%d internally.'):format(amount))
          nui(src, 'transferResult', { success = true })
          pushData(src)
        end)
      end)
    end)
  end)
end)

RegisterNetEvent('my-bank-ui:transferPlayer', function(data)
  local src = source
  with_lock(src, 'transferPlayer', 1250, function()
    local did, cid = getDiscordID(src), getCharID(src)
    local amount = parseAmount(data and data.amount)
    local from = tostring((data and data.from) or 'cash')
    local destination = tostring((data and data.destination) or (Config.Transfer and Config.Transfer.defaultRecipientDestination) or 'checking')
    local desc = tostring((data and data.description) or 'Player transfer')
    local targetServerId = tonumber(data and data.targetServerId)
    local targetCharId = tostring((data and data.targetCharId) or '')
    local maxTransfer = tonumber(Config.Transfer and Config.Transfer.maxTransfer) or 250000

    if cid == '' or amount <= 0 then
      notify(src, 'error', 'Invalid transfer amount.')
      nui(src, 'transferResult', { success = false, error = 'Invalid amount' })
      return pushData(src)
    end
    if amount > maxTransfer then
      notify(src, 'error', ('Transfer limit is $%d.'):format(maxTransfer))
      nui(src, 'transferResult', { success = false, error = 'Over transfer limit' })
      return pushData(src)
    end

    if targetServerId then
      targetCharId = tostring(getCharID(targetServerId) or '')
    end
    if targetCharId == '' and targetServerId then
      targetCharId = tostring(getCharID(targetServerId) or '')
    end
    if targetCharId == '' then
      notify(src, 'error', 'Recipient not found.')
      nui(src, 'transferResult', { success = false, error = 'Recipient not found' })
      return pushData(src)
    end
    if targetCharId == tostring(cid) then
      notify(src, 'error', 'You cannot transfer to yourself.')
      nui(src, 'transferResult', { success = false, error = 'Cannot transfer to yourself' })
      return pushData(src)
    end

    fetchMoney(did, cid, function(senderMoney)
      fetchAccounts(did, cid, function(senderAccounts)
        local senderBalance = getSourceBalance(senderMoney, senderAccounts, from)
        if senderBalance < amount then
          notify(src, 'error', 'Insufficient funds.')
          nui(src, 'transferResult', { success = false, error = 'Insufficient funds' })
          return pushData(src)
        end

        fetchMoney('', targetCharId, function(targetMoney)
          fetchAccounts(targetMoney.discordid or '', targetCharId, function(targetAccounts)
            local debit = buildAccountUpdateQueue(cid, senderAccounts, from, amount, false)
            local creditToken = (destination == 'wallet' or destination == 'cash') and 'cash' or 'checking'
            local credit = buildAccountUpdateQueue(targetCharId, targetAccounts, creditToken, amount, true)
            if not debit or not credit then
              notify(src, 'error', 'Unable to prepare this transfer.')
              nui(src, 'transferResult', { success = false, error = 'Transfer setup failed' })
              return pushData(src)
            end

            local recipientSource = findPlayerByCharId(targetCharId)
            local recipientName = recipientSource and getPlayerDisplayName(recipientSource) or ('CharID %s'):format(targetCharId)
            local senderName = getPlayerDisplayName(src)
            local activityText = desc ~= '' and desc or ('Transfer to %s'):format(recipientName)

            runStatements({ debit, credit }, function()
              logTx(cid, did, 'p2p_transfer_out', -amount, activityText, debit.accountId, targetCharId)
              logTx(targetCharId, targetMoney.discordid or '', 'p2p_transfer_in', amount, ('Transfer from %s'):format(senderName), credit.accountId, cid)
              notify(src, 'success', ('Transferred $%d to %s.'):format(amount, recipientName))
              nui(src, 'transferResult', { success = true })
              if recipientSource then
                notify(recipientSource, 'success', ('You received $%d from %s.'):format(amount, senderName))
                pushData(recipientSource)
              end
              pushData(src)
            end)
          end)
        end)
      end)
    end)
  end)
end)

RegisterNetEvent('my-bank-ui:investOpen', function(data)
  local src = source
  with_lock(src, 'investOpen', 1200, function()
    local did, cid = getDiscordID(src), getCharID(src)
    local planCode = tostring((data and data.plan) or '')
    local sourceToken = tostring((data and data.source) or 'checking')
    local amount = parseAmount(data and data.amount)
    local plan = getPlan(planCode)

    if cid == '' or not plan then
      notify(src, 'error', 'Unknown investment product.')
      return pushData(src)
    end

    local minAmt = tonumber(plan.min) or 0
    local maxAmt = tonumber(plan.max) or 999999999
    if amount < minAmt or amount > maxAmt then
      notify(src, 'error', ('%s accepts $%d - $%d.'):format(plan.label or planCode, minAmt, maxAmt))
      return pushData(src)
    end

    fetchMoney(did, cid, function(moneyRow)
      fetchAccounts(did, cid, function(accts)
        local balance = getSourceBalance(moneyRow, accts, sourceToken)
        if balance < amount then
          notify(src, 'error', 'Insufficient funds for this investment.')
          return pushData(src)
        end

        local debit = buildAccountUpdateQueue(cid, accts, sourceToken, amount, false)
        if not debit then
          notify(src, 'error', 'Invalid funding source.')
          return pushData(src)
        end

        local durationHours = tonumber(plan.durationHours) or 1
        local returnRate = tonumber(plan.returnRate) or 0
        local payout = math.floor((amount * (1 + (returnRate / 100))) * 100 + 0.5) / 100
        local maturesAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + math.floor(durationHours * 3600))
        local notes = ('Funded from %s'):format(sourceToken)

        runStatements({ debit }, function()
          local sql = ("INSERT INTO `%s` (discordid,charid,plan_code,plan_name,risk,return_rate,principal,payout,status,notes,matures_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)"):format(T.inv)
          local params = {
            did or '',
            cid,
            planCode,
            tostring(plan.label or planCode),
            tostring(plan.risk or 'Low'),
            returnRate,
            amount,
            payout,
            'active',
            notes,
            maturesAt
          }
          dsql('investOpen insert', sql, params)
          exports.oxmysql:insert(sql, params, function()
            logTx(cid, did, 'investment_open', -amount, ('Opened %s'):format(plan.label or planCode), debit.accountId, planCode)
            notify(src, 'success', ('Opened %s for $%d.'):format(plan.label or planCode, amount))
            pushData(src)
          end)
        end)
      end)
    end)
  end)
end)

RegisterNetEvent('my-bank-ui:investCollect', function(data)
  local src = source
  with_lock(src, 'investCollect', 1200, function()
    local did, cid = getDiscordID(src), getCharID(src)
    local investmentId = tonumber(data and data.id)
    local targetToken = tostring((data and data.to) or 'checking')
    if cid == '' or not investmentId then
      notify(src, 'error', 'Invalid investment selection.')
      return pushData(src)
    end

    local sql = ("SELECT * FROM `%s` WHERE id=? AND charid=? AND status='active' LIMIT 1"):format(T.inv)
    local params = { investmentId, cid }
    dsql('investCollect select', sql, params)
    exports.oxmysql:query(sql, params, function(rows)
      local row = rows and rows[1]
      if not row then
        notify(src, 'error', 'Investment not found or already closed.')
        return pushData(src)
      end
      local maturity = os.time()
      if row.matures_at and type(row.matures_at) == 'string' then
        local y, mo, d, h, mi, s = row.matures_at:match('(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)')
        if y then
          maturity = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
        end
      end
      if maturity > os.time() then
        notify(src, 'error', 'This investment has not matured yet.')
        return pushData(src)
      end

      fetchMoney(did, cid, function(moneyRow)
        fetchAccounts(did, cid, function(accts)
          local credit = buildAccountUpdateQueue(cid, accts, targetToken, tonumber(row.payout) or 0, true)
          if not credit then
            notify(src, 'error', 'Invalid payout destination.')
            return pushData(src)
          end

          runStatements({ credit }, function()
            local up = ("UPDATE `%s` SET status='closed', closed_at=NOW() WHERE id=? AND charid=? AND status='active'"):format(T.inv)
            local upp = { investmentId, cid }
            dsql('investCollect close', up, upp)
            exports.oxmysql:execute(up, upp, function()
              logTx(cid, did, 'investment_payout', tonumber(row.payout) or 0, ('Collected %s'):format(row.plan_name or row.plan_code or 'investment'), credit.accountId, row.plan_code)
              notify(src, 'success', ('Collected $%0.2f from %s.'):format(tonumber(row.payout) or 0, row.plan_name or 'investment'))
              pushData(src)
            end)
          end)
        end)
      end)
    end)
  end)
end)

local atmCooldowns = {}

local function normalizeDispatchKey(value)
  return tostring(value or ''):lower():gsub('%s+', ''):gsub('[^%w_%-]', '')
end

local function isTruthy(value)
  if value == true then return true end
  if type(value) == 'number' then return value ~= 0 end
  if type(value) == 'string' then
    value = value:lower()
    return value == 'true' or value == '1' or value == 'yes' or value == 'on'
  end
  return false
end

local function getStateValue(src, key)
  local ok, state = pcall(function() return Player(src).state end)
  if ok and state then
    local value = state[key]
    if value ~= nil then return value end
  end
  return nil
end

local function isLawEnforcement(src)
  local job = normalizeDispatchKey(getStateValue(src, 'job') or getStateValue(src, 'jobName'))
  local department = normalizeDispatchKey(getStateValue(src, 'department'))
  local role = normalizeDispatchKey(getStateValue(src, 'role'))
  local onduty = getStateValue(src, 'onduty')
  local duty = getStateValue(src, 'duty')

  local jobMatch = job ~= '' and Config.atmDispatchJobs and Config.atmDispatchJobs[job]
  local deptMatch = department ~= '' and Config.atmDispatchDepartments and Config.atmDispatchDepartments[department]
  local roleMatch = role == 'leo'
  local dutyOk = onduty == nil and duty == nil and true or isTruthy(onduty) or isTruthy(duty)

  return (jobMatch or deptMatch or roleMatch) and dutyOk
end

local function sendAtmDispatch(payload)
  for _, playerId in ipairs(GetPlayers()) do
    local target = tonumber(playerId)
    if target and isLawEnforcement(target) then
      TriggerClientEvent('dispatch:atmRobbery', target, payload)
    end
  end
end

local function getAtmRemaining(atmKey)
  local expiresAt = atmCooldowns[atmKey]
  if not expiresAt then return 0 end
  local remaining = math.floor(expiresAt - os.time())
  if remaining <= 0 then
    atmCooldowns[atmKey] = nil
    return 0
  end
  return remaining
end

local function setAtmCooldown(atmKey, seconds)
  if not atmKey or atmKey == '' then return end
  local duration = math.max(0, math.floor(tonumber(seconds) or 0))
  if duration <= 0 then
    atmCooldowns[atmKey] = nil
    TriggerClientEvent('atm:closedStatus', -1, atmKey, 0)
    return
  end
  atmCooldowns[atmKey] = os.time() + duration
  TriggerClientEvent('atm:closedStatus', -1, atmKey, duration)
end

local function validateAtmCoords(coords)
  if type(coords) ~= 'table' then return nil end
  local x = tonumber(coords.x)
  local y = tonumber(coords.y)
  local z = tonumber(coords.z)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

RegisterNetEvent('atm:attemptRob', function(atmKey, atmCoords, playerCoords)
  local src = source
  local did, cid = getDiscordID(src), getCharID(src)
  local safeKey = tostring(atmKey or '')
  local safeCoords = validateAtmCoords(atmCoords)

  if cid == '' or safeKey == '' or not safeCoords then
    notify(src, 'error', 'ATM robbery failed.')
    return
  end

  local remaining = getAtmRemaining(safeKey)
  if remaining > 0 then
    TriggerClientEvent('atm:closedStatus', src, safeKey, remaining)
    notify(src, 'error', ('This ATM is offline for %02d:%02d.'):format(math.floor(remaining / 60), remaining % 60))
    return
  end

  fetchMoney(did, cid, function(_)
    local reward = math.random(tonumber(Config.atmMinReward) or 500, tonumber(Config.atmMaxReward) or 3000)
    local sql = ("UPDATE `%s` SET cash=cash+? WHERE charid=?"):format(T.money)
    local params = { reward, cid }
    dsql('atm robbery payout', sql, params)
    exports.oxmysql:execute(sql, params, function()
      logTx(cid, did, 'atm_robbery', reward, 'ATM robbery payout')
      notify(src, 'success', ('You stole $%d from the ATM.'):format(reward))
      pushData(src)
      setAtmCooldown(safeKey, tonumber(Config.atmRobberyCooldown) or 600)
      sendAtmDispatch({
        success = true,
        reward = reward,
        coords = safeCoords,
        atmKey = safeKey,
        suspect = GetPlayerName(src),
        blipDuration = tonumber(Config.atmDispatchBlipDuration) or 30
      })
    end)
  end)
end)

RegisterNetEvent('atm:failedRob', function(atmKey, atmCoords, playerCoords)
  local src = source
  local safeKey = tostring(atmKey or '')
  local safeCoords = validateAtmCoords(atmCoords)
  if safeKey == '' or not safeCoords then return end
  if Config.atmDispatchOnFail == false then return end

  notify(src, 'error', 'ATM breach failed. Dispatch has been alerted.')
  sendAtmDispatch({
    success = false,
    reward = 0,
    coords = safeCoords,
    atmKey = safeKey,
    suspect = GetPlayerName(src),
    blipDuration = tonumber(Config.atmDispatchBlipDuration) or 30
  })
end)
