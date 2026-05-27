local Config = (Config and Config.Insurance) or {}
local Wreck = Config.WreckSystem or {}
if Config.Enabled == false or Wreck.Enabled == false then return end

local incidents = {}
local incidentCooldowns = {}
local nextImpactDetectionAt = 0
local lastVeh = 0
local lastBodyHealth = 1000.0
local lastImpactScan = 0
local collisionWindowUntil = 0
local lastSpeedMph = 0.0

local colorNames = {
    [0] = 'black', [1] = 'black', [3] = 'silver', [4] = 'silver', [5] = 'blue', [27] = 'red', [28] = 'red',
    [38] = 'green', [64] = 'yellow', [111] = 'white', [112] = 'white', [131] = 'white', [135] = 'pink'
}

local function notify(msg, typ)
    if exports and exports['Az-Framework'] and exports['Az-Framework'].hudNotify then
        pcall(function()
            exports['Az-Framework']:hudNotify({
                title = 'Insurance',
                description = tostring(msg or ''),
                icon = typ == 'bad' and 'bi-exclamation-triangle' or 'bi-car-front',
                sound = typ == 'bad' and 'cashDown' or 'job'
            })
        end)
        return
    end
    if lib and lib.notify then
        lib.notify({ title = 'Insurance', description = tostring(msg or ''), type = typ == 'bad' and 'error' or 'inform' })
    end
end

local function debugLog(...)
    if Config.Debug ~= true and Wreck.Debug ~= true then return end
    local parts = { '^3[az_insurance][wreck]^7' }
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print(table.concat(parts, ' '))
end

local function normalizePlate(plate)
    plate = tostring(plate or '')
    plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' then return nil end
    return plate:upper()
end

local function mph(speed)
    return (tonumber(speed) or 0.0) * 2.236936
end

local function getDriverVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return veh
end

local function resolveVehicleEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return 0 end
    if IsEntityAVehicle(entity) then return entity end
    if IsEntityAPed(entity) and IsPedInAnyVehicle(entity, false) then
        return GetVehiclePedIsIn(entity, false)
    end
    return 0
end

local function isStrictVehicleToVehicleCollision(playerVeh, otherVeh)
    if not playerVeh or playerVeh == 0 or not DoesEntityExist(playerVeh) then return false end
    if not otherVeh or otherVeh == 0 or not DoesEntityExist(otherVeh) then return false end
    if playerVeh == otherVeh then return false end
    if not IsEntityAVehicle(playerVeh) or not IsEntityAVehicle(otherVeh) then return false end

    local touching = IsEntityTouchingEntity and (IsEntityTouchingEntity(playerVeh, otherVeh) or IsEntityTouchingEntity(otherVeh, playerVeh)) or false
    local damagedPair = HasEntityBeenDamagedByEntity(playerVeh, otherVeh, true) or HasEntityBeenDamagedByEntity(otherVeh, playerVeh, true)

    return touching or damagedPair
end

local function draw3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    local cam = GetGameplayCamCoords()
    local dist = #(vector3(x, y, z) - cam)
    local scale = (1.0 / math.max(dist, 1.0)) * (1.0 / GetGameplayCamFov()) * 100.0
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(0.0, 0.35 * scale)
    SetTextColour(255, 255, 255, 230)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function getVehicleDisplayName(veh)
    local model = GetEntityModel(veh)
    local label = GetDisplayNameFromVehicleModel(model)
    if not label or label == '' or label == 'CARNOTFOUND' then return 'vehicle' end
    local pretty = GetLabelText(label)
    if pretty and pretty ~= '' and pretty ~= 'NULL' then return pretty end
    return label
end

local function getVehicleColorName(veh)
    local primary = select(1, GetVehicleColours(veh))
    return colorNames[primary] or ('color %s'):format(tostring(primary))
end

local function buildVehicleDescriptor(veh)
    return {
        plate = normalizePlate(GetVehicleNumberPlateText(veh)),
        model = getVehicleDisplayName(veh),
        color = getVehicleColorName(veh),
    }
end

local function setHazards(vehicle, enabled)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetVehicleIndicatorLights(vehicle, 0, enabled == true)
    SetVehicleIndicatorLights(vehicle, 1, enabled == true)
end

local function resolveGroundZ(x, y, zHint)
    local baseZ = math.max((tonumber(zHint) or 0.0) + 2.0, 32.0)
    for i = 0, 20 do
        local probeZ = baseZ + (i * 4.0)
        local ok, groundZ = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, probeZ + 0.0, false)
        if ok then
            return groundZ
        end
    end
    return nil
end

local function getRoadsideStopTarget(veh)
    local target = GetOffsetFromEntityInWorldCoords(veh, 2.8, 15.0, 0.0)
    local vehPos = GetEntityCoords(veh)
    local groundZ = resolveGroundZ(target.x, target.y, math.max(target.z, vehPos.z))
    return vector3(target.x, target.y, (groundZ or math.max(target.z, vehPos.z)) + 0.03)
end

local function getExchangeStandPos(veh, ped)
    local target = GetOffsetFromEntityInWorldCoords(veh, -1.15, 1.2, 0.0)
    local vehPos = GetEntityCoords(veh)
    local pedPos = DoesEntityExist(ped) and GetEntityCoords(ped) or vehPos
    local zHint = math.max(target.z, pedPos.z, vehPos.z)
    local groundZ = resolveGroundZ(target.x, target.y, zHint)
    return vector3(target.x, target.y, (groundZ or zHint) + 0.03)
end

local function removeTrafficZone(incident)
    if not incident then return end
    if incident.trafficZone then
        pcall(function()
            RemoveRoadNodeSpeedZone(incident.trafficZone)
        end)
        incident.trafficZone = nil
    end
end

local function ensureTrafficZone(incident, center)
    if not incident or not center then return end
    local radius = tonumber(Wreck.TrafficZoneRadius or 35.0) or 35.0
    local speed = tonumber(Wreck.TrafficZoneSpeed or 8.0) or 8.0
    if incident.trafficZoneCenter and #(incident.trafficZoneCenter - center) < 8.0 and incident.trafficZone then
        return
    end
    removeTrafficZone(incident)
    local ok, zone = pcall(function()
        return AddRoadNodeSpeedZone(center.x, center.y, center.z, radius, speed, false)
    end)
    if ok and zone then
        incident.trafficZone = zone
        incident.trafficZoneCenter = center
    end
end

local function getIncidentKeyForVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 then return ('net:%s'):format(netId) end
    return ('ent:%s'):format(vehicle)
end

local function isVehicleOnCooldown(vehicle)
    local key = getIncidentKeyForVehicle(vehicle)
    if not key then return false end
    local untilAt = incidentCooldowns[key]
    if not untilAt then return false end
    if GetGameTimer() >= untilAt then
        incidentCooldowns[key] = nil
        return false
    end
    return true
end

local function markVehicleCooldown(vehicle, ms)
    local key = getIncidentKeyForVehicle(vehicle)
    if not key then return end
    incidentCooldowns[key] = GetGameTimer() + math.max(tonumber(ms) or 0, 0)
end

local function releaseNpc(incident, driveAway)
    if not incident then return end
    incident.readyForExchange = false
    incident.status = driveAway and 'departing' or 'released'
    removeTrafficZone(incident)

    local ped = incident.npcPed
    local veh = incident.npcVeh

    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedKeepTask(ped, false)
        ClearPedTasksImmediately(ped)
        ClearPedSecondaryTask(ped)
        if ClearEntityLastDamageEntity then ClearEntityLastDamageEntity(ped) end
    end

    if DoesEntityExist(veh) then
        SetVehicleDoorsLocked(veh, 1)
        SetVehicleHandbrake(veh, false)
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, driveAway == true, true, false)
        setHazards(veh, false)
        if ClearEntityLastDamageEntity then ClearEntityLastDamageEntity(veh) end
    end

    if driveAway and DoesEntityExist(ped) and DoesEntityExist(veh) then
        CreateThread(function()
            local driverDoorPos = GetOffsetFromEntityInWorldCoords(veh, -1.0, 0.85, 0.0)
            local driverDoorGroundZ = resolveGroundZ(driverDoorPos.x, driverDoorPos.y, driverDoorPos.z)
            if driverDoorGroundZ then
                driverDoorPos = vector3(driverDoorPos.x, driverDoorPos.y, driverDoorGroundZ + 0.03)
            end
            RequestCollisionAtCoord(driverDoorPos.x, driverDoorPos.y, driverDoorPos.z)
            if #(GetEntityCoords(ped) - driverDoorPos) > 1.6 then
                TaskGoStraightToCoord(ped, driverDoorPos.x, driverDoorPos.y, driverDoorPos.z, 1.0, 1800, GetEntityHeading(veh), 0.05)
                Wait(900)
            end

            if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
            ClearPedTasks(ped)
            TaskTurnPedToFaceEntity(ped, veh, 800)
            Wait(350)
            TaskEnterVehicle(ped, veh, 6000, -1, 1.0, 1, 0)

            local enterDeadline = GetGameTimer() + 7000
            while GetGameTimer() < enterDeadline do
                if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
                if IsPedInVehicle(ped, veh, false) then break end
                Wait(100)
            end

            if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
            if not IsPedInVehicle(ped, veh, false) then
                SetPedIntoVehicle(ped, veh, -1)
                Wait(150)
            end
            if not IsPedInVehicle(ped, veh, false) then
                TaskWanderStandard(ped, 10.0, 10)
                return
            end

            SetVehicleEngineOn(veh, true, true, false)
            SetVehicleHandbrake(veh, false)
            setHazards(veh, false)
            SetDriveTaskDrivingStyle(ped, 786603)
            TaskVehicleDriveWander(ped, veh, 16.0, 786603)

            local moveStart = GetGameTimer()
            local moved = false
            while GetGameTimer() - moveStart < 4000 do
                if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
                if GetEntitySpeed(veh) > 1.0 then
                    moved = true
                    break
                end
                Wait(150)
            end

            if not moved and DoesEntityExist(ped) and DoesEntityExist(veh) then
                local forward = GetOffsetFromEntityInWorldCoords(veh, 0.0, 70.0, 0.0)
                TaskVehicleDriveToCoordLongrange(ped, veh, forward.x, forward.y, forward.z, 16.0, 786603, 8.0)
                SetDriveTaskDrivingStyle(ped, 786603)
            end
        end)
    end
end

local function cleanupIncident(id, driveAway)
    local incident = incidents[id]
    if not incident then return end
    if incident.npcVeh and DoesEntityExist(incident.npcVeh) then
        markVehicleCooldown(incident.npcVeh, driveAway and 18000 or 12000)
    end
    nextImpactDetectionAt = GetGameTimer() + 6000
    releaseNpc(incident, driveAway == true)
    incidents[id] = nil
end

local function stageNpcForExchange(incident)
    if not incident or not DoesEntityExist(incident.npcVeh) or not DoesEntityExist(incident.npcPed) then return end

    local veh = incident.npcVeh
    local ped = incident.npcPed

    setHazards(veh, true)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleHandbrake(veh, true)
    SetVehicleEngineOn(veh, false, true, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    ClearPedTasksImmediately(ped)
    TaskLeaveVehicle(ped, veh, 256)

    local timeoutAt = GetGameTimer() + 5000
    while GetGameTimer() < timeoutAt do
        if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
        if not IsPedInAnyVehicle(ped, false) then break end
        Wait(50)
    end

    if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end

    local standPos = getExchangeStandPos(veh, ped)
    RequestCollisionAtCoord(standPos.x, standPos.y, standPos.z)
    ClearPedTasksImmediately(ped)
    TaskGoStraightToCoord(ped, standPos.x, standPos.y, standPos.z, 1.0, 3500, GetEntityHeading(veh), 0.05)

    local moveUntil = GetGameTimer() + 2200
    while GetGameTimer() < moveUntil do
        if not DoesEntityExist(ped) then return end
        if #(GetEntityCoords(ped) - standPos) <= 0.9 then break end
        Wait(50)
    end

    if not DoesEntityExist(ped) then return end
    ClearPedTasksImmediately(ped)
    RequestCollisionAtCoord(standPos.x, standPos.y, standPos.z)
    SetEntityCoordsNoOffset(ped, standPos.x, standPos.y, standPos.z, false, false, false)
    SetEntityHeading(ped, GetEntityHeading(veh) + 90.0)
    FreezeEntityPosition(ped, true)
    TaskStandStill(ped, -1)
    incident.readyForExchange = true
    incident.status = 'exchange_ready'
end

local function pullOverIncident(incident)
    if not incident or not DoesEntityExist(incident.npcVeh) or not DoesEntityExist(incident.npcPed) then return end

    incident.status = 'pulling_over'
    setHazards(incident.npcVeh, true)
    SetVehicleEngineOn(incident.npcVeh, true, true, false)
    SetVehicleBrakeLights(incident.npcVeh, true)
    SetVehicleDoorsLocked(incident.npcVeh, 2)

    local stopTarget = getRoadsideStopTarget(incident.npcVeh)
    TaskVehicleDriveToCoordLongrange(incident.npcPed, incident.npcVeh, stopTarget.x, stopTarget.y, stopTarget.z, 8.0, 786603, 8.0)
    SetDriveTaskDrivingStyle(incident.npcPed, 786603)
    ensureTrafficZone(incident, GetEntityCoords(incident.npcVeh))

    CreateThread(function()
        local veh = incident.npcVeh
        local ped = incident.npcPed
        Wait(2600)
        if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end

        if BringVehicleToHalt then
            BringVehicleToHalt(veh, 4.0, 3000, false)
        else
            TaskVehicleTempAction(ped, veh, 27, 3000)
        end

        Wait(900)
        if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
        ClearPedTasks(ped)
        TaskVehicleTempAction(ped, veh, 27, 1800)
        Wait(900)

        if DoesEntityExist(veh) then
            SetVehicleHandbrake(veh, true)
            SetVehicleEngineOn(veh, false, true, false)
            setHazards(veh, true)
            SetVehicleBrakeLights(veh, true)
            ensureTrafficZone(incident, GetEntityCoords(veh))
        end

        stageNpcForExchange(incident)
    end)
end

RegisterNetEvent('az_insurance:repairVehicle', function(data)
    data = type(data) == 'table' and data or {}
    local wantedPlate = normalizePlate(data.plate)
    local ped = PlayerPedId()
    local veh = getDriverVehicle()

    if not veh then
        local pos = GetEntityCoords(ped)
        for _, candidate in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(candidate) and #(GetEntityCoords(candidate) - pos) < 8.0 then
                if normalizePlate(GetVehicleNumberPlateText(candidate)) == wantedPlate then
                    veh = candidate
                    break
                end
            end
        end
    end

    if veh and DoesEntityExist(veh) then
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehiclePetrolTankHealth(veh, 1000.0)
        SetVehicleDirtLevel(veh, 0.0)
        notify(('Your insured vehicle %s was repaired.'):format(wantedPlate or 'vehicle'), 'info')
    end
end)

AddEventHandler('entityDamaged', function(victim, culprit, weapon, baseDamage)
    local playerVeh = getDriverVehicle()
    if not playerVeh or playerVeh == 0 then return end
    if GetGameTimer() < nextImpactDetectionAt then return end

    local victimVeh = resolveVehicleEntity(victim)
    local culpritVeh = resolveVehicleEntity(culprit)
    if victimVeh == 0 or culpritVeh == 0 then
        debugLog('ignoring damage event because it was not vehicle-vs-vehicle', 'victim=', victim or 0, 'culprit=', culprit or 0)
        return
    end

    local otherVeh = 0
    if culpritVeh == playerVeh and victimVeh ~= playerVeh then
        otherVeh = victimVeh
    elseif victimVeh == playerVeh and culpritVeh ~= playerVeh then
        otherVeh = culpritVeh
    else
        debugLog('ignoring damage event because player vehicle not in pair', 'playerVeh=', playerVeh, 'victimVeh=', victimVeh, 'culpritVeh=', culpritVeh)
        return
    end

    if otherVeh == 0 or not DoesEntityExist(otherVeh) or not IsEntityAVehicle(otherVeh) then
        debugLog('ignoring damage event because other entity is not a valid vehicle', 'otherVeh=', otherVeh)
        return
    end

    local driver = GetPedInVehicleSeat(otherVeh, -1)
    if driver == 0 or not DoesEntityExist(driver) or IsPedAPlayer(driver) then
        debugLog('ignoring damage event because other vehicle driver is not an NPC', 'otherVeh=', otherVeh, 'driver=', driver or 0)
        return
    end

    if not isStrictVehicleToVehicleCollision(playerVeh, otherVeh) then
        debugLog('ignoring damage event because strict collision proof failed', 'playerVeh=', playerVeh, 'otherVeh=', otherVeh)
        return
    end

    debugLog('confirmed vehicle-to-vehicle collision', 'playerVeh=', playerVeh, 'otherVeh=', otherVeh, 'weapon=', weapon or 0, 'baseDamage=', baseDamage or 0)
    beginIncident(playerVeh, otherVeh)
end)

CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local dt = GetFrameTime()
        local exchangePromptDistance = tonumber(Wreck.ExchangePromptDistance or Wreck.ExchangeDistance or 4.0) or 4.0

        for id, incident in pairs(incidents) do
            if not DoesEntityExist(incident.npcPed) or not DoesEntityExist(incident.npcVeh) then
                cleanupIncident(id, false)
                goto continue
            end

            local npcPos = GetEntityCoords(incident.npcPed)
            local dist = #(npcPos - pcoords)

            if incident.trafficZoneCenter and Wreck.TrafficZoneVisible ~= false then
                local radius = tonumber(Wreck.TrafficZoneRadius or 35.0) or 35.0
                DrawMarker(1, incident.trafficZoneCenter.x, incident.trafficZoneCenter.y, incident.trafficZoneCenter.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, radius * 2.0, radius * 2.0, 1.2, 255, 180, 0, 50, false, false, 2, false, nil, nil, false)
            end

            if incident.readyForExchange and not incident.exchanged and not incident.reported and dist <= exchangePromptDistance and not IsPedInAnyVehicle(ped, false) then
                draw3D(npcPos.x, npcPos.y, npcPos.z + 1.0, '[E] Exchange insurance info')
                if IsControlJustPressed(0, 38) then
                    incident.exchanged = true
                    incident.readyForExchange = false
                    incident.sightSeconds = 0.0
                    incident.fleeingSince = nil
                    TriggerServerEvent('az_insurance:wreckExchangeComplete', {
                        playerPlate = incident.playerPlate,
                        playerModel = incident.playerModel,
                        playerColor = incident.playerColor,
                        suspectPlate = incident.suspectPlate,
                        suspectModel = incident.suspectModel,
                        suspectColor = incident.suspectColor,
                    })
                    notify(('Insurance exchanged. %s %s / %s %s recorded.'):format(
                        tostring(incident.playerColor or 'unknown'), tostring(incident.playerModel or 'vehicle'),
                        tostring(incident.suspectColor or 'unknown'), tostring(incident.suspectModel or 'vehicle')
                    ), 'info')
                    releaseNpc(incident, true)
                    incident.cleanupAt = GetGameTimer() + 4500
                end
            end

            if incident.readyForExchange and not incident.exchanged and not incident.reported then
                local inVehicle = IsPedInAnyVehicle(ped, false)
                local fleeing = inVehicle or dist > math.max(exchangePromptDistance + 4.0, 8.0)
                if fleeing then
                    incident.fleeingSince = incident.fleeingSince or GetGameTimer()
                else
                    incident.fleeingSince = nil
                    incident.sightSeconds = math.max(0.0, incident.sightSeconds - (dt * 2.0))
                end

                if fleeing and dist < 65.0 and HasEntityClearLosToEntity(incident.npcPed, ped, 17) then
                    incident.sightSeconds = incident.sightSeconds + dt
                end

                local fleeMs = incident.fleeingSince and (GetGameTimer() - incident.fleeingSince) or 0
                local shouldReport = false
                if incident.sightSeconds >= incident.sightThreshold then
                    shouldReport = true
                elseif fleeMs >= math.floor((incident.sightThreshold or 3.5) * 1000.0) and dist > 18.0 then
                    shouldReport = true
                elseif dist > 55.0 and fleeMs >= 1500 then
                    shouldReport = true
                end

                if shouldReport then
                    incident.reported = true
                    incident.readyForExchange = false
                    local streetHash = GetStreetNameAtCoord(npcPos.x, npcPos.y, npcPos.z)
                    local location = GetStreetNameFromHashKey(streetHash)
                    TriggerServerEvent('az_insurance:reportHitAndRun', {
                        playerPlate = incident.playerPlate,
                        playerModel = incident.playerModel,
                        playerColor = incident.playerColor,
                        suspectPlate = incident.suspectPlate,
                        suspectModel = incident.suspectModel,
                        suspectColor = incident.suspectColor,
                        coords = { x = npcPos.x, y = npcPos.y, z = npcPos.z },
                        location = location,
                    })
                    notify('The other driver reported the hit and run to police.', 'bad')
                    if DoesEntityExist(incident.npcPed) then
                        FreezeEntityPosition(incident.npcPed, false)
                        ClearPedTasksImmediately(incident.npcPed)
                        TaskStartScenarioInPlace(incident.npcPed, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
                    end
                    if DoesEntityExist(incident.npcVeh) then
                        setHazards(incident.npcVeh, true)
                    end
                    incident.cleanupAt = GetGameTimer() + 8000
                end
            end

            if incident.cleanupAt and GetGameTimer() >= incident.cleanupAt then
                cleanupIncident(id, false)
            end

            ::continue::
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id, _ in pairs(incidents) do
        cleanupIncident(id, false)
    end
end)
