if Config.Departments then
    print('[az-fw-departments-server] Departments enabled, initializing...')

    -- Utility: fetch Discord ID
    local function getDiscordId(playerId)
        for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
            if id:match('^discord:') then
                return id:gsub('discord:', '')
            end
        end
        return nil
    end

    -- Ensure tables exist
    MySQL.ready(function()
        -- user money table
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `econ_user_money` (
                `discordid` VARCHAR(255) NOT NULL,
                `cash` INT NOT NULL DEFAULT 0,
                `bank` INT NOT NULL DEFAULT 0,
                `last_daily` BIGINT NOT NULL DEFAULT 0,
                PRIMARY KEY (`discordid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]], {}, function() print('[az-fw] econ_user_money ready') end)

        -- departments table (composite PK to allow multiple per user)
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `econ_departments` (
                `discordid` VARCHAR(255) NOT NULL,
                `department` VARCHAR(100) NOT NULL,
                `paycheck` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`discordid`, `department`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]], {}, function() print('[az-fw] econ_departments ready') end)
    end)

    -- Send on-duty job
    local function sendJobToClient(playerId)
        local job = Player(playerId).state.job or 'Unemployed'
        TriggerClientEvent('az-fw-departments:refreshJob', playerId, { job = job })
    end

    -- Send money HUD: cash from econ_user_money + checking from econ_accounts
    local function sendMoneyToClient(playerId)
        local discordId = getDiscordId(playerId)
        if not discordId then return end

        MySQL.Async.fetchScalar(
            'SELECT cash FROM econ_user_money WHERE discordid = @id',
            { ['@id'] = discordId },
            function(cash)
                cash = cash or 0
                MySQL.Async.fetchScalar(
                    [[
                      SELECT balance
                      FROM econ_accounts
                      WHERE discordid = @id
                        AND type = 'checking'
                    ]],
                    { ['@id'] = discordId },
                    function(bank)
                        bank = bank or 0
                        TriggerClientEvent('updateCashHUD', playerId, cash, bank)
                    end
                )
            end
        )
    end

    -- /jobs dialog
    RegisterServerEvent('az-fw-departments:requestDeptList')
    AddEventHandler('az-fw-departments:requestDeptList', function()
        local src = source
        local discordId = getDiscordId(src)
        if not discordId then return end
        MySQL.Async.fetchAll(
            'SELECT department FROM econ_departments WHERE discordid = @id',
            { ['@id'] = discordId },
            function(rows)
                local depts = {}
                for _, r in ipairs(rows) do table.insert(depts, r.department) end
                TriggerClientEvent('az-fw-departments:openJobsDialog', src, depts)
            end
        )
    end)

    -- Set on-duty job
    RegisterServerEvent('az-fw-departments:setJob')
    AddEventHandler('az-fw-departments:setJob', function(deptName)
        local src = source
        Player(src).state.job = deptName
        TriggerClientEvent('chat:addMessage', src, {
            args = {'Jobs', '✅ On-duty set to ' .. deptName}
        })
        sendJobToClient(src)
    end)

    -- Distribute paychecks
    local function distributePaychecks()
        for _, pid in ipairs(GetPlayers()) do
            local discordId = getDiscordId(pid)
            local job = Player(pid).state.job
            if discordId and job then
                MySQL.Async.fetchScalar(
                    'SELECT paycheck FROM econ_departments WHERE discordid = @id AND department = @dept',
                    { ['@id'] = discordId, ['@dept'] = job },
                    function(pay)
                        if pay then
                            MySQL.Async.execute(
                                'INSERT INTO econ_user_money (discordid, cash) VALUES (@id,@pay) ON DUPLICATE KEY UPDATE cash = cash + @pay',
                                { ['@id'] = discordId, ['@pay'] = pay }
                            )
                            TriggerClientEvent('ox_lib:notify', pid, {
                                title       = 'Paycheck',
                                description = ('You received $%s from %s'):format(pay, job),
                                type        = 'success',
                                duration    = 5000,
                                position    = 'top',
                            })
                            sendMoneyToClient(pid)
                        end
                    end
                )
            end
        end
    end

    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Config.paycheckInterval)
            distributePaychecks()
        end
    end)


    -- Initial HUD request
    RegisterServerEvent('hud:requestDepartment')
    AddEventHandler('hud:requestDepartment', function()
        local src = source
        sendJobToClient(src)
        sendMoneyToClient(src)
    end)

    -- Exports
    exports('getDepartments', function(cb)
        MySQL.Async.fetchAll('SELECT discordid, department, paycheck FROM econ_departments', {}, cb)
    end)
    exports('getPlayerJob', function(playerId, cb)
        local job = Player(playerId).state.job
        cb(job or 'Unemployed')
    end)

else
    print('[az-fw-departments-server] Departments disabled; skipping department features.')
end
