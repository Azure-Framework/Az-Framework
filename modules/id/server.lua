local RESOURCE_NAME = GetCurrentResourceName()
local Config = (Config and Config.IDCard) or {}
if Config.Enabled == false then return end
local fw            = exports['Az-Framework']

if Config.Debug == nil then Config.Debug = true end

local db         = nil
local ID_TABLE   = Config.IdTableName   or 'az_id_cards'
local CHAR_TABLE = Config.CharTableName or 'user_characters'

do
    local state = GetResourceState('oxmysql')
    if state == 'started' or state == 'starting' then
        db = exports['oxmysql']
    end
end

local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(("^3[%s S]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

AddEventHandler('onResourceStart', function(res)
    if res ~= RESOURCE_NAME then return end
    dprint("server.lua started. DB =", db and "yes" or "no", "ID_TABLE =", ID_TABLE, "CHAR_TABLE =", CHAR_TABLE)
end)

local function getIdentityIds(src)
    local charId    = fw:GetPlayerCharacter(src)
    local discordId = fw:getDiscordID(src) or ""

    if not charId then
        dprint(("getIdentityIds: ❌ no active character for src=%s"):format(src))
        return nil
    end

    dprint(("getIdentityIds: ✅ src=%s charId=%s discord=%s"):format(
        src, tostring(charId), tostring(discordId)
    ))

    return charId, discordId
end

local function saveToDb(charId, discordId, mugshot, issued, expires, infoTable)
    if not db then
        dprint("saveToDb: ❌ oxmysql not available, skipping DB save")
        return
    end
    if not charId or not mugshot or mugshot == "" then
        dprint("saveToDb: ❌ missing charId or mugshot")
        return
    end

    local infoJson = infoTable and next(infoTable) and json.encode(infoTable) or nil

    local q = ([[INSERT INTO %s (char_id, discord_id, mugshot, issued, expires, info)
                 VALUES (?, ?, ?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE
                   discord_id = VALUES(discord_id),
                   mugshot    = VALUES(mugshot),
                   issued     = VALUES(issued),
                   expires    = VALUES(expires),
                   info       = VALUES(info)]])
        :format(ID_TABLE)

    dprint(("saveToDb: ▶ char=%s disc=%s issued=%s expires=%s infoJsonLen=%s"):format(
        tostring(charId),
        tostring(discordId),
        tostring(issued),
        tostring(expires),
        infoJson and #infoJson or 0
    ))

    db:execute(q, { charId, discordId, mugshot, issued, expires, infoJson }, function(result)
        if not Config.Debug then return end
        if type(result) == "table" then
            dprint(("saveToDb: ✅ char=%s affected=%s"):format(
                tostring(charId),
                tostring(result.affectedRows or "?")
            ))
        else
            dprint(("saveToDb: ✅ char=%s raw=%s"):format(
                tostring(charId),
                tostring(result)
            ))
        end
    end)
end

local function loadFromDbForSource(src, cb)
    local charId, discordId = getIdentityIds(src)
    if not charId then
        cb(nil, "no-identity")
        return
    end

    if not db then
        dprint("loadFromDbForSource: ❌ oxmysql not available")
        cb(nil, "no-db")
        return
    end

    local q = ([[SELECT char_id, discord_id, mugshot, issued, expires, info
                 FROM %s WHERE char_id = ? LIMIT 1]])
        :format(ID_TABLE)

    dprint(("loadFromDbForSource: ▶ querying DB for char_id=%s"):format(tostring(charId)))

    db:single(q, { charId }, function(row)
        if not row then
            dprint("loadFromDbForSource: ❌ no DB row for char", charId)
            cb(nil, "no-id")
            return
        end

        dprint(("loadFromDbForSource: ✅ got row for char=%s mugshotLen=%s"):format(
            tostring(row.char_id),
            row.mugshot and #row.mugshot or 0
        ))

        local infoTbl = {}
        if row.info and row.info ~= "" then
            local ok, decoded = pcall(json.decode, row.info)
            if ok and type(decoded) == "table" then
                infoTbl = decoded
            else
                dprint("loadFromDbForSource: info JSON decode failed, ignoring")
            end
        end

        local stored = {
            mugshot = row.mugshot,
            issued  = row.issued,
            expires = row.expires,
            charId  = row.char_id,
            discord = row.discord_id,
            info    = infoTbl
        }

        cb(stored, nil)
    end)
end

local function splitName(full)
    if not full or full == "" then return "UNKNOWN", "" end
    local fn, ln = full:match("^(%S+)%s+(.+)$")
    if not fn then
        return full, ""
    end
    return fn, ln
end

local function normalizeCharIdToString(charId)
    if type(charId) == "number" then

        return string.format("%.0f", charId)
    end

    local s = tostring(charId)

    local integerPart = s:match("^(%d+)%.0$")
    if integerPart then
        return integerPart
    end
    return s
end

local function getCharacterNameFromDb(charId, discordId, cb)
    if not db then
        dprint("getCharacterNameFromDb: ❌ no DB, skipping")
        cb(nil, "no-db")
        return
    end

    if not charId then
        dprint("getCharacterNameFromDb: ❌ missing charId")
        cb(nil, "no-ids")
        return
    end

    local charStr    = normalizeCharIdToString(charId)
    local discordStr = discordId and tostring(discordId) or nil

    local function tryCharOnly()
        local q2 = ([[SELECT name FROM %s WHERE charid = ? LIMIT 1]]):format(CHAR_TABLE)
        dprint(("getCharacterNameFromDb: ▶ fallback query (char only) %s charid=%s"):format(
            CHAR_TABLE, charStr
        ))
        db:single(q2, { charStr }, function(row2)
            if row2 and row2.name and row2.name ~= "" then
                dprint(("getCharacterNameFromDb: ✅ found name '%s' (char only)"):format(row2.name))
                cb(row2.name, nil)
            else
                dprint("getCharacterNameFromDb: ❌ no row for charid only")
                cb(nil, "no-row")
            end
        end)
    end

    if discordStr and discordStr ~= "" then
        local q1 = ([[SELECT name FROM %s WHERE discordid = ? AND charid = ? LIMIT 1]]):format(CHAR_TABLE)
        dprint(("getCharacterNameFromDb: ▶ primary query %s discordid=%s charid=%s"):format(
            CHAR_TABLE, discordStr, charStr
        ))

        db:single(q1, { discordStr, charStr }, function(row)
            if row and row.name and row.name ~= "" then
                dprint(("getCharacterNameFromDb: ✅ found name '%s' (discord+char)"):format(row.name))
                cb(row.name, nil)
            else
                dprint("getCharacterNameFromDb: ⚠ no row on discord+char, trying char only")
                tryCharOnly()
            end
        end)
    else
        tryCharOnly()
    end
end

local function resolveCharacterNameFallback(src)
    local name = GetPlayerName(src) or "Unknown"
    dprint(("resolveCharacterNameFallback: using GetPlayerName(): '%s'"):format(name))
    return name
end

local function getAllowedLicenseStatuses()
    local list = Config.DriverLicenseAllowedStatuses
    if type(list) ~= "table" or #list == 0 then

        list = { "VALID", "ACTIVE", "APPROVED", "PASSED" }
    end

    local out = {}
    for i = 1, #list do
        out[i] = string.upper(tostring(list[i]))
    end
    return out
end

local function isStatusAllowed(status, allowed)
    local s = string.upper(tostring(status or ""))
    for i = 1, #allowed do
        if s == allowed[i] then return true end
    end
    return false
end

local function hasDriverLicenseForSource(src, cb)
    if not db then
        cb(false, "no-db")
        return
    end

    local charId, discordId = getIdentityIds(src)
    if not charId then
        cb(false, "no-identity")
        return
    end

    local allowed   = getAllowedLicenseStatuses()
    local charStr   = normalizeCharIdToString(charId)
    local discStr   = discordId and tostring(discordId) or ""

    local function finish(row)
        local status = row and row.license_status or "UNKNOWN"
        cb(isStatusAllowed(status, allowed), status)
    end

    local function tryCharOnly()
        local q = ([[SELECT license_status FROM %s WHERE charid = ? LIMIT 1]]):format(CHAR_TABLE)
        db:single(q, { charStr }, function(row) finish(row) end)
    end

    if discStr ~= "" then
        local q = ([[SELECT license_status FROM %s WHERE discordid = ? AND charid = ? LIMIT 1]]):format(CHAR_TABLE)
        db:single(q, { discStr, charStr }, function(row)
            if row then finish(row) else tryCharOnly() end
        end)
    else
        tryCharOnly()
    end
end

RegisterNetEvent("az-id:checkDriverLicense", function()
    local src = source
    hasDriverLicenseForSource(src, function(ok, status)
        TriggerClientEvent("az-id:driverLicenseStatus", src, ok, status)
    end)
end)

local function getIdCardDataForSource(src, cb)
    dprint("getIdCardDataForSource: 🔍 START for src", src)

    loadFromDbForSource(src, function(stored, loadReason)
        dprint(("getIdCardDataForSource: after loadFromDbForSource reason=%s stored?=%s"):format(
            loadReason or "nil",
            stored and "yes" or "no"
        ))

        if not stored then
            cb(nil, loadReason or "no-id")
            return
        end

        if not stored.mugshot or stored.mugshot == "" then
            dprint("getIdCardDataForSource: ❌ stored row has NO mugshot")
            cb(nil, "no-photo")
            return
        end

        local info    = stored.info or {}
        local charId  = stored.charId
        local discord = stored.discord

        getCharacterNameFromDb(charId, discord, function(dbName, dbReason)
            local fullName
            local nameSource

            if dbName and dbName ~= "" then
                fullName   = dbName
                nameSource = "user_characters"
            else
                fullName   = resolveCharacterNameFallback(src)
                nameSource = "fallback"
                dprint(("getIdCardDataForSource: using fallback name '%s' (reason=%s)"):format(
                    fullName,
                    dbReason or "n/a"
                ))
            end

            local fn, ln = splitName(fullName)

            dprint(("getIdCardDataForSource: building card using name='%s' (source=%s) fn='%s' ln='%s'"):format(
                fullName, nameSource, fn, ln
            ))

            local addr1  = info.addr1 or Config.DefaultAddress  or ""
            local addr2  = info.addr2 or Config.DefaultAddress2 or ""

            local issued  = stored.issued  or os.time()
            local expires = stored.expires or (issued + (Config.ExpiryDays or (365 * 5)) * 86400)

            local card = {
                dl        = tostring(stored.charId or "00000000"),
                exp       = os.date("%m/%d/%Y", expires),

                class     = info.class or Config.DefaultClass         or "C",
                ["end"]   = info["end"] or Config.DefaultEndorsements or "NONE",

                ln        = ln,
                fn        = fn,

                addr1     = addr1,
                addr2     = addr2,

                dob       = info.dob or Config.DefaultDOB          or "01/01/1990",
                sex       = info.sex or Config.DefaultSex          or "U",
                hgt       = info.hgt or Config.DefaultHeight       or "5'-10\"",
                wgt       = info.wgt or Config.DefaultWeight       or "180 lb",
                hair      = info.hair or Config.DefaultHair        or "BRN",
                eyes      = info.eyes or Config.DefaultEyes        or "BRN",
                rst       = info.rst or Config.DefaultRestrictions or "NONE",

                dd        = info.dd  or Config.DefaultDD           or "N/A",
                iss       = info.iss or os.date("%m/%d/%Y", issued),
                idnum     = tostring(stored.charId or "000000"),
                signature = (info.signature and info.signature ~= "" and info.signature)
                            or (fn .. " " .. ln),

                mugshot   = stored.mugshot
            }

            dprint(("getIdCardDataForSource: ✅ built card: dl=%s exp=%s mugshotLen=%s fn='%s' ln='%s'"):format(
                card.dl, card.exp, card.mugshot and #card.mugshot or 0, card.fn, card.ln
            ))

            cb(card, nil)
        end)
    end)
end

RegisterNetEvent("az-id:saveMugshotAndInfo", function(mugshot, info)
    local src = source
    dprint("saveMugshotAndInfo: from", src)

    hasDriverLicenseForSource(src, function(hasLicense, status)
        if not hasLicense then
            TriggerClientEvent("az-id:notify", src,
                ("~r~DMV~s~: You need a valid driver's license to use this DMV station. (status: %s)"):format(tostring(status))
            )
            return
        end

        if not mugshot or mugshot == "" then
            dprint("saveMugshotAndInfo: ❌ empty mugshot")
            return
        end

        local charId, discordId = getIdentityIds(src)
        if not charId then
            TriggerClientEvent("az-id:notify", src,
                "~r~DMV~s~: Unable to link this photo to your character (no active character).")
            return
        end

        local now       = os.time()
        local days      = Config.ExpiryDays or (365 * 5)
        local expiresAt = now + (days * 24 * 60 * 60)

        local infoTable = {}
        if type(info) == "table" then
            for k, v in pairs(info) do
                if v ~= nil and v ~= "" then
                    infoTable[k] = v
                end
            end
        end

        dprint(("saveMugshotAndInfo: char=%s disc=%s mugshotLen=%s infoKeys=%s"):format(
            tostring(charId),
            tostring(discordId),
            #mugshot,
            infoTable and tostring(#(infoTable)) or "0"
        ))

        saveToDb(charId, discordId, mugshot, now, expiresAt, infoTable)

        TriggerClientEvent("az-id:notify", src,
            "~g~DMV~s~: Your ID has been issued. Use /showid near others to show it.")
    end)
end)

RegisterNetEvent("az-id:saveMugshot", function(mugshot)
    TriggerEvent("az-id:saveMugshotAndInfo", mugshot, nil)
end)

RegisterNetEvent("az-id:showMyIdRadius", function()
    local src = source
    dprint("showMyIdRadius: 🔔 from", src)

    getIdCardDataForSource(src, function(card, reason)
        dprint("showMyIdRadius: callback reason", reason or "nil",
            "card?", card and "yes" or "no")

        if not card then
            if reason == "no-id" or reason == "no-photo" then
                TriggerClientEvent("az-id:notify", src,
                    "~r~This character does not have an ID yet.~s~ Visit the DMV to get one.")
            elseif reason == "no-db" then
                TriggerClientEvent("az-id:notify", src,
                    "~r~ID system DB not online (oxmysql).")
            else
                TriggerClientEvent("az-id:notify", src,
                    "~r~Could not build ID card (no active character / bad data?).")
            end
            return
        end

        local radius   = Config.ShowRadius or 5.0
        local srcPed   = GetPlayerPed(src)
        local srcCoord = GetEntityCoords(srcPed)

        dprint("showMyIdRadius: ✅ sending displayId to SELF", src)
        TriggerClientEvent("az-id:displayId", src, card)

        for _, id in ipairs(GetPlayers()) do
            local ply = tonumber(id)
            if ply ~= src then
                local ped  = GetPlayerPed(ply)
                local dist = #(GetEntityCoords(ped) - srcCoord)
                if dist <= radius then
                    dprint(("showMyIdRadius: → sending displayId to %s (dist=%.2f)"):format(ply, dist))
                    TriggerClientEvent("az-id:displayId", ply, card)
                end
            end
        end
    end)
end)

RegisterNetEvent("az-id:requestId", function(target)
    local src = source
    target    = tonumber(target)

    if not target or src == target then return end

    if not GetPlayerName(target) then
        TriggerClientEvent("az-id:notify", src, "That player is no longer online.")
        return
    end

    dprint(("requestId: %s asking %s"):format(src, target))
    TriggerClientEvent("az-id:promptShowId", target, src)
end)

RegisterNetEvent("az-id:respondRequest", function(requester, accepted)
    local src = source
    requester = tonumber(requester)

    if not requester or not GetPlayerName(requester) then
        return
    end

    dprint(("respondRequest: %s -> %s accepted=%s"):format(
        src, requester, tostring(accepted)
    ))

    if not accepted then
        TriggerClientEvent("az-id:notify", requester, "They refused to show their ID.")
        return
    end

    getIdCardDataForSource(src, function(card, reason)
        if not card then
            if reason == "no-id" or reason == "no-photo" then
                TriggerClientEvent("az-id:notify", src,
                    "~r~You don't have an ID yet.~s~ Visit the DMV to get one.")
                TriggerClientEvent("az-id:notify", requester,
                    "This character does not have an ID yet.")
            else
                TriggerClientEvent("az-id:notify", src,
                    "~r~Could not build ID card (no active character / bad data?).")
            end
            return
        end

        dprint("respondRequest: ✅ sending displayId to requester", requester)
        TriggerClientEvent("az-id:displayId", requester, card)
    end)
end)

RegisterCommand("servertestid", function(src, args, raw)
    if src == 0 then
        print("[Az-Id S] /servertestid must be run by a player, not console.")
        return
    end

    local fullName = GetPlayerName(src) or "Unknown"
    local fn, ln   = splitName(fullName)

    local card = {
        dl        = "SRVTEST1",
        exp       = "01/01/2030",
        class     = "C",
        ["end"]   = "NONE",

        ln        = ln,
        fn        = fn,

        addr1     = "TEST ADDRESS,",
        addr2     = "SAN ANDREAS",

        dob       = "01/01/1990",
        sex       = "U",
        hgt       = "5'-10\"",
        wgt       = "180 lb",

        hair      = "BRN",
        eyes      = "BRN",
        rst       = "NONE",

        dd        = "N/A",
        iss       = "01/01/2025",
        idnum     = "TEST01",
        signature = fn .. " " .. ln,

        mugshot   = nil
    }

    dprint(("servertestid: sending displayId to %s"):format(src))
    TriggerClientEvent("az-id:displayId", src, card)
end, false)
