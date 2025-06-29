if Config.Departments then
    print('[az-fw-departments-client] Departments enabled, initializing...')

    -- Trigger /jobs dialog
    RegisterCommand('jobs', function()
        TriggerServerEvent('az-fw-departments:requestDeptList')
    end)

    -- Open selection dialog
    RegisterNetEvent('az-fw-departments:openJobsDialog')
    AddEventHandler('az-fw-departments:openJobsDialog', function(depts)
        if not depts or #depts == 0 then
            return exports['ox_lib']:Notify({ type='error', text='No jobs available' })
        end
        local opts = {}
        for _, d in ipairs(depts) do table.insert(opts, {value=d,label=d}) end
        local input = exports['ox_lib']:inputDialog('Select On-Duty Job', {{
            type='select', label='Job', options=opts, required=true
        }}, {allowCancel=true})
        if not input then return end
        TriggerServerEvent('az-fw-departments:setJob', input[1])
    end)

    -- Update job HUD
    RegisterNetEvent('az-fw-departments:refreshJob')
    AddEventHandler('az-fw-departments:refreshJob', function(data)
        SendNUIMessage({action='updateJob', job=data.job})
    end)

    RegisterNetEvent("updateCashHUD")
    AddEventHandler("updateCashHUD", function(cash, bank)
        SendNUIMessage({ action = "updateCash", cash = cash, bank = bank })
    end)

    -- On resource start, request HUD
    Citizen.CreateThread(function()
        Citizen.Wait(2000)
        TriggerServerEvent('hud:requestDepartment')
    end)
else
    print('[az-fw-departments-client] Departments disabled; skipping department features.')
end
