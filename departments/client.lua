if Config.Departments then
    print('[az-fw-departments] CLIENT.LUA Departments enabled. Initializing...')
    Citizen.CreateThread(function()
        print("[DEBUG] Waiting 2s then firing hud:requestDepartment")
        Citizen.Wait(100)
        print("[DEBUG] TriggerServerEvent('hud:requestDepartment')")
        TriggerServerEvent('hud:requestDepartment')
    end)
    RegisterNetEvent('hud:setDepartment', function(department)
        print('[CLIENT DEBUG] Received department:', department)
        SendNUIMessage({
            action = "updateJob",
            job = department or "Unemployed"
        })
    end)
else
    print('[az-fw-departments] Departments disabled. Department features will not work.')
end
