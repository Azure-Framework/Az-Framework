local Config = (Config and Config.Death) or {}
if Config.Enabled == false then return end

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

print(("^2[%s]^7 Injury system loaded ✅"):format(RESOURCE))
_G.AzDeathMainLoaded = true
print(("^2[%s]^7 Death main client loaded"):format(RESOURCE))
TriggerEvent('chat:addMessage', { color = { 255, 150, 80 }, args = { '^3Az-Death', 'Death main client loaded' } })

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

CreateThread(function()
  while true do
    Wait(5000)
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

local SEARCHABLE_WEAPON_NAMES = {
  'WEAPON_BULLPUPSHOTGUN',
  'WEAPON_ASSAULTSMG',
  'WEAPON_PISTOL50',
  'WEAPON_ASSAULTRIFLE',
  'WEAPON_CARBINERIFLE',
  'WEAPON_ADVANCEDRIFLE',
  'WEAPON_MG',
  'WEAPON_COMBATMG',
  'WEAPON_SNIPERRIFLE',
  'WEAPON_HEAVYSNIPER',
  'WEAPON_MICROSMG',
  'WEAPON_SMG',
  'WEAPON_RPG',
  'WEAPON_MINIGUN',
  'WEAPON_PUMPSHOTGUN',
  'WEAPON_SAWNOFFSHOTGUN',
  'WEAPON_ASSAULTSHOTGUN',
  'WEAPON_GRENADE',
  'WEAPON_MOLOTOV',
  'WEAPON_SMOKEGRENADE',
  'WEAPON_STICKYBOMB',
  'WEAPON_PISTOL',
  'WEAPON_COMBATPISTOL',
  'WEAPON_APPISTOL',
  'WEAPON_GRENADELAUNCHER',
  'WEAPON_STUNGUN',
  'WEAPON_PETROLCAN',
  'WEAPON_KNIFE',
  'WEAPON_NIGHTSTICK',
  'WEAPON_HAMMER',
  'WEAPON_BAT',
  'WEAPON_CROWBAR',
  'WEAPON_BOTTLE',
  'WEAPON_SNSPISTOL',
  'WEAPON_HEAVYPISTOL',
  'WEAPON_SPECIALCARBINE',
  'WEAPON_BULLPUPRIFLE',
  'WEAPON_RAYPISTOL',
  'WEAPON_RAYCARBINE',
  'WEAPON_RAYMINIGUN',
  'WEAPON_BULLPUPRIFLE_MK2',
  'WEAPON_DOUBLEACTION',
  'WEAPON_MARKSMANRIFLE_MK2',
  'WEAPON_PUMPSHOTGUN_MK2',
  'WEAPON_REVOLVER_MK2',
  'WEAPON_SNSPISTOL_MK2',
  'WEAPON_SPECIALCARBINE_MK2',
  'WEAPON_PROXMINE',
  'WEAPON_HOMINGLAUNCHER',
  'WEAPON_GUSENBERG',
  'WEAPON_DAGGER',
  'WEAPON_VINTAGEPISTOL',
  'WEAPON_FIREWORK',
  'WEAPON_MUSKET',
  'WEAPON_HATCHET',
  'WEAPON_RAILGUN',
  'WEAPON_HEAVYSHOTGUN',
  'WEAPON_MARKSMANRIFLE',
  'WEAPON_CERAMICPISTOL',
  'WEAPON_HAZARDCAN',
  'WEAPON_NAVYREVOLVER',
  'WEAPON_COMBATSHOTGUN',
  'WEAPON_GADGETPISTOL',
  'WEAPON_MILITARYRIFLE',
  'WEAPON_FLAREGUN',
  'WEAPON_KNUCKLE',
  'WEAPON_MARKSMANPISTOL',
  'WEAPON_COMBATPDW',
  'WEAPON_COMPACTRIFLE',
  'WEAPON_DBSHOTGUN',
  'WEAPON_MACHETE',
  'WEAPON_MACHINEPISTOL',
  'WEAPON_FLASHLIGHT',
  'WEAPON_REVOLVER',
  'WEAPON_SWITCHBLADE',
  'WEAPON_AUTOSHOTGUN',
  'WEAPON_BATTLEAXE',
  'WEAPON_COMPACTLAUNCHER',
  'WEAPON_MINISMG',
  'WEAPON_PIPEBOMB',
  'WEAPON_POOLCUE',
  'WEAPON_WRENCH',
  'WEAPON_ASSAULTRIFLE_MK2',
  'WEAPON_CARBINERIFLE_MK2',
  'WEAPON_COMBATMG_MK2',
  'WEAPON_HEAVYSNIPER_MK2',
  'WEAPON_PISTOL_MK2',
  'WEAPON_SMG_MK2',
  'WEAPON_STONE_HATCHET',
  'WEAPON_METALDETECTOR',
  'WEAPON_TACTICALRIFLE',
  'WEAPON_PRECISIONRIFLE',
  'WEAPON_EMPLAUNCHER',
  'WEAPON_HEAVYRIFLE',
  'WEAPON_PETROLCAN_SMALL_RADIUS',
  'WEAPON_FERTILIZERCAN',
  'WEAPON_STUNGUN_MP',
  'WEAPON_BATTLERIFLE',
  'WEAPON_CANDYCANE',
  'WEAPON_HACKINGDEVICE',
  'WEAPON_PISTOLXM3',
  'WEAPON_RAILGUNXM3',
  'WEAPON_SNOWBALL',
  'WEAPON_SNOWLAUNCHER',
  'WEAPON_STUNROD',
  'WEAPON_TECPISTOL',
  'WEAPON_PARACHUTE',
  'WEAPON_GOLFCLUB'
}

local SEARCHABLE_WEAPON_HASHES = {}
local SEARCHABLE_WEAPON_NAMES_BY_HASH = {}
for _,weaponName in ipairs(SEARCHABLE_WEAPON_NAMES) do
  local weaponHash = joaat(weaponName)
  SEARCHABLE_WEAPON_HASHES[weaponName] = weaponHash
  SEARCHABLE_WEAPON_NAMES_BY_HASH[weaponHash] = weaponName
end

local function weaponLabelFromName(name)
  local pretty = tostring(name or ''):gsub('WEAPON_', ''):gsub('_', ' '):lower()
  return (pretty:gsub('(%a)([%w]*)', function(a, b)
    return string.upper(a) .. b
  end))
end

local function getCurrentWeaponLootData(ped)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
  local weaponHash = GetSelectedPedWeapon(ped)
  if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then return nil end
  local weaponName = SEARCHABLE_WEAPON_NAMES_BY_HASH[weaponHash]
  if not weaponName then return nil end
  return {
    name = weaponName,
    hash = weaponHash,
    ammo = tonumber(GetAmmoInPedWeapon(ped, weaponHash)) or 0,
    label = weaponLabelFromName(weaponName)
  }
end

local function collectPedLootWeapons(ped)
  local found = {}
  if not ped or ped == 0 or not DoesEntityExist(ped) then return found end
  for _,weaponName in ipairs(SEARCHABLE_WEAPON_NAMES) do
    local weaponHash = SEARCHABLE_WEAPON_HASHES[weaponName]
    if weaponHash and HasPedGotWeapon(ped, weaponHash, false) then
      found[#found+1] = {
        name = weaponName,
        hash = weaponHash,
        ammo = tonumber(GetAmmoInPedWeapon(ped, weaponHash)) or 0,
        label = weaponLabelFromName(weaponName)
      }
    end
  end
  return found
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
local injuryPauseState = false
local injurySuppressUntil = 0

local function injuryTrackingBlocked()
  if injuryPauseState == true then return true end
  local nowMs = GetGameTimer()
  return injurySuppressUntil > 0 and nowMs < injurySuppressUntil
end

local downedStartedAt = 0
local downedCanRespawnAt = 0
local downedBleedoutAt = 0
local respawnHoldStart = 0
local lastDownedHud = 0
local hospitalPromptActive = false
local emsPromptActive = false
local registeredOxTarget = false
local cachedIsMedJob = false
local cachedIsMedJobAt = 0
local hadAliveInjuryEffects = false
local hadHeadBlur = false
local downedLootRegistered = false
local lastDownedLootTarget = nil
local droppedDeathWeaponObjects = {}

local dragState = {
  active = false,
  mode = nil,
  targetServerId = nil,
  targetPed = 0,
  targetNetId = nil,
}
local draggedByServerId = nil
local DRAG_ANIM = {
  dict = 'combat@drag_ped@',
  dragStart = 'injured_pickup_back_plyr',
  dragLoop = 'injured_drag_plyr',
  dragEnd = 'injured_putdown_plyr',
  targetStart = 'injured_pickup_back_ped',
  targetLoop = 'injured_drag_ped',
  targetEnd = 'injured_putdown_ped',
}

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

local function getTargetServerIdFromPed(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  local playerIndex = NetworkGetPlayerIndexFromPed(entity)
  if not playerIndex or playerIndex == -1 then return nil end
  return GetPlayerServerId(playerIndex)
end

local function isTargetPlayerDowned(entity)
  local serverId = getTargetServerIdFromPed(entity)
  if not serverId or serverId <= 0 then return false end
  local state = Player(serverId) and Player(serverId).state
  return state and state.azDowned == true or false
end

local function removeDroppedDeathWeaponObject(key)
  local obj = droppedDeathWeaponObjects[key]
  if obj and DoesEntityExist(obj) then
    DeleteEntity(obj)
  end
  droppedDeathWeaponObjects[key] = nil
end

local function buildDroppedWeaponObject(key, weaponHash, ammo, coords, heading)
  removeDroppedDeathWeaponObject(key)
  if not weaponHash or weaponHash == 0 or not coords then return end
  local obj = CreateWeaponObject(weaponHash, math.max(tonumber(ammo) or 0, 1), coords.x, coords.y, coords.z + 0.04, true, 1.0, 0)
  if not obj or obj == 0 then return end
  SetEntityHeading(obj, tonumber(heading) or 0.0)
  PlaceObjectOnGroundProperly(obj)
  FreezeEntityPosition(obj, true)
  droppedDeathWeaponObjects[key] = obj
end

local function openDownedSearchMenu(targetServerId)
  if not targetServerId or targetServerId <= 0 or not lib or not lib.callback then return end
  local loot = lib.callback.await('Az-Death:server:getDownedLoot', false, targetServerId)
  if type(loot) ~= 'table' then
    notify('There is nothing to search.')
    return
  end

  local options = {}
  if tonumber(loot.cash or 0) > 0 then
    options[#options+1] = {
      title = ('Take Cash - $%s'):format(tonumber(loot.cash) or 0),
      icon = 'fa-solid fa-dollar-sign',
      onSelect = function()
        TriggerServerEvent('Az-Death:server:lootCash', targetServerId)
      end
    }
  end

  for _,weapon in ipairs(loot.weapons or {}) do
    local desc = {}
    if tonumber(weapon.ammo or 0) > 0 then desc[#desc+1] = ('Ammo: %s'):format(tonumber(weapon.ammo) or 0) end
    if weapon.inHand then desc[#desc+1] = 'Dropped from hand weapon' end
    options[#options+1] = {
      title = ('Take %s'):format(weapon.label or weapon.name or 'Weapon'),
      description = #desc > 0 and table.concat(desc, ' • ') or nil,
      icon = 'fa-solid fa-gun',
      onSelect = function()
        TriggerServerEvent('Az-Death:server:lootWeapon', targetServerId, weapon.name)
      end
    }
  end

  if #options == 0 then
    notify('There is nothing left on this body.')
    return
  end

  lastDownedLootTarget = targetServerId
  lib.registerContext({
    id = 'azdeath_search_body',
    title = loot.title or 'Search Body',
    options = options
  })
  lib.showContext('azdeath_search_body')
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

local function dragConfig()
  return Config.Drag or {}
end

local function showDragHelp(text)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(text or 'Press ~INPUT_VEH_DUCK~ to drop body')
  EndTextCommandDisplayHelp(0, false, false, -1)
end

local function requestEntityControl(entity, timeoutMs)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
  if NetworkHasControlOfEntity(entity) then return true end
  NetworkRequestControlOfEntity(entity)
  local expires = GetGameTimer() + math.max(100, math.floor(tonumber(timeoutMs) or 750))
  while GetGameTimer() < expires do
    if NetworkHasControlOfEntity(entity) then
      return true
    end
    Wait(0)
    NetworkRequestControlOfEntity(entity)
  end
  return NetworkHasControlOfEntity(entity)
end

local function playLocalDragAnim(animName, duration, flag)
  if not requestAnim(DRAG_ANIM.dict) then return false end
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return false end
  TaskPlayAnim(ped, DRAG_ANIM.dict, animName, 8.0, -8.0, duration or -1, flag or 33, 0.0, false, false, false)
  return true
end

local function canDragPlayerEntity(entity)
  if dragConfig().Enabled == false or dragConfig().AllowPlayerDrag == false then return false end
  if dragState.active then return false end
  if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
  if entity == PlayerPedId() or not IsPedAPlayer(entity) then return false end
  if IsPedInAnyVehicle(entity, false) then return false end
  return isTargetPlayerDowned(entity) or IsPedFatallyInjured(entity) or IsEntityDead(entity) or IsPedDeadOrDying(entity, true)
end

local function canDragNpcEntity(entity)
  if dragConfig().Enabled == false or dragConfig().AllowNpcDrag == false then return false end
  if dragState.active then return false end
  if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
  if entity == PlayerPedId() or not IsEntityAPed(entity) or IsPedAPlayer(entity) then return false end
  if IsPedInAnyVehicle(entity, false) then return false end
  return IsPedFatallyInjured(entity) or IsEntityDead(entity) or IsPedDeadOrDying(entity, true)
end

local function finishDraggedState(skipAnim)
  local ped = PlayerPedId()
  if draggedByServerId then
    draggedByServerId = nil
    if IsEntityAttached(ped) then
      DetachEntity(ped, true, false)
    end
    if skipAnim ~= true then
      playLocalDragAnim(DRAG_ANIM.targetEnd, 900, 33)
      Wait(850)
    end
    ClearPedSecondaryTask(ped)
  end
end

local function stopDraggingCurrent(skipServer)
  if not dragState.active then return end
  local ped = PlayerPedId()
  if dragState.mode == 'player' then
    if skipServer ~= true and dragState.targetServerId and dragState.targetServerId > 0 then
      TriggerServerEvent('Az-Death:server:stopDragPlayer', dragState.targetServerId)
    end
  elseif dragState.mode == 'npc' then
    local targetPed = dragState.targetPed
    if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
      requestEntityControl(targetPed, 750)
      DetachEntity(targetPed, true, false)
      SetPedCanRagdoll(targetPed, true)
      SetEntityCollision(targetPed, true, true)
    end
  end

  playLocalDragAnim(DRAG_ANIM.dragEnd, 900, 33)
  Wait(850)
  ClearPedSecondaryTask(ped)

  dragState.active = false
  dragState.mode = nil
  dragState.targetServerId = nil
  dragState.targetPed = 0
  dragState.targetNetId = nil
end

local function startDraggingPlayer(entity)
  if dragState.active then
    stopDraggingCurrent()
    return
  end
  if not canDragPlayerEntity(entity) then
    notify('No downed player nearby to drag.')
    return
  end

  local targetServerId = getTargetServerIdFromPed(entity)
  if not targetServerId or targetServerId <= 0 then
    notify('Unable to identify that player.')
    return
  end

  local maxDistance = tonumber(dragConfig().Distance or 2.0) or 2.0
  local selfCoords = GetEntityCoords(PlayerPedId())
  local targetCoords = GetEntityCoords(entity)
  if #(selfCoords - targetCoords) > (maxDistance + 0.25) then
    notify('Move closer to drag the body.')
    return
  end

  dragState.active = true
  dragState.mode = 'player'
  dragState.targetServerId = targetServerId
  dragState.targetPed = entity
  playLocalDragAnim(DRAG_ANIM.dragStart, 900, 33)
  TriggerServerEvent('Az-Death:server:startDragPlayer', targetServerId)
  Wait(150)
  playLocalDragAnim(DRAG_ANIM.dragLoop, -1, 33)
end

local function startDraggingNpc(entity)
  if dragState.active then
    stopDraggingCurrent()
    return
  end
  if not canDragNpcEntity(entity) then
    notify('No dead NPC nearby to drag.')
    return
  end

  requestEntityControl(entity, 1000)
  SetEntityAsMissionEntity(entity, true, true)
  ClearPedTasksImmediately(entity)
  SetBlockingOfNonTemporaryEvents(entity, true)
  SetPedCanRagdoll(entity, false)
  SetEntityCollision(entity, false, false)

  dragState.active = true
  dragState.mode = 'npc'
  dragState.targetPed = entity
  dragState.targetNetId = NetworkGetNetworkIdFromEntity(entity)

  playLocalDragAnim(DRAG_ANIM.dragStart, 900, 33)
  Wait(150)

  local ped = PlayerPedId()
  local bone = GetPedBoneIndex(ped, 11816)
  AttachEntityToEntity(entity, ped, bone, 0.35, 0.62, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
  playLocalDragAnim(DRAG_ANIM.dragLoop, -1, 33)
end

local function findClosestDeadNpc(radius)
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local best, bestDist = nil, tonumber(radius or 2.0) or 2.0
  for _,npc in ipairs(GetGamePool('CPed')) do
    if canDragNpcEntity(npc) then
      local dist = #(coords - GetEntityCoords(npc))
      if dist <= bestDist then
        best = npc
        bestDist = dist
      end
    end
  end
  return best
end

local function findClosestDownedPlayer(radius)
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  for _,entry in ipairs(getPlayersNear(coords, tonumber(radius or 2.0) or 2.0)) do
    if entry.ped ~= ped and canDragPlayerEntity(entry.ped) then
      return entry.ped
    end
  end
  return nil
end

local function tryStartNearestDrag()
  if dragState.active then
    stopDraggingCurrent()
    return
  end
  local radius = tonumber(dragConfig().Distance or 2.0) or 2.0
  local targetPlayerPed = findClosestDownedPlayer(radius)
  if targetPlayerPed then
    startDraggingPlayer(targetPlayerPed)
    return
  end
  local targetNpcPed = findClosestDeadNpc(radius)
  if targetNpcPed then
    startDraggingNpc(targetNpcPed)
    return
  end
  notify('No downed body nearby to drag.')
end

RegisterCommand('dragbody', function()
  tryStartNearestDrag()
end, false)

RegisterCommand('dropbody', function()
  stopDraggingCurrent()
end, false)

RegisterNetEvent('Az-Death:client:beginDragged', function(draggerServerId)
  local draggerPlayer = GetPlayerFromServerId(tonumber(draggerServerId) or -1)
  if draggerPlayer == -1 then return end
  local draggerPed = GetPlayerPed(draggerPlayer)
  if draggerPed == 0 or not DoesEntityExist(draggerPed) then return end

  draggedByServerId = tonumber(draggerServerId) or nil
  playLocalDragAnim(DRAG_ANIM.targetStart, 900, 33)
  Wait(150)
  local bone = GetPedBoneIndex(draggerPed, 11816)
  AttachEntityToEntity(PlayerPedId(), draggerPed, bone, 0.35, 0.62, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
  playLocalDragAnim(DRAG_ANIM.targetLoop, -1, 33)
end)

RegisterNetEvent('Az-Death:client:endDragged', function(draggerServerId)
  if draggedByServerId and draggerServerId and tonumber(draggerServerId) ~= draggedByServerId then return end
  finishDraggedState(false)
end)

RegisterNetEvent('Az-Death:client:dragStartFailed', function()
  if not dragState.active or dragState.mode ~= 'player' then return end
  ClearPedSecondaryTask(PlayerPedId())
  dragState.active = false
  dragState.mode = nil
  dragState.targetServerId = nil
  dragState.targetPed = 0
  dragState.targetNetId = nil
end)

CreateThread(function()
  while true do
    if dragState.active then
      local ped = PlayerPedId()
      if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, false) then
        stopDraggingCurrent()
      else
        if not IsEntityPlayingAnim(ped, DRAG_ANIM.dict, DRAG_ANIM.dragLoop, 3) then
          playLocalDragAnim(DRAG_ANIM.dragLoop, -1, 33)
        end

        if dragState.mode == 'player' then
          local targetPlayer = dragState.targetServerId and GetPlayerFromServerId(dragState.targetServerId) or -1
          local targetPed = targetPlayer ~= -1 and GetPlayerPed(targetPlayer) or 0
          if targetPlayer == -1 or targetPed == 0 or not DoesEntityExist(targetPed) then
            stopDraggingCurrent(true)
          end
        elseif dragState.mode == 'npc' then
          local targetPed = dragState.targetPed
          if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then
            stopDraggingCurrent(true)
          elseif not IsEntityAttachedToEntity(targetPed, ped) then
            local bone = GetPedBoneIndex(ped, 11816)
            requestEntityControl(targetPed, 250)
            SetEntityCollision(targetPed, false, false)
            AttachEntityToEntity(targetPed, ped, bone, 0.35, 0.62, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
          end
        end

        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 44, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
        showDragHelp('Press ~INPUT_VEH_DUCK~ to drop body')

        local dropKey = tonumber(dragConfig().DropKey or 73) or 73
        if IsControlJustReleased(0, dropKey) or IsControlJustReleased(0, 323) then
          stopDraggingCurrent()
        end
      end
      Wait(0)
    elseif draggedByServerId then
      local draggerPlayer = GetPlayerFromServerId(draggedByServerId)
      local draggerPed = draggerPlayer ~= -1 and GetPlayerPed(draggerPlayer) or 0
      local ped = PlayerPedId()
      if draggerPed == 0 or not DoesEntityExist(draggerPed) or IsEntityDead(draggerPed) then
        finishDraggedState(true)
      else
        if not IsEntityAttachedToEntity(ped, draggerPed) then
          local bone = GetPedBoneIndex(draggerPed, 11816)
          AttachEntityToEntity(ped, draggerPed, bone, 0.35, 0.62, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        end
        if not IsEntityPlayingAnim(ped, DRAG_ANIM.dict, DRAG_ANIM.targetLoop, 3) then
          playLocalDragAnim(DRAG_ANIM.targetLoop, -1, 33)
        end
      end
      Wait(0)
    else
      Wait(350)
    end
  end
end)

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
  finishDraggedState(true)
  if dragState.active then
    stopDraggingCurrent()
  end
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  setDownedInvincible(false)
  ClearPedTasksImmediately(ped)
  ClearPedSecondaryTask(ped)
  ClearPedBloodDamage(ped)
  sendDownedHud(false, 0, 0, 0, false)
end

local function reviveFromDowned(skipHeal)
  finishDraggedState(true)
  if dragState.active then
    stopDraggingCurrent()
  end
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  isDowned = false
  respawnHoldStart = 0
  downedLootRegistered = false
  TriggerServerEvent('Az-Death:server:setDownedState', false)
  TriggerServerEvent('Az-Death:server:clearDownedLoot')
  clearAliveInjuryEffects(ped)
  clearDeathState()
  if not skipHeal then
    SetEntityHealth(ped, math.max(Config.Downed and Config.Downed.ReviveHealth or 150, 150))
  end
  sendUiUpdate()
end

local function beginDowned(reason)
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

  local deathCoords = GetEntityCoords(ped)
  local deathHeading = GetEntityHeading(ped)
  local currentWeaponLoot = getCurrentWeaponLootData(ped)
  local collectedLootWeapons = collectPedLootWeapons(ped)

  ClearPedTasksImmediately(ped)
  clearAliveInjuryEffects(ped)
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
  TriggerServerEvent('Az-Death:server:setDownedState', true)
  if not downedLootRegistered and (Config.DropWeaponOnDowned ~= false or Config.SearchDownedPlayers ~= false) then
    downedLootRegistered = true
    TriggerServerEvent('Az-Death:server:registerDownedLoot', {
      coords = { x = deathCoords.x, y = deathCoords.y, z = deathCoords.z },
      heading = deathHeading,
      handWeapon = currentWeaponLoot,
      weapons = collectedLootWeapons
    })
  end
  sendUiUpdate()
  dprint('Entered downed state:', reason or 'unknown')
end

AddEventHandler('baseevents:onPlayerDied', function()
  if not isDowned then
    beginDowned('baseevents:onPlayerDied')
  end
end)

AddEventHandler('baseevents:onPlayerKilled', function()
  if not isDowned then
    beginDowned('baseevents:onPlayerKilled')
  end
end)

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

local function isMedJobLocal(forceRefresh)
  local cacheMs = 5000
  local nowMs = now()
  if not forceRefresh and cachedIsMedJobAt > 0 and (nowMs - cachedIsMedJobAt) < cacheMs then
    return cachedIsMedJob
  end

  cachedIsMedJob = false
  cachedIsMedJobAt = nowMs

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
        if job == department then
          cachedIsMedJob = true
          return true
        end
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
          return isTargetPlayerDowned(entity) or IsPedFatallyInjured(entity) or IsEntityDead(entity) or IsPedRagdoll(entity)
        end,
        onSelect = function(data)
          local entity = data.entity
          if not entity or entity == 0 then return end
          local player = NetworkGetPlayerIndexFromPed(entity)
          if player and player ~= -1 then
            TriggerServerEvent('Az-Death:server:transportNearestPlayer', GetPlayerServerId(player))
          end
        end,

      },
      {
        name = 'azdeath_search_body',
        icon = 'fa-solid fa-magnifying-glass',
        label = 'Search Body',
        distance = tonumber(Config.SearchDistance or 2.0) or 2.0,
        canInteract = function(entity, distance, coords, name)
          if not entity or entity == 0 then return false end
          if distance and distance > (tonumber(Config.SearchDistance or 2.0) or 2.0) then return false end
          if entity == PlayerPedId() then return false end
          return isTargetPlayerDowned(entity)
        end,
        onSelect = function(data)
          local entity = data.entity
          local targetServerId = getTargetServerIdFromPed(entity)
          if targetServerId and targetServerId > 0 then
            openDownedSearchMenu(targetServerId)
          end
        end,
      },
      {
        name = 'azdeath_drag_body',
        icon = 'fa-solid fa-hand',
        label = 'Drag Body',
        distance = tonumber((Config.Drag or {}).Distance or 2.0) or 2.0,
        canInteract = function(entity, distance, coords, name)
          if distance and distance > (tonumber((Config.Drag or {}).Distance or 2.0) or 2.0) then return false end
          return canDragPlayerEntity(entity)
        end,
        onSelect = function(data)
          local entity = data.entity
          if entity and entity ~= 0 then
            startDraggingPlayer(entity)
          end
        end,
      }
    })

    exports.ox_target:addGlobalPed({
      {
        name = 'azdeath_drag_dead_npc',
        icon = 'fa-solid fa-hand',
        label = 'Drag Dead NPC',
        distance = tonumber((Config.Drag or {}).Distance or 2.0) or 2.0,
        canInteract = function(entity, distance, coords, name)
          if distance and distance > (tonumber((Config.Drag or {}).Distance or 2.0) or 2.0) then return false end
          return canDragNpcEntity(entity)
        end,
        onSelect = function(data)
          local entity = data.entity
          if entity and entity ~= 0 then
            startDraggingNpc(entity)
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
  if eventName ~= "CEventNetworkEntityDamage" then return end

  local victim     = args[1]
  local attacker   = args[2]
  local weaponHash = args[7]
  local isMelee    = args[12]
  local damage     = args[13] or 0

  local ped = PlayerPedId()
  if victim ~= ped then return end
  if IsEntityDead(ped) then return end
  if injuryTrackingBlocked() then return end
  if damage <= 0 then return end

  local extra = nil
  if VEHICLE_WEAPON[weaponHash] and attacker and DoesEntityExist(attacker) and IsEntityAVehicle(attacker) then
    extra = { mph = GetEntitySpeed(attacker) * 2.236936 }
  end

  classifyAndApply(ped, weaponHash, damage, isMelee, extra)

  SetTimeout(0, function()
    local cp = PlayerPedId()
    if isDowned or cp == 0 or not DoesEntityExist(cp) then return end
    local hp = GetEntityHealth(cp)
    if hp <= math.max(101, tonumber((Config.Downed and Config.Downed.HealthOnDown) or 110) or 110) then
      beginDowned('critical damage event')
    end
  end)
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

    ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then goto cont end
    if IsEntityDead(ped) then goto cont end

    local hp = GetEntityHealth(ped)
    local armor = GetPedArmour(ped)

    if injuryTrackingBlocked() then
      lastHp, lastArmor = hp, armor
      goto cont
    end

    local delta = (lastHp - hp) + (lastArmor - armor)
    lastHp, lastArmor = hp, armor

    if delta < (Config.VehicleImpact.MinDeltaToConsider or 2) then goto cont end
    if (now() - lastImpactAt) < (Config.VehicleImpact.CooldownMs or 750) then goto cont end

    local collided = HasEntityCollidedWithAnything(ped)
    local ragdoll  = IsPedRagdoll(ped) or IsPedGettingUp(ped)
    if not (collided or ragdoll) then goto cont end

    lastImpactAt = now()

    local speedMph = GetEntitySpeed(ped) * 2.236936
    local dmg = clamp(delta * 3.0, 4, 45)

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

    ::cont::
  end
end)

local wasAirborne = false
local airbornePeakHeight = 0.0
local airbornePeakSpeed = 0.0
local lastLandingAt = 0

CreateThread(function()
  while true do
    local sleep = 200
    local ped = PlayerPedId()

    if ped == 0 or not DoesEntityExist(ped) then
      Wait(500)
    elseif IsEntityDead(ped) or isDowned then
      Wait(300)
    elseif injuryTrackingBlocked() then
      wasAirborne = false
      airbornePeakHeight = 0.0
      airbornePeakSpeed = 0.0
      Wait(250)
    elseif IsPedInAnyVehicle(ped, false) or IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) or IsPedInParachuteFreeFall(ped) or IsPedRagdoll(ped) then
      wasAirborne = IsEntityInAir(ped) or IsPedFalling(ped)
      Wait(200)
    else
      local inAir = IsEntityInAir(ped) or IsPedFalling(ped)
      if inAir then sleep = 50 end
      local h = GetEntityHeightAboveGround(ped)
      local vel = GetEntityVelocity(ped)
      local vertical = math.abs((vel and vel.z) or 0.0) * 2.236936

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

      Wait(sleep)
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

local function clearAliveInjuryEffects(ped)
  clearClipset(ped)
  if hadHeadBlur then
    ClearTimecycleModifier()
    hadHeadBlur = false
  end
  if ped ~= 0 and DoesEntityExist(ped) then
    ResetPedWeaponMovementClipset(ped)
  end
  hadAliveInjuryEffects = false
end

local lastBlackout = 0
local lastStumble = 0

CreateThread(function()
  while true do
    local sleep = 250

    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
      Wait(500)
    else
      local dead = IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
      if dead then
        if hadAliveInjuryEffects then
          clearAliveInjuryEffects(ped)
        end
        Wait(200)
        sendUiUpdate()
      elseif isDowned then
        if hadAliveInjuryEffects then
          clearAliveInjuryEffects(ped)
        end
        Wait(200)
      else
        local head  = maxSeverityByRegions({ "head" })
        local torso = maxSeverityByRegions({ "torso" })
        local leg   = math.max(maxSeverityByRegions({ "lleg" }), maxSeverityByRegions({ "rleg" }))
        local arm   = math.max(maxSeverityByRegions({ "larm" }), maxSeverityByRegions({ "rarm" }))

        local anyInjured = (head + torso + leg + arm) > 0
        local needsPerFrame = false

        if anyInjured then
          hadAliveInjuryEffects = true
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
            needsPerFrame = true
          end
          if leg >= (Config.Thresholds.NoJump or 70) then
            DisableControlAction(0, 22, true)
            needsPerFrame = true
          end
        else
          if hadAliveInjuryEffects then
            clearAliveInjuryEffects(ped)
          end
        end

        if arm >= (Config.Thresholds.AimPenalty or 40) then
          ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", clamp(arm / 250.0, 0.05, 0.30))
          sleep = math.min(sleep, 75)
          if arm >= (Config.Thresholds.NoAim or 80) then
            DisableControlAction(0, 25, true)
            needsPerFrame = true
          end
        end

        if head >= (Config.Thresholds.HeadBlur or 30) then
          SetTimecycleModifier("tunnel")
          SetTimecycleModifierStrength(clamp(head / 120.0, 0.15, 0.55))
          hadHeadBlur = true
          sleep = math.min(sleep, 75)
        elseif hadHeadBlur then
          ClearTimecycleModifier()
          hadHeadBlur = false
        end

        if Config.Blackout and Config.Blackout.Enabled and head >= (Config.Thresholds.HeadBlackout or 75) then
          sleep = math.min(sleep, 50)
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

        if needsPerFrame then
          sleep = 0
        elseif anyInjured then
          sleep = math.min(sleep, 100)
        end
      end
    end

    Wait(sleep)
  end
end)

local lastBleedTick = 0
CreateThread(function()
  while true do
    Wait(200)

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

local function debugStatus(label)
  local ped = PlayerPedId()
  local exists = ped ~= 0 and DoesEntityExist(ped)
  local hp = exists and GetEntityHealth(ped) or -1
  local dead = exists and IsEntityDead(ped) or false
  local dying = exists and IsPedDeadOrDying(ped, true) or false
  local fatal = exists and IsPedFatallyInjured(ped) or false
  local msg = ('%s | ped=%s | hp=%s | isDowned=%s | dead=%s | dying=%s | fatal=%s'):format(tostring(label or 'deathstatus'), tostring(ped), tostring(hp), tostring(isDowned), tostring(dead), tostring(dying), tostring(fatal))
  print(('^3[%s]^7 %s'):format(RESOURCE, msg))
  TriggerServerEvent('Az-Death:server:probeLog', msg)
  TriggerEvent('chat:addMessage', { color = { 255, 150, 80 }, args = { '^3Az-Death', msg } })
end

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

  RegisterCommand('deathdebug', function()
    DEBUG = not DEBUG
    print(('^3[%s]^7 deathdebug toggled -> %s'):format(RESOURCE, tostring(DEBUG)))
    debugStatus('deathdebug')
  end, false)

  RegisterCommand('deathstatus', function()
    debugStatus('deathstatus')
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

RegisterNetEvent('Az-Death:client:createDroppedWeaponObject', function(ownerServerId, weaponName, ammo, coords, heading)
  if Config.DropWeaponOnDowned == false then return end
  if not ownerServerId or not weaponName or type(coords) ~= 'table' then return end
  local weaponHash = SEARCHABLE_WEAPON_HASHES[weaponName] or joaat(weaponName)
  if not weaponHash or weaponHash == 0 then return end
  buildDroppedWeaponObject(('deathdrop:%s'):format(ownerServerId), weaponHash, ammo, coords, heading)
end)

RegisterNetEvent('Az-Death:client:removeDroppedWeaponObject', function(ownerServerId)
  if not ownerServerId then return end
  removeDroppedDeathWeaponObject(('deathdrop:%s'):format(ownerServerId))
end)

RegisterNetEvent('Az-Death:client:receiveLootWeapon', function(weaponName, ammo)
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) or not weaponName then return end
  local weaponHash = SEARCHABLE_WEAPON_HASHES[weaponName] or joaat(weaponName)
  if not weaponHash or weaponHash == 0 then return end
  GiveWeaponToPed(ped, weaponHash, math.max(tonumber(ammo) or 0, 0), false, false)
  notify(('You took %s.'):format(weaponLabelFromName(weaponName)))
  if lastDownedLootTarget then
    SetTimeout(100, function()
      openDownedSearchMenu(lastDownedLootTarget)
    end)
  end
end)

RegisterNetEvent('Az-Death:client:stripLootWeapon', function(weaponName)
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) or not weaponName then return end
  local weaponHash = SEARCHABLE_WEAPON_HASHES[weaponName] or joaat(weaponName)
  if weaponHash and weaponHash ~= 0 then
    RemoveWeaponFromPed(ped, weaponHash)
    SetPedAmmo(ped, weaponHash, 0)
  end
end)

CreateThread(function()
  while true do
    local ped = PlayerPedId()
    local waitMs = 100
    if ped ~= 0 and DoesEntityExist(ped) then
      local hp = GetEntityHealth(ped)
      if hp <= 120 or IsPedDeadOrDying(ped, true) or IsEntityDead(ped) then
        waitMs = 0
      elseif hp <= 140 then
        waitMs = 25
      end
    end
    Wait(waitMs)
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then goto cont end

    if not isDowned then
      sendDownedHud(false, 0, 0, 0, false)
      if not injuryTrackingBlocked() and (Config.Downed and Config.Downed.Enabled ~= false) and (IsEntityDead(ped) or IsPedFatallyInjured(ped) or IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= math.max(101, tonumber((Config.Downed and Config.Downed.HealthOnDown) or 110) or 110)) then
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

      if Config.Downed and Config.Downed.PlayLoopAnim ~= false then
        clearAliveInjuryEffects(ped)
        if IsPedGettingUp(ped) or IsPedRagdoll(ped) or not IsEntityPlayingAnim(ped, Config.Downed.AnimDict or 'dead', Config.Downed.AnimName or 'dead_a', 3) then
          ClearPedTasksImmediately(ped)
          if requestAnim(Config.Downed.AnimDict or 'dead') then
            TaskPlayAnim(ped, Config.Downed.AnimDict or 'dead', Config.Downed.AnimName or 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
          end
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

    ::cont::
  end
end)

CreateThread(function()
  while true do
    local sleep = 500
    tryRegisterOxTarget()

    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
      sleep = 750
    else
      local pcoords = GetEntityCoords(ped)

      local hospital = getNearestHospital(2.25)
    if hospital and not isDowned then
      sleep = 0
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
      sleep = math.min(sleep, 200)
      local target = nil
      local near = getPlayersNear(pcoords, 2.0)
      for _,entry in ipairs(near) do
        if entry.ped ~= ped and (IsPedFatallyInjured(entry.ped) or IsEntityDead(entry.ped) or IsPedRagdoll(entry.ped)) then
          target = entry
          break
        end
      end
      if target then
        sleep = 0
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
      if emsPromptActive and not hospitalPromptActive then
        sendMedPrompt(false)
      end
      emsPromptActive = false
    end

    end
    Wait(sleep)
  end
end)

CreateThread(function()
  Wait(800)
  sendUiUpdate()
end)

RegisterNetEvent('Az-Death:injury:pause', function(state)
  injuryPauseState = state == true
end)

RegisterNetEvent('Az-Death:injury:suppress', function(ms)
  ms = math.max(0, math.floor(tonumber(ms) or 0))
  if ms <= 0 then return end
  local untilAt = GetGameTimer() + ms
  if untilAt > injurySuppressUntil then
    injurySuppressUntil = untilAt
  end
end)

exports('setInjuryPaused', function(state)
  injuryPauseState = state == true
end)

exports('suppressInjuries', function(ms)
  ms = math.max(0, math.floor(tonumber(ms) or 0))
  if ms <= 0 then return end
  local untilAt = GetGameTimer() + ms
  if untilAt > injurySuppressUntil then
    injurySuppressUntil = untilAt
  end
end)

exports('getInjuriesUi', function()
  return {
    injuries = toUiArray(),
    bleeding = bleedingInfo(),
    pinned = pinned,
    dead = isDowned
  }
end)

RegisterNetEvent('Az-Death:debug:statusRequestFromCore', function(label)
  debugStatus(label or 'core_request')
end)

RegisterNetEvent('Az-Death:debug:setDebugFromCore', function(state)
  DEBUG = state == true
  print(('^3[%s]^7 debug set from core -> %s'):format(RESOURCE, tostring(DEBUG)))
  debugStatus('debug_set_from_core')
end)
