Config = Config or {}
Config.FrameworkBridge = Config.FrameworkBridge or {}
if Config.FrameworkBridge.Enabled == false then return end

local metadataBySource = {}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end

  local out = {}
  seen[value] = out
  for k, v in pairs(value) do
    out[copy(k, seen)] = copy(v, seen)
  end
  return out
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function queryAwait(sql, params)
  if MySQL and MySQL.query and type(MySQL.query.await) == "function" then
    local ok, rows = pcall(MySQL.query.await, sql, params or {})
    if ok and type(rows) == "table" then return rows end
  end
  return {}
end

local function scalarAwait(sql, params)
  if MySQL and MySQL.scalar and type(MySQL.scalar.await) == "function" then
    local ok, value = pcall(MySQL.scalar.await, sql, params or {})
    if ok then return value end
  end
  local rows = queryAwait(sql, params)
  if rows[1] then
    for _, value in pairs(rows[1]) do return value end
  end
  return nil
end

local function updateAwait(sql, params)
  if MySQL and MySQL.update and type(MySQL.update.await) == "function" then
    local ok, affected = pcall(MySQL.update.await, sql, params or {})
    if ok then return tonumber(affected) or 0 end
  end
  return 0
end

local function framework()
  return exports["Az-Framework"]
end

local function callFrameworkExport(exportName, ...)
  local fw = framework()
  if not fw then return nil, "framework_missing" end

  local okFn, fn = pcall(function() return fw[exportName] end)
  if not okFn or type(fn) ~= "function" then return nil, "missing_export" end

  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end

  ok, a, b, c = pcall(fn, fw, ...)
  if ok then return a, b, c end

  return nil, tostring(a or "export_call_failed")
end

local function splitName(fullName)
  fullName = trim(fullName)
  if fullName == "" then return "Unknown", "Player" end

  local first, last = fullName:match("^(%S+)%s+(.+)$")
  return first or fullName, last or ""
end

local function getIdentifiers(src)
  local out = {}
  for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
    local prefix, value = tostring(identifier):match("^([^:]+):(.+)$")
    if prefix and value and out[prefix] == nil then
      out[prefix] = value
    end
  end
  return out
end

local function getDiscordIdentifier(src)
  local discordId = trim(callFrameworkExport("getDiscordID", src) or callFrameworkExport("GetDiscordID", src) or "")
  discordId = discordId:gsub("^discord:", "")
  if discordId ~= "" then return discordId end

  local identifiers = getIdentifiers(src)
  discordId = trim(identifiers.discord or ""):gsub("^discord:", "")
  if discordId ~= "" then return discordId end

  for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
    local value = tostring(identifier or "")
    if value:sub(1, 8) == "discord:" then
      return trim(value:sub(9))
    end
  end

  return ""
end

local function getCharacterContext(src)
  src = tonumber(src or 0) or 0
  if src <= 0 or GetPlayerName(src) == nil then return nil end

  local discordId = getDiscordIdentifier(src)

  local charId = callFrameworkExport("GetActiveCharacter", src)
    or callFrameworkExport("getActiveCharacter", src)
    or callFrameworkExport("GetCharacter", src)
    or callFrameworkExport("GetPlayerCharacter", src)

  if (not charId or tostring(charId) == "") and discordId ~= "" then
    local rows = queryAwait("SELECT charid FROM user_characters WHERE discordid=? LIMIT 2", { discordId })
    if rows and #rows == 1 and rows[1] and rows[1].charid then
      charId = rows[1].charid
    end
  end

  if not charId or tostring(charId) == "" then return nil end

  return {
    source = src,
    discordId = discordId,
    charId = tostring(charId),
  }
end

local function readMoney(discordId, charId)
  discordId = trim(discordId):gsub("^discord:", "")
  charId = trim(charId)

  local rows = {}
  if discordId ~= "" and charId ~= "" then
    rows = queryAwait(
      "SELECT cash, bank FROM econ_user_money WHERE discordid=? AND charid=? LIMIT 1",
      { discordId, charId }
    )
  end

  if (not rows[1]) and charId ~= "" then
    rows = queryAwait(
      "SELECT cash, bank FROM econ_user_money WHERE charid=? LIMIT 1",
      { charId }
    )
  end

  local row = rows[1] or {}
  return tonumber(row.cash) or 0, tonumber(row.bank) or 0
end

local function readCharacterName(discordId, charId)
  discordId = trim(discordId):gsub("^discord:", "")
  charId = trim(charId)

  local name
  if discordId ~= "" and charId ~= "" then
    name = scalarAwait(
      "SELECT name FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
      { discordId, charId }
    )
  end

  if trim(name) == "" and charId ~= "" then
    name = scalarAwait(
      "SELECT name FROM user_characters WHERE charid=? LIMIT 1",
      { charId }
    )
  end

  return trim(name)
end

local function syncMoneyHud(src)
  local ok, fn = pcall(function() return framework().sendMoneyToClient end)
  if ok and type(fn) == "function" then
    pcall(fn, framework(), src, true)
  end

  local ctx = getCharacterContext(src)
  if not ctx then return end

  local cash, bank = readMoney(ctx.discordId, ctx.charId)
  local name = readCharacterName(ctx.discordId, ctx.charId)
  if name == "" then name = tostring(GetPlayerName(ctx.source) or "") end
  TriggerClientEvent("updateCashHUD", ctx.source, cash, bank, name)
end

local function writeCash(discordId, charId, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  updateAwait(
    "UPDATE econ_user_money SET cash=? WHERE discordid=? AND charid=?",
    { amount, discordId, charId }
  )
  return amount
end

local function writeBank(discordId, charId, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  updateAwait(
    "UPDATE econ_user_money SET bank=? WHERE discordid=? AND charid=?",
    { amount, discordId, charId }
  )
  updateAwait(
    "UPDATE econ_accounts SET balance=? WHERE discordid=? AND charid=? AND type='checking'",
    { amount, discordId, charId }
  )
  return amount
end

local function getJobLabel(jobName)
  jobName = trim(jobName)
  if jobName == "" then return "Unemployed" end

  local configured = callFrameworkExport("getConfiguredDepartments") or {}
  for _, row in ipairs(configured or {}) do
    if tostring(row.id or ""):lower() == jobName:lower() then
      return tostring(row.label or row.id or jobName)
    end
  end

  return jobName
end

local function getSnapshot(src)
  local ctx = getCharacterContext(src)
  if not ctx then return nil end

  local fw = framework()
  local name = select(1, callFrameworkExport("GetPlayerCharacterNameSync", ctx.source))
  name = trim(name)
  if name == "" or name:lower() == tostring(GetPlayerName(ctx.source) or ""):lower() then
    local dbName = readCharacterName(ctx.discordId, ctx.charId)
    if dbName ~= "" then name = dbName end
  end
  if name == "" then
    name = tostring(GetPlayerName(ctx.source) or "Unknown Player")
  end

  local firstName, lastName = splitName(name)
  local cash, bank = readMoney(ctx.discordId, ctx.charId)
  local jobName = trim(scalarAwait("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { ctx.discordId, ctx.charId }) or ""):lower()
  if jobName == "" then
    jobName = tostring(callFrameworkExport("getPlayerJob", ctx.source) or ""):lower()
  end
  local identifiers = getIdentifiers(ctx.source)
  local metadata = copy(metadataBySource[ctx.source] or {})

  return {
    source = ctx.source,
    identifier = (ctx.discordId ~= "" and ("az:" .. ctx.discordId .. ":" .. ctx.charId)) or ("azchar:" .. ctx.charId),
    license = identifiers.license,
    identifiers = identifiers,
    discordid = ctx.discordId,
    citizenid = ctx.charId,
    charid = ctx.charId,
    name = name,
    firstname = firstName,
    lastname = lastName,
    fullname = name,
    cash = cash,
    bank = bank,
    money = {
      cash = cash,
      bank = bank,
      crypto = 0,
    },
    job = jobName ~= "" and jobName or "unemployed",
    jobInfo = {
      name = jobName ~= "" and jobName or "unemployed",
      label = getJobLabel(jobName),
      rank = 0,
      rankName = "Member",
      onduty = jobName ~= "",
    },
    metadata = metadata,
  }
end

local function getAccountKey(account)
  account = tostring(account or "cash"):lower()
  if account == "money" or account == "cash" then return "cash" end
  if account == "bank" then return "bank" end
  return nil
end

local function addMoney(src, account, amount)
  local accountKey = getAccountKey(account)
  amount = math.floor(tonumber(amount) or 0)
  if not accountKey or amount <= 0 then return false end

  local ctx = getCharacterContext(src)
  if not ctx then return false end

  if accountKey == "cash" then
    local cash = select(1, readMoney(ctx.discordId, ctx.charId))
    writeCash(ctx.discordId, ctx.charId, cash + amount)
    syncMoneyHud(ctx.source)
    TriggerEvent("Az-Framework:Bridge:moneyChanged", ctx.source, accountKey, amount, "add")
    return true
  end

  if not ctx then return false end
  local _, bank = readMoney(ctx.discordId, ctx.charId)
  writeBank(ctx.discordId, ctx.charId, bank + amount)
  syncMoneyHud(ctx.source)
  TriggerEvent("Az-Framework:Bridge:moneyChanged", ctx.source, accountKey, amount, "add")
  return true
end

local function removeMoney(src, account, amount)
  local accountKey = getAccountKey(account)
  amount = math.floor(tonumber(amount) or 0)
  if not accountKey or amount <= 0 then return false end

  local ctx = getCharacterContext(src)
  if not ctx then return false end

  if accountKey == "cash" then
    local cash = select(1, readMoney(ctx.discordId, ctx.charId))
    if cash < amount then return false end
    writeCash(ctx.discordId, ctx.charId, cash - amount)
    syncMoneyHud(ctx.source)
    TriggerEvent("Az-Framework:Bridge:moneyChanged", ctx.source, accountKey, amount, "remove")
    return true
  end

  local _, bank = readMoney(ctx.discordId, ctx.charId)
  if bank < amount then return false end
  writeBank(ctx.discordId, ctx.charId, bank - amount)
  syncMoneyHud(ctx.source)
  TriggerEvent("Az-Framework:Bridge:moneyChanged", ctx.source, accountKey, amount, "remove")
  return true
end

local function setMoney(src, account, amount)
  local accountKey = getAccountKey(account)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if not accountKey then return false end

  local ctx = getCharacterContext(src)
  if not ctx then return false end

  if accountKey == "cash" then
    writeCash(ctx.discordId, ctx.charId, amount)
  else
    writeBank(ctx.discordId, ctx.charId, amount)
  end
  syncMoneyHud(ctx.source)

  TriggerEvent("Az-Framework:Bridge:moneyChanged", ctx.source, accountKey, amount, "set")
  return true
end

local function getMoney(src, account)
  local ctx = getCharacterContext(src)
  if not ctx then return 0 end

  local cash, bank = readMoney(ctx.discordId, ctx.charId)
  local accountKey = getAccountKey(account)
  if accountKey == "bank" then return bank end
  return cash
end

local function setMetadata(src, key, value)
  src = tonumber(src or 0) or 0
  key = tostring(key or "")
  if src <= 0 or key == "" then return false end

  metadataBySource[src] = metadataBySource[src] or {}
  metadataBySource[src][key] = value
  TriggerClientEvent("Az-Framework:Bridge:MetadataUpdated", src, copy(metadataBySource[src]))
  return true
end

local function getMetadata(src, key)
  src = tonumber(src or 0) or 0
  if src <= 0 then return nil end

  local metadata = metadataBySource[src] or {}
  if key == nil then return copy(metadata) end
  return copy(metadata[tostring(key)])
end

local function notify(src, message, ntype, duration)
  src = tonumber(src or 0) or 0
  if src <= 0 then return false end

  TriggerClientEvent("ox_lib:notify", src, {
    title = "Notification",
    description = tostring(message or ""),
    type = tostring(ntype or "inform"),
    duration = tonumber(duration) or 5000,
  })
  return true
end

local function inventoryResources()
  local preferred = tostring(Config.FrameworkBridge.InventoryResource or "auto")
  local out = {}

  local function add(resourceName)
    if not resourceName or resourceName == "" then return end
    for _, existing in ipairs(out) do
      if existing == resourceName then return end
    end
    out[#out + 1] = resourceName
  end

  if preferred ~= "auto" then add(preferred) end
  add("ox_inventory")
  add("qb-inventory")
  add("Az-Inventory")
  add("Az-Framework")

  return out
end

local function inventoryDebug(...)
  if Config.FrameworkBridge.InventoryDebug == true then
    print("^3[Az-Framework][InventoryBridge]^7", ...)
  end
end

local function callResourceExport(resourceName, exportName, ...)
  if GetResourceState(resourceName) ~= "started" then
    return nil, "not_started"
  end

  local okExports, resourceExports = pcall(function() return exports[resourceName] end)
  if not okExports or not resourceExports then
    return nil, "exports_unavailable"
  end

  local okFn, fn = pcall(function() return resourceExports[exportName] end)
  if not okFn or type(fn) ~= "function" then
    return nil, "missing_export"
  end

  local okCall, a, b, c = pcall(fn, ...)
  if okCall then return a, b, c end

  okCall, a, b, c = pcall(fn, resourceExports, ...)
  if okCall then return a, b, c end

  return nil, tostring(a or "export_call_failed")
end

local function firstInventoryExport(exportName, ...)
  for _, resourceName in ipairs(inventoryResources()) do
    local result, err, extra = callResourceExport(resourceName, exportName, ...)
    if result ~= nil then
      inventoryDebug("export ok", resourceName, exportName)
      return result, err, extra, resourceName
    end
    inventoryDebug("export skipped", resourceName, exportName, err)
  end
  return nil
end

local function copyItem(value, seen)
  return copy(value, seen)
end

local function normalizeItem(item)
  if type(item) ~= "table" then return item end

  local out = copyItem(item)
  out.name = tostring(out.name or out.item or "")
  out.count = tonumber(out.count or out.amount or out.quantity or 0) or 0
  out.amount = out.count
  out.info = copyItem(out.info or out.metadata or {})
  out.metadata = copyItem(out.metadata or out.info or {})
  out.type = out.type or "item"
  return out
end

local function getItemCount(src, item, metadata)
  src = tonumber(src or 0) or src
  if not src or src == 0 or not item then return 0 end

  local count = firstInventoryExport("GetItemCount", src, item, metadata)
  if count ~= nil then return tonumber(count) or 0 end

  count = firstInventoryExport("Search", src, "count", item, metadata)
  if count ~= nil then return tonumber(count) or 0 end

  local qbItem = firstInventoryExport("GetItemByName", src, item)
  if type(qbItem) == "table" then return tonumber(qbItem.amount or qbItem.count) or 0 end

  return 0
end

local function hasItem(src, item, amount)
  amount = math.max(1, math.floor(tonumber(amount) or 1))

  if type(item) == "table" then
    local isKeyed = false
    for k in pairs(item) do
      if type(k) ~= "number" then isKeyed = true break end
    end

    if isKeyed then
      for itemName, needed in pairs(item) do
        if getItemCount(src, itemName) < (tonumber(needed) or 1) then return false end
      end
      return true
    end

    for _, itemName in pairs(item) do
      if getItemCount(src, itemName) < amount then return false end
    end
    return true
  end

  return getItemCount(src, item) >= amount
end

local function getItem(src, item, metadata)
  src = tonumber(src or 0) or src
  if not src or src == 0 or not item then return nil end

  local found = firstInventoryExport("GetItem", src, item, metadata, false)
  if type(found) == "table" and (tonumber(found.count or found.amount) or 0) > 0 then
    return normalizeItem(found)
  end

  found = firstInventoryExport("GetItemByName", src, item)
  if type(found) == "table" then return normalizeItem(found) end

  local slots = firstInventoryExport("Search", src, "slots", item, metadata)
  if type(slots) == "table" then
    for _, slotData in pairs(slots) do
      if type(slotData) == "table" then return normalizeItem(slotData) end
    end
  end

  return nil
end

local function addItem(src, item, count, metadata, slot)
  src = tonumber(src or 0) or src
  count = math.max(1, math.floor(tonumber(count) or 1))
  if not src or src == 0 or not item then return false end
  if slot == false then slot = nil end
  if metadata == false then metadata = nil end

  for _, resourceName in ipairs(inventoryResources()) do
    if resourceName == "ox_inventory" then
      local ok, response = callResourceExport(resourceName, "AddItem", src, item, count, metadata, slot)
      if ok ~= nil then inventoryDebug("AddItem ox", ok, response) return ok == true end
    elseif resourceName == "qb-inventory" or resourceName == "Az-Inventory" then
      local ok, response = callResourceExport(resourceName, "AddItem", src, item, count, slot or false, metadata or false, "Az-Framework bridge")
      if ok ~= nil then inventoryDebug("AddItem qb", ok, response) return ok == true end
    elseif resourceName == "Az-Framework" and resourceName ~= GetCurrentResourceName() then
      local ok = callResourceExport(resourceName, "AddBridgeItem", src, item, count, metadata, slot)
      if ok ~= nil then return ok == true end
    end
  end

  return false
end

local function removeItem(src, item, count, metadata, slot)
  src = tonumber(src or 0) or src
  count = math.max(1, math.floor(tonumber(count) or 1))
  if not src or src == 0 or not item then return false end
  if slot == false then slot = nil end
  if metadata == false then metadata = nil end

  for _, resourceName in ipairs(inventoryResources()) do
    if resourceName == "ox_inventory" then
      local ok, response = callResourceExport(resourceName, "RemoveItem", src, item, count, metadata, slot)
      if ok ~= nil then inventoryDebug("RemoveItem ox", ok, response) return ok == true end
    elseif resourceName == "qb-inventory" or resourceName == "Az-Inventory" then
      local ok, response = callResourceExport(resourceName, "RemoveItem", src, item, count, slot or false, "Az-Framework bridge")
      if ok ~= nil then inventoryDebug("RemoveItem qb", ok, response) return ok == true end
    elseif resourceName == "Az-Framework" and resourceName ~= GetCurrentResourceName() then
      local ok = callResourceExport(resourceName, "RemoveBridgeItem", src, item, count, metadata, slot)
      if ok ~= nil then return ok == true end
    end
  end

  return false
end

local function getPlayers(key, value, returnArray)
  local players = returnArray == true and {} or {}
  for _, playerId in ipairs(GetPlayers() or {}) do
    local snapshot = getSnapshot(tonumber(playerId))
    if snapshot then
      local matches = true
      if key ~= nil then
        matches = snapshot[key] == value
        if not matches and key == "job" then
          matches = snapshot.job == value or snapshot.jobInfo.name == value
        end
      end

      if matches then
        if returnArray == true then
          players[#players + 1] = snapshot
        else
          players[snapshot.source] = snapshot
        end
      end
    end
  end
  return players
end

RegisterNetEvent("Az-Framework:Bridge:RequestSnapshot", function()
  local src = source
  TriggerClientEvent("Az-Framework:Bridge:Snapshot", src, getSnapshot(src))
end)

RegisterNetEvent("Az-Framework:Bridge:SetMetadata", function(key, value)
  setMetadata(source, key, value)
end)

AddEventHandler("Az-Framework:jobChanged", function(changedSrc)
  local src = tonumber(changedSrc) or tonumber(source)
  if not src or src <= 0 then return end
  TriggerClientEvent("Az-Framework:Bridge:Snapshot", src, getSnapshot(src))
end)

AddEventHandler("Az-Framework:characterSelected", function(changedSrc)
  local src = tonumber(changedSrc) or tonumber(source)
  if not src or src <= 0 then return end
  TriggerClientEvent("Az-Framework:Bridge:Snapshot", src, getSnapshot(src))
end)

AddEventHandler("Az-Framework:Bridge:characterSelected", function(changedSrc)
  local src = tonumber(changedSrc) or tonumber(source)
  if not src or src <= 0 then return end
  TriggerClientEvent("Az-Framework:Bridge:Snapshot", src, getSnapshot(src))
end)

AddEventHandler("playerDropped", function()
  metadataBySource[source] = nil
end)

_G.AzBridgeServerExports = {
  GetBridgePlayerSnapshot = getSnapshot,
  GetBridgePlayers = getPlayers,
  GetBridgeMoney = getMoney,
  AddBridgeMoney = addMoney,
  RemoveBridgeMoney = removeMoney,
  SetBridgeMoney = setMoney,
  GetBridgeMetadata = getMetadata,
  SetBridgeMetadata = setMetadata,
  BridgeNotify = notify,
  GetBridgeItemCount = getItemCount,
  HasBridgeItem = hasItem,
  GetBridgeItem = getItem,
  AddBridgeItem = addItem,
  RemoveBridgeItem = removeItem,
}
