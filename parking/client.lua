if Config.Parking then
    local debug = true
    local parkedVehicles = {}
    print('[az-fw-parking] Parking True, Initializing.')

    local function debugPrint(msg)
        if debug then print(('[az-fw-parking] %s'):format(msg)) end
    end

    -- Gather all vehicle properties (including rims, lights, neon, tyre smoke, etc.)
    local function getVehicleProps(veh)
        local coords = GetEntityCoords(veh)
        local primary, secondary = GetVehicleColours(veh)
        local pearlescent, wheelCol = GetVehicleExtraColours(veh)
        local wheelType = GetVehicleWheelType(veh)
        local tint = GetVehicleWindowTint(veh)
        local plateIndex = GetVehicleNumberPlateTextIndex(veh)
        local livery = GetVehicleLivery(veh)
        local dirtLevel = GetVehicleDirtLevel(veh)
        local dashColor = GetVehicleDashboardColour(veh)
        local intColor = GetVehicleInteriorColour(veh)
        local smokeR, smokeG, smokeB = GetVehicleTyreSmokeColor(veh)

        -- Neon lights
        local neon = {
            enabled = {
                [0] = IsVehicleNeonLightEnabled(veh, 0) and 1 or 0,
                [1] = IsVehicleNeonLightEnabled(veh, 1) and 1 or 0,
                [2] = IsVehicleNeonLightEnabled(veh, 2) and 1 or 0,
                [3] = IsVehicleNeonLightEnabled(veh, 3) and 1 or 0,
            },
            color = { GetVehicleNeonLightsColour(veh) }
        }

        -- Mods
        local mods = {}
        for i = 0, 49 do mods[i] = GetVehicleMod(veh, i) end
        mods.modTurbo = IsToggleModOn(veh, 18) and 1 or 0
        mods.modXenon = IsToggleModOn(veh, 22) and 1 or 0

        -- Extras
        local extras = {}
        for i = 1, 12 do
            if DoesExtraExist(veh, i) then
                extras[i] = IsVehicleExtraTurnedOn(veh, i) and 1 or 0
            end
        end

        return {
            plate = GetVehicleNumberPlateText(veh) or "",
            plateIndex = plateIndex,
            model = tostring(GetEntityModel(veh) or 0),
            x = coords.x, y = coords.y, z = coords.z, h = GetEntityHeading(veh),
            color1 = primary, color2 = secondary,
            pearlescent = pearlescent, wheelColor = wheelCol, wheelType = wheelType,
            windowTint = tint,
            livery = livery,
            dirtLevel = dirtLevel,
            dashColor = dashColor, intColor = intColor,
            tyreSmoke = { r = smokeR, g = smokeG, b = smokeB },
            neon = neon,
            mods = mods,
            extras = extras,
        }
    end

    -- Handle parking/unparking keybind
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            local ped = PlayerPedId()
            if IsControlPressed(0, 21) and IsControlJustReleased(0, 23) then
                if IsPedInAnyVehicle(ped, false) then
                    local veh = GetVehiclePedIsIn(ped, false)
                    local props = getVehicleProps(veh)
                    debugPrint(('Requesting PARK for %s'):format(props.plate))
                    TriggerServerEvent('raptor:toggleParkVehicle', props)
                else
                    local px,py,pz = table.unpack(GetEntityCoords(ped))
                    local minDist, found = 5.0, nil
                    for _, entry in ipairs(parkedVehicles) do
                        if entry.handle and DoesEntityExist(entry.handle) then
                            local vx,vy,vz = table.unpack(GetEntityCoords(entry.handle))
                            local dist = #(vector3(px,py,pz) - vector3(vx,vy,vz))
                            if dist < minDist then minDist, found = dist, entry end
                        end
                    end
                    if found then
                        debugPrint(('Requesting UNPARK for %s'):format(found.plate))
                        TriggerServerEvent('raptor:toggleParkVehicle', { plate = found.plate })
                    else
                        debugPrint('No parked vehicle within 5m to unpark')
                    end
                end
            end
        end
    end)

    -- Load saved vehicles on resource start
    AddEventHandler('onClientResourceStart', function(resName)
        if GetCurrentResourceName() ~= resName then return end
        debugPrint('Resource started, loading saved vehicles')
        TriggerServerEvent('raptor:loadVehicles')
    end)

    -- Spawn and apply all props for loaded vehicles
    RegisterNetEvent('raptor:vehiclesLoaded')
    AddEventHandler('raptor:vehiclesLoaded', function(vehicles)
        debugPrint(('Loading %d vehicle(s)'):format(#vehicles))
        parkedVehicles = {}

        for i, v in ipairs(vehicles) do
            local modelHash = tonumber(v.model)
            if modelHash then
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do Citizen.Wait(0) end

                local veh = CreateVehicle(modelHash, v.x, v.y, v.z + 0.5, v.h, true, false)
                if veh and DoesEntityExist(veh) then
                    -- Apply saved appearance
                    SetVehicleNumberPlateText(veh, v.plate)
                    SetVehicleNumberPlateTextIndex(veh, v.plateIndex or 0)
                    SetVehicleColours(veh, v.color1, v.color2)
                    SetVehicleExtraColours(veh, v.pearlescent, v.wheelColor)
                    SetVehicleWindowTint(veh, v.windowTint)
                    SetVehicleWheelType(veh, v.wheelType)

                    SetVehicleLivery(veh, v.livery or 0)
                    SetVehicleDirtLevel(veh, v.dirtLevel or 0.0)
                    SetVehicleDashboardColour(veh, v.dashColor or 0)
                    SetVehicleInteriorColour(veh, v.intColor or 0)
                    if v.tyreSmoke then
                        SetVehicleTyreSmokeColor(veh, v.tyreSmoke.r, v.tyreSmoke.g, v.tyreSmoke.b)
                    end

                    if v.neon then
                        for id, state in pairs(v.neon.enabled) do
                            SetVehicleNeonLightEnabled(veh, id, state == 1)
                        end
                        local nc = v.neon.color
                        SetVehicleNeonLightsColour(veh, nc[1], nc[2], nc[3])
                    end

                    if v.mods then
                        for modType, modIndex in pairs(v.mods) do
                            if type(modType) == 'string' and modType:find('mod') then
                                if modType == 'modTurbo' then ToggleVehicleMod(veh, 18, modIndex)
                                elseif modType == 'modXenon' then ToggleVehicleMod(veh, 22, modIndex)
                                end
                            else
                                SetVehicleMod(veh, tonumber(modType), modIndex, false)
                            end
                        end
                    end
                    if v.extras then
                        for extraID, state in pairs(v.extras) do
                            SetVehicleExtra(veh, tonumber(extraID), state == 0)
                        end
                    end

                    -- Finalize
                    SetEntityCoordsNoOffset(veh, v.x, v.y, v.z, false, false, false)
                    SetEntityHeading(veh, v.h)
                    FreezeEntityPosition(veh, true)
                    PlaceObjectOnGroundProperly(veh)
                    SetVehicleOnGroundProperly(veh)
                    SetVehicleDoorsLocked(veh, 2)

                    table.insert(parkedVehicles, { handle = veh, plate = v.plate })
                    debugPrint(('Parked #%d: %s'):format(i, v.plate))
                    SetModelAsNoLongerNeeded(modelHash)
                else
                    debugPrint(('Failed to create vehicle #%d (model: %s)'):format(i, tostring(v.model)))
                end
            else
                debugPrint(('Invalid model for record #%d: %s'):format(i, tostring(v.model)))
            end
        end
    end)

    -- Toggle lock/unlock on park/unpark
    RegisterNetEvent('raptor:vehicleParkToggled')
    AddEventHandler('raptor:vehicleParkToggled', function(data)
        local plate, park = data.plate, data.park
        local ped = PlayerPedId()
        if park and IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            SetVehicleDoorsLocked(veh, 2)
            FreezeEntityPosition(veh, true)
            table.insert(parkedVehicles, { handle = veh, plate = plate })
            TriggerEvent('chat:addMessage', { args = { '^2[RAPTOR]', 'Parked & saved: ' .. plate } })
        elseif not park then
            for i, entry in ipairs(parkedVehicles) do
                if entry.plate == plate and entry.handle and DoesEntityExist(entry.handle) then
                    SetVehicleDoorsLocked(entry.handle, 1)
                    FreezeEntityPosition(entry.handle, false)
                    TriggerEvent('chat:addMessage', { args = { '^2[RAPTOR]', 'Unparked & removed: ' .. plate } })
                    table.remove(parkedVehicles, i)
                    break
                end
            end
        end
    end)
else
    print('[az-fw-parking] Parking disabled in config')
end
