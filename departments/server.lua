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
    -- Discord API credentials. Grabbed from Server.cfg
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
                print(('[az-fw-debug] Found Discord UserID for player %s: %s'):format(playerId, discordId))
                return discordId
            end
        end
        print(('[az-fw-debug] No Discord UserID found for player %s'):format(playerId))
        return nil
    end

    ----------------------------------------------------------------
    -- Fetch a guild member’s roles from Discord
    ----------------------------------------------------------------
    local function fetchDiscordRoles(discordId, cb)
        local url = ('https://discord.com/api/v10/guilds/%s/members/%s'):format(DISCORD_GUILD_ID, discordId)
        PerformHttpRequest(url, function(status, body)
            if status ~= 200 then
                print(('[az-fw-debug] Failed to fetch roles for %s: %s'):format(discordId, status))
                return cb({})
            end
            local ok, member = pcall(json.decode, body)
            if not ok or type(member.roles) ~= 'table' then
                print(('[az-fw-debug] Invalid Discord response for %s'):format(discordId))
                return cb({})
            end
            cb(member.roles)
        end, 'GET', '', {
            ['Authorization'] = 'Bot ' .. DISCORD_BOT_TOKEN,
            ['Content-Type']  = 'application/json'
        })
    end

    ----------------------------------------------------------------
    -- MySQL table setup
    ----------------------------------------------------------------
    MySQL.ready(function()
        MySQL.Async.execute([[CREATE TABLE IF NOT EXISTS `econ_user_money` (
            `discordid` VARCHAR(255) NOT NULL,
            `charid` VARCHAR(255) NOT NULL,
            `cash` INT NOT NULL DEFAULT 0,
            `bank` INT NOT NULL DEFAULT 0,
            `last_daily` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`discordid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {}, function() print('[az-fw-debug] econ_user_money table ensured') end)

        MySQL.Async.execute([[CREATE TABLE IF NOT EXISTS `econ_departments` (
            `discordid` VARCHAR(255) NOT NULL,
            `department` VARCHAR(100) NOT NULL,
            `paycheck` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`discordid`, `department`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {}, function() print('[az-fw-debug] econ_departments table ensured') end)

        MySQL.Async.execute([[CREATE TABLE IF NOT EXISTS `econ_user_roles` (
            `discordid` VARCHAR(255) NOT NULL,
            `roleid` VARCHAR(255) NOT NULL,
            PRIMARY KEY (`discordid`,`roleid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {}, function() print('[az-fw-debug] econ_user_roles table ensured') end)

        MySQL.Async.execute([[ALTER TABLE `user_characters` ADD COLUMN IF NOT EXISTS `active_department` VARCHAR(100) NOT NULL DEFAULT '';]], {}, function() end)
    end)

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
        local src, discordId = source, getDiscordUserId(source)
        if not discordId then return end
        MySQL.Async.execute('UPDATE user_characters SET active_department=@d WHERE discordid=@id', {['@d']=dept,['@id']=discordId})
        TriggerClientEvent('az-fw-departments:refreshJob', src, {job=dept})
    end)
else
    print('[az-fw-departments-server] Departments disabled; skipping department features.')
end
