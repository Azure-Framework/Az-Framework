AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.Garage = AZH.Garage or {}

local function sanitizePlate(p)
  p = tostring(p or '')
  p = p:gsub('^%s+', ''):gsub('%s+$', '')
  if #p > 16 then p = p:sub(1, 16) end
  return p
end

local function getGarageById(garageId)
  garageId = tonumber(garageId)
  if not garageId then return nil end
  for _, g in ipairs(AZH.C.garages or {}) do
    if tonumber(g.id) == garageId then return g end
  end
  return nil
end

local function findAnyGarageForHouse(houseId)
  houseId = tonumber(houseId)
  if not houseId then return nil end
  for _, g in ipairs(AZH.C.garages or {}) do
    if tonumber(g.house_id) == houseId then return g end
  end
  return nil
end

local function ensureSpawnClear(coords, radius)
  radius = tonumber(radius) or (Config.Garage and Config.Garage.SpawnClearance) or 3.0
  local vehicles = GetGamePool('CVehicle')
  for _, veh in ipairs(vehicles) do
    if DoesEntityExist(veh) then
      local p = GetEntityCoords(veh)
      if #(p - coords) <= radius then
        return false
      end
    end
  end
  return true
end

local function showList(houseId, list)
  houseId = tonumber(houseId)
  list = list or {}

  if #list == 0 then
    AZH.notify('inform', 'Garage', 'No vehicles stored here.')
    return
  end

  local opts = {}
  for _, v in ipairs(list) do
    local plate = sanitizePlate(v.plate)
    if plate ~= '' then
      opts[#opts+1] = {
        title = plate,
        description = 'Retrieve vehicle',
        icon = 'car',
        onSelect = function()
          TriggerServerEvent('az_housing:server:garageTakeOut', tonumber(houseId), plate)
        end
      }
    end
  end

  if #opts == 0 then
    AZH.notify('inform', 'Garage', 'No vehicles stored here.')
    return
  end

  lib.registerContext({
    id = 'azh_garage_list',
    title = 'Garage',
    options = opts
  })
  lib.showContext('azh_garage_list')
end

function AZH.Garage.store(houseId, garageId)
  houseId = tonumber(houseId)
  if not houseId then return end

  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh == 0 then
    AZH.notify('error', 'Garage', 'Get in a vehicle to store it.')
    return
  end
  if GetPedInVehicleSeat(veh, -1) ~= ped then
    AZH.notify('error', 'Garage', 'You must be the driver.')
    return
  end

  local props = lib.getVehicleProperties(veh)
  local plate = sanitizePlate((props and props.plate) or GetVehicleNumberPlateText(veh))

  if plate == '' then
    AZH.notify('error', 'Garage', 'Invalid plate.')
    return
  end

  TriggerServerEvent('az_housing:server:garageStore', houseId, plate, props)

  TaskLeaveVehicle(ped, veh, 0)
  Wait(800)
  if DoesEntityExist(veh) then
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
  end
end

function AZH.Garage.openList(houseId, garageId)
  houseId = tonumber(houseId)
  if not houseId then return end

  AZH.Garage._lastGarageId = tonumber(garageId)

  if not (lib and lib.callback and lib.callback.await) then
    AZH.notify('error', 'Garage', 'ox_lib is required for garage menus.')
    return
  end

  local ok, list = pcall(function()
    return lib.callback.await('az_housing:cb:listVehicles', false, houseId)
  end)
  if ok and list then
    showList(houseId, list)
    return
  end

  TriggerServerEvent('az_housing:server:garageList', houseId)
end

RegisterNetEvent('az_housing:client:garageList', function(houseId, list)
  showList(houseId, list)
end)

RegisterNetEvent('az_housing:client:garageTakeOut', function(houseId, plate, propsFromServer)
  houseId = tonumber(houseId)
  plate = sanitizePlate(plate)

  local g = getGarageById(AZH.Garage._lastGarageId) or findAnyGarageForHouse(houseId)
  if not g then
    AZH.notify('error', 'Garage', 'No garage point found for this property.')
    return
  end

  local spawn = vec3(g.spawn_x, g.spawn_y, g.spawn_z)
  if not ensureSpawnClear(spawn, Config.Garage and Config.Garage.SpawnClearance) then
    AZH.notify('error', 'Garage', 'Spawn area blocked.')
    return
  end

  local props = propsFromServer
  if not props then
    local rows = lib.callback.await('az_housing:cb:getVehicleProps', false, houseId, plate)
    props = rows and rows.props or nil
  end
  if not props then
    AZH.notify('error', 'Garage', 'Vehicle data not found.')
    return
  end

  local model = props.model or props.hash
  if not model then
    AZH.notify('error', 'Garage', 'Invalid vehicle model.')
    return
  end

  lib.requestModel(model, 5000)
  local veh = CreateVehicle(model, spawn.x, spawn.y, spawn.z, g.spawn_h or g.heading or 0.0, true, false)
  if veh == 0 then
    AZH.notify('error', 'Garage', 'Failed to spawn vehicle.')
    return
  end

  SetVehicleOnGroundProperly(veh)
  lib.setVehicleProperties(veh, props)
  SetVehicleNumberPlateText(veh, plate)
  SetEntityAsMissionEntity(veh, true, true)

  AZH.notify('success', 'Garage', ('Retrieved %s'):format(plate))
end)

RegisterNetEvent('az_housing:client:garageStore', function(data)
  if data and data.houseId then
    AZH.Garage.store(data.houseId, data.garageId)
  end
end)
