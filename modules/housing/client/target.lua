AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.Target = AZH.Target or {}
AZH.C = AZH.C or {}
AZH.C.zones = AZH.C.zones or { doors = {}, garages = {}, interiorExit = nil }

local function hasTarget()
  return GetResourceState('ox_target') == 'started'
    and exports
    and exports.ox_target
    and type(exports.ox_target.addSphereZone) == 'function'
end

if type(AZH.C.resetZones) ~= 'function' then
  function AZH.C.resetZones()
    AZH.C.zones = AZH.C.zones or { doors = {}, garages = {}, interiorExit = nil }

    if hasTarget() then

      if AZH.C.zones.doors then
        for i = 1, #AZH.C.zones.doors do
          local z = AZH.C.zones.doors[i]
          if z then pcall(function() exports.ox_target:removeZone(z) end) end
        end
      end

      if AZH.C.zones.garages then
        for i = 1, #AZH.C.zones.garages do
          local z = AZH.C.zones.garages[i]
          if z then pcall(function() exports.ox_target:removeZone(z) end) end
        end
      end

      if AZH.C.zones.interiorExit then
        pcall(function() exports.ox_target:removeZone(AZH.C.zones.interiorExit) end)
      end
    end

    AZH.C.zones.doors = {}
    AZH.C.zones.garages = {}
    AZH.C.zones.interiorExit = nil
  end
end

local function addDoorZone(door)
  local houseId = door.house_id
  local zname = ('azh_door_%s'):format(door.id)

  exports.ox_target:addSphereZone({
    name = zname,
    coords = vec3(door.x, door.y, door.z),
    radius = tonumber(door.radius) or (Config and Config.Interact and Config.Interact.DoorDistance) or 2.0,
    debug = (Config and Config.Debug) == true,
    options = {
      {
        name = ('azh_enter_%s'):format(door.id),
        icon = 'fa-solid fa-door-open',
        label = 'Enter',
        onSelect = function()
          TriggerServerEvent('az_housing:server:enter', houseId)
        end
      },
      {
        name = ('azh_knock_%s'):format(door.id),
        icon = 'fa-solid fa-hand',
        label = 'Knock',
        onSelect = function()
          TriggerServerEvent('az_housing:server:knock', houseId)
        end
      },
      {
        name = ('azh_lock_%s'):format(door.id),
        icon = 'fa-solid fa-lock',
        label = 'Lock / Unlock',
        onSelect = function()
          TriggerServerEvent('az_housing:server:toggleLock', houseId)
        end
      },
      {
        name = ('azh_breach_%s'):format(door.id),
        icon = 'fa-solid fa-hammer',
        label = 'Breach (Police)',

        canInteract = function(entity, distance, coords, name)
          local ok, isP = pcall(function()
            return (AZH.isPolice and AZH.isPolice() == true) or false
          end)

          if not ok then
            print(('^1[az_housing]^7 breach canInteract ERROR: %s'):format(tostring(isP)))
            return false
          end

          if Config and Config.Debug then
            AZH.__dbgNext = AZH.__dbgNext or 0
            local now = GetGameTimer()
            if now > AZH.__dbgNext then
              AZH.__dbgNext = now + 2000
              local job = (AZH.getJobName and AZH.getJobName()) or 'nil'
              print(('[az_housing] canInteract breach => isPolice=%s job=%s dist=%s'):format(
                tostring(isP), tostring(job), tostring(distance)
              ))
            end
          end

          return isP
        end,

        onSelect = function()
          TriggerServerEvent('az_housing:server:breach', houseId)
        end
      },
      {
        name = ('azh_portal_%s'):format(door.id),
        icon = 'fa-solid fa-house',
        label = 'Housing Portal',
        onSelect = function()
          if AZH.UI and AZH.UI.open then AZH.UI.open({ houseId = houseId }) end
        end
      },
      {
        name = ('azh_mail_%s'):format(door.id),
        icon = 'fa-solid fa-envelope',
        label = 'Mailbox',
        onSelect = function()
          if AZH.UI and AZH.UI.open then AZH.UI.open({ houseId = houseId, tab = 'mailbox' }) end
        end
      }
    }
  })

  AZH.C.zones.doors[#AZH.C.zones.doors+1] = zname
end

local function addGarageZone(gar)
  local zname = ('azh_gar_%s'):format(gar.id)
  local houseId = gar.house_id

  exports.ox_target:addSphereZone({
    name = zname,
    coords = vec3(gar.x, gar.y, gar.z),
    radius = tonumber(gar.radius) or (Config and Config.Interact and Config.Interact.GarageDistance) or 3.5,
    debug = (Config and Config.Debug) == true,
    options = {
      {
        name = ('azh_store_%s'):format(gar.id),
        icon = 'fa-solid fa-warehouse',
        label = 'Store Vehicle',
        onSelect = function()
          if AZH.Garage and AZH.Garage.store then
            AZH.Garage.store(houseId, gar.id)
          end
        end
      },
      {
        name = ('azh_take_%s'):format(gar.id),
        icon = 'fa-solid fa-car',
        label = 'Retrieve Vehicle',
        onSelect = function()
          if AZH.Garage and AZH.Garage.openList then
            AZH.Garage.openList(houseId, gar.id)
          end
        end
      },
      {
        name = ('azh_portal_g_%s'):format(gar.id),
        icon = 'fa-solid fa-house',
        label = 'Housing Portal',
        onSelect = function()
          if AZH.UI and AZH.UI.open then AZH.UI.open({ houseId = houseId }) end
        end
      }
    }
  })

  AZH.C.zones.garages[#AZH.C.zones.garages+1] = zname
end

local function scheduleTargetRetry()
  if AZH.__targetRetryThread then return end
  AZH.__targetRetryThread = true

  CreateThread(function()
    local loops = 0
    while loops < 40 do
      loops += 1
      if hasTarget() and AZH.C and AZH.C.ready then
        AZH.__targetRetryThread = false
        AZH.Target.buildAll()
        return
      end
      Wait(250)
    end
    AZH.__targetRetryThread = false
  end)
end

function AZH.Target.buildAll()
  if not hasTarget() then
    scheduleTargetRetry()
    return
  end

  AZH.C.resetZones()

  for _, door in ipairs(AZH.C.doors or {}) do
    addDoorZone(door)
  end

  for _, gar in ipairs(AZH.C.garages or {}) do
    addGarageZone(gar)
  end

  AZH.Target.refreshInteriorExit()
end

function AZH.Target.refreshInteriorExit()
  if not hasTarget() then
    scheduleTargetRetry()
    return
  end

  if AZH.C.zones.interiorExit then
    pcall(function() exports.ox_target:removeZone(AZH.C.zones.interiorExit) end)
    AZH.C.zones.interiorExit = nil
  end

  if not AZH.C.currentHouseId then return end
  local h = AZH.C.houses and AZH.C.houses[AZH.C.currentHouseId]
  local it = h and AZH.C.interiors and AZH.C.interiors[h.interior] or nil
  if not (it and it.exit) then return end

  local zname = 'azh_interior_exit'
  exports.ox_target:addSphereZone({
    name = zname,
    coords = vec3(it.exit.x, it.exit.y, it.exit.z),
    radius = 1.8,
    debug = (Config and Config.Debug) == true,
    options = {
      {
        name = 'azh_leave',
        icon = 'fa-solid fa-door-closed',
        label = 'Exit',
        onSelect = function()
          if AZH.leaveInterior then AZH.leaveInterior() end
        end
      }
    }
  })

  AZH.C.zones.interiorExit = zname
end

AddEventHandler('onClientResourceStart', function(resName)
  if resName ~= 'ox_target' then return end
  if AZH.C and AZH.C.ready then
    Wait(250)
    AZH.Target.buildAll()
  end
end)

AddEventHandler('az_housing:client:rebuildTargets', function()
  if AZH.Target then AZH.Target.buildAll() end
end)

AddEventHandler('az_housing:client:enteredInterior', function()
  if AZH.Target then AZH.Target.refreshInteriorExit() end
end)

AddEventHandler('az_housing:client:leftInterior', function()
  if AZH.Target then AZH.Target.refreshInteriorExit() end
end)
