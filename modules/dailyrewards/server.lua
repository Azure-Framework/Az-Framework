local Config = (Config and Config.DailyRewards) or {}
if Config.Enabled == false then return end
local json = json
local resourceName = Config.ResourceName or 'daily_checkin'

local function hasOxExport(fn)
  return exports and exports.oxmysql and type(exports.oxmysql[fn]) == 'function'
end

local function dbQuery(sql, params, cb)
  params = params or {}
  if MySQL and MySQL.query then
    if type(MySQL.query) == 'function' then
      return MySQL.query(sql, params, function(rows)
        cb(rows or {})
      end)
    elseif type(MySQL.query) == 'table' and type(MySQL.query.await) == 'function' then
      CreateThread(function()
        local ok, rows = pcall(MySQL.query.await, sql, params)
        if not ok then
          print(('[daily_checkin] DB query failed: %s | %s'):format(sql, tostring(rows)))
          rows = {}
        end
        cb(rows or {})
      end)
      return
    end
  end

  if hasOxExport('query') then
    return exports.oxmysql:query(sql, params, function(rows)
      cb(rows or {})
    end)
  end

  if hasOxExport('fetch') then
    return exports.oxmysql:fetch(sql, params, function(rows)
      cb(rows or {})
    end)
  end

  print('[daily_checkin] oxmysql/MySQL.query is not available. Daily rewards cannot load data.')
  cb({})
end

local function dbExecute(sql, params, cb)
  params = params or {}
  cb = cb or function() end

  if MySQL and MySQL.update then
    if type(MySQL.update) == 'function' then
      return MySQL.update(sql, params, function(result)
        cb(result)
      end)
    elseif type(MySQL.update) == 'table' and type(MySQL.update.await) == 'function' then
      CreateThread(function()
        local ok, result = pcall(MySQL.update.await, sql, params)
        if not ok then
          print(('[daily_checkin] DB execute failed: %s | %s'):format(sql, tostring(result)))
          result = 0
        end
        cb(result)
      end)
      return
    end
  end

  if hasOxExport('execute') then
    return exports.oxmysql:execute(sql, params, function(result)
      cb(result)
    end)
  end

  print('[daily_checkin] oxmysql/MySQL.update is not available. Daily rewards cannot save data.')
  cb(0)
end

local function ensureMonthRow(identifier, year, month, cb)
  dbQuery('SELECT * FROM daily_checkin_users WHERE identifier = ? AND year = ? AND month = ? LIMIT 1', { identifier, year, month }, function(result)
    if result and result[1] then
      cb(result[1], false)
      return
    end

    dbExecute('INSERT INTO daily_checkin_users (`identifier`, `year`, `month`, `claimed_days`, `claimed_count`, `keys`) VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE `identifier` = VALUES(`identifier`)', {
      identifier,
      year,
      month,
      json.encode({}),
      0,
      0,
    }, function()
      dbQuery('SELECT * FROM daily_checkin_users WHERE identifier = ? AND year = ? AND month = ? LIMIT 1', { identifier, year, month }, function(rows)
        cb(rows and rows[1] or nil, true)
      end)
    end)
  end)
end

local function updateUserMonth(identifier, year, month, claimed_json, claimed_count, keys, cb)
  dbExecute('UPDATE daily_checkin_users SET `claimed_days` = ?, `claimed_count` = ?, `keys` = ? WHERE `identifier` = ? AND `year` = ? AND `month` = ?', {
    claimed_json,
    claimed_count,
    keys or 0,
    identifier,
    year,
    month,
  }, function(rows)
    if cb then cb(rows) end
  end)
end

local function fetchRewardFromDB(month, day, cb)
  dbQuery('SELECT * FROM daily_checkin_rewards WHERE month = ? AND day = ? LIMIT 1', { month, day }, function(res)
    if res and res[1] then cb(res[1]) else cb(nil) end
  end)
end

local function buildMonthPayload(identifier, year, month, claimed_days_table, keys, cb)
  local daysInMonth = os.date('*t', os.time{year=year, month = month + 1, day = 0}).day
  local claimedSet = {}
  if claimed_days_table then
    for _, d in ipairs(claimed_days_table) do claimedSet[tonumber(d)] = true end
  end

  dbQuery('SELECT * FROM daily_checkin_rewards WHERE month = ?', { month }, function(res)
    local rewards = {}
    if res and next(res) then
      for _, r in ipairs(res) do
        rewards[tonumber(r.day)] = { money = r.money, weapon = r.weapon, ammo = r.ammo, keys = r.keys }
      end
    end

    local days = {}
    for d = 1, daysInMonth do
      local r = rewards[d] or (Config.DefaultRewards[month] and Config.DefaultRewards[month][d]) or {}
      table.insert(days, { day = d, claimed = claimedSet[d] == true, reward = r })
    end

    local payload = {
      year = year,
      month = month,
      days = days,
      keys = keys or 0,
      wheelPrizes = Config.WheelPrizes,
      currency = Config.CurrencyName or '$'
    }
    cb(payload)
  end)
end

local function giveMoney(src, amount)
  if not amount or amount <= 0 then return false end
  local ok, err = pcall(function() exports[resourceName]:addMoney(src, tonumber(amount)) end)
  if not ok then
    print('[daily_checkin] ' .. tostring(resourceName) .. ':addMoney failed:', err)
    return false
  end
  return true
end

local function giveWeapon(src, weapon, ammo)
  if not weapon then return end
  TriggerClientEvent('daily_checkin:client:giveWeapon', src, weapon, ammo or 0)
  return true
end

local function getIdentifier(src)
  local ids = GetPlayerIdentifiers(src)
  if not ids or #ids == 0 then return nil end
  for _, v in ipairs(ids) do
    if string.find(v, 'discord:') then return v end
  end
  for _, v in ipairs(ids) do
    if string.find(v, 'license:') then return v end
  end
  for _, v in ipairs(ids) do
    if string.find(v, 'steam:') then return v end
  end
  return ids[1]
end

local function notify(src, msg)
  TriggerClientEvent('daily_checkin:client:notify', src, msg)
end

RegisterNetEvent('daily_checkin:server:requestOpen')
AddEventHandler('daily_checkin:server:requestOpen', function()
  local src = source
  local identifier = getIdentifier(src)
  if not identifier then
    notify(src, 'No player identifier was found for daily rewards.')
    return
  end

  local time = os.date('*t')
  local year = time.year
  local month = time.month

  ensureMonthRow(identifier, year, month, function(row)
    local claimed = {}
    local keys = 0

    if row then
      local ok, parsed = pcall(json.decode, row.claimed_days or '[]')
      if ok and type(parsed) == 'table' then claimed = parsed end
      keys = tonumber(row.keys) or 0
    end

    buildMonthPayload(identifier, year, month, claimed, keys, function(payload)
      TriggerClientEvent('daily_checkin:client:openUI', src, payload)
    end)
  end)
end)

RegisterNetEvent('daily_checkin:server:claimDay')
AddEventHandler('daily_checkin:server:claimDay', function(day)
  local src = source
  local identifier = getIdentifier(src)
  if not identifier then
    notify(src, 'Identifier not found')
    return
  end

  local t = os.date('*t')
  local year, month = t.year, t.month
  day = tonumber(day)
  if not day then
    notify(src, 'Invalid day')
    return
  end

  ensureMonthRow(identifier, year, month, function(row)
    local claimed = {}
    local claimed_count = 0
    local keys = 0

    if row then
      local ok, parsed = pcall(json.decode, row.claimed_days or '[]')
      if ok and type(parsed) == 'table' then claimed = parsed end
      claimed_count = tonumber(row.claimed_count) or 0
      keys = tonumber(row.keys) or 0
    end

    for _, d in ipairs(claimed) do
      if tonumber(d) == day then
        notify(src, 'This day has already been claimed')
        return
      end
    end

    local now = os.time(t)
    local claimedDate = os.time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 })
    if claimedDate > now then
      notify(src, 'You cannot claim a future day')
      return
    end

    fetchRewardFromDB(month, day, function(dbReward)
      local reward = nil
      if dbReward then
        reward = { money = dbReward.money, weapon = dbReward.weapon, ammo = dbReward.ammo, keys = dbReward.keys }
      else
        reward = Config.DefaultRewards[month] and Config.DefaultRewards[month][day] or nil
      end

      if not reward then reward = { money = 100, keys = Config.DefaultClaimKeys } end

      if reward.money and reward.money > 0 then
        giveMoney(src, tonumber(reward.money))
      end
      if reward.weapon and reward.weapon ~= '' then
        giveWeapon(src, reward.weapon, tonumber(reward.ammo) or 0)
      end

      local giveKeys = tonumber(reward.keys) or 0
      keys = keys + giveKeys

      table.insert(claimed, day)
      claimed_count = claimed_count + 1

      local bonusKeys = 0
      if (claimed_count % 2) == 0 then
        bonusKeys = 1
        keys = keys + bonusKeys
      end

      local claimed_json = json.encode(claimed)
      updateUserMonth(identifier, year, month, claimed_json, claimed_count, keys, function()
        buildMonthPayload(identifier, year, month, claimed, keys, function(payload)
          local rewardWithBonus = reward
          if bonusKeys > 0 then
            rewardWithBonus = rewardWithBonus or {}
            rewardWithBonus.bonusKeys = (rewardWithBonus.bonusKeys or 0) + bonusKeys
          end
          TriggerClientEvent('daily_checkin:client:claimSuccess', src, { payload = payload, reward = rewardWithBonus })
        end)
      end)
    end)
  end)
end)

RegisterNetEvent('daily_checkin:server:spinWheel')
AddEventHandler('daily_checkin:server:spinWheel', function()
  local src = source
  local identifier = getIdentifier(src)
  if not identifier then
    notify(src, 'Identifier not found')
    return
  end

  local time = os.date('*t')
  local year = time.year
  local month = time.month

  ensureMonthRow(identifier, year, month, function(row)
    if not row then
      notify(src, 'No account data found. Open UI first.')
      return
    end

    local keys = tonumber(row.keys) or 0
    if keys <= 0 then
      notify(src, 'Not enough keys to spin the wheel.')
      return
    end

    keys = keys - 1

    local prizes = Config.WheelPrizes or {}
    if #prizes == 0 then
      notify(src, 'No wheel prizes are configured.')
      return
    end

    local idx = math.random(1, #prizes)
    local prize = prizes[idx]

    if prize.type == 'money' and prize.amount then
      giveMoney(src, prize.amount)
    elseif prize.type == 'weapon' and prize.weapon then
      giveWeapon(src, prize.weapon, prize.ammo or 0)
    elseif prize.type == 'keys' and prize.amount then
      keys = keys + prize.amount
    end

    updateUserMonth(identifier, year, month, row.claimed_days or '[]', tonumber(row.claimed_count) or 0, keys, function()
      TriggerClientEvent('daily_checkin:client:spinResult', src, { index = idx, prize = prize, keys = keys })
    end)
  end)
end)

AddEventHandler('onResourceStart', function(resName)
  if resName ~= GetCurrentResourceName() then return end
  if Config.AutoCreateTables then
    print('[daily_checkin] Tables are managed by schema.lua. If you use a separate DB bootstrap, keep sql/daily_checkin.sql in sync.')
  end
end)
