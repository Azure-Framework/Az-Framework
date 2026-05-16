local Config = (Config and Config.DailyRewards) or {}
if Config.Enabled == false then return end
local resourceName = Config.ResourceName or 'Az-Framework'

RegisterCommand('dailycheckin', function()
  TriggerServerEvent('daily_checkin:server:requestOpen')
end)
TriggerEvent('chat:addSuggestion', '/dailycheckin', 'Open the daily check-in calendar and spin wheel.', {})

RegisterNetEvent('daily_checkin:client:openUI')
AddEventHandler('daily_checkin:client:openUI', function(payload)
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'daily_open', payload = payload, resource = resourceName })
  SendNUIMessage({ action = 'daily_playSound', sound = 'open' })
end)

RegisterNUICallback('claim', function(data, cb)
  TriggerServerEvent('daily_checkin:server:claimDay', data.day)
  cb({ ok = true })
end)

RegisterNetEvent('daily_checkin:client:claimSuccess')
AddEventHandler('daily_checkin:client:claimSuccess', function(data)
  SendNUIMessage({ action = 'daily_claimSuccess', payload = data.payload, reward = data.reward })
  SendNUIMessage({ action = 'daily_playSound', sound = 'claim' })
end)

RegisterNetEvent('daily_checkin:client:spinResult')
AddEventHandler('daily_checkin:client:spinResult', function(data)
  SendNUIMessage({ action = 'daily_spinResult', data = data })
  SendNUIMessage({ action = 'daily_playSound', sound = 'spin' })
end)

RegisterNetEvent('daily_checkin:client:giveWeapon')
AddEventHandler('daily_checkin:client:giveWeapon', function(weaponName, ammo)
  local ped = PlayerPedId()
  local hash = GetHashKey(weaponName)
  GiveWeaponToPed(ped, hash, ammo or 0, false, false)
  TriggerEvent('chat:addMessage', { args = { '^2Daily Checkin', 'You received ' .. weaponName } })
end)

RegisterNUICallback('dailyClose', function(_, cb)
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'daily_close' })
  cb({ ok = true })
end)

RegisterNUICallback('spin', function(_, cb)
  TriggerServerEvent('daily_checkin:server:spinWheel')
  cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
  TriggerServerEvent('daily_checkin:server:requestOpen')
  cb({ ok = true })
end)

RegisterNetEvent('daily_checkin:client:notify')
AddEventHandler('daily_checkin:client:notify', function(msg)
  TriggerEvent('chat:addMessage', { args = { '^1Daily Checkin', msg } })
end)

RegisterNetEvent('daily_checkin:client:error')
AddEventHandler('daily_checkin:client:error', function(msg)
  TriggerEvent('chat:addMessage', { args = { '^1Daily Checkin', msg or 'An unknown daily check-in error occurred.' } })
end)

AddEventHandler('onResourceStop', function(resName)
  if resName ~= GetCurrentResourceName() then return end
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'daily_close' })
end)
