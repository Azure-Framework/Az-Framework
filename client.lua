-- client.lua

-- On first spawn, ask server for both money *and* department
local firstSpawn = true
AddEventHandler('playerSpawned', function()
  if firstSpawn then
    firstSpawn = false
    TriggerServerEvent('az-fw-money:requestMoney')
    TriggerServerEvent('hud:requestDepartment')
  end
end)

-- Forward cash updates
RegisterNetEvent("updateCashHUD")
AddEventHandler("updateCashHUD", function(cash, bank)
  SendNUIMessage({ action = "updateCash", cash = cash, bank = bank })
end)

-- Forward job updates *from* the departments resource
-- server.lua calls: TriggerClientEvent('az-fw-departments:refreshJob', playerId, { job = ... })
RegisterNetEvent("az-fw-departments:refreshJob")
AddEventHandler("az-fw-departments:refreshJob", function(data)
  SendNUIMessage({ action = "updateJob", job = data.job })
end)

-- Also handle the legacy/hud:setDepartment callback
-- server.lua also does: TriggerClientEvent('hud:setDepartment', src, job)
RegisterNetEvent("hud:setDepartment")
AddEventHandler("hud:setDepartment", function(job)
  SendNUIMessage({ action = "updateJob", job = job })
end)

-- Toggle move mode (gives mouse focus)
RegisterCommand("movehud", function()
  SetNuiFocus(true, true)
  SendNUIMessage({ action = "toggleMove" })
end, false)

-- Handle NUI callback to close UI/focus
RegisterNUICallback('closeUI', function(_, cb)
  SetNuiFocus(false, false)
  cb('ok')
end)
