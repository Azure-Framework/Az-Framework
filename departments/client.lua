if Config.Departments then
    print('[az-fw-departments] CLIENT.LUA Departments enabled. Initializing...')
    Citizen.CreateThread(function()
        print("[DEBUG] Waiting 2s then firing hud:requestDepartment")
        Citizen.Wait(2000) -- if you really meant 2 seconds; change back to 100 for 0.1s
        print("[DEBUG] TriggerServerEvent('hud:requestDepartment')")
        TriggerServerEvent('hud:requestDepartment')
    end)

    RegisterNetEvent('hud:setDepartment', function(department)
        print('[CLIENT DEBUG] Received department:', department)
        SendNUIMessage({
            action = "updateJob",
            job    = department or "Unemployed"
        })
    end)

    -- Corrected syntax here:
    RegisterNetEvent('az-fw-departments:refreshMoney', function(data)
        SendNUIMessage({
            action = 'updateMoneyHUD',
            cash   = data.cash,
            bank   = data.bank
        })
    end)

else
    print('[az-fw-departments] Departments disabled. Department features will not work.')
end
