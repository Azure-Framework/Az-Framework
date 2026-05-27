AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.UI = AZH.UI or {}

local uiOpen = false
local currentHouseFocus = nil
local defaultTab = nil

local lastToggleLockAt = 0
local function canFireToggleLock()
  local now = GetGameTimer()
  if (now - (lastToggleLockAt or 0)) < 650 then return false end
  lastToggleLockAt = now
  return true
end

local function nui(msg)
  SendNUIMessage(msg)
end

local function setFocus(state, keepInput)
  uiOpen = state

  local keep = false
  SetNuiFocus(state, state)
  SetNuiFocusKeepInput(keep)

  if state then

    SetCursorLocation(0.5, 0.5)

    CreateThread(function()
      Wait(0)
      if uiOpen then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(keep)
      end
      Wait(100)
      if uiOpen then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(keep)
      end
    end)
  else

  end
end

AddEventHandler('onClientResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  CreateThread(function()
    Wait(50)
    uiOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    TriggerScreenblurFadeOut(0)
    SendNUIMessage({ type = 'azhousing_close' })
  end)
end)

local function sortById(a, b)
  return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
end
local function canonIdent(v)
  if v == nil then return nil end
  local s = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then return nil end
  if string.sub(s, 1, 5) == 'char:' then
    s = 'charid:' .. string.sub(s, 6)
  end
  return s
end
local function buildUiConfig()
  local cat = {}
  local srcCat = (Config and Config.Furniture and Config.Furniture.Catalog) or {}

  for i = 1, #srcCat do
    local it = srcCat[i]
    if it and it.model then
      cat[#cat+1] = {
        label = tostring(it.label or it.model),
        model = tostring(it.model),
      }
    end
  end

  local levels = (Config and Config.Upgrades and Config.Upgrades.Levels) or {}

  local function copyLevels(t)
    local out = {}
    t = t or {}
    for i = 1, #t do
      local row = {}
      for k, v in pairs(t[i] or {}) do row[k] = v end
      out[i] = row
    end
    return out
  end

  return {
    furnitureEnabled = (Config and Config.Furniture and Config.Furniture.Enabled ~= false) or false,
    furnitureCatalog = cat,
    allowCustomFurniture = (Config and Config.Furniture and Config.Furniture.AllowCustomModelForAdmins == true) or false,

    upgradesLevels = {
      mailbox = copyLevels(levels.mailbox),
      decor   = copyLevels(levels.decor),
      storage = copyLevels(levels.storage),
    },

    rentalDefaults = {
      rentPerWeek = (Config and Config.Defaults and tonumber(Config.Defaults.RentPerWeek)) or 0,
      deposit     = (Config and Config.Defaults and tonumber(Config.Defaults.Deposit)) or 0,
    }
  }
end

local function buildPayload()
  local houses = {}

  local owned, keys, myRentals = {}, {}, {}

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

  local myIdent = canonIdent(AZH.C.identifier)

  local rentalsArr = {}
  local rentalsByHouse = {}

  for hid, r in pairs(AZH.C.rentals or {}) do
    hid = tonumber(hid)
    if hid then
      rentalsArr[#rentalsArr+1] = r
      rentalsByHouse[tostring(hid)] = r

      local ten = canonIdent(r.tenant_identifier)
      if ten and (myIdSet[ten] or (myIdent and ten == myIdent)) then
        myRentals[tostring(hid)] = true
      end
    end
  end

  for hid, h in pairs(AZH.C.houses or {}) do
    hid = tonumber(hid)
    if hid and h then
      local hh = {}
      for k,v in pairs(h) do hh[k] = v end

      hh.owner_identifier = canonIdent(hh.owner_identifier)

      houses[#houses+1] = hh

      if hh.owner_identifier and (myIdSet[hh.owner_identifier] or (myIdent and hh.owner_identifier == myIdent)) then
        owned[tostring(hid)] = true
      end

      if AZH.C.keys and AZH.C.keys[hid] then
        keys[tostring(hid)] = AZH.C.keys[hid]
      end
    end
  end

  table.sort(houses, function(a,b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)

  local isAdmin = (AZH.C.isAdmin == true)
  local isAgentRole = (AZH.C.isAgentRole == true)
  local isAgent = false
  local agentHouseIds = {}

  for hidStr, _ in pairs(owned) do
    local r = rentalsByHouse[tostring(hidStr)]
    if r then
      local st = tostring(r.status or ''):lower()
      local listed = (r.is_listed == true) or (tonumber(r.is_listed) == 1)
      if st == 'listed' or st == 'available' or st == 'open' or st == 'active' then listed = true end

      local ten = canonIdent(r.tenant_identifier)
      local hasTenant = (ten ~= nil)

      if listed or hasTenant or st == 'leased' or st == 'rented' then
        isAgent = true
        agentHouseIds[#agentHouseIds+1] = tonumber(hidStr) or hidStr
      end
    end
  end

  if isAgentRole then
    isAgent = true
  end
  local apps = {}

  if (isAdmin or isAgentRole or isAgent) and lib and lib.callback and lib.callback.await then
    local ok, res = pcall(function()
      return lib.callback.await('az_housing:cb:getAgentApps', false)
    end)
    if ok and type(res) == 'table' then
      apps = res
    end
  end

  return {
    houses = houses,
    rentals = rentalsArr,
    rentalsByHouse = rentalsByHouse,
    owned = owned,
    keys = keys,
    myRentals = myRentals,

    isPolice = (AZH.isPolice and AZH.isPolice() == true) or false,
    isAdmin = isAdmin,
    isAgent = isAgent,

    identifier = myIdent,
    playerName = GetPlayerName(PlayerId()),

    uiConfig = buildUiConfig(),
  }
end

RegisterNetEvent('az_housing:client:openPortal', function(payload)
  AZH.UI.open(payload)
end)

RegisterNetEvent('az_housing:client:appsChanged', function()
  if AZH.UI and AZH.UI.isOpen() then
    AZH.UI.refresh()
  end
end)

RegisterNetEvent('az_housing:client:mailChanged', function(houseId)
  if uiOpen then
    nui({ type = 'mailChanged', houseId = tonumber(houseId) })
  end
end)

RegisterNetEvent('az_housing:client:upgradesChanged', function(houseId)
  if uiOpen then
    nui({ type = 'upgradesChanged', houseId = tonumber(houseId) })
  end
end)

AZH.UI.__nuiRegistered = true
RegisterNUICallback('nuiAction', function(payload, cb)
  payload = payload or {}
  local action = tostring(payload.action or '')
  local data = payload.data or {}

  if action == 'close' then
    AZH.UI.close()
    cb({ ok = true })
    return
  end

  if action == 'refresh' then
    local p = buildPayload()
    p.ok = true
    cb(p)
    return
  end

  local function okRefresh()
    AZH.UI.refresh()
    cb({ ok = true })
  end

  if action == 'enter' then
    TriggerServerEvent('az_housing:server:enter', data.houseId)
    cb({ ok = true })
    return
  end

  if action == 'knock' then
    TriggerServerEvent('az_housing:server:knock', data.houseId)
    cb({ ok = true })
    return
  end

  if action == 'breach' then
    TriggerServerEvent('az_housing:server:breach', data.houseId)
    cb({ ok = true })
    return
  end

  if action == 'toggleLock' then
    if canFireToggleLock() then
      TriggerServerEvent('az_housing:server:toggleLock', data.houseId)
    end
    okRefresh(); return
  end

  if action == 'buy' then
    TriggerServerEvent('az_housing:server:buy', data.houseId)
    okRefresh(); return
  end

  if action == 'sellToPlayer' then
    TriggerServerEvent('az_housing:server:sellToPlayer', data.houseId, data.targetSrc, data.price)
    okRefresh(); return
  end

  if action == 'listForRent' then
    TriggerServerEvent('az_housing:server:listForRent', data.houseId, data.rentPerWeek, data.deposit)
    okRefresh(); return
  end

  if action == 'unlistRent' then
    TriggerServerEvent('az_housing:server:unlistRent', data.houseId)
    okRefresh(); return
  end

  if action == 'rentToPlayer' then
    TriggerServerEvent('az_housing:server:rentToPlayer', data.houseId, data.targetSrc, data.rentPerWeek, data.deposit)
    okRefresh(); return
  end

  if action == 'endLease' then
    TriggerServerEvent('az_housing:server:endLease', data.houseId)
    okRefresh(); return
  end

  if action == 'applyRent' then
    TriggerServerEvent('az_housing:server:applyRent', data.houseId, data.message)
    okRefresh(); return
  end

  if action == 'agentDecide' then
    TriggerServerEvent('az_housing:server:agentDecide', data.appId, data.decision)
    okRefresh(); return
  end

  if action == 'addHouseImage' then
    local houseId = tonumber(data.houseId)
    local payloadIn = data.payload or {}

    cb({ ok = true, queued = true })

    CreateThread(function()
      local res = nil
      if lib and lib.callback and lib.callback.await then
        local ok, out = pcall(function()
          return lib.callback.await('az_housing:cb:addHouseImage', false, houseId, payloadIn)
        end)
        if ok then res = out end
      end

      SendNUIMessage({ type = 'imagesChanged', houseId = houseId, result = res })
      AZH.UI.refresh()
    end)
    return
  end

  if action == 'deleteHouseImage' then
    local houseId = tonumber(data.houseId)
    local imageId = tonumber(data.imageId)

    cb({ ok = true, queued = true })

    CreateThread(function()
      local res = nil
      if lib and lib.callback and lib.callback.await then
        local ok, out = pcall(function()
          return lib.callback.await('az_housing:cb:deleteHouseImage', false, houseId, imageId)
        end)
        if ok then res = out end
      end

      SendNUIMessage({ type = 'imagesChanged', houseId = houseId, result = res })
      AZH.UI.refresh()
    end)
    return
  end

  if action == 'loadHouseExtras' then
    local houseId = tonumber(data.houseId)

    local res = nil
    if lib and lib.callback and lib.callback.await then
      local ok, out = pcall(function()
        return lib.callback.await('az_housing:cb:loadHouseExtras', false, houseId)
      end)
      if ok then res = out end
    end

    cb(res or { ok = false, error = 'no_response' })
    return
  end

  if action == 'sendMail' then
    TriggerServerEvent('az_housing:server:sendMail', data.houseId, data.subject, data.body)
    cb({ ok = true })
    return
  end

  if action == 'deleteMail' then
    TriggerServerEvent('az_housing:server:deleteMail', data.houseId, data.mailId)
    cb({ ok = true })
    return
  end

  if action == 'markMailRead' then
    TriggerServerEvent('az_housing:server:mailMarkRead', data.houseId, data.mailId, data.isRead)
    cb({ ok = true })
    return
  end

  if action == 'buyUpgrade' then
    TriggerServerEvent('az_housing:server:buyUpgrade', data.houseId, data.upType)
    cb({ ok = true })
    return
  end

  if action == 'startFurnish' then
    local houseId = tonumber(data.houseId)
    local model = tostring(data.model or '')
    if AZH.Furniture and AZH.Furniture.place then
      AZH.UI.close()
      AZH.Furniture.place(houseId, model)
      cb({ ok = true })
    else
      cb({ ok = false, error = 'Furniture module missing' })
    end
    return
  end

  if action == 'removeFurniture' then
    TriggerServerEvent('az_housing:server:removeFurniture', data.houseId, data.furnId)
    cb({ ok = true })
    return
  end

  cb({ ok = false, error = 'Unknown action' })
end)

function AZH.UI.isOpen()
  return uiOpen == true
end

function AZH.UI.refresh()
  if not uiOpen then return end
  local p = buildPayload()
  p.houseFocus = currentHouseFocus
  p.defaultTab = defaultTab
  SendNUIMessage({ type = 'azhousing_update', payload = p })
end

function AZH.UI.open(payload)
  payload = payload or {}
  currentHouseFocus = tonumber(payload.houseId or payload.houseFocus) or currentHouseFocus
  defaultTab = payload.tab or payload.defaultTab or defaultTab

  local p = buildPayload()
  p.houseFocus = currentHouseFocus
  p.defaultTab = defaultTab

  setFocus(true)
  SendNUIMessage({ type = 'azhousing_open', payload = p })
end

function AZH.UI.close()
  if not uiOpen then

    SendNUIMessage({ type = 'azhousing_close' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    TriggerScreenblurFadeOut(0)
    return
  end
  setFocus(false)
  SendNUIMessage({ type = 'azhousing_close' })
end

CreateThread(function()
  while true do
    if uiOpen then
      DisableAllControlActions(0)
      EnableControlAction(0, 322, true)
      EnableControlAction(0, 200, true)
      if IsControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 322) then
        AZH.UI.close()
      end
      Wait(0)
    else
      Wait(500)
    end
  end
end)

RegisterNetEvent('az_housing:client:appsChanged', function()
  if uiOpen then AZH.UI.refresh() end
end)
