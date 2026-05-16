local Config = (Config and Config.Death) or {}
if Config.Enabled == false then return end

local function CalculateDistance(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function notify(src, data)
    if not src or src <= 0 then return end
    if type(data) ~= 'table' then return end

    TriggerClientEvent('ox_lib:notify', src, {
        title       = data.title or 'Notification',
        description = data.description or '',
        type        = data.type or 'inform',
        position    = data.position or 'top',
        duration    = data.duration or 5000
    })
end

local function notifyError(src, msg)
    notify(src, {
        title       = 'Error',
        description = msg,
        type        = 'error'
    })
end

local function notifySuccess(src, title, msg)
    notify(src, {
        title       = title or 'Success',
        description = msg,
        type        = 'success'
    })
end

local function isValidPlayerId(id)
    id = tonumber(id)
    if not id then return false end
    if GetPlayerPed(id) == 0 then return false end
    return true
end

lib.addCommand('adrev', {
    help = 'Admin command, revive player.',
    params = {
        {
            name = 'target',
            type = 'playerId',
            help = 'Target player server id'
        }
    }
}, function(source, args, raw)
    local adminSrc = source
    local targetSrc = tonumber(args.target)

    if not targetSrc or not isValidPlayerId(targetSrc) then
        print('[adrev] Error: Invalid player id.')
        notifyError(adminSrc, 'Invalid player ID.')
        return
    end

    exports['Az-Framework']:isAdmin(adminSrc, function(isAdmin)
        if not isAdmin then
            print(('[adrev] Player %d tried to use adrev without permission'):format(adminSrc))
            notifyError(adminSrc, "You don't have permission to use this command.")
            exports['Az-Framework']:logAdminCommand('adrev', adminSrc, { tostring(targetSrc) }, false)
            return
        end

        local targetPed = GetPlayerPed(targetSrc)
        if targetPed == 0 or not DoesEntityExist(targetPed) then
            print('[adrev] Error: Target ped does not exist.')
            notifyError(adminSrc, 'Target player entity is invalid.')
            return
        end

        if not IsEntityDead(targetPed) then
            notifyError(adminSrc, 'Player is not dead.')
            return
        end

        TriggerClientEvent('ND_Death:AdminRevivePlayerAtPosition', targetSrc)

        notifySuccess(targetSrc, 'Admin Action', 'You have been revived by an admin.')
        notifySuccess(adminSrc, 'Admin Action', ('You have revived player %d.'):format(targetSrc))

        exports['Az-Framework']:logAdminCommand('adrev', adminSrc, { tostring(targetSrc) }, true)
    end)
end)

lib.addCommand('cpr', {
    help = 'Medic command, perform CPR on a player.',
    params = {
        {
            name = 'target',
            type = 'playerId',
            help = 'Target player server id'
        }
    }
}, function(source, args, raw)
    local medicSrc = source

    local job = exports['Az-Framework']:getPlayerJob(medicSrc)
    if not job or job == '' then
        print('[CPR] Error: No active character / job for source player.')
        notifyError(medicSrc, 'Character data not found.')
        return
    end

    local hasPermission = false
    for _, department in pairs(Config.MedDept or {}) do
        if job == department then
            hasPermission = true
            break
        end
    end

    if not hasPermission then
        print(('[CPR] Error: Player %d with job %s has no permission.'):format(medicSrc, tostring(job)))
        notifyError(medicSrc, "You don't have permission to use this command.")
        return
    end

    local targetSrc = tonumber(args.target)
    if not targetSrc or not isValidPlayerId(targetSrc) then
        print('[CPR] Error: Invalid target player ID.')
        notifyError(medicSrc, 'Invalid player ID.')
        return
    end

    local medicPed = GetPlayerPed(medicSrc)
    local targetPed = GetPlayerPed(targetSrc)

    if medicPed == 0 or targetPed == 0 then
        print('[CPR] Error: Invalid ped handles for medic/target.')
        notifyError(medicSrc, 'Invalid player entity.')
        return
    end

    local medicCoords  = GetEntityCoords(medicPed)
    local targetCoords = GetEntityCoords(targetPed)

    if not medicCoords or not targetCoords then
        print('[CPR] Error: Invalid player positions.')
        notifyError(medicSrc, 'Invalid player positions.')
        return
    end

    local maxDistance = 5.0
    local distance = CalculateDistance(
        medicCoords.x, medicCoords.y, medicCoords.z,
        targetCoords.x, targetCoords.y, targetCoords.z
    )

    print(('[CPR] Debug: Distance between medic %d and target %d is %.2f'):format(medicSrc, targetSrc, distance))

    if distance > maxDistance then
        print('[CPR] Error: Target player is too far away.')
        notifyError(medicSrc, 'Target player is too far away.')
        return
    end

    TriggerClientEvent('startCPRAnimation', medicSrc)

    notify(medicSrc, {
        title       = 'Medical Action',
        description = 'You have initiated CPR!',
        type        = 'inform'
    })

    SetTimeout(5000, function()
        TriggerClientEvent('ND_Death:CPR', targetSrc)

        notify(medicSrc, {
            title       = 'Medical Action',
            description = 'You have revived a player.',
            type        = 'success'
        })
    end)
end)

RegisterServerEvent('ND_Death:AdminRevivePlayerAtPosition')
AddEventHandler('ND_Death:AdminRevivePlayerAtPosition', function(targetPlayerId)
    local adminSrc   = source
    local targetSrc  = tonumber(targetPlayerId)

    if not targetSrc or not isValidPlayerId(targetSrc) then
        notifyError(adminSrc, 'Invalid player ID for admin revive.')
        return
    end

    local targetPed = GetPlayerPed(targetSrc)
    if targetPed == 0 or not DoesEntityExist(targetPed) then
        notifyError(adminSrc, 'Target player entity is invalid.')
        return
    end

    if not IsEntityDead(targetPed) then
        notifyError(adminSrc, 'Player is not dead.')
        return
    end

    TriggerClientEvent('ND_Death:AdminRevivePlayerAtPosition', targetSrc)

    notifySuccess(targetSrc, 'Admin Action', 'You have been revived by an admin.')
    notifySuccess(adminSrc, 'Admin Action', ('You have revived player %d.'):format(targetSrc))
end)

RegisterServerEvent('PlayerDownNotification')
AddEventHandler('PlayerDownNotification', function(streetName, crossingRoad)
    local src = source

    local job = exports['Az-Framework']:getPlayerJob(src)
    if not job or job == '' then
        return
    end

    local isMedJob = false
    for _, dept in pairs(Config.MedDept or {}) do
        if job == dept then
            isMedJob = true
            break
        end
    end

    if not isMedJob then
        return
    end

    local notificationMessage = 'Player down at ' .. (streetName or 'unknown location')
    if crossingRoad and crossingRoad ~= '' then
        notificationMessage = notificationMessage .. ' and ' .. crossingRoad
    end

    TriggerClientEvent('SendMedicalNotifications', -1, notificationMessage, job)
end)
