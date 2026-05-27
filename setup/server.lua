local RESOURCE = GetCurrentResourceName()
local SETUP_TABLE = "az_framework_setup"

local function hasOx()
  return GetResourceState("oxmysql") == "started" and exports.oxmysql ~= nil
end

local function dbFetch(sql, params, cb)
  params = params or {}
  if hasOx() then
    exports.oxmysql:query(sql, params, function(rows)
      cb(rows or {})
    end)
    return
  end
  if MySQL and MySQL.Async and MySQL.Async.fetchAll then
    MySQL.Async.fetchAll(sql, params, function(rows)
      cb(rows or {})
    end)
    return
  end
  cb({})
end

local function dbExec(sql, params, cb)
  params = params or {}
  if hasOx() then
    exports.oxmysql:execute(sql, params, function(result)
      if cb then cb(result) end
    end)
    return
  end
  if MySQL and MySQL.Async and MySQL.Async.execute then
    MySQL.Async.execute(sql, params, function(result)
      if cb then cb(result) end
    end)
    return
  end
  if cb then cb(false) end
end

local function encode(value)
  local ok, out = pcall(json.encode, value)
  return ok and out or tostring(value or "")
end

local function decode(value)
  if type(value) ~= "string" or value == "" then return nil end
  local ok, out = pcall(json.decode, value)
  if ok then return out end
  return value
end

local function getIdentifier(src)
  local license, fallback
  for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
    if id:sub(1, 8) == "license:" then license = id end
    if not fallback then fallback = id end
  end
  return license or fallback or ("source:%s"):format(src)
end

local function isAdmin(src)
  if src == 0 then return true end
  if IsPlayerAceAllowed(src, "azadmin.use") or IsPlayerAceAllowed(src, "azframework.setup") or IsPlayerAceAllowed(src, "command.framework") then
    return true
  end
  local ok, result = pcall(function()
    return exports[RESOURCE]:isAdmin(src)
  end)
  return ok and result == true
end

local function ensureSetupTable(cb)
  dbExec(([[
CREATE TABLE IF NOT EXISTS `%s` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `setup_key` varchar(64) NOT NULL,
  `setup_value` longtext DEFAULT NULL,
  `updated_by` varchar(128) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_setup_key` (`setup_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]):format(SETUP_TABLE), {}, function()
    if cb then cb() end
  end)
end

local function loadSetup(cb)
  ensureSetupTable(function()
    dbFetch(("SELECT setup_key, setup_value FROM `%s`"):format(SETUP_TABLE), {}, function(rows)
      local state = {}
      for _, row in ipairs(rows or {}) do
        state[tostring(row.setup_key)] = decode(row.setup_value)
      end
      cb(state)
    end)
  end)
end

local function saveSetup(key, value, src, cb)
  ensureSetupTable(function()
    dbExec(("INSERT INTO `%s` (setup_key, setup_value, updated_by) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE setup_value = VALUES(setup_value), updated_by = VALUES(updated_by)"):format(SETUP_TABLE), {
      key,
      encode(value),
      src and getIdentifier(src) or "server"
    }, cb)
  end)
end

local function addCheck(checks, id, label, status, detail, required)
  checks[#checks + 1] = {
    id = id,
    label = label,
    status = status,
    detail = detail,
    required = required == true
  }
end

local function resourceCheck(checks, name, label, required)
  local state = GetResourceState(name)
  local ok = state == "started"
  addCheck(checks, name, label or name, ok and "ok" or (required and "error" or "warn"), ok and "started" or state, required)
end

local function appearanceCheck(checks)
  local state = GetResourceState("fivem-appearance")
  if state ~= "started" then
    addCheck(checks, "fivem-appearance", "fivem-appearance", "warn", state, false)
    return
  end

  local hasGame = LoadResourceFile("fivem-appearance", "game/dist/index.js")
  local hasUi = LoadResourceFile("fivem-appearance", "web/dist/index.html")
  if not hasGame or not hasUi then
    addCheck(checks, "fivem-appearance", "fivem-appearance", "warn", "started, but release build files are missing", false)
    return
  end

  addCheck(checks, "fivem-appearance", "fivem-appearance", "ok", "started with release build files", false)
end

local function convarCheck(checks, id, label, convarName, required)
  local value = GetConvar(convarName, "")
  local configured = value ~= nil and value ~= ""
  addCheck(checks, id, label, configured and "ok" or (required and "error" or "warn"), configured and "configured" or "not configured", required)
end

local function permissionCheck(checks, src)
  local setupOk = src == 0 or IsPlayerAceAllowed(src, "azframework.setup") or IsPlayerAceAllowed(src, "azadmin.use") or IsPlayerAceAllowed(src, "command.framework")
  addCheck(checks, "admin_roles", "Admin roles", setupOk and "ok" or "warn", setupOk and "admin/setup permission detected" or "add azframework.setup or azadmin.use to your admin group", false)
end

local function tableChecks(checks, cb)
  local needed = {
    az_framework_setup = "Setup state",
    user_characters = "Characters",
    econ_user_money = "Money accounts",
    user_vehicles = "Vehicles",
    azfw_appearance = "Appearance saves"
  }
  dbFetch("SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name IN ('az_framework_setup','user_characters','econ_user_money','user_vehicles','azfw_appearance')", {}, function(rows)
    local found = {}
    for _, row in ipairs(rows or {}) do
      found[tostring(row.table_name or row.TABLE_NAME or "")] = true
    end
    for tableName, label in pairs(needed) do
      addCheck(checks, "table:" .. tableName, label, found[tableName] and "ok" or "error", found[tableName] and "table ready" or "missing table", true)
    end
    cb()
  end)
end

local function buildPayload(src, reason, cb)
  loadSetup(function(state)
    local checks = {}
    resourceCheck(checks, "oxmysql", "oxmysql database driver", true)
    resourceCheck(checks, "ox_lib", "ox_lib", true)
    resourceCheck(checks, "ox_target", "ox_target", false)
    resourceCheck(checks, "ox_inventory", "ox_inventory", false)
    appearanceCheck(checks)
    resourceCheck(checks, "AMenu", "AMenu", false)
    resourceCheck(checks, "AMenu-Bridge", "AMenu-Bridge", false)
    resourceCheck(checks, "qb-core", "qb-core bridge folder", false)
    resourceCheck(checks, "qb-inventory", "qb-inventory bridge folder", false)
    resourceCheck(checks, "qb-target", "qb-target bridge folder", false)
    resourceCheck(checks, "es_extended", "ESX bridge folder", false)
    resourceCheck(checks, "ND_Core", "ND Core bridge folder", false)

    local conn = GetConvar("mysql_connection_string", "")
    addCheck(checks, "mysql_connection_string", "Database connection string", conn ~= "" and "ok" or "error", conn ~= "" and "configured" or "missing", true)
    addCheck(checks, "admin", "Admin permission", isAdmin(src) and "ok" or "warn", isAdmin(src) and "admin detected" or "not an admin", false)
    permissionCheck(checks, src)
    convarCheck(checks, "discord_bot_token", "Discord bot token", "DISCORD_BOT_TOKEN", false)
    convarCheck(checks, "discord_guild_id", "Discord guild ID", "DISCORD_GUILD_ID", false)

    tableChecks(checks, function()
      local completeReady = true
      for _, check in ipairs(checks) do
        if check.required and check.status == "error" then
          completeReady = false
          break
        end
      end
      cb({
        reason = reason or "open",
        firstRun = state.completed ~= true,
        completed = state.completed == true,
        ownerIdentifier = state.ownerIdentifier,
        settings = type(state.settings) == "table" and state.settings or {},
        canClose = state.completed == true or isAdmin(src),
        canComplete = completeReady,
        isAdmin = isAdmin(src),
        checks = checks
      })
    end)
  end)
end

local function openFor(src, reason)
  if not src or src <= 0 then return end
  buildPayload(src, reason, function(payload)
    TriggerClientEvent("azfw:setup:open", src, payload)
  end)
end

RegisterNetEvent("azfw:setup:playerReady", function()
  local src = source
  loadSetup(function(state)
    if state.completed == true then return end
    local identifier = getIdentifier(src)
    if not state.ownerIdentifier or state.ownerIdentifier == "" then
      dbFetch("SELECT COUNT(*) AS count FROM `user_characters`", {}, function(rows)
        local count = tonumber(rows and rows[1] and (rows[1].count or rows[1]["COUNT(*)"])) or 0
        if count > 0 then return end
        saveSetup("ownerIdentifier", identifier, src, function()
          openFor(src, "first_player")
        end)
      end)
      return
    end
    if state.ownerIdentifier == identifier or isAdmin(src) then
      openFor(src, "resume_setup")
    end
  end)
end)

RegisterNetEvent("azfw:setup:requestOpen", function()
  local src = source
  loadSetup(function(state)
    local identifier = getIdentifier(src)
    if isAdmin(src) or state.ownerIdentifier == identifier then
      openFor(src, "command")
      return
    end
    TriggerClientEvent("az-framework:hudNotify", src, {
      title = "Az Framework",
      description = "You do not have permission to open framework setup.",
      type = "error"
    })
  end)
end)

RegisterNetEvent("azfw:setup:action", function(data)
  local src = source
  if type(data) ~= "table" then data = {} end
  loadSetup(function(state)
    local identifier = getIdentifier(src)
    if not isAdmin(src) and state.ownerIdentifier ~= identifier then return end

    local action = tostring(data.action or "refresh")
    if action == "save" then
      saveSetup("settings", type(data.settings) == "table" and data.settings or {}, src, function()
        openFor(src, "saved")
      end)
      return
    end
    if action == "complete" then
      buildPayload(src, "complete", function(payload)
        if payload.canComplete ~= true then
          TriggerClientEvent("azfw:setup:update", src, payload)
          return
        end
        saveSetup("settings", type(data.settings) == "table" and data.settings or payload.settings or {}, src, function()
          saveSetup("completed", true, src, function()
            TriggerClientEvent("azfw:setup:close", src)
          end)
        end)
      end)
      return
    end
    buildPayload(src, action, function(payload)
      TriggerClientEvent("azfw:setup:update", src, payload)
    end)
  end)
end)

RegisterNetEvent("azfw:setup:close", function()
end)

AddEventHandler("onResourceStart", function(resource)
  if resource ~= RESOURCE then return end
  ensureSetupTable()
end)
