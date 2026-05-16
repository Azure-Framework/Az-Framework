AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.Furniture = AZH.Furniture or {}

local spawned = {}

local function dprint(...)
  if Config and Config.Debug then
    print(('^3[%s:furn]^7'):format(GetCurrentResourceName()), ...)
  end
end

local function requestModel(model)
  local hash = type(model)=='number' and model or joaat(model)
  if not IsModelInCdimage(hash) then return nil end
  RequestModel(hash)
  local t = GetGameTimer() + 5000
  while not HasModelLoaded(hash) and GetGameTimer() < t do
    Wait(10)
  end
  if not HasModelLoaded(hash) then return nil end
  return hash
end

local function deleteAll()
  for id, ent in pairs(spawned) do
    if DoesEntityExist(ent) then
      DeleteEntity(ent)
    end
    spawned[id] = nil
  end
end

local function spawnOne(f)
  if not f or not f.model then return end
  local hash = requestModel(f.model)
  if not hash then return end

  local x,y,z = tonumber(f.x) or 0.0, tonumber(f.y) or 0.0, tonumber(f.z) or 0.0
  local ent = CreateObjectNoOffset(hash, x, y, z, false, false, false)
  if not ent or ent == 0 then return end
  SetEntityHeading(ent, tonumber(f.heading) or 0.0)
  FreezeEntityPosition(ent, true)
  SetEntityInvincible(ent, true)
  SetEntityAsMissionEntity(ent, true, true)

  spawned[tonumber(f.id)] = ent
end

function AZH.Furniture.refresh(houseId)
  houseId = tonumber(houseId)
  if not houseId then return end
  if not (Config.Furniture and Config.Furniture.Enabled) then return end

  local res = lib.callback.await('az_housing:cb:getFurniture', false, houseId)
  if not res or not res.ok then
    dprint('refresh failed', res and res.error)
    return
  end

  deleteAll()
  for _, f in ipairs(res.furniture or {}) do
    spawnOne(f)
  end
end

local function rotationText(h)
  h = tonumber(h) or 0
  while h < 0 do h = h + 360 end
  while h >= 360 do h = h - 360 end
  return string.format('%.1f', h)
end

local function raycastFromCam(dist)
  dist = dist or 10.0
  local camPos = GetFinalRenderedCamCoord()
  local rot = GetFinalRenderedCamRot(2)
  local pitch = math.rad(rot.x)
  local yaw = math.rad(rot.z)
  local dir = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
  local dest = camPos + (dir * dist)
  local ray = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
  local _, hit, endCoords, _, entityHit = GetShapeTestResult(ray)
  return hit == 1, endCoords, entityHit
end

function AZH.Furniture.place(houseId, model)
  houseId = tonumber(houseId)
  model = tostring(model or '')
  if not houseId or model == '' then return end

  if not AZH.C.currentHouseId or tonumber(AZH.C.currentHouseId) ~= houseId then
    AZH.notify('error', 'Furniture', 'You must be inside the property to place furniture.')
    return
  end

  local hash = requestModel(model)
  if not hash then
    AZH.notify('error', 'Furniture', 'Invalid model.')
    return
  end

  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local ent = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false)
  if not ent or ent == 0 then return end

  SetEntityCollision(ent, false, false)
  SetEntityAlpha(ent, 170, false)
  FreezeEntityPosition(ent, true)
  SetEntityAsMissionEntity(ent, true, true)

  local heading = GetEntityHeading(ped)
  local zOffset = 0.0

  lib.showTextUI('Place Furniture\n[E] Confirm  [Backspace] Cancel\nScroll: Rotate  |  Arrow Up/Down: Raise/Lower', { position = 'left-center' })

  local placing = true
  while placing do
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 37, true)

    local hit, pos = raycastFromCam(12.0)
    if hit and pos then
      SetEntityCoordsNoOffset(ent, pos.x, pos.y, pos.z + zOffset, false, false, false)
      SetEntityHeading(ent, heading)
    end

    local fine = IsControlPressed(0, 21)
    local step = fine and 0.5 or 2.5
    if IsControlJustPressed(0, 14) then heading = heading - step end
    if IsControlJustPressed(0, 15) then heading = heading + step end

    local zStep = fine and 0.01 or 0.05
    if IsControlPressed(0, 172) then zOffset = zOffset + zStep end
    if IsControlPressed(0, 173) then zOffset = zOffset - zStep end

    if IsControlJustPressed(0, 38) then
      placing = false
      local c = GetEntityCoords(ent)
      local rot = GetEntityRotation(ent, 2)
      TriggerServerEvent('az_housing:server:addFurniture', houseId, model, { x = c.x, y = c.y, z = c.z }, heading, { x = rot.x, y = rot.y, z = rot.z }, {})
    end

    if IsControlJustPressed(0, 177) then
      placing = false
    end

    Wait(0)
  end

  lib.hideTextUI()

  if DoesEntityExist(ent) then
    DeleteEntity(ent)
  end
end

AddEventHandler('az_housing:client:enteredInterior', function(houseId)
  Wait(250)
  AZH.Furniture.refresh(houseId)
end)

AddEventHandler('az_housing:client:leftInterior', function()
  deleteAll()
end)

RegisterNetEvent('az_housing:client:furnitureChanged', function(houseId)
  if AZH.C.currentHouseId and tonumber(AZH.C.currentHouseId) == tonumber(houseId) then
    AZH.Furniture.refresh(houseId)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then
    deleteAll()
  end
end)
