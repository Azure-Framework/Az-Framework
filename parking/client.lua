if Config.Parking then
    local debug = true
    local parkedVehicles = {}

    print('[az-fw-parking] Parking True, Initializing.')

    local function debugPrint(msg)
        if debug then
            print(('[az-fw-parking] %s'):format(msg))
        end
    end

    -- =========================
    -- 3D TEXT (NO RECT)
    -- =========================
    local function DrawText3D(x, y, z, text)
        local onScreen, _x, _y = World3dToScreen2d(x, y, z)
        if not onScreen then return end

        local camCoords = GetGameplayCamCoords()
        local dist = #(vector3(x, y, z) - camCoords)

        local scaleMult = (1.0 / dist) * 2.0
        local fov = (1.0 / GetGameplayCamFov()) * 100.0
        local scale = scaleMult * fov

        SetTextFont(4)
        SetTextProportional(1)
        SetTextScale(0.0, 0.35 * scale)
        SetTextColour(255, 255, 255, 255)
        SetTextCentre(true)
        SetTextOutline()

        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandDisplayText(_x, _y)
    end

    -- Draw owner tag above the vehicle
    local function drawOwnerTagForVehicle(vehicle, ownerName)
        if not vehicle or not DoesEntityExist(vehicle) then return end
        ownerName = ownerName or 'Unknown Owner'

        local model = GetEntityModel(vehicle)
        local minDim, maxDim = GetModelDimensions(model)
        local height = (maxDim.z - minDim.z) + 0.7

        local coords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, height)
        local label = ('Owner: %s'):format(ownerName)

        DrawText3D(coords.x, coords.y, coords.z, label)
    end

    -- =========================
    -- HELPERS
    -- =========================

    -- Build a full properties table from ox_lib and attach parking coords/heading
    local function buildParkProps(veh)
        if not veh or veh == 0 then return nil end

        local props = lib.getVehicleProperties(veh) or {}
        local coords = GetEntityCoords(veh)

        props.azParking = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
            h = GetEntityHeading(veh)
        }

        -- Ensure plate/model are always present in props we send to the server
        props.plate = GetVehicleNumberPlateText(veh) or props.plate or ''
        props.model = props.model or GetEntityModel(veh)

        -- Store owner name so we can show it next time the vehicle is loaded
        props.ownerName = props.ownerName or GetPlayerName(PlayerId())

        debugPrint(('buildParkProps %s model=%s owner=%s'):format(
            tostring(props.plate),
            tostring(props.model),
            tostring(props.ownerName))
        )

        return props
    end

    -- Make sure we don't end up with multiple vehicles with the same plate nearby.
    local function cleanupNearbyPlateClones(plate, keepVeh)
        if not plate or plate == '' or not keepVeh or keepVeh == 0 then return end

        local keepCoords = GetEntityCoords(keepVeh)
        local vehicles = GetGamePool('CVehicle')

        for _, veh in ipairs(vehicles) do
            if veh ~= keepVeh and DoesEntityExist(veh) then
                if GetVehicleNumberPlateText(veh) == plate then
                    local coords = GetEntityCoords(veh)
                    local dist = #(coords - keepCoords)
                    if dist < 10.0 then
                        debugPrint(('Deleting clone for plate %s within %.2fm'):format(plate, dist))
                        SetEntityAsMissionEntity(veh, true, true)
                        DeleteVehicle(veh)
                    end
                end
            end
        end
    end

    -- =========================
    -- PARK / UNPARK KEYBIND
    -- =========================

    -- Handle parking/unparking keybind (SHIFT + F: 21 + 23)
    CreateThread(function()
        while true do
            Wait(0)
            local ped = PlayerPedId()

            if IsControlPressed(0, 21) and IsControlJustReleased(0, 23) then
                if IsPedInAnyVehicle(ped, false) then
                    -- PARK the current vehicle
                    local veh = GetVehiclePedIsIn(ped, false)
                    local props = buildParkProps(veh)
                    if props and props.plate ~= '' then
                        debugPrint(('Requesting PARK for %s'):format(props.plate))
                        TriggerServerEvent('raptor:toggleParkVehicle', props)
                    else
                        debugPrint('Failed to build vehicle props for parking')
                    end
                else
                    -- UNPARK nearest parked vehicle within 5m
                    local px, py, pz = table.unpack(GetEntityCoords(ped))
                    local minDist, found = 5.0, nil

                    for _, entry in ipairs(parkedVehicles) do
                        if entry.handle and DoesEntityExist(entry.handle) then
                            local vx, vy, vz = table.unpack(GetEntityCoords(entry.handle))
                            local dist = #(vector3(px, py, pz) - vector3(vx, vy, vz))
                            if dist < minDist then
                                minDist, found = dist, entry
                            end
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

    -- =========================
    -- LOAD PARKED VEHICLES
    -- =========================

    -- Load saved vehicles on resource start
    AddEventHandler('onClientResourceStart', function(resName)
        if GetCurrentResourceName() ~= resName then return end
        debugPrint('Resource started, loading saved vehicles')
        TriggerServerEvent('raptor:loadVehicles')
    end)

    -- Spawn and apply ALL properties for loaded vehicles
    RegisterNetEvent('raptor:vehiclesLoaded')
    AddEventHandler('raptor:vehiclesLoaded', function(vehicles)
        debugPrint(('Loading %d vehicle(s) from DB'):format(#vehicles))
        parkedVehicles = {}

        for i, v in ipairs(vehicles) do
            local props = v.props or {}
            if next(props) == nil then
                debugPrint(('Skipping #%d: empty props (plate=%s)'):format(i, tostring(v.plate)))
                goto continue
            end

            local stored = props.azParking or {}
            local px = stored.x or v.x or 0.0
            local py = stored.y or v.y or 0.0
            local pz = stored.z or v.z or 0.0
            local ph = stored.h or v.h or 0.0

            local modelHash = props.model or tonumber(v.model)
            if not modelHash then
                debugPrint(('Invalid model for record #%d (plate=%s, model=%s)'):format(
                    i, tostring(v.plate), tostring(v.model)))
                goto continue
            end

            modelHash = tonumber(modelHash)

            RequestModel(modelHash)
            while not HasModelLoaded(modelHash) do
                Wait(0)
            end

            local veh = CreateVehicle(modelHash, px, py, pz + 0.5, ph, true, false)
            if veh and DoesEntityExist(veh) then
                -- Apply ALL customization using ox_lib
                local ok = lib.setVehicleProperties(veh, props)
                debugPrint(('setVehicleProperties for %s -> %s'):format(
                    tostring(v.plate),
                    ok and 'success' or 'failed (not owner?)')
                )

                -- Final positioning / lock / freeze
                SetEntityCoordsNoOffset(veh, px, py, pz, false, false, false)
                SetEntityHeading(veh, ph)
                FreezeEntityPosition(veh, true)
                SetVehicleOnGroundProperly(veh)
                SetVehicleDoorsLocked(veh, 2)

                table.insert(parkedVehicles, {
                    handle    = veh,
                    plate     = v.plate or props.plate or '',
                    ownerName = props.ownerName or 'Unknown Owner'
                })

                debugPrint(('Parked #%d: %s owner=%s'):format(
                    i,
                    v.plate or props.plate or 'UNKNOWN',
                    tostring(props.ownerName))
                )

                SetModelAsNoLongerNeeded(modelHash)
            else
                debugPrint(('Failed to create vehicle #%d (model=%s, plate=%s)'):format(
                    i, tostring(v.model), tostring(v.plate)))
            end

            ::continue::
        end
    end)

    -- =========================
    -- PARK/UNPARK RESULT HANDLER
    -- =========================

    RegisterNetEvent('raptor:vehicleParkToggled')
    AddEventHandler('raptor:vehicleParkToggled', function(data)
        local plate = data.plate
        local park  = data.park
        local ped   = PlayerPedId()

        if park and IsPedInAnyVehicle(ped, false) then
            -- Just parked THIS vehicle
            local veh = GetVehiclePedIsIn(ped, false)
            SetVehicleDoorsLocked(veh, 2)
            FreezeEntityPosition(veh, true)

            table.insert(parkedVehicles, {
                handle    = veh,
                plate     = plate,
                ownerName = GetPlayerName(PlayerId())
            })

            TriggerEvent('chat:addMessage', {
                args = { '^2[RAPTOR]', 'Parked & saved: ' .. plate }
            })

            debugPrint('vehicleParkToggled -> PARK for ' .. plate)
        elseif not park then
            -- Just unparked: unlock + unfreeze and ensure no clones
            for i, entry in ipairs(parkedVehicles) do
                if entry.plate == plate and entry.handle and DoesEntityExist(entry.handle) then
                    SetVehicleDoorsLocked(entry.handle, 1)
                    FreezeEntityPosition(entry.handle, false)

                    -- make sure we don't have a second locked clone with same plate
                    cleanupNearbyPlateClones(plate, entry.handle)

                    TriggerEvent('chat:addMessage', {
                        args = { '^2[RAPTOR]', 'Unparked: ' .. plate }
                    })

                    debugPrint('vehicleParkToggled -> UNPARK for ' .. plate)
                    table.remove(parkedVehicles, i)
                    break
                end
            end
        end
    end)

    -- =========================
    -- OWNER TAG DRAW LOOP
    -- =========================
    CreateThread(function()
        while true do
            Wait(0)
            for _, entry in ipairs(parkedVehicles) do
                if entry.handle and DoesEntityExist(entry.handle) then
                    drawOwnerTagForVehicle(entry.handle, entry.ownerName)
                end
            end
        end
    end)

else
    print('[az-fw-parking] Parking disabled in config')
end
