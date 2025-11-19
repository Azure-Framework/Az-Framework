if Config.Parking then
    local debug = true
    print('[Az-Parking] Parking True, Initializing.')

    local function debugPrint(msg)
        if debug then
            print(('[Az-Parking] %s'):format(msg))
        end
    end

    local function getDiscordID(src)
        for _, id in ipairs(GetPlayerIdentifiers(src)) do
            if id:sub(1, 8) == 'discord:' then
                return id:sub(9)
            end
        end
        return nil
    end

    -- helper to safely turn number[] into a single number for old columns
    local function scalarOrFirst(v)
        if type(v) == 'table' then
            return v[1] or 0
        end
        return v or 0
    end

    RegisterNetEvent('raptor:toggleParkVehicle')
    AddEventHandler('raptor:toggleParkVehicle', function(props)
        local src = source
        if type(props) ~= 'table' then
            debugPrint(('Denied toggleParkVehicle from %d (props not table)'):format(src))
            return
        end

        local plate = props.plate
        if not plate or plate == '' then
            debugPrint(('Denied toggleParkVehicle from %d (no plate)'):format(src))
            return
        end

        local discordID = getDiscordID(src)
        if not discordID then
            debugPrint(('Denied toggleParkVehicle from %d (no discordid)'):format(src))
            return
        end

        debugPrint(('toggleParkVehicle for %d: %s'):format(src, plate))

        MySQL.Async.fetchAll([[
            SELECT 1 FROM user_vehicles WHERE discordid=@discordid AND plate=@plate
        ]], {
            ['@discordid'] = discordID,
            ['@plate']     = plate
        }, function(rows)
            -- FIRST TIME PARKING: INSERT / UPDATE WITH FULL PROPS JSON
            if #rows == 0 then
                local azParking = props.azParking or {}
                local px, py, pz, ph = azParking.x or 0.0, azParking.y or 0.0, azParking.z or 0.0, azParking.h or 0.0

                -- For backwards compat, still populate the old columns with scalar values,
                -- but the REAL source of truth is the JSON in @mods.
                local color1 = scalarOrFirst(props.color1)
                local color2 = scalarOrFirst(props.color2)
                local pearlescent = props.pearlescentColor or props.pearlescent or 0
                local wheelColor = props.wheelColor or 0
                local wheelType = props.wheels or 0
                local windowTint = props.windowTint or 0
                local extras = props.extras or {}
                local propsJson = json.encode(props or {})

                debugPrint(('PARK -> INSERT %s for %s (model=%s)'):format(
                    plate, discordID, tostring(props.model))
                )

                MySQL.Async.execute([[
                    INSERT INTO user_vehicles
                        (discordid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras)
                    VALUES
                        (@discordid,@plate,@model,@x,@y,@z,@h,@color1,@color2,@pearlescent,@wheelColor,@wheelType,@windowTint,@mods,@extras)
                    ON DUPLICATE KEY UPDATE
                        model=@model,
                        x=@x, y=@y, z=@z, h=@h,
                        color1=@color1, color2=@color2,
                        pearlescent=@pearlescent,
                        wheelColor=@wheelColor,
                        wheelType=@wheelType,
                        windowTint=@windowTint,
                        mods=@mods,
                        extras=@extras
                ]], {
                    ['@discordid']   = discordID,
                    ['@plate']       = plate,
                    ['@model']       = tostring(props.model or 0),
                    ['@x']           = px,
                    ['@y']           = py,
                    ['@z']           = pz,
                    ['@h']           = ph,
                    ['@color1']      = color1,
                    ['@color2']      = color2,
                    ['@pearlescent'] = pearlescent,
                    ['@wheelColor']  = wheelColor,
                    ['@wheelType']   = wheelType,
                    ['@windowTint']  = windowTint,
                    ['@mods']        = propsJson,
                    ['@extras']      = json.encode(extras or {})
                }, function()
                    TriggerClientEvent('raptor:vehicleParkToggled', src, { plate = plate, park = true })
                end)
            else
                -- ALREADY PARKED: UNPARK (DELETE)
                debugPrint(('UNPARK -> DELETE %s for %s'):format(plate, discordID))
                MySQL.Async.execute([[
                    DELETE FROM user_vehicles WHERE discordid=@discordid AND plate=@plate
                ]], {
                    ['@discordid'] = discordID,
                    ['@plate']     = plate
                }, function()
                    TriggerClientEvent('raptor:vehicleParkToggled', src, { plate = plate, park = false })
                end)
            end
        end)
    end)

RegisterNetEvent('raptor:loadVehicles')
AddEventHandler('raptor:loadVehicles', function()
    local src = source
    local discordID = getDiscordID(src)
    if not discordID then
        debugPrint(('Denied loadVehicles from %d (no discordid)'):format(src))
        return
    end

    debugPrint(('Loading vehicles for %s'):format(discordID))

    MySQL.Async.fetchAll([[
        SELECT discordid, plate, model, x, y, z, h,
               color1, color2, pearlescent, wheelColor, wheelType, windowTint,
               mods, extras
        FROM user_vehicles
        WHERE discordid=@discordid
    ]], {
        ['@discordid'] = discordID
    }, function(results)
        for _, v in ipairs(results) do
            v.props  = json.decode(v.mods   or '{}') or {}
            v.extras = json.decode(v.extras or '{}') or {}

            -- Fallback for OLD rows that didn’t have ownerName stored
            if not v.props.ownerName or v.props.ownerName == '' then
                v.props.ownerName = ('Discord %s'):format(v.discordid or '?')
            end
        end

        TriggerClientEvent('raptor:vehiclesLoaded', src, results)
    end)
end)

else
    print('[Az-Parking] Parking disabled in config')
end
