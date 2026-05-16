AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end

Config.LastPosAutoSaveEnabled = (Config.LastPosAutoSaveEnabled ~= false)
Config.LastPosAutoSaveIntervalMs = tonumber(Config.LastPosAutoSaveIntervalMs) or 10000
Config.Images = Config.Images or {}
Config.Images.Enabled = (Config.Images.Enabled ~= false)
Config.Images.MaxPerHouse = tonumber(Config.Images.MaxPerHouse) or 8
Config.Images.MaxBytes = tonumber(Config.Images.MaxBytes) or (1024 * 1024 * 2)
Config.Images.AllowUrl = (Config.Images.AllowUrl ~= false)
Config.Images.AllowUpload = (Config.Images.AllowUpload ~= false)
local RESOURCE = GetCurrentResourceName()

local Storage = nil

local Houses = {}
local Doors  = {}
local Garages= {}

local Keys   = {}
local Rentals= {}
local Apps   = {}

local Occupants = {}
local ForcedUnlockedUntil = {}
local BreachCooldown = {}

local Mailbox = {}
local Furniture = {}
local Upgrades = {}

local function now()
  return os.time()
end

local HouseImages = {}

local function approxBase64Bytes(b64)
  if type(b64) ~= 'string' then return 0 end
  local len = #b64
  local padding = 0
  if b64:sub(-2) == '==' then padding = 2
  elseif b64:sub(-1) == '=' then padding = 1 end
  return math.floor((len * 3) / 4) - padding
end

local function dbHas()
  if not MySQL then return false end
  if type(MySQL.query) == 'function' and type(MySQL.query.await) == 'function' then return true end
  if type(MySQL.query) == 'table' and type(MySQL.query.await) == 'function' then return true end
  if type(MySQL.query) == 'function' then return true end
  return false
end

local function dbQuery(sql, params)
  params = params or {}
  if not MySQL or not MySQL.query then return nil end

  if type(MySQL.query.await) == 'function' then
    local ok, res = pcall(function()
      return MySQL.query.await(sql, params)
    end)
    if ok then return res end
    return nil
  end

  local ok, res = pcall(function()
    return MySQL.query(sql, params)
  end)
  if ok then return res end
  return nil
end

local function loadImagesDb(houseId)
  if not (Config.Images.Enabled and dbHas()) then
    HouseImages[houseId] = HouseImages[houseId] or {}
    return HouseImages[houseId]
  end

  local rows = dbQuery([[
    SELECT id, house_id, sort_order, title, url, data, mime, size_bytes, created_at
    FROM az_housing_images
    WHERE house_id = ?
    ORDER BY sort_order ASC, id ASC
  ]], { houseId }) or {}

  if type(rows) ~= 'table' then rows = {} end

  HouseImages[houseId] = rows
  return rows
end

local function deleteImageDb(houseId, imageId)
  if not (Config.Images.Enabled and dbHas()) then return end
  dbQuery('DELETE FROM az_housing_images WHERE id = ? AND house_id = ?', { imageId, houseId })
end

local function insertImageDb(houseId, title, url, mime, data, sizeBytes)
  if not (Config.Images.Enabled and dbHas()) then return end
  dbQuery([[
    INSERT INTO az_housing_images (house_id, sort_order, title, url, data, mime, size_bytes)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], { houseId, 0, title, url, data, mime, sizeBytes })
end
local function dprint(...)
  if Config and Config.Debug then
    print(('[%s:server]'):format(RESOURCE), ...)
  end
end

local function slog(action, src, houseId, extra)
  local ident = (src and AZH.getIdentifier and AZH.getIdentifier(src)) or "?"
  local h = houseId and Houses[houseId] or nil
  local hname = h and h.name or "?"
  print(('[az_housing:server] %s src=%s ident=%s house=%s(%s) %s'):format(
    tostring(action),
    tostring(src),
    tostring(ident),
    tostring(houseId),
    tostring(hname),
    extra and tostring(extra) or ''
  ))
end

local function toBool(v)
  if v == true then return true end
  if v == false then return false end
  if tonumber(v) == 1 then return true end
  return false
end

local function normIdent(v)
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

local function identOf(src)
  if AZH and type(AZH.getHousingIdentifier) == 'function' then
    return normIdent(AZH.getHousingIdentifier(src))
  end
  return normIdent(AZH.getIdentifier(src))
end

local function identNorm(v)
  return normIdent(v)
end

local function getAliasSet(src, identifier)
  local set = {}
  local function add(v)
    v = identNorm(v)
    if v then set[v] = true end
  end

  add(identifier)

  if src and AZH and type(AZH.getIdentifierAliases) == 'function' then
    local ok, aliases = pcall(AZH.getIdentifierAliases, src)
    if ok and type(aliases) == 'table' then
      for v, _ in pairs(aliases) do
        add(v)
      end
    end
  end

  return set
end

local function aliasMatches(src, identifier, value)
  value = identNorm(value)
  if not value then return false end
  local aliases = getAliasSet(src, identifier)
  return aliases[value] == true
end

local function aliasAnyKeyPerm(houseId, src, identifier)
  local map = Keys[houseId]
  if not map then return nil, nil end
  local aliases = getAliasSet(src, identifier)
  for alias, _ in pairs(aliases) do
    local perm = map[alias]
    if perm ~= nil then return perm, alias end
  end
  return nil, nil
end

local function aliasHasKey(houseId, src, identifier)
  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  return perm ~= nil
end

local function parseHouseId(v)
  if v == nil then return nil end
  if type(v) == 'number' then return tonumber(v) end
  local s = tostring(v)
  s = s:gsub('%D', '')
  return tonumber(s)
end

local function ensureHouseInstance(houseId)
  if not Occupants[houseId] then
    local bucket = (Config and Config.Buckets and Config.Buckets.Base or 500000) + tonumber(houseId)
    Occupants[houseId] = { bucket = bucket, players = {} }
  end
  return Occupants[houseId]
end

local function broadcastToOccupants(houseId, eventName, ...)
  local inst = Occupants[houseId]
  if not inst then return end
  for src, _ in pairs(inst.players) do
    TriggerClientEvent(eventName, src, ...)
  end
end

local function broadcastToPolice(eventName, ...)
  for _, pid in ipairs(GetPlayers()) do
    local src = tonumber(pid)
    if src and AZH.isPolice(src) then
      TriggerClientEvent(eventName, src, ...)
    end
  end
end

local function getPrimaryDoorCoords(houseId)
  for _, d in pairs(Doors) do
    if tonumber(d.house_id) == tonumber(houseId) then
      return { x = tonumber(d.x), y = tonumber(d.y), z = tonumber(d.z), label = tostring(d.label or 'Door'), doorId = tonumber(d.id) }
    end
  end
  return nil
end

local function hasKey(houseId, identifier)
  identifier = identNorm(identifier)
  if not identifier then return false end
  local map = Keys[houseId]
  if not map then return false end
  return map[identifier] ~= nil
end

local function keyPerm(houseId, identifier)
  identifier = identNorm(identifier)
  if not identifier then return nil end
  local map = Keys[houseId]
  if not map then return nil end
  return map[identifier]
end

local function isTenant(houseId, identifier)
  identifier = identNorm(identifier)
  if not identifier then return false end
  local r = Rentals[houseId]
  local t = r and identNorm(r.tenant_identifier) or nil
  return (t ~= nil and t == identifier)
end

local function isOwner(houseId, identifier)
  identifier = identNorm(identifier)
  if not identifier then return false end
  local h = Houses[houseId]
  local o = h and identNorm(h.owner_identifier) or nil
  return (o ~= nil and o == identifier)
end

local function canEnter(houseId, identifier, isPolice, src)
  local h = Houses[houseId]
  if not h then return false, 'Unknown property' end

  identifier = identNorm(identifier)

  local forced = ForcedUnlockedUntil[houseId]
  if forced and forced > now() then
    return true
  end

  if not toBool(h.locked) then
    return true
  end

  if aliasMatches(src, identifier, h.owner_identifier) then
    return true
  end

  if aliasHasKey(houseId, src, identifier) then
    return true
  end

  local r = Rentals[houseId]
  if aliasMatches(src, identifier, r and r.tenant_identifier or nil) then
    return true
  end

  if isPolice and Config and Config.Police then
    return false, 'Locked. Use breach.'
  end

  return false, 'Locked'
end

local function getDiscordId(src)

  if AZH and type(AZH.getDiscordId) == 'function' then
    local v = AZH.getDiscordId(src)
    if v and tostring(v) ~= '' then return tostring(v) end
  end
  if AZH and type(AZH.getDiscordID) == 'function' then
    local v = AZH.getDiscordID(src)
    if v and tostring(v) ~= '' then return tostring(v) end
  end

  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if type(id) == 'string' and id:sub(1, 8) == 'discord:' then
      return id:sub(9)
    end
  end
  return nil
end

local function getCharIdForLastPos(src)

  if AZH and type(AZH.getCharId) == 'function' then
    local v = AZH.getCharId(src)
    if v and tostring(v) ~= '' then return tostring(v) end
  end
  if AZH and type(AZH.getCharID) == 'function' then
    local v = AZH.getCharID(src)
    if v and tostring(v) ~= '' then return tostring(v) end
  end

  local ident = nil
  if AZH and type(AZH.getIdentifier) == 'function' then ident = AZH.getIdentifier(src) end
  ident = ident and tostring(ident) or nil
  if ident and ident:sub(1, 6) == 'charid:' then
    return ident:sub(7)
  end

  if ident and ident:match('^%d+$') then
    return ident
  end

  return nil
end

local function upsertLastPos(discordId, charId, x, y, z, heading)
  if not (discordId and charId) then return end

  x = tonumber(x) or 0.0
  y = tonumber(y) or 0.0
  z = tonumber(z) or 0.0
  heading = tonumber(heading) or 0.0

  if MySQL and type(MySQL.query) == 'function' then
    MySQL.query([[
      INSERT INTO azfw_lastpos (discordid, charid, x, y, z, heading)
      VALUES (?, ?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE
        x = VALUES(x),
        y = VALUES(y),
        z = VALUES(z),
        heading = VALUES(heading),
        updated_at = CURRENT_TIMESTAMP
    ]], { discordId, charId, x, y, z, heading })
    return
  end

  if Storage and type(Storage.saveLastPos) == 'function' then
    pcall(function()
      Storage.saveLastPos(discordId, charId, x, y, z, heading)
    end)
  end
end

RegisterNetEvent('az_housing:server:saveLastPos', function(pos)
  local src = source
  if not (Config and Config.LastPosAutoSaveEnabled) then return end
  if type(pos) ~= 'table' then return end

  local discordId = getDiscordId(src)
  local charId = getCharIdForLastPos(src)
  if not (discordId and charId) then return end

  upsertLastPos(discordId, charId, pos.x, pos.y, pos.z, pos.h)
end)

local function canManage(houseId, identifier, src)
  if src and AZH.isAdmin(src) then return true end

  identifier = identNorm(identifier)
  if not identifier then return false end

  if aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil) then return true end
  if aliasMatches(src, identifier, Rentals[houseId] and Rentals[houseId].tenant_identifier or nil) then return true end

  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  if perm and (perm == 'owner' or perm == 'manage') then return true end

  return false
end

local function canAccessFeature(houseId, identifier, src)
  if src and AZH.isAdmin(src) then return true end

  identifier = identNorm(identifier)
  if not identifier then return false end

  if aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil) then return true end
  if aliasMatches(src, identifier, Rentals[houseId] and Rentals[houseId].tenant_identifier or nil) then return true end

  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  if perm ~= nil then return true end

  return false
end

local function canManageUpgradesFeature(houseId, identifier, src)
  if src and AZH.isAdmin(src) then return true end

  identifier = identNorm(identifier)
  if not identifier then return false end

  if aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil) then return true end

  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  if perm and (perm == 'owner' or perm == 'manage') then return true end

  return false
end

local function _azh_dbg(src, msg)
  print(('[az_housing][perm][src:%s] %s'):format(tostring(src or 'nil'), tostring(msg)))
end

local function canAccessFeature(houseId, identifier, src)
  _azh_dbg(src, ('canAccessFeature -> houseId=%s identifier(in)=%s'):format(tostring(houseId), tostring(identifier)))

  if src and AZH and AZH.isAdmin then
    local okAdmin = AZH.isAdmin(src)
    _azh_dbg(src, ('admin check: AZH.isAdmin(%s)=%s'):format(tostring(src), tostring(okAdmin)))
    if okAdmin then
      _azh_dbg(src, '=> ALLOW (admin)')
      return true
    end
  else
    _azh_dbg(src, 'admin check skipped (AZH.isAdmin missing or src nil)')
  end

  local norm = identNorm(identifier)
  _azh_dbg(src, ('identNorm(%s) => %s'):format(tostring(identifier), tostring(norm)))
  identifier = norm

  if not identifier then
    _azh_dbg(src, '=> DENY (identifier nil after identNorm)')
    return false
  end

  local owner = aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil)
  _azh_dbg(src, ('alias owner match(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(owner)))
  if owner then
    _azh_dbg(src, '=> ALLOW (owner)')
    return true
  end

  local tenant = aliasMatches(src, identifier, Rentals[houseId] and Rentals[houseId].tenant_identifier or nil)
  _azh_dbg(src, ('alias tenant match(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(tenant)))
  if tenant then
    _azh_dbg(src, '=> ALLOW (tenant)')
    return true
  end

  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  _azh_dbg(src, ('aliasAnyKeyPerm(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(perm)))

  if perm ~= nil then
    _azh_dbg(src, '=> ALLOW (has any key)')
    return true
  end

  _azh_dbg(src, '=> DENY (no admin/owner/tenant/key)')
  return false
end

local function canManageUpgradesFeature(houseId, identifier, src)
  _azh_dbg(src, ('canManageUpgradesFeature -> houseId=%s identifier(in)=%s'):format(tostring(houseId), tostring(identifier)))

  if src and AZH and AZH.isAdmin then
    local okAdmin = AZH.isAdmin(src)
    _azh_dbg(src, ('admin check: AZH.isAdmin(%s)=%s'):format(tostring(src), tostring(okAdmin)))
    if okAdmin then
      _azh_dbg(src, '=> ALLOW (admin)')
      return true
    end
  else
    _azh_dbg(src, 'admin check skipped (AZH.isAdmin missing or src nil)')
  end

  local norm = identNorm(identifier)
  _azh_dbg(src, ('identNorm(%s) => %s'):format(tostring(identifier), tostring(norm)))
  identifier = norm

  if not identifier then
    _azh_dbg(src, '=> DENY (identifier nil after identNorm)')
    return false
  end

  local owner = aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil)
  _azh_dbg(src, ('alias owner match(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(owner)))
  if owner then
    _azh_dbg(src, '=> ALLOW (owner)')
    return true
  end

  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  _azh_dbg(src, ('aliasAnyKeyPerm(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(perm)))

  local ok = (perm == 'owner' or perm == 'manage')
  _azh_dbg(src, ('perm purchase allowed? (owner/manage) => %s'):format(tostring(ok)))
  if ok then
    _azh_dbg(src, '=> ALLOW (owner/manage key)')
    return true
  end

  _azh_dbg(src, '=> DENY (not admin/owner/owner-manage key)')
  return false
end

local function canToggleLock(houseId, identifier, src)
  _azh_dbg(src, ('canToggleLock -> houseId=%s identifier(in)=%s'):format(tostring(houseId), tostring(identifier)))

  if src and AZH and AZH.isAdmin then
    local okAdmin = AZH.isAdmin(src)
    _azh_dbg(src, ('admin check: AZH.isAdmin(%s)=%s'):format(tostring(src), tostring(okAdmin)))
    if okAdmin then
      _azh_dbg(src, '=> ALLOW (admin)')
      return true
    end
  else
    _azh_dbg(src, 'admin check skipped (AZH.isAdmin missing or src nil)')
  end

  local norm = identNorm(identifier)
  _azh_dbg(src, ('identNorm(%s) => %s'):format(tostring(identifier), tostring(norm)))
  identifier = norm

  if not identifier then
    _azh_dbg(src, '=> DENY (identifier nil after identNorm)')
    return false
  end

  local owner = aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil)
  _azh_dbg(src, ('alias owner match(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(owner)))
  if owner then
    _azh_dbg(src, '=> ALLOW (owner)')
    return true
  end

  local tenant = aliasMatches(src, identifier, Rentals[houseId] and Rentals[houseId].tenant_identifier or nil)
  _azh_dbg(src, ('alias tenant match(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(tenant)))
  if tenant then
    _azh_dbg(src, '=> ALLOW (tenant)')
    return true
  end

  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  _azh_dbg(src, ('aliasAnyKeyPerm(%s,%s) => %s'):format(tostring(houseId), tostring(identifier), tostring(perm)))

  local ok = (perm == 'owner' or perm == 'manage' or perm == 'lock')
  _azh_dbg(src, ('perm lock allowed? (owner/manage/lock) => %s'):format(tostring(ok)))
  if ok then
    _azh_dbg(src, '=> ALLOW (key perm)')
    return true
  end

  _azh_dbg(src, '=> DENY (not admin/owner/tenant/lock-manage-owner key)')
  return false
end

local function canManageUpgradesFeature(houseId, identifier, src)
  if src and AZH.isAdmin(src) then return true end
  identifier = identNorm(identifier)
  if not identifier then return false end
  if aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil) then return true end
  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  if perm and (perm == 'owner' or perm == 'manage') then return true end
  return false
end

local function canToggleLock(houseId, identifier, src)
  if src and AZH.isAdmin(src) then return true end
  identifier = identNorm(identifier)
  if not identifier then return false end
  if aliasMatches(src, identifier, Houses[houseId] and Houses[houseId].owner_identifier or nil) then return true end
  if aliasMatches(src, identifier, Rentals[houseId] and Rentals[houseId].tenant_identifier or nil) then return true end
  local perm = aliasAnyKeyPerm(houseId, src, identifier)
  if perm and (perm == 'owner' or perm == 'manage' or perm == 'lock') then return true end
  return false
end

local function storageHas(fn)
  return Storage and type(Storage[fn]) == 'function'
end

local function decodeImageState(raw)
  if raw == nil then return { items = {}, primaryId = nil } end
  if type(raw) == 'table' then
    raw.items = raw.items or {}
    return raw
  end
  local s = tostring(raw)
  if s == '' then return { items = {}, primaryId = nil } end
  local ok, obj = pcall(json.decode, s)
  if not ok or type(obj) ~= 'table' then return { items = {}, primaryId = nil } end
  obj.items = obj.items or {}
  return obj
end

local function normalizeImageState(st)
  st = st or {}
  st.items = st.items or {}

  for _, im in ipairs(st.items) do
    if im and im.id ~= nil then im.id = tonumber(im.id) or im.id end
  end
  if st.primaryId ~= nil then st.primaryId = tonumber(st.primaryId) or st.primaryId end
  return st
end

local function computePrimaryCoverUrl(st)
  st = normalizeImageState(st)
  local pid = st.primaryId
  local items = st.items or {}
  local primary = nil
  if pid ~= nil then
    for _, im in ipairs(items) do
      if tonumber(im.id) == tonumber(pid) then primary = im break end
    end
  end
  if not primary and #items > 0 then primary = items[1] end
  if not primary then return nil end
  if primary.url and tostring(primary.url) ~= '' then return tostring(primary.url) end

  if primary.data and primary.mime then
    return ('data:%s;base64,%s'):format(tostring(primary.mime), tostring(primary.data))
  end
  return nil
end

local function getHouseImageState(houseId)
  local h = Houses[houseId]
  if not h then return { items = {}, primaryId = nil } end
  return normalizeImageState(decodeImageState(h.image_data))
end

local function persistHouseImages(houseId, st)
  st = normalizeImageState(st)
  local cover = computePrimaryCoverUrl(st)
  local enc = json.encode(st)

  if dbHas() then
    pcall(function()
      dbQuery('UPDATE az_houses SET image_url = ?, image_data = ? WHERE id = ?', { cover, enc, houseId })
    end)
  end

  if Houses[houseId] then
    Houses[houseId].image_url = cover
    Houses[houseId].image_data = enc
  end

  return cover
end

if lib and lib.callback and lib.callback.register then

  lib.callback.register('az_housing:cb:loadHouseExtras', function(src, houseId)
    houseId = parseHouseId(houseId)
    if not houseId or not Houses[houseId] then
      return { ok=false, error='invalid_house' }
    end

    local ident = identOf(src)

    local canView = canAccessFeature(houseId, ident, src)
    if not canView then
      return { ok=false, error='no_access' }
    end

    local canUpManage = canManageUpgradesFeature(houseId, ident, src)

    local limits = nil
    if AZH and type(AZH.getHouseLimits) == 'function' then
      local ok, val = pcall(function() return AZH.getHouseLimits(houseId) end)
      if ok and type(val) == 'table' then limits = val end
    end
    limits = limits or {
      mailboxCap = (Config.Mailbox and (Config.Mailbox.BaseCapacity or Config.Mailbox.Capacity)) or 25,
      furnitureLimit = (Config.Furniture and (Config.Furniture.MaxPerHouse or Config.Furniture.Limit)) or 25,
      stashSlots = 20,
      stashWeight = 20000,
    }

    local mailbox = { ok=false, error='disabled', capacity=0, unread=0, messages={} }
    if Config.Mailbox and Config.Mailbox.Enabled then
      mailbox.ok = true
      mailbox.capacity = tonumber(limits.mailboxCap) or 25
      mailbox.messages = (Storage and Storage.listMail and Storage.listMail(houseId, 75)) or {}
      local unread = 0
      for _, m in ipairs(mailbox.messages) do
        local r = m.is_read
        if r == 0 or r == false or r == nil then unread = unread + 1 end
      end
      mailbox.unread = unread
    end

    local furniture = { ok=false, error='disabled', limit=0, furniture={} }
    if Config.Furniture and Config.Furniture.Enabled then
      furniture.ok = true
      furniture.limit = tonumber(limits.furnitureLimit) or 25
      furniture.furniture = (Storage and Storage.listFurniture and Storage.listFurniture(houseId)) or {}
    end

    local upgrades = { ok=false, error='disabled', canManage=canUpManage, upgrades={}, limits=limits }
    if Config.Upgrades and Config.Upgrades.Enabled ~= false then
      upgrades.ok = true
      if AZH and type(AZH.getHouseUpgrades) == 'function' then
        local ok, u = pcall(function() return AZH.getHouseUpgrades(houseId) end)
        if ok and type(u) == 'table' then upgrades.upgrades = u end
      elseif Storage and Storage.getUpgrades then
        upgrades.upgrades = Storage.getUpgrades(houseId) or {}
      end
    end

    local images = {
      ok = false,
      error = 'no_access',
      max = Config.Images and Config.Images.MaxPerHouse or 0,
      maxBytes = Config.Images and Config.Images.MaxBytes or 0,
      items = {},
      primaryImageId = nil
    }
    if Config.Images and Config.Images.Enabled and canUpManage then
      images.ok = true
      local st = getHouseImageState(houseId)
      images.items = st.items or {}
      images.primaryImageId = st.primaryId
    elseif not (Config.Images and Config.Images.Enabled) then
      images.error = 'disabled'
    end

    return {
      ok = true,
      mailbox = mailbox,
      upgrades = upgrades,
      furniture = furniture,
      images = images,
    }
  end)

  lib.callback.register('az_housing:cb:addHouseImage', function(src, houseId, payload)
    houseId = parseHouseId(houseId)
    if not houseId or not Houses[houseId] then return { ok=false, error='invalid_house' } end

    local ident = identOf(src)
    if not canManage(houseId, ident, src) then
      return { ok=false, error='no_access' }
    end

    if not Config.Images.Enabled then
      return { ok=false, error='images_disabled' }
    end

    payload = payload or {}
    local setPrimaryId = payload.setPrimaryId and tonumber(payload.setPrimaryId) or nil

    local title = tostring(payload.title or payload.caption or ''):sub(1, 64)
    local url = payload.url and tostring(payload.url) or nil
    local mime = payload.mime and tostring(payload.mime) or nil
    local data = payload.data and tostring(payload.data) or nil

    if (not data or data == '') and payload.dataUrl then
      local du = tostring(payload.dataUrl)
      local m = du:match('^data:(.-);base64,(.+)$')
      if m then
        mime = du:match('^data:(.-);base64,')
        data = du:match('^data:.-;base64,(.+)$')
      end
    end

    local st = getHouseImageState(houseId)

    if setPrimaryId then
      st.primaryId = setPrimaryId
      persistHouseImages(houseId, st)
      return { ok=true, items=st.items, primaryId=st.primaryId }
    end

    if #st.items >= Config.Images.MaxPerHouse then
      return { ok=false, error='max_reached', max=Config.Images.MaxPerHouse, items=st.items }
    end

    local usingUrl = (url and url ~= '')
    local usingUpload = (data and data ~= '')

    if usingUrl then
      if not (Config.Images.AllowUrl ~= false) then return { ok=false, error='url_disabled' } end
      if not url:match('^https?://') then return { ok=false, error='invalid_url' } end
    elseif usingUpload then
      if not (Config.Images.AllowUpload ~= false) then return { ok=false, error='upload_disabled' } end
      if not mime or mime == '' then return { ok=false, error='missing_mime' } end
      local bytes = approxBase64Bytes(data)
      if bytes <= 0 then return { ok=false, error='invalid_data' } end
      if bytes > Config.Images.MaxBytes then
        return { ok=false, error='too_large', maxBytes=Config.Images.MaxBytes, sizeBytes=bytes }
      end
    else
      return { ok=false, error='no_payload' }
    end

    local maxId = 0
    for _, im in ipairs(st.items) do
      local id = tonumber(im.id) or 0
      if id > maxId then maxId = id end
    end
    local newId = maxId + 1

    local item = {
      id = newId,
      title = title,
      created_at = os.time(),
    }
    if usingUrl then
      item.url = url
    else
      item.mime = mime
      item.data = data
    end

    table.insert(st.items, item)
    if st.primaryId == nil then st.primaryId = newId end

    persistHouseImages(houseId, st)
    return { ok=true, items=st.items, primaryId=st.primaryId, max=Config.Images.MaxPerHouse, maxBytes=Config.Images.MaxBytes }
  end)

  lib.callback.register('az_housing:cb:deleteHouseImage', function(src, houseId, imageId)
    houseId = parseHouseId(houseId)
    imageId = tonumber(imageId)
    if not houseId or not Houses[houseId] or not imageId then return { ok=false, error='bad_args' } end

    local ident = identOf(src)
    if not canManage(houseId, ident, src) then
      return { ok=false, error='no_access' }
    end

    if not Config.Images.Enabled then
      return { ok=false, error='images_disabled' }
    end

    local st = getHouseImageState(houseId)
    local out = {}
    for _, im in ipairs(st.items or {}) do
      if tonumber(im.id) ~= tonumber(imageId) then table.insert(out, im) end
    end
    st.items = out
    if st.primaryId ~= nil and tonumber(st.primaryId) == tonumber(imageId) then
      st.primaryId = (#st.items > 0) and tonumber(st.items[1].id) or nil
    end

    persistHouseImages(houseId, st)
    return { ok=true, items=st.items, primaryId=st.primaryId }
  end)

end

local function storageHas(fn)
  return Storage and type(Storage[fn]) == 'function'
end

local function safeStorageInit()
  Storage = AZH.Storage
  if not Storage then
    print(('[%s:server]^1 ERROR^7: AZH.Storage is nil'):format(RESOURCE))
    return false
  end
  if storageHas('init') then
    Storage.init()
  end
  return true
end

local function ensureCanonicalKeys()
  for hid, h in pairs(Houses) do
    local owner = identNorm(h.owner_identifier)
    if owner then
      Keys[hid] = Keys[hid] or {}
      if not Keys[hid][owner] then
        Keys[hid][owner] = 'owner'
        if storageHas('setKey') then pcall(function() Storage.setKey(hid, owner, 'owner') end) end
      end
    end

    local r = Rentals[hid]
    local tenant = r and identNorm(r.tenant_identifier) or nil
    if tenant then
      Keys[hid] = Keys[hid] or {}
      if not Keys[hid][tenant] then
        Keys[hid][tenant] = 'enter'
        if storageHas('setKey') then pcall(function() Storage.setKey(hid, tenant, 'enter') end) end
      end
    end
  end
end

local function loadFromStorage()
  if not safeStorageInit() then return end

  local all = {}
  if storageHas('loadAll') then
    all = Storage.loadAll() or {}
  end

  Houses, Doors, Garages, Keys, Rentals, Apps = {}, {}, {}, {}, {}, {}
  Mailbox, Furniture, Upgrades = {}, {}, {}

  for _, r in ipairs(all.houses or {}) do
    local id = tonumber(r.id)
    Houses[id] = {
      id = id,
      name = tostring(r.name or ('House ' .. id)),
      label = tostring(r.label or ''),
      price = tonumber(r.price) or (Config.Defaults and Config.Defaults.SalePrice) or 0,
      interior = tostring(r.interior or 'apt_basic'),
      locked = toBool(r.locked),
      owner_identifier = normIdent(r.owner_identifier),
      for_sale = (r.for_sale ~= nil) and toBool(r.for_sale) or nil,
      for_rent = (r.for_rent ~= nil) and toBool(r.for_rent) or nil,
      rent_per_week = (r.rent_per_week ~= nil) and (tonumber(r.rent_per_week) or 0) or nil,
      deposit = (r.deposit ~= nil) and (tonumber(r.deposit) or 0) or nil,

      image_url = (r.image_url ~= nil and tostring(r.image_url) ~= '') and tostring(r.image_url) or nil,
      image_data = (r.image_data ~= nil and tostring(r.image_data) ~= '') and tostring(r.image_data) or nil,
    }
  end

  for _, r in ipairs(all.doors or {}) do
    local id = tonumber(r.id)
    Doors[id] = {
      id = id,
      house_id = tonumber(r.house_id),
      x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
      heading = tonumber(r.heading) or 0.0,
      radius = tonumber(r.radius) or 2.0,
      label = tostring(r.label or 'Door')
    }
  end

  for _, r in ipairs(all.garages or {}) do
    local id = tonumber(r.id)
    Garages[id] = {
      id = id,
      house_id = tonumber(r.house_id),
      x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
      heading = tonumber(r.heading) or 0.0,
      spawn_x = tonumber(r.spawn_x), spawn_y = tonumber(r.spawn_y), spawn_z = tonumber(r.spawn_z), spawn_h = tonumber(r.spawn_h) or 0.0,
      radius = tonumber(r.radius) or (Config.Garage and Config.Garage.DefaultRadius or 2.2),
      label = tostring(r.label or 'Garage')
    }
  end

  for _, r in ipairs(all.keys or {}) do
    local hid = tonumber(r.house_id)
    local kid = normIdent(r.identifier)
    if hid and kid then
      Keys[hid] = Keys[hid] or {}
      Keys[hid][kid] = tostring(r.perms or 'enter')
    end
  end

  for _, r in ipairs(all.rentals or {}) do
    local hid = tonumber(r.house_id)
    local st = tostring(r.status or 'available')
    local stl = string.lower(st)
    local listed = toBool(r.is_listed)
    if not listed and (stl == 'listed' or stl == 'available' or stl == 'open' or stl == 'active') then
      listed = true
    end

Rentals[hid] = {
  house_id = hid,
  is_listed = listed,
  rent_per_week = tonumber(r.rent_per_week) or tonumber(r.rentPerWeek) or ((Config.Defaults and Config.Defaults.RentPerWeek) or 0),
  deposit = tonumber(r.deposit) or ((Config.Defaults and Config.Defaults.Deposit) or 0),
  tenant_identifier = normIdent(r.tenant_identifier),
  agent_identifier = normIdent(r.agent_identifier),
  status = st,
  tenant_name = r.tenant_name and tostring(r.tenant_name) or nil,
  start_ts = tonumber(r.start_ts) or nil,
  end_ts = tonumber(r.end_ts) or nil,
}

  end

  for hid, h in pairs(Houses) do
    if not Rentals[hid] then
      local shouldList = toBool(h.for_rent) or (tonumber(h.rent_per_week or 0) > 0)
      if shouldList then
        Rentals[hid] = {
          house_id = hid,
          is_listed = true,
          rent_per_week = tonumber(h.rent_per_week) or ((Config.Defaults and Config.Defaults.RentPerWeek) or 0),
          deposit = tonumber(h.deposit) or ((Config.Defaults and Config.Defaults.Deposit) or 0),
          tenant_identifier = nil,
          agent_identifier = nil,
          status = 'available'
        }
      end
    end
  end

  if all.mailbox then Mailbox = all.mailbox end
  if all.furniture then Furniture = all.furniture end
  if all.upgrades then Upgrades = all.upgrades end

  Apps = all.apps or {}

  ensureCanonicalKeys()

  AZH.State = { Houses = Houses, Doors = Doors, Garages = Garages, Keys = Keys, Rentals = Rentals }
end

if lib and lib.callback and lib.callback.register then
  lib.callback.register('az_housing:cb:getAgentApps', function(src)
    local isAdmin = (AZH.isAdmin(src) == true)
    local roleAgent = (AZH.isAgent and AZH.isAgent(src) == true) or false

    local agentHouse = {}

    if not (isAdmin or roleAgent) then
      local ident = identOf(src)
      for hid, h in pairs(Houses) do
        if h and ident and identNorm(h.owner_identifier) == ident then
          local r = Rentals[hid]
          if r then
            local hasTenant = identNorm(r.tenant_identifier) ~= nil
            local listed = toBool(r.is_listed)
            local st = tostring(r.status or ''):lower()
            if st == 'listed' or st == 'available' or st == 'open' or st == 'active' then listed = true end
            if listed or hasTenant or st == 'leased' or st == 'rented' then
              agentHouse[hid] = true
            end
          end
        end
      end

      if next(agentHouse) == nil then
        return {}
      end
    end

    local all = storageHas('loadAll') and (Storage.loadAll() or {}) or {}
    local apps = all.apps or {}

    local out = {}
    for _, a in ipairs(apps) do
      local hid = tonumber(a.house_id)
      if hid and (isAdmin or roleAgent or agentHouse[hid]) then
        a.house_name = (Houses[hid] and Houses[hid].name) or a.house_name
        local r = Rentals[hid]
        if r then
          a.rent_per_week = tonumber(r.rent_per_week) or a.rent_per_week
          a.deposit = tonumber(r.deposit) or a.deposit
        end
        out[#out+1] = a
      end
    end

    return out
  end)
end

local function isCharIdent(v)
  v = identNorm(v)
  return v ~= nil and string.sub(v, 1, 7) == 'charid:'
end

local function permRank(v)
  local s = tostring(v or 'enter'):lower()
  if s == 'owner' then return 30 end
  if s == 'manage' then return 20 end
  return 10
end

local function strongestPerm(a, b)
  if a == nil then return b end
  if b == nil then return a end
  if permRank(b) > permRank(a) then return b end
  return a
end

local function migrateLegacyIdentifiersForSource(src)
  src = tonumber(src)
  if not src or not (Config == nil or Config.CharacterScopedOwnership ~= false) then
    return false
  end

  local charIdent = identOf(src)
  if not isCharIdent(charIdent) then
    return false
  end

  local aliasSet = (AZH and type(AZH.getAllIdentifierAliases) == 'function' and AZH.getAllIdentifierAliases(src)) or {}
  if next(aliasSet) == nil then
    return false
  end

  local changed = false

  for hid, h in pairs(Houses) do
    local owner = identNorm(h and h.owner_identifier or nil)
    if owner and owner ~= charIdent and not isCharIdent(owner) and aliasSet[owner] then
      h.owner_identifier = charIdent
      if storageHas('saveHouse') then pcall(function() Storage.saveHouse(h) end) end
      changed = true
    end
  end

  for hid, r in pairs(Rentals) do
    local dirty = false

    local tenant = identNorm(r and r.tenant_identifier or nil)
    if tenant and tenant ~= charIdent and not isCharIdent(tenant) and aliasSet[tenant] then
      r.tenant_identifier = charIdent
      r.tenant_name = r.tenant_name or GetPlayerName(src)
      dirty = true
    end

    local agent = identNorm(r and r.agent_identifier or nil)
    if agent and agent ~= charIdent and not isCharIdent(agent) and aliasSet[agent] then
      r.agent_identifier = charIdent
      dirty = true
    end

    if dirty then
      if storageHas('upsertRental') then pcall(function() Storage.upsertRental(r) end) end
      changed = true
    end
  end

  for hid, map in pairs(Keys) do
    if type(map) == 'table' then
      local addPerm = nil
      local remove = {}
      for alias, perm in pairs(map) do
        local aid = identNorm(alias)
        if aid and aid ~= charIdent and not isCharIdent(aid) and aliasSet[aid] then
          addPerm = strongestPerm(addPerm, perm)
          remove[#remove + 1] = aid
        end
      end

      if addPerm ~= nil then
        map[charIdent] = strongestPerm(map[charIdent], addPerm)
        if storageHas('setKey') then pcall(function() Storage.setKey(hid, charIdent, map[charIdent]) end) end
        changed = true
      end

      for i = 1, #remove do
        local oldId = remove[i]
        map[oldId] = nil
        if storageHas('revokeKey') then pcall(function() Storage.revokeKey(hid, oldId) end) end
      end
    end
  end

  if changed then
    ensureCanonicalKeys()
  end

  return changed
end

local function makeBootstrap()
  local housesArr, doorsArr, garagesArr, rentalsArr = {}, {}, {}, {}
  for _, h in pairs(Houses) do housesArr[#housesArr+1] = h end
  for _, d in pairs(Doors) do doorsArr[#doorsArr+1] = d end
  for _, g in pairs(Garages) do garagesArr[#garagesArr+1] = g end
  for _, r in pairs(Rentals) do rentalsArr[#rentalsArr+1] = r end

  table.sort(housesArr, function(a,b) return a.id < b.id end)
  table.sort(doorsArr, function(a,b) return a.id < b.id end)
  table.sort(garagesArr, function(a,b) return a.id < b.id end)
  table.sort(rentalsArr, function(a,b) return a.house_id < b.house_id end)

  return {
    houses = housesArr,
    doors = doorsArr,
    garages = garagesArr,
    rentals = rentalsArr,
    interiors = Config.Interiors
  }
end

local function makeBootstrapFor(src)
  local b = makeBootstrap()
  b.identifier = identOf(src)

  local aliasSet = (AZH and type(AZH.getIdentifierAliases) == 'function' and AZH.getIdentifierAliases(src)) or {}

  b.identifierAliases = {}
  for k, _ in pairs(aliasSet) do
    b.identifierAliases[#b.identifierAliases+1] = k
  end
  b.isAdmin = (AZH.isAdmin(src) == true)
  b.isPolice = (AZH.isPolice(src) == true)
  b.isAgentRole = (AZH.isAgent and AZH.isAgent(src) == true) or false

  return b
end

local function sendBootstrap(src)
  migrateLegacyIdentifiersForSource(src)
  TriggerClientEvent('az_housing:client:bootstrap', src, makeBootstrapFor(src))
end

local function broadcastBootstrapAll()
  for _, pid in ipairs(GetPlayers()) do
    local src = tonumber(pid)
    if src then
      sendBootstrap(src)
    end
  end
end

local function pushHouseRefresh(houseId)
  local h = Houses[houseId]
  if h then
    TriggerClientEvent('az_housing:client:updateHouse', -1, h)
  end
end

AddEventHandler('onResourceStart', function(res)
  if res ~= RESOURCE then return end
  CreateThread(function()
    Wait(250)
    loadFromStorage()
    dprint('Loaded houses:', tostring(#(makeBootstrap().houses)))
    broadcastBootstrapAll()
  end)
end)

RegisterNetEvent('az_housing:server:bootstrap', function()
  local src = source
  sendBootstrap(src)
end)

RegisterNetEvent('az_housing:server:knock', function(houseId)
  local src = source
  houseId = tonumber(houseId)
  if not houseId or not Houses[houseId] then return end

  local inst = ensureHouseInstance(houseId)
  if not inst then return end

  broadcastToOccupants(houseId, 'az_housing:client:knock', {
    houseId = houseId,
    src = src,
    name = GetPlayerName(src)
  })
end)

RegisterNetEvent('az_housing:server:toggleLock', function(houseId)
  local src = source
  houseId = parseHouseId(houseId)
  slog('toggleLock', src, houseId)

  local h = Houses[houseId]
  if not h then return end

  local ident = identOf(src)
  if not canToggleLock(houseId, ident, src) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner or tenant can lock/unlock this property.')
    return
  end

  h.locked = not toBool(h.locked)

  if storageHas('saveHouse') then Storage.saveHouse(h) end
  TriggerClientEvent('az_housing:client:updateHouse', -1, h)

  AZH.notify(src, 'inform', 'Housing', h.locked and 'Locked.' or 'Unlocked.')
end)

RegisterNetEvent('az_housing:server:breach', function(houseId)
  local src = source
  houseId = tonumber(houseId)
  if not houseId or not Houses[houseId] then return end

  if not AZH.isPolice(src) then
    AZH.notify(src, 'error', 'Housing', 'You are not authorized to breach doors.')
    return
  end

  local cd = BreachCooldown[src] or 0
  if cd > now() then
    AZH.notify(src, 'error', 'Housing', ('Breach on cooldown (%ss)'):format(cd - now()))
    return
  end
  BreachCooldown[src] = now() + ((Config.Police and Config.Police.BreachCooldownSec) or 30)

  ForcedUnlockedUntil[houseId] = now() + ((Config.Police and Config.Police.BreachUnlockSeconds) or 120)

  AZH.notify(src, 'success', 'Housing', 'Door breached. You can enter now.')
  broadcastToOccupants(houseId, 'az_housing:client:breach', { houseId = houseId })

  local d = getPrimaryDoorCoords(houseId)
  broadcastToPolice('az_housing:client:policeBreach', {
    houseId = houseId,
    houseName = (Houses[houseId] and Houses[houseId].name) or ('House #' .. tostring(houseId)),
    breacher = GetPlayerName(src),
    coords = d,
    untilTs = ForcedUnlockedUntil[houseId]
  })

  TriggerClientEvent('az_housing:client:forcedUnlock', -1, houseId, ForcedUnlockedUntil[houseId])
end)

RegisterNetEvent('az_housing:server:enter', function(houseId)
  local src = source
  houseId = tonumber(houseId)

  local h = Houses[houseId]
  if not h then
    AZH.notify(src, 'error', 'Housing', 'Unknown property.')
    return
  end

  local ident = identOf(src)
  local ok, reason = canEnter(houseId, ident, AZH.isPolice(src), src)
  if not ok then
    AZH.notify(src, 'error', 'Housing', reason or 'Cannot enter')
    return
  end

  local inst = ensureHouseInstance(houseId)
  inst.players[src] = true

  SetPlayerRoutingBucket(src, inst.bucket)

  local interiorKey = h.interior or 'apt_basic'
  local it = (Config.Interiors and Config.Interiors[interiorKey]) or (Config.Interiors and Config.Interiors.apt_basic) or nil

  TriggerClientEvent('az_housing:client:enter', src, {
    house = h,
    bucket = inst.bucket,
    interior = it,
  })
end)

RegisterNetEvent('az_housing:server:leave', function(houseId)
  local src = source
  houseId = tonumber(houseId)

  SetPlayerRoutingBucket(src, 0)

  local inst = Occupants[houseId]
  if inst and inst.players then
    inst.players[src] = nil
    local empty = true
    for _, _ in pairs(inst.players) do empty = false break end
    if empty then
      Occupants[houseId] = nil
    end
  end
end)

AddEventHandler('playerDropped', function()
  local src = source
  for _, inst in pairs(Occupants) do
    if inst.players and inst.players[src] then
      inst.players[src] = nil
    end
  end
end)

RegisterNetEvent('az_housing:server:buy', function(houseId)
  local src = source
  houseId = tonumber(houseId)

  local h = Houses[houseId]
  if not h then return end

  if identNorm(h.owner_identifier) then
    AZH.notify(src, 'error', 'Housing', 'This property is already owned.')
    return
  end

  local ident = identOf(src)
  if not ident then
    AZH.notify(src, 'error', 'Housing', 'No active character found for this purchase.')
    return
  end

  local price = tonumber(h.price) or ((Config.Defaults and Config.Defaults.SalePrice) or 0)

  if not AZH.moneyTake(src, price, 'Housing Purchase') then
    AZH.notify(src, 'error', 'Housing', 'Insufficient funds.')
    return
  end

  h.owner_identifier = ident
  h.locked = true

  if storageHas('saveHouse') then Storage.saveHouse(h) end

  Keys[houseId] = Keys[houseId] or {}
  Keys[houseId][ident] = 'owner'
  if storageHas('setKey') then Storage.setKey(houseId, ident, 'owner') end

  TriggerClientEvent('az_housing:client:updateHouse', -1, h)
  AZH.notify(src, 'success', 'Housing', ('You purchased %s'):format(h.name))
end)

RegisterNetEvent('az_housing:server:sellToPlayer', function(houseId, targetSrc, price)
  local src = source
  houseId = tonumber(houseId)
  targetSrc = tonumber(targetSrc)
  price = tonumber(price) or 0

  local h = houseId and Houses[houseId] or nil
  if not h then return end

  local sellerIdent = identOf(src)
  if not sellerIdent and not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'No active character found for this sale.')
    return
  end

  if not ((identNorm(h.owner_identifier) and identNorm(h.owner_identifier) == sellerIdent) or AZH.isAdmin(src)) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner can sell this property.')
    return
  end

  if not targetSrc or targetSrc <= 0 or not GetPlayerName(targetSrc) then
    AZH.notify(src, 'error', 'Housing', 'Target player must be online.')
    return
  end

  if tonumber(targetSrc) == tonumber(src) then
    AZH.notify(src, 'error', 'Housing', 'You cannot sell to yourself.')
    return
  end

  local r = Rentals[houseId]
  if r and identNorm(r.tenant_identifier) and not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'You cannot sell a property that currently has an active tenant.')
    return
  end

  local buyerIdent = identOf(targetSrc)
  if not buyerIdent then
    AZH.notify(src, 'error', 'Housing', 'Target player must have an active character loaded.')
    return
  end

  if identNorm(h.owner_identifier) and identNorm(h.owner_identifier) == buyerIdent then
    AZH.notify(src, 'error', 'Housing', 'That player already owns this property.')
    return
  end

  if price > 0 then
    if not AZH.moneyTake(targetSrc, price, 'Housing Purchase (Player Sale)') then
      AZH.notify(src, 'error', 'Housing', 'Buyer has insufficient funds.')
      AZH.notify(targetSrc, 'error', 'Housing', 'Insufficient funds to buy this property.')
      return
    end
    AZH.moneyGive(src, price, 'Housing Sale')
  end

  if Keys[houseId] then
    for ident, _ in pairs(Keys[houseId]) do
      if storageHas('revokeKey') then pcall(function() Storage.revokeKey(houseId, ident) end) end
    end
  end
  Keys[houseId] = {}

  h.owner_identifier = buyerIdent
  h.locked = true
  if storageHas('saveHouse') then Storage.saveHouse(h) end

  Keys[houseId][buyerIdent] = 'owner'
  if storageHas('setKey') then Storage.setKey(houseId, buyerIdent, 'owner') end

  TriggerClientEvent('az_housing:client:updateHouse', -1, h)

  AZH.notify(src, 'success', 'Housing', ('Sold %s to %s for $%s'):format(h.name, GetPlayerName(targetSrc), price))
  AZH.notify(targetSrc, 'success', 'Housing', ('You bought %s for $%s'):format(h.name, price))
end)

RegisterNetEvent('az_housing:server:grantKey', function(houseId, targetSrc)
  local src = source
  houseId = tonumber(houseId)
  targetSrc = tonumber(targetSrc)
  if not houseId or not targetSrc then return end

  local h = Houses[houseId]
  if not h then return end

  local ownerIdent = identOf(src)
  if not (isOwner(houseId, ownerIdent) or AZH.isAdmin(src)) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner can manage keys.')
    return
  end

  local tid = identOf(targetSrc)
  if not tid then
    AZH.notify(src, 'error', 'Housing', 'Unable to resolve target identifier.')
    return
  end

  Keys[houseId] = Keys[houseId] or {}
  Keys[houseId][tid] = 'enter'
  if storageHas('setKey') then Storage.setKey(houseId, tid, 'enter') end

  AZH.notify(src, 'success', 'Housing', ('Granted key to %s'):format(GetPlayerName(targetSrc)))
  AZH.notify(targetSrc, 'inform', 'Housing', ('You received a key for %s'):format(h.name))
end)

RegisterNetEvent('az_housing:server:revokeKey', function(houseId, identifier)
  local src = source
  houseId = tonumber(houseId)
  local h = Houses[houseId]
  if not h then return end

  local ownerIdent = identOf(src)
  if not (isOwner(houseId, ownerIdent) or AZH.isAdmin(src)) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner can manage keys.')
    return
  end

  identifier = identNorm(identifier)
  if not identifier then return end

  if identNorm(h.owner_identifier) == identifier then
    AZH.notify(src, 'error', 'Housing', 'Cannot revoke owner.')
    return
  end

  if storageHas('revokeKey') then Storage.revokeKey(houseId, identifier) end
  if Keys[houseId] then Keys[houseId][identifier] = nil end

  AZH.notify(src, 'success', 'Housing', 'Key revoked.')
end)

RegisterNetEvent('az_housing:server:listForRent', function(houseId, rentPerWeek, deposit)
  local src = source
  houseId = tonumber(houseId)
  slog('listForRent', src, houseId, ('rent=%s dep=%s'):format(rentPerWeek, deposit))

  local h = Houses[houseId]
  if not h then return end

  local ident = identOf(src)
  if not (isOwner(houseId, ident) or AZH.isAdmin(src)) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner can list this property.')
    return
  end

  local row = Rentals[houseId] or {
    house_id = houseId,
    is_listed = true,
    rent_per_week = tonumber(rentPerWeek) or ((Config.Defaults and Config.Defaults.RentPerWeek) or 0),
    deposit = tonumber(deposit) or ((Config.Defaults and Config.Defaults.Deposit) or 0),
    tenant_identifier = nil,
    agent_identifier = nil,
    status = 'available'
  }

  row.is_listed = true
  row.rent_per_week = tonumber(rentPerWeek) or row.rent_per_week
  row.deposit = tonumber(deposit) or row.deposit
  row.status = 'available'
  row.tenant_identifier = nil

  Rentals[houseId] = row
  if storageHas('upsertRental') then Storage.upsertRental(row) end

  TriggerClientEvent('az_housing:client:updateRental', -1, row)
  pushHouseRefresh(houseId)
  ensureCanonicalKeys()

  AZH.notify(src, 'success', 'Housing', 'Listed for rent.')
end)

RegisterNetEvent('az_housing:server:unlistRent', function(houseId)
  local src = source
  houseId = tonumber(houseId)

  local h = Houses[houseId]
  if not h then return end

  local ident = identOf(src)
  if not (isOwner(houseId, ident) or AZH.isAdmin(src)) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner can update this property.')
    return
  end

  local row = Rentals[houseId] or { house_id = houseId, rent_per_week = ((Config.Defaults and Config.Defaults.RentPerWeek) or 0), deposit = ((Config.Defaults and Config.Defaults.Deposit) or 0) }
  row.is_listed = false
  row.status = row.status or 'available'
  Rentals[houseId] = row
  if storageHas('upsertRental') then Storage.upsertRental(row) end

  TriggerClientEvent('az_housing:client:updateRental', -1, row)
  pushHouseRefresh(houseId)
  ensureCanonicalKeys()

  AZH.notify(src, 'inform', 'Housing', 'Unlisted from rent.')
end)

local function findSrcByIdentifier(identifier)
  local want = identNorm(identifier)
  if not want then return nil end
  for _, pid in ipairs(GetPlayers()) do
    local src = tonumber(pid)
    if src then
      local have = identOf(src)
      if have and have == want then
        return src
      end
    end
  end
  return nil
end

RegisterNetEvent('az_housing:server:rentToPlayer', function(houseId, targetSrc, rentPerWeek, deposit)
  local src = source
  houseId = parseHouseId(houseId)
  targetSrc = tonumber(targetSrc)
  rentPerWeek = tonumber(rentPerWeek) or 0
  deposit = tonumber(deposit) or 0

  slog('rentToPlayer', src, houseId, ('target=%s rent=%s dep=%s'):format(targetSrc, rentPerWeek, deposit))

  if not houseId or not Houses[houseId] then return end
  local h = Houses[houseId]

  local actorIdent = identOf(src)
  if not (isOwner(houseId, actorIdent) or AZH.isAdmin(src)) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner can create a lease.')
    return
  end

  if not targetSrc or targetSrc <= 0 or not GetPlayerName(targetSrc) then
    AZH.notify(src, 'error', 'Housing', 'Target player must be online.')
    return
  end
  if targetSrc == src then
    AZH.notify(src, 'error', 'Housing', 'You cannot rent to yourself.')
    return
  end

  local r = Rentals[houseId]
  local tIdentExisting = r and identNorm(r.tenant_identifier) or nil
  if tIdentExisting and not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'This property already has an active tenant. End the lease first.')
    return
  end

  local tenantIdent = identOf(targetSrc)
  if not tenantIdent then
    AZH.notify(src, 'error', 'Housing', 'Unable to resolve tenant identifier.')
    return
  end

  local total = math.max(0, rentPerWeek) + math.max(0, deposit)

  local ownerSrc = nil
  if isOwner(houseId, actorIdent) then
    ownerSrc = src
  else
    ownerSrc = findSrcByIdentifier(h.owner_identifier)
  end
  if total > 0 and not ownerSrc then
    AZH.notify(src, 'error', 'Housing', 'Owner must be online to receive payment.')
    return
  end

  if total > 0 then
    if not AZH.moneyTake(targetSrc, total, 'Housing Rent + Deposit') then
      AZH.notify(src, 'error', 'Housing', 'Tenant has insufficient funds.')
      AZH.notify(targetSrc, 'error', 'Housing', 'Insufficient funds to pay rent + deposit.')
      return
    end
    AZH.moneyGive(ownerSrc or src, total, 'Housing Lease Income')
  end

  r = r or { house_id = houseId }
  r.house_id = houseId
  r.rent_per_week = rentPerWeek
  r.deposit = deposit
  r.is_listed = 0
  r.status = 'leased'
  r.tenant_identifier = tenantIdent
  r.tenant_name = GetPlayerName(targetSrc)
  r.start_ts = now()
  Rentals[houseId] = r
  if storageHas('upsertRental') then Storage.upsertRental(r) end

  Keys[houseId] = Keys[houseId] or {}
  Keys[houseId][tenantIdent] = 'enter'
  if storageHas('setKey') then Storage.setKey(houseId, tenantIdent, 'enter') end

  TriggerClientEvent('az_housing:client:updateRental', -1, r)
  pushHouseRefresh(houseId)
  ensureCanonicalKeys()

  AZH.notify(src, 'success', 'Housing', ('Lease created for %s. Charged $%s.'):format(GetPlayerName(targetSrc), tostring(total)))
  AZH.notify(targetSrc, 'success', 'Housing', ('You are now renting %s. Paid $%s.'):format(h.name, tostring(total)))
end)

RegisterNetEvent('az_housing:server:endLease', function(houseId)
  local src = source
  houseId = parseHouseId(houseId)
  if not houseId or not Houses[houseId] then return end
  local h = Houses[houseId]

  local actorIdent = identOf(src)
  if not (isOwner(houseId, actorIdent) or AZH.isAdmin(src)) then
    AZH.notify(src, 'error', 'Housing', 'Only the owner can end a lease.')
    return
  end

  local r = Rentals[houseId]
  local tenantIdent = r and identNorm(r.tenant_identifier) or nil
  if not tenantIdent then
    AZH.notify(src, 'error', 'Housing', 'No active tenant to remove.')
    return
  end

  if storageHas('revokeKey') then pcall(function() Storage.revokeKey(houseId, tenantIdent) end) end
  if Keys[houseId] then Keys[houseId][tenantIdent] = nil end

  r.tenant_identifier = nil
  r.tenant_name = nil
  r.end_ts = now()
  r.status = 'open'
  r.is_listed = 0
  Rentals[houseId] = r
  if storageHas('upsertRental') then Storage.upsertRental(r) end

  TriggerClientEvent('az_housing:client:updateRental', -1, r)
  pushHouseRefresh(houseId)
  ensureCanonicalKeys()

  AZH.notify(src, 'success', 'Housing', 'Lease ended.')

  local tenantSrc = findSrcByIdentifier(tenantIdent)
  if tenantSrc then
    AZH.notify(tenantSrc, 'inform', 'Housing', ('Your lease at %s has ended.'):format(h.name))
  end
end)

RegisterNetEvent('az_housing:server:applyRent', function(houseId, message)
  local src = source
  houseId = tonumber(houseId)
  if not houseId or not Houses[houseId] then return end

  local row = Rentals[houseId]
  if not row or not toBool(row.is_listed) then
    AZH.notify(src, 'error', 'Housing', 'This property is not listed for rent.')
    return
  end

  local ident = identOf(src)
  if not ident then
    AZH.notify(src, 'error', 'Housing', 'No active character found for this application.')
    return
  end

  if storageHas('submitApplication') then
    Storage.submitApplication(houseId, ident, message or '')
  end

  AZH.notify(src, 'success', 'Housing', 'Application submitted.')
  TriggerClientEvent('az_housing:client:appsChanged', -1)
end)

RegisterNetEvent('az_housing:server:agentGetApps', function()
  local src = source
  local isAdmin = (AZH.isAdmin(src) == true)
  local roleAgent = (AZH.isAgent and AZH.isAgent(src) == true) or false

  local agentHouse = {}
  if not (isAdmin or roleAgent) then
    local ident = identOf(src)
    for hid, h in pairs(Houses) do
      if h and ident and identNorm(h.owner_identifier) == ident then
        local r = Rentals[hid]
        if r and toBool(r.is_listed) then
          agentHouse[hid] = true
        end
      end
    end
    if next(agentHouse) == nil then
      AZH.notify(src, 'error', 'Housing', 'Not authorized.')
      return
    end
  end

  local all = storageHas('loadAll') and (Storage.loadAll() or {}) or {}
  local apps = all.apps or {}

  if not (isAdmin or roleAgent) then
    local filtered = {}
    for _, a in ipairs(apps) do
      local hid = tonumber(a.house_id)
      if hid and agentHouse[hid] then
        a.house_name = (Houses[hid] and Houses[hid].name) or a.house_name
        filtered[#filtered+1] = a
      end
    end
    apps = filtered
  else
    for _, a in ipairs(apps) do
      local hid = tonumber(a.house_id)
      if hid and Houses[hid] then a.house_name = Houses[hid].name end
    end
  end

  TriggerClientEvent('az_housing:client:agentApps', src, apps)
end)

RegisterNetEvent('az_housing:server:agentDecide', function(appId, decision)
  local src = source
  local isAdmin = (AZH.isAdmin(src) == true)
  local roleAgent = (AZH.isAgent and AZH.isAgent(src) == true) or false
  appId = tonumber(appId)
  decision = tostring(decision or 'deny')

  local all = storageHas('loadAll') and (Storage.loadAll() or {}) or {}
  local apps = all.apps or {}

  local picked = nil
  for _, a in ipairs(apps) do
    if tonumber(a.id) == appId then picked = a break end
  end
  if not picked then
    AZH.notify(src, 'error', 'Housing', 'Application not found.')
    return
  end

  if not (isAdmin or roleAgent) then
    local houseId = tonumber(picked.house_id)
    local h = houseId and Houses[houseId] or nil
    local ident = identOf(src)
    local r = houseId and Rentals[houseId] or nil
    if not (houseId and h and ident and identNorm(h.owner_identifier) == ident and r and toBool(r.is_listed)) then
      AZH.notify(src, 'error', 'Housing', 'Not authorized for this property.')
      return
    end
  end

  if decision ~= 'approve' then
    if storageHas('setApplicationStatus') then Storage.setApplicationStatus(appId, 'denied') end
    AZH.notify(src, 'inform', 'Housing', 'Application denied.')
    return
  end

  local houseId = tonumber(picked.house_id)
  local h = houseId and Houses[houseId] or nil
  if not houseId or not h then
    AZH.notify(src, 'error', 'Housing', 'Invalid house id.')
    return
  end

  local row = Rentals[houseId] or {
    house_id = houseId,
    is_listed = true,
    rent_per_week = ((Config.Defaults and Config.Defaults.RentPerWeek) or 0),
    deposit = ((Config.Defaults and Config.Defaults.Deposit) or 0)
  }

  local tenantIdent = identNorm(picked.applicant_identifier)
  local tenantSrc = tenantIdent and findSrcByIdentifier(tenantIdent) or nil
  if not tenantSrc then
    AZH.notify(src, 'error', 'Housing', 'Applicant must be online to approve (instant charge).')
    return
  end

  local total = math.max(0, tonumber(row.rent_per_week) or 0) + math.max(0, tonumber(row.deposit) or 0)
  if total > 0 then
    if not AZH.moneyTake(tenantSrc, total, 'Housing Rent + Deposit') then
      AZH.notify(src, 'error', 'Housing', 'Applicant has insufficient funds.')
      AZH.notify(tenantSrc, 'error', 'Housing', 'Insufficient funds to pay rent + deposit.')
      return
    end

    local ownerSrc = h.owner_identifier and findSrcByIdentifier(h.owner_identifier) or nil
    if ownerSrc then
      AZH.moneyGive(ownerSrc, total, 'Housing Lease Income')
    end
  end

  row.tenant_identifier = tenantIdent
  row.tenant_name = GetPlayerName(tenantSrc)
  row.start_ts = now()
  row.agent_identifier = identOf(src)
  row.status = 'rented'
  row.is_listed = false
  Rentals[houseId] = row
  if storageHas('upsertRental') then Storage.upsertRental(row) end
  if storageHas('setApplicationStatus') then Storage.setApplicationStatus(appId, 'approved') end

  Keys[houseId] = Keys[houseId] or {}
  Keys[houseId][tenantIdent] = 'enter'
  if storageHas('setKey') then Storage.setKey(houseId, tenantIdent, 'enter') end

  TriggerClientEvent('az_housing:client:updateRental', -1, row)
  pushHouseRefresh(houseId)
  ensureCanonicalKeys()

  AZH.notify(src, 'success', 'Housing', ('Application approved. Tenant charged $%s.'):format(tostring(total)))
  AZH.notify(tenantSrc, 'success', 'Housing', ('Approved for %s. Paid $%s.'):format(h.name, tostring(total)))
end)

local function getHouseFeatureAccess(src, houseId)
  local ident = identOf(src)
  return canManage(houseId, ident, src)
end

RegisterNetEvent('az_housing:server:getUpgrades', function(houseId)
  local src = source
  houseId = parseHouseId(houseId)
  if not houseId or not Houses[houseId] then return end

  if not canAccessFeature(houseId, identOf(src), src) then
    TriggerClientEvent('az_housing:client:upgrades', src, houseId, { ok=false, reason='no_access', upgrades = {} })
    return
  end

  local u = Upgrades[houseId] or {}
  if storageHas('loadUpgrades') then
    local ok, val = pcall(function() return Storage.loadUpgrades(houseId) end)
    if ok and type(val) == 'table' then u = val end
  end

  Upgrades[houseId] = u
  TriggerClientEvent('az_housing:client:upgrades', src, houseId, { ok=true, upgrades=u })
end)

RegisterNetEvent('az_housing:server:setUpgrade', function(houseId, key, value)
  local src = source
  houseId = parseHouseId(houseId)
  key = tostring(key or '')
  if key == '' or not houseId or not Houses[houseId] then return end

  if not canManageUpgradesFeature(houseId, identOf(src), src) then
    AZH.notify(src, 'error', 'Housing', 'No access to upgrades.')
    return
  end

  Upgrades[houseId] = Upgrades[houseId] or {}
  Upgrades[houseId][key] = value

  if storageHas('saveUpgrade') then pcall(function() Storage.saveUpgrade(houseId, key, value) end) end
  TriggerClientEvent('az_housing:client:upgradesChanged', -1, houseId, Upgrades[houseId])
end)

RegisterNetEvent('az_housing:server:getFurniture', function(houseId)
  local src = source
  houseId = parseHouseId(houseId)
  if not houseId or not Houses[houseId] then return end

  if not canAccessFeature(houseId, identOf(src), src) then
    TriggerClientEvent('az_housing:client:furniture', src, houseId, { ok=false, reason='no_access', items = {} })
    return
  end

  local items = Furniture[houseId] or {}
  if storageHas('loadFurniture') then
    local ok, val = pcall(function() return Storage.loadFurniture(houseId) end)
    if ok and type(val) == 'table' then items = val end
  end

  Furniture[houseId] = items
  TriggerClientEvent('az_housing:client:furniture', src, houseId, { ok=true, items=items })
end)

RegisterNetEvent('az_housing:server:saveFurniture', function(houseId, items)
  local src = source
  houseId = parseHouseId(houseId)
  if not houseId or not Houses[houseId] then return end

  if not canAccessFeature(houseId, identOf(src), src) then
    AZH.notify(src, 'error', 'Housing', 'No access to furniture.')
    return
  end

  if type(items) ~= 'table' then items = {} end
  Furniture[houseId] = items

  if storageHas('saveFurniture') then pcall(function() Storage.saveFurniture(houseId, items) end) end
  TriggerClientEvent('az_housing:client:furnitureChanged', -1, houseId, items)
end)

RegisterNetEvent('az_housing:server:getMailbox', function(houseId)
  local src = source
  houseId = parseHouseId(houseId)
  if not houseId or not Houses[houseId] then return end

  if not canAccessFeature(houseId, identOf(src), src) then
    TriggerClientEvent('az_housing:client:mailbox', src, houseId, { ok=false, reason='no_access', mail = {} })
    return
  end

  local mail = Mailbox[houseId] or {}
  if storageHas('loadMailbox') then
    local ok, val = pcall(function() return Storage.loadMailbox(houseId) end)
    if ok and type(val) == 'table' then mail = val end
  end

  Mailbox[houseId] = mail
  TriggerClientEvent('az_housing:client:mailbox', src, houseId, { ok=true, mail=mail })
end)

RegisterNetEvent('az_housing:server:mailboxAdd', function(houseId, msg)
  local src = source
  houseId = parseHouseId(houseId)
  if not houseId or not Houses[houseId] then return end

  if not canAccessFeature(houseId, identOf(src), src) then
    AZH.notify(src, 'error', 'Housing', 'No access to mailbox.')
    return
  end

  msg = tostring(msg or '')
  if msg == '' then return end

  Mailbox[houseId] = Mailbox[houseId] or {}
  local item = {
    id = tostring(now()) .. ':' .. tostring(math.random(1000,9999)),
    from = GetPlayerName(src),
    msg = msg,
    ts = now(),
    read = false
  }
  table.insert(Mailbox[houseId], 1, item)

  if storageHas('addMailbox') then pcall(function() Storage.addMailbox(houseId, item) end) end
  TriggerClientEvent('az_housing:client:mailboxChanged', -1, houseId, Mailbox[houseId])
end)

RegisterNetEvent('az_housing:server:adminCreateHouse', function(payload)
  local src = source
  if not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'Not authorized.')
    return
  end

  payload = payload or {}
  local house = {
    name = tostring(payload.name or ('House ' .. tostring(math.random(1000,9999)))),
    label = tostring(payload.label or ''),
    price = tonumber(payload.price) or ((Config.Defaults and Config.Defaults.SalePrice) or 0),
    interior = tostring(payload.interior or 'apt_basic'),
    locked = true,
    owner_identifier = nil,
  }

  local id = storageHas('saveHouse') and Storage.saveHouse(house) or math.random(10000,99999)
  house.id = id
  Houses[id] = house

  TriggerClientEvent('az_housing:client:updateHouse', -1, house)
  broadcastBootstrapAll()
  AZH.notify(src, 'success', 'Housing', ('Created house #%s'):format(id))
end)

RegisterNetEvent('az_housing:server:adminDeleteHouse', function(houseId)
  local src = source
  if not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'Not authorized.')
    return
  end
  houseId = tonumber(houseId)
  if not houseId or not Houses[houseId] then return end

  if storageHas('deleteHouse') then Storage.deleteHouse(houseId) end
  Houses[houseId] = nil
  Keys[houseId] = nil
  Rentals[houseId] = nil
  Mailbox[houseId] = nil
  Furniture[houseId] = nil
  Upgrades[houseId] = nil

  for id, d in pairs(Doors) do
    if d.house_id == houseId then Doors[id] = nil end
  end
  for id, g in pairs(Garages) do
    if g.house_id == houseId then Garages[id] = nil end
  end

  TriggerClientEvent('az_housing:client:removeHouse', -1, houseId)
  broadcastBootstrapAll()
  AZH.notify(src, 'success', 'Housing', ('Deleted house #%s'):format(houseId))
end)

RegisterNetEvent('az_housing:server:adminAddDoor', function(payload)
  local src = source
  if not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'Not authorized.')
    return
  end
  payload = payload or {}
  local row = {
    house_id = parseHouseId(payload.house_id),
    x = tonumber(payload.x), y = tonumber(payload.y), z = tonumber(payload.z),
    heading = tonumber(payload.heading) or 0.0,
    radius = tonumber(payload.radius) or 2.0,
    label = tostring(payload.label or 'Door')
  }
  if not row.house_id or not Houses[row.house_id] then
    AZH.notify(src, 'error', 'Housing', 'Invalid house id.')
    return
  end

  local id = storageHas('saveDoor') and Storage.saveDoor(row) or math.random(10000,99999)
  row.id = id
  Doors[id] = row

  TriggerClientEvent('az_housing:client:updateDoor', -1, row)
  broadcastBootstrapAll()
  AZH.notify(src, 'success', 'Housing', 'Door placed.')
end)

RegisterNetEvent('az_housing:server:adminAddGarage', function(payload)
  local src = source
  if not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'Not authorized.')
    return
  end
  payload = payload or {}
  local row = {
    house_id = parseHouseId(payload.house_id),
    x = tonumber(payload.x), y = tonumber(payload.y), z = tonumber(payload.z),
    heading = tonumber(payload.heading) or 0.0,
    spawn_x = tonumber(payload.spawn_x), spawn_y = tonumber(payload.spawn_y), spawn_z = tonumber(payload.spawn_z), spawn_h = tonumber(payload.spawn_h) or 0.0,
    radius = tonumber(payload.radius) or (Config.Garage and Config.Garage.DefaultRadius or 2.2),
    label = tostring(payload.label or 'Garage')
  }
  if not row.house_id or not Houses[row.house_id] then
    AZH.notify(src, 'error', 'Housing', 'Invalid house id.')
    return
  end

  local id = storageHas('saveGarage') and Storage.saveGarage(row) or math.random(10000,99999)
  row.id = id
  Garages[id] = row

  TriggerClientEvent('az_housing:client:updateGarage', -1, row)
  broadcastBootstrapAll()
  AZH.notify(src, 'success', 'Housing', 'Garage placed.')
end)

RegisterNetEvent('az_housing:server:adminRemoveDoor', function(id)
  local src = source
  if not AZH.isAdmin(src) then return end
  id = tonumber(id)
  if not id or not Doors[id] then return end
  if storageHas('deleteDoor') then Storage.deleteDoor(id) end
  Doors[id] = nil
  TriggerClientEvent('az_housing:client:removeDoor', -1, id)
  broadcastBootstrapAll()
end)

RegisterNetEvent('az_housing:server:adminRemoveGarage', function(id)
  local src = source
  if not AZH.isAdmin(src) then return end
  id = tonumber(id)
  if not id or not Garages[id] then return end
  if storageHas('deleteGarage') then Storage.deleteGarage(id) end
  Garages[id] = nil
  TriggerClientEvent('az_housing:client:removeGarage', -1, id)
  broadcastBootstrapAll()
end)

RegisterCommand('house_sell', function(src, args)
  if src == 0 then
    print('house_sell is a player-only command')
    return
  end
  local houseId = tonumber(args[1] or '')
  local target = tonumber(args[2] or '')
  local price = tonumber(args[3] or '') or 0
  if not houseId or not target then
    AZH.notify(src, 'inform', 'Housing', 'Usage: /house_sell <houseId> <playerId> [price]')
    return
  end
  TriggerEvent('az_housing:server:sellToPlayer', houseId, target, price)
end, false)

RegisterCommand('azhousing_sell', function(src, args)
  if src == 0 then return end
  local houseId = tonumber(args[1])
  local targetSrc = tonumber(args[2])
  local price = tonumber(args[3]) or 0
  if not houseId or not targetSrc then
    AZH.notify(src, 'inform', 'Housing', 'Usage: /azhousing_sell <houseId> <playerId> <price>')
    return
  end
  TriggerEvent('az_housing:server:sellToPlayer', houseId, targetSrc, price)
end, false)

RegisterCommand('azhousing_reload', function(src)
  if src ~= 0 and not AZH.isAdmin(src) then return end
  loadFromStorage()
  broadcastBootstrapAll()
  print('az_housing reloaded')
end, true)

RegisterNetEvent('az_housing:server:adminReload', function()
  local src = source
  if src ~= 0 and not AZH.isAdmin(src) then
    AZH.notify(src, 'error', 'Housing', 'No permission.')
    return
  end

  loadFromStorage()
  broadcastBootstrapAll()

  if src ~= 0 then
    AZH.notify(src, 'success', 'Housing', 'Reloaded.')
  end
end)

local RESOURCE = GetCurrentResourceName()

local function isAdmin(src)
  if AZH and type(AZH.isAdmin) == 'function' then
    local ok, res = pcall(AZH.isAdmin, src)
    if ok then return res == true end
  end

  if type(rawget(_G, 'Az')) == 'table' and type(Az.isAdmin) == 'function' then
    local ok, res = pcall(Az.isAdmin, src)
    if ok then return res == true end
  end

  local ok, res = pcall(function()
    return exports["Az-Framework"]:isAdmin(src)
  end)
  return ok and res == true
end

local WEATHER_OPTIONS = {
  "EXTRASUNNY",
  "CLEAR",
  "NEUTRAL",
  "SMOG",
  "FOGGY",
  "OVERCAST",
  "CLOUDS",
  "CLEARING",
  "RAIN",
  "THUNDER",
  "SNOW",
  "BLIZZARD",
  "SNOWLIGHT",
  "XMAS",
  "HALLOWEEN",
}

local function isValidWeather(w)
  w = tostring(w or ""):upper()
  for i = 1, #WEATHER_OPTIONS do
    if WEATHER_OPTIONS[i] == w then return true end
  end
  return false
end

local Current = {
  weather = "CLEAR",
  blackout = false,
  wind = 0.0,
}

local function broadcast()
  TriggerClientEvent(RESOURCE .. ":applyWeather", -1, Current)
end

local function syncTo(src)
  TriggerClientEvent(RESOURCE .. ":applyWeather", src, Current)
end

AddEventHandler("playerJoining", function()
  local src = source
  if src and src > 0 then
    SetTimeout(1000, function()
      syncTo(src)
    end)
  end
end)

RegisterNetEvent(RESOURCE .. ":setWeather", function(payload)
  local src = source
  if not isAdmin(src) then return end
  if type(payload) ~= "table" then return end

  local w = tostring(payload.weather or ""):upper()
  if not isValidWeather(w) then return end

  local blackout = (payload.blackout == true)
  local wind = tonumber(payload.wind) or 0.0
  if wind < 0.0 then wind = 0.0 end
  if wind > 100.0 then wind = 100.0 end

  Current.weather = w
  Current.blackout = blackout
  Current.wind = wind

  broadcast()
end)

RegisterCommand("weather", function(src)
  if src == 0 then return end
  if not isAdmin(src) then return end

  TriggerClientEvent(RESOURCE .. ":openWeatherPicker", src, {
    weather = Current.weather,
    blackout = Current.blackout,
    wind = Current.wind,
    options = WEATHER_OPTIONS,
  })
end, false)
