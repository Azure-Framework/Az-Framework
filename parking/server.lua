
-- server.lua
if Config.Parking then
    local debug = true
    print('[az-fw-parking] Parking True, Initializing.')
    local function debugPrint(msg)
        if debug then print(('[az-fw-parking] %s'):format(msg)) end
    end

    local function getDiscordID(src)
        for _, id in ipairs(GetPlayerIdentifiers(src)) do
            if id:sub(1,8) == 'discord:' then return id:sub(9) end
        end
        return nil
    end

    AddEventHandler('onResourceStart', function(resName)
        if GetCurrentResourceName() ~= resName then return end
        debugPrint('Ensuring user_vehicles table exists')
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS user_vehicles (
                id INT AUTO_INCREMENT PRIMARY KEY,
                discordid VARCHAR(255) NOT NULL,
                plate VARCHAR(20) NOT NULL,
                model VARCHAR(50) NOT NULL,
                x DOUBLE NOT NULL,
                y DOUBLE NOT NULL,
                z DOUBLE NOT NULL,
                h DOUBLE NOT NULL,
                color1 INT NOT NULL,
                color2 INT NOT NULL,
                pearlescent INT NOT NULL,
                wheelColor INT NOT NULL,
                wheelType INT NOT NULL,
                windowTint INT NOT NULL,
                mods JSON,
                extras JSON,
                UNIQUE KEY uq_vehicle (discordid, plate),
                INDEX idx_discord (discordid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]], {}, function() debugPrint('user_vehicles table ready') end)
    end)

    RegisterNetEvent('raptor:toggleParkVehicle')
    AddEventHandler('raptor:toggleParkVehicle', function(props)
        local src, plate = source, props.plate
        local discordID = getDiscordID(src)
        if not discordID then debugPrint(('Denied toggleParkVehicle from %d'):format(src)); return end
        debugPrint(('toggleParkVehicle for %d: %s'):format(src, plate))

        MySQL.Async.fetchAll([[
            SELECT 1 FROM user_vehicles WHERE discordid=@discordid AND plate=@plate
        ]], {
            ['@discordid'] = discordID,
            ['@plate']     = plate
        }, function(rows)
            if #rows == 0 then
                debugPrint(('PARK -> INSERT %s for %s'):format(plate, discordID))
                MySQL.Async.execute([[
                    INSERT INTO user_vehicles
                        (discordid, plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras)
                    VALUES
                        (@discordid,@plate,@model,@x,@y,@z,@h,@color1,@color2,@pearlescent,@wheelColor,@wheelType,@windowTint,@mods,@extras)
                    ON DUPLICATE KEY UPDATE
                        model=@model, x=@x, y=@y, z=@z, h=@h,
                        color1=@color1, color2=@color2,
                        pearlescent=@pearlescent, wheelColor=@wheelColor,
                        wheelType=@wheelType, windowTint=@windowTint,
                        mods=@mods, extras=@extras
                ]], {
                    ['@discordid']=discordID, ['@plate']=plate,
                    ['@model']=props.model, ['@x']=props.x, ['@y']=props.y, ['@z']=props.z, ['@h']=props.h,
                    ['@color1']=props.color1, ['@color2']=props.color2,
                    ['@pearlescent']=props.pearlescent, ['@wheelColor']=props.wheelColor,
                    ['@wheelType']=props.wheelType, ['@windowTint']=props.windowTint,
                    ['@mods']=json.encode(props.mods or {}), ['@extras']=json.encode(props.extras or {})
                }, function()
                    TriggerClientEvent('raptor:vehicleParkToggled', src, { plate=plate, park=true })
                end)
            else
                debugPrint(('UNPARK -> DELETE %s for %s'):format(plate, discordID))
                MySQL.Async.execute([[
                    DELETE FROM user_vehicles WHERE discordid=@discordid AND plate=@plate
                ]], { ['@discordid']=discordID, ['@plate']=plate }, function()
                    TriggerClientEvent('raptor:vehicleParkToggled', src, { plate=plate, park=false })
                end)
            end
        end)
    end)

    RegisterNetEvent('raptor:loadVehicles')
    AddEventHandler('raptor:loadVehicles', function()
        local src = source
        local discordID = getDiscordID(src)
        if not discordID then debugPrint(('Denied loadVehicles from %d'):format(src)); return end
        debugPrint(('Loading vehicles for %s'):format(discordID))
        MySQL.Async.fetchAll([[
            SELECT plate, model, x, y, z, h, color1, color2, pearlescent, wheelColor, wheelType, windowTint, mods, extras
            FROM user_vehicles WHERE discordid=@discordid
        ]], { ['@discordid']=discordID }, function(results)
            for _, v in ipairs(results) do
                v.mods = json.decode(v.mods or '{}')
                v.extras = json.decode(v.extras or '{}')
            end
            TriggerClientEvent('raptor:vehiclesLoaded', src, results)
        end)
    end)
else
    print('[az-fw-parking] Parking disabled in config')
end
