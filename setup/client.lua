local setupOpen = false

local function sendSetupMessage(payload)
  SendNUIMessage(payload)
end

local function openSetup(payload)
  setupOpen = true
  SetNuiFocus(true, true)
  sendSetupMessage({
    action = "azfw_setup_open",
    payload = payload or {}
  })
end

RegisterNetEvent("azfw:setup:open", function(payload)
  openSetup(payload)
end)

RegisterNetEvent("azfw:setup:update", function(payload)
  sendSetupMessage({
    action = "azfw_setup_update",
    payload = payload or {}
  })
end)

RegisterNetEvent("azfw:setup:close", function()
  setupOpen = false
  SetNuiFocus(false, false)
  sendSetupMessage({ action = "azfw_setup_close" })
  TriggerEvent("azfw:setup:closedLocal")
end)

CreateThread(function()
  Wait(7000)
  TriggerServerEvent("azfw:setup:playerReady")
end)

RegisterCommand("framework", function()
  TriggerServerEvent("azfw:setup:requestOpen")
end, false)

if type(RegisterNUICallback) == "function" then
  RegisterNUICallback("azfw_setup_action", function(data, cb)
    TriggerServerEvent("azfw:setup:action", data or {})
    if cb then cb({ ok = true }) end
  end)

  RegisterNUICallback("azfw_setup_close", function(data, cb)
    setupOpen = false
    SetNuiFocus(false, false)
    TriggerEvent("azfw:setup:closedLocal")
    TriggerServerEvent("azfw:setup:close", data or {})
    if cb then cb({ ok = true }) end
  end)
end

AddEventHandler("onResourceStop", function(resource)
  if resource ~= GetCurrentResourceName() or not setupOpen then return end
  SetNuiFocus(false, false)
end)
