local DISCORD_BOT_TOKEN = GetConvar("DISCORD_BOT_TOKEN", "")
local DISCORD_GUILD_ID  = GetConvar("DISCORD_GUILD_ID", "")

local function getDiscordUserId(playerId)
    for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
        local discordId = id:match('^discord:(%d+)$')
        if discordId then return discordId end
    end
    return nil
end

local function GetPlayerCharacter(src)
    return exports['Az-Framework']:GetPlayerCharacter(src)
end

local function toCharId(ret)
    if ret == nil then return nil end
    if type(ret) == "number" then return tostring(ret) end
    if type(ret) == "string" then return (ret ~= "" and ret) or nil end
    if type(ret) == "table" then
        local v = ret.charid or ret.charId or ret.id or ret.cid or ret.character_id or ret.characterId
        if v ~= nil then
            local s = tostring(v)
            if s ~= "" and s ~= "nil" then return s end
        end
    end
    return nil
end

local function fetchDiscordRoles(discordId, cb)
    if DISCORD_BOT_TOKEN == "" or DISCORD_GUILD_ID == "" then
        print('[Az-Dept-Debug] DISCORD_BOT_TOKEN or DISCORD_GUILD_ID convar missing.')
        return cb({})
    end

    local url = ('https://discord.com/api/v10/guilds/%s/members/%s'):format(DISCORD_GUILD_ID, discordId)
    PerformHttpRequest(url, function(status, body)
        if status ~= 200 then
            print(('[Az-Dept-Debug] Failed to fetch roles for %s: %s'):format(discordId, status))
            return cb({})
        end

        local ok, member = pcall(json.decode, body)
        if not ok or type(member) ~= 'table' or type(member.roles) ~= 'table' then
            print(('[Az-Dept-Debug] Invalid Discord response for %s'):format(discordId))
            return cb({})
        end

        cb(member.roles)
    end, 'GET', '', {
        ['Authorization'] = 'Bot ' .. DISCORD_BOT_TOKEN,
        ['Content-Type']  = 'application/json'
    })
end

local function toCharId(ret)
    if ret == nil then return nil end
    if type(ret) == "number" then return tostring(ret) end
    if type(ret) == "string" then return (ret ~= "" and ret) or nil end
    if type(ret) == "table" then
        local v = ret.charid or ret.charId or ret.id or ret.cid or ret.character_id or ret.characterId
        if v ~= nil then
            local s = tostring(v)
            if s ~= "" and s ~= "nil" then return s end
        end
    end
    return nil
end

local function getDiscordUserId(playerId)
    for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
        local discordId = id:match('^discord:(%d+)$')
        if discordId then
            print(('[Az-Dept-Debug] Found Discord UserID for player %s: %s'):format(playerId, discordId))
            return discordId
        end
    end
    print(('[Az-Dept-Debug] No Discord UserID found for player %s'):format(playerId))
    return nil
end

local deptSchemaCache = nil

local function detectDeptSchema(cb)
    if deptSchemaCache then return cb(deptSchemaCache) end

    MySQL.Async.fetchAll([[
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'econ_departments'
    ]], {}, function(cols)
        cols = cols or {}
        local names = {}
        for _, r in ipairs(cols) do
            if r.COLUMN_NAME then
                names[#names+1] = r.COLUMN_NAME
            end
        end

        local function pick(...)
            local opts = { ... }
            for _, want in ipairs(opts) do
                for _, have in ipairs(names) do
                    if have:lower() == want:lower() then return have end
                end
            end
            return nil
        end

        local schema = {
            discordCol = pick("discordid","discord_id","discord"),
            charCol    = pick("charid","char_id","char","cid"),
            deptCol    = pick("department","dept"),
            paycheckCol= pick("paycheck","salary","pay")
        }

        deptSchemaCache = schema

        print(('[Az-Dept-Debug] econ_departments columns = %s'):format(table.concat(names, ", ")))
        print(('[Az-Dept-Debug] detected schema: discordCol=%s charCol=%s deptCol=%s paycheckCol=%s')
            :format(tostring(schema.discordCol), tostring(schema.charCol), tostring(schema.deptCol), tostring(schema.paycheckCol)))

        cb(schema)
    end)
end

RegisterServerEvent('az-fw-departments:requestDeptList')
AddEventHandler('az-fw-departments:requestDeptList', function()
    local src = source
    local discordUserId = getDiscordUserId(src)
    local charId = toCharId(GetPlayerCharacter(src))

    print(('[Az-Dept-Debug] requestDeptList: src=%s discordUserId=%s charId=%s')
        :format(src, tostring(discordUserId), tostring(charId)))

    local function buildInParams(values, prefix)
        local ph, params = {}, {}
        for i, v in ipairs(values) do
            local key = ('@%s%d'):format(prefix, i)
            ph[#ph+1] = key
            params[key] = v
        end
        return table.concat(ph, ','), params
    end

    local function addUnique(list, seen, v)
        v = tostring(v or "")
        if v ~= "" and not seen[v] then
            seen[v] = true
            list[#list+1] = v
        end
    end

    local function finalizeQuery(roleIdsMerged)
        roleIdsMerged = roleIdsMerged or {}

        local ids, seen = {}, {}

        for _, rid in ipairs(roleIdsMerged) do addUnique(ids, seen, rid) end

        if charId then addUnique(ids, seen, charId) end

        if discordUserId then addUnique(ids, seen, discordUserId) end

        print(('[Az-Dept-Debug] requestDeptList: candidate ids count=%d'):format(#ids))
        if #ids <= 50 then
            print('[Az-Dept-Debug] candidates=' .. table.concat(ids, ','))
        end

        if #ids == 0 then
            TriggerClientEvent('az-fw-departments:openJobsDialog', src, {})
            return
        end

        local inClause, p1 = buildInParams(ids, "id")
        local sql = ('SELECT department FROM econ_departments WHERE discordid IN (%s) OR charid IN (%s)'):format(inClause, inClause)

        print('[Az-Dept-Debug] requestDeptList SQL = ' .. sql)

        MySQL.Async.fetchAll(sql, p1, function(rows)
            rows = rows or {}
            print(('[Az-Dept-Debug] requestDeptList: rows=%d'):format(#rows))

            local list, deptSeen = {}, {}
            for _, r in ipairs(rows) do
                local dept = r.department
                if dept and dept ~= "" and not deptSeen[dept] then
                    deptSeen[dept] = true
                    list[#list+1] = dept
                end
            end

            print(('[Az-Dept-Debug] requestDeptList: departments=%s'):format(#list > 0 and table.concat(list, ", ") or "(none)"))
            TriggerClientEvent('az-fw-departments:openJobsDialog', src, list)
        end)
    end

    if discordUserId then
        fetchDiscordRoles(discordUserId, function(liveRoles)
            liveRoles = liveRoles or {}

            MySQL.Async.fetchAll(
                'SELECT roleid FROM econ_user_roles WHERE discordid = @id',
                { ['@id'] = discordUserId },
                function(rows)
                    rows = rows or {}

                    local merged, seen = {}, {}
                    for _, rid in ipairs(liveRoles) do addUnique(merged, seen, rid) end
                    for _, row in ipairs(rows) do
                        if row.roleid then addUnique(merged, seen, row.roleid) end
                    end

                    print(('[Az-Dept-Debug] requestDeptList: liveRoles=%d storedRoles=%d merged=%d')
                        :format(#liveRoles, #rows, #merged))

                    finalizeQuery(merged)
                end
            )
        end)
    else

        finalizeQuery({})
    end
end)
