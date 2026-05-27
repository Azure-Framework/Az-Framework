local RESOURCE_NAME = GetCurrentResourceName()
local RES = RESOURCE_NAME

Config = Config or {}

local function __azfw_character_ui_enabled()
  local modules = Config.Modules or {}
  local charCfg = Config.Character or {}
  local mode = tostring(charCfg.Mode or ((modules.CharacterUI == true) and "ui" or "discord")):lower()
  return modules.CharacterSystem ~= false and modules.CharacterUI == true and mode == "ui"
end

if not __azfw_character_ui_enabled() then
  print(("^3[%s]^7 merged CharacterUI disabled by config; lightweight character mode remains active."):format(RESOURCE_NAME))
  return
end

Config.Debug = (Config.Debug == true)

Config.EnableLastLocation = (Config.EnableLastLocation ~= false)
Config.LastLocationUpdateIntervalMs = tonumber(Config.LastLocationUpdateIntervalMs) or 10000
Config.EnableFiveAppearance = (Config.EnableFiveAppearance ~= false)

Config.EnableOpenCommand = (Config.EnableOpenCommand ~= false)
Config.OpenCommand = tostring(Config.OpenCommand or "characters")

Config.EnableSpawnMenuCommand = (Config.EnableSpawnMenuCommand ~= false)
Config.SpawnMenuCommand = tostring(Config.SpawnMenuCommand or "spawnmenu")
Config.SpawnMenuAdminOnly = (Config.SpawnMenuAdminOnly ~= false)

Config.Preview = Config.Preview or {}
Config.Preview.Enabled = (Config.Preview.Enabled ~= false)
Config.Preview.Scene = Config.Preview.Scene or vector4(402.92, -996.82, -99.00, 180.0)
Config.Preview.PedOffset = Config.Preview.PedOffset or vector3(0.0, 0.0, 0.3)
Config.Preview.CamFov = tonumber(Config.Preview.CamFov) or 50.0
Config.Preview.CamInterpMs = tonumber(Config.Preview.CamInterpMs) or 250

Config.Preview.Camera = Config.Preview.Camera or {}
Config.Preview.Camera.Enabled = (Config.Preview.Camera.Enabled ~= false)
Config.Preview.Camera.Forward = tonumber(Config.Preview.Camera.Forward) or 2.80
Config.Preview.Camera.Right = tonumber(Config.Preview.Camera.Right) or -0.15
Config.Preview.Camera.Up = tonumber(Config.Preview.Camera.Up) or 0.00
Config.Preview.Camera.TargetUp = tonumber(Config.Preview.Camera.TargetUp) or -0.35

Config.Preview.PrefetchAppearances = (Config.Preview.PrefetchAppearances ~= false)
Config.Preview.PrefetchLimit = tonumber(Config.Preview.PrefetchLimit) or 16
Config.Preview.FetchAttempts = tonumber(Config.Preview.FetchAttempts) or 10
Config.Preview.FetchWaitMs = tonumber(Config.Preview.FetchWaitMs) or 250
Config.Preview.NegativeCacheMs = tonumber(Config.Preview.NegativeCacheMs) or 4000

Config.MugshotEnabled = (Config.MugshotEnabled ~= false)
Config.MugshotRefreshMs = tonumber(Config.MugshotRefreshMs) or 700

Config.Preview.Mugshot = Config.Preview.Mugshot or {}
Config.Preview.Mugshot.Enabled = (Config.Preview.Mugshot.Enabled ~= false)
Config.Preview.Mugshot.DeptText = tostring(Config.Preview.Mugshot.DeptText or "YOUR SERVER NAME")
Config.Preview.Mugshot.BoardProp = tostring(Config.Preview.Mugshot.BoardProp or "prop_police_id_board")
Config.Preview.Mugshot.TextProp  = tostring(Config.Preview.Mugshot.TextProp or "prop_police_id_text")
Config.Preview.Mugshot.HandBone  = tonumber(Config.Preview.Mugshot.HandBone) or 28422

local firstSpawn = true
local nuiOpen = false
local spawnNuiOpen = false
local nuiOwner = nil
local nuiReady = false
local cachedChars = {}
local currentCharId = nil
local selectionLockUntil = 0
local SELECTION_LOCK_TIME = 5000
local destroyMugshot

local __pendingNewCharCustomize = false
local __allowCustomizeNow = false
local __pendingNewCharCid = nil
local __azfwIntroNewCharacterCharId = nil
local __azfwIntroPlayedThisSession = false
local __pendingNewCharPreSpawnAppearanceCid = nil
local __preSpawnCustomizeBusy = false
local __continueToSpawnAfterCustomizeCid = nil
local continueToSpawnSelectorAfterAppearance
local reopenCharacterUiAfterAppearanceCancel

local STAGE_BOOT      = "boot"
local STAGE_CHAR_UI   = "char_ui"
local STAGE_SPAWN_UI  = "spawn_ui"
local STAGE_SPAWNING  = "spawning"
local STAGE_IN_WORLD  = "in_world"

local stage = STAGE_BOOT
local function setStage(s, reason)
  if stage == s then return end
  stage = s
  if Config.Debug then
    print(("^5[%s]^7 stage=%s (%s)"):format(RESOURCE_NAME, tostring(stage), tostring(reason or "unknown")))
  end
end

local playerSpawnedInWorld = false
local function setSpawnedInWorld(on, reason)
  on = on and true or false
  if playerSpawnedInWorld == on then return end
  playerSpawnedInWorld = on

  if on then
    setStage(STAGE_IN_WORLD, reason or "spawned_in_world")
  else
    if not (nuiOpen or spawnNuiOpen) then
      setStage(STAGE_BOOT, reason or "not_in_world")
    end
  end

  pcall(function()
    if LocalPlayer and LocalPlayer.state then
      LocalPlayer.state:set('azfwGameplayReady', on, false)
    end
  end)
  TriggerEvent('az-fw:client:setGameplayReady', on, reason or 'characterui_stage')

  if Config.Debug then
    print(("^5[%s]^7 spawnedInWorld=%s (%s)"):format(RESOURCE_NAME, tostring(on), tostring(reason or "unknown")))
  end
end

local function ms() return GetGameTimer() end

local function dprint(fmt, ...)
  if not Config.Debug then return end
  local ok, msg = pcall(string.format, fmt, ...)
  if ok then
    print(("^5[%s]^7 %s"):format(RESOURCE_NAME, msg))
  else
    print(("^5[%s]^7 %s"):format(RESOURCE_NAME, tostring(fmt)))
  end
end

local function blockAppearanceOpenEvent(ev)
  RegisterNetEvent(ev)
  AddEventHandler(ev, function(...)
    if nuiOpen or spawnNuiOpen or stage ~= STAGE_IN_WORLD then
      dprint("BLOCKED external appearance opener: %s stage=%s nui=%s spawn=%s", tostring(ev), tostring(stage), tostring(nuiOpen), tostring(spawnNuiOpen))
      CancelEvent()
      return
    end
  end)
end

for _, ev in ipairs({
  "fivem-appearance:client:openclothingmenu",
  "fivem-appearance:client:openClothingMenu",
  "fivem-appearance:client:openPlayerCustomization",
  "fivem-appearance:client:startPlayerCustomization",
  "fivem-appearance:open",
  "illenium-appearance:client:openClothingMenu",
  "illenium-appearance:client:openBarberMenu",
  "illenium-appearance:client:openTattooMenu",
}) do
  blockAppearanceOpenEvent(ev)
end

local function nuiSend(payload) SendNUIMessage(payload) end

local function applyHudAndMinimap()

  pcall(function() DisplayHud(true) end)
  pcall(function() DisplayRadar(true) end)
  pcall(function() SetRadarBigmapEnabled(false, false) end)
  pcall(function() SetBigmapActive(false, false) end)
  pcall(function() SetMinimapClipType(0) end)
  pcall(function() SetRadarAsExteriorThisFrame() end)
end

local _hudMinimapRestoreToken = 0
local function reinforceHudAndMinimap(durationMs)
  durationMs = tonumber(durationMs) or 2500
  if durationMs < 250 then durationMs = 250 end

  _hudMinimapRestoreToken = _hudMinimapRestoreToken + 1
  local myToken = _hudMinimapRestoreToken
  local endsAt = ms() + durationMs

  CreateThread(function()
    while _hudMinimapRestoreToken == myToken and ms() < endsAt do
      if not nuiOpen and not spawnNuiOpen then
        applyHudAndMinimap()
      end
      Wait(0)
    end

    if _hudMinimapRestoreToken == myToken and not nuiOpen and not spawnNuiOpen then
      applyHudAndMinimap()
    end
  end)
end

local function focusOff()
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
end

local function focusOn()
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
end

local function hardResetFocus()
  focusOff()
  Wait(0)
  if nuiOwner then focusOn() end
  SetTimeout(60, function() if (nuiOpen or spawnNuiOpen) and nuiOwner then focusOn() end end)
  SetTimeout(200, function() if (nuiOpen or spawnNuiOpen) and nuiOwner then focusOn() end end)
end

local function setNuiOwner(owner)
  nuiOwner = owner
  if owner then
    hardResetFocus()
  else
    focusOff()
  end
end

CreateThread(function()
  while true do
    Wait(120)
    if (nuiOpen or spawnNuiOpen) and nuiOwner and (not nuiReady) then
      focusOn()
    else
      Wait(250)
    end
  end
end)

CreateThread(function()
  while true do
    if nuiOpen or spawnNuiOpen then
      Wait(0)
      DisableAllControlActions(0)
      EnableControlAction(0, 200, true)
      EnableControlAction(0, 322, true)
      EnableControlAction(0, 245, true)
      DisplayRadar(false)
    else
      Wait(250)
    end
  end
end)

local function deathResRunning()
  local standalone = GetResourceState("Az-Death")
  if standalone == "started" or standalone == "starting" then
    return true, 'standalone'
  end

  if GetCurrentResourceName() == 'Az-Framework' and type(Config) == 'table' and type(Config.Death) == 'table' and Config.Death.Enabled ~= false then
    return true, 'embedded'
  end

  return false, nil
end

local function deathPause(on)
  local ok, mode = deathResRunning()
  if not ok then return end
  pcall(function()
    if mode == 'standalone' and exports["Az-Death"] and exports["Az-Death"].setInjuryPaused then
      exports["Az-Death"]:setInjuryPaused(on and true or false)
    else
      TriggerEvent("Az-Death:injury:pause", on and true or false)
    end
  end)
end

local function deathSuppress(msToSuppress)
  local ok, mode = deathResRunning()
  if not ok then return end
  msToSuppress = tonumber(msToSuppress) or 2500
  pcall(function()
    if mode == 'standalone' and exports["Az-Death"] and exports["Az-Death"].suppressInjuries then
      exports["Az-Death"]:suppressInjuries(msToSuppress)
    else
      TriggerEvent("Az-Death:injury:suppress", msToSuppress)
    end
  end)
end

local json = json

local function resStarted(name)
  local st = GetResourceState(name)
  return st == "started" or st == "starting"
end

local function fiveAppearanceRes()
  if resStarted("fivem-appearance") then return "fivem-appearance" end
  if resStarted("fiveappearance") then return "fiveappearance" end
  if resStarted("five-appearance") then return "five-appearance" end
  return nil
end

local function customizationEnabled()
  return Config.UseAppearance == true
end

local function requestModel(hash)
  if not hash then return false end
  RequestModel(hash)
  local t0 = ms()
  while not HasModelLoaded(hash) and (ms() - t0) < 12000 do Wait(0) end
  return HasModelLoaded(hash)
end

local function normalizeAppearance(raw)
  if raw == nil then return nil end
  if type(raw) == "table" then return raw end
  if type(raw) == "string" then
    if raw == "" then return nil end
    local ok, v = pcall(function() return json.decode(raw) end)
    if ok and type(v) == "table" then return v end
  end
  return nil
end

local function coercePedAppearance(ap)
  if type(ap) ~= "table" then return nil end
  local out = ap

  if out.model == nil then
    out.model = out.pedModel or out.ped or out.modelHash or out.modelName
  end

  if out.components == nil then
    out.components = out.pedComponents or out.clothes or out.clothing or out.drawables
  end
  if out.props == nil then
    out.props = out.pedProps or out.accessories or out.propDrawables
  end

  if out.headBlend == nil then out.headBlend = out.headblend or out.head_blend end
  if out.faceFeatures == nil then out.faceFeatures = out.face_features or out.face end
  if out.headOverlays == nil then out.headOverlays = out.head_overlays or out.overlays end
  if out.hair == nil then out.hair = out.hairstyle or out.hairStyle end
  if out.tattoos == nil then out.tattoos = out.tattoo or out.tattooList end

  return out
end

local function tryGetModelFromAppearance(raw)
  local ap = coercePedAppearance(normalizeAppearance(raw))
  if not ap then return nil end
  local m = ap.model or ap.pedModel or ap.ped
  if type(m) == "string" and m ~= "" then return GetHashKey(m) end
  if type(m) == "number" then return m end
  return nil
end

local function setPlayerModelHash(mh)
  if not mh then return false end
  local ped = PlayerPedId()
  if DoesEntityExist(ped) and GetEntityModel(ped) == mh then return true end

  deathSuppress(2500)

  if not requestModel(mh) then return false end
  local ok = pcall(function() SetPlayerModel(PlayerId(), mh) end)
  SetModelAsNoLongerNeeded(mh)
  if not ok then return false end

  local t0 = ms()
  while (not DoesEntityExist(PlayerPedId())) and (ms() - t0) < 3000 do Wait(0) end
  return DoesEntityExist(PlayerPedId())
end

local function applyAppearanceToPlayer(raw)
  if not Config.EnableFiveAppearance then return false end
  local res = fiveAppearanceRes()
  if not res then return false end

  local appearance = coercePedAppearance(normalizeAppearance(raw))
  if not appearance then return false end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return false end

  local mh = tryGetModelFromAppearance(appearance)
  if mh and GetEntityModel(ped) ~= mh then
    if IsPedInAnyVehicle(ped, false) then
      dprint("APPLY blocked model swap while in vehicle (mh=%s)", tostring(mh))
      return false
    end
    if setPlayerModelHash(mh) then
      Wait(0)
      ped = PlayerPedId()
      if not DoesEntityExist(ped) then return false end
    end
  end

  local applied = false

  if exports[res] and exports[res].setPlayerAppearance then
    local ok = pcall(function()
      exports[res]:setPlayerAppearance(appearance)
    end)
    if ok then applied = true end
  end

  if (not applied) and exports[res] and exports[res].setPedAppearance then
    local ok2 = pcall(function()
      exports[res]:setPedAppearance(ped, appearance)
    end)
    if ok2 then applied = true end
  end

  if exports[res] and exports[res].setPedComponents and type(appearance.components) == "table" then
    pcall(function() exports[res]:setPedComponents(ped, appearance.components) end)
  end
  if exports[res] and exports[res].setPedProps and type(appearance.props) == "table" then
    pcall(function() exports[res]:setPedProps(ped, appearance.props) end)
  end
  if exports[res] and exports[res].setPedTattoos and type(appearance.tattoos) == "table" then
    pcall(function() exports[res]:setPedTattoos(ped, appearance.tattoos) end)
  end

  return applied and true or false
end

local applyAppearanceReliable

local __ap_apply = {
  busy = false,
  lastCid = nil,
  lastJson = nil,
  lastAt = 0,
  queued = nil
}

local function _rawToJsonString(raw)
  if raw == nil then return nil end
  if type(raw) == "string" then return raw end
  if type(raw) == "table" then
    local ok, s = pcall(function() return json.encode(raw) end)
    if ok and type(s) == "string" then return s end
  end
  return tostring(raw)
end

local function _shouldDedupeApply(charid, rawJson, ctx, force)
  if force then return false end
  if tostring(ctx or ""):find("preview", 1, true) then return false end

  local now = ms()
  if __ap_apply.lastCid == tostring(charid) and __ap_apply.lastJson == tostring(rawJson) then
    if (now - (__ap_apply.lastAt or 0)) < 6000 then
      return true
    end
  end
  return false
end

local function _queueApply(charid, raw, ctx, force, reason)
  __ap_apply.queued = {
    cid = tostring(charid or ""),
    raw = raw,
    ctx = tostring(ctx or "ctx"),
    force = force and true or false,
    reason = tostring(reason or "queued"),
    at = ms()
  }

  CreateThread(function()
    local t0 = ms()
    while __ap_apply.queued and (ms() - t0) < 15000 do
      Wait(200)

      local ped = PlayerPedId()
      if DoesEntityExist(ped)
        and (not IsPedInAnyVehicle(ped, false))
        and (not __ap_apply.busy)
      then
        local q = __ap_apply.queued
        __ap_apply.queued = nil

        if q and q.cid ~= "" then
          dprint("APPLY[%s] deferred run reason=%s", q.ctx, q.reason)
          applyAppearanceReliable(q.raw, q.ctx, q.force)
        end
        return
      end
    end

    __ap_apply.queued = nil
  end)
end

applyAppearanceReliable = function(raw, ctx, force)
  ctx = tostring(ctx or "ctx")
  force = force and true or false

  if raw == nil or raw == false then return false end
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return false end

  if (ctx == "spawn" or ctx:find("spawn", 1, true)) and stage ~= STAGE_SPAWNING then
    dprint("APPLY[%s] blocked: stage=%s", ctx, tostring(stage))
    return false
  end

  local cid = tostring(currentCharId or "")
  local rawJson = _rawToJsonString(raw)

  if cid ~= "" and rawJson and _shouldDedupeApply(cid, rawJson, ctx, force) then
    dprint("APPLY[%s] deduped cid=%s", ctx, cid)
    return true
  end

  if __ap_apply.busy then
    _queueApply(cid, raw, ctx, force, "busy")
    return true
  end

  local mh = tryGetModelFromAppearance(raw)
  if mh and GetEntityModel(ped) ~= mh and IsPedInAnyVehicle(ped, false) then
    _queueApply(cid, raw, ctx, true, "vehicle_model_swap")
    return false
  end

  __ap_apply.busy = true

  if not IsPedInAnyVehicle(ped, false) then
    pcall(function() SetPedDefaultComponentVariation(ped) end)
    pcall(function() ClearAllPedProps(ped) end)
  end

  local ok = false
  for attempt = 1, 3 do
    ok = applyAppearanceToPlayer(raw) or ok
    if ok then break end
    Wait(80 * attempt)
  end

  if ok and cid ~= "" and rawJson then
    __ap_apply.lastCid = cid
    __ap_apply.lastJson = rawJson
    __ap_apply.lastAt = ms()
  end

  __ap_apply.busy = false
  return ok and true or false
end

local function parseFirstLast(full)
  full = tostring(full or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if full == "" then return "", "" end
  local parts = {}
  for w in full:gmatch("%S+") do parts[#parts+1] = w end
  if #parts == 1 then return parts[1], "" end
  return parts[1], parts[#parts]
end

local function getCharRow(charid)
  charid = tostring(charid or "")
  for i=1, #(cachedChars or {}) do
    local c = cachedChars[i]
    if c and tostring(c.charid or c.id or c.cid or "") == charid then return c end
  end
  return nil
end

local function getCharDisplayName(charid)
  local c = getCharRow(charid)
  if not c then return "UNKNOWN" end

  local first = tostring(c.first or c.firstname or c.fname or c.first_name or "")
  local last  = tostring(c.last  or c.lastname  or c.lname or c.last_name  or "")
  if first ~= "" or last ~= "" then
    local out = (first .. " " .. last):gsub("^%s+", ""):gsub("%s+$", "")
    if out ~= "" then return out end
  end

  local name = tostring(c.name or c.charname or c.fullname or "")
  local f, l = parseFirstLast(name)
  local out2 = (f .. " " .. l):gsub("^%s+", ""):gsub("%s+$", "")
  if out2 ~= "" then return out2 end

  return "UNKNOWN"
end

local function getCharNumberText(charid)
  local c = getCharRow(charid)
  if not c then return tostring(charid) end
  local s = tostring(c.stateid or c.stateId or c.callsign or c.badge or c.badgeNumber or "")
  if s ~= "" then return s end
  local s2 = tostring(c.charid or c.id or c.cid or "")
  if s2 ~= "" then return s2 end
  return tostring(charid)
end

local __mug = { handle=nil, txd=nil, charid=nil, at=0 }

local function sendMugshotToNui(charid, txd)
  local url = ("https://nui-img/%s/%s"):format(tostring(txd), tostring(txd))
  nuiSend({ type = "azfw_mugshot", charid = tostring(charid), txd = tostring(txd), url = url })
  nuiSend({ type = "mugshot", charid = tostring(charid), txd = tostring(txd), url = url })
end

local function destroyNuiHeadshot()
  if __mug.handle and IsPedheadshotValid(__mug.handle) then
    UnregisterPedheadshot(__mug.handle)
  end
  __mug.handle = nil
  __mug.txd = nil
  __mug.charid = nil
  __mug.at = 0

  nuiSend({ type = "azfw_mugshot", charid = nil, txd = nil, url = nil })
  nuiSend({ type = "mugshot", charid = nil, txd = nil, url = nil })
end

local function ensureMugshotForCurrentPreview(charid, force)
  if not Config.MugshotEnabled then return end
  if not nuiOpen then return end
  if not charid then return end

  local now = ms()
  if not force then
    if __mug.charid == tostring(charid) and (now - (__mug.at or 0)) < (Config.MugshotRefreshMs or 700) then
      return
    end
  end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end

  if __mug.handle and IsPedheadshotValid(__mug.handle) then
    UnregisterPedheadshot(__mug.handle)
  end
  __mug.handle = nil
  __mug.txd = nil
  __mug.charid = tostring(charid)
  __mug.at = now

  local handle = nil
  local okT = pcall(function()
    if type(RegisterPedheadshotTransparent) == "function" then
      handle = RegisterPedheadshotTransparent(ped)
    end
  end)
  if not okT or not handle or handle == -1 then
    handle = RegisterPedheadshot(ped)
  end

  if not handle or handle == -1 then
    dprint("MUGSHOT(NUI) failed: RegisterPedheadshot returned %s", tostring(handle))
    return
  end

  __mug.handle = handle

  CreateThread(function()
    local t0 = ms()
    while nuiOpen and __mug.handle == handle and (ms() - t0) < 2500 do
      if IsPedheadshotReady(handle) and IsPedheadshotValid(handle) then break end
      Wait(0)
    end

    if not nuiOpen then
      if IsPedheadshotValid(handle) then UnregisterPedheadshot(handle) end
      return
    end
    if __mug.handle ~= handle then
      if IsPedheadshotValid(handle) then UnregisterPedheadshot(handle) end
      return
    end

    if not (IsPedheadshotReady(handle) and IsPedheadshotValid(handle)) then
      dprint("MUGSHOT(NUI) not ready/valid in time cid=%s", tostring(charid))
      if IsPedheadshotValid(handle) then UnregisterPedheadshot(handle) end
      if __mug.handle == handle then __mug.handle = nil end
      return
    end

    local txd = GetPedheadshotTxdString(handle)
    if not txd or txd == "" then
      dprint("MUGSHOT(NUI) txd missing cid=%s", tostring(charid))
      return
    end

    __mug.txd = txd
    sendMugshotToNui(charid, txd)
  end)
end

local __held = {
  board = nil,
  text = nil,
  attachedCid = nil,
  rtName = "ID_Text",
  rtHandle = 0,
  scaleform = 0,
  draw = false,
  l1 = "",
  l2 = "",
  l3 = "",
  l4 = ""
}

local function createNamedRenderTargetForModel(name, model)
  if not IsNamedRendertargetRegistered(name) then
    RegisterNamedRendertarget(name, false)
  end
  if not IsNamedRendertargetLinked(model) then
    LinkNamedRendertarget(model)
  end
  if IsNamedRendertargetRegistered(name) then
    return GetNamedRendertargetRenderId(name)
  end
  return 0
end

local function ensureHeldScaleform()
  if __held.scaleform ~= 0 and HasScaleformMovieLoaded(__held.scaleform) then return true end
  __held.scaleform = RequestScaleformMovie("MUGSHOT_BOARD_01")
  local t0 = ms()
  while __held.scaleform ~= 0 and not HasScaleformMovieLoaded(__held.scaleform) and (ms() - t0) < 5000 do
    Wait(0)
  end
  return (__held.scaleform ~= 0 and HasScaleformMovieLoaded(__held.scaleform))
end

local function stopHeldDraw()
  __held.draw = false
  __held.rtHandle = 0
  if __held.scaleform ~= 0 then
    pcall(function() SetScaleformMovieAsNoLongerNeeded(__held.scaleform) end)
  end
  __held.scaleform = 0
end

local function startHeldDrawIfNeeded()
  if __held.draw then return end
  __held.draw = true
  CreateThread(function()
    while __held.draw do
      Wait(0)

      if not nuiOpen then break end
      if not __held.attachedCid then break end
      if not __held.text or not DoesEntityExist(__held.text) then break end

      local overlayModel = GetHashKey(Config.Preview.Mugshot.TextProp)
      if __held.rtHandle == 0 then
        __held.rtHandle = createNamedRenderTargetForModel(__held.rtName, overlayModel)
      end

      if __held.rtHandle == 0 then
        Wait(100)
      else
        if ensureHeldScaleform() then
          BeginScaleformMovieMethod(__held.scaleform, "SET_BOARD")
          PushScaleformMovieMethodParameterString(tostring(__held.l1 or ""))
          PushScaleformMovieMethodParameterString(tostring(__held.l3 or ""))
          PushScaleformMovieMethodParameterString(tostring(__held.l4 or ""))
          PushScaleformMovieMethodParameterString(tostring(__held.l2 or ""))
          PushScaleformMovieFunctionParameterInt(0)
          PushScaleformMovieFunctionParameterInt(5)
          PushScaleformMovieFunctionParameterInt(0)
          EndScaleformMovieMethod()

          SetTextRenderId(__held.rtHandle)
          SetScriptGfxDrawOrder(4)
          DrawScaleformMovie(__held.scaleform, 0.405, 0.37, 0.81, 0.74, 255, 255, 255, 255, 0)
          SetTextRenderId(GetDefaultScriptRendertargetRenderId())
        else
          Wait(100)
        end
      end
    end

    stopHeldDraw()
  end)
end

local function ensureAnimDict(dict)
  if not dict or dict == "" then return false end
  RequestAnimDict(dict)
  local t0 = ms()
  while not HasAnimDictLoaded(dict) and (ms() - t0) < 6000 do Wait(0) end
  return HasAnimDictLoaded(dict)
end

local function playHeldMugshotAnim(ped)
  if not DoesEntityExist(ped) then return end
  local model = GetEntityModel(ped)
  local isFemale = (model == `mp_f_freemode_01`)
  local dict = isFemale and "mp_character_creation@lineup@female_a" or "mp_character_creation@lineup@male_a"
  local name = "loop_raised"
  if ensureAnimDict(dict) then
    TaskPlayAnim(ped, dict, name, 2.0, 2.0, -1, 49, 0.0, false, false, false)
  end
end

local function forceDeleteEntity(ent)
  if not ent or ent == 0 or not DoesEntityExist(ent) then return end
  pcall(function() DetachEntity(ent, true, true) end)
  pcall(function() SetEntityAsMissionEntity(ent, true, true) end)
  pcall(function() DeleteObject(ent) end)
  if DoesEntityExist(ent) then
    pcall(function() DeleteEntity(ent) end)
  end
  if DoesEntityExist(ent) then
    pcall(function() SetEntityCoordsNoOffset(ent, 0.0, 0.0, -200.0, false, false, false) end)
  end
end

local function cleanupNearbyHeldMugshotProps(radius)
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end

  local here = GetEntityCoords(ped)
  local boardHash = GetHashKey(Config.Preview.Mugshot.BoardProp)
  local textHash  = GetHashKey(Config.Preview.Mugshot.TextProp)
  local r = tonumber(radius) or 6.0

  for _, obj in ipairs(GetGamePool('CObject')) do
    if DoesEntityExist(obj) then
      local model = GetEntityModel(obj)
      if model == boardHash or model == textHash then
        local c = GetEntityCoords(obj)
        local dx = here.x - c.x
        local dy = here.y - c.y
        local dz = here.z - c.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        local keep = (obj == __held.board or obj == __held.text)
        if (not keep) and dist <= r then
          forceDeleteEntity(obj)
        end
      end
    end
  end
end

local function destroyHeldMugshot()
  __held.attachedCid = nil
  stopHeldDraw()
  if __held.board and DoesEntityExist(__held.board) then forceDeleteEntity(__held.board) end
  if __held.text and DoesEntityExist(__held.text) then forceDeleteEntity(__held.text) end
  __held.board, __held.text = nil, nil
  cleanupNearbyHeldMugshotProps(8.0)

  local ped = PlayerPedId()
  if DoesEntityExist(ped) then
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
  end
end

local function ensureHeldMugshot(cid)
  if not Config.Preview.Mugshot.Enabled then
    destroyHeldMugshot()
    return
  end
  if not nuiOpen then
    destroyHeldMugshot()
    return
  end

  cid = tostring(cid or "")
  if cid == "" then
    destroyHeldMugshot()
    return
  end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end

  if __held.attachedCid ~= cid then
    destroyHeldMugshot()
  end

  cleanupNearbyHeldMugshotProps(8.0)

  local boardHash = GetHashKey(Config.Preview.Mugshot.BoardProp)
  local textHash  = GetHashKey(Config.Preview.Mugshot.TextProp)

  if (not __held.board or not DoesEntityExist(__held.board)) and requestModel(boardHash) then
    __held.board = CreateObject(boardHash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityCollision(__held.board, false, false)
    SetModelAsNoLongerNeeded(boardHash)
  end

  if (not __held.text or not DoesEntityExist(__held.text)) and requestModel(textHash) then
    __held.text = CreateObject(textHash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityCollision(__held.text, false, false)
    SetModelAsNoLongerNeeded(textHash)
  end

  local bone = tonumber(Config.Preview.Mugshot.HandBone) or 28422
  local bi = GetPedBoneIndex(ped, bone)

  if __held.board and DoesEntityExist(__held.board) then
    AttachEntityToEntity(__held.board, ped, bi, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
  end

  if __held.text and DoesEntityExist(__held.text) and __held.board and DoesEntityExist(__held.board) then
    AttachEntityToEntity(__held.text, __held.board, -1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
  end

  __held.l1 = tostring(Config.Preview.Mugshot.DeptText or "YOUR SERVER NAME")
  __held.l2 = tostring(getCharDisplayName(cid) or "UNKNOWN")
  __held.l3 = tostring(getCharNumberText(cid) or cid)
  __held.l4 = tostring(cid)

  playHeldMugshotAnim(ped)
  __held.attachedCid = cid
  startHeldDrawIfNeeded()
end

destroyMugshot = function()
  destroyHeldMugshot()
  destroyNuiHeadshot()
end

local apCache, apInflight = {}, {}

local function apCacheGet(charid)
  charid = tostring(charid)
  local e = apCache[charid]
  if not e then return nil end

  local age = ms() - (e.at or 0)
  if age > 120000 then apCache[charid] = nil return nil end

  if e.raw == false and age > (Config.Preview.NegativeCacheMs or 4000) then
    return nil
  end

  return e.raw
end

local function apCacheSet(charid, raw)
  apCache[tostring(charid)] = { raw = raw, at = ms() }
end

local function fetchAppearanceForChar(charid)
  if not (lib and lib.callback and lib.callback.await) then return nil end
  local ok, resp = pcall(function()
    return lib.callback.await("azfw:appearance:get", 12000, tostring(charid))
  end)

  if not ok then
    dprint("appearance:get callback threw cid=%s", tostring(charid))
    return nil
  end

  if type(resp) == "table" then
    if resp.ok ~= true then return nil end
    if resp.exists ~= true then return false end

    local ap = resp.appearance

    if type(ap) == "table" then
      local okEnc, s = pcall(function() return json.encode(ap) end)
      if okEnc and type(s) == "string" and s ~= "" then
        ap = s
      end
    end

    if type(ap) ~= "string" or ap == "" then return false end
    if not normalizeAppearance(ap) then return nil end
    return ap
  end

  if type(resp) == "string" then
    if resp == "" then return false end
    if not normalizeAppearance(resp) then return nil end
    return resp
  end

  return nil
end

local function requestAppearanceAsync(charid)
  charid = tostring(charid)
  if apInflight[charid] then return end
  apInflight[charid] = true

  CreateThread(function()
    local raw = fetchAppearanceForChar(charid)
    if raw ~= nil then
      apCacheSet(charid, raw)
      if raw ~= false then
        local mh = tryGetModelFromAppearance(raw)
        if mh then pcall(function() RequestModel(mh) end) end
      end
    end
    apInflight[charid] = nil
  end)
end

local function getAppearanceRawRetry(charid, attempts, retryWaitMs)
  charid = tostring(charid)

  local cached = apCacheGet(charid)
  if cached ~= nil and cached ~= false then
    return cached
  end

  attempts = tonumber(attempts) or (Config.Preview.FetchAttempts or 10)
  retryWaitMs = tonumber(retryWaitMs) or (Config.Preview.FetchWaitMs or 250)

  local lastWasFalse = (cached == false)

  for _=1, attempts do
    local raw = fetchAppearanceForChar(charid)
    if raw == false then
      apCacheSet(charid, false)
      lastWasFalse = true
      Wait(retryWaitMs)
    elseif raw ~= nil then
      apCacheSet(charid, raw)
      local mh = tryGetModelFromAppearance(raw)
      if mh then pcall(function() RequestModel(mh) end) end
      return raw
    else
      Wait(retryWaitMs)
    end
  end

  if lastWasFalse then return false end
  return nil
end

local __customizing = false

local function confirmNoAppearance(charid)
  charid = tostring(charid or "")
  if charid == "" then return nil end

  apCache[charid] = nil

  local sawFalse = false
  for _ = 1, 4 do
    local raw = fetchAppearanceForChar(charid)
    if raw ~= nil then
      if raw == false then
        sawFalse = true
      elseif type(raw) == "string" and raw ~= "" then
        return raw
      end
    end
    Wait(250)
  end

  if sawFalse then return false end
  return nil
end

local function openCustomizationForChar(charid, contextTag)
  if __customizing then return false end
  if not Config.EnableFiveAppearance then return false end

  local res = fiveAppearanceRes()
  if not res or not exports[res] then return false end

  if nuiOpen or spawnNuiOpen then
    if tostring(contextTag or "") ~= "new_character_pre_spawn" then
      dprint("CUSTOMIZE blocked (menu open) ctx=%s nuiOpen=%s spawnNuiOpen=%s", tostring(contextTag), tostring(nuiOpen), tostring(spawnNuiOpen))
      return false
    end

    dprint("CUSTOMIZE[%s] hiding character UI before appearance open", tostring(contextTag))
    nuiOpen = false
    spawnNuiOpen = false
    setNuiOwner(nil)
    nuiSend({ type = "azfw_close_ui" })
    nuiSend({ type = "azfw_visibility", open = false })
    nuiSend({ type = "hard_hide_all" })
    SetNuiFocus(false, false)
    Wait(250)
  end

  if not __allowCustomizeNow then
    dprint("CUSTOMIZE blocked (not permitted yet) ctx=%s stage=%s", tostring(contextTag), tostring(stage))
    return false
  end

  if stage ~= STAGE_IN_WORLD then
    dprint("CUSTOMIZE blocked (stage) ctx=%s stage=%s", tostring(contextTag), tostring(stage))
    return false
  end

  if Config.UseAppearance ~= true then
    dprint("CUSTOMIZE[%s] blocked: set Config.UseAppearance = true", tostring(contextTag or "ctx"))
    return false
  end

  __customizing = true
  deathSuppress(8000)

  local config = {
    ped = true,
    headBlend = true,
    faceFeatures = true,
    headOverlays = true,
    components = true,
    props = true,
    allowExit = true,
    tattoos = true
  }

  dprint("CUSTOMIZE[%s] opening cid=%s", tostring(contextTag or "ctx"), tostring(charid))

  local okCall, callErr = pcall(function()
    exports[res]:startPlayerCustomization(function(appearance)
      __customizing = false

      if not appearance then
        dprint("CUSTOMIZE[%s] canceled cid=%s", tostring(contextTag or "ctx"), tostring(charid))
        if tostring(__continueToSpawnAfterCustomizeCid or "") == tostring(charid) then
          reopenCharacterUiAfterAppearanceCancel()
        end
        return
      end

      local ped = PlayerPedId()
      if DoesEntityExist(ped) and exports[res] and exports[res].getPedAppearance then
        pcall(function()
          local snap = exports[res]:getPedAppearance(ped)
          if type(snap) == "table" then appearance = snap end
        end)
      end

      local ok, encoded = pcall(function() return json.encode(appearance) end)
      if not ok or type(encoded) ~= "string" or encoded == "" then
        dprint("CUSTOMIZE[%s] encode failed cid=%s", tostring(contextTag or "ctx"), tostring(charid))
        return
      end

      TriggerServerEvent("azfw:appearance:save", tostring(charid), encoded)
      apCacheSet(tostring(charid), encoded)

      dprint("CUSTOMIZE[%s] saved cid=%s bytes=%d", tostring(contextTag or "ctx"), tostring(charid), #encoded)

      if tostring(__continueToSpawnAfterCustomizeCid or "") == tostring(charid) then
        __pendingNewCharPreSpawnAppearanceCid = nil
        continueToSpawnSelectorAfterAppearance(charid)
      end
    end, config)
  end)

  if not okCall then
    __customizing = false
    dprint("CUSTOMIZE[%s] failed: startPlayerCustomization missing/errored resource=%s err=%s", tostring(contextTag or "ctx"), tostring(res), tostring(callErr))
    return false
  end

  return true
end

local function applyOrCustomizeForChar(charid, allowCustomize, contextTag)
  charid = tostring(charid or "")
  if charid == "" then return false end

  if not Config.EnableFiveAppearance then
    dprint("APPLY[%s] skipped: EnableFiveAppearance=false", tostring(contextTag or "ctx"))
    return false
  end

  local res = fiveAppearanceRes()
  if not res then
    dprint("APPLY[%s] skipped: five-appearance not running", tostring(contextTag or "ctx"))
    return false
  end

  deathSuppress(3500)

  requestAppearanceAsync(charid)
  local raw = getAppearanceRawRetry(charid)

  if raw == false then
    dprint("APPLY[%s] cid=%s appearance=NONE (maybe new character)", tostring(contextTag or "ctx"), charid)
    if allowCustomize then

      __pendingNewCharCustomize = true
      __pendingNewCharCid = charid
    end
    return true
  end

  if raw == nil then
    dprint("APPLY[%s] cid=%s appearance=nil (fetch fail) -> skipping customize", tostring(contextTag or "ctx"), charid)
    return false
  end

  __pendingNewCharCustomize = false
  __pendingNewCharCid = nil

  local applied = applyAppearanceReliable(raw, contextTag or "ctx", false)
  dprint("APPLY[%s] cid=%s applied=%s bytes=%d", tostring(contextTag or "ctx"), charid, tostring(applied), #tostring(raw))
  return applied
end

local previewCam = nil
local previewReturn = nil
local inPreviewInstance = false
local previewNonce = 0
local previewWantedCharId = nil
local previewThreadRunning = false

local function ensurePreviewInstance()
  if inPreviewInstance then return end
  inPreviewInstance = true
  TriggerServerEvent("azfw:preview:enter")
end

local function exitPreviewInstance()
  if not inPreviewInstance then return end
  inPreviewInstance = false
  TriggerServerEvent("azfw:preview:exit")
end

local function destroyPreviewCam()
  if previewCam and DoesCamExist(previewCam) then
    DestroyCam(previewCam, false)
  end
  previewCam = nil
  RenderScriptCams(false, true, Config.Preview.CamInterpMs or 250, true, true)
  ClearFocus()
end

local function ensurePreviewScene()
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end

  if not previewReturn then
    local c = GetEntityCoords(ped)
    previewReturn = { x=c.x, y=c.y, z=c.z, h=GetEntityHeading(ped) }
  end

  local scene = Config.Preview.Scene
  local poff = Config.Preview.PedOffset or vector3(0.0, 0.0, 0.0)
  local px, py, pz, ph = scene.x + poff.x, scene.y + poff.y, scene.z + poff.z, scene.w

  RequestCollisionAtCoord(px, py, pz)
  local t0 = ms()
  while not HasCollisionLoadedAroundEntity(ped) and (ms() - t0) < 2000 do Wait(0) end

  FreezeEntityPosition(ped, true)
  SetEntityVisible(ped, true, false)
  SetEntityAlpha(ped, 255, false)
  SetEntityInvincible(ped, true)

  SetEntityCoordsNoOffset(ped, px, py, pz, false, false, false)
  SetEntityHeading(ped, ph or 0.0)
end

local function restoreAfterPreviewIfNeeded()
  if not previewReturn then return end
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then previewReturn=nil return end

  FreezeEntityPosition(ped, false)
  ResetEntityAlpha(ped)
  SetEntityVisible(ped, true, false)
  SetEntityInvincible(ped, false)
  SetEntityCoordsNoOffset(ped, previewReturn.x, previewReturn.y, previewReturn.z, false, false, false)
  SetEntityHeading(ped, previewReturn.h or 0.0)
  previewReturn = nil
end

local function hidePreviewPedNow()
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end
  ClearPedTasksImmediately(ped)
  ClearPedSecondaryTask(ped)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetEntityVisible(ped, false, false)
  SetEntityAlpha(ped, 0, false)
end

local function showPreviewPedNow()
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  ResetEntityAlpha(ped)
  SetEntityVisible(ped, true, false)
end

local function clearPreviewSelectionVisuals()
  previewWantedCharId = nil
  previewNonce = previewNonce + 1
  destroyMugshot()
  if Config.Preview.Enabled then
    ensurePreviewScene()
  end
  hidePreviewPedNow()
end

local function makePreviewCam()
  if not Config.Preview.Enabled or not Config.Preview.Camera.Enabled then return end
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return end

  local forward  = tonumber(Config.Preview.Camera.Forward) or 2.8
  local right    = tonumber(Config.Preview.Camera.Right) or -0.15
  local up       = tonumber(Config.Preview.Camera.Up) or 0.0
  local targetUp = tonumber(Config.Preview.Camera.TargetUp) or -0.35

  local head = GetEntityHeading(ped) or 0.0
  local h = math.rad(head)
  local fwdX, fwdY = -math.sin(h), math.cos(h)
  local rightX, rightY = math.cos(h), math.sin(h)

  local target = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.05)
  local tx, ty, tz = target.x, target.y, target.z + targetUp

  local cx = tx + (fwdX * forward) + (rightX * right)
  local cy = ty + (fwdY * forward) + (rightY * right)
  local cz = tz + up

  local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
  SetCamCoord(cam, cx, cy, cz)
  SetCamFov(cam, Config.Preview.CamFov or 50.0)
  PointCamAtCoord(cam, tx, ty, tz)

  if previewCam and DoesCamExist(previewCam) then
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    SetCamActiveWithInterp(cam, previewCam, Config.Preview.CamInterpMs or 250, true, true)
    Wait((Config.Preview.CamInterpMs or 250) + 10)
    DestroyCam(previewCam, false)
    previewCam = cam
  else
    previewCam = cam
    SetCamActive(previewCam, true)
    RenderScriptCams(true, false, 0, true, true)
  end
end

local function prefetchAppearances(chars)
  if not Config.Preview.PrefetchAppearances then return end
  if type(chars) ~= "table" then return end
  CreateThread(function()
    local n = math.min(#chars, Config.Preview.PrefetchLimit or 16)
    for i=1, n do
      local c = chars[i]
      local cid = c and (c.charid or c.id or c.cid)
      if cid then
        requestAppearanceAsync(tostring(cid))
        Wait(40)
      end
    end
  end)
end

local function startPreviewWorker()
  if previewThreadRunning then return end
  previewThreadRunning = true

  CreateThread(function()
    while nuiOpen do
      if not previewWantedCharId then
        Wait(50)
      else
        local cid = tostring(previewWantedCharId)
        previewWantedCharId = nil
        local myNonce = previewNonce

        showPreviewPedNow()
        ensurePreviewScene()

        local raw = getAppearanceRawRetry(cid, Config.Preview.FetchAttempts, Config.Preview.FetchWaitMs)

        if myNonce ~= previewNonce then
          Wait(0)
        elseif raw ~= nil and raw ~= false then
          applyAppearanceReliable(raw, "preview", false)
          Wait(0)
          ensurePreviewScene()
        else
          local ped = PlayerPedId()
          if DoesEntityExist(ped) then
            pcall(function() SetPedDefaultComponentVariation(ped) end)
            pcall(function() ClearAllPedProps(ped) end)
          end
          Wait(0)
          ensurePreviewScene()
        end

        makePreviewCam()
        ensureHeldMugshot(cid)
        ensureMugshotForCurrentPreview(cid, true)

        Wait(0)
      end
    end

    previewThreadRunning = false
  end)
end

local function previewCharacter(charid)
  if not Config.Preview.Enabled then return end
  if not nuiOpen then return end
  if not charid then return end

  previewWantedCharId = tostring(charid)
  previewNonce = previewNonce + 1

  startPreviewWorker()
end

Config.AppearanceAutosaveEnabled = (Config.AppearanceAutosaveEnabled ~= false)
Config.AppearanceAutosaveMs = tonumber(Config.AppearanceAutosaveMs) or 60000
Config.AppearanceMinIntervalMs = tonumber(Config.AppearanceMinIntervalMs) or 15000
Config.AppearanceAutosaveInMenus = (Config.AppearanceAutosaveInMenus == true)

local __ap_lastJson = nil
local __ap_lastAt = 0

local function __getPlayerAppearanceTable_safe()
  if not Config.EnableFiveAppearance then return nil end
  local res = fiveAppearanceRes()
  if not res or not exports[res] then return nil end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return nil end

  local ap = nil

  if exports[res].getPedAppearance then
    local ok, v = pcall(function()
      return exports[res]:getPedAppearance(ped)
    end)
    if ok and type(v) == "table" then ap = v end
  end

  ap = ap or {}

  if (ap.model == nil) and exports[res].getPedModel then
    pcall(function() ap.model = exports[res]:getPedModel(ped) end)
  end
  if (type(ap.components) ~= "table") and exports[res].getPedComponents then
    pcall(function() ap.components = exports[res]:getPedComponents(ped) end)
  end
  if (type(ap.props) ~= "table") and exports[res].getPedProps then
    pcall(function() ap.props = exports[res]:getPedProps(ped) end)
  end
  if (ap.headBlend == nil) and exports[res].getPedHeadBlend then
    pcall(function() ap.headBlend = exports[res]:getPedHeadBlend(ped) end)
  end
  if (ap.faceFeatures == nil) and exports[res].getPedFaceFeatures then
    pcall(function() ap.faceFeatures = exports[res]:getPedFaceFeatures(ped) end)
  end
  if (ap.headOverlays == nil) and exports[res].getPedHeadOverlays then
    pcall(function() ap.headOverlays = exports[res]:getPedHeadOverlays(ped) end)
  end
  if (ap.hair == nil) and exports[res].getPedHair then
    pcall(function() ap.hair = exports[res]:getPedHair(ped) end)
  end
  if (ap.tattoos == nil) and exports[res].getPedTattoos then
    pcall(function() ap.tattoos = exports[res]:getPedTattoos(ped) end)
  end

  local hasSomething = false
  for _ in pairs(ap) do hasSomething = true break end
  return hasSomething and ap or nil
end

local function saveAppearanceToServer(reason, force)
  if not currentCharId then return false end

  local ap = __getPlayerAppearanceTable_safe()
  if type(ap) ~= "table" then return false end

  local ok, encoded = pcall(function() return json.encode(ap) end)
  if not ok or type(encoded) ~= "string" or encoded == "" then return false end

  local now = ms()
  if not force then
    if encoded == __ap_lastJson then return false end
    if (now - __ap_lastAt) < (Config.AppearanceMinIntervalMs or 15000) then return false end
  end

  __ap_lastJson = encoded
  __ap_lastAt = now

  TriggerServerEvent("azfw:appearance:save", tostring(currentCharId), encoded)
  dprint("OUTFIT saved cid=%s bytes=%d reason=%s", tostring(currentCharId), #encoded, tostring(reason or "unknown"))
  return true
end

local function getBestCoordsForLastPosSave(forcePedOnly)
  local ped = PlayerPedId()

  if not forcePedOnly then
    if (nuiOpen or spawnNuiOpen or inPreviewInstance) and previewReturn and previewReturn.x then
      return previewReturn.x, previewReturn.y, previewReturn.z, (previewReturn.h or 0.0), true
    end
  end

  if DoesEntityExist(ped) then
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    return c.x, c.y, c.z, h, false
  end

  return nil, nil, nil, nil, false
end

local function _allowLastPosWrite(reason)
  reason = tostring(reason or "")
  if reason == "resourceStop" then return true end
  if reason:find("^server_", 1, true) then return true end
  if stage == STAGE_IN_WORLD or stage == STAGE_SPAWNING then return true end
  return false
end

local function saveLastPosToServer(reason)
  if not Config.EnableLastLocation then return false end
  if not currentCharId then return false end

  if not _allowLastPosWrite(reason) then
    dprint("LASTPOS skip cid=%s reason=%s stage=%s", tostring(currentCharId), tostring(reason), tostring(stage))
    return false
  end

  local forcePedOnly = false
  reason = tostring(reason or "")
  if reason == "resourceStop" or reason:find("^server_", 1, true) then
    forcePedOnly = true
  end

  local x, y, z, h, usedPreviewReturn = getBestCoordsForLastPosSave(forcePedOnly)
  if not x then return false end

  TriggerServerEvent("azfw:lastloc:update", tostring(currentCharId), x, y, z, h or 0.0)
  dprint("LASTPOS saved cid=%s reason=%s (usedPreviewReturn=%s forcePedOnly=%s)", tostring(currentCharId), tostring(reason), tostring(usedPreviewReturn), tostring(forcePedOnly))
  return true
end

exports("saveCurrentAppearance", function(reason, force)
  return saveAppearanceToServer(reason, force and true or false)
end)

exports("saveCurrentLastPos", function(reason)
  return saveLastPosToServer(reason)
end)

exports("getCurrentCharId", function()
  return currentCharId
end)

RegisterNetEvent("azfw:finalSave:request")
AddEventHandler("azfw:finalSave:request", function(reason)
  saveLastPosToServer("server_" .. tostring(reason or "request"))
  saveAppearanceToServer("server_" .. tostring(reason or "request"), true)
end)

local pendingUiIssue = nil

local function pushPendingUiIssueToNui()
  if not pendingUiIssue or not nuiOpen then return end
  nuiSend({ type = "azfw_ui_issue", issue = pendingUiIssue })
end

RegisterNetEvent("azfw:ui_issue")
AddEventHandler("azfw:ui_issue", function(issue)
  pendingUiIssue = issue or {
    code = "unknown",
    title = "Character UI Issue",
    message = "A required identifier is missing or invalid.",
    detail = ""
  }

  if nuiOpen then
    pushPendingUiIssueToNui()
    return
  end

  if lib and lib.notify then
    lib.notify({
      title = tostring(pendingUiIssue.title or "Character UI Issue"),
      description = tostring(pendingUiIssue.message or pendingUiIssue.detail or "A required identifier is missing."),
      type = 'error'
    })
  end
end)

RegisterNetEvent("azfw:clear_ui_issue")
AddEventHandler("azfw:clear_ui_issue", function(_)
  pendingUiIssue = nil
  if nuiOpen then
    nuiSend({ type = "azfw_clear_ui_issue" })
  end
end)

local function azLobbyRouterIsHoldingCharacterUI()
  if GetResourceState("Az-LobbyRouter") ~= "started" then return false end
  local ok, holding = pcall(function()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.az_lobby_selecting == true
  end)
  return ok and holding == true
end

local openAzfwUI

local function shouldPreSpawnCustomizeNewCharacter(charid)
  charid = tostring(charid or "")
  if charid == "" then return false end
  if Config.EnableFiveAppearance ~= true or Config.UseAppearance ~= true then return false end
  if ((Config.Character or {}).AppearanceBeforeFirstSpawn ~= false) ~= true then return false end
  return tostring(__pendingNewCharPreSpawnAppearanceCid or "") == charid
end

continueToSpawnSelectorAfterAppearance = function(charid)
  charid = tostring(charid or "")
  if charid == "" then return end

  __continueToSpawnAfterCustomizeCid = nil
  __preSpawnCustomizeBusy = false
  __allowCustomizeNow = false
  setSpawnedInWorld(false, "pre_spawn_appearance_complete")
  setStage(STAGE_BOOT, "pre_spawn_appearance_complete")

  SetTimeout(150, function()
    TriggerServerEvent("spawn_selector:requestSpawns", charid)
  end)
end

reopenCharacterUiAfterAppearanceCancel = function()
  __continueToSpawnAfterCustomizeCid = nil
  __preSpawnCustomizeBusy = false
  __allowCustomizeNow = false
  setSpawnedInWorld(false, "pre_spawn_appearance_cancel")
  setStage(STAGE_BOOT, "pre_spawn_appearance_cancel")

  SetTimeout(150, function()
    openAzfwUI(cachedChars)
  end)
end

local function beginPreSpawnAppearanceFlow(charid)
  charid = tostring(charid or "")
  if charid == "" then return false end
  if __preSpawnCustomizeBusy then return true end

  __preSpawnCustomizeBusy = true
  __continueToSpawnAfterCustomizeCid = charid

  deathPause(true)
  deathSuppress(12000)
  ensurePreviewInstance()

  local ped = PlayerPedId()
  if DoesEntityExist(ped) then
    showPreviewPedNow()
    ensurePreviewScene()
    makePreviewCam()
  end

  setStage(STAGE_IN_WORLD, "pre_spawn_appearance_flow")

  requestAppearanceAsync(charid)
  local existing = getAppearanceRawRetry(charid, 3, 200)
  if existing and existing ~= false then
    apCacheSet(charid, existing)
    applyAppearanceReliable(existing, "pre_spawn_existing", true)
    __pendingNewCharPreSpawnAppearanceCid = nil
    continueToSpawnSelectorAfterAppearance(charid)
    return true
  end

  __allowCustomizeNow = true
  local opened = openCustomizationForChar(charid, "new_character_pre_spawn")
  if not opened then
    __allowCustomizeNow = false
    __preSpawnCustomizeBusy = false
    __continueToSpawnAfterCustomizeCid = nil
    if lib and lib.notify then
      lib.notify({
        title = 'Appearance',
        description = 'Appearance customization is unavailable. Continuing to spawn.',
        type = 'inform'
      })
    end
    __pendingNewCharPreSpawnAppearanceCid = nil
    continueToSpawnSelectorAfterAppearance(charid)
    return true
  end

  return true
end

openAzfwUI = function(initialChars)
  if nuiOpen then return end
  if nuiOwner == "spawn" or spawnNuiOpen then return end

  __allowCustomizeNow = false
  __pendingNewCharCustomize = false
  __pendingNewCharCid = nil

  saveLastPosToServer("open_characters")

  ensurePreviewInstance()
  deathPause(true)
  deathSuppress(8000)

  nuiOpen = true
  nuiReady = false

  if type(initialChars) == "table" and #initialChars > 0 then cachedChars = initialChars end

  local ped = PlayerPedId()
  if DoesEntityExist(ped) then
    if Config.Preview.Enabled then
      ensurePreviewScene()
      makePreviewCam()
    else
      FreezeEntityPosition(ped, true)
      SetEntityVisible(ped, false, false)
    end
  end

  setStage(STAGE_CHAR_UI, "openAzfwUI")
  setNuiOwner("azfw")

  SetTimeout(100, function()
    nuiSend({ type = "azfw_set_resource", resource = RESOURCE_NAME })
    nuiSend({ type = "azfw_visibility", open = true })
    nuiSend({ type = "spawn_visibility", open = false })

    local charsToSend = cachedChars

    if (not charsToSend) or (type(charsToSend) ~= "table") or (#charsToSend == 0) then
      if lib and lib.callback and lib.callback.await then
        local ok, result = pcall(function()
          return lib.callback.await("azfw:fetch_characters", 8000)
        end)
        if ok and type(result) == "table" then
          charsToSend = result
          cachedChars = result
        else
          charsToSend = {}
        end
      else
        charsToSend = {}
      end
    end

    nuiSend({ type = "azfw_open_ui", chars = charsToSend or {} })
    pushPendingUiIssueToNui()

    TriggerServerEvent("azfw:appearance:bulkRequest")
    prefetchAppearances(charsToSend or {})

    SetTimeout(220, function()
      if not nuiOpen then return end
      local firstChar = (charsToSend and charsToSend[1] and (charsToSend[1].charid or charsToSend[1].id or charsToSend[1].cid))
      if firstChar then
        currentCharId = tostring(firstChar)
        previewCharacter(currentCharId)
        ensureHeldMugshot(currentCharId)
        ensureMugshotForCurrentPreview(currentCharId, true)
      else
        currentCharId = nil
        clearPreviewSelectionVisuals()
      end
    end)

    hardResetFocus()
  end)
end

local function closeAzfwUI(restorePlayer, exitInstanceNow)
  if not nuiOpen then return end

  saveLastPosToServer("close_characters")

  nuiOpen = false

  local ped = PlayerPedId()
  if DoesEntityExist(ped) then
    FreezeEntityPosition(ped, false)
    ResetEntityAlpha(ped)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
  end

  deathPause(false)

  setNuiOwner(nil)
  destroyPreviewCam()
  destroyMugshot()

  nuiSend({ type = "azfw_close_ui" })
  nuiSend({ type = "azfw_visibility", open = false })
  nuiSend({ type = "hard_hide_all" })

  if restorePlayer then restoreAfterPreviewIfNeeded() end
  if exitInstanceNow then exitPreviewInstance() end

  if playerSpawnedInWorld then
    setStage(STAGE_IN_WORLD, "closeAzfwUI")
  else
    setStage(STAGE_BOOT, "closeAzfwUI")
  end

  applyHudAndMinimap()
  reinforceHudAndMinimap(1500)
end

local function closeAllAzUIs()
  saveLastPosToServer("close_all_ui")

  nuiOpen = false
  spawnNuiOpen = false
  nuiOwner = nil
  nuiReady = true

  destroyPreviewCam()
  destroyMugshot()

  local ped = PlayerPedId()
  if DoesEntityExist(ped) then
    FreezeEntityPosition(ped, false)
    ResetEntityAlpha(ped)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
  end

  deathPause(false)

  setNuiOwner(nil)
  focusOff()

  nuiSend({ type = "azfw_close_ui" })
  nuiSend({ type = "spawn_close" })
  nuiSend({ type = "azfw_visibility", open = false })
  nuiSend({ type = "spawn_visibility", open = false })
  nuiSend({ type = "hard_hide_all" })

  if playerSpawnedInWorld then
    setStage(STAGE_IN_WORLD, "closeAllAzUIs")
  else
    setStage(STAGE_BOOT, "closeAllAzUIs")
  end

  applyHudAndMinimap()
  reinforceHudAndMinimap(1500)
end

RegisterNetEvent("azfw:characterui:forceClose")
AddEventHandler("azfw:characterui:forceClose", function(reason)
  dprint("Az-LobbyRouter force close requested: %s", tostring(reason or "no_reason"))
  closeAllAzUIs()
end)

RegisterNetEvent("azfw:characterui:open")
AddEventHandler("azfw:characterui:open", function(chars)
  if azLobbyRouterIsHoldingCharacterUI() then
    dprint("Az-LobbyRouter is holding CharacterUI; open request ignored.")
    return
  end

  if type(chars) == "table" and #chars > 0 then cachedChars = chars end
  TriggerServerEvent("azfw:request_characters")
  if not nuiOpen and not spawnNuiOpen then
    openAzfwUI(cachedChars)
  end
end)

AddEventHandler("azfw:setup:closedLocal", function()
  if (nuiOpen or spawnNuiOpen) and nuiOwner then
    hardResetFocus()
  end
end)

local booted = false
local function bootCharacterUI()
  if booted then return end
  booted = true
  CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(200) end

    local lobbyWaitUntil = ms() + 60000
    while azLobbyRouterIsHoldingCharacterUI() and ms() < lobbyWaitUntil do
      Wait(250)
    end

    if azLobbyRouterIsHoldingCharacterUI() then
      dprint("Az-LobbyRouter is still holding CharacterUI; skipped automatic character UI boot.")
      return
    end

    Wait(1200)

    if azLobbyRouterIsHoldingCharacterUI() then
      dprint("Az-LobbyRouter started holding CharacterUI during boot delay; skipped automatic open.")
      return
    end

    TriggerServerEvent("azfw:request_characters")
    if not nuiOpen and not spawnNuiOpen then
      openAzfwUI(cachedChars)
    end
  end)
end

AddEventHandler("onClientResourceStart", function(res)
  if res ~= RESOURCE_NAME then return end
  CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(200) end
    Wait(400)
    booted = false
    bootCharacterUI()

    SetTimeout(2500, function()
      if not (nuiOpen or spawnNuiOpen or inPreviewInstance) then
        setSpawnedInWorld(true, "resource_restart_heuristic")
      end
    end)
  end)
end)

AddEventHandler("playerSpawned", function()
  if firstSpawn then
    firstSpawn = false
    booted = false
    SetTimeout(400, function() bootCharacterUI() end)
  end
end)

RegisterNUICallback("azfw_nui_ready", function(_, cb)
  nuiReady = true
  if (nuiOpen or spawnNuiOpen) and nuiOwner then hardResetFocus() end
  if nuiOpen and pendingUiIssue then
    pushPendingUiIssueToNui()
  end
  cb({ ok = true })
end)

RegisterNUICallback("azfw_select_character", function(data, cb)
  cb({ ok = true })
  local charid = data and data.charid
  if not charid then return end

  currentCharId = tostring(charid)

  if nuiOpen then
    previewCharacter(currentCharId)
    ensureHeldMugshot(currentCharId)
    ensureMugshotForCurrentPreview(currentCharId, true)
  end

  selectionLockUntil = ms() + SELECTION_LOCK_TIME
  SetTimeout(SELECTION_LOCK_TIME + 200, function()
    if selectionLockUntil > 0 and selectionLockUntil <= ms() then selectionLockUntil = 0 end
  end)

  TriggerServerEvent("azfw:set_active_character", currentCharId)
  TriggerServerEvent("az-fw-money:selectCharacter", currentCharId)
  TriggerServerEvent("vMenu-Bridge:setActiveCharacter", currentCharId)
end)

RegisterNetEvent("azfw:characterCreated")
AddEventHandler("azfw:characterCreated", function(charid)
  local cid = tostring(charid or "")
  __azfwIntroNewCharacterCharId = cid
  __pendingNewCharPreSpawnAppearanceCid = cid ~= "" and cid or nil
end)

RegisterNUICallback("azfw_create_character", function(data, cb)
  cb({ ok = true })
  local first = (data and data.first) or ""
  local last  = (data and data.last) or ""
  if first == "" then return end

  __pendingNewCharCustomize = false
  __allowCustomizeNow = false
  __pendingNewCharCid = nil
  __pendingNewCharPreSpawnAppearanceCid = nil
  __preSpawnCustomizeBusy = false
  __continueToSpawnAfterCustomizeCid = nil

  TriggerServerEvent("azfw:register_character", first, last)
end)

RegisterNUICallback("azfw_delete_character", function(data, cb)
  cb({ ok = true })
  local charid = data and data.charid
  if not charid then return end
  if tostring(__pendingNewCharPreSpawnAppearanceCid or "") == tostring(charid) then
    __pendingNewCharPreSpawnAppearanceCid = nil
  end
  TriggerServerEvent("azfw:delete_character", tostring(charid))
end)

RegisterNUICallback("azfw_close_ui", function(_, cb)
  cb({ ok = true })
  closeAzfwUI(true, true)
end)

RegisterNUICallback("azfw_preview_character", function(data, cb)
  cb({ ok = true })
  local charid = data and data.charid
  if not charid then return end
  if not nuiOpen then return end
  currentCharId = tostring(charid)
  previewCharacter(currentCharId)
  ensureHeldMugshot(currentCharId)
  ensureMugshotForCurrentPreview(currentCharId, true)
end)

RegisterNUICallback("closeSpawnMenu", function(_, cb)
  cb("ok")
  closeAllAzUIs()
  exitPreviewInstance()
  restoreAfterPreviewIfNeeded()
  applyHudAndMinimap()
  reinforceHudAndMinimap(1500)
end)

RegisterNUICallback("request_spawns", function(_, cb)
  TriggerServerEvent("spawn_selector:requestSpawns", currentCharId)
  cb({ ok = true })
end)

RegisterNUICallback("request_edit_permission", function(_, cb)
  TriggerServerEvent("spawn_selector:checkAdmin")
  cb({ ok = true })
end)

RegisterNUICallback("saveSpawns", function(data, cb)
  local spawns = data and data.spawns
  if type(spawns) ~= "table" then cb({ ok=false, err="invalid_spawns" }) return end
  TriggerServerEvent("spawn_selector:saveSpawns", spawns)
  cb({ ok = true })
end)

RegisterNUICallback("request_player_coords", function(_, cb)
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then cb({ ok=false }) return end
  local c = GetEntityCoords(ped)
  local h = GetEntityHeading(ped)
  cb({ x=c.x, y=c.y, z=c.z, h=h })
end)

local firstJoinWelcomeShownThisSession = false

local function firstJoinSecondsToPretty(s)
  s = tonumber(s) or 0
  if s <= 0 then return "0s" end

  local hours = math.floor(s / 3600)
  local mins  = math.floor((s % 3600) / 60)
  local secs  = math.floor(s % 60)

  if hours > 0 then
    return string.format("%dh %dm", hours, mins)
  elseif mins > 0 then
    return string.format("%dm %ds", mins, secs)
  else
    return string.format("%ds", secs)
  end
end

local function getRandomFirstCarModel()
  local list = (((Config.FirstJoin or {}).FirstCar or {}).SedanModels) or {}
  if #list == 0 then return "asea" end
  return list[math.random(1, #list)]
end

local function makeFirstCarPlate()
  return string.format("1ST-%d%d", math.random(0, 9), math.random(0, 9))
end

local function tryShowFirstJoinWelcomeAfterSpawn()
  if not Config.UseFirstJoin then return end
  if firstJoinWelcomeShownThisSession then return end

  local welcome = ((Config.FirstJoin or {}).Welcome) or {}
  local shouldShow = lib.callback.await('az_characterui:firstjoin:shouldShowWelcome', false)
  if not shouldShow then return end

  lib.alertDialog({
    header   = tostring(welcome.Header or 'Welcome to the Server'),
    content  = tostring(welcome.Content or ''),
    centered = (welcome.Centered ~= false),
    cancel   = false,
    size     = tostring(welcome.Size or 'md')
  })

  TriggerServerEvent('az_characterui:firstjoin:markWelcomeSeen')
  firstJoinWelcomeShownThisSession = true
end

RegisterCommand('firstcar', function()
  if not Config.UseFirstJoin then
    lib.notify({
      title = 'First Car',
      description = 'First Join is disabled in config.',
      type = 'error'
    })
    return
  end

  local result = lib.callback.await('az_characterui:firstjoin:claimFirstCar', false)

  if not result or not result.ok then
    local remaining = result and result.remaining or ((((Config.FirstJoin or {}).FirstCar or {}).CooldownSeconds) or (24 * 60 * 60))
    local msg = ('You already claimed your free car. Come back in **%s**.'):format(firstJoinSecondsToPretty(remaining))

    lib.notify({
      title = 'First Car',
      description = msg,
      type = 'error'
    })

    if (((Config.FirstJoin or {}).FirstCar or {}).ShowCooldownChatMessage) ~= false then
      TriggerEvent('chat:addMessage', { args = { '^1First Car', msg } })
    end
    return
  end

  local chosenName = getRandomFirstCarModel()
  local model = joaat(chosenName)

  if not IsModelInCdimage(model) then
    lib.notify({
      title = 'First Car',
      description = 'Vehicle model is invalid in config.',
      type = 'error'
    })
    return
  end

  RequestModel(model)
  while not HasModelLoaded(model) do Wait(0) end

  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  local forward = GetEntityForwardVector(ped)
  local spawn = coords + (forward * 3.0)

  local veh = CreateVehicle(model, spawn.x, spawn.y, spawn.z, heading, true, false)
  SetModelAsNoLongerNeeded(model)

  if veh and veh ~= 0 then
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, makeFirstCarPlate())

    if (((Config.FirstJoin or {}).FirstCar or {}).WarpIntoVehicle) ~= false then
      TaskWarpPedIntoVehicle(ped, veh, -1)
    end

    lib.notify({
      title = 'First Car',
      description = ('Your free car **(%s)** has been delivered!\nRemember: **SHIFT + F** to park and save its spot.'):format(chosenName),
      type = 'success'
    })
  else
    lib.notify({
      title = 'First Car',
      description = 'Failed to spawn vehicle.',
      type = 'error'
    })
  end
end, false)

TriggerEvent('chat:addSuggestion', '/firstcar', 'Claim your free starter car (1 per 24 hours).')

local _spawnDeathFxToken = 0

local function _safeStopSpawnDeathFx(opts)
  if opts.ScreenEffect and opts.ScreenEffect ~= "" then
    StopScreenEffect(opts.ScreenEffect)
  end
  if opts.UseTimecycle then
    ClearExtraTimecycleModifier()
    ClearTimecycleModifier()
  end
  if opts.MotionBlur then
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
      SetPedMotionBlur(ped, false)
    end
  end
end

local function playSpawnDeathScreen(opts)
  if not opts or opts.Enabled ~= true then return end

  _spawnDeathFxToken = _spawnDeathFxToken + 1
  local myToken = _spawnDeathFxToken

  local ped = PlayerPedId()

  if opts.HideRadarDuring then
    DisplayRadar(false)
  end

  if opts.UseTimecycle then
    ClearTimecycleModifier()
    if opts.Timecycle and opts.Timecycle ~= "" then
      SetTimecycleModifier(opts.Timecycle)
      SetTimecycleModifierStrength(tonumber(opts.TimecycleStrength) or 0.7)
    end
    if opts.ExtraTimecycle and opts.ExtraTimecycle ~= "" then
      SetExtraTimecycleModifier(opts.ExtraTimecycle)
      SetExtraTimecycleModifierStrength(tonumber(opts.ExtraTimecycleStrength) or 1.0)
    end
  end

  if opts.MotionBlur and DoesEntityExist(ped) then
    SetPedMotionBlur(ped, true)
  end

  if opts.ScreenEffect and opts.ScreenEffect ~= "" then
    StartScreenEffect(opts.ScreenEffect, 0, false)
  end

  if opts.PlaySound then
    local sName = tostring(opts.SoundName or "")
    local sSet  = tostring(opts.SoundSet or "")
    if sName ~= "" and sSet ~= "" then
      PlaySoundFrontend(-1, sName, sSet, true)
    end
  end

  local sf = nil
  if opts.ShowShard then
    sf = RequestScaleformMovie("mp_big_message_freemode")
    while sf and not HasScaleformMovieLoaded(sf) do
      Wait(0)
    end

    if sf and HasScaleformMovieLoaded(sf) then
      BeginScaleformMovieMethod(sf, "SHOW_SHARD_WASTED_MP_MESSAGE")
      ScaleformMovieMethodAddParamPlayerNameString(tostring(opts.Title or "WASTED"))
      ScaleformMovieMethodAddParamPlayerNameString(tostring(opts.Subtitle or ""))
      ScaleformMovieMethodAddParamInt(tonumber(opts.ShardBgColor) or 5)
      EndScaleformMovieMethod()
    end
  end

  local endsAt = ms() + (tonumber(opts.DurationMs) or 2000)

  while _spawnDeathFxToken == myToken and ms() < endsAt do
    if opts.HideRadarDuring then
      DisplayRadar(false)
    end

    if sf then
      DrawScaleformMovieFullscreen(sf, 255, 255, 255, 255, 0)
    end

    Wait(0)
  end

  if sf then
    SetScaleformMovieAsNoLongerNeeded(sf)
  end

  if _spawnDeathFxToken == myToken then
    _safeStopSpawnDeathFx(opts)
  end
end

RegisterNUICallback("selectSpawn", function(data, cb)
  cb({ ok = true })
  local spawn = data and data.spawn
  if type(spawn) ~= "table" then return end

  local coords
  local heading = 0.0

  if spawn.spawn and spawn.spawn.coords then
    coords = spawn.spawn.coords
    heading = tonumber(spawn.spawn.heading) or 0.0
  elseif spawn.coords then
    coords = spawn.coords
    heading = tonumber(spawn.heading) or 0.0
  end

  if not coords or coords.x == nil or coords.y == nil or coords.z == nil then return end

  __allowCustomizeNow = false

  closeAllAzUIs()

  CreateThread(function()
    exitPreviewInstance()
    Wait(0)

    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
      deathSuppress(8000)
      DoScreenFadeOut(720)
      local t0 = ms()
      while not IsScreenFadedOut() and (ms() - t0) < 1200 do Wait(0) end

      FreezeEntityPosition(ped, true)
      SetEntityVisible(ped, false, false)

      SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
      SetEntityHeading(ped, heading)

      RequestCollisionAtCoord(coords.x, coords.y, coords.z)
      local tCol = ms()
      while not HasCollisionLoadedAroundEntity(ped) and (ms() - tCol) < 7000 do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
      end

      SetEntityVisible(ped, false, false)

      setStage(STAGE_SPAWNING, "spawn_selected_begin")

      if currentCharId then

        applyOrCustomizeForChar(currentCharId, not shouldPreSpawnCustomizeNewCharacter(currentCharId), "spawn")
        saveLastPosToServer("after_spawn_select")

      end

      previewReturn = nil

      local introResult = nil
      local shouldConsiderIntro = (__azfwIntroPlayedThisSession ~= true)
      local isNewCharSpawn = tostring(__azfwIntroNewCharacterCharId or "") ~= "" and tostring(__azfwIntroNewCharacterCharId or "") == tostring(currentCharId or "")

      if shouldConsiderIntro and _G.AzFwPlayIntroCutsceneIfNeeded then
        introResult = _G.AzFwPlayIntroCutsceneIfNeeded({
          mode = "ui",
          isNewCharacter = isNewCharSpawn,
          charid = currentCharId,
          spawn = { x = coords.x, y = coords.y, z = coords.z, h = heading }
        })
        if type(introResult) == "table" and introResult.played == true then
          __azfwIntroPlayedThisSession = true
          __azfwIntroNewCharacterCharId = nil
        end
      end

      local introPlayed = (type(introResult) == "table" and introResult.played == true)
      if DoesEntityExist(ped) then
        SetEntityVisible(ped, true, false)
        FreezeEntityPosition(ped, false)
      end

      if introPlayed then
        Wait(120)
      else
        Wait(500)
      end
      setSpawnedInWorld(true, "spawn_selected")

      local spawnFadeInMs = introPlayed and 1800 or 6020
      if IsScreenFadedOut() or introPlayed then
        DoScreenFadeIn(spawnFadeInMs)
      end
      local fadeWaitStart = ms()
      while not IsScreenFadedIn() and (ms() - fadeWaitStart) < (spawnFadeInMs + 2000) do
        Wait(0)
      end
      Wait(150)

      deathPause(false)

      local shouldShowSpawnDeath = false
      if Config.SpawnDeathScreen and Config.SpawnDeathScreen.Enabled then
        if shouldConsiderIntro then
          if type(introResult) == "table" then
            if introResult.played == true then
              shouldShowSpawnDeath = introResult.showDeathScreenAfter ~= false
            else
              local introReason = tostring(introResult.reason or "")
              shouldShowSpawnDeath = (introReason == "disabled" or introReason == "already_seen" or introReason == "not_new_character" or introReason == "discord_mode_disabled" or introReason == "no_discord" or introReason == "server_no")
            end
          else
            shouldShowSpawnDeath = false
          end
        else
          shouldShowSpawnDeath = true
        end
      end
      if shouldShowSpawnDeath then
        playSpawnDeathScreen(Config.SpawnDeathScreen)
      end

      tryShowFirstJoinWelcomeAfterSpawn()

      applyHudAndMinimap()
      reinforceHudAndMinimap(5000)

      __allowCustomizeNow = false

      if __pendingNewCharCustomize and currentCharId and tostring(__pendingNewCharCid or "") == tostring(currentCharId) then

        __allowCustomizeNow = true

        local confirmed = confirmNoAppearance(currentCharId)

        if confirmed and confirmed ~= false then

          apCacheSet(tostring(currentCharId), confirmed)
          applyAppearanceReliable(confirmed, "spawn_confirm", true)
          dprint("CUSTOMIZE skipped: appearance exists (confirm) cid=%s", tostring(currentCharId))

          __pendingNewCharCustomize = false
          __pendingNewCharCid = nil
          __allowCustomizeNow = false

        elseif confirmed == false then

          __pendingNewCharCustomize = false
          __pendingNewCharCid = nil
          Wait(150)
          openCustomizationForChar(currentCharId, "new_character_spawn")

          SetTimeout(1500, function() __allowCustomizeNow = false end)

        else

          dprint("CUSTOMIZE skipped: confirm inconclusive cid=%s", tostring(currentCharId))
          __pendingNewCharCustomize = false
          __pendingNewCharCid = nil
          __allowCustomizeNow = false
        end
      end

      SetTimeout(8000, function()
        __allowCustomizeNow = false
      end)
    end
  end)
end)

RegisterNetEvent("azfw:characters_updated")
AddEventHandler("azfw:characters_updated", function(chars)
  cachedChars = chars or {}
  if nuiOpen then
    nuiSend({ type = "azfw_update_chars", chars = cachedChars })
    prefetchAppearances(cachedChars)
    TriggerServerEvent("azfw:appearance:bulkRequest")

    local firstChar = (cachedChars and cachedChars[1] and (cachedChars[1].charid or cachedChars[1].id or cachedChars[1].cid))
    local stillValid = false
    if currentCharId and type(cachedChars) == "table" then
      for i = 1, #cachedChars do
        local c = cachedChars[i]
        local cid = c and tostring(c.charid or c.id or c.cid or "")
        if cid ~= "" and cid == tostring(currentCharId) then
          stillValid = true
          break
        end
      end
    end

    if (not firstChar) then
      currentCharId = nil
      clearPreviewSelectionVisuals()
    else
      if (not stillValid) then
        currentCharId = tostring(firstChar)
      end
      previewCharacter(currentCharId)
      ensureHeldMugshot(currentCharId)
      ensureMugshotForCurrentPreview(currentCharId, true)
    end
  end
end)

RegisterNetEvent("azfw:appearance:bulk")
AddEventHandler("azfw:appearance:bulk", function(map)
  if type(map) ~= "table" then return end
  local count = 0
  for cid, ap in pairs(map) do
    cid = tostring(cid)
    if type(ap) == "string" and ap ~= "" then
      apCacheSet(cid, ap)
      local mh = tryGetModelFromAppearance(ap)
      if mh then pcall(function() RequestModel(mh) end) end
      count = count + 1
    end
  end
  dprint("AP BULK received entries=%d", count)
  if nuiOpen and currentCharId then
    previewCharacter(currentCharId)
    ensureHeldMugshot(currentCharId)
    ensureMugshotForCurrentPreview(currentCharId, true)
  end
end)

RegisterNetEvent("azfw:activeAppearance")
AddEventHandler("azfw:activeAppearance", function(charid, appearanceJson)
  if not charid then return end
  charid = tostring(charid)
  if appearanceJson and type(appearanceJson) == "string" and appearanceJson ~= "" then
    apCacheSet(charid, appearanceJson)
    local mh = tryGetModelFromAppearance(appearanceJson)
    if mh then pcall(function() RequestModel(mh) end) end
    dprint("ACTIVE AP received cid=%s bytes=%d", charid, #appearanceJson)
  else
    apCacheSet(charid, false)
    dprint("ACTIVE AP none cid=%s", charid)
  end

  if nuiOpen and currentCharId and tostring(currentCharId) == tostring(charid) then
    previewCharacter(currentCharId)
    ensureHeldMugshot(currentCharId)
    ensureMugshotForCurrentPreview(currentCharId, true)
  end
end)

RegisterNetEvent("az-fw-money:characterSelected")
AddEventHandler("az-fw-money:characterSelected", function(charid)
  if charid then currentCharId = tostring(charid) end
  setSpawnedInWorld(false, "character_selected")

  closeAzfwUI(false, false)
  if currentCharId then requestAppearanceAsync(currentCharId) end

  if currentCharId and shouldPreSpawnCustomizeNewCharacter(currentCharId) then
    beginPreSpawnAppearanceFlow(currentCharId)
    return
  end

  SetTimeout(60, function()
    TriggerServerEvent("spawn_selector:requestSpawns", currentCharId)
  end)
end)

RegisterNetEvent("spawn_selector:sendSpawns")
AddEventHandler("spawn_selector:sendSpawns", function(spawns, mapBounds, isAdmin)
  saveLastPosToServer("open_spawn_selector")

  if nuiOpen then closeAzfwUI(false, false) end
  ensurePreviewInstance()

  __allowCustomizeNow = false

  deathPause(true)
  deathSuppress(8000)

  spawnNuiOpen = true
  setNuiOwner("spawn")
  setStage(STAGE_SPAWN_UI, "spawn_selector_open")

  nuiSend({ type = "spawn_visibility", open = true })
  nuiSend({
    type = "spawn_data",
    spawns = spawns or {},
    mapBounds = mapBounds or {},
    resourceName = RESOURCE_NAME,
    isAdmin = isAdmin and true or false,
    openEditor = false
  })

  hardResetFocus()
end)

RegisterNetEvent("spawn_selector:adminCheckResult")
AddEventHandler("spawn_selector:adminCheckResult", function(isAdmin)
  nuiSend({ type = "spawn_admin", isAdmin = isAdmin and true or false })
end)

RegisterNetEvent("spawn_selector:spawnsSaved")
AddEventHandler("spawn_selector:spawnsSaved", function(ok, err)
  nuiSend({ type = "saveResult", ok = ok and true or false, err = err })
end)

RegisterNetEvent("spawn_selector:spawnsUpdated")
AddEventHandler("spawn_selector:spawnsUpdated", function(spawns)
  nuiSend({ type = "spawn_update", spawns = spawns or {} })
end)

RegisterNetEvent("azfw:open_ui")
AddEventHandler("azfw:open_ui", function(chars)
  if type(chars) == "table" and #chars > 0 then cachedChars = chars end
  if azLobbyRouterIsHoldingCharacterUI() then
    dprint("Az-LobbyRouter is holding CharacterUI; azfw:open_ui ignored until lobby is selected.")
    return
  end
  openAzfwUI(chars)
end)

CreateThread(function()
  while true do
    Wait(Config.LastLocationUpdateIntervalMs or 10000)

    if not Config.EnableLastLocation then goto cont end
    if not currentCharId then goto cont end
    if not playerSpawnedInWorld then goto cont end
    if nuiOpen or spawnNuiOpen or inPreviewInstance then goto cont end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then goto cont end

    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)

    TriggerServerEvent("azfw:lastloc:update", tostring(currentCharId), c.x, c.y, c.z, h)

    ::cont::
  end
end)

CreateThread(function()
  while true do
    Wait(Config.AppearanceAutosaveMs or 60000)

    if not Config.AppearanceAutosaveEnabled then goto cont end
    if not currentCharId then goto cont end

    if (nuiOpen or spawnNuiOpen) and not Config.AppearanceAutosaveInMenus then
      goto cont
    end

    saveAppearanceToServer("autosave", false)

    ::cont::
  end
end)

CreateThread(function()
  Wait(0)
  if not Config.EnableOpenCommand then return end

  local cmd = tostring(Config.OpenCommand or "characters")
  if cmd == "" then cmd = "characters" end

  RegisterCommand(cmd, function()

    if GetResourceState('ox_inventory') == 'started' then
      pcall(function() exports.ox_inventory:closeInventory() end)
      TriggerEvent('ox_inventory:closeInventory')
      SetNuiFocus(false, false)
      SetNuiFocusKeepInput(false)
      Wait(100)
    end

    if spawnNuiOpen or nuiOwner == "spawn" then return end
    if nuiOpen then
      closeAzfwUI(true, true)
      return
    end

    saveLastPosToServer("command_open_characters")

    TriggerServerEvent("azfw:request_characters")
    openAzfwUI(cachedChars)
  end, false)

  pcall(function()
    TriggerEvent("chat:addSuggestion", "/" .. cmd, "Open the character menu")
  end)
end)

CreateThread(function()
  Wait(0)
  if not Config.EnableSpawnMenuCommand then return end

  local cmd = tostring(Config.SpawnMenuCommand or "spawnmenu")
  if cmd == "" then cmd = "spawnmenu" end

  RegisterCommand(cmd, function()
    if Config.SpawnMenuAdminOnly then
      TriggerServerEvent("spawn_selector:checkAdmin")
    end

    if nuiOpen then closeAzfwUI(true, false) end

    saveLastPosToServer("command_open_spawnmenu")

    TriggerServerEvent("spawn_selector:requestSpawns", currentCharId)
  end, false)

  pcall(function()
    TriggerEvent("chat:addSuggestion", "/" .. cmd, "Open the spawn menu (admin) / spawn selector")
  end)
end)

CreateThread(function()
  while true do
    Wait(0)
    if nuiOpen and IsControlJustReleased(0, 200) then
      closeAzfwUI(true, true)
    end
  end
end)

AddEventHandler("onClientResourceStop", function(res)
  if res ~= RESOURCE_NAME then return end

  __allowCustomizeNow = false
  __pendingNewCharCustomize = false
  __pendingNewCharCid = nil
  __azfwIntroNewCharacterCharId = nil
  __azfwIntroPlayedThisSession = false

  saveLastPosToServer("resourceStop")
  saveAppearanceToServer("resourceStop", true)

  destroyPreviewCam()
  destroyMugshot()
  cleanupNearbyHeldMugshotProps(12.0)
  focusOff()
  exitPreviewInstance()
  deathPause(false)
  applyHudAndMinimap()
  reinforceHudAndMinimap(1500)
end)

print(("^2[Az-CharacterUI]^7 client loaded. Resource=%s"):format(RESOURCE_NAME))
