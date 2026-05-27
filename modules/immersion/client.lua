local CFG = (Config and Config.Immersion) or {}
if CFG.Enabled == false then return end

local RESOURCE_NAME = GetCurrentResourceName()
local Shared = AZ_IMMERSION_SHARED or {}
local registeredTargets = false

local function dprint(...)
    if not CFG.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(('^3[%s C]^7 %s'):format(RESOURCE_NAME, table.concat(args, ' ')))
end

local function notify(message, notifType)
    if lib and lib.notify then
        lib.notify({
            title = 'Immersion',
            description = tostring(message or ''),
            type = notifType or 'inform'
        })
    else
        print(('[Immersion] %s'):format(tostring(message or '')))
    end
end

local function getStreetLabel(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local street = streetHash and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash and GetStreetNameFromHashKey(crossingHash) or ''
    if street ~= '' and crossing ~= '' then
        return ('%s / %s'):format(street, crossing)
    end
    if street ~= '' then return street end
    if crossing ~= '' then return crossing end
    return 'Unknown Street'
end

local function buildPropPayload(entity, family)
    local coords = GetEntityCoords(entity)
    local model = GetEntityModel(entity)
    local key = Shared.makeObjectKey and Shared.makeObjectKey(family, model, coords) or (family .. ':' .. tostring(model))
    local zone = GetNameOfZone(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or 0

    return {
        family = family,
        model = model,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        key = key,
        zone = tostring(zone or ''),
        street = getStreetLabel(coords),
        netId = netId,
    }
end

local function buildPedPayload(entity)
    local coords = GetEntityCoords(entity)
    local model = GetEntityModel(entity)
    local zone = GetNameOfZone(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local heading = GetEntityHeading(entity)
    local npcKey = ('npc:%s:%.1f:%.1f:%.1f:%.1f'):format(tostring(model), Shared.round(coords.x, 1), Shared.round(coords.y, 1), Shared.round(coords.z, 1), Shared.round(heading, 0))

    return {
        npcKey = npcKey,
        model = model,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        zone = tostring(zone or ''),
        street = getStreetLabel(coords),
        heading = heading + 0.0,
    }
end

local function runScenarioProgress(action, coords)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return false end
    if IsPedInAnyVehicle(ped, false) then
        notify('Get out of the vehicle first.', 'error')
        return false
    end

    if coords then
        TaskTurnPedToFaceCoord(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, 500)
        Wait(200)
    end

    if action.scenario and action.scenario ~= '' then
        TaskStartScenarioInPlace(ped, action.scenario, 0, true)
        Wait(125)
    end

    local ok = true
    if lib and lib.progressCircle then
        ok = lib.progressCircle({
            duration = tonumber(action.duration) or 2200,
            position = 'bottom',
            label = action.label,
            canCancel = true,
            disable = {
                move = true,
                combat = true,
                car = true,
                sprint = true,
            }
        })
    else
        Wait(tonumber(action.duration) or 2200)
        ok = true
    end

    ClearPedTasks(ped)
    return ok == true
end

local function runSkillCheck(action)
    if not action.skill or not lib or not lib.skillCheck then
        return true
    end
    return lib.skillCheck(action.skill, { 'e', 'q', 'r' }) == true
end

local function promptExtra(actionName)
    if not lib or not lib.inputDialog then return nil end

    if actionName == 'leave_note' then
        local result = lib.inputDialog('Leave Note', {
            { type = 'textarea', label = 'Message', required = true, min = 3, max = CFG.MaxNoteLength or 180 }
        })
        return result and result[1] or nil
    elseif actionName == 'hide_item' then
        local result = lib.inputDialog('Hide Small Item', {
            { type = 'input', label = 'Item label', required = true, min = 2, max = 48 }
        })
        return result and result[1] or nil
    elseif actionName == 'leave_gift' then
        local result = lib.inputDialog('Leave Gift', {
            { type = 'input', label = 'Gift / flowers / item', required = true, min = 2, max = 48 }
        })
        return result and result[1] or nil
    elseif actionName == 'report' then
        local result = lib.inputDialog('Report Suspicious Activity', {
            { type = 'textarea', label = 'Reason', required = true, min = 5, max = CFG.MaxReasonLength or 240 }
        })
        return result and result[1] or nil
    elseif actionName == 'ask_out' then
        local result = lib.inputDialog('Ask Out', {
            {
                type = 'select',
                label = 'Date Idea',
                required = true,
                options = {
                    { value = 'coffee', label = 'Coffee Run' },
                    { value = 'beach', label = 'Beach Walk' },
                    { value = 'diner', label = 'Late Night Diner' },
                    { value = 'drive', label = 'Night Drive' },
                }
            }
        })
        return result and result[1] or nil
    end

    return nil
end

local function sendPropAction(entity, family, action)
    local payload = buildPropPayload(entity, family)
    payload.action = action.name

    local extra = nil
    if action.prompt then
        extra = promptExtra(action.name)
        if not extra or extra == '' then return end
        payload.extra = tostring(extra)
    end

    if not runScenarioProgress(action, payload.coords) then
        return
    end

    payload.skillPassed = runSkillCheck(action)
    TriggerServerEvent('azfw:immersion:server:performPropAction', payload)
end

local function sendSocialAction(entity, action)
    local payload = buildPedPayload(entity)
    payload.action = action.name

    local extra = nil
    if action.prompt then
        extra = promptExtra(action.name)
        if not extra or extra == '' then return end
        payload.extra = tostring(extra)
    end

    if not runScenarioProgress(action, payload.coords) then
        return
    end

    payload.skillPassed = runSkillCheck(action)
    TriggerServerEvent('azfw:immersion:server:performSocialAction', payload)
end

local function openPropMenu(entity, family)
    local familyCfg = (CFG.PropFamilies or {})[family]
    if not familyCfg then return end

    local actions = Shared.getPropActionsForFamily and Shared.getPropActionsForFamily(family) or {}
    local options = {}

    for i = 1, #actions do
        local action = actions[i]
        options[#options + 1] = {
            title = action.label,
            description = action.description,
            icon = action.icon,
            onSelect = function()
                sendPropAction(entity, family, action)
            end
        }
    end

    if lib and lib.registerContext and lib.showContext then
        local menuId = ('azimm_prop_%s'):format(family)
        lib.registerContext({
            id = menuId,
            title = familyCfg.label or family,
            options = options,
        })
        lib.showContext(menuId)
    end
end

local function openPedMenu(entity)
    local actions = Shared.getSocialActions and Shared.getSocialActions() or {}
    local options = {}

    for i = 1, #actions do
        local action = actions[i]
        options[#options + 1] = {
            title = action.label,
            description = action.description,
            icon = action.icon,
            onSelect = function()
                sendSocialAction(entity, action)
            end
        }
    end

    if lib and lib.registerContext and lib.showContext then
        local menuId = 'azimm_social_ped'
        lib.registerContext({
            id = menuId,
            title = 'NPC Interaction',
            options = options,
        })
        lib.showContext(menuId)
    end
end

local function registerTargets()
    if registeredTargets then return end
    if CFG.UseOxTarget == false then return end
    if GetResourceState('ox_target') ~= 'started' then
        dprint('ox_target not started, immersion target registration skipped for now')
        return
    end

    if CFG.EnablePropInteractions ~= false then
        for family, familyCfg in pairs(CFG.PropFamilies or {}) do
            local models = Shared.getModelsForTarget and Shared.getModelsForTarget(family) or {}
            if #models > 0 then
                exports.ox_target:addModel(models, {
                    {
                        name = ('azimm_%s'):format(family),
                        icon = familyCfg.icon or 'fa-solid fa-hand',
                        label = familyCfg.label or family,
                        distance = familyCfg.targetDistance or CFG.TargetDistance or 1.9,
                        canInteract = function(entity, distance)
                            return DoesEntityExist(entity) and distance <= (familyCfg.targetDistance or CFG.TargetDistance or 1.9)
                        end,
                        onSelect = function(data)
                            openPropMenu(data.entity, family)
                        end
                    }
                })
            end
        end
    end

    if CFG.EnableNPCSocial ~= false then
        exports.ox_target:addGlobalPed({
            {
                name = 'azimm_social_ped',
                icon = 'fa-solid fa-comments',
                label = 'Talk / Interact',
                distance = CFG.NPCDistance or 2.2,
                canInteract = function(entity, distance)
                    return DoesEntityExist(entity)
                        and not IsPedAPlayer(entity)
                        and not IsPedDeadOrDying(entity, true)
                        and distance <= (CFG.NPCDistance or 2.2)
                end,
                onSelect = function(data)
                    openPedMenu(data.entity)
                end
            }
        })
    end

    registeredTargets = true
    dprint('Immersion targets registered')
end

RegisterNetEvent('azfw:immersion:client:actionResult', function(payload)
    if type(payload) ~= 'table' then return end
    notify(payload.message or 'Interaction completed.', payload.type or 'inform')
end)

CreateThread(function()
    local timeout = GetGameTimer() + 15000
    while GetResourceState('ox_target') ~= 'started' and GetGameTimer() < timeout do
        Wait(500)
    end
    registerTargets()
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() and res ~= 'ox_target' then return end
    Wait(500)
    registerTargets()
end)
