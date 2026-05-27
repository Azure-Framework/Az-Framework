local Config = (Config and Config.Death) or {}
if Config.Enabled == false then return end

local RES = GetCurrentResourceName()

Config = Config or {}
Config.Debug = Config.Debug ~= false

local function dprint(...)
  if not Config.Debug then return end
  local t = {}
  for i=1,select("#", ...) do t[#t+1] = tostring(select(i, ...)) end
  print(("^3[%s]^7 %s"):format(RES, table.concat(t, " ")))
end

local function notify(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, false)
end

local function drawHelp(msg)
  BeginTextCommandDisplayHelp("STRING")
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandDisplayHelp(0, false, true, -1)
end

local function loadModel(hash)
  if not hash or hash == 0 then return false end
  if not IsModelInCdimage(hash) then return false end
  RequestModel(hash)
  local t = 0
  while not HasModelLoaded(hash) and t < 200 do
    Wait(25)
    t = t + 1
  end
  return HasModelLoaded(hash)
end

local function randFloat(a, b)
  return a + (math.random() * (b - a))
end

local function clamp(v,a,b)
  if v < a then return a end
  if v > b then return b end
  return v
end

Config.AIEMSCommand = Config.AIEMSCommand or "aiems"
Config.EMSCommand   = Config.EMSCommand   or "ems"

Config.AIEMS = Config.AIEMS or {}
Config.AIEMS.AmbulanceModel = Config.AIEMS.AmbulanceModel or `ambulance`
Config.AIEMS.MedicModel     = Config.AIEMS.MedicModel     or `s_m_m_paramedic_01`

Config.AIEMS.DriveSpeed = Config.AIEMS.DriveSpeed or 24.0
Config.AIEMS.DriveFlags = Config.AIEMS.DriveFlags or 786603

Config.AIEMS.MedicApproachDist = Config.AIEMS.MedicApproachDist or 2.2
Config.AIEMS.TimeoutMs         = Config.AIEMS.TimeoutMs or 90000
Config.AIEMS.TreatTimeMs       = Config.AIEMS.TreatTimeMs or 9000
Config.AIEMS.FadeOutMs         = Config.AIEMS.FadeOutMs or 650
Config.AIEMS.FadeInMs          = Config.AIEMS.FadeInMs or 900

Config.AIEMS.SpawnMinDist = Config.AIEMS.SpawnMinDist or 180.0
Config.AIEMS.SpawnMaxDist = Config.AIEMS.SpawnMaxDist or 420.0
Config.AIEMS.SpawnTries   = Config.AIEMS.SpawnTries   or 30

Config.AIEMS.Eligibility = Config.AIEMS.Eligibility or {
  HealthThreshold = 175,
  RecentDamageMs  = 45000,
  AllowWhenDowned = true,
  AlwaysAllowIfUiShowsInjury = true,
}

Config.AIEMS.DeathChance = Config.AIEMS.DeathChance or {
  Base = 0.03,
  PerBleedLevel = 0.12,
  GswTorso = 0.18,
  GswHead  = 0.45,
  PerWound = 0.02,
  Cap = 0.85,
}

Config.AIEMS.Hospitals = Config.AIEMS.Hospitals or {
  {
    name = "Pillbox Medical",
    checkIn = vector3(307.74, -595.06, 43.28),
    respawn = vector4(329.28, -575.33, 43.28, 160.0),
    radius = 2.2
  },
  {
    name = "Sandy Shores Medical",
    checkIn = vector3(1839.67, 3673.88, 34.28),
    respawn = vector4(1841.81, 3668.18, 34.28, 30.0),
    radius = 2.2
  },
  {
    name = "Paleto Medical",
    checkIn = vector3(-247.25, 6331.15, 32.43),
    respawn = vector4(-252.52, 6334.64, 32.43, 225.0),
    radius = 2.2
  },
}

local function getInjuryUi()

  local ok, data = pcall(function()
    return exports[RES]:getInjuriesUi()
  end)
  if not ok or type(data) ~= "table" then return nil end
  return data
end

local function parseUiInjurySignals()

  local data = getInjuryUi()
  if not data then return false, 0, 0, false, false end

  local injuries = (type(data.injuries) == "table") and data.injuries or {}
  local bleedLevel = 0
  if type(data.bleeding) == "table" then bleedLevel = tonumber(data.bleeding.level or 0) or 0 end

  local woundCount = 0
  local gswTorso, gswHead = false, false

  for _,entry in ipairs(injuries) do
    local zone = tostring(entry.zone or "")
    local wounds = (type(entry.wounds) == "table") and entry.wounds or {}
    for _,w in ipairs(wounds) do
      woundCount = t + 1
      local typ = tostring(w.type or "")
      if typ == "GSW" then
        if zone == "Head" then gswHead = true end
        if zone == "Torso" then gswTorso = true end
      end
    end
  end

  local hasUiInjury = (#injuries > 0) or (bleedLevel > 0) or (woundCount > 0)
  return hasUiInjury, bleedLevel, woundCount, gswTorso, gswHead
end

local function computeDeathChance()
  local hasUiInjury, bleedLevel, woundCount, gswTorso, gswHead = parseUiInjurySignals()
  if not hasUiInjury then return 0.0 end

  local dc = Config.AIEMS.DeathChance
  local c = dc.Base
  c = c + (bleedLevel * dc.PerBleedLevel)
  c = c + (woundCount * dc.PerWound)
  if gswTorso then c = c + dc.GswTorso end
  if gswHead  then c = c + dc.GswHead  end
  c = clamp(c, 0.0, dc.Cap)
  return c
end

local lastDamagedAt = 0

CreateThread(function()
  while true do
    Wait(active and 250 or 500)
    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) then
      if HasEntityBeenDamagedByAnyPed(ped) or HasEntityBeenDamagedByAnyVehicle(ped) or HasEntityBeenDamagedByAnyObject(ped) then
        lastDamagedAt = GetGameTimer()
        ClearEntityLastDamageEntity(ped)
        ClearEntityLastDamageEntity(ped)
      end
    end
  end
end)

local function canCallAiEms()
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then
    return false, "no_ped"
  end

  local dead = IsPedDeadOrDying(ped, true) or IsEntityDead(ped)
  if dead and Config.AIEMS.Eligibility.AllowWhenDowned then
    return true, "downed"
  end

  local hp = GetEntityHealth(ped) or 200
  if hp <= (Config.AIEMS.Eligibility.HealthThreshold or 175) then
    return true, ("low_hp(%d)"):format(hp)
  end

  local recentlyDamaged = (lastDamagedAt > 0) and ((GetGameTimer() - lastDamagedAt) <= (Config.AIEMS.Eligibility.RecentDamageMs or 45000))
  if recentlyDamaged then
    return true, "recent_damage"
  end

  local hasUiInjury, bleedLevel, woundCount, gswTorso, gswHead = parseUiInjurySignals()
  if Config.AIEMS.Eligibility.AlwaysAllowIfUiShowsInjury and hasUiInjury then
    local why = ("ui_injury(bleed=%d,wounds=%d,gswT=%s,gswH=%s)"):format(
      bleedLevel, woundCount, tostring(gswTorso), tostring(gswHead)
    )
    return true, why
  end

  return false, ("stable(hp=%d, ui=%s)"):format(hp, tostring(hasUiInjury))
end

local function healPlayer()
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  SetEntityHealth(ped, GetEntityMaxHealth(ped))
  SetPedArmour(ped, 0)
  ClearPedBloodDamage(ped)
  ClearPedTasksImmediately(ped)
end

local function clearInjuriesBestEffort()
  TriggerEvent("Az-Death:injury:set", {})
  TriggerServerEvent("Az-Death:injury:sync", {})
end

local function nearestHospital()
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local best, bestDist = nil, 1e9
  for _,h in ipairs(Config.AIEMS.Hospitals) do
    local d = #(p - h.checkIn)
    if d < bestDist then bestDist = d; best = h end
  end
  return best
end

local function requestHospitalBilling(kind)
  if lib and lib.callback and lib.callback.await then
    local ok, success, msg = pcall(function()
      return lib.callback.await('Az-Death:server:billHospital', false, kind or 'checkin')
    end)
    if ok then return success, msg end
  end
  return true, nil
end

local function transportToHospital(label, billKind)
  local ped = PlayerPedId()
  local h = nearestHospital()
  local ok, msg = requestHospitalBilling(billKind or 'checkin')
  if not ok then
    if msg and msg ~= '' then notify(msg) end
    return false
  end

  local seconds = (Config.Hospital and Config.Hospital.TreatmentSeconds) or 3
  if lib and lib.progressCircle then
    local finished = lib.progressCircle({
      duration = seconds * 1000,
      position = 'bottom',
      label = ('Receiving treatment%s'):format(label and (' - ' .. label) or ''),
      useWhileDead = true,
      canCancel = false,
      disable = { move = true, car = true, combat = true }
    })
    if not finished then return false end
  else
    Wait(seconds * 1000)
  end

  DoScreenFadeOut(Config.AIEMS.FadeOutMs)
  while not IsScreenFadedOut() do Wait(10) end

  if h and h.respawn then
    SetEntityCoordsNoOffset(ped, h.respawn.x, h.respawn.y, h.respawn.z, false, false, false)
    SetEntityHeading(ped, h.respawn.w or 0.0)
  end

  Wait(250)
  healPlayer()
  clearInjuriesBestEffort()

  TriggerEvent('ND_Death:AdminRevivePlayerAtPosition')

  DoScreenFadeIn(Config.AIEMS.FadeInMs)
  notify(("Transported to hospital%s."):format(label and (" ("..label..")") or ""))
  return true
end

local function isWaterAt(pos)

  local waterZ = 0.0
  return GetWaterHeight(pos.x, pos.y, pos.z, waterZ) == true
end

local function snapToRoadNode(x, y, z)
  local found, outPos, outHeading = GetClosestVehicleNodeWithHeading(x, y, z, 1, 6.0, 0)
  if not found then return nil end

  local p = vector3(outPos.x, outPos.y, outPos.z)
  if not IsPointOnRoad(p.x, p.y, p.z, 0) then return nil end
  if isWaterAt(p) then return nil end

  local ok, groundZ = GetGroundZFor_3dCoord(p.x, p.y, p.z + 50.0, false)
  if ok then p = vector3(p.x, p.y, groundZ + 0.05) end

  return p, outHeading
end

local function findSpawnFarOnRoad(pCoords)
  local minD  = Config.AIEMS.SpawnMinDist or 180.0
  local maxD  = Config.AIEMS.SpawnMaxDist or 420.0
  local tries = Config.AIEMS.SpawnTries or 30

  for _ = 1, tries do
    local ang  = randFloat(0.0, math.pi * 2.0)
    local dist = randFloat(minD, maxD)

    local tx = pCoords.x + (math.cos(ang) * dist)
    local ty = pCoords.y + (math.sin(ang) * dist)
    local tz = pCoords.z + 5.0

    local snapped, heading = snapToRoadNode(tx, ty, tz)
    if snapped then
      local d = #(snapped - pCoords)
      if d >= (minD - 10.0) then
        return snapped, heading
      end
    end
  end

  local fallback = pCoords + vector3(-minD, 0.0, 0.0)
  local snapped, heading = snapToRoadNode(fallback.x, fallback.y, fallback.z)
  if snapped then return snapped, heading end

  local found, outPos, outHeading = GetClosestVehicleNodeWithHeading(pCoords.x, pCoords.y, pCoords.z, 1, 6.0, 0)
  if found then
    return vector3(outPos.x, outPos.y, outPos.z), outHeading
  end

  return (pCoords + vector3(-30.0, 0.0, 0.0)), 0.0
end

local active = false
local ambVeh, medicPed, ambBlip, medicBlip

local function cleanup()
  if DoesBlipExist(ambBlip) then RemoveBlip(ambBlip) end
  if DoesBlipExist(medicBlip) then RemoveBlip(medicBlip) end
  ambBlip, medicBlip = nil, nil

  if medicPed and DoesEntityExist(medicPed) then DeleteEntity(medicPed) end
  medicPed = nil

  if ambVeh and DoesEntityExist(ambVeh) then DeleteEntity(ambVeh) end
  ambVeh = nil
end

local function callAI()
  if active then
    notify("AI EMS already dispatched.")
    return
  end

  local ok, why = canCallAiEms()
  dprint("AI EMS eligibility:", ok, why)

  if not ok then
    notify("You are not injured enough to call AI EMS.")
    return
  end

  active = true
  notify("AI EMS has been dispatched.")

  local ped = PlayerPedId()
  local pCoords = GetEntityCoords(ped)

  local spawnPos, spawnHeading = findSpawnFarOnRoad(pCoords)
  dprint(("SpawnPos: %.2f %.2f %.2f heading %.1f"):format(spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading))

  if not loadModel(Config.AIEMS.AmbulanceModel) or not loadModel(Config.AIEMS.MedicModel) then
    notify("AI EMS failed to load models.")
    active = false
    return
  end

  ambVeh = CreateVehicle(Config.AIEMS.AmbulanceModel, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, false)
  SetEntityAsMissionEntity(ambVeh, true, true)
  SetVehicleOnGroundProperly(ambVeh)
  SetVehicleDoorsLocked(ambVeh, 1)
  SetVehicleSiren(ambVeh, true)
  SetVehicleEngineOn(ambVeh, true, true, false)

  medicPed = CreatePedInsideVehicle(ambVeh, 26, Config.AIEMS.MedicModel, -1, true, false)
  SetBlockingOfNonTemporaryEvents(medicPed, true)
  SetPedFleeAttributes(medicPed, 0, false)
  SetPedCanBeDraggedOut(medicPed, false)

  ambBlip = AddBlipForEntity(ambVeh)
  SetBlipSprite(ambBlip, 56)
  SetBlipScale(ambBlip, 0.85)
  SetBlipColour(ambBlip, 1)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentString("AI Ambulance")
  EndTextCommandSetBlipName(ambBlip)

  medicBlip = AddBlipForEntity(medicPed)
  SetBlipSprite(medicBlip, 153)
  SetBlipScale(medicBlip, 0.75)
  SetBlipColour(medicBlip, 1)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentString("AI Medic")
  EndTextCommandSetBlipName(medicBlip)

  TaskVehicleDriveToCoordLongrange(medicPed, ambVeh, pCoords.x, pCoords.y, pCoords.z, Config.AIEMS.DriveSpeed, Config.AIEMS.DriveFlags, 8.0)

  local startAt = GetGameTimer()
  local arrived = false

  while (GetGameTimer() - startAt) < Config.AIEMS.TimeoutMs do
    Wait(250)
    if not DoesEntityExist(ambVeh) or not DoesEntityExist(medicPed) then break end

    local curP = GetEntityCoords(PlayerPedId())
    local vPos = GetEntityCoords(ambVeh)
    local dist = #(curP - vPos)

    if dist < 12.0 then
      arrived = true
      break
    end
  end

  if not arrived then
    notify("AI EMS could not reach you.")
    cleanup()
    active = false
    return
  end

  TaskVehicleTempAction(medicPed, ambVeh, 27, 2000)
  Wait(800)
  TaskLeaveVehicle(medicPed, ambVeh, 256)
  Wait(1200)

  local tgt = GetEntityCoords(PlayerPedId())
  TaskGoToCoordAnyMeans(medicPed, tgt.x, tgt.y, tgt.z, 1.2, 0, 0, 786603, 0.0)

  local t0 = GetGameTimer()
  while (GetGameTimer() - t0) < 25000 do
    Wait(250)
    if not DoesEntityExist(medicPed) then break end
    tgt = GetEntityCoords(PlayerPedId())
    local mPos = GetEntityCoords(medicPed)
    if #(tgt - mPos) <= (Config.AIEMS.MedicApproachDist + 0.5) then break end
  end

  notify("AI Medic is treating you...")
  ClearPedTasks(medicPed)
  TaskStartScenarioInPlace(medicPed, "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)

  Wait(Config.AIEMS.TreatTimeMs)

  local chance = computeDeathChance()
  local roll = math.random()
  dprint(("Outcome roll=%.3f chance=%.3f"):format(roll, chance))

  cleanup()
  active = false

  if roll < chance then
    notify("The medic couldn't save you...")
    DoScreenFadeOut(Config.AIEMS.FadeOutMs)
    while not IsScreenFadedOut() do Wait(10) end
    SetEntityHealth(PlayerPedId(), 0)
    DoScreenFadeIn(Config.AIEMS.FadeInMs)
  else
    transportToHospital("AI EMS", "checkin")
  end
end

CreateThread(function()
  while true do
    local sleep = 1000
    local ped = PlayerPedId()

    if ped ~= 0 and DoesEntityExist(ped) then
      local p = GetEntityCoords(ped)
      local best, bestDist = nil, 999999
      for _,h in ipairs(Config.AIEMS.Hospitals) do
        local d = #(p - h.checkIn)
        if d < bestDist then bestDist = d; best = h end
      end

      if best and bestDist <= ((best.radius or 2.2) + 12.0) then
        if bestDist > ((best.radius or 2.2) + 6.0) then
          sleep = 250
        else
          sleep = 0
          DrawMarker(1, best.checkIn.x, best.checkIn.y, best.checkIn.z - 1.0,
            0.0,0.0,0.0, 0.0,0.0,0.0,
            1.2,1.2,0.5, 90,170,255,160,
            false,true,2,false,nil,nil,false)

          if bestDist <= (best.radius or 2.2) then
            drawHelp(("Press ~INPUT_CONTEXT~ to check in at ~b~%s~s~"):format(best.name or "Hospital"))
            if IsControlJustReleased(0, 38) then
              notify("Checking in...")
              transportToHospital(best.name, "visit")
              Wait(750)
            end
          end
        end
      end
    end

    Wait(sleep)
  end
end)

local function bind()
  RegisterCommand(Config.AIEMSCommand, function()
    dprint("Command /"..Config.AIEMSCommand.." executed")
    callAI()
  end, false)

  RegisterCommand(Config.EMSCommand, function()
    dprint("Command /"..Config.EMSCommand.." executed")
    callAI()
  end, false)
end

bind()

CreateThread(function()
  local schedule = { 0, 250, 1000, 3000, 8000, 15000 }
  for _,ms in ipairs(schedule) do
    Wait(ms)
    bind()
    dprint("Rebound commands after", ms, "ms")
  end
  while true do
    Wait(30000)
    bind()
  end
end)

AddEventHandler("onClientResourceStart", function(r)
  if r ~= RES then return end
  dprint("aiems.lua loaded ✅ Commands: /"..Config.AIEMSCommand.." and /"..Config.EMSCommand)
  notify("AI EMS ready: /aiems")
end)

print(("^2[%s]^7 aiems.lua loaded ✅ (/aiems /ems)"):format(RES))
