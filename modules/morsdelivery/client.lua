local RESOURCE = GetCurrentResourceName()

local function dbg(msg)
  print(('[%s][DEBUG] %s'):format(RESOURCE, tostring(msg)))
end

local function notify(msg)
  SetNotificationTextEntry("STRING")
  AddTextComponentString(tostring(msg))
  DrawNotification(false, false)
end

local Config = (Config and Config.MorsDelivery) or {}

Config.Command   = Config.Command  or 'mors'

Config.CallSeconds = Config.CallSeconds or 9

Config.SpawnDistanceMin = Config.SpawnDistanceMin or 280.0
Config.SpawnDistanceMax = Config.SpawnDistanceMax or 520.0

Config.DriverPedModel = Config.DriverPedModel or 's_m_y_valet_01'

Config.DriveSpeed    = Config.DriveSpeed or 20.0
Config.DrivingStyle  = Config.DrivingStyle or 786603
Config.StopDistance  = Config.StopDistance or 8.0

Config.Theme = Config.Theme or { accent = '#2fb7ff' }

Config.OperatorVoice = Config.OperatorVoice or {
  enable = true,
  voiceName  = 'mp_f_stripperlite',
  speechName = 'GENERIC_HI',
  speechParam = 'SPEECH_PARAMS_FORCE_NORMAL',
  delayMs = 2300,
}

Config.RoadSearchAttempts = Config.RoadSearchAttempts or 40
Config.RoadNodeType       = Config.RoadNodeType       or 1
Config.RoadNodeRadius     = Config.RoadNodeRadius     or 3.0

Config.StuckSeconds       = Config.StuckSeconds       or 8
Config.StuckTeleportAfter = Config.StuckTeleportAfter or 3
Config.TeleportDistMin    = Config.TeleportDistMin    or 120.0
Config.TeleportDistMax    = Config.TeleportDistMax    or 180.0

Config.PhoneCallAnim = Config.PhoneCallAnim or {
  enable = true,
  dict = 'cellphone@',
  anim = 'cellphone_call_listen_base',
  flags = 49,
  prop = 'prop_npc_phone_02',
  bone = 28422,
  pos  = { x=0.02, y=0.01, z=0.02 },
  rot  = { x=0.0,  y=0.0,  z=0.0  },
}

local function normalizeHash(h)
  h = tonumber(h)
  if not h then return nil end
  if h < 0 then h = h + 0x100000000 end
  return h
end

local function modelToHashNoLoad(model)
  if model == nil then return nil end

  if type(model) == 'number' then
    return normalizeHash(model)
  end

  if type(model) == 'string' then
    local n = tonumber(model)
    if n ~= nil then
      return normalizeHash(n)
    end
    return normalizeHash(joaat(model))
  end

  return nil
end

local function sanitizeSpawnName(s)
  if type(s) ~= 'string' then return nil end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == '' then return nil end
  if not s:match("^[%w_]+$") then return nil end
  return s:lower()
end

local function modelToSpawnName(model)
  if model == nil then return nil end

  if type(model) == 'string' then
    local s = model:gsub("^%s+", ""):gsub("%s+$", "")
    if tonumber(s) == nil then
      return sanitizeSpawnName(s)
    end
  end

  local hash = modelToHashNoLoad(model)
  if not hash then return nil end
  if not IsModelInCdimage(hash) then return nil end

  local disp = GetDisplayNameFromVehicleModel(hash)
  if not disp or disp == '' then return nil end
  return string.lower(disp)
end

local function modelToPrettyName(model)
  local hash = modelToHashNoLoad(model)
  if not hash then return tostring(model) end

  if not IsModelInCdimage(hash) then
    if type(model) == 'string' and tonumber(model) == nil then
      local s = sanitizeSpawnName(model)
      if s then
        return (s:gsub("^%l", string.upper))
      end
    end
    return tostring(model)
  end

  local disp = GetDisplayNameFromVehicleModel(hash) or ''
  if disp == '' then return tostring(model) end

  local label = GetLabelText(disp)
  if label and label ~= '' and label ~= 'NULL' then
    return label
  end

  return disp
end

local function augmentVehicleRowForNui(row)
  if type(row) ~= 'table' then return row end

  local originalModel = row.model

  local spawn =
      modelToSpawnName(row.spawnName) or
      modelToSpawnName(row.spawn) or
      modelToSpawnName(originalModel) or
      modelToSpawnName(row.modelHash) or
      modelToSpawnName(row.hash)

  local pretty =
      row.modelName or
      modelToPrettyName(originalModel) or
      modelToPrettyName(row.modelHash) or
      tostring(originalModel or "Unknown")

  row.spawnName = spawn or row.spawnName

  if not row.previewUrl and spawn and spawn:match("^[%w_]+$") then
    row.previewUrl = ("https://docs.fivem.net/vehicles/%s.webp?v=1"):format(spawn)
  end

  row.model = pretty
  if row.plate then row.plate = tostring(row.plate):upper() end
  return row
end

local nuiOpen = false
local deliveryActive = false

local function closeNuiHard(reason)
  reason = reason or "unknown"
  dbg("closeNuiHard() reason=" .. reason)
  nuiOpen = false
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ type = "setVisible", visible = false })
end

local function openNui()
  dbg("openNui()")
  nuiOpen = true
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ type = "setVisible", visible = true })
end

AddEventHandler('onClientResourceStart', function(res)
  if res ~= RESOURCE then return end
  Wait(0)
  closeNuiHard("resource_start")
end)

CreateThread(function()
  Wait(250)
  closeNuiHard("startup_safety_timer")
end)

RegisterNUICallback('morsClose', function(_, cb)
  closeNuiHard("nui_close_callback")
  cb(true)
end)

RegisterCommand(Config.Command, function()
  dbg("Command /" .. tostring(Config.Command) .. " -> request list")
  if nuiOpen then return end
  SendNUIMessage({ type = "setTheme", accent = (Config.Theme and Config.Theme.accent) or "#2fb7ff" })
  SendNUIMessage({ type = "setData", ok = true, cooldown = 0, vehicles = {} })
  openNui()
  TriggerServerEvent('nv_morsmutual:sv_list')
end, false)

if Config.Command2 and tostring(Config.Command2) ~= '' then
  RegisterCommand(Config.Command2, function()
    dbg("Command /" .. tostring(Config.Command2) .. " -> request list")
    if nuiOpen then return end
    SendNUIMessage({ type = "setTheme", accent = (Config.Theme and Config.Theme.accent) or "#2fb7ff" })
    SendNUIMessage({ type = "setData", ok = true, cooldown = 0, vehicles = {} })
    openNui()
    TriggerServerEvent('nv_morsmutual:sv_list')
  end, false)
end

RegisterNetEvent('nv_morsmutual:cl_notify', function(msg)
  notify(msg)
end)

RegisterNetEvent('nv_morsmutual:cl_list', function(payload)
  dbg(("cl_list received: ok=%s cooldown=%s vehicles=%s"):format(
    tostring(payload and payload.ok),
    tostring(payload and payload.cooldown),
    tostring(payload and payload.vehicles and #payload.vehicles or 0)
  ))

  local vehs = {}
  if payload and type(payload.vehicles) == 'table' then
    for i = 1, #payload.vehicles do
      vehs[i] = augmentVehicleRowForNui(payload.vehicles[i])
    end
  end

  SendNUIMessage({ type = "setTheme", accent = (Config.Theme and Config.Theme.accent) or "#2fb7ff" })

  SendNUIMessage({
    type = "setData",
    ok = payload and payload.ok or false,
    cooldown = tonumber(payload and payload.cooldown or 0) or 0,
    vehicles = vehs
  })

  openNui()
end)

local activeSoundIds = {}

local function stopAllPhoneSounds()
  for _, sid in ipairs(activeSoundIds) do
    StopSound(sid)
    ReleaseSoundId(sid)
  end
  activeSoundIds = {}
end

local function playFrontendSoundForMs(name, set, ms)
  local sid = GetSoundId()
  table.insert(activeSoundIds, sid)
  PlaySoundFrontend(sid, name, set, true)
  Wait(ms)
  StopSound(sid)
  ReleaseSoundId(sid)
  for i = #activeSoundIds, 1, -1 do
    if activeSoundIds[i] == sid then
      table.remove(activeSoundIds, i)
      break
    end
  end
end

local function playCallSequence(callMs)
  stopAllPhoneSounds()

  local t0 = GetGameTimer()
  playFrontendSoundForMs('Dial_and_Remote_Ring', 'Phone_SoundSet_Default', 1800)
  playFrontendSoundForMs('Remote_Ring',          'Phone_SoundSet_Default', 2200)
  playFrontendSoundForMs('Remote_Ring',          'Phone_SoundSet_Default', 2200)
  playFrontendSoundForMs('Text_Arrive_Tone',     'Phone_SoundSet_Default', 350)

  local elapsed = GetGameTimer() - t0
  local remaining = callMs - elapsed
  if remaining > 0 then Wait(remaining) end

  playFrontendSoundForMs('Hang_Up', 'Phone_SoundSet_Default', 350)
end

local function playOperatorVoice()
  if not (Config.OperatorVoice and Config.OperatorVoice.enable) then return end

  local ped = PlayerPedId()
  local speechName = Config.OperatorVoice.speechName or 'GENERIC_HI'
  local voiceName  = Config.OperatorVoice.voiceName  or 'mp_f_stripperlite'
  local speechParam= Config.OperatorVoice.speechParam or 'SPEECH_PARAMS_FORCE_NORMAL'

  pcall(function()
    Citizen.InvokeNative(0x3523634255FC3318, ped, speechName, voiceName, speechParam, 0)
  end)
end

local phoneProp = nil

local function ensureAnimDict(dict)
  if HasAnimDictLoaded(dict) then return true end
  RequestAnimDict(dict)
  local t = GetGameTimer() + 5000
  while not HasAnimDictLoaded(dict) do
    Wait(0)
    if GetGameTimer() > t then return false end
  end
  return true
end

local function spawnAndAttachPhone(ped)
  if not (Config.PhoneCallAnim and Config.PhoneCallAnim.enable) then return end
  if phoneProp and DoesEntityExist(phoneProp) then return end

  local model = Config.PhoneCallAnim.prop or 'prop_npc_phone_02'
  local hash = joaat(model)
  if not IsModelInCdimage(hash) then return end

  RequestModel(hash)
  local t = GetGameTimer() + 3000
  while not HasModelLoaded(hash) do
    Wait(0)
    if GetGameTimer() > t then return end
  end

  local p = GetEntityCoords(ped)
  phoneProp = CreateObject(hash, p.x, p.y, p.z + 0.2, true, true, false)
  SetModelAsNoLongerNeeded(hash)

  if not DoesEntityExist(phoneProp) then return end

  local bone = Config.PhoneCallAnim.bone or 28422
  local pos  = Config.PhoneCallAnim.pos or { x=0.02, y=0.01, z=0.02 }
  local rot  = Config.PhoneCallAnim.rot or { x=0.0, y=0.0, z=0.0 }

  AttachEntityToEntity(
    phoneProp, ped, GetPedBoneIndex(ped, bone),
    pos.x or 0.0, pos.y or 0.0, pos.z or 0.0,
    rot.x or 0.0, rot.y or 0.0, rot.z or 0.0,
    true, true, false, true, 1, true
  )
end

local function stopPhoneProp()
  if phoneProp and DoesEntityExist(phoneProp) then
    DetachEntity(phoneProp, true, true)
    DeleteEntity(phoneProp)
  end
  phoneProp = nil
end

local function doPhoneCallAnimation(durationMs)
  local ped = PlayerPedId()

  if not (Config.PhoneCallAnim and Config.PhoneCallAnim.enable) then

    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_MOBILE", 0, true)
    Wait(durationMs)
    ClearPedTasks(ped)
    return
  end

  local dict = Config.PhoneCallAnim.dict or 'cellphone@'
  local anim = Config.PhoneCallAnim.anim or 'cellphone_call_listen_base'
  local flags = tonumber(Config.PhoneCallAnim.flags or 49) or 49

  ClearPedTasks(ped)

  if ensureAnimDict(dict) then
    spawnAndAttachPhone(ped)
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, flags, 0.0, false, false, false)
  else

    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_MOBILE", 0, true)
  end

  local endAt = GetGameTimer() + durationMs
  while GetGameTimer() < endAt do
    Wait(0)
    if IsPedRagdoll(ped) or IsEntityDead(ped) then break end

    if HasAnimDictLoaded(dict) and not IsEntityPlayingAnim(ped, dict, anim, 3) then
      TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, flags, 0.0, false, false, false)
    end
  end

  ClearPedTasks(ped)
  stopPhoneProp()
end

local function snapToRoadNode(x, y, z)
  local nodeType = tonumber(Config.RoadNodeType or 1)
  local radius   = tonumber(Config.RoadNodeRadius or 3.0)

  local found, pos, heading = GetClosestVehicleNodeWithHeading(x + 0.0, y + 0.0, z + 0.0, nodeType, radius, 0)
  if found and pos then
    return pos, (heading or 0.0)
  end

  local found2, pos2 = GetClosestVehicleNode(x + 0.0, y + 0.0, z + 0.0, nodeType, radius, 0)
  if found2 and pos2 then
    return pos2, 0.0
  end

  return nil, nil
end

local function getValidRoadSpawnAroundPlayer()
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)

  local minD = tonumber(Config.SpawnDistanceMin or 280.0)
  local maxD = tonumber(Config.SpawnDistanceMax or 520.0)
  local attempts = tonumber(Config.RoadSearchAttempts or 40)

  for _ = 1, attempts do
    local ang  = math.random() * math.pi * 2.0
    local dist = minD + (math.random() * (maxD - minD))

    local cx = p.x + math.cos(ang) * dist
    local cy = p.y + math.sin(ang) * dist
    local cz = p.z + 80.0

    local okGround, gz = GetGroundZFor_3dCoord(cx, cy, cz, false)
    if okGround then cz = gz end

    local nodePos, nodeH = snapToRoadNode(cx, cy, cz)
    if nodePos then
      local d = #(vector3(nodePos.x, nodePos.y, nodePos.z) - p)
      if d >= (minD * 0.65) then
        return { x=nodePos.x+0.0, y=nodePos.y+0.0, z=(nodePos.z+1.0)+0.0, h=(nodeH or 0.0)+0.0 }
      end
    end
  end

  local nodePos, nodeH = snapToRoadNode(p.x, p.y, p.z)
  if nodePos then
    return { x=nodePos.x+0.0, y=nodePos.y+0.0, z=(nodePos.z+1.0)+0.0, h=(nodeH or 0.0)+0.0 }
  end

  return { x=p.x+0.0, y=p.y+0.0, z=(p.z+1.0)+0.0, h=GetEntityHeading(ped)+0.0 }
end

local function getPlayerRoadDestination()
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local pos, _h = snapToRoadNode(p.x, p.y, p.z)
  if pos then
    return vector3(pos.x, pos.y, pos.z)
  end
  return vector3(p.x, p.y, p.z)
end

local spawnBlip = nil
local vehBlip   = nil

local function removeBlips()
  if spawnBlip and DoesBlipExist(spawnBlip) then RemoveBlip(spawnBlip) end
  if vehBlip   and DoesBlipExist(vehBlip)   then RemoveBlip(vehBlip)   end
  spawnBlip = nil
  vehBlip   = nil
end

local function setSpawnBlip(spawn)
  if spawnBlip and DoesBlipExist(spawnBlip) then RemoveBlip(spawnBlip) end
  spawnBlip = AddBlipForCoord(spawn.x, spawn.y, spawn.z)
  SetBlipSprite(spawnBlip, 225)
  SetBlipScale(spawnBlip, 0.85)
  SetBlipColour(spawnBlip, 1)
  SetBlipAsShortRange(spawnBlip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('Delivery Spawn')
  EndTextCommandSetBlipName(spawnBlip)
end

local function setVehBlip(veh)
  if vehBlip and DoesBlipExist(vehBlip) then RemoveBlip(vehBlip) end
  vehBlip = AddBlipForEntity(veh)
  SetBlipSprite(vehBlip, 225)
  SetBlipScale(vehBlip, 0.85)
  SetBlipAsShortRange(vehBlip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('Insurance Delivery')
  EndTextCommandSetBlipName(vehBlip)
  SetBlipRoute(vehBlip, true)
  SetBlipRouteColour(vehBlip, 1)
end

local function loadModel(model)
  local hash = modelToHashNoLoad(model)
  if not hash then return false end

  if not IsModelInCdimage(hash) then
    dbg(("IsModelInCdimage FAILED hash=%s input=%s"):format(tostring(hash), tostring(model)))
    return false
  end

  RequestModel(hash)
  local t = GetGameTimer() + 8000
  while not HasModelLoaded(hash) do
    Wait(0)
    if GetGameTimer() > t then
      dbg(("HasModelLoaded TIMEOUT hash=%s input=%s"):format(tostring(hash), tostring(model)))
      return false
    end
  end

  return hash
end

local function decodeJsonMaybe(v)
  if v == nil then return nil end
  if type(v) == 'table' then return v end
  if type(v) ~= 'string' then return nil end
  v = v:gsub('^%s+', ''):gsub('%s+$', '')
  if v == '' then return nil end
  local ok, data = pcall(function() return json.decode(v) end)
  if ok then return data end
  return nil
end

local function normalizeExtras(extras)
  if extras == nil then return nil end
  if type(extras) == 'table' then
    local isArray = (extras[1] ~= nil)
    if isArray then
      local out = {}
      for _, id in ipairs(extras) do
        local n = tonumber(id)
        if n then out[n] = 1 end
      end
      return out
    end
    return extras
  end
  if type(extras) == 'string' then
    return normalizeExtras(decodeJsonMaybe(extras))
  end
  return nil
end

CreateThread(function()
  pcall(function()
    if not DecorIsRegisteredAsType("_FUEL_LEVEL", 1) then
      DecorRegister("_FUEL_LEVEL", 1)
    end
  end)
end)

local function setFuelTo(veh, level)
  if not DoesEntityExist(veh) then return end
  level = tonumber(level) or 100.0

  pcall(function() SetVehicleFuelLevel(veh, level) end)
  pcall(function() DecorSetFloat(veh, "_FUEL_LEVEL", level) end)

  pcall(function()
    if exports and exports['ox_fuel'] and exports['ox_fuel'].SetFuel then
      exports['ox_fuel']:SetFuel(veh, level)
    end
  end)
  pcall(function()
    if exports and exports['LegacyFuel'] and exports['LegacyFuel'].SetFuel then
      exports['LegacyFuel']:SetFuel(veh, level)
    end
  end)
  pcall(function()
    if exports and exports['cdn-fuel'] and exports['cdn-fuel'].SetFuel then
      exports['cdn-fuel']:SetFuel(veh, level)
    end
  end)
  pcall(function()
    if exports and exports['cd_fuel'] and exports['cd_fuel'].SetFuel then
      exports['cd_fuel']:SetFuel(veh, level)
    end
  end)
  pcall(function()
    if exports and exports['ps-fuel'] and exports['ps-fuel'].SetFuel then
      exports['ps-fuel']:SetFuel(veh, level)
    end
  end)
end

local function setFuel100(veh)
  setFuelTo(veh, 100.0)
end

local function applyFullProps(veh, payload)
  if not DoesEntityExist(veh) then return end
  if type(payload) ~= 'table' then return end

  local propsWrapper = payload.props or {}
  local mods = decodeJsonMaybe(propsWrapper.mods) or {}

  local final = mods

  final.model = modelToHashNoLoad(payload.model) or final.model
  final.plate = payload.plate or propsWrapper.plate or final.plate

  final.color1 = propsWrapper.color1 or final.color1
  final.color2 = propsWrapper.color2 or final.color2
  final.windowTint = propsWrapper.windowTint or final.windowTint
  final.wheelColor = propsWrapper.wheelColor or final.wheelColor
  final.wheelType  = propsWrapper.wheelType  or final.wheelType
  final.pearlescentColor = propsWrapper.pearlescent or final.pearlescentColor
  final.extras = normalizeExtras(propsWrapper.extras) or normalizeExtras(final.extras)

  final.fuelLevel = 100

  if lib and lib.setVehicleProperties then
    pcall(function()
      lib.setVehicleProperties(veh, final)
    end)
  end

  setFuel100(veh)
end

local function forceDriveable(veh, seconds)
  seconds = tonumber(seconds) or 5
  if not DoesEntityExist(veh) then return end

  CreateThread(function()
    local untilT = GetGameTimer() + (seconds * 1000)
    while DoesEntityExist(veh) and GetGameTimer() < untilT do
      SetVehicleHandbrake(veh, false)
      SetVehicleUndriveable(veh, false)
      FreezeEntityPosition(veh, false)
      SetVehicleEngineOn(veh, true, true, false)
      Wait(250)
    end
  end)
end

local function repairAndClean(veh)
  if not DoesEntityExist(veh) then return end

  SetVehicleHandbrake(veh, false)
  SetVehicleUndriveable(veh, false)
  FreezeEntityPosition(veh, false)

  SetVehicleFixed(veh)
  SetVehicleDeformationFixed(veh)
  SetVehicleEngineHealth(veh, 1000.0)
  SetVehicleBodyHealth(veh, 1000.0)
  SetVehiclePetrolTankHealth(veh, 1000.0)

  SetVehicleDirtLevel(veh, 0.0)
  WashDecalsFromVehicle(veh, 1.0)

  SetVehicleEngineOn(veh, true, true, false)
end

local function plateUpper(p)
  p = tostring(p or ''):upper()
  if p == '' then return nil end
  return p
end

local function payloadPlate(payload, veh)
  local p = plateUpper(payload and payload.plate)
  if not p and payload and payload.props then
    p = plateUpper(payload.props.plate)
  end
  if not p and veh and DoesEntityExist(veh) then
    p = plateUpper(GetVehicleNumberPlateText(veh))
  end
  return p
end

local function svDeliveryDone(payload, veh, ok)
  local p = payloadPlate(payload, veh)
  TriggerServerEvent('nv_morsmutual:sv_deliveryDone', p, ok == true)
end

RegisterNUICallback('requestDelivery', function(data, cb)
  local plate = tostring(data and data.plate or ''):upper()
  dbg("NUI requestDelivery -> plate=" .. plate)

  if deliveryActive then
    cb({ ok=false, msg="Delivery already active." })
    return
  end
  if plate == '' then
    cb({ ok=false, msg="Invalid plate." })
    return
  end

  closeNuiHard("call_pressed")

  CreateThread(function()
    deliveryActive = true

    local callMs = (tonumber(Config.CallSeconds) or 9) * 1000

    CreateThread(function()
      playCallSequence(callMs)
    end)

    if Config.OperatorVoice and Config.OperatorVoice.enable then
      CreateThread(function()
        Wait(tonumber(Config.OperatorVoice.delayMs or 2300))
        playOperatorVoice()
      end)
    end

    doPhoneCallAnimation(callMs)
    stopAllPhoneSounds()

    local spawn = getValidRoadSpawnAroundPlayer()
    setSpawnBlip(spawn)

    TriggerServerEvent('nv_morsmutual:sv_requestDelivery', plate, spawn)
  end)

  cb({ ok=true })
end)

local activeVeh = nil
local activeDriver = nil
local deliveredVeh = nil

local function safeDeleteEntity(ent)
  if ent and DoesEntityExist(ent) then
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)
  end
end

local function clearDeliveryEntities(deleteVehicleToo)
  if activeDriver then
    safeDeleteEntity(activeDriver)
  end
  activeDriver = nil

  if deleteVehicleToo and activeVeh and DoesEntityExist(activeVeh) then
    if deliveredVeh ~= activeVeh then
      safeDeleteEntity(activeVeh)
    end
  end

  activeVeh = nil
end

local function driveToPlayer(driver, veh)
  local dest = getPlayerRoadDestination()

  ClearPedTasks(driver)

  TaskVehicleDriveToCoordLongrange(
    driver, veh,
    dest.x, dest.y, dest.z,
    tonumber(Config.DriveSpeed or 20.0),
    tonumber(Config.DrivingStyle or 786603),
    tonumber(Config.StopDistance or 8.0)
  )

  pcall(function()
    SetDriveTaskMaxCruiseSpeed(driver, tonumber(Config.DriveSpeed or 20.0))
  end)
end

local function teleportVehicleCloserToPlayerRoad(veh)
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)

  local minD = tonumber(Config.TeleportDistMin or 120.0)
  local maxD = tonumber(Config.TeleportDistMax or 180.0)

  for _ = 1, 12 do
    local ang  = math.random() * math.pi * 2.0
    local dist = minD + (math.random() * (maxD - minD))

    local cx = p.x + math.cos(ang) * dist
    local cy = p.y + math.sin(ang) * dist
    local cz = p.z + 80.0

    local okGround, gz = GetGroundZFor_3dCoord(cx, cy, cz, false)
    if okGround then cz = gz end

    local nodePos, nodeH = snapToRoadNode(cx, cy, cz)
    if nodePos then
      SetEntityCoordsNoOffset(veh, nodePos.x, nodePos.y, nodePos.z + 1.0, false, false, false)
      SetEntityHeading(veh, nodeH or GetEntityHeading(veh))
      SetVehicleOnGroundProperly(veh)
      return true
    end
  end

  local nodePos, nodeH = snapToRoadNode(p.x, p.y, p.z)
  if nodePos then
    SetEntityCoordsNoOffset(veh, nodePos.x, nodePos.y, nodePos.z + 1.0, false, false, false)
    SetEntityHeading(veh, nodeH or GetEntityHeading(veh))
    SetVehicleOnGroundProperly(veh)
    return true
  end

  return false
end

local function monitorArrival(payload, driver, veh)
  CreateThread(function()
    local timeout   = GetGameTimer() + (6 * 60 * 1000)
    local stopDist  = tonumber(Config.StopDistance or 8.0)
    local stuckSecs = tonumber(Config.StuckSeconds or 8)
    local tpAfter   = tonumber(Config.StuckTeleportAfter or 3)

    local lastPos    = GetEntityCoords(veh)
    local lastMoveAt = GetGameTimer()
    local reroutes   = 0

    while deliveryActive and DoesEntityExist(veh) and DoesEntityExist(driver) do
      Wait(500)

      if IsEntityDead(driver) or IsEntityDead(veh) then break end

      local ped = PlayerPedId()
      local p   = GetEntityCoords(ped)
      local v   = GetEntityCoords(veh)
      local dist = #(p - v)

      if math.random(1, 6) == 1 then
        driveToPlayer(driver, veh)
      end

      local moved = #(v - lastPos)
      local speed = GetEntitySpeed(veh)

      if moved > 2.0 then
        lastPos = v
        lastMoveAt = GetGameTimer()
      end

      local stuckFor = (GetGameTimer() - lastMoveAt) / 1000.0
      if dist > (stopDist + 25.0) and speed < 1.0 and stuckFor >= stuckSecs then
        reroutes = reroutes + 1
        dbg(("AI stuck (%.1fs). Reroute #%d"):format(stuckFor, reroutes))

        driveToPlayer(driver, veh)

        if reroutes >= tpAfter then
          dbg("Teleport failsafe triggered (stuck). Moving valet closer to road node.")
          teleportVehicleCloserToPlayerRoad(veh)
          driveToPlayer(driver, veh)
          reroutes = 0
        end

        lastMoveAt = GetGameTimer()
        lastPos = GetEntityCoords(veh)
      end

      if dist <= (stopDist + 2.0) then
        TaskVehicleTempAction(driver, veh, 27, 1200)
        SetVehicleHandbrake(veh, true)
        Wait(600)
        SetVehicleHandbrake(veh, false)

        TaskLeaveVehicle(driver, veh, 256)
        Wait(1400)

        safeDeleteEntity(driver)
        activeDriver = nil
        removeBlips()

        SetVehicleHasBeenOwnedByPlayer(veh, true)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleDoorsLocked(veh, 1)

        repairAndClean(veh)
        applyFullProps(veh, payload)

        setFuel100(veh)
        forceDriveable(veh, 6)

        deliveredVeh = veh
        activeVeh = nil

        notify('Your vehicle has been delivered (repaired, cleaned, fuel 100%).')

        svDeliveryDone(payload, veh, true)

        deliveryActive = false
        return
      end

      if GetGameTimer() > timeout then
        removeBlips()
        notify('Delivery timed out. Try again.')

        svDeliveryDone(payload, veh, false)

        deliveryActive = false
        clearDeliveryEntities(true)
        return
      end
    end

    removeBlips()
    svDeliveryDone(payload, veh, false)
    deliveryActive = false
    clearDeliveryEntities(true)
  end)
end

RegisterNetEvent('nv_morsmutual:cl_deliveryApproved', function(payload)
  dbg("cl_deliveryApproved received")

  if not payload or not payload.model or not payload.spawn then
    notify("Delivery failed: missing payload.")
    deliveryActive = false
    removeBlips()
    svDeliveryDone(payload, nil, false)
    return
  end

  clearDeliveryEntities(true)

  local vehHash = loadModel(payload.model)
  if not vehHash then
    notify('Vehicle model could not be loaded: ' .. tostring(payload.model))
    deliveryActive = false
    removeBlips()
    svDeliveryDone(payload, nil, false)
    return
  end

  local driverHash = loadModel(Config.DriverPedModel)
  if not driverHash then
    notify('Driver model could not be loaded.')
    deliveryActive = false
    removeBlips()
    svDeliveryDone(payload, nil, false)
    return
  end

  local s = payload.spawn
  do
    local pos, h = snapToRoadNode(s.x or 0.0, s.y or 0.0, s.z or 0.0)
    if not pos then
      s = getValidRoadSpawnAroundPlayer()
    else
      s = { x=pos.x+0.0, y=pos.y+0.0, z=(pos.z+1.0)+0.0, h=(h or s.h or 0.0)+0.0 }
    end
  end
  payload.spawn = s

  local veh = CreateVehicle(vehHash, s.x, s.y, s.z, s.h, true, true)
  if not DoesEntityExist(veh) then
    notify('Failed to create vehicle.')
    deliveryActive = false
    removeBlips()
    svDeliveryDone(payload, nil, false)
    return
  end

  activeVeh = veh
  SetEntityAsMissionEntity(veh, true, true)

  applyFullProps(veh, payload)
  setFuel100(veh)

  SetVehicleDoorsLocked(veh, 2)
  SetVehicleHandbrake(veh, false)
  SetVehicleUndriveable(veh, false)
  FreezeEntityPosition(veh, false)
  SetVehicleEngineOn(veh, true, true, false)
  SetVehicleOnGroundProperly(veh)

  local driver = CreatePedInsideVehicle(veh, 26, driverHash, -1, true, false)
  if not DoesEntityExist(driver) then
    notify('Failed to create driver.')
    deliveryActive = false
    removeBlips()
    safeDeleteEntity(veh)
    svDeliveryDone(payload, veh, false)
    return
  end

  activeDriver = driver
  SetEntityAsMissionEntity(driver, true, true)
  SetBlockingOfNonTemporaryEvents(driver, true)
  SetPedKeepTask(driver, true)
  SetPedCanBeDraggedOut(driver, false)
  SetDriverAbility(driver, 1.0)
  SetDriverAggressiveness(driver, 0.0)

  setVehBlip(veh)

  driveToPlayer(driver, veh)
  monitorArrival(payload, driver, veh)

  notify('Mors Mutual: your vehicle is on the way.')
end)

CreateThread(function()
  while true do
    Wait(0)
    if nuiOpen then
      if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 200) then
        closeNuiHard("esc_pressed")
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= RESOURCE then return end
  stopAllPhoneSounds()
  stopPhoneProp()
  closeNuiHard("resource_stop")
  removeBlips()
  deliveryActive = false
  clearDeliveryEntities(true)
end)
