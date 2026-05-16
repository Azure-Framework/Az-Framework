local RESOURCE_NAME = GetCurrentResourceName()
local json = json

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

local function syncAppearanceCustomizationConvar()
  local on = (Config and Config.UseAppearance == true) and 1 or 0
  ExecuteCommand(("setr fivem-appearance:customization %d"):format(on))
  print(("[Az-CharacterUI] setr fivem-appearance:customization %d (Config.UseAppearance=%s)"):format(on, tostring(Config and Config.UseAppearance)))
end

AddEventHandler("onResourceStart", function(res)

  if res == RESOURCE_NAME then
    syncAppearanceCustomizationConvar()

    CreateThread(function()
      Wait(1500)
      for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        if src and GetPlayerName(src) then

          TriggerEvent("__azfw_internal:adminWarmup", src, "resourceStart")
        end
      end
    end)
  end

  if res == "fivem-appearance" or res == "five-appearance" or res == "fiveappearance" then
    Wait(250)
    syncAppearanceCustomizationConvar()
  end
end)

AddEventHandler("onResourceStop", function(res)
  if res == RESOURCE_NAME then
    ExecuteCommand("setr fivem-appearance:customization 0")
  end
end)

local fw = exports["Az-Framework"]

Config.Debug = (Config.Debug ~= false)
local DEBUG = Config.Debug

Config.EnableLastLocation   = (Config.EnableLastLocation ~= false)
Config.EnableFiveAppearance = (Config.EnableFiveAppearance ~= false)

Config.SpawnFile  = Config.SpawnFile or "spawns.json"
Config.MapBounds  = Config.MapBounds or { minX = -3000, maxX = 3000, minY = -6300, maxY = 7000 }

Config.RequireAzAdminForEdit = (Config.RequireAzAdminForEdit == true)
Config.AdminAcePermission    = Config.AdminAcePermission or "azfw.spawns.edit"
Config.SpawnMenuCommand      = Config.SpawnMenuCommand or "spawnmenu"

Config.StartingCash = tonumber(Config.StartingCash) or 0

Config.Housing = Config.Housing or {}
Config.Housing.Enabled = (Config.Housing.Enabled ~= false)

Config.Housing.Table       = tostring(Config.Housing.Table or "az_houses")
Config.Housing.OwnerColumn = tostring(Config.Housing.OwnerColumn or "owner_identifier")

Config.Housing.DoorsTable        = tostring(Config.Housing.DoorsTable or "az_house_doors")
Config.Housing.EnableHomePill    = (Config.Housing.EnableHomePill ~= false)
Config.Housing.EnableHomeSpawn   = (Config.Housing.EnableHomeSpawn ~= false)
Config.Housing.HomeSpawnLocked   = (Config.Housing.HomeSpawnLocked == true)

Config.Housing.ShowInCharacterUI = (Config.Housing.EnableHomePill ~= false)
Config.Housing.ShowAsSpawnOption = (Config.Housing.EnableHomeSpawn ~= false)

Config.Housing.SpawnCoordsByInterior = Config.Housing.SpawnCoordsByInterior or Config.Housing.InteriorSpawns or {}
Config.Housing.FallbackSpawn         = Config.Housing.FallbackSpawn or { x = 215.76, y = -810.12, z = 30.73, h = 157.0 }

local __AZFW_ACTIVE_STORE = rawget(_G, "__AZFW_ACTIVE_CHARACTER_STORE")
if type(__AZFW_ACTIVE_STORE) ~= "table" then
  __AZFW_ACTIVE_STORE = { bySource = {}, byDiscord = {}, updated = {}, reason = {} }
  rawset(_G, "__AZFW_ACTIVE_CHARACTER_STORE", __AZFW_ACTIVE_STORE)
end
__AZFW_ACTIVE_STORE.bySource = __AZFW_ACTIVE_STORE.bySource or {}
__AZFW_ACTIVE_STORE.byDiscord = __AZFW_ACTIVE_STORE.byDiscord or {}
__AZFW_ACTIVE_STORE.updated = __AZFW_ACTIVE_STORE.updated or {}
__AZFW_ACTIVE_STORE.reason = __AZFW_ACTIVE_STORE.reason or {}

local function __azfwSourceKey(src)
  local n = tonumber(src)
  if n and n > 0 then return tostring(math.floor(n)) end
  return tostring(src or "")
end

local function __azfwDiscordKey(did)
  return tostring(did or ""):gsub("^discord:", "")
end

local function __azfwActiveSourceProxy()
  local localStore = {}
  return setmetatable({}, {
    __index = function(_, k)
      local key = __azfwSourceKey(k)
      if key == "" then return nil end
      return __AZFW_ACTIVE_STORE.bySource[key] or localStore[key]
    end,
    __newindex = function(_, k, v)
      local key = __azfwSourceKey(k)
      if key == "" then return end
      if v == nil or tostring(v) == "" then
        __AZFW_ACTIVE_STORE.bySource[key] = nil
        localStore[key] = nil
        __AZFW_ACTIVE_STORE.reason[key] = nil
        __AZFW_ACTIVE_STORE.updated[key] = os.time()
        return
      end
      local value = tostring(v)
      __AZFW_ACTIVE_STORE.bySource[key] = value
      localStore[key] = value
      __AZFW_ACTIVE_STORE.updated[key] = os.time()
    end,
    __pairs = function() return next, (__AZFW_ACTIVE_STORE.bySource or {}), nil end
  })
end

local activeCharacters = __azfwActiveSourceProxy()

local function setUiActiveCharacter(src, did, charid, reason)
  src = tonumber(src or 0) or 0
  local cid = tostring(charid or "")
  if src <= 0 or cid == "" then return false end

  activeCharacters[src] = cid
  if Player and Player(src) and Player(src).state then
    Player(src).state:set("az_active_character", cid, true)
    Player(src).state:set("az_active_charid", cid, true)
    Player(src).state:set("activeCharacter", cid, true)
    Player(src).state:set("charid", cid, true)
  end
  TriggerEvent("vMenu-Bridge:setActiveCharacter", src, cid)
  did = __azfwDiscordKey(did)
  if did ~= "" then
    __AZFW_ACTIVE_STORE.byDiscord[did] = cid
  end

  local sk = __azfwSourceKey(src)
  __AZFW_ACTIVE_STORE.reason[sk] = tostring(reason or "characterui")
  __AZFW_ACTIVE_STORE.updated[sk] = os.time()
  return true
end

local function clearUiActiveCharacter(src)
  src = tonumber(src or 0) or 0
  if src <= 0 then return end

  local current = tostring(activeCharacters[src] or "")
  if current ~= "" then
    for did, cid in pairs(__AZFW_ACTIVE_STORE.byDiscord or {}) do
      if tostring(cid or "") == current then
        __AZFW_ACTIVE_STORE.byDiscord[did] = nil
      end
    end
  end

  activeCharacters[src] = nil
  if Player and Player(src) and Player(src).state then
    Player(src).state:set("az_active_character", nil, true)
    Player(src).state:set("az_active_charid", nil, true)
    Player(src).state:set("activeCharacter", nil, true)
    Player(src).state:set("charid", nil, true)
  end
  local sk = __azfwSourceKey(src)
  __AZFW_ACTIVE_STORE.bySource[sk] = nil
  __AZFW_ACTIVE_STORE.reason[sk] = nil
  __AZFW_ACTIVE_STORE.updated[sk] = os.time()
end

local function getPrimaryIdentifier(src)
  local license = GetPlayerIdentifierByType(src, 'license')
  if license and license ~= '' then
    return license
  end

  local ids = GetPlayerIdentifiers(src)
  return ids[1] or ("src:" .. tostring(src))
end

local function firstJoinGetIdentity(src)
  local charid = tostring(activeCharacters[tostring(src)] or "")
  if charid ~= "" then
    return ("char:%s"):format(charid)
  end
  return ("license:%s"):format(getPrimaryIdentifier(src))
end

local function welcomeKey(identity)
  return ("az_characterui_welcome_seen_%s"):format(identity)
end

local function firstCarKey(identity)
  return ("az_characterui_firstcar_lastclaim_%s"):format(identity)
end

local function GetActiveCharacter_export(...)
  local args = { ... }
  local src = args[1]
  if type(src) == "table" or type(src) == "userdata" then
    src = args[2]
  end
  return activeCharacters[src]
end

exports("getActiveCharacter", GetActiveCharacter_export)
exports("GetActiveCharacter", GetActiveCharacter_export)
exports("GetCharacter", GetActiveCharacter_export)
exports("getCharacter", GetActiveCharacter_export)
local prevBuckets      = {}
local lastLoc          = {}
local adminCache       = {}

local appearanceCache  = {}

local function iprint(fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  print(("^3[%s]^7 %s"):format(RESOURCE_NAME, ok and msg or tostring(fmt)))
end

local function dprint(fmt, ...)
  if not DEBUG then return end
  iprint("[DEBUG] " .. tostring(fmt), ...)
end

iprint("^2server.lua BOOT (Config.Debug=%s)^7", tostring(Config.Debug))

local HAS_OX = (exports and exports.oxmysql and (type(exports.oxmysql.query) == "function" or type(exports.oxmysql.execute) == "function"))
local HAS_MY = (MySQL and (MySQL.Async or MySQL.Sync))

local function dbDriver()
  if HAS_OX then return "ox" end
  if HAS_MY then return "mysql" end
  return "none"
end

local function awaitPromise(fn)
  local p = promise.new()
  fn(function(res) p:resolve(res) end)
  return Citizen.Await(p)
end

local function oxQuery(sql, params)
  if type(exports.oxmysql.query) == "function" then
    return awaitPromise(function(done)
      exports.oxmysql:query(sql, params or {}, function(rows) done(rows or {}) end)
    end)
  end
  if type(exports.oxmysql.execute) == "function" then
    return awaitPromise(function(done)
      exports.oxmysql:execute(sql, params or {}, function(rows) done(rows or {}) end)
    end)
  end
  return {}
end

local function oxExec(sql, params)
  return awaitPromise(function(done)
    exports.oxmysql:execute(sql, params or {}, function(affected) done(affected) end)
  end)
end

local function myFetchAll(sql, paramsNamed)
  if MySQL.Async and MySQL.Async.fetchAll then
    return awaitPromise(function(done)
      MySQL.Async.fetchAll(sql, paramsNamed or {}, function(rows) done(rows or {}) end)
    end)
  end
  if MySQL.Sync and MySQL.Sync.fetchAll then
    return MySQL.Sync.fetchAll(sql, paramsNamed or {}) or {}
  end
  return {}
end

local function myExecute(sql, paramsNamed)
  if MySQL.Async and MySQL.Async.execute then
    return awaitPromise(function(done)
      MySQL.Async.execute(sql, paramsNamed or {}, function(affected) done(affected) end)
    end)
  end
  if MySQL.Sync and MySQL.Sync.execute then
    return MySQL.Sync.execute(sql, paramsNamed or {})
  end
  return 0
end

local function parseAffected(affected)
  if type(affected) == "number" then return affected end
  if type(affected) == "string" then
    local n = tonumber(affected)
    if n then return n end
  end
  if type(affected) == "table" then
    for _, k in ipairs({ "affectedRows", "affected", "rowsAffected", "changedRows" }) do
      if affected[k] ~= nil then
        local n = tonumber(affected[k])
        if n then return n end
      end
    end
    if next(affected) ~= nil then return 1 end
  end
  return 0
end

local function getDiscordID(src)
  local ids = GetPlayerIdentifiers(src) or {}
  for _, id in ipairs(ids) do
    if type(id) == "string" and id:sub(1, 8) == "discord:" then
      return id:sub(9)
    end
  end

  for _, id in ipairs(ids) do
    if type(id) == "string" and id:match("^%d+$") then
      return id
    end
  end
  return ""
end

local lastUiIssueCodeBySrc = {}

local function makeNoDiscordIssue()
  return {
    code = "no_discord",
    title = "Discord Not Detected",
    message = "Your Discord ID is missing for this session.",
    detail = "Az-CharacterUI could not find a Discord identifier, so your characters cannot load, create, or be selected. Open Discord, reconnect FiveM, and rejoin the server."
  }
end

local function sendUiIssue(src, issue)
  if not src or src == 0 then return end
  issue = issue or makeNoDiscordIssue()
  lastUiIssueCodeBySrc[src] = tostring(issue.code or "unknown")
  TriggerClientEvent("azfw:ui_issue", src, issue)
end

local function clearUiIssue(src, code)
  if not src or src == 0 then return end
  local existing = lastUiIssueCodeBySrc[src]
  if not existing then return end
  if code == nil or tostring(code) == existing or tostring(code) == "all" then
    lastUiIssueCodeBySrc[src] = nil
    TriggerClientEvent("azfw:clear_ui_issue", src, { code = tostring(code or "all") })
  end
end

local function _fwIsAdmin(src)
  local ok, res
  local fwGlobal = rawget(_G, "fw")
  if fwGlobal and type(fwGlobal.isAdmin) == "function" then
    ok, res = pcall(function() return fwGlobal:isAdmin(src) end)
    if ok then return res end
  end
  if exports and exports["Az-Framework"] and type(exports["Az-Framework"].isAdmin) == "function" then
    ok, res = pcall(function() return exports["Az-Framework"]:isAdmin(src) end)
    if ok then return res end
  end
  return nil
end

local function isAdmin(src)
  if not src then return false end
  if Config.RequireAzAdminForEdit then
    local v = _fwIsAdmin(src)
    dprint("isAdmin fw:isAdmin src=%s result=%s", tostring(src), tostring(v))
    if v ~= nil and v == true then return true end
  end
  if IsPlayerAceAllowed(src, Config.AdminAcePermission) == true then return true end
  if IsPlayerAceAllowed(src, "azadmin.use") == true then return true end
  if IsPlayerAceAllowed(src, "command") == true then return true end
  return false
end

local function computeAndSendAdmin(src, reason)
  local ok = isAdmin(src)
  adminCache[src] = ok and true or false
  dprint("adminCache set src=%s ok=%s reason=%s", tostring(src), tostring(adminCache[src]), tostring(reason or ""))
  TriggerClientEvent("spawn_selector:adminCheckResult", src, adminCache[src])
  return adminCache[src]
end

RegisterNetEvent("__azfw_internal:adminWarmup", function(src, reason)

  if source ~= 0 then return end
  if src and GetPlayerName(src) then
    computeAndSendAdmin(src, reason or "warmup")
  end
end)

local SQL_VERIFY_OX = "SELECT 1 FROM user_characters WHERE discordid = ? AND charid = ? LIMIT 1"
local SQL_VERIFY_MY = "SELECT 1 FROM user_characters WHERE discordid = @d AND charid = @c LIMIT 1"

local function verifyCharOwner(did, charid)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return false end

  local drv = dbDriver()
  if drv == "ox" then
    local rows = oxQuery(SQL_VERIFY_OX, { did, charid })
    return (rows and #rows > 0) and true or false
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_VERIFY_MY, { ["@d"] = did, ["@c"] = charid })
    return (rows and #rows > 0) and true or false
  end
  return false
end

local function getActiveCharId(src)
  if fw and fw.GetPlayerCharacter then
    local cid = fw:GetPlayerCharacter(src)
    if cid then return tostring(cid) end
  end
  local ac = activeCharacters[tostring(src)]
  if ac and tostring(ac) ~= "" then return tostring(ac) end
  return ""
end

local function getActiveCharIdForSource(src, did, optionalCharId)
  local cid = tostring(optionalCharId or "")
  if cid ~= "" and did ~= "" and verifyCharOwner(did, cid) then
    return cid
  end

  if fw and fw.GetPlayerCharacter then
    local fcid = tostring(fw:GetPlayerCharacter(src) or "")
    if fcid ~= "" and did ~= "" and verifyCharOwner(did, fcid) then
      return fcid
    end
  end

  local ac = tostring(activeCharacters[tostring(src)] or "")
  if ac ~= "" and did ~= "" and verifyCharOwner(did, ac) then
    return ac
  end

  return ""
end

local function _vec4ToCoords(v)
  if type(v) ~= "table" then return nil end
  local x = tonumber(v.x or v[1])
  local y = tonumber(v.y or v[2])
  local z = tonumber(v.z or v[3])
  local h = tonumber(v.w or v.h or v[4])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z, h = h or 0.0 }
end

local function _anyToCoords(v)
  if type(v) ~= "table" then return nil end
  if v.coords and type(v.coords) == "table" then
    return _anyToCoords(v.coords)
  end
  local x = tonumber(v.x or v[1])
  local y = tonumber(v.y or v[2])
  local z = tonumber(v.z or v[3])
  local h = tonumber(v.w or v.h or v.heading or v[4])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z, h = h or 0.0 }
end

local function houseRowToHomeObject(r)
  if type(r) ~= "table" then return nil end
  local nm = r.label
  if nm == nil or nm == "" then nm = r.name end
  return {
    houseId = tonumber(r.id) or nil,
    kind = (r.tenant_identifier and tostring(r.tenant_identifier) ~= "" and "rented" or "owned"),
    name = nm,
    interior = r.interior,
    price = tonumber(r.price) or nil,
    locked = (tonumber(r.locked) == 1)
  }
end

local function resolveHomeSpawnCoords(homeObj)
  if not (Config.Housing and Config.Housing.ShowAsSpawnOption) then return nil end
  if type(homeObj) ~= "table" then return nil end

  local interior = tostring(homeObj.interior or "")
  local byInterior = Config.Housing.SpawnCoordsByInterior or {}
  local c = _vec4ToCoords(byInterior[interior])
  if c then return c end

  return _vec4ToCoords(Config.Housing.FallbackSpawn)
end

local function dbFetchPrimaryHouseByCharId(charid)
  charid = tostring(charid or "")
  if charid == "" then return nil end

  local housesTbl = Config.Housing.Table
  local ownerCol  = Config.Housing.OwnerColumn
  local ownerKey  = "charid:" .. charid

  local drv = dbDriver()
  if drv == "ox" then
    local sql = string.format(
      "SELECT id, name, label, price, interior, locked, `%s` AS owner_identifier FROM `%s` WHERE `%s` = ? ORDER BY id ASC LIMIT 1",
      ownerCol, housesTbl, ownerCol
    )
    local rows = oxQuery(sql, { ownerKey }) or {}
    return rows[1]
  elseif drv == "mysql" then
    local sql = string.format(
      "SELECT id, name, label, price, interior, locked, `%s` AS owner_identifier FROM `%s` WHERE `%s` = @o ORDER BY id ASC LIMIT 1",
      ownerCol, housesTbl, ownerCol
    )
    local rows = myFetchAll(sql, { ["@o"] = ownerKey }) or {}
    return rows[1]
  end

  return nil
end

local function dbFetchHouseDoorCoords(houseId)
  houseId = tonumber(houseId or 0)
  if not houseId or houseId <= 0 then return nil end

  local doorsTbl = Config.Housing.DoorsTable
  local drv = dbDriver()

  if drv == "ox" then
    local sql = string.format(
      "SELECT x, y, z, heading, radius, label FROM `%s` WHERE house_id = ? ORDER BY id ASC LIMIT 1",
      doorsTbl
    )
    local rows = oxQuery(sql, { houseId }) or {}
    local r = rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  elseif drv == "mysql" then
    local sql = string.format(
      "SELECT x, y, z, heading, radius, label FROM `%s` WHERE house_id = @hid ORDER BY id ASC LIMIT 1",
      doorsTbl
    )
    local rows = myFetchAll(sql, { ["@hid"] = houseId }) or {}
    local r = rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  end

  return nil
end

local function tryResolveHouseDoorCoords_DB_ONLY(houseRow)
  if type(houseRow) ~= "table" then return nil end
  local houseId = tonumber(houseRow.id or 0)
  if not houseId or houseId <= 0 then return nil end

  if Config.Housing and type(Config.Housing.DoorCoordsByHouseId) == "table" then
    local mapped = Config.Housing.DoorCoordsByHouseId[houseId]
    local c = _anyToCoords(mapped)
    if c then return c end
  end

  local door = dbFetchHouseDoorCoords(houseId)
  if door and door.x and door.y and door.z then return door end

  local homeObj = houseRowToHomeObject(houseRow)
  local spawn = resolveHomeSpawnCoords(homeObj)
  if spawn then return spawn end

  return nil
end

local function apKey(did, charid)
  return tostring(did) .. "|" .. tostring(charid)
end

local function cacheAppearance(did, charid, appearanceJson)
  appearanceCache[apKey(did, charid)] = { appearance = appearanceJson, at = os.time() }
end

local function getCachedAppearance(did, charid)
  local v = appearanceCache[apKey(did, charid)]
  if not v then return nil end
  if (os.time() - (v.at or 0)) > 600 then
    appearanceCache[apKey(did, charid)] = nil
    return nil
  end
  return v.appearance
end

local SQL_AP_FETCH_OX = "SELECT appearance FROM azfw_appearance WHERE discordid = ? AND charid = ? LIMIT 1"
local SQL_AP_FETCH_MY = "SELECT appearance FROM azfw_appearance WHERE discordid = @d AND charid = @c LIMIT 1"

local function dbFetchAppearance(did, charid)
  if not Config.EnableFiveAppearance then return nil end
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return nil end

  local cached = getCachedAppearance(did, charid)
  if cached then
    dprint("appearance cache hit did=%s charid=%s bytes=%d", did, charid, #tostring(cached))
    return cached
  end

  local drv = dbDriver()
  if drv == "ox" then
    local rows = oxQuery(SQL_AP_FETCH_OX, { did, charid })
    local a = (rows and rows[1] and rows[1].appearance) or nil
    dprint("appearance db fetch ox did=%s charid=%s has=%s", did, charid, tostring(a ~= nil))
    if a then cacheAppearance(did, charid, a) end
    return a
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_AP_FETCH_MY, { ["@d"] = did, ["@c"] = charid })
    local a = (rows and rows[1] and rows[1].appearance) or nil
    dprint("appearance db fetch mysql did=%s charid=%s has=%s", did, charid, tostring(a ~= nil))
    if a then cacheAppearance(did, charid, a) end
    return a
  end

  return nil
end

local SQL_AP_FETCH_ALL_OX = "SELECT charid, appearance FROM azfw_appearance WHERE discordid = ?"
local SQL_AP_FETCH_ALL_MY = "SELECT charid, appearance FROM azfw_appearance WHERE discordid = @d"

local function dbFetchAllAppearances(did)
  if not Config.EnableFiveAppearance then return {} end
  did = tostring(did or "")
  if did == "" then return {} end

  local out = {}
  local drv = dbDriver()
  if drv == "ox" then
    local rows = oxQuery(SQL_AP_FETCH_ALL_OX, { did })
    for i = 1, #(rows or {}) do
      local r = rows[i]
      if r and r.charid ~= nil and type(r.appearance) == "string" and r.appearance ~= "" then
        out[tostring(r.charid)] = r.appearance
        cacheAppearance(did, tostring(r.charid), r.appearance)
      end
    end
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_AP_FETCH_ALL_MY, { ["@d"] = did })
    for i = 1, #(rows or {}) do
      local r = rows[i]
      if r and r.charid ~= nil and type(r.appearance) == "string" and r.appearance ~= "" then
        out[tostring(r.charid)] = r.appearance
        cacheAppearance(did, tostring(r.charid), r.appearance)
      end
    end
  end

  return out
end

local function countPairs(t)
  local c = 0
  for _ in pairs(t or {}) do c = c + 1 end
  return c
end

local function pushAllAppearances(src)
  if not Config.EnableFiveAppearance then return end
  local did = getDiscordID(src)
  if did == "" then return end
  local map = dbFetchAllAppearances(did)
  dprint("appearance bulk push src=%s entries=%d", tostring(src), countPairs(map))
  TriggerClientEvent("azfw:appearance:bulk", src, map or {})
end

RegisterNetEvent("azfw:appearance:bulkRequest", function()
  pushAllAppearances(source)
end)

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("azfw:appearance:get", function(source, charid)
    if not Config.EnableFiveAppearance then
      return { ok = true, exists = false }
    end

    local src = source
    local did = getDiscordID(src)
    if did == "" then return { ok = false, err = "no_discord" } end

    charid = tostring(charid or "")
    if charid == "" then return { ok = false, err = "no_charid" } end

    if not verifyCharOwner(did, charid) then
      return { ok = false, err = "not_owner" }
    end

    local ap = dbFetchAppearance(did, charid)
    if ap and type(ap) == "string" and ap ~= "" then
      return { ok = true, exists = true, appearance = ap }
    end
    return { ok = true, exists = false }
  end)
end

local SQL_AP_UPSERT_OX = [[
  INSERT INTO azfw_appearance (discordid, charid, appearance)
  VALUES (?, ?, ?)
  ON DUPLICATE KEY UPDATE appearance = VALUES(appearance)
]]

local SQL_AP_UPSERT_MY = [[
  INSERT INTO azfw_appearance (discordid, charid, appearance)
  VALUES (@d, @c, @a)
  ON DUPLICATE KEY UPDATE appearance = VALUES(appearance)
]]

local function dbSaveAppearance(did, charid, appearanceJson)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return false end
  if type(appearanceJson) ~= "string" or appearanceJson == "" then return false end

  local drv = dbDriver()
  if drv == "ox" then
    oxExec(SQL_AP_UPSERT_OX, { did, charid, appearanceJson })
    cacheAppearance(did, charid, appearanceJson)
    return true
  elseif drv == "mysql" then
    myExecute(SQL_AP_UPSERT_MY, { ["@d"] = did, ["@c"] = charid, ["@a"] = appearanceJson })
    cacheAppearance(did, charid, appearanceJson)
    return true
  end
  return false
end

RegisterNetEvent("azfw:appearance:save", function(charid, appearanceJson)
  if not Config.EnableFiveAppearance then
    dprint("appearance:save ignored EnableFiveAppearance=false")
    return
  end

  local src = source
  local did = getDiscordID(src)

  dprint("appearance:save recv src=%s did=%s charid=%s bytes=%s",
    tostring(src), tostring(did), tostring(charid),
    tostring(type(appearanceJson) == "string" and #appearanceJson or "na")
  )

  if did == "" then
    dprint("appearance:save blocked no_discord src=%s", tostring(src))
    return
  end

  charid = tostring(charid or "")
  if charid == "" then
    dprint("appearance:save blocked no_charid src=%s", tostring(src))
    return
  end

  if not verifyCharOwner(did, charid) then
    dprint("appearance:save denied not_owner src=%s did=%s charid=%s", tostring(src), tostring(did), tostring(charid))
    return
  end

  if type(appearanceJson) ~= "string" or appearanceJson == "" then
    dprint("appearance:save blocked empty_json src=%s charid=%s", tostring(src), tostring(charid))
    return
  end

  local okSaved = dbSaveAppearance(did, charid, appearanceJson)
  dprint("appearance:save dbSaveAppearance=%s src=%s charid=%s", tostring(okSaved), tostring(src), tostring(charid))

  if okSaved then
    TriggerClientEvent("azfw:activeAppearance", src, charid, appearanceJson)
    pushAllAppearances(src)
  end
end)

local SQL_LASTPOS_REPLACE_OX = [[
  REPLACE INTO azfw_lastpos (discordid, charid, x, y, z, heading)
  VALUES (?, ?, ?, ?, ?, ?)
]]

local SQL_LASTPOS_REPLACE_MY = [[
  REPLACE INTO azfw_lastpos (discordid, charid, x, y, z, heading)
  VALUES (@d, @c, @x, @y, @z, @h)
]]

local SQL_LASTPOS_GET_OX = [[
  SELECT x, y, z, heading
  FROM azfw_lastpos
  WHERE discordid = ? AND charid = ?
  LIMIT 1
]]

local SQL_LASTPOS_GET_MY = [[
  SELECT x, y, z, heading
  FROM azfw_lastpos
  WHERE discordid = @d AND charid = @c
  LIMIT 1
]]

local function dbSaveLastPosByChar(did, charid, x, y, z, h)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return end

  x = tonumber(x); y = tonumber(y); z = tonumber(z)
  h = tonumber(h) or 0.0
  if not x or not y or not z then return end

  local drv = dbDriver()
  if drv == "ox" then
    oxExec(SQL_LASTPOS_REPLACE_OX, { did, charid, x, y, z, h })
  elseif drv == "mysql" then
    myExecute(SQL_LASTPOS_REPLACE_MY, { ["@d"]=did, ["@c"]=charid, ["@x"]=x, ["@y"]=y, ["@z"]=z, ["@h"]=h })
  end
end

local function dbGetLastPos(did, charid)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return nil end

  local drv = dbDriver()
  if drv == "ox" then
    local rows = oxQuery(SQL_LASTPOS_GET_OX, { did, charid })
    local r = rows and rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  elseif drv == "mysql" then
    local rows = myFetchAll(SQL_LASTPOS_GET_MY, { ["@d"] = did, ["@c"] = charid })
    local r = rows and rows[1]
    if not r then return nil end
    return { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
  end

  return nil
end

RegisterNetEvent("azfw:lastloc:update", function(clientCharid, x, y, z, heading)
  if not Config.EnableLastLocation then return end

  local src = source
  local did = getDiscordID(src)
  if did == "" then return end

  local charid = fw and fw.GetPlayerCharacter and fw:GetPlayerCharacter(src) or nil
  charid = tostring(charid or "")

  if charid == "" then
    local c = tostring(clientCharid or "")
    if c ~= "" and verifyCharOwner(did, c) then
      charid = c
    else
      return
    end
  end

  x = tonumber(x); y = tonumber(y); z = tonumber(z); heading = tonumber(heading) or 0.0
  if not x or not y or not z then return end

  dbSaveLastPosByChar(did, charid, x, y, z, heading)

  lastLoc[src] = { charid = charid, x = x, y = y, z = z, h = heading, at = os.time() }
end)

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("azfw:lastloc:get", function(source, charid)
    if not Config.EnableLastLocation then return nil end

    local src = source
    local did = getDiscordID(src)
    if did == "" then return nil end

    charid = tostring(charid or "")
    if charid == "" and fw and fw.GetPlayerCharacter then
      charid = tostring(fw:GetPlayerCharacter(src) or "")
    end
    if charid == "" then return nil end

    if not verifyCharOwner(did, charid) then return nil end

    local v = lastLoc[src]
    if v and v.charid == charid and (os.time() - (v.at or 0)) <= 10 then
      return { x = v.x, y = v.y, z = v.z, h = v.h, at = v.at }
    end

    local dbv = dbGetLastPos(did, charid)
    if not dbv then return nil end

    lastLoc[src] = { charid = charid, x = dbv.x, y = dbv.y, z = dbv.z, h = dbv.h, at = os.time() }
    return { x = dbv.x, y = dbv.y, z = dbv.z, h = dbv.h, at = os.time() }
  end)
end

local SQL_CHARS_OX = [[
  SELECT
    uc.charid,
    uc.name,
    uc.active_department,
    uc.license_status,
    IFNULL(eum.firstname,'') AS firstname,
    IFNULL(eum.lastname,'')  AS lastname,
    IFNULL(eum.cash, 0)      AS cash,
    IFNULL(eum.bank, 0)      AS bank
  FROM user_characters uc
  LEFT JOIN econ_user_money eum
    ON eum.discordid = uc.discordid AND eum.charid = uc.charid
  WHERE uc.discordid = ?
  ORDER BY uc.id ASC
]]

local SQL_CHARS_MY = [[
  SELECT
    uc.charid,
    uc.name,
    uc.active_department,
    uc.license_status,
    IFNULL(eum.firstname,'') AS firstname,
    IFNULL(eum.lastname,'')  AS lastname,
    IFNULL(eum.cash, 0)      AS cash,
    IFNULL(eum.bank, 0)      AS bank
  FROM user_characters uc
  LEFT JOIN econ_user_money eum
    ON eum.discordid = uc.discordid AND eum.charid = uc.charid
  WHERE uc.discordid = @discordid
  ORDER BY uc.id ASC
]]

local function fetchCharactersForSource(src)
  local did = getDiscordID(src)
  if did == "" then
    dprint("fetchCharactersForSource no discord id src=%s", tostring(src))
    return {}
  end

  local drv = dbDriver()
  local rows = {}

  if drv == "ox" then
    rows = oxQuery(SQL_CHARS_OX, { did }) or {}
    dprint("fetchCharactersForSource ox src=%s did=%s rows=%d", tostring(src), tostring(did), #(rows or {}))
  elseif drv == "mysql" then
    rows = myFetchAll(SQL_CHARS_MY, { ["@discordid"] = did }) or {}
    dprint("fetchCharactersForSource mysql src=%s did=%s rows=%d", tostring(src), tostring(did), #(rows or {}))
  else
    dprint("fetchCharactersForSource no db driver")
    rows = {}
  end

  if Config.Housing and Config.Housing.Enabled and Config.Housing.ShowInCharacterUI then
    for _, r in ipairs(rows or {}) do
      local cid = tostring(r.charid or "")
      if cid ~= "" then
        local house = dbFetchPrimaryHouseByCharId(cid)
        if house then
          r.home = houseRowToHomeObject(house)
        end
      end
    end
  end

  return rows or {}
end

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("azfw:fetch_characters", function(source, _)
    local did = getDiscordID(source)
    if did == "" then
      sendUiIssue(source, makeNoDiscordIssue())
      return {}
    end
    clearUiIssue(source, "no_discord")
    return fetchCharactersForSource(source)
  end)
end

RegisterNetEvent("azfw:request_characters", function()
  local src = source
  local did = getDiscordID(src)
  if did == "" then
    sendUiIssue(src, makeNoDiscordIssue())
    TriggerClientEvent("azfw:characters_updated", src, {})
    return
  end

  clearUiIssue(src, "no_discord")
  TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
end)

RegisterNetEvent("azfw:request_active_character", function()
  local src = source
  local charid = activeCharacters[tostring(src)]

  if not charid then
    dprint("request_active_character: none src=%s", tostring(src))
    TriggerClientEvent("azfw:activeAppearance", src, "", nil)
    return
  end

  local did = getDiscordID(src)
  local a = nil
  if Config.EnableFiveAppearance and did ~= "" then
    a = dbFetchAppearance(did, tostring(charid))
  end

  dprint("request_active_character: src=%s charid=%s hasAp=%s",
    tostring(src), tostring(charid), tostring(a ~= nil and a ~= "")
  )

  TriggerClientEvent("azfw:activeAppearance", src, tostring(charid), a)
end)

RegisterNetEvent("azfw:preview:enter", function()
  local src = source
  if prevBuckets[src] then return end
  local b = (src + 1000)
  prevBuckets[src] = b
  SetPlayerRoutingBucket(src, b)
  dprint("preview enter src=%s bucket=%s", tostring(src), tostring(b))
end)

RegisterNetEvent("azfw:preview:exit", function()
  local src = source
  local b = prevBuckets[src]
  prevBuckets[src] = nil
  SetPlayerRoutingBucket(src, 0)
  dprint("preview exit src=%s prevBucket=%s", tostring(src), tostring(b))
end)

local spawns = {}

local function defaultSpawns()
  return {
    {
      id = "pillbox", name = "Pillbox Hospital", description = "Central Los Santos",
      spawn = { coords = { x = 311.20, y = -592.95, z = 43.28 }, heading = 340.0 },
      map   = { coords = { x = 311.20, y = -592.95, z = 43.28 }, heading = 340.0 },
      style = { size = 28, color = "#e74c3c", shape = "circle", icon = "" }
    },
    {
      id = "mrpd", name = "Mission Row PD", description = "Downtown",
      spawn = { coords = { x = 428.23, y = -981.16, z = 30.71 }, heading = 90.0 },
      map   = { coords = { x = 428.23, y = -981.16, z = 30.71 }, heading = 90.0 },
      style = { size = 28, color = "#e74c3c", shape = "circle", icon = "" }
    },
    {
      id = "legion", name = "Legion Square", description = "City Center",
      spawn = { coords = { x = 204.92, y = -908.77, z = 30.69 }, heading = 0.0 },
      map   = { coords = { x = 204.92, y = -908.77, z = 30.69 }, heading = 0.0 },
      style = { size = 28, color = "#e74c3c", shape = "circle", icon = "" }
    }
  }
end

local function _num(v, fallback)
  local n = tonumber(v)
  if n == nil then return fallback end
  return n
end

local function _normStyle(s)
  s = (type(s) == "table") and s or {}
  local size = tonumber(s.size or s.pinSize) or 28
  if size < 10 then size = 10 end
  if size > 96 then size = 96 end
  local color = tostring(s.color or s.pinColor or "#e74c3c")
  local shape = tostring(s.shape or s.pinShape or "circle")
  local icon = tostring(s.icon or s.pinIcon or "")
  if #icon > 8 then icon = icon:sub(1, 8) end
  return { size = size, color = color, shape = shape, icon = icon }
end

local function _normXYZH(obj, fallbackXYZH)
  fallbackXYZH = fallbackXYZH or { x = 0, y = 0, z = 0, h = 0 }
  if type(obj) ~= "table" then
    return { x = fallbackXYZH.x, y = fallbackXYZH.y, z = fallbackXYZH.z, h = fallbackXYZH.h }
  end
  return {
    x = _num(obj.x, fallbackXYZH.x),
    y = _num(obj.y, fallbackXYZH.y),
    z = _num(obj.z, fallbackXYZH.z),
    h = _num(obj.h or obj.heading, fallbackXYZH.h)
  }
end

local function normalizeSpawnList(list)
  local out = {}
  if type(list) ~= "table" then return out end

  for i = 1, #list do
    local s = list[i]
    if type(s) == "table" then
      local id = tostring(s.id or s.name or ("spawn" .. i))
      local name = tostring(s.name or s.label or id)
      local desc = tostring(s.description or "")

      local legacy = nil
      if type(s.coords) == "table" and s.coords.x and s.coords.y and s.coords.z then
        legacy = { x = s.coords.x, y = s.coords.y, z = s.coords.z, h = (s.heading or s.coords.h or 0.0) }
      end

      local spawnXYZH = nil
      if s.spawn and type(s.spawn) == "table" and s.spawn.coords and type(s.spawn.coords) == "table" then
        spawnXYZH = { x = s.spawn.coords.x, y = s.spawn.coords.y, z = s.spawn.coords.z, h = (s.spawn.heading or s.spawn.coords.h or s.heading or 0.0) }
      end
      spawnXYZH = spawnXYZH or s.spawnXYZH or s.spawnCoords or legacy
      spawnXYZH = _normXYZH(spawnXYZH, legacy or { x = 0, y = 0, z = 0, h = 0 })

      local mapXYZH = nil
      if s.map and type(s.map) == "table" and s.map.coords and type(s.map.coords) == "table" then
        mapXYZH = { x = s.map.coords.x, y = s.map.coords.y, z = s.map.coords.z, h = (s.map.heading or s.map.coords.h or s.mapHeading or 0.0) }
      end
      mapXYZH = mapXYZH or s.mapXYZH or s.mapCoords

      if mapXYZH then
        mapXYZH = _normXYZH(mapXYZH, spawnXYZH)
      else
        mapXYZH = { x = spawnXYZH.x, y = spawnXYZH.y, z = spawnXYZH.z, h = spawnXYZH.h }
      end

      out[#out + 1] = {
        id = id, name = name, description = desc,
        style = _normStyle(s.style or s),
        map = { coords = { x = mapXYZH.x, y = mapXYZH.y, z = mapXYZH.z }, heading = mapXYZH.h },
        spawn = { coords = { x = spawnXYZH.x, y = spawnXYZH.y, z = spawnXYZH.z }, heading = spawnXYZH.h }
      }
    end
  end

  return out
end

local function isLastLocationSpawn(s)
  if type(s) ~= "table" then return false end
  local idv = tostring(s.id or s.name or s.label or ""):lower():gsub("%s+", " "):gsub("^%s+",""):gsub("%s+$","")
  local nm  = tostring(s.name or s.label or ""):lower():gsub("%s+", " "):gsub("^%s+",""):gsub("%s+$","")
  if s.isLastLocation == true then return true end
  if idv == "last_location" or idv == "last location" or idv == "lastloc" then return true end
  if nm == "last location" or nm == "last_location" then return true end
  if idv:find("last_location", 1, true) then return true end
  if nm:find("last location", 1, true) then return true end
  return false
end

local function isReservedHouseSpawn(s)
  if type(s) ~= "table" then return false end
  local function norm(v)
    return tostring(v or ""):lower():gsub("%s+", "_"):gsub("^_+", ""):gsub("_+$", "")
  end
  local idv = norm(s.id)
  local nm = norm(s.name or s.label)
  local desc = tostring(s.description or ""):lower()
  if s.isHouse == true or s.isProperty == true then return true end
  if idv == "house" or idv == "home" or idv == "my_house" or idv == "property" then return true end
  if nm == "house" or nm == "my_house" or nm == "my_home" or nm == "property" then return true end
  if desc:find("spawn at your property", 1, true) then return true end
  return false
end

local function stripReservedDynamicSpawns(list)
  if type(list) ~= "table" then return {} end
  local out = {}
  for i=1,#list do
    local s = list[i]
    if not isLastLocationSpawn(s) and not isReservedHouseSpawn(s) then
      out[#out+1] = s
    end
  end
  return out
end

local function loadSpawnsFromFile()
  local raw = LoadResourceFile(RESOURCE_NAME, Config.SpawnFile)
  if not raw or raw == "" then
    spawns = defaultSpawns()
    return false
  end

  local ok, decoded = pcall(function() return json.decode(raw) end)
  if not ok or type(decoded) ~= "table" then
    spawns = defaultSpawns()
    return false
  end

  spawns = normalizeSpawnList(decoded)
  spawns = stripReservedDynamicSpawns(spawns)

  if #spawns == 0 then spawns = defaultSpawns() end
  return true
end

local function saveSpawnsToFile(list)
  local norm = normalizeSpawnList(list)
  norm = stripReservedDynamicSpawns(norm)
  local ok, encoded = pcall(function() return json.encode(norm) end)
  if not ok or type(encoded) ~= "string" then return false, "encode_failed" end
  SaveResourceFile(RESOURCE_NAME, Config.SpawnFile, encoded, -1)
  spawns = norm
  return true
end

loadSpawnsFromFile()
dprint("spawns loaded count=%d file=%s", #spawns, tostring(Config.SpawnFile))

local function buildDynamicLastLocSpawn(src, did, charid)
  if not Config.EnableLastLocation then return nil end

  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return nil end
  if not verifyCharOwner(did, charid) then return nil end

  local v = lastLoc[src]
  if (not v) or v.charid ~= charid then
    local dbv = dbGetLastPos(did, charid)
    if not dbv then return nil end
    v = { charid = charid, x = dbv.x, y = dbv.y, z = dbv.z, h = dbv.h, at = os.time() }
    lastLoc[src] = v
  end

  if v.x == nil or v.y == nil or v.z == nil then return nil end

  return {
    id = "last_location",
    isLastLocation = true,
    name = "Last Location",
    description = "Resume where you left off",
    style = { size = 30, color = "#2ecc71", shape = "pin", icon = "⟲" },
    map = { coords = { x = v.x, y = v.y, z = v.z }, heading = v.h or 0.0 },
    spawn = { coords = { x = v.x, y = v.y, z = v.z }, heading = v.h or 0.0 }
  }
end

local function makeSpawnsForClient(src, optionalCharId)
  local out = {}

  local did = getDiscordID(src)
  local charid = ""
  if did ~= "" then
    charid = getActiveCharIdForSource(src, did, optionalCharId)
  end

  local ll = buildDynamicLastLocSpawn(src, did, charid)
  if ll then out[#out + 1] = ll end

  if Config.Housing and Config.Housing.Enabled and Config.Housing.ShowAsSpawnOption then
    local hc = getActiveCharId(src)
    if hc ~= "" then
      local house = dbFetchPrimaryHouseByCharId(hc)
      if house then
        local coords = tryResolveHouseDoorCoords_DB_ONLY(house)
        if coords and coords.x and coords.y and coords.z then
          local label = tostring(house.label or house.name or ("House #" .. tostring(house.id)))
          out[#out + 1] = {
            id = "house",
            name = "House — " .. label,
            description = "Spawn at your property",
            locked = Config.Housing.HomeSpawnLocked and true or false,
            style = { size = 30, color = "#f1c40f", shape = "pin", icon = "🏠" },
            map = { coords = { x = coords.x, y = coords.y, z = coords.z }, heading = coords.h or 0.0 },
            spawn = { coords = { x = coords.x, y = coords.y, z = coords.z }, heading = coords.h or 0.0 }
          }
        end
      end
    end
  end

  for i = 1, #(spawns or {}) do out[#out + 1] = spawns[i] end
  return out
end

RegisterNetEvent("spawn_selector:requestSpawns", function(optionalCharId)
  local src = source

  if optionalCharId ~= nil then
    local did = getDiscordID(src)
    local cid = tostring(optionalCharId or "")
    if did ~= "" and cid ~= "" and verifyCharOwner(did, cid) then
      setUiActiveCharacter(src, did, cid, "spawn_selector:requestSpawns")
    end
  end

  local ok = adminCache[src]
  if ok == nil then ok = computeAndSendAdmin(src, "lazy_requestSpawns") end

  local list = makeSpawnsForClient(src, optionalCharId)
  TriggerClientEvent("spawn_selector:sendSpawns", src, list or {}, Config.MapBounds or {}, ok and true or false)
end)

RegisterNetEvent("spawn_selector:checkAdmin", function()
  local src = source
  local ok = computeAndSendAdmin(src, "manual_checkAdmin")
  dprint("spawn_selector:checkAdmin src=%s ok=%s", tostring(src), tostring(ok))
end)

RegisterNetEvent("spawn_selector:saveSpawns", function(payload)
  local src = source

  if not isAdmin(src) then
    dprint("spawn_selector:saveSpawns denied src=%s", tostring(src))
    TriggerClientEvent("spawn_selector:spawnsSaved", src, false, "no_permission")
    return
  end

  local list = payload
  if type(payload) == "table" and type(payload.spawns) == "table" then
    list = payload.spawns
  end

  if type(list) ~= "table" then
    TriggerClientEvent("spawn_selector:spawnsSaved", src, false, "invalid_payload")
    return
  end

  local filtered = {}
  for i = 1, #list do
    local s = list[i]
    if type(s) == "table" then
      if not isLastLocationSpawn(s) then
        filtered[#filtered + 1] = s
      end
    end
  end

  local ok, err = saveSpawnsToFile(filtered)
  if ok then
    TriggerClientEvent("spawn_selector:spawnsSaved", src, true, nil)
    TriggerClientEvent("spawn_selector:spawnsUpdated", -1, spawns or {})
    dprint("spawns saved by src=%s count=%d", tostring(src), #(spawns or {}))
  else
    TriggerClientEvent("spawn_selector:spawnsSaved", src, false, err or "save_failed")
  end
end)

RegisterCommand(Config.SpawnMenuCommand, function(src)
  if src == 0 then return end
  if not isAdmin(src) then
    TriggerClientEvent("chat:addMessage", src, { args = { "^1SYSTEM^7", "No permission." } })
    return
  end

  local ok = adminCache[src]
  if ok == nil then ok = computeAndSendAdmin(src, "spawnmenu_command") end

  local list = makeSpawnsForClient(src, nil)
  TriggerClientEvent("spawn_selector:sendSpawns", src, list or {}, Config.MapBounds or {}, true)
end, false)

local function handleSelectCharacter(src, charID)
  if not src or not charID then return end

  local did = getDiscordID(src)
  if did == "" then
    sendUiIssue(src, makeNoDiscordIssue())
    return
  end

  clearUiIssue(src, "no_discord")
  charID = tostring(charID)
  if not verifyCharOwner(did, charID) then
    dprint("selectCharacter FAIL src=%s did=%s charid=%s", tostring(src), tostring(did), tostring(charID))
    return
  end

  setUiActiveCharacter(src, did, charID, "CharacterUI select")
  dprint("selectCharacter OK src=%s charid=%s", tostring(src), tostring(charID))
  TriggerEvent("Az-Framework:characterSelected", src, charID)
  TriggerEvent("Az-Framework:Bridge:characterSelected", src, charID)

  if Config.EnableFiveAppearance then
    local a = dbFetchAppearance(did, charID)
    TriggerClientEvent("azfw:activeAppearance", src, charID, a)
    pushAllAppearances(src)
  end
end

RegisterNetEvent("azfw:set_active_character", function(charid)
  handleSelectCharacter(source, charid)
end)

RegisterNetEvent("az-fw-money:selectCharacter", function(charid)
  handleSelectCharacter(source, charid)
end)

local SQL_INS_CHAR_OX = [[
  INSERT INTO user_characters (discordid, charid, name, active_department, license_status)
  VALUES (?, ?, ?, ?, ?)
]]

local SQL_INS_CHAR_MY = [[
  INSERT INTO user_characters (discordid, charid, name, active_department, license_status)
  VALUES (@discordid, @charid, @name, @dept, @license)
]]

local SQL_INS_MONEY_OX = [[
  INSERT IGNORE INTO econ_user_money (discordid, charid, firstname, lastname, cash, bank, last_daily, card_status)
  VALUES (?, ?, ?, ?, ?, ?, 0, 'active')
]]

local SQL_INS_MONEY_MY = [[
  INSERT IGNORE INTO econ_user_money (discordid, charid, firstname, lastname, cash, bank, last_daily, card_status)
  VALUES (@discordid, @charid, @firstname, @lastname, @cash, @bank, 0, 'active')
]]

RegisterNetEvent("azfw:register_character", function(firstName, lastName, dept, license)
  local src = source
  local did = getDiscordID(src)
  if did == "" then
    sendUiIssue(src, makeNoDiscordIssue())
    return
  end

  clearUiIssue(src, "no_discord")
  local charID = ("%d%03d%04d"):format(os.time(), math.random(0, 999), tonumber(src) or 0)
  local fullName = tostring(firstName or "") .. ((lastName and lastName ~= "") and (" " .. tostring(lastName)) or "")
  local active_department = tostring(dept or "")
  local license_status = tostring(license or "UNKNOWN")
  local startingCash = tonumber(Config.StartingCash) or 0

  local drv = dbDriver()
  dprint("register_character src=%s did=%s charid=%s name=%s drv=%s", tostring(src), tostring(did), tostring(charID), tostring(fullName), drv)

  if drv == "ox" then
    local affected = oxExec(SQL_INS_CHAR_OX, { did, charID, fullName, active_department, license_status })
    if parseAffected(affected) < 1 then return end
    oxExec(SQL_INS_MONEY_OX, { did, charID, firstName or "", lastName or "", startingCash, 0 })
    setUiActiveCharacter(src, did, charID, "CharacterUI create")
    TriggerClientEvent("azfw:characterCreated", src, charID)
    TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
    pushAllAppearances(src)
    return
  end

  if drv == "mysql" then
    local affected = myExecute(SQL_INS_CHAR_MY, {
      ["@discordid"] = did,
      ["@charid"] = charID,
      ["@name"] = fullName,
      ["@dept"] = active_department,
      ["@license"] = license_status
    })
    if parseAffected(affected) < 1 then return end
    myExecute(SQL_INS_MONEY_MY, {
      ["@discordid"] = did,
      ["@charid"] = charID,
      ["@firstname"] = firstName or "",
      ["@lastname"] = lastName or "",
      ["@cash"] = startingCash,
      ["@bank"] = 0
    })
    setUiActiveCharacter(src, did, charID, "CharacterUI create")
    TriggerClientEvent("azfw:characterCreated", src, charID)
    TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
    pushAllAppearances(src)
  end
end)

local SQL_DEL_CHAR_OX  = "DELETE FROM user_characters WHERE discordid = ? AND charid = ?"
local SQL_DEL_CHAR_MY  = "DELETE FROM user_characters WHERE discordid = @d AND charid = @c"
local SQL_AP_DELETE_OX = "DELETE FROM azfw_appearance WHERE discordid = ? AND charid = ?"
local SQL_AP_DELETE_MY = "DELETE FROM azfw_appearance WHERE discordid = @d AND charid = @c"

local function purgeAppearanceCacheForDid(did)
  if not did or did == "" then return end
  local prefix = tostring(did) .. "|"
  for k in pairs(appearanceCache) do
    if type(k) == "string" and k:sub(1, #prefix) == prefix then
      appearanceCache[k] = nil
    end
  end
end

local function dbDeleteAppearance(did, charid)
  did = tostring(did or "")
  charid = tostring(charid or "")
  if did == "" or charid == "" then return end

  local drv = dbDriver()
  if drv == "ox" then
    oxExec(SQL_AP_DELETE_OX, { did, charid })
  elseif drv == "mysql" then
    myExecute(SQL_AP_DELETE_MY, { ["@d"] = did, ["@c"] = charid })
  end
end

RegisterNetEvent("azfw:delete_character", function(charid)
  local src = source
  local did = getDiscordID(src)
  if did == "" then
    sendUiIssue(src, makeNoDiscordIssue())
    return
  end
  if not charid then return end

  clearUiIssue(src, "no_discord")
  charid = tostring(charid)

  local drv = dbDriver()
  if drv == "ox" then
    oxExec(SQL_DEL_CHAR_OX, { did, charid })
  elseif drv == "mysql" then
    myExecute(SQL_DEL_CHAR_MY, { ["@d"] = did, ["@c"] = charid })
  end

  if Config.EnableFiveAppearance then
    dbDeleteAppearance(did, charid)
    purgeAppearanceCacheForDid(did)
  end

  TriggerClientEvent("azfw:characters_updated", src, fetchCharactersForSource(src) or {})
  pushAllAppearances(src)
  if activeCharacters[tostring(src)] == charid then clearUiActiveCharacter(src) end
end)

local FINAL_SAVE_WAIT_MS = 1200

local function requestClientFinalSave(src, reason)
  if not src or src == 0 then return end
  TriggerClientEvent("azfw:finalSave:request", src, tostring(reason or "unknown"))
end

local function getServerPlayerPos(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  local c = GetEntityCoords(ped)
  if not c then return nil end
  local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
  if not x or not y or not z then return nil end
  local h = tonumber(GetEntityHeading(ped)) or 0.0
  return x, y, z, h
end

local function serverSaveLastPosNow(src, reason)
  if not Config.EnableLastLocation then return end
  local did = getDiscordID(src)
  if did == "" then return end
  local charid = activeCharacters[tostring(src)]
  if not charid or tostring(charid) == "" then return end
  charid = tostring(charid)
  if not verifyCharOwner(did, charid) then return end

  local x, y, z, h = getServerPlayerPos(src)
  if not x then return end
  dbSaveLastPosByChar(did, charid, x, y, z, h or 0.0)
  dprint("serverSaveLastPosNow src=%s charid=%s reason=%s", tostring(src), tostring(charid), tostring(reason or ""))
end

local function broadcastFinalSave(reason)
  local players = GetPlayers() or {}
  for _, s in ipairs(players) do
    local src = tonumber(s)
    if src and GetPlayerName(src) then
      requestClientFinalSave(src, reason)
    end
  end

  Wait(FINAL_SAVE_WAIT_MS)

  for _, s in ipairs(players) do
    local src = tonumber(s)
    if src and GetPlayerName(src) then
      serverSaveLastPosNow(src, "server_fallback_" .. tostring(reason or ""))
    end
  end
end

AddEventHandler("onResourceStop", function(res)
  if res ~= RESOURCE_NAME then return end
  dprint("onResourceStop -> requesting final saves")
  broadcastFinalSave("resourceStop")
end)

RegisterNetEvent("txAdmin:events:serverShuttingDown", function()
  dprint("txAdmin:serverShuttingDown -> requesting final saves")
  broadcastFinalSave("txAdminShutdown")
end)

RegisterNetEvent("txAdmin:events:scheduledRestart", function()
  dprint("txAdmin:scheduledRestart -> requesting final saves")
  broadcastFinalSave("txAdminRestart")
end)

AddEventHandler("playerJoining", function()
  local src = source
  CreateThread(function()
    Wait(800)
    if GetPlayerName(src) then
      computeAndSendAdmin(src, "playerJoining")
    end
  end)
end)

AddEventHandler("playerDropped", function(reason)
  local src = source
  local did = getDiscordID(src)

  if Config.EnableLastLocation and did ~= "" then
    local charid = nil
    local x, y, z, h = nil, nil, nil, nil

    local v = lastLoc[src]
    if v and v.charid and v.x and v.y and v.z then
      charid = tostring(v.charid)
      x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
      h = tonumber(v.h) or 0.0
    else
      local ac = activeCharacters[tostring(src)]
      if ac and tostring(ac) ~= "" then
        charid = tostring(ac)
        x, y, z, h = getServerPlayerPos(src)
      end
    end

    if charid and charid ~= "" and x and y and z then
      if verifyCharOwner(did, charid) then
        dbSaveLastPosByChar(did, charid, x, y, z, h or 0.0)
        dprint("playerDropped lastpos saved src=%s charid=%s reason=%s", tostring(src), tostring(charid), tostring(reason or ""))
      else
        dprint("playerDropped lastpos skip (not owner) src=%s charid=%s", tostring(src), tostring(charid))
      end
    end
  end

  clearUiActiveCharacter(src)
  lastLoc[src] = nil
  prevBuckets[src] = nil
  adminCache[src] = nil

  if did ~= "" then
    purgeAppearanceCacheForDid(did)
  end
end)

iprint("^2server.lua LOADED (resource=%s)^7", tostring(RESOURCE_NAME))

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("az_characterui:firstjoin:shouldShowWelcome", function(src)
    if not Config.UseFirstJoin then return false end

    Config.FirstJoin = Config.FirstJoin or {}
    Config.FirstJoin.Welcome = Config.FirstJoin.Welcome or {}

    if Config.FirstJoin.Welcome.ShowEverySession ~= false then
      return true
    end

    if Config.FirstJoin.Welcome.PersistOncePerPlayer == false then
      return true
    end

    local identity = firstJoinGetIdentity(src)
    local seen = GetResourceKvpInt(welcomeKey(identity))
    return not (seen and seen == 1)
  end)

  lib.callback.register("az_characterui:firstjoin:claimFirstCar", function(src)
    if not Config.UseFirstJoin then
      return { ok = false, remaining = 0, reason = "disabled" }
    end

    Config.FirstJoin = Config.FirstJoin or {}
    Config.FirstJoin.FirstCar = Config.FirstJoin.FirstCar or {}

    local cooldown = tonumber(Config.FirstJoin.FirstCar.CooldownSeconds) or (24 * 60 * 60)
    local identity = firstJoinGetIdentity(src)
    local key = firstCarKey(identity)

    local lastClaim = GetResourceKvpInt(key) or 0
    local now = os.time()

    if lastClaim > 0 then
      local elapsed = now - lastClaim
      if elapsed < cooldown then
        return { ok = false, remaining = math.max(0, cooldown - elapsed) }
      end
    end

    SetResourceKvpInt(key, now)
    return { ok = true, remaining = 0 }
  end)
end

RegisterNetEvent("az_characterui:firstjoin:markWelcomeSeen", function()
  local src = source
  if not Config.UseFirstJoin then return end

  Config.FirstJoin = Config.FirstJoin or {}
  Config.FirstJoin.Welcome = Config.FirstJoin.Welcome or {}

  if Config.FirstJoin.Welcome.ShowEverySession ~= false then
    return
  end

  if Config.FirstJoin.Welcome.PersistOncePerPlayer == false then
    return
  end

  local identity = firstJoinGetIdentity(src)
  SetResourceKvpInt(welcomeKey(identity), 1)
end)
