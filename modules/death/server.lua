local Config = (Config and Config.Death) or {}
if Config.Enabled == false then return end

local RESOURCE = GetCurrentResourceName()

Config = Config or {}
Config.Debug = Config.Debug ~= false

local function dprint(...)
  if not Config.Debug then return end
  local t = {}
  for i=1,select("#", ...) do t[#t+1] = tostring(select(i, ...)) end
  print(("^3[%s]^7 %s"):format(RESOURCE, table.concat(t, " ")))
end

local function notify(src, title, description, ntype)
  if GetResourceState('ox_lib') == 'started' then
    TriggerClientEvent('ox_lib:notify', src, {
      title = title,
      description = description,
      type = ntype or 'inform'
    })
  else
    TriggerClientEvent('chat:addMessage', src, {
      color = {255,255,255},
      args = { title or 'Az-Death', description or '' }
    })
  end
end

local injuriesBySrc = {}

local downedPlayers = {}
local downedLootBySrc = {}

local function distBetween(a, b)
  if not a or not b then return 9999.0 end
  local dx = (a.x or 0.0) - (b.x or 0.0)
  local dy = (a.y or 0.0) - (b.y or 0.0)
  local dz = (a.z or 0.0) - (b.z or 0.0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function weaponLabelFromName(name)
  local pretty = tostring(name or ''):gsub('WEAPON_', ''):gsub('_', ' '):lower()
  return (pretty:gsub('(%a)([%w]*)', function(a, b)
    return string.upper(a) .. b
  end))
end

local function fetchPlayerCash(src, cb)
  if GetResourceState('Az-Framework') ~= 'started' then return cb(0) end
  local ok = pcall(function()
    exports['Az-Framework']:GetPlayerMoney(src, function(a, b)
      local data = nil
      if type(a) == 'table' and type(b) ~= 'table' then
        data = a
      elseif type(b) == 'table' then
        data = b
      end
      cb(math.max(0, math.floor(tonumber((data and data.cash) or 0) or 0)))
    end)
  end)
  if not ok then cb(0) end
end

local function cleanupDownedLoot(src)
  src = tonumber(src or 0) or 0
  if src <= 0 then return end
  if downedLootBySrc[src] then
    TriggerClientEvent('Az-Death:client:removeDroppedWeaponObject', -1, src)
  end
  downedLootBySrc[src] = nil
end

local function setPlayerDownedState(src, state)
  src = tonumber(src or 0) or 0
  if src <= 0 then return end
  downedPlayers[src] = state == true
  local ply = Player(src)
  if ply and ply.state then
    ply.state:set('azDowned', state == true, true)
  end
end

local function sanitizeWeaponEntries(entries, handWeaponName)
  local out, seen = {}, {}
  if type(entries) ~= 'table' then return out end
  for _,entry in ipairs(entries) do
    local name = tostring((type(entry) == 'table' and entry.name) or '')
    if name ~= '' and not seen[name] then
      seen[name] = true
      out[name] = {
        name = name,
        ammo = math.max(0, math.floor(tonumber(entry.ammo) or 0)),
        label = weaponLabelFromName(name),
        inHand = (handWeaponName ~= nil and name == handWeaponName) or false,
      }
    end
  end
  return out
end

local function remainingLootCount(entry)
  local count = 0
  if not entry then return 0 end
  if tonumber(entry.cash or 0) > 0 then count = count + 1 end
  for _ in pairs(entry.weapons or {}) do count = count + 1 end
  return count
end

local function getLootEntryForInteraction(src, target)
  src = tonumber(src or 0) or 0
  target = tonumber(target or 0) or 0
  if src <= 0 or target <= 0 or src == target then return nil, 'invalid' end
  local entry = downedLootBySrc[target]
  if not entry then return nil, 'empty' end
  local srcPed = GetPlayerPed(src)
  local targetPed = GetPlayerPed(target)
  if srcPed == 0 or targetPed == 0 then return nil, 'missing_ped' end
  local a = GetEntityCoords(srcPed)
  local b = GetEntityCoords(targetPed)
  if distBetween(a, b) > (tonumber(Config.SearchDistance or 2.0) + 0.5) then return nil, 'too_far' end
  return entry
end

AddEventHandler("playerDropped", function()
  injuriesBySrc[source] = nil
  setPlayerDownedState(source, false)
  cleanupDownedLoot(source)
end)

RegisterNetEvent("Az-Death:injury:sync", function(state)
  local src = source
  if type(state) ~= "table" then return end
  injuriesBySrc[src] = state
  dprint("sync from", src)
end)

RegisterNetEvent('Az-Death:server:setDownedState', function(state)
  setPlayerDownedState(source, state == true)
  if state ~= true then
    cleanupDownedLoot(source)
  end
end)

RegisterNetEvent('Az-Death:server:clearDownedLoot', function()
  cleanupDownedLoot(source)
end)

RegisterNetEvent('Az-Death:server:registerDownedLoot', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  cleanupDownedLoot(src)
  local hand = type(payload.handWeapon) == 'table' and payload.handWeapon or nil
  local handWeaponName = hand and tostring(hand.name or '') or nil
  local coords = type(payload.coords) == 'table' and payload.coords or nil
  local heading = tonumber(payload.heading) or 0.0
  fetchPlayerCash(src, function(cash)
    downedLootBySrc[src] = {
      owner = src,
      cash = cash,
      coords = coords,
      heading = heading,
      handWeaponName = handWeaponName,
      weapons = sanitizeWeaponEntries(payload.weapons, handWeaponName),
      createdAt = os.time(),
    }
    if Config.DropWeaponOnDowned ~= false and handWeaponName and coords then
      TriggerClientEvent('Az-Death:client:createDroppedWeaponObject', -1, src, handWeaponName, tonumber(hand.ammo) or 0, coords, heading)
    end
  end)
end)

RegisterCommand("azinjuries_server", function(src)
  if src == 0 then return end
  TriggerClientEvent("Az-Death:ui:togglePinned", src)
end, false)

RegisterCommand("injclear", function(src, args)
  local target = tonumber(args[1] or "")
  if src == 0 then
    if target then
      injuriesBySrc[target] = {}
      TriggerClientEvent("Az-Death:injury:set", target, {})
      print("Cleared injuries for", target)
    end
    return
  end

  if target then
    injuriesBySrc[target] = {}
    TriggerClientEvent("Az-Death:injury:set", target, {})
  else
    injuriesBySrc[src] = {}
    TriggerClientEvent("Az-Death:injury:set", src, {})
  end
end, false)

local function hasAzFramework()
  return GetResourceState('Az-Framework') == 'started'
end

local function tryChargeAzFramework(src, amount, reason)
  if not hasAzFramework() or not amount or amount <= 0 then return true end

  local attempts = {
    function() return exports['Az-Framework']:removeMoney(src, 'bank', amount, reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:removeMoney(src, amount, 'bank', reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:removePlayerMoney(src, 'bank', amount, reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:removePlayerMoney(src, amount, 'bank', reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:deductMoney(src, 'bank', amount, reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:deductMoney(src, amount, reason or 'Hospital treatment') end,
  }

  for _,fn in ipairs(attempts) do
    local ok, res = pcall(fn)
    if ok then
      if res == nil or res == true or res == 1 then return true end
      if type(res) == 'table' and (res.success == true or res.ok == true) then return true end
    end
  end

  return false
end

if lib and lib.callback then
  lib.callback.register('Az-Death:server:billHospital', function(source, kind)
    local amount = ((Config.Hospital or {}).VisitHealCost or 250)
    if tostring(kind) == 'checkin' then
      amount = ((Config.Hospital or {}).CheckInCost or 500)
    end

    if hasAzFramework() then
      local ok = tryChargeAzFramework(source, amount, 'Az-Death hospital treatment')
      if not ok then
        return false, ('You need $%s in the bank for treatment.'):format(amount)
      end
      return true, ('Charged $%s for treatment.'):format(amount)
    end

    return true, nil
  end)
end

local function playerHasMedPerm(src)
  local ok, job = pcall(function()
    return exports['Az-Framework']:getPlayerJob(src)
  end)
  if not ok then return false end
  for _,department in pairs(Config.MedDept or Config.EMSJobs or {}) do
    if job == department then return true end
  end
  return false
end

if lib and lib.callback then
  lib.callback.register('Az-Death:server:getDownedLoot', function(source, target)
    local entry, reason = getLootEntryForInteraction(source, target)
    if not entry then return nil end
    local weapons = {}
    for _,weapon in pairs(entry.weapons or {}) do
      weapons[#weapons+1] = {
        name = weapon.name,
        label = weapon.label,
        ammo = weapon.ammo,
        inHand = weapon.inHand == true,
      }
    end
    table.sort(weapons, function(a, b)
      if a.inHand ~= b.inHand then return a.inHand == true end
      return tostring(a.label or a.name) < tostring(b.label or b.name)
    end)
    return {
      title = 'Search Body',
      cash = math.max(0, math.floor(tonumber(entry.cash or 0) or 0)),
      weapons = weapons,
    }
  end)
end

RegisterNetEvent('Az-Death:server:lootCash', function(target)
  local src = source
  local entry = getLootEntryForInteraction(src, target)
  if not entry then
    notify(src, 'Search Body', 'There is no cash to take.', 'error')
    return
  end
  local amount = math.max(0, math.floor(tonumber(entry.cash or 0) or 0))
  if amount <= 0 then
    notify(src, 'Search Body', 'There is no cash to take.', 'error')
    return
  end
  fetchPlayerCash(target, function(currentCash)
    local payout = math.min(amount, math.max(0, math.floor(tonumber(currentCash) or 0)))
    if payout <= 0 then
      entry.cash = 0
      notify(src, 'Search Body', 'There is no cash left to take.', 'error')
      return
    end
    pcall(function() exports['Az-Framework']:deductMoney(target, payout) end)
    pcall(function() exports['Az-Framework']:addMoney(src, payout) end)
    entry.cash = 0
    notify(src, 'Search Body', ('You took $%s in cash.'):format(payout), 'success')
    notify(target, 'Search Body', ('Someone took $%s from your body.'):format(payout), 'error')
    if remainingLootCount(entry) <= 0 then
      cleanupDownedLoot(target)
    end
  end)
end)

RegisterNetEvent('Az-Death:server:lootWeapon', function(target, weaponName)
  local src = source
  local entry = getLootEntryForInteraction(src, target)
  if not entry then
    notify(src, 'Search Body', 'There is nothing to take.', 'error')
    return
  end
  weaponName = tostring(weaponName or '')
  local weapon = entry.weapons and entry.weapons[weaponName] or nil
  if not weapon then
    notify(src, 'Search Body', 'That weapon is no longer there.', 'error')
    return
  end
  TriggerClientEvent('Az-Death:client:receiveLootWeapon', src, weapon.name, weapon.ammo)
  TriggerClientEvent('Az-Death:client:stripLootWeapon', target, weapon.name)
  if entry.handWeaponName and entry.handWeaponName == weapon.name then
    TriggerClientEvent('Az-Death:client:removeDroppedWeaponObject', -1, target)
    entry.handWeaponName = nil
  end
  entry.weapons[weaponName] = nil
  notify(src, 'Search Body', ('You took %s.'):format(weapon.label or weapon.name), 'success')
  notify(target, 'Search Body', ('Someone took your %s.'):format(weapon.label or weapon.name), 'error')
  if remainingLootCount(entry) <= 0 then
    cleanupDownedLoot(target)
  end
end)

RegisterNetEvent('Az-Death:server:transportNearestPlayer', function(target)
  local src = source
  target = tonumber(target or '')
  if not target or GetPlayerPed(target) == 0 then
    notify(src, 'Hospital Transport', 'Invalid target player.', 'error')
    return
  end
  if not playerHasMedPerm(src) then
    notify(src, 'Hospital Transport', 'You do not have permission to transport patients.', 'error')
    return
  end

  local srcPed = GetPlayerPed(src)
  local targetPed = GetPlayerPed(target)
  if srcPed == 0 or targetPed == 0 then
    notify(src, 'Hospital Transport', 'Unable to find both players.', 'error')
    return
  end

  local a = GetEntityCoords(srcPed)
  local b = GetEntityCoords(targetPed)
  local dx,dy,dz = a.x-b.x, a.y-b.y, a.z-b.z
  local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
  if dist > 3.0 then
    notify(src, 'Hospital Transport', 'Move closer to the patient.', 'error')
    return
  end

  TriggerClientEvent('Az-Death:client:transportToHospital', target, 'EMS transport')
  notify(src, 'Hospital Transport', ('You transported player %s to the hospital.'):format(target), 'success')
end)

RegisterCommand('takehospital', function(src, args)
  if src == 0 then return end
  if not playerHasMedPerm(src) then
    notify(src, 'Hospital Transport', 'You do not have permission to use /takehospital.', 'error')
    return
  end

  local target = tonumber(args[1] or '')
  if not target or GetPlayerPed(target) == 0 then
    notify(src, 'Hospital Transport', 'Invalid target player ID.', 'error')
    return
  end

  TriggerClientEvent('Az-Death:client:transportToHospital', target, 'EMS transport')
  notify(src, 'Hospital Transport', ('You transported player %s to the hospital.'):format(target), 'success')
end, false)

RegisterNetEvent('Az-Death:server:startDragPlayer', function(target)
  local src = source
  target = tonumber(target or 0) or 0
  if src <= 0 or target <= 0 or src == target then return end

  local srcPed = GetPlayerPed(src)
  local targetPed = GetPlayerPed(target)
  if srcPed == 0 or targetPed == 0 then
    notify(src, 'Drag Body', 'Unable to find that player.', 'error')
    TriggerClientEvent('Az-Death:client:dragStartFailed', src)
    return
  end

  local maxDistance = tonumber(((Config.Drag or {}).Distance or 2.0)) or 2.0
  local a = GetEntityCoords(srcPed)
  local b = GetEntityCoords(targetPed)
  if distBetween(a, b) > (maxDistance + 0.75) then
    notify(src, 'Drag Body', 'Move closer to drag the body.', 'error')
    TriggerClientEvent('Az-Death:client:dragStartFailed', src)
    return
  end

  if downedPlayers[target] ~= true then
    notify(src, 'Drag Body', 'That player is not downed.', 'error')
    TriggerClientEvent('Az-Death:client:dragStartFailed', src)
    return
  end

  TriggerClientEvent('Az-Death:client:beginDragged', target, src)
end)

RegisterNetEvent('Az-Death:server:stopDragPlayer', function(target)
  local src = source
  target = tonumber(target or 0) or 0
  if src <= 0 or target <= 0 or src == target then return end
  TriggerClientEvent('Az-Death:client:endDragged', target, src)
end)

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  print('^3[Az-Framework]^7 death/server.lua loaded (hotfix v4b)')
end)

RegisterNetEvent('Az-Death:server:probeLog', function(msg)
  print(('^5[%s PROBE]^7 [%s] %s'):format(RESOURCE, tostring(source), tostring(msg or '')))
end)
