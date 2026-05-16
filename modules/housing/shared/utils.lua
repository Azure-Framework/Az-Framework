AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.ResName = AZH.ResName or GetCurrentResourceName()

local function pfx()
  return ('^3[%s]^7'):format(AZH.ResName or 'az_housing')
end

function AZH.dprint(...)
  if not Config or not Config.Debug then return end
  print(pfx(), ...)
end

function AZH.hasResource(name)
  if type(name) ~= 'string' then return false end
  local s = GetResourceState(name)
  return (s == 'started' or s == 'starting')
end

function AZH.useOx()
  if not Config then return false end
  if not Config.UseOxLib then return false end
  return AZH.hasResource('ox_lib') and lib ~= nil
end

if IsDuplicityVersion() then
  function AZH.notify(src, ntype, title, description)
    TriggerClientEvent('az_housing:client:notify', src, ntype or 'inform', title or 'Housing', description or '')
  end
else
  function AZH.notify(ntype, title, description)
    if AZH.useOx() and lib and lib.notify then
      lib.notify({ title = title or 'Housing', description = description or '', type = ntype or 'inform' })
      return
    end

    TriggerEvent('chat:addMessage', {
      color = { 230, 60, 70 },
      multiline = true,
      args = { title or 'Housing', tostring(description or '') }
    })
  end
end

function AZH.getJobNameFromState(state)
  if not state then return nil end

  local direct = state.jobName or state.job_name or state.jobname
  if type(direct) == 'string' and direct ~= '' then return direct end

  local job = state.job
  if type(job) == 'table' then
    if type(job.name) == 'string' then return job.name end
    if type(job.job) == 'string' then return job.job end
  elseif type(job) == 'string' then
    return job
  end

  return nil
end

function AZH.inList(val, list)
  if val == nil or type(list) ~= 'table' then return false end
  local needle = tostring(val):lower()
  for _, v in ipairs(list) do
    if tostring(v):lower() == needle then return true end
  end
  return false
end

if IsDuplicityVersion() then
  local function getFw()
    if type(rawget(_G, 'Az')) == 'table' then
      return rawget(_G, 'Az')
    end
    local ok, exp = pcall(function() return exports['Az-Framework'] end)
    if ok and exp then return exp end
    return nil
  end

  local function safeGetFwCallable(fw, fnName)
    if not fw or type(fnName) ~= 'string' or fnName == '' then return nil end
    local ok, f = pcall(function()
      return fw[fnName]
    end)
    if ok and type(f) == 'function' then
      return f
    end
    return nil
  end

  local function fwCallAny(fw, fns, ...)
    if not fw then return nil end
    local args = { ... }
    for _, fnName in ipairs(fns or {}) do
      local f = safeGetFwCallable(fw, fnName)
      if f then
        local ok, res = pcall(f, table.unpack(args))
        if ok then return res end
        ok, res = pcall(f, fw, table.unpack(args))
        if ok then return res end
      end
    end
    return nil
  end

  local function extractCharId(v)
  if v == nil then return nil end
  if type(v) == 'table' then
    v = v.charid or v.charId or v.characterId or v.character_id or v.cid or v.id or v.identifier or v[1]
  end
  if v == nil then return nil end
  local s = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then return nil end

  s = s:gsub('^charid:', ''):gsub('^char:', '')
  local digits = s:match('^(%d+)$') or s:match('(%d+)')
  return digits
end

local function getCharId(src)
  src = tonumber(src)
  if not src then return nil end

  local fw = getFw()
  if not fw then return nil end

  local res = fwCallAny(fw, { 'GetPlayerCharacter', 'GetCharacter', 'getPlayerCharacter', 'getCharacter' }, src)
  return extractCharId(res)
end

  local function normalizeRoleList(v)
    if type(v) ~= 'table' then return nil end
    local out = {}
    for _, r in pairs(v) do
      if r ~= nil then out[#out + 1] = tostring(r) end
    end
    return out
  end

  function AZH.hasDiscordRole(src, roleId)
    roleId = tostring(roleId or '')
    if roleId == '' then return false end
    local st = Player(src) and Player(src).state or nil
    if not st then return false end
    local roles = normalizeRoleList(st.discordRoles) or normalizeRoleList(st.roles) or normalizeRoleList(st.discord_roles)
    if not roles then return false end
    for _, r in ipairs(roles) do
      if r == roleId then return true end
    end
    return false
  end

  function AZH.hasAnyDiscordRole(src, roleIds)
    if type(roleIds) ~= 'table' then return false end
    for _, rid in ipairs(roleIds) do
      if AZH.hasDiscordRole(src, rid) then return true end
    end
    return false
  end

  function AZH.getJobName(src)
    src = tonumber(src)
    if not src then return nil end

    if AZH.Framework and type(AZH.Framework.getPlayerJob) == 'function' then
      local j = AZH.Framework.getPlayerJob(src)
      if type(j) == 'string' and j ~= '' then return j:lower() end
    end

    local fw = getFw()
    if fw then
      local res = fwCallAny(fw, { 'getPlayerJob', 'GetPlayerJob' }, src)
      if type(res) == 'string' and res ~= '' then
        return tostring(res):lower()
      end
    end

    return nil
  end

  function AZH.isPolice(src)
    local job = AZH.getJobName(src)
    return AZH.inList(job, (Config and Config.Police and Config.Police.Jobs) or {})
  end

  function AZH.isAgent(src)
    if Config and Config.Perms and type(Config.Perms.AgentRoleIds) == 'table' and #Config.Perms.AgentRoleIds > 0 then
      if AZH.hasAnyDiscordRole(src, Config.Perms.AgentRoleIds) then
        return true
      end
    end
    local job = AZH.getJobName(src)
    return AZH.inList(job, (Config and Config.Agent and Config.Agent.Jobs) or {})
  end

  function AZH.getIdentifier(src)
    local charId = getCharId(src)
    if charId then
      return ('charid:%s'):format(charId)
    end

    local fw = getFw()
    if fw then
      local discordId = fwCallAny(fw, { 'getDiscordID', 'GetDiscordID', 'getDiscordId', 'GetDiscordId' }, src)
      if discordId and discordId ~= "" then
        return ('discord:%s'):format(discordId)
      end
    end

    local prio = (Config and Config.IdentifierPriority) or { 'license' }
    for _, typ in ipairs(prio) do
      local id = GetPlayerIdentifierByType(src, typ)
      if id and id ~= '' then return id end
    end
    local ids = GetPlayerIdentifiers(src)
    return ids and ids[1] or ('src:' .. tostring(src))
  end

  function AZH.getCharId(src)
    return getCharId(src)
  end

  function AZH.getCharID(src)
    return getCharId(src)
  end

  function AZH.getDiscordID(src)
    local fw = getFw()
    if fw then
      local discordId = fwCallAny(fw, { 'getDiscordID', 'GetDiscordID', 'getDiscordId', 'GetDiscordId' }, src)
      if discordId and tostring(discordId) ~= '' then
        return tostring(discordId)
      end
    end

    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
      if type(id) == 'string' and id:sub(1, 8) == 'discord:' then
        return id:sub(9)
      end
    end

    return nil
  end

  AZH.getDiscordId = AZH.getDiscordID

  function AZH.normIdentifier(v)
    if v == nil then return nil end
    local s = tostring(v)
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    local sl = string.lower(s)
    if sl == '0' or sl == 'null' or sl == 'none' or sl == 'false' or sl == 'nil' or sl == 'n/a' or sl == 'na' or sl == 'undefined' then
      return nil
    end
    if string.sub(s, 1, 5) == 'char:' then
      s = 'charid:' .. string.sub(s, 6)
    end
    return s
  end

  function AZH.isCharacterScopedOwnership()
    return (Config == nil or Config.CharacterScopedOwnership ~= false)
  end

  function AZH.getHousingIdentifier(src)
    src = tonumber(src)
    if not src then return nil end

    if AZH.isCharacterScopedOwnership() then
      local charId = getCharId(src)
      if charId then
        return ('charid:%s'):format(charId)
      end
      return nil
    end

    return AZH.getIdentifier(src)
  end

  local function buildIdentifierAliasSet(src, includeAccountAliases)
    src = tonumber(src)
    if not src then return {} end

    local set = {}
    local function add(v)
      v = AZH.normIdentifier(v)
      if not v then return end
      set[v] = true
      if string.sub(v, 1, 7) == 'charid:' then
        local raw = string.sub(v, 8)
        if raw and raw ~= '' then
          set['char:' .. raw] = true
        end
      end
    end

    add(AZH.getHousingIdentifier(src))

    if not includeAccountAliases then
      return set
    end

    add(AZH.getIdentifier(src))
    add(GetPlayerIdentifierByType(src, 'license'))
    add(GetPlayerIdentifierByType(src, 'steam'))
    add(GetPlayerIdentifierByType(src, 'discord'))

    local prio = (Config and Config.IdentifierPriority) or { 'license' }
    for _, typ in ipairs(prio) do
      add(GetPlayerIdentifierByType(src, typ))
    end

    local all = GetPlayerIdentifiers(src) or {}
    for i = 1, #all do
      add(all[i])
    end

    local did = AZH.getDiscordID(src)
    if did and tostring(did) ~= '' then
      add('discord:' .. tostring(did))
    end

    return set
  end

  function AZH.getCharacterIdentifierAliases(src)
    return buildIdentifierAliasSet(src, false)
  end

  function AZH.getAllIdentifierAliases(src)
    return buildIdentifierAliasSet(src, true)
  end

  function AZH.getIdentifierAliases(src)
    if AZH.isCharacterScopedOwnership() then
      return AZH.getCharacterIdentifierAliases(src)
    end
    return AZH.getAllIdentifierAliases(src)
  end

  function AZH.isAdmin(src)
    src = tonumber(src)
    if not src then return false end
    if AZH.Framework and type(AZH.Framework.isAdmin) == 'function' then
      local ok, res = pcall(AZH.Framework.isAdmin, src)
      if ok then return res == true end
    end
    return false
  end

else

  local reqSeq = 0
  local pending = {}

  local function haveOxCallback()
    return (GetResourceState('ox_lib') == 'started' and lib and lib.callback and lib.callback.await)
  end

  RegisterNetEvent('az_housing:client:getJobRes', function(reqId, job)
    local p = pending[reqId]
    if p then pending[reqId] = nil; p:resolve(job) end
  end)

  RegisterNetEvent('az_housing:client:isPoliceRes', function(reqId, ok, job)
    local p = pending[reqId]
    if p then pending[reqId] = nil; p:resolve({ ok = ok == true, job = job }) end
  end)

  RegisterNetEvent('az_housing:client:isAdminRes', function(reqId, ok)
    local p = pending[reqId]
    if p then pending[reqId] = nil; p:resolve(ok == true) end
  end)

  local function serverGetJob()
    if haveOxCallback() then
      return lib.callback.await('az_housing:cb:getJob', false)
    end

    reqSeq = reqSeq + 1
    local id = reqSeq
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('az_housing:server:getJobReq', id)
    return Citizen.Await(p)
  end

  local function serverIsPolice()
    if haveOxCallback() then
      local ok, job = lib.callback.await('az_housing:cb:isPolice', false)
      return ok == true, job
    end

    reqSeq = reqSeq + 1
    local id = reqSeq
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('az_housing:server:isPoliceReq', id)
    local out = Citizen.Await(p)
    if out then return out.ok == true, out.job end
    return false, nil
  end

  local function serverIsAdmin()
    if haveOxCallback() then
      local ok = lib.callback.await('az_housing:cb:isAdmin', false)
      return ok == true
    end

    reqSeq = reqSeq + 1
    local id = reqSeq
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('az_housing:server:isAdminReq', id)
    return Citizen.Await(p) == true
  end

  local cache = {
    job = nil,
    police = false,
    admin = false,
    last = 0,
    ttl = 1500
  }

  function AZH.refreshJobCache(force)
    local t = GetGameTimer()
    if not force and (t - cache.last) < cache.ttl then
      return cache.job, cache.police, cache.admin
    end

    local okPolice, job = serverIsPolice()
    cache.police = okPolice == true
    if type(job) == 'string' and job ~= '' then
      cache.job = tostring(job):lower()
    else
      cache.job = nil
    end

    cache.admin = serverIsAdmin() == true
    cache.last = t

    if Config and Config.Debug then
      AZH.dprint(('cache -> job=%s police=%s admin=%s'):format(tostring(cache.job), tostring(cache.police), tostring(cache.admin)))
    end

    return cache.job, cache.police, cache.admin
  end

  function AZH.getJobName()
    local job = select(1, AZH.refreshJobCache(false))

    if not job then
      local st = LocalPlayer and LocalPlayer.state or nil
      local j = AZH.getJobNameFromState(st)
      if type(j) == 'string' and j ~= '' then return tostring(j):lower() end
    end
    return job
  end

  function AZH.isPolice()
    local _, police = AZH.refreshJobCache(false)
    return police == true
  end

  function AZH.isAdmin()
    local _, _, admin = AZH.refreshJobCache(false)
    return admin == true
  end

  function AZH.isAgent()
    local job = AZH.getJobName()
    return AZH.inList(job, (Config and Config.Agent and Config.Agent.Jobs) or {})
  end
end
