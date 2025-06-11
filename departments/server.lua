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
        ]], {}, function(rowsChanged)
            print('[az-fw-departments] Ensured table econ_user_money exists.')
        end)

        -- Create departments table if it doesn't exist
        MySQL.Async.execute([[ 
            CREATE TABLE IF NOT EXISTS `econ_departments` (
                `discordid` VARCHAR(255) NOT NULL PRIMARY KEY,
                `department` VARCHAR(100) NOT NULL,
                `paycheck` INT NOT NULL DEFAULT 0
            )
        ]], {}, function(rowsChanged)
            print('[az-fw-departments] Ensured table econ_departments exists.')
        end)
    end)

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

    -- Utility: refresh money HUD for a player
    local function sendMoneyToClient(playerId, discordId)
        MySQL.Async.fetchScalar(
            'SELECT cash FROM econ_user_money WHERE discordid = @id',
            { ['@id'] = discordId },
            function(cash)
                TriggerClientEvent('az-fw-departments:refreshMoney', playerId, { cash = cash or 0 })
            end
        )
    end

    -- **New** Utility: refresh job HUD for a player
function sendJobToClient(playerId, discordId)
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
function FetchDepartments(callback)
    -- MySQL.Async.fetchAll is asynchronous. We pass the rows into the callback when ready.
    MySQL.Async.fetchAll(
        'SELECT discordid, department, paycheck FROM econ_departments',
        {},
        function(rows)
            -- rows is an array of results: { { discordid = ..., department = ..., paycheck = ... }, ... }
            if type(callback) == "function" then
                callback(rows)
            end
        end
    )
end

    -- Fetch all departments
    RegisterServerEvent('az-fw-departments:requestDepartments')
    AddEventHandler('az-fw-departments:requestDepartments', function(cbId)
        local src = source
        MySQL.Async.fetchAll(
            'SELECT discordid, department, paycheck FROM econ_departments',
            {},
            function(rows)
                TriggerClientEvent('az-fw-departments:nuiResponse', src, cbId, { departments = rows })
            end
        )
    end)

    -- Update a department’s data
RegisterServerEvent('hud:requestDepartment')
 AddEventHandler('hud:requestDepartment', function()
   local src = source
   local discordId = getDiscordId(src)
  if not discordId then
    TriggerClientEvent('hud:setDepartment', src, 'Unknown')
    return
  end

  -- Query their department and send it to the HUD
  MySQL.Async.fetchScalar(
    'SELECT department FROM econ_departments WHERE discordid = @id',
    { ['@id'] = discordId },
    function(dept)
      TriggerClientEvent('hud:setDepartment', src, dept or 'Unemployed')
    end
  )
 
   -- **NEW**: only send via the unified helper
   sendJobToClient(src, discordId)
 end)

    -- Distribute paychecks to all users in each department
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
                        function(_)
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
                                    -- update money HUD
                                    sendMoneyToClient(playerId, dept.discordid)
                                    -- update job HUD (in case they switched department)
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

    -- Schedule distributePaychecks every interval defined in Config.paycheckInterval
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Config.paycheckInterval)
            distributePaychecks()
        end
    end)

    -- Handle department request from client HUD
    RegisterServerEvent('hud:requestDepartment')
    AddEventHandler('hud:requestDepartment', function()
        local src = source
        print('[DEBUG] Server received hud:requestDepartment from player id =', src)

        -- Dump all identifiers for sanity
        print('[DEBUG] Identifiers for', src, ':')
        for _, ident in ipairs(GetPlayerIdentifiers(src)) do
            print('   →', ident)
        end

        -- Attempt to get Discord ID
        local discordId = getDiscordId(src)
        print('[DEBUG] getDiscordId returned =', tostring(discordId))

        if not discordId then
            print('[DEBUG] Could not get a Discord ID for player', src)
            -- send default job
            TriggerClientEvent('hud:setDepartment', src, 'Unknown')
            return
        end

        -- Query their department and send it to the HUD
        MySQL.Async.fetchScalar(
            'SELECT department FROM econ_departments WHERE discordid = @id',
            { ['@id'] = discordId },
            function(dept)
                print('[DEBUG] SQL returned department =', tostring(dept))
                TriggerClientEvent('hud:setDepartment', src, dept or 'Unemployed')
            end
        )

        -- **New**: also immediately send their job to the in‐game HUD
        sendJobToClient(src, discordId)
    end)

else
    print('[az-fw-departments] Departments False. Departments WILL NOT WORK')
end

-- Function to fetch all departments
local function getDepartments(callback)
    MySQL.Async.fetchAll(
        'SELECT discordid, department, paycheck FROM econ_departments',
        {},
        function(rows)
            if callback then
                callback(rows)
            end
        end
    )
end

-- Export the function for other server scripts to use
exports('getDepartments', getDepartments)
