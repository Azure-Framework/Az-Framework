Config = Config or {}

if Config.Departments then
    print('[az-fw-departments-client] Departments enabled, initializing...')

    -- Command to open job selector
    RegisterCommand('jobs', function()
        TriggerServerEvent('az-fw-departments:requestDeptList')
    end, false)

    -- Server sends list of departments
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
            type = 'select',
            label = 'Job',
            options = opts,
            required = true
        }}, { allowCancel = true })

        if not input then return end

        local chosen = input[1]
        print("[az-fw-departments-client] selected job = " .. tostring(chosen))

        -- This MUST exist server-side (we added it)
        TriggerServerEvent('az-fw-departments:setJob', chosen)
    end)

    -- Server confirms job change -> update HUD/NUI
    RegisterNetEvent('az-fw-departments:refreshJob')
    AddEventHandler('az-fw-departments:refreshJob', function(data)
        local job = data and data.job or ""
        -- Update any NUI that listens for updateJob (your HUD does)
        SendNUIMessage({ action = 'updateJob', job = job })

        -- Also fire the HUD event locally (RegisterNetEvent works for local triggers too)
        TriggerEvent("hud:setDepartment", job)
    end)

    -- Optional: if your HUD uses this event too
    RegisterNetEvent("updateCashHUD")
    AddEventHandler("updateCashHUD", function(cash, bank)
        SendNUIMessage({ action = "updateCash", cash = cash, bank = bank })
    end)

    -- Ask server for current department after joining/spawn
    CreateThread(function()
        Wait(2000)
        TriggerServerEvent('hud:requestDepartment')
    end)

else
    print('[az-fw-departments-client] Departments disabled; skipping department features.')
end
