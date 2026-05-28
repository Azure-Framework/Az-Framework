local RESOURCE = GetCurrentResourceName()
print(("[az-fw-hud] client.lua loaded. Resource=%s IsDuplicity=%s"):format(RESOURCE, tostring(IsDuplicityVersion())))

if IsDuplicityVersion() then
  print(("[az-fw-hud] ERROR: client.lua executed server-side. Move this file to client_scripts in fxmanifest.lua."):format(RESOURCE))
  return
end

local function safePrint(msg)
  print("[az-fw-hud] " .. tostring(msg))
end

local function sendNui(msg)
  SendNUIMessage(msg)
end

local cachedHudPreset = nil

local function lowerText(v)
  return tostring(v or ""):lower()
end

local function isMergedCharacterUiMode()
  local modules = Config.Modules or {}
  local charCfg = Config.Character or {}
  local mode = lowerText(charCfg.Mode or ((modules.CharacterUI == true) and "ui" or "discord"))
  return modules.CharacterSystem ~= false and modules.CharacterUI == true and mode == "ui"
end

local gameplayReady = false
local radarEnforceThread = nil

local function setRadarVisible(visible)
  pcall(function() DisplayHud(visible == true) end)
  pcall(function() DisplayRadar(visible == true) end)
  if visible == true then
    pcall(function() SetRadarBigmapEnabled(false, false) end)
    pcall(function() SetBigmapActive(false, false) end)
    pcall(function() SetMinimapClipType(0) end)
    pcall(function() SetRadarAsExteriorThisFrame() end)
  end
end

local function startRadarEnforcer()
  if radarEnforceThread then return end
  radarEnforceThread = CreateThread(function()
    while gameplayReady do
      setRadarVisible(true)
      Wait(0)
    end
    if not gameplayReady then
      setRadarVisible(false)
    end
    radarEnforceThread = nil
  end)
end

local function setGameplayReady(state, reason)
  gameplayReady = state == true
  pcall(function()
    if LocalPlayer and LocalPlayer.state then
      LocalPlayer.state:set('azfwGameplayReady', gameplayReady, false)
    end
  end)
  setRadarVisible(gameplayReady)
  if gameplayReady then startRadarEnforcer() end
  sendNui({ action = 'setHudVisible', visible = gameplayReady and ((Config.Modules or {}).HUD ~= false) })
  if Config and Config.Debug then
    safePrint(("gameplayReady=%s reason=%s"):format(tostring(gameplayReady), tostring(reason or 'unknown')))
  end
end

RegisterNetEvent('az-fw:client:setGameplayReady')
AddEventHandler('az-fw:client:setGameplayReady', function(state, reason)
  setGameplayReady(state == true, reason or 'event')
end)

CreateThread(function()
  while true do
    if gameplayReady then
      setRadarVisible(true)
      Wait(250)
    else
      Wait(1250)
    end
  end
end)

RegisterCommand('fixminimap', function()
  setGameplayReady(true, 'fixminimap_command')
  setRadarVisible(true)
  startRadarEnforcer()
end, false)

_G.AzClientCoreExports = _G.AzClientCoreExports or {}
_G.AzClientCoreExports.IsGameplayReady = function() return gameplayReady end

local function pushPresetToNui()
  if type(cachedHudPreset) == "table" then
    sendNui({ action = "loadPresetSettings", settings = cachedHudPreset })
  end
end

local function trim(s)
  return (s and s:gsub("^%s*(.-)%s*$", "%1") or "")
end

local function headingToCompass(heading)
  local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
  local idx = math.floor(((heading % 360.0) + 22.5) / 45.0) + 1
  return dirs[((idx - 1) % #dirs) + 1]
end

local function getNavStreetInfo(coords)
  local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
  local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ""
  local crossing = crossingHash and crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or ""
  local zone = GetNameOfZone(coords.x, coords.y, coords.z)
  local zoneLabel = zone and GetLabelText(zone) or ""
  if zoneLabel == "NULL" then zoneLabel = "" end
  return street or "", crossing or "", zoneLabel or ""
end

local function getPostalText()
  local postalCfg = (Config and Config.HUD and Config.HUD.Postal) or {}
  local resources = postalCfg.ResourceNames or { "nearest-postal", "nearest_postal", "postals", "new-postals" }
  local exportsList = postalCfg.ExportNames or { "getPostal", "GetPostal", "getCurrentPostal", "GetCurrentPostal" }

  for _, resourceName in ipairs(resources) do
    local state = GetResourceState(resourceName)
    if state == "started" then
      for _, exportName in ipairs(exportsList) do
        local ok, ret = pcall(function()
          return exports[resourceName][exportName]()
        end)
        if ok and ret ~= nil then
          if type(ret) == "table" then
            local postal = ret.postal or ret.code or ret.value or ret.text or ret.nearest
            if postal ~= nil and tostring(postal) ~= "" then
              return tostring(postal)
            end
          elseif tostring(ret) ~= "" then
            return tostring(ret)
          end
        end
      end
    end
  end

  return ""
end

local function defaultFeatureState()
  local hudCfg = (Config and Config.HUD and Config.HUD.Features) or {}
  return {
    compass = hudCfg.compass ~= false,
    postal = hudCfg.postal ~= false,
    aop = hudCfg.aop ~= false,
    prio = hudCfg.prio ~= false,
  }
end

local function onNet(eventName, handler)
  RegisterNetEvent(eventName)
  AddEventHandler(eventName, handler)
end

local function pushHudNotification(payload)
  payload = payload or {}
  sendNui({
    action = 'hudNotify',
    title = tostring(payload.title or 'Notification'),
    description = tostring(payload.description or ''),
    icon = tostring(payload.icon or 'bi-bell'),
    sound = tostring(payload.sound or 'job')
  })
end

local wantedServicesDisabled = false

local function applyWantedSuppression(forceServices)
  if not (Config and Config.DisableWanted) then return end

  local playerId = PlayerId()
  if playerId == -1 then return end

  SetMaxWantedLevel(0)
  SetPlayerWantedLevel(playerId, 0, false)
  SetPlayerWantedLevelNow(playerId, false)
  ClearPlayerWantedLevel(playerId)
  SetPoliceIgnorePlayer(playerId, true)
  SetDispatchCopsForPlayer(playerId, false)

  if forceServices or not wantedServicesDisabled then
    for service = 1, 15 do
      EnableDispatchService(service, false)
    end
    wantedServicesDisabled = true
  end
end

onNet('az-framework:hudNotify', function(payload)
  pushHudNotification(payload)
end)

_G.AzClientCoreExports = _G.AzClientCoreExports or {}
_G.AzClientCoreExports.hudNotify = function(payload) pushHudNotification(payload) end

local navState = {
  features = defaultFeatureState(),
  aop = (Config and Config.HUD and Config.HUD.DefaultAOP) or "None Set",
  prio = (Config and Config.HUD and Config.HUD.DefaultPrio) or "None Set",
  compass = "N",
  street = "",
  crossStreet = "",
  zone = "",
  postal = "",
}

local function pushNavStateToNui(partial)
  partial = partial or {}
  if partial.features then
    navState.features = partial.features
  end
  if partial.aop ~= nil then navState.aop = tostring(partial.aop) end
  if partial.prio ~= nil then navState.prio = tostring(partial.prio) end
  if partial.compass ~= nil then navState.compass = tostring(partial.compass) end
  if partial.street ~= nil then navState.street = tostring(partial.street) end
  if partial.crossStreet ~= nil then navState.crossStreet = tostring(partial.crossStreet) end
  if partial.zone ~= nil then navState.zone = tostring(partial.zone) end
  if partial.postal ~= nil then navState.postal = tostring(partial.postal) end

  sendNui({
    action = "updateHudState",
    features = navState.features,
    aop = navState.aop,
    prio = navState.prio,
    compass = navState.compass,
    street = navState.street,
    crossStreet = navState.crossStreet,
    zone = navState.zone,
    postal = navState.postal,
  })
end

if type(RegisterNUICallback) ~= "function" then
  safePrint("WARNING: RegisterNUICallback not available; NUI callbacks won't be registered.")
else
  local function registerNuiCallbacks()
    RegisterNUICallback("saveHUD", function(data, cb)
      safePrint("Received saveHUD from NUI (cookies/localStorage mode).")
      if type(data) == "table" and tostring(data.mode or "") == "preset" then
        TriggerServerEvent("az-fw-hud:savePreset", data)
      end
      SetNuiFocus(false, false)
      sendNui({ action = "saved", ok = true })
      if cb then cb({ ok = true }) end
    end)

    RegisterNUICallback("resetDefaults", function(_, cb)
      safePrint("Received resetDefaults from NUI (cookies/localStorage mode).")
      SetNuiFocus(false, false)
      if cb then cb({ ok = true }) end
    end)

    RegisterNUICallback("closeUI", function(_, cb)
      SetNuiFocus(false, false)
      if cb then cb({ ok = true }) end
    end)

    RegisterNUICallback("requestSettings", function(_, cb)
      pushPresetToNui()
      TriggerServerEvent("az-fw-hud:requestPreset")
      pushNavStateToNui()
      if cb then cb({ ok = true }) end
    end)
  end

  registerNuiCallbacks()
end

onNet("updateCashHUD", function(cash, bank, playerName)
  sendNui({ action = "updateCash", cash = cash, bank = bank, playerName = playerName })
end)

onNet("az-fw-departments:refreshJob", function(data)
  local job = data and data.job or ""
  sendNui({ action = "updateJob", job = job })

end)

onNet("hud:setDepartment", function(job)
  sendNui({ action = "updateJob", job = job })
end)

onNet("az-fw-hud:syncState", function(state)
  if type(state) ~= "table" then return end
  pushNavStateToNui({
    features = type(state.features) == "table" and state.features or navState.features,
    aop = state.aop or navState.aop,
    prio = state.prio or navState.prio,
  })
end)

onNet("az-fw-hud:syncPreset", function(settings)
  if type(settings) ~= "table" then
    cachedHudPreset = nil
    return
  end
  cachedHudPreset = settings
  pushPresetToNui()
end)

onNet("az-fw-hud:togglePresetMove", function()
  SetNuiFocus(true, true)
  sendNui({ action = "togglePresetMove" })
end)

onNet("az-fw-hud:featureToggled", function(feature, enabled)
  local features = navState.features or defaultFeatureState()
  features[tostring(feature or "")] = enabled == true
  pushNavStateToNui({ features = features })
end)

onNet("az-fw-hud:setAOP", function(value)
  navState.aop = tostring(value or ((Config and Config.HUD and Config.HUD.DefaultAOP) or "None Set"))
  sendNui({ action = "setAOP", value = navState.aop })
end)

onNet("az-fw-hud:setPRIO", function(value)
  navState.prio = tostring(value or ((Config and Config.HUD and Config.HUD.DefaultPrio) or "None Set"))
  sendNui({ action = "setPRIO", value = navState.prio })
end)

local firstSpawn = true
local introSpawnHandled = false
AddEventHandler("playerSpawned", function()
  if firstSpawn then
    firstSpawn = false
    TriggerServerEvent("hud:requestDepartment")
    TriggerServerEvent("az-fw-hud:requestState")
    TriggerServerEvent("az-fw-hud:requestPreset")
  end

  if not isMergedCharacterUiMode() then
    setGameplayReady(true, 'playerSpawned_no_character_ui')
    if not introSpawnHandled and _G.AzFwPlayIntroForCurrentSpawnIfNeeded then
      introSpawnHandled = true
      CreateThread(function()
        Wait(250)
        setGameplayReady(false, 'intro_cutscene_start')
        local result = _G.AzFwPlayIntroForCurrentSpawnIfNeeded({ mode = 'discord', isNewCharacter = true })
        setGameplayReady(true, 'intro_cutscene_end')
        local shouldShowSpawnDeath = false
        if _G.AzFwShowSpawnDeathScreen then
          if type(result) == 'table' then
            if result.played == true then
              shouldShowSpawnDeath = result.showDeathScreenAfter ~= false
            else
              local introReason = tostring(result.reason or '')
              shouldShowSpawnDeath = (introReason == 'disabled' or introReason == 'already_seen' or introReason == 'discord_mode_disabled' or introReason == 'no_discord' or introReason == 'server_no')
            end
          else
            shouldShowSpawnDeath = false
          end
        end
        if shouldShowSpawnDeath then
          DoScreenFadeIn(1000)
          local fadeWaitStart = GetGameTimer()
          while not IsScreenFadedIn() and (GetGameTimer() - fadeWaitStart) < 2500 do
            Wait(0)
          end
          Wait(150)
          _G.AzFwShowSpawnDeathScreen(Config.SpawnDeathScreen or {})
        end
      end)
    end
  end

  if Config and Config.DisableWanted then
    CreateThread(function()
      Wait(750)
      applyWantedSuppression(true)
    end)
  end
end)

AddEventHandler("onClientResourceStart", function(res)
  if res ~= RESOURCE then return end
  setGameplayReady(false, 'resource_start')
  CreateThread(function()
    Wait(1500)
    if not isMergedCharacterUiMode() then
      setGameplayReady(true, 'resource_start_no_character_ui')
    end
    TriggerServerEvent("az-fw-hud:requestState")
    TriggerServerEvent("az-fw-hud:requestPreset")
    pushPresetToNui()
    pushNavStateToNui()
    if Config and Config.DisableWanted then
      applyWantedSuppression(true)
    end
  end)
end)

RegisterCommand("movehud", function()
  SetNuiFocus(true, true)
  sendNui({ action = "toggleMove" })
end, false)

RegisterCommand("hudsettings", function()
  SetNuiFocus(true, true)
  sendNui({ action = "openSettings" })
end, false)

local CHAR_MAIN = "char_main_menu"
local CHAR_LIST = "char_list_menu"
local EVENT_SHOW_LIST = "az-fw-money:openListMenu"

lib.registerContext({
  id = CHAR_MAIN,
  title = "📝 Character Menu",
  canClose = true,
  options = {
    {
      title = "➕ Register New Character",
      description = "Create a brand-new character",
      icon = "user-plus",
      event = "az-fw-money:openRegisterDialog"
    },
    {
      title = "📜 List / Select Character",
      description = "Switch between your saved characters",
      icon = "users",
      event = EVENT_SHOW_LIST
    }
  }
})

onNet("az-fw-money:openRegisterDialog", function()
  local title = "Register Character"
  local fields = {
    {
      type = "input",
      label = "First Name",
      placeholder = "John",
      required = true,
      min = 1,
      max = 20,
      icon = "id-badge"
    },
    {
      type = "input",
      label = "Last Name",
      placeholder = "Doe",
      required = true,
      min = 1,
      max = 20,
      icon = "id-badge"
    }
  }
  local opts = { allowCancel = true }

  while true do
    local inputs = lib.inputDialog(title, fields, opts)

    if not inputs then
      lib.notify({
        title = "Registration",
        description = "Registration cancelled.",
        type = "inform"
      })
      break
    end

    local first = trim(inputs[1] or "")
    local last = trim(inputs[2] or "")

    if first ~= "" and last ~= "" then
      TriggerServerEvent("az-fw-money:registerCharacter", first, last)
      break
    else
      lib.notify({
        title = "Registration",
        description = "First and last name are required and cannot be empty.",
        type = "error"
      })
      Citizen.Wait(150)
    end
  end
end)

onNet(EVENT_SHOW_LIST, function()
  lib.callback("az-fw-money:fetchCharacters", {}, function(rows)
    local opts = {}

    if not rows or #rows == 0 then
      table.insert(opts, { title = "❗ You have no characters yet", disabled = true })
    else
      for _, row in ipairs(rows) do
        table.insert(opts, {
          title = row.name,
          description = "ID: " .. row.charid,
          icon = "user",
          onSelect = function()
            TriggerServerEvent("az-fw-money:selectCharacter", row.charid)
          end
        })
      end
    end

    lib.registerContext({
      id = CHAR_LIST,
      title = "🔄 Your Characters",
      menu = CHAR_MAIN,
      canClose = true,
      options = opts
    })
    lib.showContext(CHAR_LIST)
  end)
end)

onNet("az-fw-money:characterRegistered", function(charid)
  lib.notify({
    title = "Character Registered",
    description = "Your new char ID is " .. charid,
    type = "success"
  })
  TriggerServerEvent("az-fw-money:requestMoney")
  TriggerServerEvent("az-fw-hud:requestState")
end)

onNet("az-fw-money:characterSelected", function(charid)
  if isMergedCharacterUiMode() then
    setGameplayReady(false, 'character_selected')
  end
  lib.notify({
    title = "Character Selected",
    description = "Now using char ID " .. charid,
    type = "info"
  })
  TriggerServerEvent("az-fw-money:requestMoney")
  TriggerServerEvent("az-fw-hud:requestState")
end)

local function refreshHUD()
  safePrint("refreshHUD export called; requesting money, department, and shared HUD state from server.")
  TriggerServerEvent("az-fw-money:requestMoney")
  TriggerServerEvent("hud:requestDepartment")
  TriggerServerEvent("az-fw-hud:requestState")
end

_G.AzClientCoreExports = _G.AzClientCoreExports or {}
_G.AzClientCoreExports.refreshHUD = refreshHUD
_G.AzClientCoreExports.updateHUD = refreshHUD

CreateThread(function()
  local postalRefresh = tonumber((Config and Config.HUD and Config.HUD.Postal and Config.HUD.Postal.RefreshMs) or 1000) or 1000
  local navRefresh = tonumber((Config and Config.HUD and Config.HUD.NavRefreshMs) or 350) or 350
  local lastPostalAt = 0
  local lastPostal = ""
  local wantedRefreshCounter = 0

  while true do
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
      Wait(1000)
    else
      local coords = GetEntityCoords(ped)
      local heading = GetEntityHeading(ped)
      local street, crossing, zoneLabel = getNavStreetInfo(coords)
      local nextPartial = {
        compass = headingToCompass(heading),
        street = street,
        crossStreet = crossing,
        zone = zoneLabel,
      }

      local now = GetGameTimer()
      if navState.features and navState.features.postal ~= false and (now - lastPostalAt) >= postalRefresh then
        lastPostalAt = now
        lastPostal = getPostalText() or ""
        nextPartial.postal = lastPostal
      elseif lastPostal ~= "" then
        nextPartial.postal = lastPostal
      end

      pushNavStateToNui(nextPartial)

      if Config and Config.DisableWanted then
        wantedRefreshCounter = wantedRefreshCounter + navRefresh
        if wantedRefreshCounter >= 1000 then
          wantedRefreshCounter = 0
          applyWantedSuppression(false)
        end
      end

      Wait(navRefresh)
    end
  end
end)

safePrint("client.lua initialized.")

RegisterCommand('azfwv4check', function()
  local ped = PlayerPedId()
  local hp = (ped ~= 0 and DoesEntityExist(ped)) and GetEntityHealth(ped) or -1
  local msg = ('client status | ped=%s | hp=%s | resource=%s'):format(tostring(ped), tostring(hp), tostring(GetCurrentResourceName()))
  print('^2[Az-Framework]^7 ' .. msg)
  TriggerEvent('chat:addMessage', { color = { 0, 255, 170 }, args = { '^2Az-Framework', msg } })
end, false)

local azDeathCoreDebug = Config and Config.Debug == true

local function azfwDeathCoreStatus(label)
  local ped = PlayerPedId()
  local exists = ped ~= 0 and DoesEntityExist(ped)
  local hp = exists and GetEntityHealth(ped) or -1
  local armor = exists and GetPedArmour(ped) or -1
  local dead = exists and IsEntityDead(ped) or false
  local dying = exists and IsPedDeadOrDying(ped, true) or false
  local fatal = exists and IsPedFatallyInjured(ped) or false
  local msg = ('%s | ped=%s | hp=%s | armor=%s | dead=%s | dying=%s | fatal=%s | deathMain=%s | deathProbe=%s | baseevents=%s | spawnmanager=%s'):format(
    tostring(label or 'deathstatus'), tostring(ped), tostring(hp), tostring(armor), tostring(dead), tostring(dying), tostring(fatal),
    tostring(_G.AzDeathMainLoaded == true), tostring(_G.AzDeathProbeLoaded == true), tostring(GetResourceState('baseevents')), tostring(GetResourceState('spawnmanager'))
  )
  print('^1[Az-Framework DeathCore]^7 ' .. msg)
  TriggerEvent('chat:addMessage', { color = { 255, 80, 80 }, args = { '^1Az-Framework DeathCore', msg } })
  if _G.AzDeathMainLoaded == true then
    TriggerEvent('Az-Death:debug:statusRequestFromCore', tostring(label or 'deathstatus'))
  end
end

RegisterCommand('deathstatus', function()
  azfwDeathCoreStatus('deathstatus')
end, false)

RegisterCommand('deathprobe', function()
  azfwDeathCoreStatus('deathprobe')
end, false)

RegisterCommand('deathdebug', function()
  azDeathCoreDebug = not azDeathCoreDebug
  azfwDeathCoreStatus('deathdebug toggled=' .. tostring(azDeathCoreDebug))
  if _G.AzDeathMainLoaded == true then
    TriggerEvent('Az-Death:debug:setDebugFromCore', azDeathCoreDebug)
  end
end, false)

if Config and Config.Debug then
  CreateThread(function()
    Wait(2500)
    azfwDeathCoreStatus('deathcore_boot')
  end)
end
