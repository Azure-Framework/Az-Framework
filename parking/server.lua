if Config.Parking then
    local RESOURCE_NAME = GetCurrentResourceName()
    local debug = true

    print(('[%s] Parking True, Initializing.'):format(RESOURCE_NAME))

    local function debugPrint(msg)
        if debug then
            print(('[%s] %s'):format(RESOURCE_NAME, msg))
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

    ---------------------------------------------------------------------
    -- 🌍 Parked world vehicle tracking (netId registry)
    -- We ONLY delete vehicles that were spawned as "parked copies".
    -- Another resource can delete DB row -> we then delete the parked copy.
    ---------------------------------------------------------------------
    local parkedWorldByNet = {} -- [netId] = { discordid=string, plate=string, added=os.time() }
    local parkedWorldByKey = {} -- [discordid.."::"..plate] = { [netId]=true, ... }

    local function makeKey(discordid, plate)
        return tostring(discordid or '') .. "::" .. tostring(plate or '')
    end

    local function addParkedWorld(netId, discordid, plate)
        netId = tonumber(netId)
        if not netId or netId <= 0 then return end
        if not discordid or discordid == '' then return end
        if not plate or plate == '' then return end

        plate = tostring(plate)
        local key = makeKey(discordid, plate)

        parkedWorldByNet[netId] = { discordid = discordid, plate = plate, added = os.time() }
        parkedWorldByKey[key] = parkedWorldByKey[key] or {}
        parkedWorldByKey[key][netId] = true

        debugPrint(("Registered parked-world vehicle netId=%s key=%s"):format(netId, key))
    end

    local function removeParkedWorld(netId)
        netId = tonumber(netId)
        if not netId or netId <= 0 then return end

        local info = parkedWorldByNet[netId]
        if info then
            local key = makeKey(info.discordid, info.plate)
            if parkedWorldByKey[key] then
                parkedWorldByKey[key][netId] = nil
                if next(parkedWorldByKey[key]) == nil then
                    parkedWorldByKey[key] = nil
                end
            end
        end

        parkedWorldByNet[netId] = nil
    end

    -- Client registers a spawned parked vehicle so we can clean it up if DB row disappears
    RegisterNetEvent('raptor:registerParkedWorldVehicle', function(netId, plate)
        local src = source
        local discordID = getDiscordID(src)
        if not discordID then
            debugPrint(("Denied registerParkedWorldVehicle from %d (no discord)"):format(src))
            return
        end
        netId = tonumber(netId)
        plate = tostring(plate or '')
        if not netId or netId <= 0 or plate == '' then
            debugPrint(("Denied registerParkedWorldVehicle from %d (bad netId/plate)"):format(src))
            return
        end

        addParkedWorld(netId, discordID, plate)
    end)

    RegisterNetEvent('raptor:unregisterParkedWorldVehicle', function(netId)
        local src = source
        netId = tonumber(netId)
        if not netId or netId <= 0 then return end
        debugPrint(("Unregister parked-world vehicle netId=%s by %d"):format(netId, src))
        removeParkedWorld(netId)
    end)

    -- Optional server export so OTHER scripts can register parked vehicles too
    exports('RegisterParkedWorldVehicle', function(discordID, netId, plate)
        addParkedWorld(netId, discordID, plate)
    end)

    exports('UnregisterParkedWorldVehicle', function(netId)
        removeParkedWorld(netId)
    end)

    ---------------------------------------------------------------------
    -- 🔁 Every 5 seconds: delete parked-world vehicles whose DB row is gone
    ---------------------------------------------------------------------
    CreateThread(function()
        while true do
            Wait(5000)

            if next(parkedWorldByNet) == nil then
                goto continue
            end

            -- Build a set of all currently PARKED vehicles still present in DB
            MySQL.Async.fetchAll([[
                SELECT discordid, plate
                FROM user_vehicles
            ]], {}, function(rows)
                local dbSet = {}
                for _, r in ipairs(rows or {}) do
                    local did = tostring(r.discordid or '')
                    local plt = tostring(r.plate or '')
                    if did ~= '' and plt ~= '' then
                        dbSet[makeKey(did, plt)] = true
                    end
                end

                local checked, deleted = 0, 0

                for netId, info in pairs(parkedWorldByNet) do
                    checked = checked + 1
                    local key = makeKey(info.discordid, info.plate)

                    -- If row no longer exists, it is "unparked" -> delete parked-world copy
                    if not dbSet[key] then
                        debugPrint(("DB missing -> deleting parked-world copy netId=%s key=%s"):format(netId, key))

                        -- Tell ALL clients to delete this network entity (whoever has control will delete)
                        TriggerClientEvent('raptor:deleteNetVehicle', -1, netId)

                        -- Remove from registry so we stop trying
                        removeParkedWorld(netId)
                        deleted = deleted + 1
                    end
                end

                if deleted > 0 then
                    debugPrint(("Cleanup tick: checked=%d deleted=%d"):format(checked, deleted))
                end
            end)

            ::continue::
        end
    end)

    ---------------------------------------------------------------------
    -- 🔁 Shared DB helper – used by both events AND exports
    ---------------------------------------------------------------------
    local function fetchVehiclesForDiscord(discordID, cb)
        if not discordID or discordID == '' then
            if cb then
                local ok, err = pcall(cb, {})
                if not ok then
                    debugPrint(('fetchVehiclesForDiscord cb error (empty set): %s'):format(tostring(err)))
                end
            end
            return
        end

        MySQL.Async.fetchAll([[
            SELECT discordid, plate, model, x, y, z, h,
                   color1, color2, pearlescent, wheelColor, wheelType, windowTint,
                   mods, extras
            FROM user_vehicles
            WHERE discordid=@discordid
        ]], {
            ['@discordid'] = discordID
        }, function(results)
            for _, v in ipairs(results or {}) do
                v.props  = json.decode(v.mods   or '{}') or {}
                v.extras = json.decode(v.extras or '{}') or {}

                if not v.props.ownerName or v.props.ownerName == '' then
                    v.props.ownerName = ('Discord %s'):format(v.discordid or '?')
                end
            end

            if cb then
                local ok, err = pcall(cb, results or {})
                if not ok then
                    debugPrint(('fetchVehiclesForDiscord cb error: %s'):format(tostring(err)))
                end
            end
        end)
    end

    ---------------------------------------------------------------------
    -- 🚗 Toggle Park / Unpark
    ---------------------------------------------------------------------
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
            if #rows == 0 then
                -- PARK -> INSERT / UPDATE
                local azParking = props.azParking or {}
                local px, py, pz, ph = azParking.x or 0.0, azParking.y or 0.0, azParking.z or 0.0, azParking.h or 0.0

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
                -- UNPARK -> DELETE
                debugPrint(('UNPARK -> DELETE %s for %s'):format(plate, discordID))
                MySQL.Async.execute([[
                    DELETE FROM user_vehicles WHERE discordid=@discordid AND plate=@plate
                ]], {
                    ['@discordid'] = discordID,
                    ['@plate']     = plate
                }, function()
                    TriggerClientEvent('raptor:vehicleParkToggled', src, { plate = plate, park = false })

                    -- Immediately nuke any parked-world copies we already know about for this key
                    local key = makeKey(discordID, plate)
                    local bucket = parkedWorldByKey[key]
                    if bucket then
                        for netId, _ in pairs(bucket) do
                            debugPrint(("UNPARK immediate -> deleting parked-world copy netId=%s key=%s"):format(netId, key))
                            TriggerClientEvent('raptor:deleteNetVehicle', -1, tonumber(netId))
                            removeParkedWorld(tonumber(netId))
                        end
                    end
                end)
            end
        end)
    end)

    ---------------------------------------------------------------------
    -- 🚚 Load parked vehicles (existing event)
    ---------------------------------------------------------------------
    RegisterNetEvent('raptor:loadVehicles')
    AddEventHandler('raptor:loadVehicles', function()
        local src = source
        local discordID = getDiscordID(src)
        if not discordID then
            debugPrint(('Denied loadVehicles from %d (no discordid)'):format(src))
            return
        end

        debugPrint(('Loading vehicles for %s'):format(discordID))

        fetchVehiclesForDiscord(discordID, function(results)
            TriggerClientEvent('raptor:vehiclesLoaded', src, results)
        end)
    end)

    ---------------------------------------------------------------------
    -- 📦 EXPORTS for Az-Insurance & other Az-Framework modules
    ---------------------------------------------------------------------
    local function dbgCaller(prefix, ...)
        local inv = GetInvokingResource() or "UNKNOWN"
        local argStrs = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            argStrs[#argStrs+1] = ("[%d]=%s(%s)"):format(i, tostring(v), type(v))
        end
        debugPrint(("%s from %s | args: %s"):format(prefix, inv, table.concat(argStrs, ", ")))
    end

    exports('GetParkingDiscordId', function(src)
        if type(src) ~= 'number' or src <= 0 then return nil end
        return getDiscordID(src)
    end)

    exports('GetPlayerParkedVehicles', function(discordID, cb)
        dbgCaller('GetPlayerParkedVehicles', discordID, cb)
        fetchVehiclesForDiscord(discordID, function(results)
            if cb then
                local ok, err = pcall(cb, results or {})
                if not ok then
                    debugPrint(('GetPlayerParkedVehicles cb error: %s'):format(tostring(err)))
                end
            end
        end)
    end)

    exports('GetParkedVehicleByPlate', function(discordID, plate, cb)
        dbgCaller('GetParkedVehicleByPlate', discordID, plate, cb)

        if not discordID or discordID == '' or not plate or plate == '' then
            if cb then
                local ok, err = pcall(cb, nil)
                if not ok then
                    debugPrint(('GetParkedVehicleByPlate cb error (nil early): %s'):format(tostring(err)))
                end
            end
            return
        end

        fetchVehiclesForDiscord(discordID, function(results)
            local found
            for _, v in ipairs(results or {}) do
                if v.plate == plate then
                    found = v
                    break
                end
            end

            if cb then
                local ok, err = pcall(cb, found)
                if not ok then
                    debugPrint(('GetParkedVehicleByPlate cb error: %s'):format(tostring(err)))
                end
            end
        end)
    end)

    exports('IsVehicleParked', function(discordID, plate, cb)
        dbgCaller('IsVehicleParked', discordID, plate, cb)

        if not discordID or discordID == '' or not plate or plate == '' then
            if cb then
                local ok, err = pcall(cb, false)
                if not ok then
                    debugPrint(('IsVehicleParked cb error (false early): %s'):format(tostring(err)))
                end
            end
            return
        end

        fetchVehiclesForDiscord(discordID, function(results)
            local parked = false
            for _, v in ipairs(results or {}) do
                if v.plate == plate then
                    parked = true
                    break
                end
            end

            if cb then
                local ok, err = pcall(cb, parked)
                if not ok then
                    debugPrint(('IsVehicleParked cb error: %s'):format(tostring(err)))
                end
            end
        end)
    end)

else
    print('[Az-Parking] Parking disabled in config')
end
