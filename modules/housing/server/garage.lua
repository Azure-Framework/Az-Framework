AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.Garage = AZH.Garage or {}

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
  local getter = (AZH and type(AZH.getHousingIdentifier) == 'function' and AZH.getHousingIdentifier) or AZH.getIdentifier
  if not getter then
    print('^1[az_housing:garage]^7 identOf:missing', 'AZH.getHousingIdentifier/AZH.getIdentifier missing')
    return nil
  end
  local ok, res = pcall(getter, src)
  if not ok then
    print('^1[az_housing:garage]^7 identOf:error', 'src=', src, 'err=', tostring(res))
    return nil
  end
  local ident = normIdent(res)
  print('^3[az_housing:garage]^7 identOf', 'src=', src, 'raw=', tostring(res), 'norm=', tostring(ident))
  return ident
end

local function aliasSetOf(src, primaryIdent)
  local set = {}
  local function add(v)
    v = normIdent(v)
    if v then set[v] = true end
  end

  add(primaryIdent)

  if AZH and type(AZH.getIdentifierAliases) == 'function' then
    local ok, aliases = pcall(AZH.getIdentifierAliases, src)
    if ok and type(aliases) == 'table' then
      for v, _ in pairs(aliases) do
        add(v)
      end
    end
  end

  return set
end

local function dbExec(sql, params)
  if not AZH.Storage or type(AZH.Storage.exec) ~= 'function' then
    print('^1[az_housing:garage]^7 dbExec:missing', 'AZH.Storage.exec missing')
    return nil
  end
  local ok, rows = pcall(AZH.Storage.exec, sql, params)
  print('^3[az_housing:garage]^7 dbExec', 'ok=', ok, 'sql=', sql, 'params=', json.encode(params or {}), 'rowsType=', tostring(type(rows)))
  if not ok then
    print('^1[az_housing:garage]^7 dbExec:error', tostring(rows))
    return nil
  end
  return rows
end

function canUseGarage(src, houseId)
  print('^3[az_housing:garage]^7 canUseGarage:start', 'src=', src, 'houseId=', houseId)

  src = tonumber(src)
  houseId = tonumber(houseId)
  if not src or not houseId then
    print('^1[az_housing:garage]^7 canUseGarage:fail', 'invalid args', 'src=', tostring(src), 'houseId=', tostring(houseId))
    return false
  end

  local ident = identOf(src)
  if not ident then
    print('^1[az_housing:garage]^7 canUseGarage:deny', 'reason=no identifier')
    return false
  end
  local aliases = aliasSetOf(src, ident)

  if AZH.isAdmin then
    local ok, isAdm = pcall(AZH.isAdmin, src)
    print('^3[az_housing:garage]^7 canUseGarage:adminCheck', 'ok=', ok, 'isAdmin=', tostring(isAdm))
    if ok and isAdm == true then
      print('^2[az_housing:garage]^7 canUseGarage:allow', 'reason=admin')
      return true
    end
  else
    print('^3[az_housing:garage]^7 canUseGarage:adminCheck', 'AZH.isAdmin missing')
  end

  do
    local rows = dbExec('SELECT owner_identifier FROM az_houses WHERE id=? LIMIT 1', { houseId })
    local ownerRaw = rows and rows[1] and rows[1].owner_identifier or nil
    local owner = normIdent(ownerRaw)

    print('^3[az_housing:garage]^7 canUseGarage:ownerDB',
      'ownerRaw=', tostring(ownerRaw),
      'ownerNorm=', tostring(owner),
      'ident=', tostring(ident),
      'match=', tostring(owner ~= nil and aliases[owner] == true)
    )

    if owner and aliases[owner] == true then
      print('^2[az_housing:garage]^7 canUseGarage:allow', 'reason=owner(db)')
      return true
    end
  end

  do
    local rows = dbExec('SELECT tenant_identifier, status FROM az_house_rentals WHERE house_id=? LIMIT 1', { houseId })
    local tenantRaw = rows and rows[1] and rows[1].tenant_identifier or nil
    local status = rows and rows[1] and rows[1].status or nil
    local tenant = normIdent(tenantRaw)

    print('^3[az_housing:garage]^7 canUseGarage:tenantDB',
      'tenantRaw=', tostring(tenantRaw),
      'tenantNorm=', tostring(tenant),
      'status=', tostring(status),
      'ident=', tostring(ident),
      'match=', tostring(tenant ~= nil and aliases[tenant] == true)
    )

    if tenant and aliases[tenant] == true then
      print('^2[az_housing:garage]^7 canUseGarage:allow', 'reason=tenant(db)')
      return true
    end
  end

  do
    local Keys = rawget(_G, 'Keys') or (AZH.C and AZH.C.keys) or (AZH.Keys)
    print('^3[az_housing:garage]^7 canUseGarage:keysCache',
      'KeysType=', tostring(type(Keys)),
      'hasHouse=', tostring(Keys and Keys[houseId] ~= nil)
    )

    if Keys and Keys[houseId] then
      for alias, _ in pairs(aliases) do
        local perm = Keys[houseId][alias]
        print('^3[az_housing:garage]^7 canUseGarage:keyCheck', 'alias=', tostring(alias), 'permType=', tostring(type(perm)), 'perm=', tostring(perm))

        if perm == true then
          print('^2[az_housing:garage]^7 canUseGarage:allow', 'reason=key(true)', 'alias=', tostring(alias))
          return true
        end

        if type(perm) == 'table' then
          print('^3[az_housing:garage]^7 canUseGarage:keyTable',
            'alias=', tostring(alias),
            'garage=', tostring(perm.garage),
            'all=', tostring(perm.all),
            'access=', tostring(perm.access)
          )
          if perm.garage == true or perm.all == true or perm.access == true then
            print('^2[az_housing:garage]^7 canUseGarage:allow', 'reason=key(table)', 'alias=', tostring(alias))
            return true
          end
        elseif perm ~= nil then
          print('^2[az_housing:garage]^7 canUseGarage:allow', 'reason=key(value)', 'alias=', tostring(alias))
          return true
        end
      end
    end
  end

  print('^1[az_housing:garage]^7 canUseGarage:deny', 'reason=no access (not owner, not tenant, no keys)')
  return false
end

if lib and lib.callback and lib.callback.register then
  lib.callback.register('az_housing:cb:listVehicles', function(src, houseId)
    print('^3[az_housing:garage]^7 cb:listVehicles', 'src=', src, 'houseId=', houseId)
    if not canUseGarage(src, houseId) then
      print('^1[az_housing:garage]^7 cb:listVehicles:deny', 'src=', src, 'houseId=', houseId)
      return {}
    end
    local list = (AZH.Storage and AZH.Storage.listVehicles) and (AZH.Storage.listVehicles(tonumber(houseId)) or {}) or {}
    print('^3[az_housing:garage]^7 cb:listVehicles:ok', 'count=', tostring(#list))
    return list
  end)

  lib.callback.register('az_housing:cb:getVehicleProps', function(src, houseId, plate)
    print('^3[az_housing:garage]^7 cb:getVehicleProps', 'src=', src, 'houseId=', houseId, 'plate=', tostring(plate))
    houseId = tonumber(houseId)
    plate = tostring(plate or '')
    if not houseId or plate == '' then
      print('^1[az_housing:garage]^7 cb:getVehicleProps:fail', 'bad args')
      return nil
    end
    if not canUseGarage(src, houseId) then
      print('^1[az_housing:garage]^7 cb:getVehicleProps:deny', 'src=', src, 'houseId=', houseId)
      return nil
    end

    local rows = dbExec('SELECT props_json FROM az_house_vehicles WHERE house_id=? AND plate=? LIMIT 1', { houseId, plate })
    if not rows or not rows[1] then
      print('^1[az_housing:garage]^7 cb:getVehicleProps:notfound', 'houseId=', houseId, 'plate=', plate)
      return nil
    end

    local ok, props = pcall(json.decode, rows[1].props_json or '{}')
    print('^3[az_housing:garage]^7 cb:getVehicleProps:decode', 'ok=', ok, 'hasProps=', tostring(props ~= nil))
    if not ok or not props then return nil end

    return { plate = plate, props = props }
  end)
else
  print('^1[az_housing:garage]^7 ox_lib callbacks not available (lib.callback.register missing)')
end

RegisterNetEvent('az_housing:server:garageList', function(houseId)
  local src = source
  print('^3[az_housing:garage]^7 evt:garageList', 'src=', src, 'houseId=', houseId)

  houseId = tonumber(houseId)
  if not houseId then
    print('^1[az_housing:garage]^7 evt:garageList:fail', 'invalid houseId')
    return
  end

  if not canUseGarage(src, houseId) then
    print('^1[az_housing:garage]^7 evt:garageList:deny', 'src=', src, 'houseId=', houseId)
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'You do not have access to this garage.') end
    return
  end

  local list = (AZH.Storage and AZH.Storage.listVehicles) and (AZH.Storage.listVehicles(houseId) or {}) or {}
  print('^3[az_housing:garage]^7 evt:garageList:ok', 'count=', tostring(#list))
  TriggerClientEvent('az_housing:client:garageList', src, houseId, list)
end)

RegisterNetEvent('az_housing:server:garageStore', function(houseId, plate, props)
  local src = source
  print('^3[az_housing:garage]^7 evt:garageStore', 'src=', src, 'houseId=', houseId, 'plate=', tostring(plate))

  houseId = tonumber(houseId)
  if not houseId then
    print('^1[az_housing:garage]^7 evt:garageStore:fail', 'invalid houseId')
    return
  end

  if not canUseGarage(src, houseId) then
    print('^1[az_housing:garage]^7 evt:garageStore:deny', 'src=', src, 'houseId=', houseId)
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'You do not have access to this garage.') end
    return
  end

  local ident = identOf(src)
  plate = tostring(plate or '')
  if plate == '' then
    print('^1[az_housing:garage]^7 evt:garageStore:fail', 'missing plate')
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'Missing plate.') end
    return
  end

  if not (AZH.Storage and type(AZH.Storage.saveVehicle) == 'function') then
    print('^1[az_housing:garage]^7 evt:garageStore:fail', 'AZH.Storage.saveVehicle missing')
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'Storage system not ready.') end
    return
  end

  print('^3[az_housing:garage]^7 evt:garageStore:save', 'ident=', tostring(ident), 'plate=', plate)
  AZH.Storage.saveVehicle(houseId, ident, plate, props or {})
  if AZH.notify then AZH.notify(src, 'success', 'Garage', ('Stored vehicle %s'):format(plate)) end
end)

RegisterNetEvent('az_housing:server:garageTakeOut', function(houseId, plate)
  local src = source
  print('^3[az_housing:garage]^7 evt:garageTakeOut', 'src=', src, 'houseId=', houseId, 'plate=', tostring(plate))

  houseId = tonumber(houseId)
  plate = tostring(plate or '')
  if not houseId or plate == '' then
    print('^1[az_housing:garage]^7 evt:garageTakeOut:fail', 'bad args')
    return
  end

  if not canUseGarage(src, houseId) then
    print('^1[az_housing:garage]^7 evt:garageTakeOut:deny', 'src=', src, 'houseId=', houseId)
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'You do not have access to this garage.') end
    return
  end

  if not (AZH.Storage and type(AZH.Storage.getVehicle) == 'function') then
    print('^1[az_housing:garage]^7 evt:garageTakeOut:fail', 'AZH.Storage.getVehicle missing')
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'Storage system not ready.') end
    return
  end

  local row = AZH.Storage.getVehicle(houseId, plate)
  print('^3[az_housing:garage]^7 evt:garageTakeOut:getVehicle', 'found=', tostring(row ~= nil))
  if not row then
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'Vehicle not found.') end
    return
  end

  if not toBool(row.stored) then
    print('^1[az_housing:garage]^7 evt:garageTakeOut:notStored', 'stored=', tostring(row.stored))
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'That vehicle is not stored here.') end
    return
  end

  local ok, props = pcall(json.decode, row.props_json or '{}')
  print('^3[az_housing:garage]^7 evt:garageTakeOut:decode', 'ok=', ok, 'hasProps=', tostring(props ~= nil))
  if not ok or not props then
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'Vehicle data is corrupted.') end
    return
  end

  if not (AZH.Storage and type(AZH.Storage.markVehicleOut) == 'function') then
    print('^1[az_housing:garage]^7 evt:garageTakeOut:fail', 'AZH.Storage.markVehicleOut missing')
    if AZH.notify then AZH.notify(src, 'error', 'Garage', 'Storage system not ready.') end
    return
  end

  print('^3[az_housing:garage]^7 evt:garageTakeOut:markOut', 'houseId=', houseId, 'plate=', plate)
  AZH.Storage.markVehicleOut(houseId, plate)

  print('^3[az_housing:garage]^7 evt:garageTakeOut:spawnClient', 'src=', src)
  TriggerClientEvent('az_housing:client:garageTakeOut', src, houseId, plate, props)
end)

print('^2[az_housing:garage]^7 loaded garage.lua (MYSQL access checks enabled)')
