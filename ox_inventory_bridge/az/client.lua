local AZ_RESOURCE = shared.azresource or (Config and Config.AzResource) or GetConvar('inventory:azresource', 'Az-Framework')
local AZ_DEBUG = (shared and shared.debugAz) or (Config and Config.DebugAz == true) or GetConvarInt('inventory:azdebug', 0) == 1
local AZ_VERBOSE = (shared and shared.debugVerbose) or (Config and Config.DebugVerbose == true)
local lastAzSnapshot = nil

local function debugPrint(category, ...)
    if not AZ_DEBUG then return end
    if shared and shared.debugLog then
        return shared.debugLog(('az:%s'):format(tostring(category or 'bridge')), ...)
    end
    print('^3[ox_inventory][az][client]^7', category, ...)
end

local function verbosePrint(category, ...)
    if not AZ_VERBOSE then return end
    debugPrint(category, ...)
end

local function safeTable(value)
    return type(value) == 'table' and value or {}
end

local function groupsFromSnapshot(snapshot)
    local groups = {}
    snapshot = safeTable(snapshot)

    if type(snapshot.groups) == 'table' then
        for name, grade in pairs(snapshot.groups) do
            groups[tostring(name):lower()] = tonumber(grade) or 0
        end
    end

    local jobInfo = safeTable(snapshot.jobInfo)
    local jobName = snapshot.job or jobInfo.name
    if jobName and tostring(jobName) ~= '' then
        groups[tostring(jobName):lower()] = tonumber(jobInfo.rank or snapshot.grade or snapshot.jobGrade) or 0
    end

    if not next(groups) then groups.unemployed = 0 end
    return groups
end

local function requestSnapshot(reason)
    debugPrint('requestSnapshot', ('reason=%s loaded=%s'):format(tostring(reason), tostring(PlayerData and PlayerData.loaded)))
    TriggerServerEvent('Az-Framework:Bridge:RequestSnapshot')
end

local function requestLoad(reason)
    debugPrint('requestLoad', ('reason=%s loaded=%s hasSnapshot=%s'):format(tostring(reason), tostring(PlayerData and PlayerData.loaded), tostring(type(lastAzSnapshot) == 'table')))
    TriggerServerEvent('ox_inventory:az:requestLoad', reason, lastAzSnapshot)
end

RegisterNetEvent('ox_inventory:az:setGroups', function(groups)
    debugPrint('setGroups', json.encode(groups or {}))
    client.setPlayerData('groups', groups or {})
end)

RegisterNetEvent('ox_inventory:az:debugClient', function(message)
    debugPrint('serverMessage', tostring(message))
    if shared.debugNotify and lib and lib.notify then
        lib.notify({ title = 'ox_inventory Az debug', description = tostring(message), type = 'inform', duration = 6000 })
    end
end)

RegisterNetEvent('Az-Framework:Bridge:Snapshot', function(snapshot)
    debugPrint('snapshot', ('type=%s identifier=%s charid=%s job=%s loaded=%s'):format(
        type(snapshot), tostring(snapshot and snapshot.identifier), tostring(snapshot and (snapshot.charid or snapshot.citizenid)), tostring(snapshot and (snapshot.job or (snapshot.jobInfo and snapshot.jobInfo.name))), tostring(PlayerData and PlayerData.loaded)
    ))

    if type(snapshot) == 'table' then
        lastAzSnapshot = snapshot

        if PlayerData.loaded then
            client.setPlayerData('groups', groupsFromSnapshot(snapshot))
        end

        if snapshot.charid or snapshot.citizenid or snapshot.identifier then
            requestLoad('Az snapshot received')
        end
    end
end)

RegisterNetEvent('az-fw-money:characterSelected', function(charid)
    debugPrint('event', ('az-fw-money:characterSelected charid=%s'):format(tostring(charid)))
    requestSnapshot('az-fw-money:characterSelected')
    requestLoad('az-fw-money:characterSelected')
end)

RegisterNetEvent('azfw:character_confirmed', function(charid)
    debugPrint('event', ('azfw:character_confirmed charid=%s'):format(tostring(charid)))
    requestSnapshot('azfw:character_confirmed')
    requestLoad('azfw:character_confirmed')
end)

RegisterNetEvent('azfw:receive_active_character', function(charid)
    debugPrint('event', ('azfw:receive_active_character charid=%s'):format(tostring(charid)))
    requestSnapshot('azfw:receive_active_character')
    requestLoad('azfw:receive_active_character')
end)

RegisterNetEvent('Az-Framework:characterUnloaded', client.onLogout)
RegisterNetEvent('Az-Framework:Bridge:characterUnloaded', client.onLogout)

RegisterCommand('oxinvdebug', function()
    local snapshot = nil
    local gameplayReady = nil

    if GetResourceState(AZ_RESOURCE) == 'started' then
        pcall(function() snapshot = exports[AZ_RESOURCE]:GetBridgeClientSnapshot() end)
        if type(snapshot) == 'table' then lastAzSnapshot = snapshot end
        pcall(function() gameplayReady = exports[AZ_RESOURCE]:IsGameplayReady() end)
    end

    local report = {
        loaded = PlayerData and PlayerData.loaded == true,
        invBusy = LocalPlayer.state.invBusy,
        invHotkeys = LocalPlayer.state.invHotkeys,
        canUseWeapons = LocalPlayer.state.canUseWeapons,
        azResource = AZ_RESOURCE,
        azState = GetResourceState(AZ_RESOURCE),
        gameplayReady = gameplayReady,
        snapshot = snapshot,
    }

    print(('^5[ox_inventory][debug][client][az:state]^7 %s'):format(json.encode(report)))
    TriggerServerEvent('ox_inventory:az:debugState', report)
    requestSnapshot('oxinvdebug command')
    requestLoad('oxinvdebug command')
end, false)

CreateThread(function()
    Wait(1000)
    debugPrint('startup', ('framework=%s azResource=%s azState=%s'):format(tostring(shared.framework), tostring(AZ_RESOURCE), tostring(GetResourceState(AZ_RESOURCE))))

    local attempts = tonumber(shared.azRetryAttempts) or 20
    local delay = tonumber(shared.azRetryDelayMs) or 1500

    for i = 1, attempts do
        if PlayerData and PlayerData.loaded then
            debugPrint('retry', ('stopping retries; inventory loaded at attempt=%s'):format(i))
            break
        end

        requestSnapshot(('startup retry %s/%s'):format(i, attempts))
        requestLoad(('startup retry %s/%s'):format(i, attempts))
        Wait(delay)
    end
end)

---@diagnostic disable-next-line: duplicate-set-field
function client.setPlayerStatus(values)
    local playerState = LocalPlayer.state

    for name, value in pairs(values) do
        if value > 100 or value < -100 then
            value = value * 0.0001
        end

        local current = tonumber(playerState[name]) or 0
        playerState:set(name, lib.math.clamp(current + value, 0, 100), true)
    end
end
