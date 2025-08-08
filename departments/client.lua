if Config.Departments then
    print('[az-fw-departments-client] Departments enabled, initializing...')

    RegisterCommand('jobs', function()
        TriggerServerEvent('az-fw-departments:requestDeptList')
    end)

    RegisterNetEvent('az-fw-departments:openJobsDialog')
    AddEventHandler('az-fw-departments:openJobsDialog', function(depts)
        if not depts or #depts == 0 then
            lib.notify({
                id = 'no_jobs',
                title = 'Departments',
                description = 'No jobs available',
                type = 'error',
                icon = 'triangle-exclamation',
                position = 'top-right',
                duration = 3000,
                showDuration = true
            })
            return
        end

        local opts = {}
        for _, d in ipairs(depts) do
            table.insert(opts, { value = d, label = d })
        end

        local input = lib.inputDialog('Select On-Duty Job', {{
            type = 'select', label = 'Job', options = opts, required = true
        }}, { allowCancel = true })

        if not input then return end
        TriggerServerEvent('az-fw-departments:setJob', input[1])
    end)

    RegisterNetEvent('az-fw-departments:refreshJob')
    AddEventHandler('az-fw-departments:refreshJob', function(data)
        SendNUIMessage({ action = 'updateJob', job = data.job })
    end)

    RegisterNetEvent("updateCashHUD")
    AddEventHandler("updateCashHUD", function(cash, bank)
        SendNUIMessage({ action = "updateCash", cash = cash, bank = bank })
    end)

    Citizen.CreateThread(function()
        Citizen.Wait(2000)
        TriggerServerEvent('hud:requestDepartment')
    end)
else
    print('[az-fw-departments-client] Departments disabled; skipping department features.')
end
