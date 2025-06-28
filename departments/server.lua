if Config.Departments then
    print('[az-fw-departments] Departments True, Initializing...')
    print('[DEBUG] server.lua loaded')

    -- Wait for MySQL-Async to be ready and ensure your tables exist
    MySQL.ready(function()
        print('[az-fw-departments] MySQL-Async ready!')

        -- Create user money table if it doesn't exist
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `econ_user_money` (
                `discordid` VARCHAR(255) NOT NULL PRIMARY KEY,
                `cash` INT NOT NULL DEFAULT 0,
                `bank` INT NOT NULL DEFAULT 0,
                `last_daily` BIGINT NOT NULL DEFAULT 0
            )
        ]], {}, function()
            print('[az-fw-departments] Ensured table econ_user_money exists.')
        end)

        -- Create departments table if it doesn't exist
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `econ_departments` (
                `discordid` VARCHAR(255) NOT NULL PRIMARY KEY,
                `department` VARCHAR(100) NOT NULL,
                `paycheck` INT NOT NULL DEFAULT 0
            )
        ]], {}, function()
            print('[az-fw-departments] Ensured table econ_departments exists.')
        end)
    end)

    ----------------------------------------------------------------
    -- Utility: get the Discord ID from a player’s identifiers
    local function getDiscordId(playerId)
        print('[DEBUG] getDiscordId called for player', playerId)
        for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
            print('   [DEBUG] identifier:', id)
            if id:match('^discord:') then
                local clean = id:gsub('discord:', '')
                print('[DEBUG] extracted discord id =', clean)
                return clean
            end
        end
        print('[DEBUG] no discord id found for player', playerId)
        return nil
    end

    ----------------------------------------------------------------
    -- Utility: refresh money HUD for a player, now returns both cash and checking‐bank
    local function sendMoneyToClient(playerId, discordId)
        -- 1) fetch wallet cash
        MySQL.Async.fetchScalar(
            'SELECT cash FROM econ_user_money WHERE discordid = @id',
            { ['@id'] = discordId },
            function(cash)
                cash = cash or 0

                -- 2) fetch checking account balance
                MySQL.Async.fetchScalar(
                    "SELECT balance FROM econ_accounts WHERE discordid = @id AND type = 'checking'",
                    { ['@id'] = discordId },
                    function(bank)
                        bank = bank or 0

                        -- 3) send both values to client
                        TriggerClientEvent('az-fw-departments:refreshMoney', playerId, {
                            cash = cash,
                            bank = bank
                        })
                    end
                )
            end
        )
    end


    -- Utility: refresh job HUD for a player
    local function sendJobToClient(playerId, discordId)
        if not discordId then
            TriggerClientEvent('az-fw-departments:refreshJob', playerId, { job = "Unknown" })
            return
        end

        MySQL.Async.fetchScalar(
            'SELECT department FROM econ_departments WHERE discordid = @id',
            { ['@id'] = discordId },
            function(department)
                local job = department or "Unemployed"
                print("DEBUG: Sending job to player", playerId, "->", job)
                TriggerClientEvent('az-fw-departments:refreshJob', playerId, { job = job })
            end
        )
    end

    ----------------------------------------------------------------
    -- Admin login handler
    RegisterServerEvent('az-fw-departments:attemptAdminLogin')
    AddEventHandler('az-fw-departments:attemptAdminLogin', function(username, password, cbId)
        local src = source
        MySQL.Async.fetchScalar(
            'SELECT password FROM econ_admins WHERE username = @u',
            { ['@u'] = username },
            function(dbHash)
                local ok = (dbHash ~= nil and dbHash == password)
                TriggerClientEvent('az-fw-departments:nuiResponse', src, cbId, { success = ok })
            end
        )
    end)

    -- Fetch all users
    RegisterServerEvent('az-fw-departments:requestUsers')
    AddEventHandler('az-fw-departments:requestUsers', function(cbId)
        local src = source
        MySQL.Async.fetchAll(
            'SELECT discordid, cash, bank FROM econ_user_money',
            {},
            function(rows)
                TriggerClientEvent('az-fw-departments:nuiResponse', src, cbId, { users = rows })
            end
        )
    end)

    -- Update a user’s cash & bank
    RegisterServerEvent('az-fw-departments:updateUserMoney')
    AddEventHandler('az-fw-departments:updateUserMoney', function(discordid, cash, bank, cbId)
        local src = source
        MySQL.Async.execute(
            [[
            INSERT INTO econ_user_money (discordid, cash, bank)
            VALUES (@id, @c, @b)
            ON DUPLICATE KEY UPDATE
                cash = @c,
                bank = @b
            ]],
            {
                ['@id'] = discordid,
                ['@c']  = tonumber(cash) or 0,
                ['@b']  = tonumber(bank) or 0,
            },
            function(affected)
                local ok = (affected > 0)
                TriggerClientEvent('az-fw-departments:nuiResponse', src, cbId, { success = ok })
            end
        )
    end)

    ----------------------------------------------------------------
    -- HUD update handler (single registration)
    RegisterServerEvent('hud:requestDepartment')
    AddEventHandler('hud:requestDepartment', function()
        local src = source
        print('[DEBUG] Server received hud:requestDepartment from player id =', src)

        -- Dump all identifiers for sanity
        for _, ident in ipairs(GetPlayerIdentifiers(src)) do
            print('   →', ident)
        end

        -- Attempt to get Discord ID
        local discordId = getDiscordId(src)
        print('[DEBUG] getDiscordId returned =', tostring(discordId))

        if not discordId then
            print('[DEBUG] Could not get a Discord ID for player', src)
            TriggerClientEvent('hud:setDepartment', src, 'Unknown')
            return
        end

        -- Send HUD updates
        sendJobToClient(src, discordId)
        sendMoneyToClient(src, discordId)
    end)

    ----------------------------------------------------------------
    -- Distribute paychecks every Config.paycheckInterval
    local function distributePaychecks()
        print('[DEBUG] distributePaychecks started')
        MySQL.Async.fetchAll(
            'SELECT discordid, department, paycheck FROM econ_departments',
            {},
            function(depts)
                print('[DEBUG] Retrieved departments:', json.encode(depts))
                for _, dept in ipairs(depts) do
                    MySQL.Async.execute(
                        [[
                        INSERT INTO econ_user_money (discordid, cash)
                        VALUES (@id, @pay)
                        ON DUPLICATE KEY UPDATE
                            cash = cash + @pay
                        ]],
                        {
                            ['@id']  = dept.discordid,
                            ['@pay'] = dept.paycheck,
                        },
                        function()
                            for _, playerId in ipairs(GetPlayers()) do
                                if getDiscordId(playerId) == dept.discordid then
                                    -- send ox_lib notification
                                    TriggerClientEvent('ox_lib:notify', playerId, {
                                        title       = 'Paycheck',
                                        description = string.format('You received $%s from your department.', dept.paycheck),
                                        type        = 'success',
                                        duration    = 5000,
                                        position    = 'top',
                                    })
                                    -- update HUD
                                    sendMoneyToClient(playerId, dept.discordid)
                                    sendJobToClient(playerId, dept.discordid)
                                    break
                                end
                            end
                        end
                    )
                end
            end
        )
    end

    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Config.paycheckInterval)
            distributePaychecks()
        end
    end)
else
    print('[az-fw-departments] Departments False. Departments WILL NOT WORK')
end

----------------------------------------------------------------
-- Exports

-- Fetch all departments
local function getDepartments(callback)
    MySQL.Async.fetchAll(
        'SELECT discordid, department, paycheck FROM econ_departments',
        {},
        function(rows)
            if type(callback) == "function" then
                callback(rows)
            end
        end
    )
end
exports('getDepartments', getDepartments)

-- Fetch a player's job name (department) from the database using their Discord ID
local function getPlayerJob(playerId, callback)
    local discordId = nil
    for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
        if id:match('^discord:') then
            discordId = id:gsub('discord:', '')
            break
        end
    end

    if not discordId then
        print(("[az-fw-departments] getPlayerJob: no discord ID for %d"):format(playerId))
        return callback("Unknown")
    end

    MySQL.Async.fetchScalar(
        'SELECT department FROM econ_departments WHERE discordid = @id',
        { ['@id'] = discordId },
        function(department)
            local job = department or "Unemployed"
            print(("[az-fw-departments] getPlayerJob: %d → Job: %s"):format(playerId, job))
            callback(job)
        end
    )
end


exports('getPlayerJob', getPlayerJob)