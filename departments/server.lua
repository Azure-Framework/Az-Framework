local RESOURCE = GetCurrentResourceName()

local function dprint(msg)
    print(("[az-fw-departments] %s"):format(tostring(msg)))
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

local function getDiscordUserId(src)

    local did = exports["Az-Framework"]:getDiscordID(src)
    did = tostring(did or "")
    if did ~= "" and did ~= "nil" then return did end

    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        local discordId = id:match('^discord:(%d+)$')
        if discordId then return discordId end
    end
    return nil
end

local DISCORD_BOT_TOKEN = GetConvar("DISCORD_BOT_TOKEN", "")
local DISCORD_GUILD_ID  = GetConvar("DISCORD_GUILD_ID", "")

local function fetchDiscordRoles(discordId, cb)
    if DISCORD_BOT_TOKEN == "" or DISCORD_GUILD_ID == "" then
        dprint("[Debug] DISCORD_BOT_TOKEN or DISCORD_GUILD_ID convar missing.")
        return cb({})
    end

    local url = ('https://discord.com/api/v10/guilds/%s/members/%s'):format(DISCORD_GUILD_ID, discordId)
    PerformHttpRequest(url, function(status, body)
        if status ~= 200 then
            dprint(('[Debug] Failed to fetch roles for %s: %s'):format(discordId, status))
            return cb({})
        end

        local ok, member = pcall(json.decode, body)
        if not ok or type(member) ~= 'table' or type(member.roles) ~= 'table' then
            dprint(('[Debug] Invalid Discord response for %s'):format(discordId))
            return cb({})
        end

        cb(member.roles)
    end, 'GET', '', {
        ['Authorization'] = 'Bot ' .. DISCORD_BOT_TOKEN,
        ['Content-Type']  = 'application/json'
    })
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
            discordCol   = pick("discordid","discord_id","discord"),
            charCol      = pick("charid","char_id","char","cid"),
            deptCol      = pick("department","dept","job"),
            paycheckCol  = pick("paycheck","salary","pay")
        }

        deptSchemaCache = schema

        dprint(('[Debug] econ_departments columns = %s'):format(#names > 0 and table.concat(names, ", ") or "(none)"))
        dprint(('[Debug] detected schema: discordCol=%s charCol=%s deptCol=%s paycheckCol=%s')
            :format(tostring(schema.discordCol), tostring(schema.charCol), tostring(schema.deptCol), tostring(schema.paycheckCol)))

        cb(schema)
    end)
end

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
    if v ~= "" and v ~= "nil" and not seen[v] then
        seen[v] = true
        list[#list+1] = v
    end
end

RegisterServerEvent('az-fw-departments:requestDeptList')
AddEventHandler('az-fw-departments:requestDeptList', function()
    local src = source

    local discordUserId = getDiscordUserId(src)
    local charId = toCharId(GetPlayerCharacter(src))

    dprint(('[Debug] requestDeptList: src=%s discordUserId=%s charId=%s')
        :format(src, tostring(discordUserId), tostring(charId)))

    detectDeptSchema(function(schema)

        if not schema or not schema.deptCol then
            dprint("[Debug] requestDeptList: econ_departments missing department column. Returning empty list.")
            TriggerClientEvent('az-fw-departments:openJobsDialog', src, {})
            return
        end

        local function finalizeQuery(roleIdsMerged)
            roleIdsMerged = roleIdsMerged or {}

            local ids, seen = {}, {}

            for _, rid in ipairs(roleIdsMerged) do addUnique(ids, seen, rid) end
            if charId then addUnique(ids, seen, charId) end
            if discordUserId then addUnique(ids, seen, discordUserId) end

            dprint(('[Debug] requestDeptList: candidate ids count=%d'):format(#ids))
            if #ids == 0 then
                TriggerClientEvent('az-fw-departments:openJobsDialog', src, {})
                return
            end

            local inClause, params = buildInParams(ids, "id")

            local whereParts = {}
            if schema.discordCol then
                whereParts[#whereParts+1] = ("`%s` IN (%s)"):format(schema.discordCol, inClause)
            end
            if schema.charCol then
                whereParts[#whereParts+1] = ("`%s` IN (%s)"):format(schema.charCol, inClause)
            end

            if #whereParts == 0 then
                dprint("[Debug] requestDeptList: econ_departments has neither discord nor char columns.")
                TriggerClientEvent('az-fw-departments:openJobsDialog', src, {})
                return
            end

            local sql = ("SELECT `%s` AS department FROM econ_departments WHERE %s"):format(
                schema.deptCol,
                table.concat(whereParts, " OR ")
            )

            dprint('[Debug] requestDeptList SQL = ' .. sql)

            MySQL.Async.fetchAll(sql, params, function(rows)
                rows = rows or {}
                dprint(('[Debug] requestDeptList: rows=%d'):format(#rows))

                local list, deptSeen = {}, {}
                for _, r in ipairs(rows) do
                    local dept = r.department
                    if dept and dept ~= "" and not deptSeen[dept] then
                        deptSeen[dept] = true
                        list[#list+1] = dept
                    end
                end

                dprint(('[Debug] requestDeptList: departments=%s'):format(#list > 0 and table.concat(list, ", ") or "(none)"))
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

                        dprint(('[Debug] requestDeptList: liveRoles=%d storedRoles=%d merged=%d')
                            :format(#liveRoles, #rows, #merged))

                        finalizeQuery(merged)
                    end
                )
            end)
        else
            finalizeQuery({})
        end
    end)
end)

RegisterNetEvent("az-fw-departments:setJob", function(job)
    local src = source
    job = tostring(job or "")

    local cid = toCharId(GetPlayerCharacter(src))
    if not cid then
        dprint(("[setJob] denied: no active character for src=%s"):format(src))
        TriggerClientEvent("ox_lib:notify", src, {
            title = "Departments",
            description = "No active character selected.",
            type = "error"
        })
        return
    end

    local did = getDiscordUserId(src)
    did = tostring(did or "")
    if did == "" or did == "nil" then
        dprint(("[setJob] denied: no discord id for src=%s"):format(src))
        TriggerClientEvent("ox_lib:notify", src, {
            title = "Departments",
            description = "Discord not linked.",
            type = "error"
        })
        return
    end

    dprint(("[setJob] src=%s did=%s cid=%s job=%s"):format(src, did, cid, job))

    MySQL.Async.execute(
        "UPDATE user_characters SET active_department = ? WHERE discordid = ? AND charid = ?",
        { job, did, cid },
        function(affected)
            dprint(("[setJob] updated rows=%s"):format(tostring(affected)))

            TriggerClientEvent("az-fw-departments:refreshJob", src, { job = job })
            TriggerClientEvent("hud:setDepartment", src, job)

            if Player and Player(src) and Player(src).state then
                Player(src).state:set("job", job, true)
                Player(src).state:set("department", job, true)
            end

            TriggerClientEvent("ox_lib:notify", src, {
                title = "Departments",
                description = ("On-duty as: %s"):format(job ~= "" and job or "None"),
                type = "success"
            })
        end
    )
end)

RegisterNetEvent("az-fw-departments:setActive", function(job)
    TriggerEvent("az-fw-departments:setJob", job)
end)

RegisterNetEvent("hud:requestDepartment", function()
    local src = source
    local did = getDiscordUserId(src)
    local cid = toCharId(GetPlayerCharacter(src))

    if not did or not cid then
        TriggerClientEvent("hud:setDepartment", src, "")
        return
    end

    MySQL.Async.fetchAll(
        "SELECT active_department FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1",
        { did, cid },
        function(rows)
            local job = ""
            if rows and rows[1] and rows[1].active_department then
                job = tostring(rows[1].active_department or "")
            end
            TriggerClientEvent("hud:setDepartment", src, job)
        end
    )
end)
