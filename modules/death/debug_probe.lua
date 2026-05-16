local DeathCfg = (Config and Config.Death) or {}
if DeathCfg.Enabled == false then return end

local RES = GetCurrentResourceName()
_G.AzDeathProbeLoaded = true

local probeDebug = true
local probeForceFallback = true
local probeLastFatalAt = 0
local probeLastReason = 'none'
local probeDownedByProbe = false
local probeRespawnAt = 0
local probeBleedoutAt = 0
local probeHoldStart = 0
local probeLastStatusPrint = 0

local function notify(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, false)
end

local function chat(msg)
  TriggerEvent('chat:addMessage', { color = { 80, 200, 255 }, args = { '^5Az-Death Probe', tostring(msg) } })
end

local function slog(msg)
  print(("^5[%s PROBE]^7 %s"):format(RES, tostring(msg)))
  TriggerServerEvent('Az-Death:server:probeLog', tostring(msg))
end

local function say(msg)
  if not probeDebug then return end
  chat(msg)
  notify(('[DeathProbe] %s'):format(tostring(msg)))
  slog(msg)
end

local function status(label)
  local ped = PlayerPedId()
  local exists = ped ~= 0 and DoesEntityExist(ped)
  local hp = exists and GetEntityHealth(ped) or -1
  local armor = exists and GetPedArmour(ped) or -1
  local dead = exists and IsEntityDead(ped) or false
  local dying = exists and IsPedDeadOrDying(ped, true) or false
  local fatal = exists and IsPedFatallyInjured(ped) or false
  local msg = table.concat({
    tostring(label or 'status'),
    ('hp=%s'):format(hp),
    ('armor=%s'):format(armor),
    ('dead=%s'):format(tostring(dead)),
    ('dying=%s'):format(tostring(dying)),
    ('fatal=%s'):format(tostring(fatal)),
    ('baseevents=%s'):format(GetResourceState('baseevents')),
    ('spawnmanager=%s'):format(GetResourceState('spawnmanager')),
    ('mainLoaded=%s'):format(tostring(_G.AzDeathMainLoaded == true)),
    ('probeDowned=%s'):format(tostring(probeDownedByProbe == true))
  }, ' | ')
  chat(msg)
  slog(msg)
end

print(("^2[%s PROBE]^7 Death probe loaded"):format(RES))
chat('Death probe loaded.')

local function disableSpawnmanagerAutoRespawn()
  if GetResourceState('spawnmanager') ~= 'started' then return end
  pcall(function()
    exports.spawnmanager:setAutoSpawn(false)
  end)
end

local function getNearestRespawn()
  local list = (DeathCfg.RespawnLocations or {})
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return nil end
  local p = GetEntityCoords(ped)
  local best, bestDist = nil, 999999.0
  for _,loc in ipairs(list) do
    local c = loc.coords
    if c then
      local d = #(p - c)
      if d < bestDist then
        best, bestDist = loc, d
      end
    end
  end
  return best
end

local function requestAnim(dict)
  RequestAnimDict(dict)
  local tries = 0
  while not HasAnimDictLoaded(dict) and tries < 100 do
    Wait(20)
    tries = tries + 1
  end
  return HasAnimDictLoaded(dict)
end

local function probeEnterDowned(reason)
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  if probeDownedByProbe then return end
  disableSpawnmanagerAutoRespawn()
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    Wait(50)
    ped = PlayerPedId()
  end
  probeDownedByProbe = true
  probeRespawnAt = GetGameTimer() + (((DeathCfg.ReviveTime or 60) * 1000))
  probeBleedoutAt = GetGameTimer() + (((DeathCfg.BleedoutTime or 300) * 1000))
  SetEntityHealth(ped, math.max(tonumber((DeathCfg.Downed and DeathCfg.Downed.HealthOnDown) or 110) or 110, 110))
  SetPedArmour(ped, 0)
  SetEntityInvincible(ped, true)
  SetPlayerInvincible(PlayerId(), true)
  ClearPedTasksImmediately(ped)
  if requestAnim((DeathCfg.Downed and DeathCfg.Downed.AnimDict) or 'dead') then
    TaskPlayAnim(ped, (DeathCfg.Downed and DeathCfg.Downed.AnimDict) or 'dead', (DeathCfg.Downed and DeathCfg.Downed.AnimName) or 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
  end
  say(('Probe fallback entered downed state (%s)'):format(tostring(reason or 'unknown')))
end

local function probeRespawn(label)
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  local loc = getNearestRespawn()
  DoScreenFadeOut(500)
  while not IsScreenFadedOut() do Wait(10) end
  Wait((DeathCfg.Hospital and DeathCfg.Hospital.RespawnSeconds or 3) * 1000)
  if loc and loc.coords then
    SetEntityCoordsNoOffset(ped, loc.coords.x, loc.coords.y, loc.coords.z, false, false, false)
    SetEntityHeading(ped, loc.heading or 0.0)
  end
  NetworkResurrectLocalPlayer(GetEntityCoords(ped).x, GetEntityCoords(ped).y, GetEntityCoords(ped).z, GetEntityHeading(ped), true, false)
  SetEntityHealth(ped, GetEntityMaxHealth(ped))
  SetEntityInvincible(ped, false)
  SetPlayerInvincible(PlayerId(), false)
  ClearPedTasksImmediately(ped)
  probeDownedByProbe = false
  probeHoldStart = 0
  DoScreenFadeIn(800)
  say(label or 'Probe hospital respawn complete')
end

RegisterCommand('deathprobe', function()
  status('deathprobe')
end, false)

RegisterCommand('deathdebug', function()
  probeDebug = not probeDebug
  chat(('Death probe debug %s'):format(probeDebug and 'enabled' or 'disabled'))
  slog(('deathdebug toggled %s'):format(tostring(probeDebug)))
  status('deathdebug')
end, false)

RegisterCommand('deathstatus', function()
  probeDebug = true
  status('deathstatus')
end, false)

RegisterCommand('deathfallback', function()
  probeForceFallback = not probeForceFallback
  say(('Probe force fallback %s'):format(probeForceFallback and 'enabled' or 'disabled'))
end, false)

AddEventHandler('onClientResourceStart', function(res)
  if res == RES or res == 'spawnmanager' then
    Wait(250)
    disableSpawnmanagerAutoRespawn()
    status('resource_start')
  end
end)

AddEventHandler('baseevents:onPlayerDied', function(...)
  probeLastFatalAt = GetGameTimer()
  probeLastReason = 'baseevents:onPlayerDied'
  say('baseevents:onPlayerDied fired')
end)

AddEventHandler('baseevents:onPlayerKilled', function(...)
  probeLastFatalAt = GetGameTimer()
  probeLastReason = 'baseevents:onPlayerKilled'
  say('baseevents:onPlayerKilled fired')
end)

AddEventHandler('baseevents:onPlayerWasted', function(...)
  probeLastFatalAt = GetGameTimer()
  probeLastReason = 'baseevents:onPlayerWasted'
  say('baseevents:onPlayerWasted fired')
end)

AddEventHandler('playerSpawned', function()
  disableSpawnmanagerAutoRespawn()
  say('playerSpawned fired')
end)

AddEventHandler('gameEventTriggered', function(name, args)
  if name ~= 'CEventNetworkEntityDamage' then return end
  local ped = PlayerPedId()
  if args[1] ~= ped then return end
  local dmg = tonumber(args[13] or 0) or 0
  local hp = GetEntityHealth(ped)
  if dmg > 0 then
    probeLastFatalAt = GetGameTimer()
    probeLastReason = ('CEventNetworkEntityDamage damage=%s hp=%s'):format(dmg, hp)
    if probeDebug and (GetGameTimer() - probeLastStatusPrint) > 750 then
      probeLastStatusPrint = GetGameTimer()
      slog(probeLastReason)
    end
  end
end)

CreateThread(function()
  Wait(1500)
  status('probe_boot')
  if GetResourceState('baseevents') ~= 'started' then
    say('baseevents is not started')
  end
end)

CreateThread(function()
  while true do
    Wait(100)
    disableSpawnmanagerAutoRespawn()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then goto cont end
    local hp = GetEntityHealth(ped)
    local fatal = IsEntityDead(ped) or IsPedDeadOrDying(ped, true) or IsPedFatallyInjured(ped)
    if fatal then
      probeLastFatalAt = GetGameTimer()
      if probeLastReason == 'none' then
        probeLastReason = ('fatal hp=%s'):format(hp)
      end
      if _G.AzDeathMainLoaded == true then
        TriggerEvent('Az-Death:debug:forceDownedFallback', probeLastReason)
      elseif probeForceFallback then
        probeEnterDowned(probeLastReason)
      end
    end
    ::cont::
  end
end)

CreateThread(function()
  while true do
    Wait(probeDownedByProbe and 0 or 250)
    if not probeDownedByProbe then goto cont3 end
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then goto cont3 end
    DisableAllControlActions(0)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 249, true)
    EnableControlAction(0, 46, true)
    EnableControlAction(0, tonumber(DeathCfg.EarlyRespawnKey or 38) or 38, true)
    if IsPedGettingUp(ped) or IsPedRagdoll(ped) or not IsEntityPlayingAnim(ped, (DeathCfg.Downed and DeathCfg.Downed.AnimDict) or 'dead', (DeathCfg.Downed and DeathCfg.Downed.AnimName) or 'dead_a', 3) then
      ClearPedTasksImmediately(ped)
      if requestAnim((DeathCfg.Downed and DeathCfg.Downed.AnimDict) or 'dead') then
        TaskPlayAnim(ped, (DeathCfg.Downed and DeathCfg.Downed.AnimDict) or 'dead', (DeathCfg.Downed and DeathCfg.Downed.AnimName) or 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
      end
    end
    local nowMs = GetGameTimer()
    local reviveLeft = math.max(0, math.ceil((probeRespawnAt - nowMs) / 1000))
    local bleedoutLeft = math.max(0, math.ceil((probeBleedoutAt - nowMs) / 1000))
    SetTextFont(4)
    SetTextScale(0.42, 0.42)
    SetTextColour(255,255,255,215)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('~r~DOWNED~s~ [probe fallback] | Respawn in %ss | Bleedout %ss'):format(reviveLeft, bleedoutLeft))
    EndTextCommandDisplayText(0.5, 0.88)
    if nowMs >= probeRespawnAt then
      if IsControlPressed(0, tonumber(DeathCfg.EarlyRespawnKey or 38) or 38) then
        if probeHoldStart == 0 then probeHoldStart = nowMs end
        if (nowMs - probeHoldStart) >= tonumber(DeathCfg.EarlyRespawnHoldMs or 2500) then
          probeRespawn('Probe early respawn used')
        end
      else
        probeHoldStart = 0
      end
    end
    if nowMs >= probeBleedoutAt then
      probeRespawn('Probe bleedout respawn used')
    end
    ::cont3::
  end
end)
