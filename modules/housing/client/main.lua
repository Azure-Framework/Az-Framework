local RES = GetCurrentResourceName()
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
Config.LastPosAutoSaveEnabled = (Config.LastPosAutoSaveEnabled ~= false)
Config.LastPosAutoSaveIntervalMs = tonumber(Config.LastPosAutoSaveIntervalMs) or 10000
AZH = AZH or {}
AZH.C = AZH.C or {}

AZH.C.houses = AZH.C.houses or {}
AZH.C.doors = AZH.C.doors or {}
AZH.C.garages = AZH.C.garages or {}
AZH.C.rentals = AZH.C.rentals or {}
AZH.C.interiors = AZH.C.interiors or {}
AZH.C.blips = AZH.C.blips or {}
AZH.C.zones = AZH.C.zones or { doors = {}, garages = {}, interiorExit = nil }
AZH.C.forcedUnlockUntil = AZH.C.forcedUnlockUntil or {}
AZH.C.policeBreachBlips = AZH.C.policeBreachBlips or {}

local function dprint(...)
  if Config and Config.Debug then
    print(('^3[%s:client]^7'):format(RES), ...)
  end
end

if type(AZH.C.clearBlips) ~= 'function' then
  function AZH.C.clearBlips()
    if not AZH.C.blips then AZH.C.blips = {} return end
    for i = 1, #AZH.C.blips do
      local b = AZH.C.blips[i]
      if b and DoesBlipExist(b) then
        RemoveBlip(b)
      end
    end
    AZH.C.blips = {}
  end
end

RegisterCommand('azh_job', function()
  local job = (AZH.getJobName and AZH.getJobName()) or 'nil'
  local isP = (AZH.isPolice and AZH.isPolice()) or false
  print(('[az_housing] job=%s isPolice=%s'):format(tostring(job), tostring(isP)))
end)

local function makeBlips()
  AZH.C.clearBlips()
  if not (Config and Config.Blips and Config.Blips.Enabled) then return end

  for _, door in ipairs(AZH.C.doors or {}) do
    local h = AZH.C.houses and AZH.C.houses[tonumber(door.house_id)]
    if h then
      local blip = AddBlipForCoord(door.x, door.y, door.z)
      SetBlipSprite(blip, (Config.Blips.Sprite or 40))
      SetBlipColour(blip, (Config.Blips.Color or 2))
      SetBlipScale(blip, (Config.Blips.Scale or 0.65))
      SetBlipAsShortRange(blip, (Config.Blips.ShortRange ~= false))
      BeginTextCommandSetBlipName('STRING')
      AddTextComponentString(tostring(h.name or ('House #' .. tostring(h.id))))
      EndTextCommandSetBlipName(blip)
      AZH.C.blips[#AZH.C.blips+1] = blip
    end
  end
end

local function applyBootstrap(data)
  data = data or {}
  AZH.C.isAgentRole = (data.isAgentRole == true)

  AZH.C.houses = {}
  for _, h in ipairs(data.houses or {}) do
    h.id = tonumber(h.id)
    if h.id then AZH.C.houses[h.id] = h end
  end

  AZH.C.doors = data.doors or {}
  AZH.C.garages = data.garages or {}

  AZH.C.rentals = {}
  for _, r in ipairs(data.rentals or {}) do
    local hid = tonumber(r.house_id)
    if hid then AZH.C.rentals[hid] = r end
  end

  AZH.C.interiors = data.interiors or (Config and Config.Interiors) or {}

  AZH.C.identifier = data.identifier or AZH.C.identifier
  AZH.C.identifierAliases = data.identifierAliases or AZH.C.identifierAliases or {}

  if type(AZH.C.identifier) == 'string' then
    if AZH.C.identifier:sub(1,5) == 'char:' then
      AZH.C.identifier = 'charid:' .. AZH.C.identifier:sub(6)
    end
  end

  if type(AZH.C.identifierAliases) == 'table' then
    for i = 1, #AZH.C.identifierAliases do
      local v = AZH.C.identifierAliases[i]
      if type(v) == 'string' and v:sub(1,5) == 'char:' then
        AZH.C.identifierAliases[i] = 'charid:' .. v:sub(6)
      end
    end
  end

  AZH.C.isAdmin = (data.isAdmin == true)
  AZH.C.isPoliceFlag = (data.isPolice == true)

  AZH.C.ready = true

  makeBlips()
  TriggerEvent('az_housing:client:rebuildTargets')
end

RegisterNetEvent('az_housing:client:bootstrap', function(data)
  applyBootstrap(data or {})
end)

RegisterNetEvent('az_housing:client:updateHouse', function(h)
  if not h or not h.id then return end
  h.id = tonumber(h.id)
  if not h.id then return end
  AZH.C.houses[h.id] = h
  makeBlips()
  TriggerEvent('az_housing:client:rebuildTargets')
end)

RegisterNetEvent('az_housing:client:removeHouse', function(houseId)
  houseId = tonumber(houseId)
  if not houseId then return end

  AZH.C.houses[houseId] = nil

  local nd, ng = {}, {}
  for _, d in ipairs(AZH.C.doors or {}) do
    if tonumber(d.house_id) ~= houseId then nd[#nd+1] = d end
  end
  for _, g in ipairs(AZH.C.garages or {}) do
    if tonumber(g.house_id) ~= houseId then ng[#ng+1] = g end
  end
  AZH.C.doors, AZH.C.garages = nd, ng

  makeBlips()
  TriggerEvent('az_housing:client:rebuildTargets')
end)

RegisterNetEvent('az_housing:client:updateDoor', function(d)
  if not d or not d.id then return end
  local replaced = false
  for i = 1, #(AZH.C.doors or {}) do
    if tonumber(AZH.C.doors[i].id) == tonumber(d.id) then
      AZH.C.doors[i] = d
      replaced = true
      break
    end
  end
  if not replaced then
    AZH.C.doors[#AZH.C.doors+1] = d
  end
  makeBlips()
  TriggerEvent('az_housing:client:rebuildTargets')
end)

RegisterNetEvent('az_housing:client:removeDoor', function(id)
  id = tonumber(id)
  if not id then return end
  local out = {}
  for _, d in ipairs(AZH.C.doors or {}) do
    if tonumber(d.id) ~= id then out[#out+1] = d end
  end
  AZH.C.doors = out
  makeBlips()
  TriggerEvent('az_housing:client:rebuildTargets')
end)

RegisterNetEvent('az_housing:client:updateGarage', function(g)
  if not g or not g.id then return end
  local replaced = false
  for i = 1, #(AZH.C.garages or {}) do
    if tonumber(AZH.C.garages[i].id) == tonumber(g.id) then
      AZH.C.garages[i] = g
      replaced = true
      break
    end
  end
  if not replaced then
    AZH.C.garages[#AZH.C.garages+1] = g
  end
  TriggerEvent('az_housing:client:rebuildTargets')
end)

RegisterNetEvent('az_housing:client:removeGarage', function(id)
  id = tonumber(id)
  if not id then return end
  local out = {}
  for _, g in ipairs(AZH.C.garages or {}) do
    if tonumber(g.id) ~= id then out[#out+1] = g end
  end
  AZH.C.garages = out
  TriggerEvent('az_housing:client:rebuildTargets')
end)

RegisterNetEvent('az_housing:client:updateRental', function(r)
  if not r or not r.house_id then return end
  AZH.C.rentals[tonumber(r.house_id)] = r
  if AZH.UI and AZH.UI.isOpen and AZH.UI.isOpen() then
    if AZH.UI.refresh then AZH.UI.refresh() end
  end
end)

RegisterNetEvent('az_housing:client:forcedUnlock', function(houseId, untilTs)
  houseId = tonumber(houseId)
  if not houseId then return end
  AZH.C.forcedUnlockUntil[houseId] = tonumber(untilTs) or 0
end)

RegisterNetEvent('az_housing:client:notify', function(ntype, title, desc)
  if AZH.notify then AZH.notify(ntype, title, desc) end
end)

RegisterNetEvent('az_housing:client:knock', function(info)
  local name = (info and info.name) or 'Someone'
  if AZH.notify then AZH.notify('inform', 'Knock', name .. ' is knocking at the door.') end
  PlaySoundFrontend(-1, 'ATM_WINDOW', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end)

RegisterNetEvent('az_housing:client:breach', function()
  if AZH.notify then AZH.notify('warning', 'Breach', 'Police forced the door!') end
  PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

RegisterNetEvent('az_housing:client:policeBreach', function(info)
  if not AZH.isPolice or not AZH.isPolice() then return end
  info = info or {}
  local name = tostring(info.houseName or ('House #' .. tostring(info.houseId or '')))

  if AZH.notify then
    AZH.notify('warning', 'Breach', ('Breach reported at %s'):format(name))
  end

  local c = info.coords
  if not c or not c.x then return end

  AZH.C.policeBreachBlips = AZH.C.policeBreachBlips or {}

  local blip = AddBlipForCoord(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
  SetBlipSprite(blip, 161)
  SetBlipScale(blip, 1.05)
  SetBlipAsShortRange(blip, false)
  SetBlipFlashes(blip, true)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('Housing Breach')
  EndTextCommandSetBlipName(blip)

  AZH.C.policeBreachBlips[#AZH.C.policeBreachBlips+1] = blip

  local ttl = (Config and Config.Police and Config.Police.BreachBlipSeconds) or 180
  CreateThread(function()
    Wait(math.max(10, ttl) * 1000)
    if DoesBlipExist(blip) then RemoveBlip(blip) end
  end)
end)

local function teleportTo(vec4)
  local ped = PlayerPedId()
  SetEntityCoords(ped, vec4.x, vec4.y, vec4.z - 0.95, false, false, false, true)
  SetEntityHeading(ped, vec4.w or 0.0)
end

function AZH.enterInterior(houseId, interior)
  houseId = tonumber(houseId)
  if not houseId or not interior or not interior.entry then return end

  AZH.C.currentHouseId = houseId

  DoScreenFadeOut(200)
  while not IsScreenFadedOut() do Wait(0) end

  local ped = PlayerPedId()
  AZH.C.outside = {
    coords = GetEntityCoords(ped),
    heading = GetEntityHeading(ped)
  }

  teleportTo(interior.entry)

  DoScreenFadeIn(200)
  TriggerEvent('az_housing:client:enteredInterior', houseId, interior)
end

function AZH.leaveInterior()
  if not AZH.C.currentHouseId then return end
  local houseId = AZH.C.currentHouseId
  AZH.C.currentHouseId = nil

  DoScreenFadeOut(200)
  while not IsScreenFadedOut() do Wait(0) end

  if AZH.C.outside and AZH.C.outside.coords then
    local ped = PlayerPedId()
    SetEntityCoords(ped, AZH.C.outside.coords.x, AZH.C.outside.coords.y, AZH.C.outside.coords.z - 0.95, false, false, false, true)
    SetEntityHeading(ped, AZH.C.outside.heading or 0.0)
  end

  DoScreenFadeIn(200)
  TriggerServerEvent('az_housing:server:leave', houseId)
  TriggerEvent('az_housing:client:leftInterior', houseId)
end

RegisterNetEvent('az_housing:client:enter', function(payload)
  if not payload or not payload.house or not payload.interior then return end
  AZH.enterInterior(payload.house.id, payload.interior)
end)

CreateThread(function()
  while true do
    if not AZH.C.ready then
      Wait(1000)
    elseif not AZH.C.currentHouseId then
      Wait(750)
    else
      local h = AZH.C.houses[AZH.C.currentHouseId]
      local it = h and AZH.C.interiors[h.interior] or nil
      if not (it and it.exit) then
        Wait(500)
      else
        local ped = PlayerPedId()
        local p = GetEntityCoords(ped)
        local dist = #(p - vector3(it.exit.x, it.exit.y, it.exit.z))
        if dist <= 2.0 then
          if lib and lib.showTextUI then
            lib.showTextUI('[E] Exit', { position = 'left-center' })
          end
          if IsControlJustPressed(0, 38) then
            if lib and lib.hideTextUI then lib.hideTextUI() end
            AZH.leaveInterior()
          end
        else
          if lib and lib.hideTextUI then lib.hideTextUI() end
        end
        Wait(0)
      end
    end
  end
end)

local function requestBootstrap(reason)
  if AZH.C.__bootInFlight then return end
  AZH.C.__bootInFlight = true

  CreateThread(function()
    local tries = 0
    while not AZH.C.ready and tries < 12 do
      tries += 1
      dprint(('bootstrap request (%s) try=%s'):format(tostring(reason), tostring(tries)))

      TriggerServerEvent('az_housing:server:bootstrap')

      local waited = 0
      while not AZH.C.ready and waited < 2000 do
        Wait(100)
        waited += 100
      end
    end

    AZH.C.__bootInFlight = false

    if AZH.C.ready then
      makeBlips()
      TriggerEvent('az_housing:client:rebuildTargets')
    else
      print(('^1[%s]^7 bootstrap failed after %s tries (no client:bootstrap received)'):format(RES, tries))
    end
  end)
end

CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(250) end
  while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
  Wait(750)
  requestBootstrap('join')
end)

AddEventHandler('onClientResourceStart', function(resName)
  if resName ~= RES then return end
  Wait(500)
  requestBootstrap('resourceStart')
end)

AddEventHandler('playerSpawned', function()
  Wait(750)
  if AZH.C.ready then
    makeBlips()
    TriggerEvent('az_housing:client:rebuildTargets')
  else
    requestBootstrap('playerSpawned')
  end
end)

AddEventHandler('onClientResourceStop', function(resName)
  if resName ~= RES then return end
  pcall(function()
    if AZH.C and AZH.C.clearBlips then AZH.C.clearBlips() end
    if AZH.C and AZH.C.resetZones then AZH.C.resetZones() end
  end)
end)

RegisterCommand((Config and Config.Commands and (Config.Commands.Portal or 'housing')) or 'housing', function()
  if AZH.UI and AZH.UI.open then AZH.UI.open() end
end)

local function buildUIState()

  local function canonIdent(v)
    if v == nil then return nil end
    local s = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    s = s:lower()
    if s:sub(1,5) == 'char:' then
      s = 'charid:' .. s:sub(6)
    end
    return s
  end

  local myIdSet = {}
  local function addMyId(v)
    v = canonIdent(v)
    if not v then return end
    myIdSet[v] = true
  end

  addMyId(AZH.C.identifier)
  if type(AZH.C.identifierAliases) == 'table' then
    for i = 1, #AZH.C.identifierAliases do
      addMyId(AZH.C.identifierAliases[i])
    end
  end

  local owned = {}
  for _, h in pairs(AZH.C.houses or {}) do
    local hid = tonumber(h.id)
    if hid then
      local owner = canonIdent(h.owner_identifier or h.ownerIdentifier or h.owner)
      if owner and myIdSet[owner] then
        owned[tostring(hid)] = true
      end
    end
  end

  return {
    ok = true,
    ready = (AZH.C.ready == true),
    isAdmin = (AZH.C.isAdmin == true),
    isPolice = (AZH.isPolice and AZH.isPolice()) or (AZH.C.isPoliceFlag == true),
    isAgentRole = (AZH.C.isAgentRole == true),
    identifier = AZH.C.identifier,
    identifierAliases = AZH.C.identifierAliases or {},
    houses = AZH.C.houses or {},
    doors = AZH.C.doors or {},
    garages = AZH.C.garages or {},
    rentals = AZH.C.rentals or {},
    interiors = AZH.C.interiors or {},
    forcedUnlockUntil = AZH.C.forcedUnlockUntil or {},
    currentHouseId = AZH.C.currentHouseId,
    owned = owned,
  }
end

if type(AZH.UI.isOpen) ~= "function" then
  function AZH.UI.isOpen() return AZH.UI.__open == true end
end

if type(AZH.UI.open) ~= "function" then
function AZH.UI.open()
  AZH.UI.__open = true
  SetNuiFocus(true, true)
  local s = buildUIState()
  SendNUIMessage({ type = "azhousing_open", payload = s })
end
end

if type(AZH.UI.close) ~= "function" then
function AZH.UI.close()
  AZH.UI.__open = false
  SetNuiFocus(false, false)
  SendNUIMessage({ type = "azhousing_close" })
end
end

if type(AZH.UI.refresh) ~= "function" then
function AZH.UI.refresh()
  if not AZH.UI.isOpen() then return end
  local s = buildUIState()
  SendNUIMessage({ type = "azhousing_update", payload = s })
end
end

if not AZH.UI.__nuiRegistered then
  AZH.UI.__nuiRegistered = true
RegisterNUICallback("nuiAction", function(req, cb)
  req = req or {}
  local action = tostring(req.action or "")
  local data = req.data or {}

  local function ok(payload)
    cb(payload or { ok = true })
  end
  local function bad(err, extra)
    local out = { ok = false, error = err or "error" }
    if extra then
      for k,v in pairs(extra) do out[k] = v end
    end
    cb(out)
  end

  if action == "close" then
    AZH.UI.close()
    return ok()

  elseif action == "requestState" then
    return ok(buildUIState())

  elseif action == "refresh" then

    return ok(buildUIState())

  elseif action == "enter" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:enter', houseId)
    return ok()

  elseif action == "knock" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:knock', houseId)
    return ok()

  elseif action == "toggleLock" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:toggleLock', houseId)
    return ok()

  elseif action == "buy" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:buy', houseId)
    return ok()

  elseif action == "applyRent" then
    local houseId = tonumber(data.houseId)
    local message = tostring(data.message or ""):sub(1, 800)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:applyRent', houseId, message)
    return ok()

  elseif action == "sellToPlayer" then
    local houseId = tonumber(data.houseId)
    local targetSrc = tonumber(data.targetSrc)
    local price = tonumber(data.price) or 0
    if not (houseId and targetSrc) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:sellToPlayer', houseId, targetSrc, price)
    return ok()

  elseif action == "listForRent" then
    local houseId = tonumber(data.houseId)
    local rentPerWeek = tonumber(data.rentPerWeek) or 0
    local deposit = tonumber(data.deposit) or 0
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:listForRent', houseId, rentPerWeek, deposit)
    return ok()

  elseif action == "unlistRent" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:unlistRent', houseId)
    return ok()

  elseif action == "rentToPlayer" then
    local houseId = tonumber(data.houseId)
    local targetSrc = tonumber(data.targetSrc)
    local rentPerWeek = tonumber(data.rentPerWeek) or 0
    local deposit = tonumber(data.deposit) or 0
    if not (houseId and targetSrc) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:rentToPlayer', houseId, targetSrc, rentPerWeek, deposit)
    return ok()

  elseif action == "endLease" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:endLease', houseId)
    return ok()

  elseif action == "buyUpgrade" then
    local houseId = tonumber(data.houseId)
    local upType = tostring(data.upType or "")
    if not (houseId and upType ~= "") then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:buyUpgrade', houseId, upType)
    return ok()

  elseif action == "startFurnish" then
    local houseId = tonumber(data.houseId)
    local model = tostring(data.model or "")
    if not (houseId and model ~= "") then return bad("bad_args") end

    TriggerEvent('az_housing:client:startFurnish', houseId, model)
    return ok()

  elseif action == "removeFurniture" then
    local houseId = tonumber(data.houseId)
    local furnId = tonumber(data.furnId)
    if not (houseId and furnId) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:removeFurniture', houseId, furnId)
    return ok()

  elseif action == "sendMail" then
    local houseId = tonumber(data.houseId)
    local subject = tostring(data.subject or "Message"):sub(1, 64)
    local body = tostring(data.body or ""):sub(1, 1200)
    if not (houseId and body ~= "") then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:sendMail', houseId, subject, body)
    return ok()

  elseif action == "markMailRead" then
    local houseId = tonumber(data.houseId)
    local mailId = tonumber(data.mailId)
    local isRead = (data.isRead == true)
    if not (houseId and mailId) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:markMailRead', houseId, mailId, isRead)
    return ok()

  elseif action == "deleteMail" then
    local houseId = tonumber(data.houseId)
    local mailId = tonumber(data.mailId)
    if not (houseId and mailId) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:deleteMail', houseId, mailId)
    return ok()

elseif action == 'loadHouseExtras' then
  local houseId = data and data.houseId
  houseId = tonumber(houseId)

  if not houseId then
    cb({ ok = false, error = 'bad_houseId' })
    return
  end

  local extras = lib.callback.await('az_housing:loadHouseExtras', false, houseId)

  print(('[az_housing][nui] loadHouseExtras type=%s'):format(type(extras)))

  if type(extras) ~= 'table' then
    print(('[az_housing][nui] loadHouseExtras BAD RESPONSE: %s'):format(tostring(extras)))
    cb({ ok = false, error = 'bad_extras_type:' .. type(extras) })
    return
  end

  print(('[az_housing][nui] extras keys: mailbox=%s upgrades=%s furniture=%s images=%s'):format(
    tostring(extras.mailbox ~= nil),
    tostring(extras.upgrades ~= nil),
    tostring(extras.furniture ~= nil),
    tostring(extras.images ~= nil)
  ))

  cb(extras)
  return

  elseif action == "addHouseImage" then
    local houseId = data.houseId
    local payload = data.payload or {}

    if not (lib and lib.callback and lib.callback.await) then
      return bad('ox_lib_missing')
    end

    local okk, res = pcall(function()
      return lib.callback.await('az_housing:cb:addHouseImage', 15000, houseId, payload)
    end)

    if not okk then
      print(('[%s] addHouseImage callback error: %s'):format(RES, tostring(res)))
      return bad('callback_error')
    end

    cb(res or { ok=false, error='no_response' })
    return

  elseif action == "deleteHouseImage" then
    local houseId = data.houseId
    local imageId = data.imageId

    if not (lib and lib.callback and lib.callback.await) then
      return bad('ox_lib_missing')
    end

    local okk, res = pcall(function()
      return lib.callback.await('az_housing:cb:deleteHouseImage', 15000, houseId, imageId)
    end)

    if not okk then
      print(('[%s] deleteHouseImage callback error: %s'):format(RES, tostring(res)))
      return bad('callback_error')
    end

    cb(res or { ok=false, error='no_response' })
    return

  else
    return bad("unknown_action", { action = action })
  end
end)
RegisterNUICallback("nuiAction", function(req, cb)
  req = req or {}
  local action = tostring(req.action or "")
  local data = req.data or {}

  local function ok(payload)
    cb(payload or { ok = true })
  end
  local function bad(err, extra)
    local out = { ok = false, error = err or "error" }
    if extra then
      for k,v in pairs(extra) do out[k] = v end
    end
    cb(out)
  end

  if action == "close" then
    AZH.UI.close()
    return ok()

  elseif action == "requestState" then
    return ok(buildUIState())

  elseif action == "refresh" then

    return ok(buildUIState())

  elseif action == "enter" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:enter', houseId)
    return ok()

  elseif action == "knock" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:knock', houseId)
    return ok()

  elseif action == "toggleLock" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:toggleLock', houseId)
    return ok()

  elseif action == "buy" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:buy', houseId)
    return ok()

  elseif action == "applyRent" then
    local houseId = tonumber(data.houseId)
    local message = tostring(data.message or ""):sub(1, 800)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:applyRent', houseId, message)
    return ok()

  elseif action == "sellToPlayer" then
    local houseId = tonumber(data.houseId)
    local targetSrc = tonumber(data.targetSrc)
    local price = tonumber(data.price) or 0
    if not (houseId and targetSrc) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:sellToPlayer', houseId, targetSrc, price)
    return ok()

  elseif action == "listForRent" then
    local houseId = tonumber(data.houseId)
    local rentPerWeek = tonumber(data.rentPerWeek) or 0
    local deposit = tonumber(data.deposit) or 0
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:listForRent', houseId, rentPerWeek, deposit)
    return ok()

  elseif action == "unlistRent" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:unlistRent', houseId)
    return ok()

  elseif action == "rentToPlayer" then
    local houseId = tonumber(data.houseId)
    local targetSrc = tonumber(data.targetSrc)
    local rentPerWeek = tonumber(data.rentPerWeek) or 0
    local deposit = tonumber(data.deposit) or 0
    if not (houseId and targetSrc) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:rentToPlayer', houseId, targetSrc, rentPerWeek, deposit)
    return ok()

  elseif action == "endLease" then
    local houseId = tonumber(data.houseId)
    if not houseId then return bad("bad_house") end
    TriggerServerEvent('az_housing:server:endLease', houseId)
    return ok()

  elseif action == "buyUpgrade" then
    local houseId = tonumber(data.houseId)
    local upType = tostring(data.upType or "")
    if not (houseId and upType ~= "") then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:buyUpgrade', houseId, upType)
    return ok()

  elseif action == "startFurnish" then
    local houseId = tonumber(data.houseId)
    local model = tostring(data.model or "")
    if not (houseId and model ~= "") then return bad("bad_args") end

    TriggerEvent('az_housing:client:startFurnish', houseId, model)
    return ok()

  elseif action == "removeFurniture" then
    local houseId = tonumber(data.houseId)
    local furnId = tonumber(data.furnId)
    if not (houseId and furnId) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:removeFurniture', houseId, furnId)
    return ok()

  elseif action == "sendMail" then
    local houseId = tonumber(data.houseId)
    local subject = tostring(data.subject or "Message"):sub(1, 64)
    local body = tostring(data.body or ""):sub(1, 1200)
    if not (houseId and body ~= "") then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:sendMail', houseId, subject, body)
    return ok()

  elseif action == "markMailRead" then
    local houseId = tonumber(data.houseId)
    local mailId = tonumber(data.mailId)
    local isRead = (data.isRead == true)
    if not (houseId and mailId) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:markMailRead', houseId, mailId, isRead)
    return ok()

  elseif action == "deleteMail" then
    local houseId = tonumber(data.houseId)
    local mailId = tonumber(data.mailId)
    if not (houseId and mailId) then return bad("bad_args") end
    TriggerServerEvent('az_housing:server:deleteMail', houseId, mailId)
    return ok()

  elseif action == "loadHouseExtras" then
    local houseId = data.houseId
    if not (lib and lib.callback and lib.callback.await) then
      return bad('ox_lib_missing')
    end

    local okk, extras = pcall(function()
      return lib.callback.await('az_housing:cb:loadHouseExtras', 8000, houseId)
    end)

    if not okk then
      print(('[%s] loadHouseExtras callback error: %s'):format(RES, tostring(extras)))
      return bad('callback_error')
    end

    cb(extras or { ok=false, error='no_response' })
    return

  elseif action == "addHouseImage" then
    local houseId = data.houseId
    local payload = data.payload or {}

    if not (lib and lib.callback and lib.callback.await) then
      return bad('ox_lib_missing')
    end

    local okk, res = pcall(function()
      return lib.callback.await('az_housing:cb:addHouseImage', 15000, houseId, payload)
    end)

    if not okk then
      print(('[%s] addHouseImage callback error: %s'):format(RES, tostring(res)))
      return bad('callback_error')
    end

    cb(res or { ok=false, error='no_response' })
    return

  elseif action == "deleteHouseImage" then
    local houseId = data.houseId
    local imageId = data.imageId

    if not (lib and lib.callback and lib.callback.await) then
      return bad('ox_lib_missing')
    end

    local okk, res = pcall(function()
      return lib.callback.await('az_housing:cb:deleteHouseImage', 15000, houseId, imageId)
    end)

    if not okk then
      print(('[%s] deleteHouseImage callback error: %s'):format(RES, tostring(res)))
      return bad('callback_error')
    end

    cb(res or { ok=false, error='no_response' })
    return

  else
    return bad("unknown_action", { action = action })
  end
end)

end
