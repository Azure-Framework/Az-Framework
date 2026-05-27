local Inventory = require 'modules.inventory.server'

local AZ_RESOURCE = shared.azresource or GetConvar('inventory:azresource', Config and Config.AzResource or 'Az-Framework')
local AZ_DEBUG = (shared and shared.debugAz) or GetConvarInt('inventory:azdebug', 0) == 1 or (Config and Config.DebugAz == true)
local AZ_VERBOSE = (shared and shared.debugVerbose) or (Config and Config.DebugVerbose == true) or GetConvarInt('inventory:debugverbose', 0) == 1
local SYNC_MONEY = GetConvarInt('inventory:azframeworkmoney', 1) == 1
local pendingLoads = {}
local clientSnapshots = {}
local initialLoadSources = {}
local debugPrint

local function parseAzInventoryIdentifier(identifier)
    identifier = tostring(identifier or '')
    local discord, charid = identifier:match('^az:([^:]+):(.+)$')
    if discord and charid then return discord, charid end

    charid = identifier:match('^azlic:[^:]+:(.+)$') or identifier:match('^azchar:(.+)$')
    if charid and charid ~= '' then return nil, charid end

    return nil, identifier ~= '' and identifier or nil
end

local function installAzInventoryStorage()
    if type(db) ~= 'table' then
        SetTimeout(250, installAzInventoryStorage)
        return
    end

    CreateThread(function()
        pcall(MySQL.query.await, 'ALTER TABLE `user_characters` ADD COLUMN `inventory` LONGTEXT NULL')
        pcall(MySQL.query.await, 'ALTER TABLE `user_vehicles` ADD COLUMN `glovebox` LONGTEXT NULL')
        pcall(MySQL.query.await, 'ALTER TABLE `user_vehicles` ADD COLUMN `trunk` LONGTEXT NULL')
    end)

    db.loadPlayer = function(identifier)
        local discord, charid = parseAzInventoryIdentifier(identifier)
        if not charid then return end

        local inventory
        if discord and discord ~= '' then
            inventory = MySQL.prepare.await('SELECT inventory FROM `user_characters` WHERE `discordid` = ? AND `charid` = ? LIMIT 1', { discord, charid })
        else
            inventory = MySQL.prepare.await('SELECT inventory FROM `user_characters` WHERE `charid` = ? LIMIT 1', { charid })
        end

        return inventory and json.decode(inventory)
    end

    db.savePlayer = function(owner, inventory)
        local discord, charid = parseAzInventoryIdentifier(owner)
        if not charid then return end

        if discord and discord ~= '' then
            return MySQL.prepare('UPDATE `user_characters` SET inventory = ? WHERE `discordid` = ? AND `charid` = ?', { inventory, discord, charid })
        end

        return MySQL.prepare('UPDATE `user_characters` SET inventory = ? WHERE `charid` = ?', { inventory, charid })
    end

    db.loadGlovebox = function(plate)
        return MySQL.prepare.await('SELECT plate, glovebox FROM `user_vehicles` WHERE `plate` = ? LIMIT 1', { plate })
    end

    db.saveGlovebox = function(plate, inventory)
        return MySQL.prepare('UPDATE `user_vehicles` SET glovebox = ? WHERE `plate` = ?', { inventory, plate })
    end

    db.loadTrunk = function(plate)
        return MySQL.prepare.await('SELECT plate, trunk FROM `user_vehicles` WHERE `plate` = ? LIMIT 1', { plate })
    end

    db.saveTrunk = function(plate, inventory)
        return MySQL.prepare('UPDATE `user_vehicles` SET trunk = ? WHERE `plate` = ?', { inventory, plate })
    end

    if debugPrint then debugPrint('storage', 'Az inventory storage installed for user_characters/user_vehicles') end
end

function debugPrint(category, ...)
    if not AZ_DEBUG then return end
    if shared and shared.debugLog then
        return shared.debugLog(('az:%s'):format(tostring(category or 'bridge')), ...)
    end
    print('^3[ox_inventory][az]^7', category, ...)
end

local function verbosePrint(category, ...)
    if not AZ_VERBOSE then return end
    debugPrint(category, ...)
end

installAzInventoryStorage()

local function azReady()
    local state = GetResourceState(AZ_RESOURCE)
    return state == 'started' or state == 'starting', state
end

local function azExport(name, ...)
    local ready, state = azReady()
    if not ready then
        verbosePrint('export', ('%s skipped; %s state=%s'):format(name, AZ_RESOURCE, tostring(state)))
        return nil, 'az_not_started'
    end

    local ok, result, a, b = pcall(function(...)
        return exports[AZ_RESOURCE][name](...)
    end, ...)

    if ok then
        verbosePrint('export', ('%s ok resultType=%s'):format(name, type(result)))
        return result, a, b
    end

    local firstErr = result

    ok, result, a, b = pcall(function(...)
        return exports[AZ_RESOURCE][name](exports[AZ_RESOURCE], ...)
    end, ...)

    if ok then
        verbosePrint('export', ('%s ok-self resultType=%s'):format(name, type(result)))
        return result, a, b
    end

    debugPrint('export-error', ('%s failed. first=%s second=%s'):format(name, tostring(firstErr), tostring(result)))
    return nil, result
end

local function safeTable(value)
    return type(value) == 'table' and value or {}
end

local function tableValue(tbl, key)
    return type(tbl) == 'table' and tbl[key] or nil
end

local function getIdentifierValue(source, wanted)
    wanted = tostring(wanted or ''):gsub(':$', '')
    if wanted == '' then return nil end

    if GetPlayerIdentifierByType then
        local direct = GetPlayerIdentifierByType(source, wanted)
        if direct and direct ~= '' then
            return tostring(direct):gsub('^' .. wanted .. ':', '')
        end
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(source) or {}) do
        local prefix, value = tostring(identifier):match('^([^:]+):(.+)$')
        if prefix == wanted and value and value ~= '' then return value end
    end

    return nil
end

local function getStateCharId(source)
    local ok, state = pcall(function()
        local player = Player(source)
        return player and player.state
    end)

    if not ok or not state then return nil end

    local candidates = {
        state.az_active_character,
        state.az_active_charid,
        state.activeCharacter,
        state.charid,
        state.citizenid,
    }

    for i = 1, #candidates do
        local value = tostring(candidates[i] or '')
        if value ~= '' and value ~= 'nil' and value ~= 'unknown' then return value end
    end

    return nil
end

local function sanitizeClientSnapshot(source, snapshot)
    if type(snapshot) ~= 'table' then return nil end

    local stateCharId = getStateCharId(source)
    local charid = tostring(stateCharId or snapshot.charid or snapshot.citizenid or '')
    if charid == '' or charid == 'nil' or charid == 'unknown' then return nil end

    -- Never trust a client-sent full identifier if we can build one from server-side player identifiers.
    local serverDiscord = getIdentifierValue(source, 'discord') or tostring(snapshot.discordid or snapshot.discordId or ''):gsub('^discord:', '')
    local serverLicense = getIdentifierValue(source, 'license2') or getIdentifierValue(source, 'license')
    local identifier

    if serverDiscord and serverDiscord ~= '' then
        identifier = ('az:%s:%s'):format(serverDiscord, charid)
    elseif serverLicense and serverLicense ~= '' then
        identifier = ('azlic:%s:%s'):format(serverLicense, charid)
    else
        identifier = ('azchar:%s'):format(charid)
    end

    local cleaned = {}
    for key, value in pairs(snapshot) do cleaned[key] = value end

    cleaned.source = source
    cleaned.identifier = identifier
    cleaned.charid = charid
    cleaned.citizenid = charid
    cleaned.discordid = serverDiscord or cleaned.discordid
    cleaned.license = serverLicense or cleaned.license

    if type(cleaned.money) ~= 'table' then cleaned.money = {} end
    cleaned.money.cash = tonumber(cleaned.cash or cleaned.money.cash) or 0
    cleaned.money.bank = tonumber(cleaned.bank or cleaned.money.bank) or 0
    cleaned.cash = cleaned.money.cash
    cleaned.bank = cleaned.money.bank

    if not cleaned.name or tostring(cleaned.name) == '' then cleaned.name = GetPlayerName(source) end
    if not cleaned.fullname or tostring(cleaned.fullname) == '' then cleaned.fullname = cleaned.name end

    return cleaned
end

local function cacheClientSnapshot(source, snapshot, reason)
    local cleaned = sanitizeClientSnapshot(source, snapshot)
    if not cleaned then
        verbosePrint('client-snapshot', ('ignored source=%s reason=%s type=%s stateCharId=%s'):format(
            tostring(source), tostring(reason), type(snapshot), tostring(getStateCharId(source))
        ))
        return nil
    end

    clientSnapshots[source] = cleaned
    debugPrint('client-snapshot', ('cached source=%s reason=%s identifier=%s charid=%s job=%s'):format(
        tostring(source), tostring(reason), tostring(cleaned.identifier), tostring(cleaned.charid), tostring(cleaned.job or (cleaned.jobInfo and cleaned.jobInfo.name))
    ))
    return cleaned
end

local function resolveSnapshot(source, suppliedSnapshot, reason)
    local snapshot, err = azExport('GetBridgePlayerSnapshot', source)

    if snapshot then
        debugPrint('snapshot-source', ('source=%s using server export reason=%s'):format(tostring(source), tostring(reason)))
        return snapshot, 'server_export'
    end

    local stateCharId = getStateCharId(source)
    debugPrint('snapshot-miss', ('source=%s export returned nil err=%s reason=%s stateCharId=%s discord=%s license=%s'):format(
        tostring(source), tostring(err), tostring(reason), tostring(stateCharId), tostring(getIdentifierValue(source, 'discord')), tostring(getIdentifierValue(source, 'license'))
    ))

    if suppliedSnapshot then
        snapshot = cacheClientSnapshot(source, suppliedSnapshot, ('resolve:%s'):format(tostring(reason)))
        if snapshot then return snapshot, 'client_supplied' end
    end

    snapshot = clientSnapshots[source]
    if snapshot then
        debugPrint('snapshot-source', ('source=%s using cached client snapshot reason=%s charid=%s'):format(tostring(source), tostring(reason), tostring(snapshot.charid)))
        return snapshot, 'client_cache'
    end

    return nil, err or 'no_snapshot'
end

local function getJobName(snapshot)
    local jobInfo = safeTable(snapshot.jobInfo)
    return snapshot.job or jobInfo.name
end

local function getJobRank(snapshot)
    local jobInfo = safeTable(snapshot.jobInfo)
    return tonumber(jobInfo.rank or snapshot.grade or snapshot.jobGrade) or 0
end

local function jobGroups(snapshot)
    snapshot = safeTable(snapshot)
    local groups = {}

    if type(snapshot.groups) == 'table' then
        for name, grade in pairs(snapshot.groups) do
            groups[tostring(name):lower()] = tonumber(grade) or 0
        end
    end

    local jobName = getJobName(snapshot)
    if jobName and tostring(jobName) ~= '' then
        groups[tostring(jobName):lower()] = getJobRank(snapshot)
    end

    if not next(groups) then groups.unemployed = 0 end
    return groups
end

local function normalizeSnapshot(source, snapshot)
    if type(snapshot) ~= 'table' then
        debugPrint('snapshot', ('source=%s invalid snapshot type=%s'):format(tostring(source), type(snapshot)))
        return nil
    end

    local identifier = tostring(snapshot.identifier or '')
    local charid = tostring(snapshot.charid or snapshot.citizenid or '')
    local discordid = tostring(snapshot.discordid or snapshot.discordId or ''):gsub('^discord:', '')

    if identifier == '' then
        if discordid ~= '' and charid ~= '' then
            identifier = ('az:%s:%s'):format(discordid, charid)
        elseif charid ~= '' then
            identifier = ('azchar:%s'):format(charid)
        else
            identifier = GetPlayerIdentifierByType(source, 'license2') or GetPlayerIdentifierByType(source, 'license') or ('source:%s'):format(source)
        end
    end

    if charid == '' then
        debugPrint('snapshot', ('source=%s snapshot has no charid/citizenid yet. identifier=%s name=%s'):format(tostring(source), identifier, tostring(snapshot.name or snapshot.fullname)))
        return nil
    end

    local metadata = safeTable(snapshot.metadata)

    return {
        source = source,
        identifier = identifier,
        citizenid = charid,
        charid = charid,
        name = tostring(snapshot.fullname or snapshot.name or GetPlayerName(source) or ('Player %s'):format(source)),
        firstname = snapshot.firstname,
        lastname = snapshot.lastname,
        sex = snapshot.sex or snapshot.gender or metadata.sex,
        dateofbirth = snapshot.dateofbirth or snapshot.dob or metadata.dateofbirth,
        job = snapshot.job,
        jobInfo = snapshot.jobInfo,
        groups = jobGroups(snapshot),
        snapshot = snapshot,
    }
end

local function loadAzPlayer(source, force, reason, suppliedSnapshot)
    source = tonumber(source or 0) or 0
    if source <= 0 or not GetPlayerName(source) then
        debugPrint('load', ('ignored invalid source=%s reason=%s'):format(tostring(source), tostring(reason)))
        return false
    end

    local ready, state = azReady()
    debugPrint('load', ('attempt source=%s name=%s force=%s reason=%s azState=%s'):format(source, tostring(GetPlayerName(source)), tostring(force), tostring(reason), tostring(state)))

    if not ready then return false end

    local snapshot, snapshotSource = resolveSnapshot(source, suppliedSnapshot, reason)
    if not snapshot then
        debugPrint('load', ('no snapshot source=%s err=%s'):format(source, tostring(snapshotSource)))
        return false
    end

    debugPrint('load', ('snapshot source=%s via=%s'):format(source, tostring(snapshotSource)))

    debugPrint('snapshot', ('source=%s identifier=%s charid=%s job=%s cash=%s bank=%s'):format(
        source, tostring(snapshot.identifier), tostring(snapshot.charid or snapshot.citizenid), tostring(getJobName(snapshot)), tostring(snapshot.cash or tableValue(snapshot.money, 'cash')), tostring(snapshot.bank or tableValue(snapshot.money, 'bank'))
    ))

    local player = normalizeSnapshot(source, snapshot)
    if not player then return false end

    local existing = Inventory(source)
    if existing then
        if existing.owner == player.identifier and not force then
            existing.player = existing.player or {}
            existing.player.groups = player.groups or existing.player.groups or {}
            debugPrint('load', ('already loaded source=%s owner=%s'):format(source, tostring(existing.owner)))
            TriggerClientEvent('ox_inventory:az:debugClient', source, 'server says inventory already loaded')
            return existing
        end

        debugPrint('load', ('reloading inventory source=%s oldOwner=%s newOwner=%s'):format(source, tostring(existing.owner), tostring(player.identifier)))
        existing:closeInventory(true)
        Inventory.Save(existing)
        Inventory.Remove(existing)
        Wait(100)
    end

    debugPrint('load', ('creating ox inventory for %s (%s) groups=%s'):format(player.name, player.identifier, json.encode(player.groups or {})))
    initialLoadSources[source] = true
    server.setPlayerInventory(player)

    local inv = Inventory(source)
    if not inv then
        initialLoadSources[source] = nil
        debugPrint('load-error', ('server.setPlayerInventory finished but Inventory(%s) is still nil'):format(source))
        return false
    end

    if SYNC_MONEY then
        local snapshotCash = tonumber(snapshot.cash or tableValue(snapshot.money, 'cash'))
        local exportCash = nil

        if snapshotSource == 'server_export' then
            exportCash = tonumber(azExport('GetBridgeMoney', source, 'cash') or azExport('GetBridgeMoney', source, 'money'))
        end

        local cash = exportCash or snapshotCash or 0
        debugPrint('money', ('sync cash source=%s amount=%s snapshotSource=%s exportCash=%s snapshotCash=%s'):format(source, cash, tostring(snapshotSource), tostring(exportCash), tostring(snapshotCash)))
        if cash >= 0 then
            Inventory.SetItem(inv, 'money', cash)
        end
    end

    initialLoadSources[source] = nil
    TriggerClientEvent('ox_inventory:az:debugClient', source, ('server loaded inventory owner=%s'):format(player.identifier))
    return inv
end

local function scheduleLoad(source, force, reason, attempt, suppliedSnapshot)
    source = tonumber(source or 0) or 0
    if source <= 0 then return end

    attempt = attempt or 1
    local maxAttempts = tonumber(shared.azRetryAttempts) or 20
    local retryDelay = tonumber(shared.azRetryDelayMs) or 1500

    if suppliedSnapshot then
        cacheClientSnapshot(source, suppliedSnapshot, ('schedule:%s'):format(tostring(reason)))
    end

    if pendingLoads[source] and attempt == 1 then
        verbosePrint('retry', ('source=%s already pending; reason=%s; cachedSnapshot=%s'):format(source, tostring(reason), tostring(clientSnapshots[source] ~= nil)))
        return
    end

    pendingLoads[source] = true

    SetTimeout(attempt == 1 and 100 or retryDelay, function()
        if not GetPlayerName(source) then
            pendingLoads[source] = nil
            return
        end

        local inv = loadAzPlayer(source, force, ('%s attempt=%s/%s'):format(tostring(reason), attempt, maxAttempts), suppliedSnapshot or clientSnapshots[source])
        if inv or not shared.azRetryLoads or attempt >= maxAttempts then
            if not inv then
                debugPrint('retry-failed', ('source=%s reason=%s attempts=%s. Run /oxinvdebug in F8 and check server console.'):format(source, tostring(reason), attempt))
                TriggerClientEvent('ox_inventory:az:debugClient', source, ('FAILED to load after %s attempts. Check server console.'):format(attempt))
            end
            pendingLoads[source] = nil
            return
        end

        scheduleLoad(source, force, reason, attempt + 1, suppliedSnapshot or clientSnapshots[source])
    end)
end

AddEventHandler('playerDropped', function()
    pendingLoads[source] = nil
    clientSnapshots[source] = nil
    initialLoadSources[source] = nil
    server.playerDropped(source)
end)

AddEventHandler('Az-Framework:characterSelected', function(changedSrc, charid)
    local src = tonumber(changedSrc) or source
    debugPrint('event', ('Az-Framework:characterSelected src=%s charid=%s eventSource=%s'):format(tostring(src), tostring(charid), tostring(source)))
    scheduleLoad(src, true, 'Az-Framework:characterSelected')
end)

AddEventHandler('Az-Framework:Bridge:characterSelected', function(changedSrc, charid)
    local src = tonumber(changedSrc) or source
    debugPrint('event', ('Az-Framework:Bridge:characterSelected src=%s charid=%s eventSource=%s'):format(tostring(src), tostring(charid), tostring(source)))
    scheduleLoad(src, true, 'Az-Framework:Bridge:characterSelected')
end)

AddEventHandler('az-fw-money:characterSelected', function(changedSrc)
    local src = tonumber(changedSrc) or source
    debugPrint('event', ('az-fw-money:characterSelected src=%s eventSource=%s'):format(tostring(src), tostring(source)))
    scheduleLoad(src, true, 'az-fw-money:characterSelected')
end)

RegisterNetEvent('ox_inventory:az:requestLoad', function(reason, snapshot)
    local src = source
    debugPrint('event', ('client requested load src=%s reason=%s snapshotType=%s'):format(src, tostring(reason), type(snapshot)))
    if type(snapshot) == 'table' then
        cacheClientSnapshot(src, snapshot, ('client:%s'):format(tostring(reason)))
    end
    scheduleLoad(src, false, ('client:%s'):format(tostring(reason)), nil, snapshot)
end)

RegisterNetEvent('ox_inventory:az:debugState', function(clientReport)
    local src = source
    local inv = Inventory(src)
    local supplied = type(clientReport) == 'table' and clientReport.snapshot or nil
    if supplied then cacheClientSnapshot(src, supplied, 'debugState') end
    local snapshot = select(1, resolveSnapshot(src, supplied, 'debugState'))
    print(('^5[ox_inventory][debug][server][az:state]^7 src=%s name=%s azState=%s inv=%s owner=%s loadedClient=%s stateCharId=%s cachedClientSnapshot=%s'):format(
        tostring(src), tostring(GetPlayerName(src)), tostring(select(2, azReady())), tostring(inv ~= nil), tostring(inv and inv.owner), tostring(type(clientReport) == 'table' and clientReport.loaded), tostring(getStateCharId(src)), tostring(clientSnapshots[src] ~= nil)
    ))
    print(('^5[ox_inventory][debug][server][az:snapshot]^7 %s'):format(json.encode(snapshot or {})))
    print(('^5[ox_inventory][debug][server][az:clientReport]^7 %s'):format(json.encode(clientReport or {})))
    if not inv then scheduleLoad(src, false, 'debug command', nil, supplied) end
end)

AddEventHandler('Az-Framework:jobChanged', function(changedSrc)
    local src = tonumber(changedSrc) or source
    if not src or src <= 0 then return end

    local inv = Inventory(src)
    if not inv or not inv.player then
        debugPrint('job', ('jobChanged but inventory missing src=%s; scheduling load'):format(src))
        return scheduleLoad(src, false, 'jobChanged inventory missing')
    end

    local snapshot = select(1, resolveSnapshot(src, nil, 'jobChanged'))
    local player = normalizeSnapshot(src, snapshot)
    if player then
        inv.player.groups = player.groups or {}
        TriggerClientEvent('ox_inventory:az:setGroups', src, inv.player.groups)
        debugPrint('job', ('updated groups src=%s groups=%s'):format(src, json.encode(inv.player.groups)))
    end
end)

AddEventHandler('Az-Framework:Bridge:moneyChanged', function(changedSrc, account)
    if not SYNC_MONEY then return end
    local src = tonumber(changedSrc) or source
    if not src or src <= 0 then return end

    account = tostring(account or 'cash'):lower()
    if account ~= 'cash' and account ~= 'money' then return end

    local inv = Inventory(src)
    if not inv then
        debugPrint('money', ('moneyChanged but inventory missing src=%s; scheduling load'):format(src))
        return scheduleLoad(src, false, 'moneyChanged inventory missing')
    end

    local snapshot, snapshotSource = resolveSnapshot(src, nil, 'moneyChanged')
    local cash
    if snapshotSource == 'server_export' then
        cash = tonumber(azExport('GetBridgeMoney', src, 'cash') or azExport('GetBridgeMoney', src, 'money'))
    elseif snapshot then
        cash = tonumber(snapshot.cash or (snapshot.money and snapshot.money.cash))
    end
    cash = cash or 0

    local current = Inventory.GetItem(inv, 'money', false, true) or 0
    debugPrint('money', ('moneyChanged src=%s current=%s az=%s snapshotSource=%s'):format(src, current, cash, tostring(snapshotSource)))
    if current ~= cash then
        Inventory.SetItem(inv, 'money', cash)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= AZ_RESOURCE and resourceName ~= GetCurrentResourceName() then return end
    SetTimeout(1000, function()
        debugPrint('resource', ('resourceStart=%s scanning players'):format(resourceName))
        for _, playerId in ipairs(GetPlayers()) do
            scheduleLoad(tonumber(playerId), false, ('resourceStart:%s'):format(resourceName))
        end
    end)
end)

SetTimeout(1000, function()
    local ready, state = azReady()
    debugPrint('startup', ('framework=%s azResource=%s azState=%s syncMoney=%s retry=%s attempts=%s'):format(shared.framework, AZ_RESOURCE, tostring(state), tostring(SYNC_MONEY), tostring(shared.azRetryLoads), tostring(shared.azRetryAttempts)))

    if not ready then
        warn(('[ox_inventory] inventory:framework is az but %s has not started yet. Start Az-Framework before ox_inventory.'):format(AZ_RESOURCE))
        return
    end

    server.GetPlayerFromId = function(source)
        return normalizeSnapshot(source, select(1, resolveSnapshot(source, nil, 'GetPlayerFromId')))
    end

    for _, playerId in ipairs(GetPlayers()) do
        scheduleLoad(tonumber(playerId), false, 'ox_inventory startup scan')
    end
end)

---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerData(player)
    local groups = player.groups or jobGroups(player.snapshot or player)

    debugPrint('setPlayerData', ('source=%s identifier=%s groups=%s'):format(tostring(player.source), tostring(player.identifier), json.encode(groups or {})))

    return {
        source = player.source,
        identifier = player.identifier,
        citizenid = player.citizenid or player.charid,
        charid = player.charid or player.citizenid,
        name = player.name,
        groups = groups or {},
        sex = player.sex,
        dateofbirth = player.dateofbirth,
    }
end

---@diagnostic disable-next-line: duplicate-set-field
function server.syncInventory(inv)
    if not SYNC_MONEY then return end
    if inv and initialLoadSources[inv.id] then
        debugPrint('syncInventory', ('skip initial load sync src=%s'):format(tostring(inv.id)))
        return
    end

    local snapshot, snapshotSource = resolveSnapshot(inv.id, nil, 'syncInventory')
    if not snapshot then
        debugPrint('syncInventory', ('skip; no Az snapshot src=%s'):format(tostring(inv and inv.id)))
        return
    end

    local accounts = Inventory.GetAccountItemCounts(inv)
    if not accounts then return end

    for account, amount in pairs(accounts) do
        local azAccount = account == 'money' and 'cash' or account
        local current
        if snapshotSource == 'server_export' then
            current = tonumber(azExport('GetBridgeMoney', inv.id, azAccount))
        else
            current = tonumber(azAccount == 'bank' and snapshot.bank or snapshot.cash or (snapshot.money and snapshot.money[azAccount]))
        end
        current = current or 0
        amount = tonumber(amount) or 0

        if current ~= amount then
            debugPrint('syncInventory', ('src=%s account=%s az=%s ox=%s snapshotSource=%s'):format(tostring(inv.id), tostring(azAccount), tostring(current), tostring(amount), tostring(snapshotSource)))
            if snapshotSource == 'server_export' then
                azExport('SetBridgeMoney', inv.id, azAccount, amount, 'ox_inventory sync')
            else
                debugPrint('syncInventory', ('not writing money because Az server export snapshot is unavailable for src=%s'):format(tostring(inv.id)))
            end
        end
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.hasLicense(inv, license)
    local metadata = azExport('GetBridgeMetadata', inv.id, 'licenses')
    if type(metadata) == 'table' then
        local name = type(license) == 'table' and license.name or license
        return metadata[name]
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.buyLicense(inv, license)
    if server.hasLicense(inv, license.name) then
        return false, 'already_have'
    elseif Inventory.GetItem(inv, 'money', false, true) < license.price then
        return false, 'can_not_afford'
    end

    Inventory.RemoveItem(inv, 'money', license.price)
    local licenses = azExport('GetBridgeMetadata', inv.id, 'licenses')
    if type(licenses) ~= 'table' then licenses = {} end
    licenses[license.name] = true
    azExport('SetBridgeMetadata', inv.id, 'licenses', licenses)

    return true, 'have_purchased'
end

---@diagnostic disable-next-line: duplicate-set-field
function server.isPlayerBoss(playerId, group, grade)
    local snapshot = select(1, resolveSnapshot(playerId, nil, 'isPlayerBoss'))
    local jobInfo = type(snapshot) == 'table' and type(snapshot.jobInfo) == 'table' and snapshot.jobInfo or {}
    local boss = jobInfo.isBoss or jobInfo.boss
    if boss ~= nil then return boss == true end
    return tonumber(grade) and tonumber(grade) >= 4
end
