AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.Framework = AZH.Framework or {}

local RESOURCE = GetCurrentResourceName()

local function log(...)
  print(('^3[%s:framework]^7'):format(RESOURCE), ...)
end

local function truthy(v)
  if v == nil then return false end
  if type(v) == 'boolean' then return v == true end
  if type(v) == 'number' then return v ~= 0 end
  if type(v) == 'string' then
    local s = string.lower(v:gsub('^%s+', ''):gsub('%s+$', ''))
    return (s == 'true' or s == '1' or s == 'yes' or s == 'y' or s == 'on')
  end
  return false
end

local function getAzCore()
  if type(rawget(_G, 'Az')) == 'table' then
    return rawget(_G, 'Az')
  end

  local ok, exp = pcall(function() return exports['Az-Framework'] end)
  if ok and exp then return exp end
  return nil
end

local function safeGetCallable(core, name)
  if not core or type(name) ~= 'string' or name == '' then return nil end
  local ok, fn = pcall(function()
    return core[name]
  end)
  if ok and type(fn) == 'function' then
    return fn
  end
  return nil
end

local function callAny(core, names, ...)
  if not core then return nil end

  local args = { ... }
  for _, name in ipairs(names or {}) do
    local fn = safeGetCallable(core, name)
    if fn then
      local ok, res = pcall(fn, table.unpack(args))
      if ok then return res end

      ok, res = pcall(fn, core, table.unpack(args))
      if ok then return res end
    end
  end

  return nil
end

local function inList(val, list)
  if not val or type(list) ~= 'table' then return false end
  local needle = tostring(val):lower()
  for _, v in ipairs(list) do
    if tostring(v):lower() == needle then return true end
  end
  return false
end

function AZH.Framework.getJob(src)
  src = tonumber(src)
  if not src then return nil end

  local core = getAzCore()
  if not core then
    log('getJob: no Az-Framework bridge/export available')
    return nil
  end

  local res = callAny(core, { 'getPlayerJob', 'GetPlayerJob', 'getJob', 'GetJob' }, src)
  if type(res) == 'string' and res ~= '' then
    return tostring(res):lower()
  end

  return nil
end

AZH.Framework.getPlayerJob = AZH.Framework.getJob

function AZH.Framework.getDiscordID(src)
  src = tonumber(src)
  if not src then return nil end

  local core = getAzCore()
  if not core then return nil end

  local res = callAny(core, { 'getDiscordID', 'GetDiscordID', 'getDiscordId', 'GetDiscordId' }, src)
  if res == nil or tostring(res) == '' then return nil end
  return tostring(res)
end

function AZH.Framework.getCharId(src)
  src = tonumber(src)
  if not src then return nil end

  local core = getAzCore()
  if not core then return nil end

  local res = callAny(core, { 'GetPlayerCharacter', 'getPlayerCharacter', 'GetCharacter', 'getCharacter' }, src)
  if res == nil then return nil end

  if type(res) == 'table' then
    res = res.charid or res.charId or res.characterId or res.character_id or res.cid or res.id or res.identifier or res[1]
  end

  if res == nil then return nil end

  local s = tostring(res):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then return nil end
  s = s:gsub('^charid:', ''):gsub('^char:', '')
  local digits = s:match('^(%d+)$') or s:match('(%d+)')
  return digits
end

function AZH.Framework.isAdmin(src)
  src = tonumber(src)
  if not src then return false end

  local core = getAzCore()
  if not core then
    log('isAdmin: no Az-Framework bridge/export available')
    return false
  end

  local res = callAny(core, { 'isAdmin', 'IsAdmin' }, src)
  if res ~= nil then
    return truthy(res)
  end

  return false
end

CreateThread(function()
  Wait(0)

  if GetResourceState('ox_lib') ~= 'started' or not lib or not lib.callback or not lib.callback.register then
    log('ox_lib not ready; callbacks will not be registered')
    return
  end

  lib.callback.register('az_housing:cb:getJob', function(src)
    return AZH.Framework.getJob(src)
  end)

  lib.callback.register('az_housing:cb:isPolice', function(src)
    local job = AZH.Framework.getJob(src)
    local okPolice = inList(job, (Config and Config.Police and Config.Police.Jobs) or {})
    return okPolice == true, job
  end)

  lib.callback.register('az_housing:cb:isAdmin', function(src)
    return AZH.Framework.isAdmin(src) == true
  end)

  log('Registered callback az_housing:cb:getJob')
  log('Registered callback az_housing:cb:isPolice')
  log('Registered callback az_housing:cb:isAdmin')
end)

RegisterNetEvent('az_housing:server:getJobReq', function(reqId)
  local src = source
  local job = AZH.Framework.getJob(src)
  TriggerClientEvent('az_housing:client:getJobRes', src, reqId, job)
end)

RegisterNetEvent('az_housing:server:isPoliceReq', function(reqId)
  local src = source
  local job = AZH.Framework.getJob(src)
  local okPolice = inList(job, (Config and Config.Police and Config.Police.Jobs) or {})
  TriggerClientEvent('az_housing:client:isPoliceRes', src, reqId, okPolice == true, job)
end)

RegisterNetEvent('az_housing:server:isAdminReq', function(reqId)
  local src = source
  local okAdmin = AZH.Framework.isAdmin(src) == true
  TriggerClientEvent('az_housing:client:isAdminRes', src, reqId, okAdmin == true)
end)
