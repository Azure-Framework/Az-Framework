Config = Config or {}

local function introCfg()
  return Config.IntroCutscene or {}
end

local function introDprint(fmt, ...)
  local cfg = introCfg()
  if cfg.Debug ~= true then return end
  local ok, msg = pcall(string.format, fmt, ...)
  print(("^5[azfw-intro]^7 %s"):format(ok and msg or tostring(fmt)))
end

local INTRO_FEMALE_PASSENGERS = {
  [1] = true,
  [2] = true,
  [4] = true,
  [6] = true,
}

local INTRO_PASSENGER_MODEL_POOL = {
  male = {
    'a_m_m_beach_01',
    'a_m_m_bevhills_01',
    'a_m_m_business_01',
    'a_m_m_eastsa_01',
    'a_m_m_genfat_01',
    'a_m_m_hillbilly_01',
    'a_m_m_ktown_01',
    'a_m_m_malibu_01',
    'a_m_m_mexcntry_01',
    'a_m_m_og_boss_01',
    'a_m_m_salton_01',
    'a_m_m_skater_01',
    'a_m_y_beach_01',
    'a_m_y_beachvesp_01',
    'a_m_y_business_01',
    'a_m_y_business_03',
    'a_m_y_genstreet_01',
    'a_m_y_hipster_01',
    'a_m_y_jetski_01',
    'a_m_y_runner_01',
    'a_m_y_smartcaspat_01',
    'a_m_y_stbla_01',
    'ig_talcc',
    'ig_trafficwarden',
    's_m_m_bouncer_01',
    's_m_m_dockwork_01',
    's_m_m_gaffer_01',
    's_m_m_migrant_01',
    's_m_y_airworker',
    's_m_y_baywatch_01',
    's_m_y_busboy_01',
    's_m_y_devinsec_01',
  },
  female = {
    'a_f_m_beach_01',
    'a_f_m_bevhills_01',
    'a_f_m_business_02',
    'a_f_m_ktown_01',
    'a_f_m_tourist_01',
    'a_f_m_trampbeac_01',
    'a_f_o_soucent_01',
    'a_f_y_beach_01',
    'a_f_y_bevhills_01',
    'a_f_y_business_01',
    'a_f_y_business_02',
    'a_f_y_business_04',
    'a_f_y_eastsa_03',
    'a_f_y_fitness_01',
    'a_f_y_genhot_01',
    'a_f_y_hipster_01',
    'a_f_y_runner_01',
    'a_f_y_scdressy_01',
    'a_f_y_tourist_01',
    'a_f_y_vinewood_01',
    'csb_abigail',
    'ig_kerrymcintosh',
    'ig_michelle',
    'ig_tanisha',
    's_f_y_airhostess_01',
    's_f_y_bartender_01',
    's_f_y_baywatch_01',
    's_f_y_clubbar_01',
    's_f_y_cop_01',
    's_f_y_shop_mid',
    'u_f_y_bikerchic',
  }
}

local INTRO_PASSENGER_NAMES = {
  [0] = "MP_Plane_Passenger_1",
  [1] = "MP_Plane_Passenger_2",
  [2] = "MP_Plane_Passenger_3",
  [3] = "MP_Plane_Passenger_4",
  [4] = "MP_Plane_Passenger_5",
  [5] = "MP_Plane_Passenger_6",
  [6] = "MP_Plane_Passenger_7",
}

local function _introMs()
  return GetGameTimer()
end

local function _introHideAllHudThisFrame()
  HideHudAndRadarThisFrame()
  for i = 1, 22 do
    HideHudComponentThisFrame(i)
  end
end

local function _introHideFrameworkHud()
  pcall(function()
    TriggerEvent('az-fw:client:setGameplayReady', false, 'intro_cutscene_active')
  end)
  pcall(function()
    SendNUIMessage({ action = 'setHudVisible', visible = false })
  end)
end

local function _introFiveAppearanceRes()
  if GetResourceState('fivem-appearance') == 'started' then return 'fivem-appearance' end
  if GetResourceState('fiveappearance') == 'started' then return 'fiveappearance' end
  if GetResourceState('five-appearance') == 'started' then return 'five-appearance' end
  return nil
end

local function _introNormalizeAppearance(raw)
  if raw == nil then return nil end
  if type(raw) == 'table' then return raw end
  if type(raw) == 'string' and raw ~= '' then
    local ok, decoded = pcall(function() return json.decode(raw) end)
    if ok and type(decoded) == 'table' then
      return decoded
    end
  end
  return nil
end

local function _introCoerceAppearance(ap)
  if type(ap) ~= 'table' then return nil end
  local out = ap
  if out.model == nil then out.model = out.pedModel or out.ped or out.modelHash or out.modelName end
  if out.components == nil then out.components = out.pedComponents or out.clothes or out.clothing or out.drawables end
  if out.props == nil then out.props = out.pedProps or out.accessories or out.propDrawables end
  if out.headBlend == nil then out.headBlend = out.headblend or out.head_blend end
  if out.faceFeatures == nil then out.faceFeatures = out.face_features or out.face end
  if out.headOverlays == nil then out.headOverlays = out.head_overlays or out.overlays end
  if out.hair == nil then out.hair = out.hairstyle or out.hairStyle end
  if out.tattoos == nil then out.tattoos = out.tattoo or out.tattooList end
  return out
end

local function _introTryGetModelFromAppearance(raw)
  local ap = _introCoerceAppearance(_introNormalizeAppearance(raw))
  if not ap then return nil end
  local m = ap.model or ap.pedModel or ap.ped
  if type(m) == 'string' and m ~= '' then return GetHashKey(m) end
  if type(m) == 'number' then return m end
  return nil
end

local function _introFetchAppearanceRaw(charid)
  charid = tostring(charid or '')
  if charid == '' or not (lib and lib.callback and lib.callback.await) then return nil end
  local ok, resp = pcall(function()
    return lib.callback.await('azfw:appearance:get', 12000, charid)
  end)
  if not ok then return nil end
  if type(resp) == 'table' then
    local ap = resp.appearance or resp.raw
    if ap ~= nil and _introNormalizeAppearance(ap) then
      return ap
    end
    return nil
  end
  if _introNormalizeAppearance(resp) then
    return resp
  end
  return nil
end

local function _introApplyAppearanceToPed(ped, raw, allowPlayerModelSwap)
  local res = _introFiveAppearanceRes()
  local appearance = _introCoerceAppearance(_introNormalizeAppearance(raw))
  if not res or not appearance or not ped or ped == 0 or not DoesEntityExist(ped) then return false end

  if allowPlayerModelSwap == true and ped == PlayerPedId() then
    local mh = _introTryGetModelFromAppearance(appearance)
    if mh and GetEntityModel(ped) ~= mh and IsModelInCdimage(mh) then
      RequestModel(mh)
      local t0 = _introMs()
      while not HasModelLoaded(mh) and (_introMs() - t0) < 10000 do
        Wait(0)
      end
      if HasModelLoaded(mh) then
        pcall(function() SetPlayerModel(PlayerId(), mh) end)
        SetModelAsNoLongerNeeded(mh)
        Wait(0)
        ped = PlayerPedId()
      end
    end
  end

  pcall(function() SetPedDefaultComponentVariation(ped) end)
  pcall(function() ClearAllPedProps(ped) end)

  local applied = false
  if exports[res] and exports[res].setPedAppearance then
    local ok = pcall(function() exports[res]:setPedAppearance(ped, appearance) end)
    if ok then applied = true end
  end
  if (not applied) and ped == PlayerPedId() and exports[res] and exports[res].setPlayerAppearance then
    local ok = pcall(function() exports[res]:setPlayerAppearance(appearance) end)
    if ok then applied = true end
  end
  if exports[res] and exports[res].setPedComponents and type(appearance.components) == 'table' then
    pcall(function() exports[res]:setPedComponents(ped, appearance.components) end)
  end
  if exports[res] and exports[res].setPedProps and type(appearance.props) == 'table' then
    pcall(function() exports[res]:setPedProps(ped, appearance.props) end)
  end
  if exports[res] and exports[res].setPedTattoos and type(appearance.tattoos) == 'table' then
    pcall(function() exports[res]:setPedTattoos(ped, appearance.tattoos) end)
  end
  return applied
end

local function _introLoadModel(model)
  local hash = type(model) == "number" and model or joaat(model)
  if not IsModelInCdimage(hash) then return false, hash end
  RequestModel(hash)
  local t0 = _introMs()
  while not HasModelLoaded(hash) and (_introMs() - t0) < 15000 do
    Wait(0)
  end
  return HasModelLoaded(hash), hash
end

local function _introIsFreemodeModel(modelHash)
  return modelHash == GetHashKey('mp_m_freemode_01') or modelHash == GetHashKey('mp_f_freemode_01')
end

local function _introPrepareCutsceneActor(realPed, appearanceRaw)
  if not realPed or realPed == 0 or not DoesEntityExist(realPed) then
    return realPed, false, false
  end

  local appearanceModel = _introTryGetModelFromAppearance(appearanceRaw)
  if appearanceModel and IsModelInCdimage(appearanceModel) and not _introIsFreemodeModel(appearanceModel) then
    local ok = false
    ok, appearanceModel = _introLoadModel(appearanceModel)
    if ok then
      local coords = GetEntityCoords(realPed)
      local actorPed = CreatePed(26, appearanceModel, coords.x, coords.y, coords.z - 25.0, GetEntityHeading(realPed), false, true)
      if actorPed and actorPed ~= 0 and DoesEntityExist(actorPed) then
        SetEntityVisible(actorPed, false, false)
        SetEntityInvincible(actorPed, true)
        SetEntityCollision(actorPed, false, false)
        FreezeEntityPosition(actorPed, true)
        SetBlockingOfNonTemporaryEvents(actorPed, true)
        pcall(function() SetPedCanRagdoll(actorPed, false) end)
        if appearanceRaw ~= nil then
          _introApplyAppearanceToPed(actorPed, appearanceRaw, false)
        end
        SetModelAsNoLongerNeeded(appearanceModel)
        return actorPed, true, true
      end
      SetModelAsNoLongerNeeded(appearanceModel)
    end
  end

  local clonePed = ClonePed(realPed, GetEntityHeading(realPed), false, true)
  if clonePed and clonePed ~= 0 and DoesEntityExist(clonePed) then
    SetEntityVisible(clonePed, false, false)
    SetEntityInvincible(clonePed, true)
    SetEntityCollision(clonePed, false, false)
    FreezeEntityPosition(clonePed, true)
    SetBlockingOfNonTemporaryEvents(clonePed, true)
    pcall(function() SetPedCanRagdoll(clonePed, false) end)
    if appearanceRaw ~= nil then
      _introApplyAppearanceToPed(clonePed, appearanceRaw, false)
    end
    return clonePed, true, false
  end

  return realPed, false, false
end

local function _introCleanupCutsceneActor(actorPed, createdActor)
  if createdActor == true and actorPed and actorPed ~= 0 and DoesEntityExist(actorPed) then
    DeleteEntity(actorPed)
  end
end

local function _introClearPedProps(ped)
  for i = 0, 8 do
    ClearPedProp(ped, i)
  end
end

local function _introRandomizePassenger(ped)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return end
  local model = GetEntityModel(ped)
  if model == GetHashKey('mp_m_freemode_01') or model == GetHashKey('mp_f_freemode_01') then
    SetPedRandomComponentVariation(ped, 0)
    _introClearPedProps(ped)
  end
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetEntityInvincible(ped, true)
  FreezeEntityPosition(ped, true)
  SetPedCanRagdoll(ped, false)
end

local function _introChoosePassengerModel(isFemale)
  local pool = isFemale and INTRO_PASSENGER_MODEL_POOL.female or INTRO_PASSENGER_MODEL_POOL.male
  if type(pool) ~= 'table' or #pool == 0 then
    return isFemale and 'mp_f_freemode_01' or 'mp_m_freemode_01'
  end
  local idx = math.random(1, #pool)
  return pool[idx]
end

local function _introRegisterMainPed(sourcePed)
  local sourceModel = GetEntityModel(sourcePed)
  local male = IsPedMale(sourcePed)
  local primary = male and "MP_Male_Character" or "MP_Female_Character"
  local secondary = male and "MP_Female_Character" or "MP_Male_Character"

  SetCutsceneEntityStreamingFlags(primary, 0, 1)
  RegisterEntityForCutscene(sourcePed, primary, 0, sourceModel, 64)
  SetCutsceneEntityStreamingFlags(secondary, 0, 1)
  local ped2 = RegisterEntityForCutscene(0, secondary, 3, male and GetHashKey('mp_f_freemode_01') or GetHashKey('mp_m_freemode_01'), 64)
  if ped2 and ped2 ~= 0 then
    NetworkSetEntityInvisibleToNetwork(ped2, true)
  end
  return male, primary
end

local function _introSyncPlayerLookToCutscene(cutsceneEntName, playerPed)
  if type(cutsceneEntName) ~= "string" or cutsceneEntName == "" then return end
  if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then return end

  pcall(function()
    SetCutscenePedComponentVariationFromPed(cutsceneEntName, playerPed, 0)
  end)

  for propId = 0, 7 do
    local propIndex = GetPedPropIndex(playerPed, propId)
    if propIndex and propIndex >= 0 then
      local propTexture = GetPedPropTextureIndex(playerPed, propId)
      local propHash = 0
      pcall(function()
        propHash = GetHashNameForProp(playerPed, propId, propIndex, propTexture)
      end)
      pcall(function()
        SetCutscenePedPropVariation(cutsceneEntName, propId, propIndex, propTexture, propHash or 0)
      end)
    end
  end
end

local function _introForceClonePlayerToCutscenePed(cutsceneEntName, playerPed)
  if type(cutsceneEntName) ~= "string" or cutsceneEntName == "" then return false end
  if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then return false end

  local okIdx, cutscenePed = pcall(function()
    return GetEntityIndexOfCutsceneEntity(cutsceneEntName, 0)
  end)
  if not okIdx or not cutscenePed or cutscenePed == 0 or not DoesEntityExist(cutscenePed) then
    return false
  end

  pcall(function()
    ClonePedToTarget(playerPed, cutscenePed)
  end)
  pcall(function()
    SetEntityVisible(cutscenePed, true, false)
  end)
  pcall(function()
    SetEntityInvincible(cutscenePed, true)
  end)
  _introSyncPlayerLookToCutscene(cutsceneEntName, playerPed)
  return true
end

local function _introSpawnPassengers()
  local spawned = {}
  for idx = 0, 6 do
    local model = _introChoosePassengerModel(INTRO_FEMALE_PASSENGERS[idx] == true)
    local ok, hash = _introLoadModel(model)
    if ok then
      local ped = CreatePed(26, hash, -1117.78, -1557.62, 3.38, 0.0, false, true)
      if ped and ped ~= 0 then
        _introRandomizePassenger(ped)
        RegisterEntityForCutscene(ped, INTRO_PASSENGER_NAMES[idx], idx, 0, 64)
        spawned[#spawned + 1] = ped
      end
      SetModelAsNoLongerNeeded(hash)
    end
  end
  return spawned
end

local function _introCleanupPassengers(spawned)
  for i = 1, #(spawned or {}) do
    local ped = spawned[i]
    if ped and ped ~= 0 and DoesEntityExist(ped) then
      DeleteEntity(ped)
    end
  end
end

local function _introSafeStopCutscene()
  if IsCutscenePlaying() then
    StopCutsceneImmediately()
  end
  if HasCutsceneLoaded() then
    RemoveCutscene()
  end
  StopAudioScenes()
  StopGameplayCamShaking(true)
  StopScreenEffect("DeathFailOut")
end

local function _introTeleportPed(ped, spawn)
  if not ped or ped == 0 or type(spawn) ~= "table" then return end
  local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
  local h = tonumber(spawn.h or spawn.heading) or 0.0
  if not x or not y or not z then return end

  SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
  SetEntityHeading(ped, h)
  RequestCollisionAtCoord(x, y, z)
  local t0 = _introMs()
  while not HasCollisionLoadedAroundEntity(ped) and (_introMs() - t0) < 7000 do
    RequestCollisionAtCoord(x, y, z)
    Wait(0)
  end
end

local function _introDestroyCam(cam)
  if cam and DoesCamExist(cam) then
    DestroyCam(cam, false)
  end
end

local function _introScriptCamForShot(shotIdx, coords, heading)
  local zBase = coords.z
  local lookZ = zBase + 0.95
  local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
  if shotIdx == 1 then
    SetCamCoord(cam, coords.x - 9.0, coords.y - 5.5, zBase + 4.2)
    PointCamAtCoord(cam, coords.x, coords.y, lookZ)
  elseif shotIdx == 2 then
    SetCamCoord(cam, coords.x + 6.0, coords.y - 2.0, zBase + 1.8)
    PointCamAtCoord(cam, coords.x, coords.y, lookZ + 0.15)
  elseif shotIdx == 3 then
    SetCamCoord(cam, coords.x - 1.5, coords.y + 8.5, zBase + 3.1)
    PointCamAtCoord(cam, coords.x, coords.y, lookZ)
  else
    local rad = math.rad((heading or 0.0) + 180.0)
    local backX = math.sin(rad) * 4.8
    local backY = math.cos(rad) * 4.8
    SetCamCoord(cam, coords.x + backX, coords.y + backY, zBase + 1.4)
    PointCamAtCoord(cam, coords.x, coords.y, lookZ)
  end
  SetCamFov(cam, 52.0)
  return cam
end

local function _introPlayScriptedAtSpawn(spawn)
  local cfg = introCfg()
  _introHideFrameworkHud()
  local ped = PlayerPedId()
  if not ped or ped == 0 then
    return false, { reason = "no_ped" }
  end

  local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
  local h = tonumber(spawn.h or spawn.heading) or 0.0
  if not x or not y or not z then
    return false, { reason = "bad_spawn" }
  end

  local duration = tonumber(cfg.ScriptedDurationMs) or 14000
  if duration < 6000 then duration = 6000 end

  local coords = vector3(x, y, z)
  _introTeleportPed(ped, spawn)
  FreezeEntityPosition(ped, true)
  SetPlayerControl(PlayerId(), false, 0)
  if not IsScreenFadedOut() then
    DoScreenFadeOut(0)
  end
  if cfg.WeatherType and cfg.WeatherType ~= "" then
    SetWeatherTypeNowPersist(tostring(cfg.WeatherType))
  end

  local activeCam = _introScriptCamForShot(1, coords, h)
  SetCamActive(activeCam, true)
  RenderScriptCams(true, true, 1200, true, true)
  DoScreenFadeIn(800)

  local shotLength = math.floor(duration / 4)
  local shotEnds = {
    shotLength,
    shotLength * 2,
    shotLength * 3,
    duration,
  }

  local startedAt = _introMs()
  local currentShot = 1
  while (_introMs() - startedAt) < duration do
    local elapsed = _introMs() - startedAt
    local desiredShot = currentShot
    if elapsed >= shotEnds[3] then
      desiredShot = 4
    elseif elapsed >= shotEnds[2] then
      desiredShot = 3
    elseif elapsed >= shotEnds[1] then
      desiredShot = 2
    end

    if desiredShot ~= currentShot then
      local nextCam = _introScriptCamForShot(desiredShot, coords, h)
      SetCamActiveWithInterp(nextCam, activeCam, 1800, true, true)
      Wait(50)
      _introDestroyCam(activeCam)
      activeCam = nextCam
      currentShot = desiredShot
    end

    _introHideAllHudThisFrame()
    DisableAllControlActions(0)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 200, true)
    Wait(0)
  end

  DoScreenFadeOut(450)
  local fadeT0 = _introMs()
  while not IsScreenFadedOut() and (_introMs() - fadeT0) < 1500 do
    Wait(0)
  end

  RenderScriptCams(false, true, 800, true, true)
  Wait(200)
  _introDestroyCam(activeCam)
  ClearFocus()
  SetPlayerControl(PlayerId(), true, 0)
  FreezeEntityPosition(ped, false)
  _introTeleportPed(ped, spawn)

  return true, {
    endedNaturally = true,
    forcedStop = false,
    scripted = true,
    durationMs = duration,
  }
end

local function _introPlayNativeAtSpawn(spawn, context)
  local cfg = introCfg()
  local cut = cfg.Cutscene or {}
  context = type(context) == "table" and context or {}
  local appearanceRaw = _introFetchAppearanceRaw(context.charid)
  local realPed = PlayerPedId()
  if not realPed or realPed == 0 then
    return false
  end

  _introHideFrameworkHud()

  if appearanceRaw ~= nil then
    _introApplyAppearanceToPed(realPed, appearanceRaw, true)
    Wait(100)
    realPed = PlayerPedId()
  end

  local sourcePed, createdActor = _introPrepareCutsceneActor(realPed, appearanceRaw)
  local playback = IsPedMale(sourcePed) and tonumber(cut.MalePlaybackList) or tonumber(cut.FemalePlaybackList)
  playback = playback or 31
  local flags = tonumber(cut.Flags) or 8
  local startFlags = tonumber(cut.StartFlags) or 4
  local cutsceneName = tostring(cut.Name or "MP_INTRO_CONCAT")
  local loadTimeout = tonumber(cut.LoadTimeoutMs) or 15000
  local duration = tonumber(cut.DurationMs) or 31520
  local forceStopAt = tonumber(cut.ForceStopAtDurationMs or 0) or 0
  local maxWaitMs = tonumber(cut.MaxWaitMs) or math.max(duration + 15000, 90000)
  local sceneX = tonumber(cut.SceneX) or -1212.79
  local sceneY = tonumber(cut.SceneY) or -1673.52
  local sceneZ = tonumber(cut.SceneZ) or 7.0
  local sceneRadius = tonumber(cut.SceneRadius) or 1000.0

  PrepareMusicEvent("FM_INTRO_START")
  TriggerMusicEvent("FM_INTRO_START")

  RequestCutsceneWithPlaybackList(cutsceneName, playback, flags)
  local t0 = _introMs()
  while not HasCutsceneLoaded() and (_introMs() - t0) < loadTimeout do
    Wait(10)
  end
  if not HasCutsceneLoaded() then
    introDprint("cutscene load timeout")
    _introSafeStopCutscene()
    return false
  end

  local _, cutsceneMainName = _introRegisterMainPed(sourcePed)
  _introSyncPlayerLookToCutscene(cutsceneMainName, sourcePed)
  local passengers = _introSpawnPassengers()

  NewLoadSceneStartSphere(sceneX, sceneY, sceneZ, sceneRadius, 0)
  SetFocusPosAndVel(sceneX, sceneY, sceneZ, 0.0, 0.0, 0.0)
  RequestCollisionAtCoord(sceneX, sceneY, sceneZ)
  if cfg.WeatherType and cfg.WeatherType ~= "" then
    SetWeatherTypeNowPersist(tostring(cfg.WeatherType))
  end

  FreezeEntityPosition(realPed, true)
  SetPlayerControl(PlayerId(), false, 0)

  StartCutscene(startFlags)

  local startWaitMs = tonumber(cut.StartWaitMs) or 12000
  local waitStart = _introMs()
  local fadeShown = false
  while not IsCutscenePlaying() and (_introMs() - waitStart) < startWaitMs do
    _introHideAllHudThisFrame()
    DisableAllControlActions(0)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 200, true)
    _introHideFrameworkHud()
    _introSyncPlayerLookToCutscene(cutsceneMainName, sourcePed)
    _introForceClonePlayerToCutscenePed(cutsceneMainName, sourcePed)
    if appearanceRaw ~= nil then
      local okIdx, cutscenePed = pcall(function() return GetEntityIndexOfCutsceneEntity(cutsceneMainName, 0) end)
      if okIdx and cutscenePed and cutscenePed ~= 0 and DoesEntityExist(cutscenePed) then
        _introApplyAppearanceToPed(cutscenePed, appearanceRaw, false)
      end
    end
    if not IsScreenFadedOut() then
      DoScreenFadeOut(0)
    end
    Wait(0)
  end

  if not IsCutscenePlaying() then
    introDprint("cutscene failed to enter playing state after %dms", startWaitMs)
    _introCleanupPassengers(passengers)
    PrepareMusicEvent("AC_STOP")
    TriggerMusicEvent("AC_STOP")
    _introSafeStopCutscene()
    NewLoadSceneStop()
    FreezeEntityPosition(realPed, false)
    SetPlayerControl(PlayerId(), true, 0)
    _introCleanupCutsceneActor(sourcePed, createdActor)
    return false, { reason = "failed_to_start", startWaitMs = startWaitMs }
  end

  local startedAt = _introMs()
  local endedNaturally = false
  local syncedCutsceneLook = false
  local cloneAttempts = 0
  while IsCutscenePlaying() do
    local elapsed = _introMs() - startedAt
    _introHideAllHudThisFrame()
    _introHideFrameworkHud()
    DisableAllControlActions(0)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 200, true)
    if not fadeShown then
      DoScreenFadeIn(800)
      fadeShown = true
    end
    if DoesCutsceneEntityExist(cutsceneMainName, 0) then
      if not syncedCutsceneLook then
        _introHideFrameworkHud()
        _introSyncPlayerLookToCutscene(cutsceneMainName, sourcePed)
        if appearanceRaw ~= nil then
          local okIdx, cutscenePed = pcall(function() return GetEntityIndexOfCutsceneEntity(cutsceneMainName, 0) end)
          if okIdx and cutscenePed and cutscenePed ~= 0 and DoesEntityExist(cutscenePed) then
            _introApplyAppearanceToPed(cutscenePed, appearanceRaw, false)
          end
        end
        syncedCutsceneLook = true
      end
      if cloneAttempts < 25 then
        if _introForceClonePlayerToCutscenePed(cutsceneMainName, sourcePed) then
          if appearanceRaw ~= nil then
            local okIdx, cutscenePed = pcall(function() return GetEntityIndexOfCutsceneEntity(cutsceneMainName, 0) end)
            if okIdx and cutscenePed and cutscenePed ~= 0 and DoesEntityExist(cutscenePed) then
              _introApplyAppearanceToPed(cutscenePed, appearanceRaw, false)
            end
          end
          cloneAttempts = cloneAttempts + 1
        end
      end
    end
    if forceStopAt > 0 and elapsed >= forceStopAt then
      introDprint("force-stopping cutscene after %dms", forceStopAt)
      break
    end
    if elapsed >= maxWaitMs then
      introDprint("cutscene safety timeout after %dms", maxWaitMs)
      break
    end
    Wait(0)
  end
  endedNaturally = not IsCutscenePlaying()
  Wait(150)

  _introCleanupPassengers(passengers)
  PrepareMusicEvent("AC_STOP")
  TriggerMusicEvent("AC_STOP")
  _introSafeStopCutscene()
  NewLoadSceneStop()
  ClearFocus()

  DoScreenFadeOut(900)
  local fadeT0 = _introMs()
  while not IsScreenFadedOut() and (_introMs() - fadeT0) < 1800 do
    Wait(0)
  end

  if appearanceRaw ~= nil then
    _introApplyAppearanceToPed(realPed, appearanceRaw, true)
    Wait(0)
    realPed = PlayerPedId()
  end
  SetEntityVisible(realPed, false, false)
  _introTeleportPed(realPed, spawn)
  FreezeEntityPosition(realPed, false)
  SetPlayerControl(PlayerId(), true, 0)
  _introCleanupCutsceneActor(sourcePed, createdActor)
  return true, {
    endedNaturally = endedNaturally,
    forcedStop = not endedNaturally,
    maxWaitMs = maxWaitMs,
    forceStopAt = forceStopAt,
  }
end

local function _introPlaySpawnDeathScreen(opts)
  opts = opts or {}
  if opts.Enabled == false then return end
  local duration = tonumber(opts.DurationMs) or 4200
  local endsAt = _introMs() + duration
  local shard = nil
  local effectName = tostring(opts.ScreenEffect or "")
  local timecycle = tostring(opts.Timecycle or "")
  local extraTimecycle = tostring(opts.ExtraTimecycle or "")

  if effectName ~= "" then
    StartScreenEffect(effectName, 0, true)
  end
  if opts.UseTimecycle ~= false and timecycle ~= "" then
    SetTimecycleModifier(timecycle)
    SetTimecycleModifierStrength(tonumber(opts.TimecycleStrength) or 0.70)
  end
  if extraTimecycle ~= "" then
    SetExtraTimecycleModifier(extraTimecycle)
  end
  if opts.MotionBlur ~= false then
    AnimpostfxPlay("MinigameTransitionOut", duration, false)
  end
  if opts.PlaySound ~= false then
    PlaySoundFrontend(-1, tostring(opts.SoundName or "Bed"), tostring(opts.SoundSet or "WastedSounds"), true)
  end

  if opts.ShowShard ~= false then
    shard = RequestScaleformMovie("MP_BIG_MESSAGE_FREEMODE")
    local loadUntil = _introMs() + 3000
    while shard and shard ~= 0 and not HasScaleformMovieLoaded(shard) and _introMs() < loadUntil do
      Wait(0)
    end
    if shard and shard ~= 0 and HasScaleformMovieLoaded(shard) then
      BeginScaleformMovieMethod(shard, "SHOW_SHARD_WASTED_MP_MESSAGE")
      ScaleformMovieMethodAddParamPlayerNameString(tostring(opts.Title or "WASTED"))
      ScaleformMovieMethodAddParamPlayerNameString(tostring(opts.Subtitle or ""))
      EndScaleformMovieMethod()
    else
      shard = nil
    end
  end

  while _introMs() < endsAt do
    Wait(0)
    if shard then
      DrawScaleformMovieFullscreen(shard, 255, 255, 255, 255, 0)
    end
    _introHideAllHudThisFrame()
  end

  if shard then
    SetScaleformMovieAsNoLongerNeeded(shard)
  end
  if effectName ~= "" then
    StopScreenEffect(effectName)
  end
  ClearTimecycleModifier()
  if extraTimecycle ~= "" then
    ClearExtraTimecycleModifier()
  end
end

_G.AzFwPlayIntroCutsceneIfNeeded = function(context)
  local cfg = introCfg()
  if cfg.Enabled ~= true then
    return { played = false, reason = "disabled" }
  end

  context = type(context) == "table" and context or {}
  local spawn = context.spawn
  if type(spawn) ~= "table" then
    return { played = false, reason = "no_spawn" }
  end

  local result = lib.callback.await("azfw:intro:shouldPlay", false, {
    mode = tostring(context.mode or "ui"),
    isNewCharacter = context.isNewCharacter == true,
    charid = tostring(context.charid or ""),
  })

  if type(result) ~= "table" or result.play ~= true then
    return { played = false, reason = type(result) == "table" and result.reason or "server_no" }
  end

  local useNative = cfg.UseNativeGtaCutscene == true
  local played, playMeta
  if useNative then
    played, playMeta = _introPlayNativeAtSpawn(spawn, context)
  else
    played, playMeta = _introPlayScriptedAtSpawn(spawn)
  end
  if played then
    TriggerServerEvent("azfw:intro:markSeen", {
      charid = tostring(context.charid or ""),
      name = tostring(GetPlayerName(PlayerId()) or "")
    })
  end

  return {
    played = played,
    reason = played and "played" or tostring(type(playMeta) == "table" and playMeta.reason or "failed"),
    showDeathScreenAfter = played and (result.showDeathScreenAfter ~= false) or false,
    cutscene = playMeta,
  }
end

_G.AzFwPlayIntroForCurrentSpawnIfNeeded = function(context)
  context = type(context) == "table" and context or {}
  local ped = PlayerPedId()
  if not ped or ped == 0 then return { played = false, reason = "no_ped" } end
  local coords = GetEntityCoords(ped)
  context.spawn = context.spawn or {
    x = coords.x,
    y = coords.y,
    z = coords.z,
    h = GetEntityHeading(ped)
  }
  return _G.AzFwPlayIntroCutsceneIfNeeded(context)
end

_G.AzFwShowSpawnDeathScreen = function(opts)
  _introPlaySpawnDeathScreen(opts or (Config.SpawnDeathScreen or {}))
end
