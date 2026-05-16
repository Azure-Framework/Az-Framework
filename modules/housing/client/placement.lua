AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end

local placing = false

local function isAdmin()
  return (AZH and AZH.isAdmin and AZH.isAdmin() == true) or false
end

local function inputNumber(label, default)
  local v = tonumber(default or 0)
  return { type = 'number', label = label, default = v }
end

local function pickInteriorOptions()
  local opts = {}
  for k, v in pairs(Config.Interiors or {}) do
    opts[#opts+1] = { label = ('%s (%s)'):format(v.label or k, k), value = k }
  end
  table.sort(opts, function(a,b) return a.label < b.label end)
  return opts
end

local function openAdminMenu()
  if not isAdmin() then
    AZH.notify('error', 'Housing', 'No permission.')
    return
  end

  lib.registerContext({
    id = 'azh_admin',
    title = 'Housing Editor',
    options = {
      {
        title = 'Create House',
        icon = 'plus',
        onSelect = function()
          local interiors = pickInteriorOptions()
          local input = lib.inputDialog('Create House', {
            { type='input', label='Name', placeholder='Mirror Park 12', required=true },
            { type='input', label='Label (optional)', placeholder='2 Bed / 1 Bath' },
            inputNumber('Sale Price', Config.Defaults.SalePrice),
            { type='select', label='Interior Template', options=interiors, default=interiors[1] and interiors[1].value or 'apt_basic' },
          })
          if not input then return end
          TriggerServerEvent('az_housing:server:adminCreateHouse', {
            name = input[1],
            label = input[2],
            price = tonumber(input[3]) or Config.Defaults.SalePrice,
            interior = input[4] or 'apt_basic',
          })
        end
      },
      {
        title = 'Place Door Entrance (stand at the door)',
        icon = 'door-open',
        onSelect = function()
          local input = lib.inputDialog('Place Door', {
            inputNumber('House ID', 1),
            { type='input', label='Door Label', default='Front Door' },
            inputNumber('Radius', 2.0),
          })
          if not input then return end
          local houseId = tonumber(input[1])
          local ped = PlayerPedId()
          local coords = GetEntityCoords(ped)
          local heading = GetEntityHeading(ped)
          TriggerServerEvent('az_housing:server:adminAddDoor', {
            house_id = houseId,
            x = coords.x, y = coords.y, z = coords.z,
            heading = heading,
            radius = tonumber(input[3]) or 2.0,
            label = input[2] or 'Door'
          })
        end
      },
      {
        title = 'Place Garage Entrance (stand at garage entry)',
        icon = 'warehouse',
        onSelect = function()
          local input = lib.inputDialog('Place Garage', {
            inputNumber('House ID', 1),
            { type='input', label='Garage Label', default='Garage' },
            inputNumber('Radius', Config.Garage and Config.Garage.DefaultRadius or 2.2),
            { type='checkbox', label='Use my current vehicle position as spawn?', checked=true },
          })
          if not input then return end
          local houseId = tonumber(input[1])
          local ped = PlayerPedId()
          local coords = GetEntityCoords(ped)
          local heading = GetEntityHeading(ped)

          local spawn = coords
          local sh = heading
          if input[4] == true then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh and veh ~= 0 then
              spawn = GetEntityCoords(veh)
              sh = GetEntityHeading(veh)
            end
          else

            local fwd = GetEntityForwardVector(ped)
            spawn = coords + (fwd * 6.0)
            sh = heading
          end

          TriggerServerEvent('az_housing:server:adminAddGarage', {
            house_id = houseId,
            x = coords.x, y = coords.y, z = coords.z,
            heading = heading,
            spawn_x = spawn.x, spawn_y = spawn.y, spawn_z = spawn.z,
            spawn_h = sh,
            radius = tonumber(input[3]) or (Config.Garage and Config.Garage.DefaultRadius or 2.2),
            label = input[2] or 'Garage'
          })
        end
      },
      {
        title = 'Delete House',
        icon = 'trash',
        onSelect = function()
          local input = lib.inputDialog('Delete House', { inputNumber('House ID', 1) })
          if not input then return end
          TriggerServerEvent('az_housing:server:adminDeleteHouse', tonumber(input[1]))
        end
      },
      {
        title = 'Reload (server)',
        icon = 'rotate',
        onSelect = function()
          TriggerServerEvent('az_housing:server:adminReload')
        end
      }
    }
  })

  lib.showContext('azh_admin')
end

RegisterCommand(Config.Commands.Placement or 'housingedit', function()
  openAdminMenu()
end)
