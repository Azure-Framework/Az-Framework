local Config = Config or {}
Config.Plates = Config.Plates or {}
if Config.Plates.Enabled == false or Config.Plates.UseOxTarget == false then return end
if GetResourceState('ox_target') ~= 'started' then return end

local registered = false

local function normalizePlate(plate)
    plate = tostring(plate or '')
    plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' then return nil end
    return plate:upper()
end

local function notify(msg, typ)
    if exports and exports['Az-Framework'] and exports['Az-Framework'].hudNotify then
        pcall(function()
            exports['Az-Framework']:hudNotify({
                title = 'Plates',
                description = tostring(msg or ''),
                icon = typ == 'bad' and 'bi-exclamation-triangle' or 'bi-credit-card-2-front',
                sound = typ == 'bad' and 'cashDown' or 'job'
            })
        end)
        return
    end
    if lib and lib.notify then
        lib.notify({ title = 'Plates', description = tostring(msg or ''), type = typ == 'bad' and 'error' or 'inform' })
    end
end

local function canUseOnVehicle(entity)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    if GetEntitySpeed(entity) > 0.5 then return false end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
    return true
end

local function removePlate(entity)
    if not canUseOnVehicle(entity) then return end
    local currentPlate = normalizePlate(GetVehicleNumberPlateText(entity))
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(entity))
    local result = lib.callback.await('azfw:plates:removePlate', false, currentPlate, model)
    if result and result.ok then
        SetVehicleNumberPlateText(entity, tostring(result.blankPlateText or 'NO PLATE'))
        notify(('Removed plate %s. It was saved.'):format(currentPlate or 'UNKNOWN'))
    elseif result and result.error then
        notify(result.error, 'bad')
    end
end

local function installPlate(entity)
    if not canUseOnVehicle(entity) then return end
    local list = lib.callback.await('azfw:plates:getList', false) or {}
    if #list == 0 then
        notify('You do not have any saved plates.', 'bad')
        return
    end

    local options = {}
    for i = 1, #list do
        local row = list[i]
        options[#options + 1] = {
            title = tostring(row.text or 'Saved Plate'),
            description = row.meta and row.meta.model and ('Removed from %s'):format(row.meta.model) or 'Install this saved plate',
            onSelect = function()
                local currentPlate = normalizePlate(GetVehicleNumberPlateText(entity))
                local model = GetDisplayNameFromVehicleModel(GetEntityModel(entity))
                local result = lib.callback.await('azfw:plates:installPlate', false, row.id, currentPlate, model)
                if result and result.ok then
                    SetVehicleNumberPlateText(entity, tostring(result.plate or row.text or ''))
                    notify(('Installed plate %s.'):format(tostring(result.plate or row.text or 'saved plate')))
                elseif result and result.error then
                    notify(result.error, 'bad')
                end
            end
        }
    end

    lib.registerContext({ id = 'azfw_saved_plates_menu', title = 'Saved Plates', options = options })
    lib.showContext('azfw_saved_plates_menu')
end

CreateThread(function()
    if registered then return end
    registered = true
    exports.ox_target:addGlobalVehicle({
        {
            name = 'azfw_remove_plate',
            icon = 'fas fa-screwdriver-wrench',
            label = 'Remove Plate',
            distance = tonumber(Config.Plates.TargetDistance or 2.0) or 2.0,
            canInteract = function(entity)
                if not canUseOnVehicle(entity) then return false end
                local plate = normalizePlate(GetVehicleNumberPlateText(entity))
                return plate ~= nil and plate ~= normalizePlate(Config.Plates.BlankPlateText or 'NO PLATE')
            end,
            onSelect = function(data)
                removePlate(data.entity)
            end
        },
        {
            name = 'azfw_install_saved_plate',
            icon = 'fas fa-id-card',
            label = 'Install Saved Plate',
            distance = tonumber(Config.Plates.TargetDistance or 2.0) or 2.0,
            canInteract = function(entity)
                return canUseOnVehicle(entity)
            end,
            onSelect = function(data)
                installPlate(data.entity)
            end
        }
    })
end)
