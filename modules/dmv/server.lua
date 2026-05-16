local Config = (Config and Config.DMV) or {}
if Config.Enabled == false then return end

local function dbExecute(query, params, cb)
    params = params or {}
    if exports and exports.oxmysql and exports.oxmysql.execute then
        exports.oxmysql:execute(query, params, function(affected)
            if cb then cb(affected) end
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.execute then
        MySQL.Async.execute(query, params, function(result)
            if cb then cb(result) end
        end)
    else
        print("^1[dmv] No MySQL library available (dbExecute)^0")
        if cb then cb(nil) end
    end
end

local function dbFetchAll(query, params, cb)
    params = params or {}
    if exports and exports.oxmysql and exports.oxmysql.execute then
        exports.oxmysql:execute(query, params, function(rows)
            if cb then cb(rows) end
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.fetchAll then
        MySQL.Async.fetchAll(query, params, function(rows)
            if cb then cb(rows) end
        end)
    else
        print("^1[dmv] No MySQL library available (dbFetchAll)^0")
        if cb then cb({}) end
    end
end

local function splitName(full)
    if not full then return "", "" end
    local first, last = full:match("^(%S+)%s+(.+)$")
    return first or full, last or ""
end

local function getPlayerIdentifier(src)
    local ids = GetPlayerIdentifiers(src)
    if not ids or #ids == 0 then return tostring(src) end
    return ids[1]
end

local function getDiscordId(src)
    local ids = GetPlayerIdentifiers(src) or {}
    for _, id in ipairs(ids) do
        if type(id) == "string" and id:sub(1, 8) == "discord:" then
            return id:sub(9)
        end
    end
    return nil
end

local function getCharId(src)
    local ok, ply = pcall(function() return Player(src) end)
    if not ok or not ply or not ply.state then return nil end

    return ply.state.charid
        or ply.state.charId
        or ply.state.characterId
        or ply.state.cid
        or nil
end

local function setUserCharactersLicenseValid(src, cb)
    local discordId = getDiscordId(src)
    if not discordId or discordId == "" then
        if cb then cb(false, "no_discord") end
        return
    end

    local charId = getCharId(src)

    if charId and tostring(charId) ~= "" then
        dbExecute([[
            UPDATE user_characters
            SET license_status = @ls
            WHERE discordid = @discordid AND charid = @charid
        ]], {
            ['@ls'] = "VALID",
            ['@discordid'] = tostring(discordId),
            ['@charid'] = tostring(charId),
        }, function()
            if cb then cb(true, "discord+char") end
        end)
    else

        dbExecute([[
            UPDATE user_characters
            SET license_status = @ls
            WHERE discordid = @discordid
        ]], {
            ['@ls'] = "VALID",
            ['@discordid'] = tostring(discordId),
        }, function()
            if cb then cb(true, "discord_only") end
        end)
    end
end

CreateThread(function()

    local tries = 0
    while tries < 30 do
        if (exports and exports.oxmysql and exports.oxmysql.execute) or (MySQL and MySQL.Async) then
            break
        end
        tries = tries + 1
        Wait(500)
    end

    dbExecute([[
        CREATE TABLE IF NOT EXISTS dmv_progress (
            identifier VARCHAR(64) NOT NULL,
            written TINYINT(1) NOT NULL DEFAULT 0,
            driving TINYINT(1) NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (identifier)
        )
    ]], {}, function() end)
end)

local function ensureProgressRow(identifier, cb)
    dbExecute([[
        INSERT INTO dmv_progress (identifier, written, driving)
        VALUES (@id, 0, 0)
        ON DUPLICATE KEY UPDATE identifier = identifier
    ]], { ['@id'] = identifier }, function()
        if cb then cb() end
    end)
end

local function fetchProgress(identifier, cb)
    ensureProgressRow(identifier, function()
        dbFetchAll("SELECT written, driving FROM dmv_progress WHERE identifier = @id LIMIT 1", {
            ['@id'] = identifier
        }, function(rows)
            local r = rows and rows[1] or nil
            cb({
                written = (r and tonumber(r.written) == 1) or false,
                driving = (r and tonumber(r.driving) == 1) or false,
            })
        end)
    end)
end

local function setProgress(identifier, written, driving, cb)
    dbExecute([[
        INSERT INTO dmv_progress (identifier, written, driving)
        VALUES (@id, @w, @d)
        ON DUPLICATE KEY UPDATE written = @w, driving = @d
    ]], {
        ['@id'] = identifier,
        ['@w']  = written and 1 or 0,
        ['@d']  = driving and 1 or 0
    }, function()
        if cb then cb() end
    end)
end

local function grantLicenseFor(src)
    local plyName = GetPlayerName(src) or tostring(src)
    local idf = getPlayerIdentifier(src) or tostring(src)
    local first, last = splitName(plyName)

    dbExecute([[
        UPDATE id_records
        SET license_status = @ls
        WHERE identifier = @identifier OR identifier = @name OR netId = @netId
    ]],
    {
        ['@ls'] = "VALID",
        ['@identifier'] = idf,
        ['@name'] = plyName,
        ['@netId'] = tostring(src),
    },
    function()

        dbExecute([[
            INSERT INTO id_records (netId, identifier, first_name, last_name, type, license_status)
            VALUES (@netId, @identifier, @first, @last, @type, @ls)
        ]],
        {
            ['@netId'] = tostring(src),
            ['@identifier'] = idf,
            ['@first'] = first,
            ['@last'] = last,
            ['@type'] = 'LicenseIssued',
            ['@ls'] = 'VALID'
        },
        function()

            setUserCharactersLicenseValid(src, function(_ok, _mode)
                TriggerClientEvent('dmv:licenseGranted', src)
                TriggerClientEvent('dmv:notifyClient', src, "DMV: License issued/updated.")

            end)
        end)
    end)
end

RegisterNetEvent('dmv:grantLicense', function()
    local src = source
    grantLicenseFor(src)
end)

RegisterNetEvent("dmv:requestProgress", function()
    local src = source
    local idf = getPlayerIdentifier(src)

    fetchProgress(idf, function(p)
        TriggerClientEvent("dmv:progress", src, p)
    end)
end)

RegisterNetEvent('dmv:writtenPassed', function()
    local src = source
    local idf = getPlayerIdentifier(src)

    fetchProgress(idf, function(p)
        if p.written then
            TriggerClientEvent('dmv:notifyClient', src, "DMV: You have completed the Written Test already.")
            TriggerClientEvent("dmv:progress", src, p)
            return
        end

        setProgress(idf, true, p.driving, function()
            TriggerClientEvent('dmv:notifyClient', src, "DMV: Written test passed. You can start the driving test.")
            TriggerClientEvent("dmv:progress", src, { written = true, driving = p.driving })
        end)
    end)
end)

RegisterNetEvent('dmv:writtenFailed', function()
    local src = source
    TriggerClientEvent('dmv:notifyClient', src, "DMV: Written test failed. Study and try again.")
end)

RegisterNetEvent('dmv:drivingPassed', function()
    local src = source
    local idf = getPlayerIdentifier(src)

    fetchProgress(idf, function(p)
        if p.driving then
            TriggerClientEvent('dmv:notifyClient', src, "DMV: You have completed the Driving Test already.")
            TriggerClientEvent("dmv:progress", src, p)
            return
        end

        setProgress(idf, true, true, function()
            grantLicenseFor(src)
            TriggerClientEvent("dmv:progress", src, { written = true, driving = true })
        end)
    end)
end)

RegisterNetEvent('dmv:drivingFailed', function(reason)
    local src = source
    TriggerClientEvent('dmv:notifyClient', src, "DMV: Driving test failed. Reason: " .. tostring(reason or ""))
end)

RegisterCommand("dmvgrant", function(src, args)
    local target = tonumber(args[1]) or src
    if target and target > 0 then
        grantLicenseFor(target)
    end
end, true)
