-- [[ server.lua ]]  (az-fw-departments)
if Config.Departments then
    print('[az-fw-departments-server] Departments enabled, initializing...')

    ----------------------------------------------------------------
    -- Character Export Wrapper
    ----------------------------------------------------------------
    -- Wraps the export call to retrieve the active character ID
    local function GetPlayerCharacter(src)
        return exports['Az-Framework']:GetPlayerCharacter(src)
    end

    ----------------------------------------------------------------
    -- Discord API credentials (keep these secret!).
    ----------------------------------------------------------------
    local DISCORD_BOT_TOKEN = GetConvar("DISCORD_BOT_TOKEN", "")
    local DISCORD_GUILD_ID  = GetConvar("DISCORD_GUILD_ID", "")

    ----------------------------------------------------------------
    -- Utility: extract a player’s Discord user ID
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Fetch a guild member’s roles from Discord
    ----------------------------------------------------------------
    local function fetchDiscordRoles(discordId, cb)
        local url = ('https://discord.com/api/v10/guilds/%s/members/%s'):format(DISCORD_GUILD_ID, discordId)
        PerformHttpRequest(url, function(status, body)
            if status ~= 200 then
                print(('[Az-Dept-Debug] Failed to fetch roles for %s: %s'):format(discordId, status))
                return cb({})
            end
            local ok, member = pcall(json.decode, body)
            if not ok or type(member.roles) ~= 'table' then
                print(('[Az-Dept-Debug] Invalid Discord response for %s'):format(discordId))
                return cb({})
            end
            cb(member.roles)
        end, 'GET', '', {
            ['Authorization'] = 'Bot ' .. DISCORD_BOT_TOKEN,
            ['Content-Type']  = 'application/json'
        })
    end



    ----------------------------------------------------------------
    -- Request /jobs handler for selecting on-duty job
    ----------------------------------------------------------------
    RegisterServerEvent('az-fw-departments:requestDeptList')
    AddEventHandler('az-fw-departments:requestDeptList', function()
        local src = source
        local discordId = getDiscordUserId(src)
        if not discordId then return end

        fetchDiscordRoles(discordId, function(liveRoles)
            local storedRoles = {}
            MySQL.Async.fetchAll('SELECT roleid FROM econ_user_roles WHERE discordid = @id', {['@id']=discordId}, function(rows)
                for _, r in ipairs(rows) do table.insert(storedRoles, r.roleid) end

                local allRoles, seen = {}, {}
                for _, rid in ipairs(liveRoles) do seen[rid]=true; table.insert(allRoles,rid) end
                for _, rid in ipairs(storedRoles) do if not seen[rid] then table.insert(allRoles,rid) end end

                local ids, ph, params = {discordId}, {}, {}
                for i,id in ipairs(allRoles) do ids[#ids+1]=id end
                for i,id in ipairs(ids) do ph[#ph+1]='@id'..i; params['@id'..i]=id end
                local query = ('SELECT department FROM econ_departments WHERE discordid IN ('..table.concat(ph,',')..')')

                MySQL.Async.fetchAll(query, params, function(depts)
                    local list = {}
                    for _,d in ipairs(depts) do table.insert(list, d.department) end
                    TriggerClientEvent('az-fw-departments:openJobsDialog', src, list)
                end)
            end)
        end)
    end)

    ----------------------------------------------------------------
    -- Set on-duty job
    ----------------------------------------------------------------
    RegisterServerEvent('az-fw-departments:setJob')
    AddEventHandler('az-fw-departments:setJob', function(dept)
        local src       = source
        local discordId = getDiscordUserId(src)
        local charId    = exports['Az-Framework']:GetPlayerCharacter(src)

        if not discordId or not charId or charId == '' then
            print(('[Az-Dept-Debug] setJob: missing discordId or charId for player %s'):format(src))
            return
        end

        -- DEBUG: show exactly what we're about to run
        print(('[Az-Dept-Debug] setJob: UPDATE user_characters SET active_department=%s WHERE discordid=%s AND charid=%s')
            :format(dept, discordId, charId))

        MySQL.Async.execute([[
            UPDATE user_characters
            SET active_department = @dept
            WHERE discordid        = @discordId
            AND charid           = @charId
        ]], {
            ['@dept']      = dept,
            ['@discordId'] = discordId,
            ['@charId']    = charId,
        }, function(affected)
            -- report exactly how many rows got updated
            print(('[Az-Dept-Debug] setJob: updated %d row(s) for %s / %s'):format(affected, discordId, charId))
            TriggerClientEvent('az-fw-departments:refreshJob', src, { job = dept })
        end)
    end)

else
    print('[az-fw-departments-server] Departments disabled; skipping department features.')
end
