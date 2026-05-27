local Config = (Config and Config.MorsDelivery) or {}
local RESOURCE = GetCurrentResourceName()

local function dbg(msg)
  print(('[%s] %s'):format(RESOURCE, tostring(msg)))
end

local function getFramework()
  local state = GetResourceState('Az-Framework')
  if state == 'started' or state == 'starting' then
    return exports['Az-Framework']
  end
  return nil
end

local function getActiveCharId(src)
  local fw = getFramework()
  if fw and fw.GetPlayerCharacter then
    local ok, cid = pcall(function() return fw:GetPlayerCharacter(src) end)
    if ok and cid ~= nil and tostring(cid) ~= '' then
      return tostring(cid)
    end
  end
  return nil
end

local function isOx() return (Config.MySQL or ''):lower() == 'oxmysql' end
local function isMyAsync() return (Config.MySQL or ''):lower() == 'mysql-async' end
local function isGH() return (Config.MySQL or ''):lower() == 'ghmattimysql' end

local function fetchAll(query, params)
  if isOx() then
    return exports.oxmysql:fetchSync(query, params or {})
  elseif isMyAsync() then
    local p = promise.new()
    exports['mysql-async']:fetchAll(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  elseif isGH() then
    local p = promise.new()
    exports.ghmattimysql:execute(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  else
    error('Config.MySQL must be one of: oxmysql, mysql-async, ghmattimysql')
  end
end

local function execute(query, params)
  if isOx() then
    return exports.oxmysql:executeSync(query, params or {})
  elseif isMyAsync() then
    local p = promise.new()
    exports['mysql-async']:execute(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  elseif isGH() then
    local p = promise.new()
    exports.ghmattimysql:execute(query, params or {}, function(r) p:resolve(r) end)
    return Citizen.Await(p)
  else
    error('Config.MySQL must be one of: oxmysql, mysql-async, ghmattimysql')
  end
end

local function getIdentifier(src)
  local t = (Config.IdentifierType or 'discord'):lower()

  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if t == 'discord' and id:find('discord:', 1, true) == 1 then
      return id:gsub('discord:', '')
    elseif t == 'license' and id:find('license:', 1, true) == 1 then
      return id:gsub('license:', '')
    end
  end

  if t ~= 'license' then
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
      if id:find('license:', 1, true) == 1 then
        return id:gsub('license:', '')
      end
    end
  end
  return nil
end

local _vehicleSchemaChecked = false
local _vehicleHasCharId = false

local function ensureVehicleSchema()
  if _vehicleSchemaChecked then return end
  _vehicleSchemaChecked = true

  local t = Config.DB_TABLE
  local rows = fetchAll(("SHOW COLUMNS FROM %s LIKE 'charid'"):format(t), {})
  _vehicleHasCharId = rows and rows[1] ~= nil or false

  if not _vehicleHasCharId then
    local ok, err = pcall(function()
      execute(("ALTER TABLE %s ADD COLUMN charid VARCHAR(64) NULL DEFAULT NULL AFTER %s"):format(t, Config.DB_OWNER_COLUMN), {})
      execute(("ALTER TABLE %s ADD KEY idx_%s_charid (%s, charid)"):format(t, Config.DB_OWNER_COLUMN, Config.DB_OWNER_COLUMN), {})
    end)
    if not ok then
      dbg(("Vehicle schema migration failed: %s"):format(tostring(err)))
    end

    rows = fetchAll(("SHOW COLUMNS FROM %s LIKE 'charid'"):format(t), {})
    _vehicleHasCharId = rows and rows[1] ~= nil or false
  end
end

local function getOwnerContext(src)
  ensureVehicleSchema()

  local ownerId = getIdentifier(src)
  if not ownerId then return nil end

  local charId = getActiveCharId(src)
  local ownerKey
  if _vehicleHasCharId and charId and charId ~= '' then
    ownerKey = ('%s:%s'):format(ownerId, charId)
  else
    ownerKey = tostring(ownerId)
  end

  return { ownerId = tostring(ownerId), charId = charId and tostring(charId) or nil, ownerKey = ownerKey }
end

local function adoptLegacyVehicles(ownerId, charId)
  ensureVehicleSchema()
  if not _vehicleHasCharId then return end
  ownerId = tostring(ownerId or '')
  charId = tostring(charId or '')
  if ownerId == '' or charId == '' then return end

  pcall(function()
    execute(("UPDATE %s SET charid = ? WHERE %s = ? AND (charid IS NULL OR charid = '')"):format(Config.DB_TABLE, Config.DB_OWNER_COLUMN), { charId, ownerId })
  end)
end

local cooldowns = {}
local activeDeliveries = {}

local function canUse(ownerId)
  local now = os.time()
  if cooldowns[ownerId] and cooldowns[ownerId] > now then
    return false, (cooldowns[ownerId] - now)
  end
  return true, 0
end

local outVehicles = {}

local function ownerMap(ownerId)
  outVehicles[ownerId] = outVehicles[ownerId] or {}
  return outVehicles[ownerId]
end

local function isOut(ownerId, plate)
  local m = outVehicles[ownerId]
  return (m and m[plate]) ~= nil
end

local function setOut(ownerId, plate, row, state)
  local m = ownerMap(ownerId)
  m[plate] = {
    row = row,
    state = state or 'out',
    since = os.time()
  }
end

local function clearOut(ownerId, plate)
  local m = outVehicles[ownerId]
  if not m then return end
  m[plate] = nil
end

local function toJsonString(v)
  if v == nil then return nil end
  if type(v) == 'string' then return v end
  local ok, s = pcall(function() return json.encode(v) end)
  if ok then return s end
  return nil
end

local function upperPlate(p)
  return tostring(p or ''):upper()
end

local function getVehiclesForOwner(ctx)
  ensureVehicleSchema()
  if not ctx or not ctx.ownerId then return {} end

  local t = Config.DB_TABLE
  local ownerCol = Config.DB_OWNER_COLUMN

  if _vehicleHasCharId and ctx.charId and ctx.charId ~= '' then
    adoptLegacyVehicles(ctx.ownerId, ctx.charId)
    local rows = fetchAll(([[
      SELECT id, %s AS ownerid, charid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras
      FROM %s
      WHERE %s = ? AND charid = ?
      ORDER BY id DESC
    ]]):format(ownerCol, t, ownerCol), { ctx.ownerId, ctx.charId })
    return rows or {}
  end

  local rows = fetchAll(([[
    SELECT id, %s AS ownerid, charid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras
    FROM %s
    WHERE %s = ?
    ORDER BY id DESC
  ]]):format(ownerCol, t, ownerCol), { ctx.ownerId })

  return rows or {}
end

local function getVehicleByPlate(ctx, plate)
  ensureVehicleSchema()
  if not ctx or not ctx.ownerId then return nil end

  local t = Config.DB_TABLE
  local ownerCol = Config.DB_OWNER_COLUMN

  if _vehicleHasCharId and ctx.charId and ctx.charId ~= '' then
    adoptLegacyVehicles(ctx.ownerId, ctx.charId)
    local rows = fetchAll(("SELECT * FROM %s WHERE %s = ? AND charid = ? AND plate = ? LIMIT 1"):format(t, ownerCol), { ctx.ownerId, ctx.charId, plate })
    return rows and rows[1] or nil
  end

  local rows = fetchAll(("SELECT * FROM %s WHERE %s = ? AND plate = ? LIMIT 1"):format(t, ownerCol), { ctx.ownerId, plate })
  return rows and rows[1] or nil
end

local function deleteVehicleRow(ctx, plate)
  ensureVehicleSchema()
  if not ctx or not ctx.ownerId then return end

  local t = Config.DB_TABLE
  local ownerCol = Config.DB_OWNER_COLUMN

  if _vehicleHasCharId and ctx.charId and ctx.charId ~= '' then
    execute(("DELETE FROM %s WHERE %s = ? AND charid = ? AND plate = ? LIMIT 1"):format(t, ownerCol), { ctx.ownerId, ctx.charId, plate })
    return
  end

  execute(("DELETE FROM %s WHERE %s = ? AND plate = ? LIMIT 1"):format(t, ownerCol), { ctx.ownerId, plate })
end

local function upsertVehicleRow(ctx, row)
  ensureVehicleSchema()
  if not ctx or not ctx.ownerId then return end

  local t = Config.DB_TABLE
  local ownerCol = Config.DB_OWNER_COLUMN

  local ownerValue   = row[ownerCol] or row.ownerid or row.discordid or ctx.ownerId
  local charId       = row.charid or ctx.charId
  local plate        = row.plate
  local model        = row.model
  local x            = tonumber(row.x) or 0.0
  local y            = tonumber(row.y) or 0.0
  local z            = tonumber(row.z) or 0.0
  local h            = tonumber(row.h) or 0.0
  local color1       = tonumber(row.color1) or 0
  local color2       = tonumber(row.color2) or 0
  local pearlescent  = tonumber(row.pearlescent) or 0
  local wheelColor   = tonumber(row.wheelColor) or 0
  local wheelType    = tonumber(row.wheelType) or 0
  local windowTint   = tonumber(row.windowTint) or 0
  local mods         = toJsonString(row.mods)
  local extras       = toJsonString(row.extras)

  if _vehicleHasCharId and charId and tostring(charId) ~= '' then
    execute(([[
      INSERT INTO %s
        (%s, charid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras)
      VALUES
        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE
        charid=VALUES(charid),
        model=VALUES(model),
        x=VALUES(x), y=VALUES(y), z=VALUES(z), h=VALUES(h),
        color1=VALUES(color1), color2=VALUES(color2),
        pearlescent=VALUES(pearlescent),
        wheelColor=VALUES(wheelColor),
        wheelType=VALUES(wheelType),
        windowTint=VALUES(windowTint),
        mods=VALUES(mods),
        extras=VALUES(extras)
    ]]):format(t, ownerCol), {
      ownerValue, tostring(charId), plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras
    })
    return
  end

  execute(([[
    INSERT INTO %s
      (%s, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras)
    VALUES
      (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      model=VALUES(model),
      x=VALUES(x), y=VALUES(y), z=VALUES(z), h=VALUES(h),
      color1=VALUES(color1), color2=VALUES(color2),
      pearlescent=VALUES(pearlescent),
      wheelColor=VALUES(wheelColor),
      wheelType=VALUES(wheelType),
      windowTint=VALUES(windowTint),
      mods=VALUES(mods),
      extras=VALUES(extras)
  ]]):format(t, ownerCol), {
    ownerValue, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras
  })
end

RegisterNetEvent('nv_morsmutual:sv_list', function()
  local src = source
  local ctx
  local okCtx, ctxOrErr = pcall(function()
    return getOwnerContext(src)
  end)
  if okCtx then ctx = ctxOrErr end
  if not ctx then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'No owner/character context found.')
    TriggerClientEvent('nv_morsmutual:cl_list', src, { ok = false, cooldown = 0, vehicles = {} })
    return
  end

  local ok, remaining = canUse(ctx.ownerKey)
  local fetchOk, vehiclesOrErr = pcall(function()
    return getVehiclesForOwner(ctx)
  end)

  if not fetchOk then
    dbg(('sv_list failed for owner=%s char=%s err=%s'):format(tostring(ctx.ownerId), tostring(ctx.charId), tostring(vehiclesOrErr)))
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'Mors could not load your parked vehicles right now.')
    TriggerClientEvent('nv_morsmutual:cl_list', src, {
      ok = ok,
      cooldown = remaining,
      vehicles = {},
      ownerId = ctx.ownerId,
      charId = ctx.charId,
    })
    return
  end

  local vehicles = vehiclesOrErr or {}
  for _, v in ipairs(vehicles) do
    v.parked = 1
  end

  TriggerClientEvent('nv_morsmutual:cl_list', src, {
    ok = ok,
    cooldown = remaining,
    vehicles = vehicles,
    ownerId = ctx.ownerId,
    charId = ctx.charId,
  })
end)

RegisterNetEvent('nv_morsmutual:sv_requestDelivery', function(plate, spawn)
  local src = source
  plate = upperPlate(plate)
  if plate == '' then return end

  local ctx = getOwnerContext(src)
  if not ctx then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'No owner/character context found.')
    return
  end

  local ok, remaining = canUse(ctx.ownerKey)
  if not ok then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, ('Insurance is busy. Try again in %ds.'):format(remaining))
    return
  end

  if activeDeliveries[ctx.ownerKey] then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'You already have a delivery in progress.')
    return
  end

  if isOut(ctx.ownerKey, plate) then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'That vehicle is already unparked / out.')
    return
  end

  local row = getVehicleByPlate(ctx, plate)
  if not row then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'That vehicle is currently unparked / out (not in garage).')
    return
  end

  local sx, sy, sz, sh = tonumber(spawn and spawn.x), tonumber(spawn and spawn.y), tonumber(spawn and spawn.z), tonumber(spawn and spawn.h)
  if not sx or not sy or not sz or not sh then
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'Invalid spawn point.')
    return
  end

  activeDeliveries[ctx.ownerKey] = plate
  cooldowns[ctx.ownerKey] = os.time() + tonumber(Config.CooldownSeconds or 60)

  local okDel, errDel = pcall(function()
    deleteVehicleRow(ctx, plate)
  end)
  if not okDel then
    dbg(("DELETE failed for %s/%s/%s: %s"):format(ctx.ownerId, tostring(ctx.charId or 'nochar'), plate, tostring(errDel)))
    activeDeliveries[ctx.ownerKey] = nil
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'DB error removing vehicle from garage.')
    return
  end

  setOut(ctx.ownerKey, plate, row, 'delivering')

  TriggerClientEvent('nv_morsmutual:cl_deliveryApproved', src, {
    plate = plate,
    model = row.model,
    props = {
      plate = row.plate,
      color1 = row.color1,
      color2 = row.color2,
      pearlescent = row.pearlescent,
      wheelColor = row.wheelColor,
      wheelType = row.wheelType,
      windowTint = row.windowTint,
      mods = row.mods,
      extras = row.extras,
    },
    spawn = { x=sx, y=sy, z=sz, h=sh }
  })
end)

RegisterNetEvent('nv_morsmutual:sv_deliveryDone', function(plate, deliveredOk)
  local src = source
  local ctx = getOwnerContext(src)
  if not ctx then return end

  if deliveredOk == nil then
    deliveredOk = true
    dbg(("sv_deliveryDone legacy call (no args) -> assuming SUCCESS for owner=%s"):format(ctx.ownerKey))
  else
    deliveredOk = (deliveredOk == true or deliveredOk == 1 or deliveredOk == 'true' or deliveredOk == '1')
  end

  plate = upperPlate(plate or activeDeliveries[ctx.ownerKey])
  activeDeliveries[ctx.ownerKey] = nil
  if plate == '' then return end

  local entry = outVehicles[ctx.ownerKey] and outVehicles[ctx.ownerKey][plate]
  if not entry or not entry.row then
    return
  end

  if deliveredOk then
    entry.state = 'out'
    dbg(("Delivery success -> %s/%s/%s remains OUT (row removed from DB)"):format(ctx.ownerId, tostring(ctx.charId or 'nochar'), plate))
  else
    dbg(("Delivery failed -> restoring %s/%s/%s back into DB"):format(ctx.ownerId, tostring(ctx.charId or 'nochar'), plate))
    local okIns, errIns = pcall(function()
      upsertVehicleRow(ctx, entry.row)
    end)
    if not okIns then
      dbg(("Restore insert failed %s/%s/%s err=%s"):format(ctx.ownerId, tostring(ctx.charId or 'nochar'), plate, tostring(errIns)))
    end
    clearOut(ctx.ownerKey, plate)
  end
end)

RegisterNetEvent('nv_morsmutual:sv_markParked', function(plate, props, coords, heading)
  local src = source
  local ctx = getOwnerContext(src)
  if not ctx then return end

  plate = upperPlate(plate)
  if plate == '' then return end

  local entry = outVehicles[ctx.ownerKey] and outVehicles[ctx.ownerKey][plate]
  local row = entry and entry.row or nil

  if not row then
    if type(props) ~= 'table' then
      TriggerClientEvent('nv_morsmutual:cl_notify', src, 'Cannot park: missing stored data (server restart). Send vehicle properties.')
      return
    end

    row = {
      [Config.DB_OWNER_COLUMN] = ctx.ownerId,
      charid = ctx.charId,
      plate = plate,
      model = tostring(props.model or props.hash or props.vehicleModel or ''),
      color1 = (type(props.color1) == 'table') and props.color1[1] or props.color1,
      color2 = (type(props.color2) == 'table') and props.color2[1] or props.color2,
      pearlescent = props.pearlescentColor or props.pearlescent,
      wheelColor = props.wheelColor,
      wheelType = props.wheels or props.wheelType,
      windowTint = props.windowTint,
      mods = toJsonString(props),
      extras = toJsonString(props.extras),
    }
  end

  if type(coords) == 'table' then
    row.x = tonumber(coords.x) or row.x
    row.y = tonumber(coords.y) or row.y
    row.z = tonumber(coords.z) or row.z
  end
  if heading ~= nil then
    row.h = tonumber(heading) or row.h
  end

  dbg(("Parking -> inserting %s/%s/%s back into DB"):format(ctx.ownerId, tostring(ctx.charId or 'nochar'), plate))
  local okIns, errIns = pcall(function()
    upsertVehicleRow(ctx, row)
  end)

  if not okIns then
    dbg("Park insert failed: "..tostring(errIns))
    TriggerClientEvent('nv_morsmutual:cl_notify', src, 'DB error: failed to park vehicle.')
    return
  end

  clearOut(ctx.ownerKey, plate)
end)

RegisterNetEvent('nv_morsmutual:sv_cancelOut', function(plate)
  local src = source
  local ctx = getOwnerContext(src)
  if not ctx then return end

  plate = upperPlate(plate)
  local entry = outVehicles[ctx.ownerKey] and outVehicles[ctx.ownerKey][plate]
  if not entry or not entry.row then return end

  pcall(function()
    upsertVehicleRow(ctx, entry.row)
  end)
  clearOut(ctx.ownerKey, plate)
end)
