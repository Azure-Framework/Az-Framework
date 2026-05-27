if Config.Parking then
    local RESOURCE_NAME = GetCurrentResourceName()
    local EVENT_PREFIX = 'az-parking'
    local LEGACY_EVENT_PREFIX = 'raptor'
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

local function getCharacterNameSyncForSource(src)
    local state = GetResourceState('Az-Framework')
    if state == 'started' or state == 'starting' then
        local fw = exports['Az-Framework']
        if fw and fw.GetPlayerCharacterNameSync then
            local ok, name = pcall(function() return fw:GetPlayerCharacterNameSync(src) end)
            if ok and name ~= nil and tostring(name) ~= '' then
                return tostring(name)
            end
        end
    end
    return nil
end

local function fetchCharacterNameByIds(discordId, charId, cb)
    if not discordId or discordId == '' or not charId or charId == '' then
        if cb then cb(nil) end
        return
    end

    MySQL.Async.fetchScalar([[SELECT name FROM user_characters WHERE discordid=@discordid AND charid=@charid LIMIT 1]], {
        ['@discordid'] = tostring(discordId),
        ['@charid'] = tostring(charId),
    }, function(name)
        if cb then cb(name and tostring(name) or nil) end
    end)
end

    local function getActiveCharId(src)
        local state = GetResourceState('Az-Framework')
        if state == 'started' or state == 'starting' then
            local fw = exports['Az-Framework']
            if fw and fw.GetPlayerCharacter then
                local ok, cid = pcall(function() return fw:GetPlayerCharacter(src) end)
                if ok and cid ~= nil and tostring(cid) ~= '' then
                    return tostring(cid)
                end
            end
        end
        return nil
    end

    local vehicleTableHasCharId = false

    local function ensureVehicleSchema(cb)
        MySQL.Async.fetchAll("SHOW COLUMNS FROM user_vehicles LIKE 'charid'", {}, function(rows)
            vehicleTableHasCharId = rows and rows[1] ~= nil or false
            if not vehicleTableHasCharId then
                MySQL.Async.execute("ALTER TABLE user_vehicles ADD COLUMN charid VARCHAR(64) NULL DEFAULT NULL AFTER discordid", {}, function()
                    MySQL.Async.execute("ALTER TABLE user_vehicles ADD KEY idx_user_vehicles_discordid_charid (discordid, charid)", {}, function()
                        MySQL.Async.fetchAll("SHOW COLUMNS FROM user_vehicles LIKE 'charid'", {}, function(rows2)
                            vehicleTableHasCharId = rows2 and rows2[1] ~= nil or false
                            if cb then cb() end
                        end)
                    end)
                end)
            else
                if cb then cb() end
            end
        end)
    end

    local function adoptLegacyVehicles(discordID, charId, cb)
        if not vehicleTableHasCharId or not discordID or discordID == '' or not charId or charId == '' then
            if cb then cb() end
            return
        end

        MySQL.Async.execute([[
            UPDATE user_vehicles
            SET charid = @charid
            WHERE discordid = @discordid AND (charid IS NULL OR charid = '')
        ]], { ['@discordid'] = discordID, ['@charid'] = charId }, function()
            if cb then cb() end
        end)
    end

    local function scalarOrFirst(v)
        if type(v) == 'table' then
            return v[1] or 0
        end
        return v or 0
    end

    local parkedWorldByNet = {}
    local parkedWorldByKey = {}

    local function makeKey(discordid, charid, plate)
        return tostring(discordid or '') .. "::" .. tostring(charid or '') .. "::" .. tostring(plate or '')
    end

    local function addParkedWorld(netId, discordid, charid, plate)
        netId = tonumber(netId)
        if not netId or netId <= 0 then return end
        if not discordid or discordid == '' then return end
        if not plate or plate == '' then return end

        plate = tostring(plate)
        local key = makeKey(discordid, charid, plate)

        parkedWorldByNet[netId] = { discordid = discordid, charid = charid, plate = plate, added = os.time() }
        parkedWorldByKey[key] = parkedWorldByKey[key] or {}
        parkedWorldByKey[key][netId] = true

        debugPrint(("Registered parked-world vehicle netId=%s key=%s"):format(netId, key))
    end

    local function removeParkedWorld(netId)
        netId = tonumber(netId)
        if not netId or netId <= 0 then return end

        local info = parkedWorldByNet[netId]
        if info then
            local key = makeKey(info.discordid, info.charid, info.plate)
            if parkedWorldByKey[key] then
                parkedWorldByKey[key][netId] = nil
                if next(parkedWorldByKey[key]) == nil then
                    parkedWorldByKey[key] = nil
                end
            end
        end

        parkedWorldByNet[netId] = nil
    end

    local function handleRegisterParkedWorldVehicle(src, netId, plate)
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

        local charId = getActiveCharId(src)
        addParkedWorld(netId, discordID, charId, plate)
    end

    RegisterNetEvent(EVENT_PREFIX .. ':registerParkedWorldVehicle')
    AddEventHandler(EVENT_PREFIX .. ':registerParkedWorldVehicle', function(netId, plate)
        handleRegisterParkedWorldVehicle(source, netId, plate)
    end)

    RegisterNetEvent(LEGACY_EVENT_PREFIX .. ':registerParkedWorldVehicle')
    AddEventHandler(LEGACY_EVENT_PREFIX .. ':registerParkedWorldVehicle', function(netId, plate)
        handleRegisterParkedWorldVehicle(source, netId, plate)
    end)

    local function handleUnregisterParkedWorldVehicle(src, netId)
        netId = tonumber(netId)
        if not netId or netId <= 0 then return end
        debugPrint(("Unregister parked-world vehicle netId=%s by %d"):format(netId, src))
        removeParkedWorld(netId)
    end

    RegisterNetEvent(EVENT_PREFIX .. ':unregisterParkedWorldVehicle')
    AddEventHandler(EVENT_PREFIX .. ':unregisterParkedWorldVehicle', function(netId)
        handleUnregisterParkedWorldVehicle(source, netId)
    end)

    RegisterNetEvent(LEGACY_EVENT_PREFIX .. ':unregisterParkedWorldVehicle')
    AddEventHandler(LEGACY_EVENT_PREFIX .. ':unregisterParkedWorldVehicle', function(netId)
        handleUnregisterParkedWorldVehicle(source, netId)
    end)

    exports('RegisterParkedWorldVehicle', function(discordID, netId, plate, charId)
        addParkedWorld(netId, discordID, charId, plate)
    end)

    exports('UnregisterParkedWorldVehicle', function(netId)
        removeParkedWorld(netId)
    end)

    CreateThread(function()
        while true do
            Wait(5000)

            if next(parkedWorldByNet) == nil then
                goto continue
            end

            MySQL.Async.fetchAll([[
                SELECT discordid, charid, plate
                FROM user_vehicles
            ]], {}, function(rows)
                local dbSet = {}
                for _, r in ipairs(rows or {}) do
                    local did = tostring(r.discordid or '')
                    local plt = tostring(r.plate or '')
                    if did ~= '' and plt ~= '' then
                        dbSet[makeKey(did, tostring(r.charid or ''), plt)] = true
                    end
                end

                local checked, deleted = 0, 0

                for netId, info in pairs(parkedWorldByNet) do
                    checked = checked + 1
                    local key = makeKey(info.discordid, info.charid, info.plate)

                    if not dbSet[key] then
                        debugPrint(("DB missing -> deleting parked-world copy netId=%s key=%s"):format(netId, key))

                        TriggerClientEvent(EVENT_PREFIX .. ':deleteNetVehicle', -1, netId)

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

local function fetchVehiclesForDiscord(discordID, charId, cb)
    if type(charId) == 'function' and cb == nil then
        cb = charId
        charId = nil
    end

    if not discordID or discordID == '' then
        if cb then
            local ok, err = pcall(cb, {})
            if not ok then
                debugPrint(('fetchVehiclesForDiscord cb error (empty set): %s'):format(tostring(err)))
            end
        end
        return
    end

    local function runQuery()
        local query, params
        if vehicleTableHasCharId and charId and charId ~= '' then
            query = [[
                SELECT discordid, charid, plate, model, x, y, z, h,
                       color1, color2, pearlescent, wheelColor, wheelType, windowTint,
                       mods, extras
                FROM user_vehicles
                WHERE discordid=@discordid AND charid=@charid
            ]]
            params = { ['@discordid'] = discordID, ['@charid'] = charId }
        else
            query = [[
                SELECT discordid, charid, plate, model, x, y, z, h,
                       color1, color2, pearlescent, wheelColor, wheelType, windowTint,
                       mods, extras
                FROM user_vehicles
                WHERE discordid=@discordid
            ]]
            params = { ['@discordid'] = discordID }
        end

        MySQL.Async.fetchAll(query, params, function(results)
            local function finish(ownerName)
                for _, v in ipairs(results or {}) do
                    v.props  = json.decode(v.mods or '{}') or {}
                    v.extras = json.decode(v.extras or '{}') or {}

                    if not v.props.ownerName or v.props.ownerName == '' then
                        v.props.ownerName = ownerName or ('Discord %s'):format(v.discordid or '?')
                    end
                end

                if cb then
                    local ok, err = pcall(cb, results or {})
                    if not ok then
                        debugPrint(('fetchVehiclesForDiscord cb error: %s'):format(tostring(err)))
                    end
                end
            end

            if charId and charId ~= '' then
                fetchCharacterNameByIds(discordID, charId, finish)
            else
                finish(nil)
            end
        end)
    end

    ensureVehicleSchema(function()
        adoptLegacyVehicles(discordID, charId, runQuery)
    end)
end

    local function handleToggleParkVehicle(src, props)
        if type(props) ~= 'table' then
            debugPrint(("Denied toggleParkVehicle from %d (props not table)"):format(src))
            return
        end

        local plate = props.plate
        if not plate or plate == '' then
            debugPrint(("Denied toggleParkVehicle from %d (no plate)"):format(src))
            return
        end

        local discordID = getDiscordID(src)
        if not discordID then
            debugPrint(("Denied toggleParkVehicle from %d (no discordid)"):format(src))
            return
        end

        local charId = getActiveCharId(src)
        debugPrint(("toggleParkVehicle for %d: %s (char=%s)"):format(src, plate, tostring(charId)))

        ensureVehicleSchema(function()
            adoptLegacyVehicles(discordID, charId, function()
                local query = vehicleTableHasCharId and charId and [[SELECT 1 FROM user_vehicles WHERE discordid=@discordid AND charid=@charid AND plate=@plate]] or [[SELECT 1 FROM user_vehicles WHERE discordid=@discordid AND plate=@plate]]
                local params = vehicleTableHasCharId and charId and { ['@discordid'] = discordID, ['@charid'] = charId, ['@plate'] = plate } or { ['@discordid'] = discordID, ['@plate'] = plate }
                MySQL.Async.fetchAll(query, params, function(rows)
                    if #rows == 0 then

                        local azParking = props.azParking or {}
                        props.ownerName = getCharacterNameSyncForSource(src) or props.ownerName or ('Discord %s'):format(discordID)
                        local px, py, pz, ph = azParking.x or 0.0, azParking.y or 0.0, azParking.z or 0.0, azParking.h or 0.0

                        local color1 = scalarOrFirst(props.color1)
                        local color2 = scalarOrFirst(props.color2)
                        local pearlescent = props.pearlescentColor or props.pearlescent or 0
                        local wheelColor = props.wheelColor or 0
                        local wheelType = props.wheels or 0
                        local windowTint = props.windowTint or 0
                        local extras = props.extras or {}
                        local propsJson = json.encode(props or {})

                        debugPrint(("PARK -> INSERT %s for %s (model=%s)"):format(
                            plate, discordID, tostring(props.model))
                        )

                        local insertQuery = vehicleTableHasCharId and charId and [[
                            INSERT INTO user_vehicles
                                (discordid, charid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras)
                            VALUES
                                (@discordid,@charid,@plate,@model,@x,@y,@z,@h,@color1,@color2,@pearlescent,@wheelColor,@wheelType,@windowTint,@mods,@extras)
                            ON DUPLICATE KEY UPDATE
                                charid=@charid,
                                model=@model,
                                x=@x, y=@y, z=@z, h=@h,
                                color1=@color1, color2=@color2,
                                pearlescent=@pearlescent,
                                wheelColor=@wheelColor,
                                wheelType=@wheelType,
                                windowTint=@windowTint,
                                mods=@mods,
                                extras=@extras
                        ]] or [[
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
                        ]]

                        MySQL.Async.execute(insertQuery, {
                            ['@discordid']   = discordID,
                            ['@charid']      = charId,
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
                            TriggerClientEvent(EVENT_PREFIX .. ':vehicleParkToggled', src, { plate = plate, park = true, ownerName = props.ownerName })
                        end)
                    else

                        debugPrint(("UNPARK -> DELETE %s for %s"):format(plate, discordID))
                        local deleteQuery = vehicleTableHasCharId and charId and [[DELETE FROM user_vehicles WHERE discordid=@discordid AND charid=@charid AND plate=@plate]] or [[DELETE FROM user_vehicles WHERE discordid=@discordid AND plate=@plate]]
                        MySQL.Async.execute(deleteQuery, {
                            ['@discordid'] = discordID,
                            ['@charid']    = charId,
                            ['@plate']     = plate
                        }, function()
                            TriggerClientEvent(EVENT_PREFIX .. ':vehicleParkToggled', src, { plate = plate, park = false })

                            local key = makeKey(discordID, charId, plate)
                            local bucket = parkedWorldByKey[key]
                            if bucket then
                                for netId, _ in pairs(bucket) do
                                    debugPrint(("UNPARK immediate -> deleting parked-world copy netId=%s key=%s"):format(netId, key))
                                    TriggerClientEvent(EVENT_PREFIX .. ':deleteNetVehicle', -1, tonumber(netId))
                                    removeParkedWorld(tonumber(netId))
                                end
                            end
                        end)
                    end
                end)
            end)
        end)
    end

    RegisterNetEvent(EVENT_PREFIX .. ':toggleParkVehicle')
    AddEventHandler(EVENT_PREFIX .. ':toggleParkVehicle', function(props)
        handleToggleParkVehicle(source, props)
    end)

    RegisterNetEvent(LEGACY_EVENT_PREFIX .. ':toggleParkVehicle')
    AddEventHandler(LEGACY_EVENT_PREFIX .. ':toggleParkVehicle', function(props)
        handleToggleParkVehicle(source, props)
    end)

    local function handleLoadVehicles(src)
        local discordID = getDiscordID(src)
        if not discordID then
            debugPrint(("Denied loadVehicles from %d (no discordid)"):format(src))
            return
        end

        local charId = getActiveCharId(src)
        debugPrint(("Loading vehicles for %s char=%s"):format(discordID, tostring(charId)))

        fetchVehiclesForDiscord(discordID, charId, function(results)
            TriggerClientEvent(EVENT_PREFIX .. ':vehiclesLoaded', src, results)
        end)
    end

    RegisterNetEvent(EVENT_PREFIX .. ':loadVehicles')
    AddEventHandler(EVENT_PREFIX .. ':loadVehicles', function()
        handleLoadVehicles(source)
    end)

    RegisterNetEvent(LEGACY_EVENT_PREFIX .. ':loadVehicles')
    AddEventHandler(LEGACY_EVENT_PREFIX .. ':loadVehicles', function()
        handleLoadVehicles(source)
    end)

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

    exports('GetPlayerParkedVehicles', function(discordID, charId, cb)
        if type(charId) == 'function' and cb == nil then cb = charId charId = nil end
        dbgCaller('GetPlayerParkedVehicles', discordID, charId, cb)
        fetchVehiclesForDiscord(discordID, charId, function(results)
            if cb then
                local ok, err = pcall(cb, results or {})
                if not ok then
                    debugPrint(('GetPlayerParkedVehicles cb error: %s'):format(tostring(err)))
                end
            end
        end)
    end)

    exports('GetParkedVehicleByPlate', function(discordID, charId, plate, cb)
        if type(charId) == 'string' and type(plate) == 'function' and cb == nil then cb = plate plate = charId charId = nil end
        if type(charId) == 'function' and cb == nil then cb = charId charId = nil end
        dbgCaller('GetParkedVehicleByPlate', discordID, charId, plate, cb)

        if not discordID or discordID == '' or not plate or plate == '' then
            if cb then
                local ok, err = pcall(cb, nil)
                if not ok then
                    debugPrint(('GetParkedVehicleByPlate cb error (nil early): %s'):format(tostring(err)))
                end
            end
            return
        end

        fetchVehiclesForDiscord(discordID, charId, function(results)
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

    exports('IsVehicleParked', function(discordID, charId, plate, cb)
        if type(charId) == 'string' and type(plate) == 'function' and cb == nil then cb = plate plate = charId charId = nil end
        if type(charId) == 'function' and cb == nil then cb = charId charId = nil end
        dbgCaller('IsVehicleParked', discordID, charId, plate, cb)

        if not discordID or discordID == '' or not plate or plate == '' then
            if cb then
                local ok, err = pcall(cb, false)
                if not ok then
                    debugPrint(('IsVehicleParked cb error (false early): %s'):format(tostring(err)))
                end
            end
            return
        end

        fetchVehiclesForDiscord(discordID, charId, function(results)
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

    CreateThread(function()
        ensureVehicleSchema(function()
            debugPrint(('Parking schema ready. user_vehicles.charid=%s'):format(tostring(vehicleTableHasCharId)))
        end)
    end)
else
    print('[Az-Parking] Parking disabled in config')
end
