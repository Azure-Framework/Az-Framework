AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end

local function mode()
  return (Config and Config.Money and Config.Money.Mode) or 'none'
end

if IsDuplicityVersion() then
  local function azFw()
    if type(rawget(_G, 'Az')) == 'table' then
      return rawget(_G, 'Az')
    end

    local names = { 'Az-Framework', 'az-framework', 'az_framework', 'az-fw', 'az_fw', 'azfw' }
    for _, name in ipairs(names) do
      if AZH.hasResource(name) then
        local ok, fw = pcall(function() return exports[name] end)
        if ok and fw then return fw end
      end
    end
    return nil
  end

  local function safeGetCallable(obj, name)
    if not obj or type(name) ~= 'string' or name == '' then return nil end
    local ok, fn = pcall(function()
      return obj[name]
    end)
    if ok and type(fn) == 'function' then
      return fn
    end
    return nil
  end

  local function azEconTake(src, amount, reason)
    local exp = exports and exports['az-econ']
    if not exp then return nil end
    local fns = { 'RemoveMoney', 'Remove', 'TakeMoney', 'Take', 'removeMoney', 'takeMoney' }
    for _, fn in ipairs(fns) do
      local f = safeGetCallable(exp, fn)
      if f then
        local ok, res = pcall(f, src, amount, reason or 'housing')
        if ok then
          if res == nil then return true end
          return res == true
        end
      end
    end
    return nil
  end

  local function azEconGive(src, amount, reason)
    local exp = exports and exports['az-econ']
    if not exp then return nil end
    local fns = { 'AddMoney', 'Add', 'GiveMoney', 'Give', 'addMoney', 'giveMoney' }
    for _, fn in ipairs(fns) do
      local f = safeGetCallable(exp, fn)
      if f then
        local ok, res = pcall(f, src, amount, reason or 'housing')
        if ok then
          if res == nil then return true end
          return res == true
        end
      end
    end
    return nil
  end

  function AZH.moneyTake(src, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    local m = mode()
    if m == 'none' then return true end

    if m == 'az-econ' then
      local res = azEconTake(src, amount, reason)
      if res ~= nil then return res end
    end

    if (m == 'azfw' or m == 'az-framework' or m == 'Az-Framework') then
      local fw = azFw()
      if not fw then return false end

      local fns = { 'deductMoney', 'DeductMoney', 'removeMoney', 'RemoveMoney' }
      for _, name in ipairs(fns) do
        local fn = safeGetCallable(fw, name)
        if fn then
          local ok, res = pcall(fn, src, amount)
          if ok then return res == true end
          ok, res = pcall(fn, fw, src, amount)
          if ok then return res == true end
        end
      end

      return false
    end

    if m == 'qb' and AZH.hasResource('qb-core') then
      local QB = exports['qb-core']:GetCoreObject()
      local ply = QB and QB.Functions and QB.Functions.GetPlayer(src) or nil
      if not ply then return false end
      return ply.Functions.RemoveMoney((Config.Money.Account or 'bank'), amount, reason or 'housing') == true
    end

    if m == 'esx' and AZH.hasResource('es_extended') then
      local ESX = exports['es_extended']:getSharedObject()
      local xP = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src) or nil
      if not xP then return false end
      xP.removeAccountMoney((Config.Money.Account or 'bank'), amount)
      return true
    end

    if m == 'custom' then

      return true
    end

    return false
  end

  function AZH.moneyGive(src, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    local m = mode()
    if m == 'none' then return true end

    if m == 'az-econ' then
      local res = azEconGive(src, amount, reason)
      if res ~= nil then return res end
    end

    if (m == 'azfw' or m == 'az-framework' or m == 'Az-Framework') then
      local fw = azFw()
      if not fw then return false end

      local fns = { 'addMoney', 'AddMoney', 'giveMoney', 'GiveMoney' }
      for _, name in ipairs(fns) do
        local fn = safeGetCallable(fw, name)
        if fn then
          local ok, res = pcall(fn, src, amount)
          if ok then return res == true end
          ok, res = pcall(fn, fw, src, amount)
          if ok then return res == true end
        end
      end

      return false
    end

    if m == 'qb' and AZH.hasResource('qb-core') then
      local QB = exports['qb-core']:GetCoreObject()
      local ply = QB and QB.Functions and QB.Functions.GetPlayer(src) or nil
      if not ply then return false end
      ply.Functions.AddMoney((Config.Money.Account or 'bank'), amount, reason or 'housing')
      return true
    end

    if m == 'esx' and AZH.hasResource('es_extended') then
      local ESX = exports['es_extended']:getSharedObject()
      local xP = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src) or nil
      if not xP then return false end
      xP.addAccountMoney((Config.Money.Account or 'bank'), amount)
      return true
    end

    if m == 'custom' then

      return true
    end

    return false
  end
end
