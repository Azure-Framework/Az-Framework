local Config = (Config and Config.Banking) or {}
if Config.Enabled == false then return end

Config.ATMModels = Config.ATMModels or { `prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm` }
Config.UseKey = Config.UseKey or 38
Config.PromptDist = Config.PromptDist or 3.0
Config.BlipDist = Config.BlipDist or 50.0
Config.Blip = Config.Blip or { sprite = 108, color = 2, scale = 0.8, text = 'Bank ATM' }
Config.GlitchCircuitParams = Config.GlitchCircuitParams or {2, 1, 1000, 3000, 3000, 0, 10000, 3000, 30000}
Config.SkillCheckSeq = Config.SkillCheckSeq or {'easy', { areaSize = 80, speedMultiplier = 0.8 }}
Config.SkillCheckInputs = Config.SkillCheckInputs or {'e'}
Config.atmRobberyCooldown = Config.atmRobberyCooldown or 600
Config.atmMinReward = Config.atmMinReward or 500
Config.atmMaxReward = Config.atmMaxReward or 3000
Config.atmDispatchOnFail = Config.atmDispatchOnFail ~= false
Config.RobKey = Config.RobKey or 74
Config.TextScale = Config.TextScale or 0.60

local nuiOpen = false
local atmEntities = {}
local atmBlips = {}
local atmStates = {}

local function DrawText3D(x, y, z, text, scale)
  scale = scale or 0.35
  SetTextScale(scale, scale)
  SetTextFont(4)
  SetTextProportional(1)
  SetTextColour(255, 255, 255, 215)
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(text)
  SetDrawOrigin(x, y, z, 0)
  DrawText(0.0, 0.0)
  ClearDrawOrigin()
end

local function coordsToKey(v)
  return string.format('%.1f:%.1f:%.1f', v.x, v.y, v.z)
end

local function shortNotify(text)
  SetNotificationTextEntry('STRING')
  AddTextComponentString(text)
  DrawNotification(false, false)
end

local function setBankVisible(state)
  nuiOpen = state == true
  if SetNuiFocusKeepInput then
    SetNuiFocusKeepInput(false)
  end
  SetNuiFocus(nuiOpen, nuiOpen)
  SendNUIMessage({ action = nuiOpen and 'show' or 'hide' })
end

RegisterCommand('bank', function()
  setBankVisible(not nuiOpen)
end, false)

RegisterNUICallback('bankClose', function(_, cb)
  setBankVisible(false)
  cb({})
end)

for _, evt in ipairs({
  'getData',
  'deposit',
  'withdraw',
  'transferInternal',
  'transferPlayer',
  'investOpen',
  'investCollect'
}) do
  RegisterNUICallback(evt, function(data, cb)
    TriggerServerEvent('my-bank-ui:' .. evt, data)
    cb({})
  end)
end

RegisterNetEvent('my-bank-ui:updateData', function(payload)
  SendNUIMessage({ action = 'setData', data = payload })
end)

RegisterNetEvent('my-bank-ui:nui', function(msg)
  SendNUIMessage(msg or {})
end)

RegisterNetEvent('dispatch:atmRobbery', function(payload)
  if not payload or not payload.coords then return end

  local x, y, z = payload.coords.x or 0.0, payload.coords.y or 0.0, payload.coords.z or 0.0
  local duration = tonumber(payload.blipDuration) or 20
  local reward = tonumber(payload.reward) or 0
  local wasSuccessful = payload.success == true
  local title = wasSuccessful and 'ATM Robbery' or 'ATM Tampering'

  local b = AddBlipForCoord(x, y, z)
  SetBlipSprite(b, 161)
  SetBlipColour(b, wasSuccessful and 1 or 47)
  SetBlipScale(b, 1.0)
  SetBlipAsShortRange(b, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString(title)
  EndTextCommandSetBlipName(b)
  SetBlipFlashes(b, true)
  SetBlipFlashInterval(b, 250)

  Citizen.SetTimeout(duration * 1000, function()
    if DoesBlipExist(b) then RemoveBlip(b) end
  end)

  local locText = ('%.1f, %.1f'):format(x, y)
  local msg = wasSuccessful
    and ('~r~ATM ROBBERY ~s~| ~y~Location: ~s~%s ~s~| ~g~Stolen: $%d'):format(locText, reward)
    or ('~o~FAILED ATM ROBBERY ~s~| ~y~Location: ~s~%s'):format(locText)

  SetNotificationTextEntry('STRING')
  AddTextComponentString(msg)
  DrawNotification(false, false)

  TriggerEvent('chat:addMessage', {
    color = { 255, 170, 0 },
    multiline = false,
    args = {
      'DISPATCH',
      wasSuccessful and (('ATM Robbery — Location: %s — Stolen: $%d'):format(locText, reward))
        or (('Failed ATM Robbery — Location: %s'):format(locText))
    }
  })
end)

RegisterNetEvent('atm:closedStatus', function(atmKey, remainingSeconds)
  if not atmKey then return end
  if remainingSeconds and remainingSeconds > 0 then
    atmStates[atmKey] = math.floor(GetGameTimer() / 1000) + math.floor(remainingSeconds)
  else
    atmStates[atmKey] = nil
  end
end)

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(2000)
    atmEntities = {}
    local handle, obj = FindFirstObject()
    local success = true
    repeat
      if DoesEntityExist(obj) then
        local model = GetEntityModel(obj)
        for _, atmModel in ipairs(Config.ATMModels) do
          if model == atmModel then
            atmEntities[obj] = true
            break
          end
        end
      end
      success, obj = FindNextObject(handle)
    until not success
    EndFindObject(handle)
  end
end)

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local nowSec = math.floor(GetGameTimer() / 1000)

    for obj, _ in pairs(atmEntities) do
      if DoesEntityExist(obj) then
        local oCoords = GetEntityCoords(obj)
        local dist = #(pCoords - oCoords)

        if dist <= Config.BlipDist and not atmBlips[obj] then
          local blip = AddBlipForCoord(oCoords.x, oCoords.y, oCoords.z)
          SetBlipSprite(blip, Config.Blip.sprite)
          SetBlipColour(blip, Config.Blip.color)
          SetBlipScale(blip, Config.Blip.scale)
          BeginTextCommandSetBlipName('STRING')
          AddTextComponentString(Config.Blip.text)
          EndTextCommandSetBlipName(blip)
          atmBlips[obj] = blip
        elseif dist > Config.BlipDist and atmBlips[obj] then
          RemoveBlip(atmBlips[obj])
          atmBlips[obj] = nil
        end

        if dist <= Config.PromptDist then
          local key = coordsToKey(oCoords)
          local expiry = atmStates[key]
          if expiry and expiry > nowSec then
            local remaining = math.max(0, expiry - nowSec)
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            DrawText3D(oCoords.x, oCoords.y, oCoords.z + 1.0, ('~r~ATM Offline - %02d:%02d'):format(mins, secs), 0.5)
          else
            DrawText3D(oCoords.x, oCoords.y, oCoords.z + 1.0, '[~g~E~w~] Open Banking   [~r~H~w~] Breach ATM', Config.TextScale)
            if IsControlJustReleased(0, Config.UseKey) then
              ExecuteCommand('bank')
            end
            if IsControlJustReleased(0, Config.RobKey) then
              attemptAtmRobbery(oCoords)
            end
          end
        end
      end
    end
  end
end)

function attemptAtmRobbery(atmCoords)
  if not atmCoords then return end

  local gmState = GetResourceState and GetResourceState('glitch-minigames') or nil
  if gmState == 'started' then
    local ok, result = pcall(function()
      return exports['glitch-minigames']:StartCircuitBreaker(table.unpack(Config.GlitchCircuitParams))
    end)
    if ok and result then
      TriggerServerEvent('atm:attemptRob', coordsToKey(atmCoords), atmCoords, GetEntityCoords(PlayerPedId()))
      shortNotify('ATM breach succeeded!')
    else
      if Config.atmDispatchOnFail then
        TriggerServerEvent('atm:failedRob', coordsToKey(atmCoords), atmCoords, GetEntityCoords(PlayerPedId()))
      end
      shortNotify('ATM breach failed. Law enforcement has been notified.')
    end
    return
  end

  local ok, success = pcall(function()
    if type(lib) == 'table' and lib.skillCheck then
      return lib.skillCheck(Config.SkillCheckSeq, Config.SkillCheckInputs)
    end
    return false
  end)

  if ok and success then
    TriggerServerEvent('atm:attemptRob', coordsToKey(atmCoords), atmCoords, GetEntityCoords(PlayerPedId()))
    shortNotify('ATM breach succeeded!')
  else
    if Config.atmDispatchOnFail then
      TriggerServerEvent('atm:failedRob', coordsToKey(atmCoords), atmCoords, GetEntityCoords(PlayerPedId()))
    end
    shortNotify('ATM breach failed. Law enforcement has been notified.')
  end
end

AddEventHandler('onClientResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  TriggerServerEvent('my-bank-ui:getData')
end)
