local RESOURCE = GetCurrentResourceName()

Config = Config or {}
local DEBUG = Config.Debug == true

Config.ShowAliveInjuries = (Config.ShowAliveInjuries == true)
Config.ShowDeadInjuries  = (Config.ShowDeadInjuries ~= false)

local function dprint(...)
  if not DEBUG then return end
  local t = {}
  for i=1,select("#", ...) do t[#t+1] = tostring(select(i, ...)) end
  print(("^3[%s]^7 %s"):format(RESOURCE, table.concat(t, " ")))
end

local function notify(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, false)
end

local injuryPauseState = false

local function warzoneDeathBlocked()
  local st = LocalPlayer and LocalPlayer.state
  if injuryPauseState == true then return true end
  if st and (st.in5MWarzone == true or st.fiveMWarzone == true or st.azWarzone == true or st.azDeathSuppressed == true) then return true end
  return false
end

local function clearWarzoneDeathHud()
  SendNUIMessage({ type = 'injury:update', injuries = {}, bleeding = { active = false, rate = 0 }, pinned = false })
  SendNUIMessage({ type = 'downed:update', visible = false, revive = 0, bleedout = 0, hold = 0, canRespawn = false })
  SendNUIMessage({ type = 'medprompt:update', visible = false, name = 'Medical Action' })
end

print(("^2[%s]^7 Injury system loaded ✅"):format(RESOURCE))

local function disableSpawnmanagerAutoRespawn()
  if GetResourceState('spawnmanager') ~= 'started' then return end
  local ok, err = pcall(function()
    exports.spawnmanager:setAutoSpawn(false)
  end)
  if DEBUG then
    if ok then
      dprint('spawnmanager auto-respawn disabled')
    else
      dprint('failed to disable spawnmanager auto-respawn:', err)
    end
  end
end

CreateThread(function()
  Wait(500)
  disableSpawnmanagerAutoRespawn()
end)

AddEventHandler('onClientResourceStart', function(resName)
  if resName == 'spawnmanager' or resName == GetCurrentResourceName() then
    Wait(250)
    disableSpawnmanagerAutoRespawn()
  end
end)

local REGION_TO_ZONE = {
  head  = "Head",
  torso = "Torso",
  larm  = "Left Arm",
  rarm  = "Right Arm",
  lleg  = "Left Leg",
  rleg  = "Right Leg",
}

local BONE_TO_REGION = {
  [31086] = "head",  [39317] = "head",
  [24816] = "torso", [24817] = "torso", [24818] = "torso", [23553] = "torso",
  [64729] = "torso", [40269] = "torso", [45509] = "torso",
  [18905] = "larm",  [61163] = "larm",  [26610] = "larm",
  [57005] = "rarm",  [28252] = "rarm",  [58866] = "rarm",
  [52301] = "rleg",  [36864] = "rleg",  [20781] = "rleg",
  [14201] = "lleg",  [63931] = "lleg",  [58271] = "lleg",
}

local DAMAGE_TYPES = {
  GSW       = "GSW",
  BRUISE    = "Bruising",
  FRACTURE  = "Broken Bone",
  LACERATE  = "Laceration",
  BURN      = "Burn",
  EXPLOSION = "Explosion Trauma",
  ASPHYXIA  = "Asphyxia",
  IMPACT    = "Impact Trauma",
}

local VEHICLE_WEAPON = {
  [`WEAPON_RAMMED_BY_CAR`] = true,
  [`WEAPON_RUN_OVER_BY_CAR`] = true,
}

local ASPHYXIA_WEAPON = {
  [`WEAPON_DROWNING`] = true,
  [`WEAPON_DROWNING_IN_VEHICLE`] = true,
  [`WEAPON_SMOKEGRENADE`] = false,
}

local EXPLOSIVE_WEAPON = {
  [`WEAPON_EXPLOSION`] = true,
  [`WEAPON_GRENADE`] = true,
  [`WEAPON_STICKYBOMB`] = true,
  [`WEAPON_PIPEBOMB`] = true,
  [`WEAPON_PROXMINE`] = true,
  [`WEAPON_MOLOTOV`] = true,
}

local function isMeleeWeapon(hash)
  local melee = {
    [`WEAPON_UNARMED`] = true,
    [`WEAPON_BAT`] = true, [`WEAPON_NIGHTSTICK`] = true, [`WEAPON_CROWBAR`] = true,
    [`WEAPON_HAMMER`] = true, [`WEAPON_WRENCH`] = true, [`WEAPON_FLASHLIGHT`] = true,
    [`WEAPON_GOLFCLUB`] = true, [`WEAPON_POOLCUE`] = true,
    [`WEAPON_KNIFE`] = true, [`WEAPON_DAGGER`] = true, [`WEAPON_MACHETE`] = true,
    [`WEAPON_SWITCHBLADE`] = true, [`WEAPON_BOTTLE`] = true, [`WEAPON_HATCHET`] = true,
    [`WEAPON_KNUCKLE`] = true,
  }
  return melee[hash] == true
end

local function clamp(v,a,b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function now() return GetGameTimer() end

local function regionFromLastBone(ped)
  local _, bone = GetPedLastDamageBone(ped)
  return (BONE_TO_REGION[bone] or "torso"), bone
end

local injuries = {}
local pinned = false
local isDowned = false
local downedStartedAt = 0
local downedCanRespawnAt = 0
local downedBleedoutAt = 0
local respawnHoldStart = 0
local lastDownedHud = 0
local hospitalPromptActive = false
local emsPromptActive = false
local registeredOxTarget = false

local function ensureRegion(region)
  if not injuries[region] then
    injuries[region] = { severity = 0, bleed = 0.0, wounds = {} }
  end
  return injuries[region]
end

local function totalBleed()
  local s = 0.0
  for _,v in pairs(injuries) do s = s + (v.bleed or 0.0) end
  return s
end

local function maxSeverityByRegions(keys)
  local m = 0
  for _,k in ipairs(keys) do
    local r = injuries[k]
    if r and (r.severity or 0) > m then m = r.severity end
  end
  return m
end

local function injuryCount()
  local c = 0
  for _,data in pairs(injuries) do
    if data and (data.severity or 0) > 0 then
      c = c + 1
    end
  end
  return c
end

local recentTraumaContext = nil
local function setRecentTrauma(kind, region, detail, sev, bleed)
  recentTraumaContext = {
    kind = kind or DAMAGE_TYPES.IMPACT,
    region = region or 'torso',
    detail = detail or 'Critical trauma',
    sev = sev or 35,
    bleed = bleed or 0.08,
    at = now()
  }
end

local function toUiArray()
  local arr = {}
  for region,data in pairs(injuries) do
    if (data.severity or 0) > 0 then
      arr[#arr+1] = { zone = REGION_TO_ZONE[region] or "Torso", wounds = data.wounds or {} }
    end
  end
  local order = { Head=1, Torso=2, ["Left Arm"]=3, ["Right Arm"]=4, ["Left Leg"]=5, ["Right Leg"]=6 }
  table.sort(arr, function(a,b) return (order[a.zone] or 99) < (order[b.zone] or 99) end)
  return arr
end

local function bleedingInfo()
  local b = totalBleed()
  local lvl = 0
  if b >= 0.25 then lvl = 1 end
  if b >= 1.50 then lvl = 2 end
  if b >= 3.00 then lvl = 3 end
  return { active = (lvl > 0), level = lvl }
end

local function sendUiUpdate()
  if Config.EnableNui == false then return end
  local ped = PlayerPedId()
  local dead = isDowned or ((ped ~= 0 and DoesEntityExist(ped) and (IsPedDeadOrDying(ped, true) or IsEntityDead(ped))) or false)

  SendNUIMessage({
    type = "injury:update",
    injuries = toUiArray(),
    dead = dead,
    pinned = pinned,
    showAlive = Config.ShowAliveInjuries,
    showDead = Config.ShowDeadInjuries,
    bleeding = bleedingInfo(),
  })
end

local function pushSync()
  TriggerServerEvent("Az-Death:injury:sync", injuries)
end

local function addWound(region, woundType, details, boneName, sevAdd, bleedAdd)
  region = region or "torso"
  local r = ensureRegion(region)

  r.severity = clamp((r.severity or 0) + (sevAdd or 0), 0, 100)
  r.bleed    = clamp((r.bleed or 0.0) + (bleedAdd or 0.0), 0.0, Config.MaxBleed or 8.0)

  r.wounds[#r.wounds+1] = {
    type = woundType,
    details = details,
    bone = boneName,
    severity = math.floor(sevAdd or 0),
    at = now()
  }

  if #r.wounds > (Config.MaxWoundsPerRegion or 12) then
    table.remove(r.wounds, 1)
  end

  pushSync()
  sendUiUpdate()
end

local function drawTxt(x, y, scale, text, center)
  SetTextFont(4)
  SetTextScale(scale, scale)
  SetTextColour(255,255,255,215)
  SetTextOutline()
  SetTextCentre(center == true)
  BeginTextCommandDisplayText('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(x, y)
end

local function sendMedPrompt(visible, name)
  if Config.EnableNui == false then return end
  SendNUIMessage({ type = 'medprompt:update', visible = visible == true, name = name or 'Medical Action' })
end

local function sendDownedHud(visible, respawnLeft, bleedoutLeft, holdPercent, canRespawn)
  if Config.EnableNui == false then return end
  SendNUIMessage({
    type = 'downed:update',
    visible = visible == true,
    subtitle = 'EMS / CPR available',
    respawnLeft = math.max(0, math.floor(respawnLeft or 0)),
    bleedoutLeft = math.max(0, math.floor(bleedoutLeft or 0)),
    holdPercent = math.max(0.0, math.min(100.0, holdPercent or 0.0)),
    canRespawn = canRespawn == true,
  })
end

local function screenTransitionWait(seconds)
  DoScreenFadeOut(500)
  while not IsScreenFadedOut() do Wait(10) end
  Wait(math.floor((seconds or 3) * 1000))
end

local function getPlayersNear(coords, radius)
  local out = {}
  for _,player in ipairs(GetActivePlayers()) do
    local ped = GetPlayerPed(player)
    if ped ~= 0 and DoesEntityExist(ped) then
      local pcoords = GetEntityCoords(ped)
      local dist = #(coords - pcoords)
      if dist <= radius then
        out[#out+1] = { player = player, ped = ped, dist = dist, serverId = GetPlayerServerId(player) }
      end
    end
  end
  table.sort(out, function(a,b) return a.dist < b.dist end)
  return out
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

local function nearestRespawnLocation()
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local best, bestDist = nil, 1e9
  for _,loc in ipairs(Config.RespawnLocations or {}) do
    local d = #(p - loc.coords)
    if d < bestDist then
      best = loc
      bestDist = d
    end
  end
  return best
end

local function notifyDownedLocation()
  if Config.Downed and Config.Downed.NotifyEMS == false then return end
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local s1, s2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
  local street = GetStreetNameFromHashKey(s1 or 0)
  local crossing = (s2 and s2 ~= 0) and GetStreetNameFromHashKey(s2) or ''
  TriggerServerEvent('PlayerDownNotification', street, crossing)
end

local function setDownedInvincible(state)
  local ped = PlayerPedId()
  SetEntityInvincible(ped, state)
  SetPlayerInvincible(PlayerId(), state)
end

local function clearDeathState()
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  setDownedInvincible(false)
  ClearPedTasksImmediately(ped)
  ClearPedSecondaryTask(ped)
  ClearPedBloodDamage(ped)
  sendDownedHud(false, 0, 0, 0, false)
end

local function reviveFromDowned(skipHeal)
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  isDowned = false
  respawnHoldStart = 0
  clearDeathState()
  if not skipHeal then
    SetEntityHealth(ped, math.max(Config.Downed and Config.Downed.ReviveHealth or 150, 150))
  end
  sendUiUpdate()
end

local function beginDowned(reason)
  if warzoneDeathBlocked() then return end
  if isDowned or not (Config.Downed and Config.Downed.Enabled ~= false) then return end

  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)

  disableSpawnmanagerAutoRespawn()

  if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    Wait(50)
    ped = PlayerPedId()
  end

  isDowned = true
  downedStartedAt = now()
  downedCanRespawnAt = now() + ((Config.ReviveTime or 60) * 1000)
  downedBleedoutAt = now() + ((Config.BleedoutTime or 300) * 1000)
  respawnHoldStart = 0

  ClearPedTasksImmediately(ped)
  SetEntityHealth(ped, Config.Downed.HealthOnDown or 110)
  SetPedArmour(ped, 0)
  setDownedInvincible(true)
  SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

  if injuryCount() == 0 then
    local ctx = recentTraumaContext
    if ctx and (now() - (ctx.at or 0)) <= 8000 then
      addWound(ctx.region or 'torso', ctx.kind or DAMAGE_TYPES.IMPACT, ctx.detail or 'Critical trauma', 'Bone ??.', ctx.sev or 35, ctx.bleed or 0.08)
    else
      addWound('torso', DAMAGE_TYPES.IMPACT, 'Critical trauma causing downed state', 'Bone ??.', 35, 0.08)
    end
  end

  notifyDownedLocation()
  sendUiUpdate()
  dprint('Entered downed state:', reason or 'unknown')
end

local function respawnAtHospital(label)
  local ped = PlayerPedId()
  local loc = nearestRespawnLocation()
  DoScreenFadeOut(500)
  while not IsScreenFadedOut() do Wait(10) end
  Wait((Config.Hospital and Config.Hospital.RespawnSeconds or 3) * 1000)
  if loc then
    SetEntityCoordsNoOffset(ped, loc.coords.x, loc.coords.y, loc.coords.z, false, false, false)
    SetEntityHeading(ped, loc.heading or 0.0)
  end
  injuries = {}
  pushSync()
  reviveFromDowned(false)
  SetEntityHealth(ped, GetEntityMaxHealth(ped))
  DoScreenFadeIn(800)
  notify(label or 'You were treated and released from the hospital.')
  sendMedPrompt(false)
end

local function getNearestHospital(radius)
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local best, bestDist = nil, radius or 3.0
  for _,loc in ipairs(Config.RespawnLocations or {}) do
    local d = #(p - loc.coords)
    if d <= bestDist then
      best = loc
      bestDist = d
    end
  end
  return best, bestDist
end

local function tryBillHospital(kind)
  if not lib or not lib.callback then return true end
  local ok, success, message = pcall(function()
    return lib.callback.await('Az-Death:server:billHospital', false, kind)
  end)
  if not ok then return true end
  if success == false then
    if message then notify(message) end
    return false
  end
  if type(message) == 'string' and message ~= '' then notify(message) end
  return true
end

local function performHospitalTreatment(kind)
  local loc = nearestRespawnLocation()
  local ped = PlayerPedId()
  local secs = (Config.Hospital and Config.Hospital.TreatmentSeconds or 3)
  local label = (kind == 'checkin') and 'Hospital Check-In' or 'Hospital Visit'
  sendMedPrompt(false)
  screenTransitionWait(secs)
  if loc then
    SetEntityCoordsNoOffset(ped, loc.coords.x, loc.coords.y, loc.coords.z, false, false, false)
    SetEntityHeading(ped, loc.heading or 0.0)
  end
  injuries = {}
  pushSync()
  reviveFromDowned(false)
  SetEntityHealth(ped, GetEntityMaxHealth(ped))
  ClearPedTasksImmediately(ped)
  DoScreenFadeIn(800)
  notify(label .. ' complete. You were treated successfully.')
end

local function attemptHospitalUse(kind)
  if not tryBillHospital(kind) then return end
  performHospitalTreatment(kind)
end

local function isMedJobLocal()
  if GetResourceState('Az-Framework') ~= 'started' then return false end
  local attempts = {
    function() return exports['Az-Framework']:getPlayerJob() end,
    function() return exports['Az-Framework']:getPlayerJob(PlayerId()) end,
    function() return exports['Az-Framework']:getPlayerJob(GetPlayerServerId(PlayerId())) end,
  }
  for _,fn in ipairs(attempts) do
    local ok, job = pcall(fn)
    if ok then
      for _,department in pairs(Config.MedDept or Config.EMSJobs or {}) do
        if job == department then return true end
      end
    end
  end
  return false
end

local function tryRegisterOxTarget()
  if registeredOxTarget or GetResourceState('ox_target') ~= 'started' then return end
  local ok = pcall(function()
    exports.ox_target:addGlobalPlayer({
      {
        name = 'azdeath_takehospital',
        icon = 'fa-solid fa-truck-medical',
        label = 'Take To Hospital',
        distance = 2.0,
        canInteract = function(entity, distance, coords, name)
          if not isMedJobLocal() then return false end
          if distance and distance > 2.0 then return false end
          return IsPedFatallyInjured(entity) or IsEntityDead(entity) or IsPedRagdoll(entity)
        end,
        onSelect = function(data)
          local entity = data.entity
          if not entity or entity == 0 then return end
          local player = NetworkGetPlayerIndexFromPed(entity)
          if player and player ~= -1 then
            TriggerServerEvent('Az-Death:server:transportNearestPlayer', GetPlayerServerId(player))
          end
        end,
      }
    })
  end)
  registeredOxTarget = ok
end

local function classifyAndApply(ped, weaponHash, damage, isMeleeFlag, impactExtra)
  local region, bone = regionFromLastBone(ped)
  local boneName = ("Bone %s"):format(tostring(bone or "??"))

  local sev, bleedAdd, typ, details

  if ASPHYXIA_WEAPON[weaponHash] then
    typ = DAMAGE_TYPES.ASPHYXIA
    details = "Asphyxia / drowning"
    sev = clamp(damage * 1.2, 8, 45)
    bleedAdd = 0.00
    setRecentTrauma(typ, 'head', details, sev, bleedAdd)
    addWound('head', typ, details, boneName, sev, bleedAdd)
    return
  end

  if EXPLOSIVE_WEAPON[weaponHash] then
    typ = DAMAGE_TYPES.EXPLOSION
    details = "Explosion trauma + burns"
    sev = clamp(damage * 1.4, 15, 85)
    bleedAdd = clamp(0.10 + (damage * 0.01), 0.10, 0.60)
    setRecentTrauma(typ, 'torso', details, sev, bleedAdd)
    addWound('torso', typ, details, boneName, sev, bleedAdd)
    return
  end

  if VEHICLE_WEAPON[weaponHash] then
    typ = DAMAGE_TYPES.IMPACT
    local mph = impactExtra and impactExtra.mph or 0.0
    details = ("Vehicle impact (%.0f mph)"):format(mph)
    sev = clamp((damage * 1.1) + (mph * 0.35), 10, 80)
    bleedAdd = clamp(0.05 + (mph * 0.01), 0.05, 0.40)
    if sev >= 35 then typ = DAMAGE_TYPES.FRACTURE end
    setRecentTrauma(typ, region, details, sev, bleedAdd)
    addWound(region, typ, details, boneName, sev, bleedAdd)
    return
  end

  if weaponHash == `WEAPON_FALL` then
    typ = DAMAGE_TYPES.FRACTURE
    details = "Fall injury / possible fracture"
    sev = clamp(damage * 1.0, 8, 60)
    bleedAdd = clamp(0.02 + (damage * 0.01), 0.02, 0.30)
    setRecentTrauma(typ, region, details, sev, bleedAdd)
    addWound(region, typ, details, boneName, sev, bleedAdd)
    return
  end

  if isMeleeFlag or isMeleeWeapon(weaponHash) then
    typ = DAMAGE_TYPES.BRUISE
    details = "Blunt trauma / bruising"
    sev = clamp(damage * 0.75, 2, 30)
    bleedAdd = clamp(0.03 + (damage * 0.002), 0.03, 0.18)
    if sev >= 25 then typ = DAMAGE_TYPES.FRACTURE end
    setRecentTrauma(typ, region, details, sev, bleedAdd)
    addWound(region, typ, details, boneName, sev, bleedAdd)
    return
  end

  if IsEntityOnFire(ped) then
    typ = DAMAGE_TYPES.BURN
    details = "Burns"
    sev = clamp(damage * 0.9, 6, 55)
    bleedAdd = 0.02
    setRecentTrauma(typ, 'torso', details, sev, bleedAdd)
    addWound('torso', typ, details, boneName, sev, bleedAdd)
    return
  end

  if weaponHash ~= 0 and weaponHash ~= nil then
    typ = DAMAGE_TYPES.GSW
    details = "Gunshot wound"
    sev = clamp(damage * 1.1, 8, 70)
    bleedAdd = clamp(0.12 + (damage * 0.004), 0.12, 0.70)

    if region == 'head' then
      details = "Gunshot wound (critical risk)"
      sev = sev * 1.35
      bleedAdd = bleedAdd * 1.20
    end

    setRecentTrauma(typ, region, details, sev, bleedAdd)
    addWound(region, typ, details, boneName, sev, bleedAdd)
    return
  end

  typ = DAMAGE_TYPES.LACERATE
  details = "Unknown trauma"
  sev = clamp(damage * 0.8, 4, 45)
  bleedAdd = 0.08
  setRecentTrauma(typ, region, details, sev, bleedAdd)
  addWound(region, typ, details, boneName, sev, bleedAdd)
end

AddEventHandler("gameEventTriggered", function(eventName, args)
  if warzoneDeathBlocked() then return end
  if eventName ~= "CEventNetworkEntityDamage" then return end

  local victim     = args[1]
  local attacker   = args[2]
  local weaponHash = args[7]
  local isMelee    = args[12]
  local damage     = args[13] or 0

  local ped = PlayerPedId()
  if victim ~= ped then return end
  if IsEntityDead(ped) then return end
  if damage <= 0 then return end

  local extra = nil
  if VEHICLE_WEAPON[weaponHash] and attacker and DoesEntityExist(attacker) and IsEntityAVehicle(attacker) then
    extra = { mph = GetEntitySpeed(attacker) * 2.236936 }
  end

  classifyAndApply(ped, weaponHash, damage, isMelee, extra)
end)

local lastHp, lastArmor = 0, 0
local lastImpactAt = 0

CreateThread(function()
  Wait(500)
  local ped = PlayerPedId()
  if ped ~= 0 and DoesEntityExist(ped) then
    lastHp = GetEntityHealth(ped)
    lastArmor = GetPedArmour(ped)
  end

  while Config.VehicleImpact and Config.VehicleImpact.Enabled do
    Wait(Config.VehicleImpact.HealthDropPollMs or 150)

    if warzoneDeathBlocked() then
      ped = PlayerPedId()
      if ped ~= 0 and DoesEntityExist(ped) then
        lastHp = GetEntityHealth(ped)
        lastArmor = GetPedArmour(ped)
      end
    else
      ped = PlayerPedId()
      if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
      local hp = GetEntityHealth(ped)
      local armor = GetPedArmour(ped)

      local delta = (lastHp - hp) + (lastArmor - armor)
      lastHp, lastArmor = hp, armor

      if delta >= (Config.VehicleImpact.MinDeltaToConsider or 2) and (now() - lastImpactAt) >= (Config.VehicleImpact.CooldownMs or 750) then
        local collided = HasEntityCollidedWithAnything(ped)
        local ragdoll  = IsPedRagdoll(ped) or IsPedGettingUp(ped)
        if collided or ragdoll then
          lastImpactAt = now()

          local speedMph = GetEntitySpeed(ped) * 2.236936
          local typ = DAMAGE_TYPES.IMPACT
          if delta >= 8 or speedMph >= 22 then typ = DAMAGE_TYPES.FRACTURE end

          local region, bone = regionFromLastBone(ped)
          local boneName = ("Bone %s"):format(tostring(bone or "??"))
          local details = ("%s (Δ%.0f hp, %.0f mph)"):format(typ, delta, speedMph)

          local sev = clamp((delta * 2.2) + (speedMph * 0.35), 6, 80)
          local bleedAdd = clamp(0.02 + (delta * 0.01), 0.02, 0.35)

          if region == "head" then
            sev = sev * 1.20
            details = details .. " (head impact)"
          end

          setRecentTrauma(typ, region, details, sev, bleedAdd)
          addWound(region, typ, details, boneName, sev, bleedAdd)
          dprint("IMPACT fallback ->", REGION_TO_ZONE[region] or region, details)
        end
      end
    end
    end
  end
end)

local wasAirborne = false
local airbornePeakHeight = 0.0
local airbornePeakSpeed = 0.0
local lastLandingAt = 0

CreateThread(function()
  while true do
    Wait(75)
    if warzoneDeathBlocked() then
      wasAirborne = false
      airbornePeakHeight = 0.0
      airbornePeakSpeed = 0.0
    else
      local ped = PlayerPedId()

    if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) and not isDowned then
      if IsPedInAnyVehicle(ped, false) or IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) or IsPedInParachuteFreeFall(ped) or IsPedRagdoll(ped) then
        wasAirborne = IsEntityInAir(ped) or IsPedFalling(ped)
      else
        local inAir = IsEntityInAir(ped) or IsPedFalling(ped)
        local h = GetEntityHeightAboveGround(ped)
        local vel = GetEntityVelocity(ped)
        local vertical = math.abs(vel.z or 0.0) * 2.236936

        if inAir then
          wasAirborne = true
          if h > airbornePeakHeight then airbornePeakHeight = h end
          if vertical > airbornePeakSpeed then airbornePeakSpeed = vertical end
        elseif wasAirborne then
          wasAirborne = false
          if (now() - lastLandingAt) >= 1500 then
            lastLandingAt = now()
            local hp = GetEntityHealth(ped)
            local hardEnough = airbornePeakHeight >= 4.0 or airbornePeakSpeed >= 18.0 or hp <= 120
            if hardEnough then
              local region = (airbornePeakHeight >= 10.0) and ((math.random(1,2) == 1) and 'lleg' or 'rleg') or 'torso'
              local sev = clamp((airbornePeakHeight * 3.0) + (airbornePeakSpeed * 0.8), 12, 85)
              local bleed = clamp(0.02 + (airbornePeakHeight * 0.01), 0.02, 0.30)
              local details = ('Hard landing / fall impact (%.1fm drop, %.0f mph vertical)'):format(airbornePeakHeight, airbornePeakSpeed)
              setRecentTrauma(DAMAGE_TYPES.FRACTURE, region, details, sev, bleed)
              addWound(region, DAMAGE_TYPES.FRACTURE, details, 'Bone 14201', sev, bleed)
            end
          end
          airbornePeakHeight = 0.0
          airbornePeakSpeed = 0.0
        end
      end
    end
    end
  end
end)

local hasClipset = false

local function ensureClipset()
  if not Config.UseInjuredClipset then return end
  if hasClipset then return end
  local cs = Config.InjuredClipset or "move_m@injured"
  RequestAnimSet(cs)
  local t = 0
  while not HasAnimSetLoaded(cs) and t < 100 do
    Wait(20)
    t = t + 1
  end
  hasClipset = HasAnimSetLoaded(cs)
end

local function clearClipset(ped)
  ResetPedMovementClipset(ped, 0.2)
  ResetPedStrafeClipset(ped)
end

local lastBlackout = 0
local lastStumble = 0

CreateThread(function()
  while true do
    Wait(0)

    if warzoneDeathBlocked() then
      ClearTimecycleModifier()
      local wzPed = PlayerPedId()
      if wzPed ~= 0 and DoesEntityExist(wzPed) then clearClipset(wzPed) end
      Wait(500)
    else
      local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
      Wait(250)
    else
      local dead = IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
      if dead then
        Wait(200)
        sendUiUpdate()
      else
        local head  = maxSeverityByRegions({ "head" })
        local torso = maxSeverityByRegions({ "torso" })
        local leg   = math.max(maxSeverityByRegions({ "lleg" }), maxSeverityByRegions({ "rleg" }))
        local arm   = math.max(maxSeverityByRegions({ "larm" }), maxSeverityByRegions({ "rarm" }))

        local anyInjured = (head + torso + leg + arm) > 0

        if anyInjured then
          if Config.UseInjuredClipset and leg >= (Config.Thresholds.Limp or 25) then
            ensureClipset()
            if hasClipset then
              SetPedMovementClipset(ped, Config.InjuredClipset or "move_m@injured", 0.2)
            end
          else
            clearClipset(ped)
          end

          if leg >= (Config.Thresholds.NoSprint or 55) or torso >= (Config.Thresholds.TorsoNoSprint or 70) then
            DisableControlAction(0, 21, true)
          end
          if leg >= (Config.Thresholds.NoJump or 70) then
            DisableControlAction(0, 22, true)
          end
        else
          clearClipset(ped)
        end

        if arm >= (Config.Thresholds.AimPenalty or 40) then
          ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", clamp(arm / 250.0, 0.05, 0.30))
          if arm >= (Config.Thresholds.NoAim or 80) then
            DisableControlAction(0, 25, true)
          end
        end

        if head >= (Config.Thresholds.HeadBlur or 30) then
          SetTimecycleModifier("tunnel")
          SetTimecycleModifierStrength(clamp(head / 120.0, 0.15, 0.55))
        else
          ClearTimecycleModifier()
        end

        if Config.Blackout and Config.Blackout.Enabled and head >= (Config.Thresholds.HeadBlackout or 75) then
          if (now() - lastBlackout) > (Config.Blackout.CooldownMs or 12000) then
            lastBlackout = now()
            DoScreenFadeOut(Config.Blackout.FadeOutMs or 400)
            Wait(450)
            if DoesEntityExist(ped) then
              SetPedToRagdoll(ped, Config.Blackout.RagMs or 1600, Config.Blackout.RagMs or 1600, 0, true, true, false)
            end
            Wait(900)
            DoScreenFadeIn(Config.Blackout.FadeInMs or 600)
          end
        end

        if Config.Stumble and Config.Stumble.Enabled then
          local overall = math.max(head, torso, leg, arm)
          if overall >= 45 and (now() - lastStumble) > (Config.Stumble.CooldownMs or 8000) then
            local pct = clamp((overall - 45) / 55.0, 0.0, 1.0)
            local base = (Config.Stumble.BaseChance or 0.02)
            local maxc = (Config.Stumble.MaxChance or 0.12)
            local chance = base + pct * (maxc - base)
            if math.random() < chance then
              lastStumble = now()
              SetPedToRagdoll(ped, 900, 900, 0, true, true, false)
            end
          end
        end
      end
    end
    end
  end
end)

local lastBleedTick = 0
CreateThread(function()
  while true do
    Wait(200)

    if warzoneDeathBlocked() then
      lastBleedTick = now()
      clearWarzoneDeathHud()
    else
      local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
      local b = totalBleed()
      if b > 0.0 and (now() - lastBleedTick) >= (Config.BleedTickMs or 1000) then
        lastBleedTick = now()

        local hp = GetEntityHealth(ped)
        local maxDps = Config.BleedHpPerSecondMax or 6
        local dmg = math.floor(clamp((b / (Config.MaxBleed or 8.0)) * maxDps, Config.BleedHpPerSecondMin or 0, maxDps))

        if dmg > 0 and hp > 105 then
          SetEntityHealth(ped, hp - dmg)
          ApplyPedBloodDamage(ped, 0.0, 0.0, 0.0, 1.0)
        end

        sendUiUpdate()
      end
    end
    end
  end
end)

local function togglePinned(label)
  pinned = not pinned
  notify(pinned and "Injury overlay pinned." or "Injury overlay unpinned.")
  dprint(label or "toggle", "pinned:", pinned)
  sendUiUpdate()
end

RegisterNetEvent("Az-Death:ui:togglePinned", function()
  togglePinned("server")
end)

local function bindCommands()
  RegisterCommand(Config.CommandInjuries or "injuries", function()
    togglePinned("/injuries")
  end, false)

  RegisterCommand(Config.CommandBackup or "azinjuries", function()
    togglePinned("/azinjuries")
  end, false)

  RegisterCommand(Config.CommandClear or "injuriesclear", function()
    injuries = {}
    pushSync()
    sendUiUpdate()
    notify("Injuries cleared.")
  end, false)
end

bindCommands()

CreateThread(function()
  for _,ms in ipairs(Config.RebindScheduleMs or {0,250,1000,3000,8000,15000}) do
    Wait(ms)
    bindCommands()
    dprint("Rebound commands after", ms, "ms")
  end
end)

CreateThread(function()
  while (Config.RebindEveryMs or 0) > 0 do
    Wait(Config.RebindEveryMs)
    bindCommands()
  end
end)

RegisterNetEvent("Az-Death:injury:set", function(state)
  if type(state) ~= "table" then return end
  injuries = state
  sendUiUpdate()
end)

RegisterNetEvent('ND_Death:CPR', function()
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  reviveFromDowned(true)
  SetEntityHealth(ped, math.max(Config.Downed and Config.Downed.ReviveHealth or 150, 150))
  notify('You were revived by EMS.')
end)

RegisterNetEvent('ND_Death:AdminRevivePlayerAtPosition', function()
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  injuries = {}
  pushSync()
  reviveFromDowned(false)
  SetEntityHealth(ped, GetEntityMaxHealth(ped))
  notify('You were revived.')
end)

RegisterNetEvent('startCPRAnimation', function()
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  if requestAnim('mini@cpr@char_a@cpr_str') then
    TaskPlayAnim(ped, 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest', 8.0, -8.0, 5000, 1, 0.0, false, false, false)
  end
end)

RegisterNetEvent('Az-Death:client:transportToHospital', function(reasonLabel)
  respawnAtHospital(reasonLabel or 'You were transported to the hospital.')
end)

CreateThread(function()
  while true do
    Wait(100)
    if warzoneDeathBlocked() then
      if isDowned then reviveFromDowned(false) end
      injuries = {}
      clearWarzoneDeathHud()
      Wait(400)
    else
      local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) then
      if not isDowned then
        sendDownedHud(false, 0, 0, 0, false)
        if (Config.Downed and Config.Downed.Enabled ~= false) and (IsEntityDead(ped) or IsPedFatallyInjured(ped) or GetEntityHealth(ped) <= 101) then
          beginDowned('health/death threshold')
        end
      else
        if Config.Downed and Config.Downed.DisableControls ~= false then
          DisableAllControlActions(0)
          EnableControlAction(0, 245, true)
          EnableControlAction(0, 249, true)
          EnableControlAction(0, 46, true)
          EnableControlAction(0, Config.EarlyRespawnKey or 38, true)
        end

        if Config.Downed and Config.Downed.PlayLoopAnim ~= false and not IsEntityPlayingAnim(ped, Config.Downed.AnimDict or 'dead', Config.Downed.AnimName or 'dead_a', 3) then
          if requestAnim(Config.Downed.AnimDict or 'dead') then
            TaskPlayAnim(ped, Config.Downed.AnimDict or 'dead', Config.Downed.AnimName or 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
          end
        end

        local nowMs = now()
        local reviveLeft = math.max(0, math.ceil((downedCanRespawnAt - nowMs) / 1000))
        local bleedoutLeft = math.max(0, math.ceil((downedBleedoutAt - nowMs) / 1000))

        local holdPercent = 0
        local canRespawn = nowMs >= downedCanRespawnAt
        if canRespawn then
          if IsControlPressed(0, Config.EarlyRespawnKey or 38) then
            if respawnHoldStart == 0 then respawnHoldStart = nowMs end
            local held = nowMs - respawnHoldStart
            local needed = Config.EarlyRespawnHoldMs or 2500
            holdPercent = math.min(100, math.floor((held / needed) * 100))
            if Config.EnableNui == false then
              drawTxt(0.5, 0.94, 0.33, ('Respawning... %d%%'):format(holdPercent), true)
            end
            if held >= needed then
              respawnAtHospital('You checked into the hospital and were stabilized.')
            end
          else
            respawnHoldStart = 0
          end
        end

        if Config.EnableNui == false then
          drawTxt(0.5, 0.88, 0.40, ('~r~DOWNED~s~  |  EMS/CPR available  |  Respawn in %ss'):format(reviveLeft), true)
          drawTxt(0.5, 0.91, 0.33, ('Bleedout: %ss  |  Hold [E] to respawn at hospital'):format(bleedoutLeft), true)
        elseif (nowMs - lastDownedHud) >= 100 then
          lastDownedHud = nowMs
          sendDownedHud(true, reviveLeft, bleedoutLeft, holdPercent, canRespawn)
        end

        if nowMs >= downedBleedoutAt then
          respawnAtHospital('You bled out and were transported to the hospital.')
        end
      end
    end
    end
  end
end)

CreateThread(function()
  while true do
    Wait(150)
    if warzoneDeathBlocked() then
      hospitalPromptActive = false
      emsPromptActive = false
      sendMedPrompt(false)
      Wait(500)
    else
      tryRegisterOxTarget()

    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) then
      local pcoords = GetEntityCoords(ped)

      local hospital, dist = getNearestHospital(2.25)
      if hospital and not isDowned then
        hospitalPromptActive = true
        sendMedPrompt(true, 'Press E to check in / heal')
        if IsControlJustReleased(0, 38) then
          attemptHospitalUse('visit')
        end
      else
        if hospitalPromptActive then
          sendMedPrompt(false)
          hospitalPromptActive = false
        end
      end

      if GetResourceState('ox_target') ~= 'started' and isMedJobLocal() then
        local near = getPlayersNear(pcoords, 2.0)
        local target = nil
        for _,entry in ipairs(near) do
          if entry.ped ~= ped and (IsPedFatallyInjured(entry.ped) or IsEntityDead(entry.ped) or IsPedRagdoll(entry.ped)) then
            target = entry
            break
          end
        end
        if target then
          emsPromptActive = true
          sendMedPrompt(true, 'Press E to take patient to hospital')
          if IsControlJustReleased(0, 38) then
            TriggerServerEvent('Az-Death:server:transportNearestPlayer', target.serverId)
          end
        else
          if emsPromptActive and not hospitalPromptActive then
            sendMedPrompt(false)
          end
          emsPromptActive = false
        end
      else
        emsPromptActive = false
      end
    end
    end
  end
end)


RegisterNetEvent('Az-Death:injury:pause', function(state)
  injuryPauseState = state == true
  if injuryPauseState then
    injuries = {}
    if isDowned then reviveFromDowned(false) end
    clearWarzoneDeathHud()
  end
end)

RegisterNetEvent('Az-Death:injury:suppress', function(ms, reason)
  injuryPauseState = true
  if isDowned then reviveFromDowned(false) end
  injuries = {}
  clearWarzoneDeathHud()
  local duration = tonumber(ms) or 2500
  SetTimeout(duration, function()
    local st = LocalPlayer and LocalPlayer.state
    if not (st and (st.in5MWarzone == true or st.fiveMWarzone == true or st.azWarzone == true or st.azDeathSuppressed == true)) then
      injuryPauseState = false
    end
  end)
end)

exports('setInjuryPaused', function(state)
  injuryPauseState = state == true
  if injuryPauseState then clearWarzoneDeathHud() end
end)

exports('suppressInjuries', function(ms, reason)
  TriggerEvent('Az-Death:injury:suppress', ms or 2500, reason or 'export suppress')
end)

CreateThread(function()
  Wait(800)
  sendUiUpdate()
end)
