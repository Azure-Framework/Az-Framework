local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
Config.Debug = Config.Debug or false
Config.Discord = Config.Discord or {}
Config.PaycheckIntervalMinutes = tonumber(Config.PaycheckIntervalMinutes) or 60

Config.Discord.BotToken   = Config.Discord.BotToken   or GetConvar("DISCORD_BOT_TOKEN", "")
Config.Discord.WebhookURL = Config.Discord.WebhookURL or GetConvar("DISCORD_WEBHOOK_URL", "")
Config.Discord.GuildId    = Config.Discord.GuildId    or GetConvar("DISCORD_GUILD_ID", "")

Config.AdminRoleId        = tostring(Config.AdminRoleId or GetConvar("AZFW_ADMIN_ROLE_ID", "") or "")
Config.AdminAcePermission = Config.AdminAcePermission or "adminmenu.use"

local T = {
  money = "econ_user_money",
  accts = "econ_accounts",
  dept  = "econ_departments",
}

local SAVINGS_APR = 0.05

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

local function __azfwActiveProxy(kind)
  local localStore = {}

  local function keyFor(k)
    if kind == "discord" then return __azfwDiscordKey(k) end
    return __azfwSourceKey(k)
  end

  local function globalStore()
    if kind == "discord" then return __AZFW_ACTIVE_STORE.byDiscord end
    return __AZFW_ACTIVE_STORE.bySource
  end

  return setmetatable({}, {
    __index = function(_, k)
      local key = keyFor(k)
      if key == "" then return nil end
      local gs = globalStore()
      return gs[key] or localStore[key]
    end,
    __newindex = function(_, k, v)
      local key = keyFor(k)
      if key == "" then return end
      local gs = globalStore()
      if v == nil or tostring(v) == "" then
        gs[key] = nil
        localStore[key] = nil
        __AZFW_ACTIVE_STORE.updated[key] = os.time()
        return
      end
      local value = tostring(v)
      gs[key] = value
      localStore[key] = value
      __AZFW_ACTIVE_STORE.updated[key] = os.time()
    end,
    __pairs = function()
      return next, globalStore(), nil
    end
  })
end

local activeCharacters = __azfwActiveProxy("source")
local activeCharByDiscord = __azfwActiveProxy("discord")
local lastDeptReq = {}
local lastDeptSet = {}
local lastDeptValue = {}

local function setFrameworkActiveCharacter(src, did, charId, reason, activeDepartment)
  src = tonumber(src or 0) or 0
  local cid = tostring(charId or "")
  if src <= 0 or cid == "" then return false end

  activeCharacters[src] = cid

  did = __azfwDiscordKey(did)
  if did ~= "" then
    activeCharByDiscord[did] = cid
  end

  if Player and Player(src) and Player(src).state then
    Player(src).state:set("az_active_character", cid, true)
    Player(src).state:set("az_active_charid", cid, true)
    Player(src).state:set("activeCharacter", cid, true)
    Player(src).state:set("charid", cid, true)
  end

  if activeDepartment ~= nil then
    lastDeptValue[src] = tostring(activeDepartment or ""):lower()
  end

  local sk = __azfwSourceKey(src)
  __AZFW_ACTIVE_STORE.reason[sk] = tostring(reason or "unknown")
  __AZFW_ACTIVE_STORE.updated[sk] = os.time()
  return true
end

local function getFrameworkActiveCharacter(src, did)
  src = tonumber(src or 0) or 0
  if src > 0 then
    local cid = tostring(activeCharacters[src] or "")
    if cid ~= "" then return cid end
    if Player and Player(src) and Player(src).state then
      cid = tostring(Player(src).state.az_active_character or Player(src).state.az_active_charid or Player(src).state.activeCharacter or Player(src).state.charid or "")
      if cid ~= "" and cid ~= "nil" and cid ~= "unknown" then
        activeCharacters[src] = cid
        return cid
      end
    end
  end

  did = __azfwDiscordKey(did)
  if did ~= "" then
    local cid = tostring(activeCharByDiscord[did] or "")
    if cid ~= "" then return cid end
  end

  return nil
end

local function clearFrameworkActiveCharacter(src)
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

local function dprint(...)
  if not Config.Debug then return end
  local args = { ... }
  for i=1,#args do args[i] = tostring(args[i]) end
  print(("^3[%s]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local function safeCb(cb, ...)
  if type(cb) == "function" then
    return cb(...)
  end
end

local function trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function resolveSourceId(arg)
  local s = tonumber(arg)
  if s and s > 0 then return s end
  local g = tonumber(_G.source)
  if g and g > 0 then return g end
  return nil
end

local function stripSelf(...)
  local a = { ... }
  local t = type(a[1])
  if t == "table" or t == "userdata" then
    table.remove(a, 1)
  end
  return table.unpack(a)
end

local MODULES = Config.Modules or {}
local CHARACTER_CFG = Config.Character or {}
local DEPT_SETUP = Config.DepartmentsConfig or {}
local PAYCHECK_CFG = Config.Paychecks or {}

local function moduleEnabled(name, fallback)
  local v = MODULES[name]
  if v == nil then return fallback == true end
  return v == true
end

local function lower(v)
  return tostring(v or ""):lower()
end

local function isCharacterUiMode()
  local mode = lower(CHARACTER_CFG.Mode or (moduleEnabled("CharacterUI", false) and "ui" or "discord"))
  return mode == "ui" and moduleEnabled("CharacterUI", false)
end

local function isDiscordCharacterMode()
  return not isCharacterUiMode()
end

local configuredDepartmentsById = {}
local configuredDepartmentsOrdered = {}
local configuredDepartmentsSourceList = {}
local DEPT_RUNTIME_FILE = tostring(DEPT_SETUP.RuntimeFile or "config/departments_runtime.json")

local function cloneConfiguredDepartmentRow(row)
  return {
    id = tostring(row.id or ""),
    label = tostring(row.label or ""),
    paycheck = tonumber(row.paycheck) or 0,
    canUseAOP = row.canUseAOP == true,
    canUsePrio = row.canUsePrio == true,
    enabled = row.enabled ~= false,
  }
end

local function normalizeConfiguredDepartmentRow(entry)
  if type(entry) ~= "table" then return nil end

  local id = trim(entry.id or entry.name or entry.department or entry.label)
  local label = trim(entry.label or entry.name or entry.department or entry.id)

  if id == "" and label == "" then
    return nil
  end

  if id == "" then id = label end
  if label == "" then label = id end

  return {
    id = lower(id),
    label = label,
    paycheck = tonumber(entry.paycheck) or 0,
    canUseAOP = entry.canUseAOP == true,
    canUsePrio = entry.canUsePrio == true,
    enabled = entry.enabled ~= false,
  }
end

local function rebuildConfiguredDepartments(list)
  configuredDepartmentsById = {}
  configuredDepartmentsOrdered = {}
  configuredDepartmentsSourceList = {}

  for _, entry in ipairs(list or {}) do
    local norm = normalizeConfiguredDepartmentRow(entry)
    if norm then
      configuredDepartmentsSourceList[#configuredDepartmentsSourceList + 1] = cloneConfiguredDepartmentRow(norm)
      if norm.enabled ~= false then
        configuredDepartmentsById[norm.id] = norm
        configuredDepartmentsById[lower(norm.label)] = norm
        configuredDepartmentsOrdered[#configuredDepartmentsOrdered + 1] = norm
      end
    end
  end
end

local function loadConfiguredDepartmentsRuntime()
  local raw = LoadResourceFile(RESOURCE_NAME, DEPT_RUNTIME_FILE)
  if not raw or raw == "" then return nil end

  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  if decoded.override ~= true then
    return nil
  end

  if type(decoded.list) ~= "table" then
    return {}
  end

  return decoded.list
end

local function saveConfiguredDepartmentsRuntime(list)
  local payload = {
    override = true,
    list = {},
  }

  for _, entry in ipairs(list or {}) do
    local norm = normalizeConfiguredDepartmentRow(entry)
    if norm then
      payload.list[#payload.list + 1] = cloneConfiguredDepartmentRow(norm)
    end
  end

  local encoded = json.encode(payload)
  return SaveResourceFile(RESOURCE_NAME, DEPT_RUNTIME_FILE, encoded, -1)
end

local function getConfiguredDepartmentsExport()
  local out = {}
  for _, row in ipairs(configuredDepartmentsSourceList) do
    out[#out + 1] = cloneConfiguredDepartmentRow(row)
  end
  return out
end

local function setConfiguredDepartmentsExport(list)
  if type(list) ~= "table" then
    return false, "Invalid department list"
  end

  local cleaned = {}
  local seen = {}
  for _, entry in ipairs(list) do
    local norm = normalizeConfiguredDepartmentRow(entry)
    if norm and not seen[norm.id] then
      seen[norm.id] = true
      cleaned[#cleaned + 1] = norm
    end
  end

  DEPT_SETUP.List = {}
  for _, row in ipairs(cleaned) do
    DEPT_SETUP.List[#DEPT_SETUP.List + 1] = cloneConfiguredDepartmentRow(row)
  end

  rebuildConfiguredDepartments(DEPT_SETUP.List)
  saveConfiguredDepartmentsRuntime(DEPT_SETUP.List)
  return true, getConfiguredDepartmentsExport()
end

local function upsertConfiguredDepartmentExport(entry)
  local norm = normalizeConfiguredDepartmentRow(entry)
  if not norm then
    return false, "Invalid department"
  end

  local list = getConfiguredDepartmentsExport()
  local replaced = false

  for i = 1, #list do
    if lower(list[i].id) == norm.id then
      list[i] = cloneConfiguredDepartmentRow(norm)
      replaced = true
      break
    end
  end

  if not replaced then
    list[#list + 1] = cloneConfiguredDepartmentRow(norm)
  end

  return setConfiguredDepartmentsExport(list)
end

local function removeConfiguredDepartmentExport(id)
  id = lower(trim(id))
  if id == "" then
    return false, "Missing department id"
  end

  local current = getConfiguredDepartmentsExport()
  local nextList = {}
  for _, row in ipairs(current) do
    if lower(row.id) ~= id then
      nextList[#nextList + 1] = row
    end
  end

  return setConfiguredDepartmentsExport(nextList)
end

do
  local runtimeList = loadConfiguredDepartmentsRuntime()
  if type(runtimeList) == "table" then
    DEPT_SETUP.List = runtimeList
  end
  rebuildConfiguredDepartments(DEPT_SETUP.List or {})
end

local function useConfiguredDepartments()
  return Config.Departments == true and DEPT_SETUP.UseSimpleList == true and #configuredDepartmentsOrdered > 0
end

local function getConfiguredDepartment(dept)
  return configuredDepartmentsById[lower(dept)]
end

local function getConfiguredDepartmentPaycheck(dept)
  local cfg = getConfiguredDepartment(dept)
  if not cfg then return nil end
  return tonumber(cfg.paycheck) or 0
end

local autoCharacterInFlight = {}

local function finishAutoCharacter(src, ok, charId, reason)
  local inflight = autoCharacterInFlight[src]
  if not inflight then return end
  autoCharacterInFlight[src] = nil
  for _, cb in ipairs(inflight.cbs or {}) do
    safeCb(cb, ok == true, charId, reason)
  end
end

local function hasOx()
  return exports.oxmysql ~= nil
end

local function oxQuery(query, params, cb)
  params = params or {}
  if not hasOx() or not exports.oxmysql.query then
    dprint("oxmysql not available: query")
    return safeCb(cb, {})
  end
  exports.oxmysql:query(query, params, function(res)
    safeCb(cb, res or {})
  end)
end

local function oxExecute(query, params, cb)
  params = params or {}
  if not hasOx() or not exports.oxmysql.execute then
    dprint("oxmysql not available: execute")
    return safeCb(cb, 0)
  end
  exports.oxmysql:execute(query, params, function(res)
    safeCb(cb, res or 0)
  end)
end

local function oxInsert(query, params, cb)
  params = params or {}
  if not hasOx() or not exports.oxmysql.insert then
    dprint("oxmysql not available: insert")
    return safeCb(cb, nil)
  end
  exports.oxmysql:insert(query, params, function(insertId)
    safeCb(cb, insertId)
  end)
end

local function oxScalar(query, params, cb)
  oxQuery(query, params, function(rows)
    if rows and rows[1] then
      for _, v in pairs(rows[1]) do
        return safeCb(cb, v)
      end
    end
    safeCb(cb, nil)
  end)
end

if MySQL == nil then MySQL = {} end
if MySQL.Async == nil then MySQL.Async = {} end
if type(MySQL.Async.fetchAll) ~= "function" then
  MySQL.Async.fetchAll = function(query, params, cb) oxQuery(query, params, cb) end
end
if type(MySQL.Async.execute) ~= "function" then
  MySQL.Async.execute = function(query, params, cb) oxExecute(query, params, cb) end
end
if type(MySQL.Async.insert) ~= "function" then
  MySQL.Async.insert = function(query, params, cb) oxInsert(query, params, cb) end
end
if type(MySQL.Async.scalar) ~= "function" then
  MySQL.Async.scalar = function(query, params, cb) oxScalar(query, params, cb) end
end

local function getDiscordID(src)
  src = tonumber(src or 0) or 0
  if src <= 0 then return "" end

  local ids = GetPlayerIdentifiers(src)
  if type(ids) ~= "table" then return "" end

  for _, id in ipairs(ids) do
    if type(id) == "string" and id:sub(1,8) == "discord:" then
      return id:sub(9)
    end
  end
  return ""
end

local function buildAutoCharacterName(src, discordID)
  local playerName = trim(GetPlayerName(src) or "")
  if playerName == "" then
    playerName = "Player " .. tostring(src)
  end

  local first = trim(CHARACTER_CFG.DefaultFirstName or "Discord")
  local lastMode = lower(CHARACTER_CFG.DefaultLastNameFrom or "player")
  local last = trim(CHARACTER_CFG.DefaultLastName or "Player")

  if lastMode == "player" then
    last = playerName
  elseif lastMode == "discord" then
    last = tostring(discordID or "Player")
  end

  if first == "" then first = "Discord" end
  if last == "" then last = "Player" end
  return first, last
end

local function getPreferredCharacterId(src, discordID)
  local base = trim(CHARACTER_CFG.DefaultCharacterId or "main")
  if base == "" then base = "main" end
  return base
end

local function setActiveCharacterContext(src, did, charId, activeDepartment)
  return setFrameworkActiveCharacter(src, did, charId, "setActiveCharacterContext", activeDepartment)
end

local function ensureCharacterReady(src, cb)
  if type(cb) ~= "function" then return end

  src = resolveSourceId(src)
  if not src then
    return cb(false, nil, "invalid_source")
  end

  local did = getDiscordID(src)
  if did == "" then
    return cb(false, nil, "no_discord_id")
  end

  if activeCharacters[src] and activeCharacters[src] ~= "" then
    return cb(true, activeCharacters[src], "active")
  end

  if activeCharByDiscord[did] and activeCharByDiscord[did] ~= "" then
    activeCharacters[src] = activeCharByDiscord[did]
    return cb(true, activeCharacters[src], "cached")
  end

  if not isDiscordCharacterMode() or CHARACTER_CFG.AutoCreateDiscordCharacter == false then
    return cb(false, nil, "ui_mode")
  end

  if autoCharacterInFlight[src] then
    table.insert(autoCharacterInFlight[src].cbs, cb)
    return
  end
  autoCharacterInFlight[src] = { cbs = { cb } }

  local preferredCharId = getPreferredCharacterId(src, did)

  local function done(ok, charId, reason)
    finishAutoCharacter(src, ok, charId, reason)
  end

  oxQuery("SELECT charid, active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, preferredCharId }, function(rows)
    if rows and rows[1] and rows[1].charid then
      setActiveCharacterContext(src, did, rows[1].charid, rows[1].active_department)
      return done(true, rows[1].charid, "preferred_existing")
    end

    oxQuery("SELECT charid, active_department FROM user_characters WHERE discordid=? ORDER BY id ASC LIMIT 1", { did }, function(existing)
      if existing and existing[1] and existing[1].charid then
        setActiveCharacterContext(src, did, existing[1].charid, existing[1].active_department)
        return done(true, existing[1].charid, "existing")
      end

      local firstName, lastName = buildAutoCharacterName(src, did)
      local fullName = trim(firstName .. " " .. lastName)
      local defaultLicense = (Config.Licenses and Config.Licenses.DefaultHuntingLicense == true) and 1 or 0

      oxInsert(
        "INSERT INTO user_characters (discordid,charid,name,active_department,hunting_license) VALUES (?,?,?,?,?)",
        { did, preferredCharId, fullName, "", defaultLicense },
        function(insertId)
          if not insertId then
            oxQuery("SELECT charid, active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, preferredCharId }, function(recheck)
              if recheck and recheck[1] and recheck[1].charid then
                setActiveCharacterContext(src, did, recheck[1].charid, recheck[1].active_department)
                return done(true, recheck[1].charid, "race_recovered")
              end
              return done(false, nil, "create_failed")
            end)
            return
          end

          oxExecute(
            ("INSERT IGNORE INTO `%s` (discordid,charid,firstname,lastname,cash,bank,last_daily,card_status) VALUES (?,?,?,?,?,?,?,?)"):format(T.money),
            { did, preferredCharId, firstName, lastName, 0, 0, 0, "active" },
            function()
              setActiveCharacterContext(src, did, preferredCharId, "")
              done(true, preferredCharId, "created")
            end
          )
        end
      )
    end)
  end)
end

local roleCache = {}
local roleInFlight = {}
local ROLE_TTL_MS = 5 * 60 * 1000

local function getDiscordRoleList(src, cb)
  if type(cb) ~= "function" then return end

  src = resolveSourceId(src)
  if not src then return cb("invalid_source", nil) end

  local discordID = getDiscordID(src)
  if discordID == "" then return cb("no_discord_id", nil) end

  local now = GetGameTimer()

  local c = roleCache[discordID]
  if c and c.exp and c.exp > now and type(c.roles) == "table" then
    return cb(nil, c.roles)
  end

  if roleInFlight[discordID] then
    table.insert(roleInFlight[discordID].cbs, cb)
    return
  end
  roleInFlight[discordID] = { cbs = { cb } }

  local guildId  = Config.Discord.GuildId or ""
  local botToken = Config.Discord.BotToken or ""
  if guildId == "" or botToken == "" then
    local cbs = roleInFlight[discordID].cbs
    roleInFlight[discordID] = nil
    for _, f in ipairs(cbs) do f("config_error", nil) end
    return
  end

  local url = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(guildId, discordID)

  PerformHttpRequest(url, function(status, body)
    local cbs = roleInFlight[discordID] and roleInFlight[discordID].cbs or {}
    roleInFlight[discordID] = nil

    if status ~= 200 or not body or body == "" then
      for _, f in ipairs(cbs) do f("http_" .. tostring(status), nil) end
      return
    end

    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" or type(data.roles) ~= "table" then
      for _, f in ipairs(cbs) do f("bad_json", nil) end
      return
    end

    roleCache[discordID] = { roles = data.roles, exp = GetGameTimer() + ROLE_TTL_MS }
    for _, f in ipairs(cbs) do f(nil, data.roles) end
  end, "GET", "", {
    ["Authorization"] = "Bot " .. botToken,
    ["Content-Type"]  = "application/json"
  })
end

local function isAdmin_impl(playerSrc, cb)
  playerSrc = resolveSourceId(playerSrc)
  if not playerSrc then
    return safeCb(cb, false, "invalid_source")
  end

  if playerSrc == 0 then
    return safeCb(cb, true, "console")
  end

  local acePerm = Config.AdminAcePermission or "adminmenu.use"
  local aceAllowed = IsPlayerAceAllowed(playerSrc, acePerm)
  if aceAllowed then
    return safeCb(cb, true, "ace")
  end

  local wanted = tostring(Config.AdminRoleId or "")
  if wanted == "" or wanted == "nil" then
    return safeCb(cb, false, "no_role_config")
  end

  getDiscordRoleList(playerSrc, function(err, roles)
    if err or type(roles) ~= "table" then
      return safeCb(cb, false, err or "role_fetch_failed")
    end
    for _, roleId in ipairs(roles) do
      if tostring(roleId) == wanted then
        return safeCb(cb, true, "role")
      end
    end
    return safeCb(cb, false, "no_match")
  end)
end

local function isAdmin_export(...)
  local src, cb = stripSelf(...)

  if type(src) == "function" then
    cb = src
    src = resolveSourceId(nil)
  end

  if src == nil and cb == nil then
    src = resolveSourceId(nil)
  end

  if type(cb) == "function" then
    return isAdmin_impl(src, cb)
  end

  local p = promise.new()
  local done = false
  isAdmin_impl(src, function(ok)
    if done then return end
    done = true
    p:resolve(ok == true)
  end)

  SetTimeout(1500, function()
    if done then return end
    done = true
    local s = resolveSourceId(src)
    if s and s > 0 then
      local acePerm = Config.AdminAcePermission or "adminmenu.use"
      return p:resolve(IsPlayerAceAllowed(s, acePerm) == true)
    end
    p:resolve(false)
  end)

  return Citizen.Await(p)
end

local function sendWebhookLog(message)
  local url = Config.Discord.WebhookURL or ""
  if url == "" then return end

  local payload = { username = "Azure Logger", content = tostring(message) }
  PerformHttpRequest(url, function(statusCode)
    if Config.Debug and statusCode ~= 204 and statusCode ~= 200 then
      dprint("Webhook error:", statusCode)
    end
  end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

local function logAdminCommand(commandName, src, args, success)
  local playerName = (type(src) == "number" and GetPlayerName(src)) or "Unknown"
  local statusIcon = success and "ALLOWED" or "DENIED"
  local argsStr = (type(args) == "table" and table.concat(args, " ")) or tostring(args or "")
  local msg = ("**Admin Command:** `%s`\n**Player:** %s (ID %s)\n**Status:** %s\n**Args:** %s"):format(
    tostring(commandName), tostring(playerName), tostring(src), statusIcon, argsStr
  )
  sendWebhookLog(msg)
end

local function logLargeTransaction(txType, src, amount, reason)
  local playerName = (type(src) == "number" and GetPlayerName(src)) or "Unknown"
  local msg = (":moneybag: **Large Transaction** `%s`\n**Player:** %s (ID %s)\n**Amount:** $%s\n**Reason:** %s"):format(
    tostring(txType), tostring(playerName), tostring(src), tostring(amount), tostring(reason or "")
  )
  sendWebhookLog(msg)
end

local function GetMoney(discordID, charID, callback)
  if type(callback) ~= "function" then return end

  oxQuery(("SELECT cash, bank, last_daily FROM `%s` WHERE discordid=? AND charid=? LIMIT 1"):format(T.money),
    { discordID, charID },
    function(rows)
      if rows and rows[1] then
        return callback(rows[1])
      end

      oxScalar("SELECT name FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
        { discordID, charID },
        function(fullName)
          local first, last = "", ""
          if type(fullName) == "string" then
            local f, l = fullName:match("^(%S+)%s+(%S+)$")
            first, last = f or "", l or ""
          end

          oxInsert(("INSERT INTO `%s` (discordid,charid,firstname,lastname,cash,bank,last_daily) VALUES (?,?,?,?,?,?,?)"):format(T.money),
            { discordID, charID, first, last, 0, 0, 0 },
            function()
              callback({ cash = 0, bank = 0, last_daily = 0 })
            end
          )
        end
      )
    end
  )
end

local function UpdateMoney(discordID, charID, data, cb)
  oxExecute(("UPDATE `%s` SET cash=?, bank=?, last_daily=? WHERE discordid=? AND charid=?"):format(T.money),
    { tonumber(data.cash) or 0, tonumber(data.bank) or 0, tonumber(data.last_daily) or 0, discordID, charID },
    function(affected)
      safeCb(cb, affected)
    end
  )
end

local function ensureChecking(discordID, charID, cb)
  oxQuery(("SELECT id, balance FROM `%s` WHERE charid=? AND type='checking' LIMIT 1"):format(T.accts),
    { charID },
    function(rows)
      if rows and rows[1] and rows[1].id then
        return cb(rows[1].id, tonumber(rows[1].balance) or 0)
      end

      oxInsert(("INSERT INTO `%s` (discordid,charid,type,balance) VALUES (?,?,?,?),(?,?,?,?)"):format(T.accts),
        { discordID, charID, "checking", 0, discordID, charID, "savings", 0 },
        function()
          oxQuery(("SELECT id, balance FROM `%s` WHERE charid=? AND type='checking' LIMIT 1"):format(T.accts),
            { charID },
            function(rows2)
              if rows2 and rows2[1] and rows2[1].id then
                return cb(rows2[1].id, tonumber(rows2[1].balance) or 0)
              end
              cb(nil, 0)
            end
          )
        end
      )
    end
  )
end

local function getFullName(charID, fallbackSrc, cb)
  oxScalar("SELECT name FROM user_characters WHERE charid=? LIMIT 1", { charID }, function(name)
    if name and name ~= "" then return cb(name) end
    cb((fallbackSrc and GetPlayerName(fallbackSrc)) or "No Name")
  end)
end

local MONEY_PUSH_MIN_MS = 2500
local lastMoneyPush = {}

local function canPushMoney(src)
  local now = GetGameTimer()
  local last = lastMoneyPush[src] or 0
  if (now - last) < MONEY_PUSH_MIN_MS then
    return false
  end
  lastMoneyPush[src] = now
  return true
end

local function sendMoneyToClient(playerId, force)
  local src = resolveSourceId(playerId)
  if not src then return end

  if not force and not canPushMoney(src) then
    if Config.Debug then dprint("sendMoneyToClient throttled for src", src) end
    return
  end

  local did = getDiscordID(src)
  local charID = getFrameworkActiveCharacter(src, did)

  if (not charID or charID == "") and isDiscordCharacterMode() then
    return ensureCharacterReady(src, function(ok)
      if ok then
        sendMoneyToClient(src, force)
      end
    end)
  end

  if not charID or charID == "" or did == "" then return end

  GetMoney(did, charID, function(m)
    ensureChecking(did, charID, function(_checkingId, checkingBalance)
      getFullName(charID, src, function(playerName)
        TriggerClientEvent("updateCashHUD", src, tonumber(m.cash) or 0, tonumber(checkingBalance) or 0, playerName)
      end)
    end)
  end)
end

local function withMoney(src, fn)
  src = resolveSourceId(src)
  if not src then return end

  local discordID = getDiscordID(src)
  local charID = getFrameworkActiveCharacter(src, discordID)
  if (not charID or charID == "") and isDiscordCharacterMode() then
    return ensureCharacterReady(src, function(ok)
      if ok then
        withMoney(src, fn)
      else
        TriggerClientEvent('ox_lib:notify', src, { title="Account", description="No character selected.", type="error" })
      end
    end)
  end

  if discordID == "" or not charID then
    TriggerClientEvent('ox_lib:notify', src, { title="Account", description="No character selected.", type="error" })
    return
  end

  GetMoney(discordID, charID, function(data)
    fn(discordID, charID, data, src)
  end)
end

local function addMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = tonumber(amount)
  if not src or not amount then return false end

  withMoney(src, function(dID, cID, data)
    data.cash = (tonumber(data.cash) or 0) + amount
    UpdateMoney(dID, cID, data, function()
      sendMoneyToClient(src, false)
      if amount >= 1e6 then logLargeTransaction("addMoney", src, amount, "addMoney() export") end
    end)
  end)

  return true
end

local function deductMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = tonumber(amount)
  if not src or not amount then return false end

  withMoney(src, function(dID, cID, data)
    data.cash = math.max(0, (tonumber(data.cash) or 0) - amount)
    UpdateMoney(dID, cID, data, function()
      sendMoneyToClient(src, false)
      if amount >= 1e6 then logLargeTransaction("deductMoney", src, amount, "deductMoney() export") end
    end)
  end)

  return true
end

local function depositMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = math.floor(tonumber(amount) or 0)
  if not src or amount <= 0 then return false end

  withMoney(src, function(dID, cID, data)
    if (tonumber(data.cash) or 0) < amount then
      TriggerClientEvent('ox_lib:notify', src, { title="Bank", description="Not enough cash to deposit.", type="error" })
      return
    end

    ensureChecking(dID, cID, function(checkId, bal)
      if not checkId then
        TriggerClientEvent('ox_lib:notify', src, { title="Bank", description="Checking account missing.", type="error" })
        return
      end

      local newBalance = (tonumber(bal) or 0) + amount
      oxExecute(("UPDATE `%s` SET balance=?, discordid=?, charid=? WHERE id=?"):format(T.accts),
        { newBalance, dID, cID, checkId },
        function()
          data.cash = (tonumber(data.cash) or 0) - amount
          data.bank = newBalance
          UpdateMoney(dID, cID, data, function()
            sendMoneyToClient(src, false)
            if amount >= 1e6 then logLargeTransaction("depositMoney", src, amount, "depositMoney() export") end
          end)
        end
      )
    end)
  end)

  return true
end

local function withdrawMoney_export(...)
  local a, b = stripSelf(...)
  local src, amount

  if b == nil then
    src = resolveSourceId(nil)
    amount = a
  else
    src = resolveSourceId(a)
    amount = b
  end

  amount = math.floor(tonumber(amount) or 0)
  if not src or amount <= 0 then return false end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if did == "" or not cid then return false end

  ensureChecking(did, cid, function(checkId, bal)
    if not checkId then return false end
    local current = tonumber(bal) or 0
    if current < amount then
      TriggerClientEvent('ox_lib:notify', src, { title="Bank", description="Not enough bank funds to withdraw.", type="error" })
      return
    end

    local newBalance = current - amount
    oxExecute(("UPDATE `%s` SET balance=?, discordid=?, charid=? WHERE id=?"):format(T.accts),
      { newBalance, did, cid, checkId },
      function()
        withMoney(src, function(dID, cID, data)
          data.bank = newBalance
          data.cash = (tonumber(data.cash) or 0) + amount
          UpdateMoney(dID, cID, data, function()
            sendMoneyToClient(src, false)
            if amount >= 1e6 then logLargeTransaction("withdrawMoney", src, amount, "withdrawMoney() export") end
          end)
        end)
      end
    )
  end)

  return true
end

local function transferMoney_export(...)
  local a, b, c = stripSelf(...)
  local src, target, amount

  if c == nil then
    src = resolveSourceId(nil)
    target = resolveSourceId(a)
    amount = b
  else
    src = resolveSourceId(a)
    target = resolveSourceId(b)
    amount = c
  end

  amount = tonumber(amount)
  if not src or not target or not amount or amount <= 0 then return false end

  local senderID = getDiscordID(src)
  local senderChar = getFrameworkActiveCharacter(src, senderID)
  local targetID = getDiscordID(target)
  local targetChar = getFrameworkActiveCharacter(target, targetID)
  if senderID == "" or not senderChar or targetID == "" or not targetChar then
    return false
  end

  GetMoney(senderID, senderChar, function(sData)
    if (tonumber(sData.cash) or 0) < amount then
      TriggerClientEvent('ox_lib:notify', src, { title="Transfer", description="Not enough cash to transfer.", type="error" })
      return
    end

    GetMoney(targetID, targetChar, function(tData)
      sData.cash = (tonumber(sData.cash) or 0) - amount
      tData.cash = (tonumber(tData.cash) or 0) + amount

      UpdateMoney(senderID, senderChar, sData, function()
        sendMoneyToClient(src, false)
      end)
      UpdateMoney(targetID, targetChar, tData, function()
        sendMoneyToClient(target, false)
      end)

      if amount >= 1e6 then
        logLargeTransaction("transferMoney", src, amount, "to ID " .. tostring(target))
      end
    end)
  end)

  return true
end

local function claimDailyReward_export(...)
  local a, b = stripSelf(...)
  local src, reward

  if b == nil then
    src = resolveSourceId(nil)
    reward = a
  else
    src = resolveSourceId(a)
    reward = b
  end

  reward = tonumber(reward) or 500
  if not src then return false end

  withMoney(src, function(dID, cID, data)
    local now = os.time()
    if (now - tonumber(data.last_daily or 0)) < 86400 then
      TriggerClientEvent("chat:addMessage", src, { args = {"^1SYSTEM", "Daily reward already claimed."} })
      return
    end

    data.cash = (tonumber(data.cash) or 0) + reward
    data.last_daily = now

    UpdateMoney(dID, cID, data, function()
      sendMoneyToClient(src, false)
      if reward >= 1e6 then logLargeTransaction("claimDailyReward", src, reward, "Daily reward") end
    end)
  end)

  return true
end

local function GetPlayerCharacter_export(...)
  local playerId = stripSelf(...)
  local id = resolveSourceId(playerId)
  if not id then return nil end

  local did = getDiscordID(id)
  local cid = getFrameworkActiveCharacter(id, did)
  if cid and cid ~= "" then
    return cid
  end

  if did ~= "" and isDiscordCharacterMode() then
    return getPreferredCharacterId(id, did)
  end

  return nil
end

local function GetPlayerCharacterName_export(...)
  local a, b = stripSelf(...)
  local src, cb

  if type(a) == "function" and b == nil then
    src = resolveSourceId(nil)
    cb = a
  else
    src = resolveSourceId(a)
    cb = b
  end

  if type(cb) ~= "function" then return end
  if not src then return safeCb(cb, "invalid_source", nil) end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if (not cid or cid == "") and isDiscordCharacterMode() then
    return ensureCharacterReady(src, function(ok)
      if ok then return GetPlayerCharacterName_export(src, cb) end
      return safeCb(cb, "no_character", nil)
    end)
  end
  if did == "" or not cid then
    return safeCb(cb, "no_character", nil)
  end

  local ok = pcall(function()
    oxScalar(
      "SELECT name FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
      { did, cid },
      function(name)
        if not name then return safeCb(cb, "not_found", nil) end
        return safeCb(cb, nil, name)
      end
    )
  end)

  if not ok then
    return safeCb(cb, "db_error", nil)
  end
end

local function GetPlayerCharacterNameSync_export(...)
  local src = stripSelf(...)
  src = resolveSourceId(src)
  if not src then return nil, "invalid_source" end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if (not cid or cid == "") and isDiscordCharacterMode() then
    cid = getPreferredCharacterId(src, did)
  end
  if did == "" or not cid then
    return nil, "no_character"
  end

  local p = promise.new()
  local done = false

  oxScalar(
    "SELECT name FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
    { did, cid },
    function(name)
      if done then return end
      done = true
      p:resolve(name)
    end
  )

  SetTimeout(1500, function()
    if done then return end
    done = true
    p:resolve(nil)
  end)

  local name = Citizen.Await(p)
  if not name or tostring(name) == "" then
    return nil, "not_found"
  end

  return tostring(name), nil
end

exports("GetPlayerCharacterNameSync", GetPlayerCharacterNameSync_export)

local function GetPlayerMoney_export(...)
  local a, b = stripSelf(...)
  local src, cb
  if type(a) == "function" and b == nil then
    src = resolveSourceId(nil)
    cb = a
  else
    src = resolveSourceId(a)
    cb = b
  end

  if not src then return safeCb(cb, "invalid_source", nil) end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if (not cid or cid == "") and isDiscordCharacterMode() then
    return ensureCharacterReady(src, function(ok)
      if ok then return GetPlayerMoney_export(src, cb) end
      return safeCb(cb, "no_character", nil)
    end)
  end
  if did == "" or not cid then
    return safeCb(cb, "no_character", nil)
  end

  GetMoney(did, cid, function(data)
    if not data then
      return safeCb(cb, "no_data", { cash=0, bank=0 })
    end
    safeCb(cb, nil, { cash = data.cash or 0, bank = data.bank or 0 })
  end)
end

local function getCachedJobForSource(src)
  src = tonumber(src or 0) or 0
  if src <= 0 then return "" end
  return tostring(lastDeptValue[src] or "")
end

local function publishJobChanged(src, job, previousJob)
  src = tonumber(src or 0) or 0
  if src <= 0 then return end

  TriggerEvent("Az-Framework:jobChanged", src, job or "", previousJob or "")
  TriggerClientEvent("Az-Framework:jobChanged", src, job or "", previousJob or "")
end

local function GetPlayerJob_async(src, cb)
  src = resolveSourceId(src)
  if not src then return safeCb(cb, "invalid_source", "") end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if (not cid or cid == "") and isDiscordCharacterMode() then
    return ensureCharacterReady(src, function(ok)
      if ok then return GetPlayerJob_async(src, cb) end
      return safeCb(cb, "no_character", getCachedJobForSource(src))
    end)
  end
  if did == "" or not cid then
    return safeCb(cb, "no_character", getCachedJobForSource(src))
  end

  local ok = pcall(function()
    oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
      { did, cid },
      function(job)
        job = tostring(job or getCachedJobForSource(src) or "")
        if job ~= "" then lastDeptValue[src] = job:lower() end
        safeCb(cb, nil, job)
      end
    )
  end)

  if not ok then
    safeCb(cb, "db_error", getCachedJobForSource(src))
  end
end

local function getPlayerJob_export(...)
  local packed = { stripSelf(...) }
  local src = resolveSourceId(packed[1])
  if not src then return "" end

  local cached = tostring(getCachedJobForSource(src) or "")
  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)

  if did == "" or not cid or cid == "" then
    return cached
  end

  if not (MySQL and MySQL.scalar and MySQL.scalar.await) then
    return cached
  end

  local ok, job = pcall(function()
    return MySQL.scalar.await(
      "SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
      { did, cid }
    )
  end)

  job = tostring((ok and job) or cached or "")
  if job ~= "" then
    lastDeptValue[src] = job:lower()
  end
  return job
end

local function setPlayerJob_export(...)
  local a, b = stripSelf(...)
  local src = resolveSourceId(a)
  local job = tostring(b or ""):lower()
  if not src then return false end

  local function writeJob(discordId, charId, cb)
    discordId = tostring(discordId or "")
    charId = tostring(charId or "")
    if discordId == "" or charId == "" then
      return safeCb(cb, false)
    end

    local previousJob = getCachedJobForSource(src)

    oxExecute(
      "UPDATE user_characters SET active_department=? WHERE discordid=? AND charid=?",
      { job, discordId, charId },
      function()
        lastDeptValue[src] = job
        TriggerClientEvent("hud:setDepartment", src, job)
        if Player and Player(src) and Player(src).state then
          Player(src).state:set("job", job, true)
          Player(src).state:set("department", job, true)
        end
        publishJobChanged(src, job, previousJob)
        safeCb(cb, true)
      end
    )
  end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if did ~= "" and cid and cid ~= "" then
    local p = promise.new()
    writeJob(did, cid, function(ok)
      p:resolve(ok == true)
    end)
    return Citizen.Await(p) == true
  end

  if not isDiscordCharacterMode() then
    return false
  end

  local p = promise.new()
  ensureCharacterReady(src, function(ok, resolvedCharId)
    if not ok or not resolvedCharId then
      p:resolve(false)
      return
    end
    writeJob(getDiscordID(src), resolvedCharId, function(writeOk)
      p:resolve(writeOk == true)
    end)
  end)

  return Citizen.Await(p) == true
end

local function isHuntingLicenseEnabled_export(...)
  return Config and Config.Licenses and Config.Licenses.UseHuntingLicense == true
end

local function GetPlayerHuntingLicense_async(src, cb)
  src = resolveSourceId(src)
  if not src then return safeCb(cb, "invalid_source", false) end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if (not cid or cid == "") and isDiscordCharacterMode() then
    return ensureCharacterReady(src, function(ok)
      if ok then return GetPlayerHuntingLicense_async(src, cb) end
      return safeCb(cb, "no_character", false)
    end)
  end
  if did == "" or not cid then
    return safeCb(cb, "no_character", false)
  end

  oxScalar(
    "SELECT COALESCE(hunting_license, 0) FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
    { did, cid },
    function(status)
      safeCb(cb, nil, tonumber(status) == 1)
    end
  )
end

local function hasHuntingLicense_export(...)
  local src = stripSelf(...)
  src = resolveSourceId(src)
  if not src then return false end

  local p = promise.new()
  local done = false

  GetPlayerHuntingLicense_async(src, function(_err, status)
    done = true
    p:resolve(status == true)
  end)

  SetTimeout(800, function()
    if done then return end
    done = true
    p:resolve(false)
  end)

  return Citizen.Await(p) == true
end

local function setHuntingLicense_export(...)
  local a, b, c = stripSelf(...)
  local targetSrc = resolveSourceId(a)
  local did, cid, state

  if targetSrc then
    did = getDiscordID(targetSrc)
    cid = activeCharacters[targetSrc]
    state = b
  else
    did = tostring(a or "")
    cid = tostring(b or "")
    state = c
  end

  if did == "" or not cid or tostring(cid) == "" then return false end

  local p = promise.new()
  oxExecute(
    "UPDATE user_characters SET hunting_license=? WHERE discordid=? AND charid=?",
    { state == true and 1 or 0, did, cid },
    function(affected)
      p:resolve((tonumber(affected) or 0) > 0)
    end
  )
  return Citizen.Await(p) == true
end

local DEPT_REQ_MIN_MS = 4000
lastDeptReq = {}

RegisterNetEvent("hud:requestDepartment", function()
  local src = source
  local now = GetGameTimer()
  local last = lastDeptReq[src] or 0
  if (now - last) < DEPT_REQ_MIN_MS then
    if Config.Debug then dprint("hud:requestDepartment throttled for src", src) end
    return
  end
  lastDeptReq[src] = now

  local function doRequest()
    local did = getDiscordID(src)
    local cid = getFrameworkActiveCharacter(src, did)
    if did == "" or not cid then
      TriggerClientEvent("hud:setDepartment", src, "")
      return
    end

    oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
      { did, cid },
      function(job)
        TriggerClientEvent("hud:setDepartment", src, job or "")
      end
    )
  end

  if isDiscordCharacterMode() and (not activeCharacters[src] or activeCharacters[src] == "") then
    return ensureCharacterReady(src, function(_ok)
      doRequest()
    end)
  end

  doRequest()
end)

local DEPT_SET_MIN_MS = 4000
lastDeptSet = {}
lastDeptValue = {}

RegisterNetEvent("az-fw-departments:setActive", function(job)
  local src = source
  local now = GetGameTimer()

  job = tostring(job or ""):lower()

  local last = lastDeptSet[src] or 0
  if (now - last) < DEPT_SET_MIN_MS then
    if Config.Debug then dprint("setActive throttled src", src, "job", job) end
    return
  end

  if lastDeptValue[src] == job then
    if Config.Debug then dprint("setActive ignored (same job) src", src, "job", job) end
    return
  end

  local did = getDiscordID(src)
  local cid = getFrameworkActiveCharacter(src, did)
  if did == "" or not cid then
    if isDiscordCharacterMode() then
      return ensureCharacterReady(src, function(ok, resolvedCharId)
        if not ok then return end
        local resolvedDid = getDiscordID(src)
        if resolvedDid == "" or not resolvedCharId then return end
        local previousJob = getCachedJobForSource(src)
        lastDeptSet[src] = now
        lastDeptValue[src] = job
        oxExecute(
          "UPDATE user_characters SET active_department=? WHERE discordid=? AND charid=?",
          { job, resolvedDid, resolvedCharId },
          function()
            TriggerClientEvent("hud:setDepartment", src, job)
            if Player and Player(src) and Player(src).state then
              Player(src).state:set("job", job, true)
              Player(src).state:set("department", job, true)
            end
            publishJobChanged(src, job, previousJob)
            TriggerClientEvent("ox_lib:notify", src, {
              title = "Departments",
              description = ("On-duty as: %s"):format(job ~= "" and job or "None"),
              type = "success"
            })
          end
        )
      end)
    end
    return
  end

  local previousJob = getCachedJobForSource(src)
  lastDeptSet[src] = now
  lastDeptValue[src] = job

  oxExecute(
    "UPDATE user_characters SET active_department=? WHERE discordid=? AND charid=?",
    { job, did, cid },
    function()

      TriggerClientEvent("hud:setDepartment", src, job)
      if Player and Player(src) and Player(src).state then
        Player(src).state:set("job", job, true)
        Player(src).state:set("department", job, true)
      end
      publishJobChanged(src, job, previousJob)
      TriggerClientEvent("ox_lib:notify", src, {
        title = "Departments",
        description = ("On-duty as: %s"):format(job ~= "" and job or "None"),
        type = "success"
      })
    end
  )
end)

local HUD_CFG = Config.HUD or {}
local HUD_PRESET_FILE = tostring(HUD_CFG.PresetFile or "config/hud_preset.json")
local HUD_STATE_FILE = tostring(HUD_CFG.StateFile or "config/hud_state.json")
local RESOURCE_NAME = GetCurrentResourceName()

local function hudTrimmed(value)
  local s = trim(value)
  return s
end

local function pickRandomHudValue(list, fallback)
  local pool = {}
  for _, v in ipairs(list or {}) do
    local cleaned = hudTrimmed(v)
    if cleaned ~= "" then
      pool[#pool + 1] = cleaned
    end
  end
  if #pool == 0 then
    return tostring(fallback or "None Set")
  end
  return tostring(pool[math.random(1, #pool)])
end

local function loadSavedHudStateFromDisk()
  local raw = LoadResourceFile(RESOURCE_NAME, HUD_STATE_FILE)
  if not raw or raw == "" then return {} end

  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    print(("[Az-Framework] Failed to decode HUD state file %s"):format(HUD_STATE_FILE))
    return {}
  end

  return {
    aop = hudTrimmed(decoded.aop or ""),
    prio = hudTrimmed(decoded.prio or ""),
  }
end

local persistedHudSharedState = loadSavedHudStateFromDisk()

local function saveSharedHudStateToDisk()
  local encoded = json.encode({
    aop = tostring(globalHudState and globalHudState.aop or ""),
    prio = tostring(globalHudState and globalHudState.prio or ""),
  })
  if not encoded then
    print(("[Az-Framework] Failed to encode HUD state for %s"):format(HUD_STATE_FILE))
    return false
  end
  return SaveResourceFile(RESOURCE_NAME, HUD_STATE_FILE, encoded, -1)
end

local function resolveSharedHudDefault(kind)
  local key = lower(kind)
  local saved = hudTrimmed(persistedHudSharedState[key] or "")
  local defaultValue = tostring(key == "aop" and (HUD_CFG.DefaultAOP or "None Set") or (HUD_CFG.DefaultPrio or "None Set"))
  local strategy = lower(key == "aop" and (HUD_CFG.DefaultAOPStrategy or "default") or (HUD_CFG.DefaultPrioStrategy or "default"))
  local choices = key == "aop" and (HUD_CFG.AOPChoices or {}) or (HUD_CFG.PrioChoices or {})

  local wantsLast = strategy:find("last", 1, true) ~= nil
  local wantsRandom = strategy:find("random", 1, true) ~= nil

  if strategy == "last" and saved ~= "" then
    return saved
  end

  if strategy == "random" then
    return pickRandomHudValue(choices, defaultValue)
  end

  if strategy == "random_or_last" then
    local randomValue = pickRandomHudValue(choices, defaultValue)
    if randomValue ~= "" then return randomValue end
    if saved ~= "" then return saved end
  elseif strategy == "last_or_random" then
    if saved ~= "" then return saved end
    return pickRandomHudValue(choices, defaultValue)
  elseif wantsLast and saved ~= "" then
    return saved
  elseif wantsRandom then
    return pickRandomHudValue(choices, defaultValue)
  end

  if saved ~= "" and wantsLast then
    return saved
  end

  return defaultValue
end

local function clampHudOpacity(value)
  local n = tonumber(value) or 100
  if n < 25 then n = 25 end
  if n > 100 then n = 100 end
  return math.floor(n + 0.5)
end

local function sanitizeHudCardState(card)
  if type(card) ~= "table" then return nil end
  local clean = {
    display = (card.display == "none") and "none" or "",
    position = (card.position == "fixed" or card.position == "absolute") and card.position or "",
    width = card.width and tostring(card.width) or "",
    height = card.height and tostring(card.height) or "",
  }
  if card.left ~= nil and tostring(card.left) ~= "" then clean.left = math.floor((tonumber(card.left) or 0) + 0.5) end
  if card.top ~= nil and tostring(card.top) ~= "" then clean.top = math.floor((tonumber(card.top) or 0) + 0.5) end
  return clean
end

local function sanitizeHudSettingsPayload(payload)
  if type(payload) ~= "table" then return {} end
  local clean = { toggles = {}, cards = {} }

  if payload.hudRight ~= nil and tostring(payload.hudRight) ~= "" then
    clean.hudRight = math.max(0, math.floor((tonumber(payload.hudRight) or 0) + 0.5))
  end
  if payload.hudTop ~= nil and tostring(payload.hudTop) ~= "" then
    clean.hudTop = math.max(0, math.floor((tonumber(payload.hudTop) or 0) + 0.5))
  end

  if type(payload.toggles) == "table" then
    for k, v in pairs(payload.toggles) do
      clean.toggles[tostring(k)] = v == true
    end
  end

  if type(payload.cards) == "table" then
    for id, card in pairs(payload.cards) do
      local cleaned = sanitizeHudCardState(card)
      if cleaned then clean.cards[tostring(id)] = cleaned end
    end
  end

  if type(payload.uiSettings) == "table" then
    clean.uiSettings = {
      hudEnabled = payload.uiSettings.hudEnabled ~= false,
      soundEnabled = payload.uiSettings.soundEnabled ~= false,
      opacity = clampHudOpacity(payload.uiSettings.opacity),
    }
  end

  return clean
end

local function loadHudPresetFromDisk()
  local raw = LoadResourceFile(RESOURCE_NAME, HUD_PRESET_FILE)
  if not raw or raw == "" then return {} end

  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    print(("[Az-Framework] Failed to decode HUD preset file %s"):format(HUD_PRESET_FILE))
    return {}
  end

  return sanitizeHudSettingsPayload(decoded)
end

local globalHudPreset = loadHudPresetFromDisk()

local function cloneHudPreset()
  return sanitizeHudSettingsPayload(globalHudPreset)
end

local function saveHudPresetToDisk()
  local encoded = json.encode(globalHudPreset or {})
  if not encoded then
    print(("[Az-Framework] Failed to encode HUD preset for %s"):format(HUD_PRESET_FILE))
    return false
  end
  return SaveResourceFile(RESOURCE_NAME, HUD_PRESET_FILE, encoded, -1)
end

local function broadcastHudPreset(target)
  local payload = cloneHudPreset()
  if target ~= nil then
    TriggerClientEvent("az-fw-hud:syncPreset", target, payload)
  else
    TriggerClientEvent("az-fw-hud:syncPreset", -1, payload)
  end
end

local globalHudState = {
  features = {
    compass = not (HUD_CFG.Features and HUD_CFG.Features.compass == false),
    postal  = not (HUD_CFG.Features and HUD_CFG.Features.postal == false),
    aop     = not (HUD_CFG.Features and HUD_CFG.Features.aop == false),
    prio    = not (HUD_CFG.Features and HUD_CFG.Features.prio == false),
  },
  aop = tostring(resolveSharedHudDefault("aop") or "None Set"),
  prio = tostring(resolveSharedHudDefault("prio") or "None Set"),
}

local function cloneHudState()
  return {
    features = {
      compass = globalHudState.features.compass == true,
      postal = globalHudState.features.postal == true,
      aop = globalHudState.features.aop == true,
      prio = globalHudState.features.prio == true,
    },
    aop = tostring(globalHudState.aop or HUD_CFG.DefaultAOP or "None Set"),
    prio = tostring(globalHudState.prio or HUD_CFG.DefaultPrio or "None Set"),
  }
end

local function broadcastHudState(target)
  local payload = cloneHudState()
  if target ~= nil then
    TriggerClientEvent("az-fw-hud:syncState", target, payload)
  else
    TriggerClientEvent("az-fw-hud:syncState", -1, payload)
  end
end

local function normalizeHudFeatureName(name)
  local v = tostring(name or ""):lower()
  if v == "compas" then v = "compass" end
  if v == "priority" then v = "prio" end
  return v
end

local function lowerSet(tbl)
  local out = {}
  for _, v in ipairs(tbl or {}) do
    out[#out + 1] = tostring(v):lower()
  end
  return out
end

local function tableContainsLower(tbl, value)
  value = tostring(value or ""):lower()
  for _, v in ipairs(tbl or {}) do
    if tostring(v):lower() == value then
      return true
    end
  end
  return false
end

local function canUseSharedHudCommand(src, commandName)
  if tonumber(src) == 0 then return true, "console" end
  if isAdmin_export(src) then return true, "admin" end

  local job = tostring(getPlayerJob_export(src) or ""):lower()
  local configured = getConfiguredDepartment(job)
  if configured then
    if commandName == "aop" and configured.canUseAOP ~= nil then
      return configured.canUseAOP == true, job
    end
    if commandName == "prio" and configured.canUsePrio ~= nil then
      return configured.canUsePrio == true, job
    end
  end

  local cmdJobs = (((Config.HUD or {}).CommandJobs or {})[commandName]) or {}
  if type(cmdJobs) ~= "table" or #cmdJobs == 0 then
    return false, tostring(job or "")
  end

  if job ~= "" and tableContainsLower(cmdJobs, job) then
    return true, job
  end

  return false, job
end

RegisterNetEvent("az-fw-hud:requestState", function()
  broadcastHudState(source)
end)

RegisterNetEvent("az-fw-hud:requestPreset", function()
  broadcastHudPreset(source)
end)

RegisterNetEvent("az-fw-hud:savePreset", function(payload)
  local src = source
  if tonumber(src or 0) ~= 0 and not isAdmin_export(src) then
    TriggerClientEvent("chat:addMessage", src, { args = { "^1SYSTEM", "Admin permission required." } })
    return
  end

  globalHudPreset = sanitizeHudSettingsPayload(payload)
  saveHudPresetToDisk()
  broadcastHudPreset()

  if tonumber(src or 0) ~= 0 then
    TriggerClientEvent("chat:addMessage", src, { args = { "^2SYSTEM", "HUD preset saved for the server." } })
  else
    print("[Az-Framework] HUD preset saved for the server.")
  end
end)

RegisterCommand("addmoney", function(src, args)
  if src == 0 then return end
  isAdmin_export(src, function(ok)
    logAdminCommand("addmoney", src, args, ok)
    if not ok then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Permission denied."} }) end
    local amt = tonumber(args[1])
    if not amt then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /addmoney [amount]"} }) end
    addMoney_export(src, amt)
  end)
end, false)

RegisterCommand("deductMoney", function(src, args)
  if src == 0 then return end
  isAdmin_export(src, function(ok)
    logAdminCommand("deductMoney", src, args, ok)
    if not ok then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Permission denied."} }) end
    local amt = tonumber(args[1])
    if not amt then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /deductMoney [amount]"} }) end
    deductMoney_export(src, amt)
  end)
end, false)

RegisterCommand("deposit", function(src, args)
  local amount = tonumber(args[1])
  if not amount then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /deposit [amount]"} }) end
  depositMoney_export(src, amount)
end, false)

RegisterCommand("withdraw", function(src, args)
  local amount = tonumber(args[1])
  if not amount then return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /withdraw [amount]"} }) end
  withdrawMoney_export(src, amount)
end, false)

RegisterCommand("transfer", function(src, args)
  local targetId = tonumber(args[1])
  local amount = tonumber(args[2])
  if not targetId or not amount then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /transfer [id] [amount]"} })
  end
  transferMoney_export(src, targetId, amount)
end, false)

RegisterCommand("dailyreward", function(src, args)
  if src == 0 then return end
  local reward = tonumber(args[1]) or 500
  claimDailyReward_export(src, reward)
end, false)

RegisterCommand("movehudpreset", function(src)
  if src == 0 then
    print("[Az-Framework] /movehudpreset can only be used in-game.")
    return
  end

  if not isAdmin_export(src) then
    TriggerClientEvent("chat:addMessage", src, { args = { "^1SYSTEM", "Admin permission required." } })
    return
  end

  broadcastHudPreset(src)
  TriggerClientEvent("az-fw-hud:togglePresetMove", src)
  TriggerClientEvent("chat:addMessage", src, { args = { "^2SYSTEM", "Preset editor opened. Save to update the server default HUD layout." } })
end, false)

RegisterCommand("hudfeature", function(src, args)
  local feature = normalizeHudFeatureName(args[1])
  local rawState = tostring(args[2] or ""):lower()
  local enabled = nil
  if rawState == "on" or rawState == "true" or rawState == "1" then enabled = true end
  if rawState == "off" or rawState == "false" or rawState == "0" then enabled = false end

  if not isAdmin_export(src) then
    if src ~= 0 then
      TriggerClientEvent("chat:addMessage", src, { args = { "^1SYSTEM", "Admin permission required." } })
    end
    return
  end

  if globalHudState.features[feature] == nil or enabled == nil then
    if src ~= 0 then
      TriggerClientEvent("chat:addMessage", src, { args = { "^3SYSTEM", "Usage: /hudfeature [compass|postal|aop|prio] [on|off]" } })
    else
      print("Usage: /hudfeature [compass|postal|aop|prio] [on|off]")
    end
    return
  end

  globalHudState.features[feature] = enabled
  TriggerClientEvent("az-fw-hud:featureToggled", -1, feature, enabled)
  broadcastHudState()

  local stateWord = enabled and "enabled" or "disabled"
  if src ~= 0 then
    TriggerClientEvent("chat:addMessage", src, { args = { "^2SYSTEM", ("%s HUD %s."):format(feature, stateWord) } })
  else
    print(("[Az-Framework] %s HUD %s."):format(feature, stateWord))
  end
end, false)

RegisterCommand("aop", function(src, args)
  local ok, currentJob = canUseSharedHudCommand(src, "aop")
  if not ok then
    if src ~= 0 then
      TriggerClientEvent("chat:addMessage", src, { args = { "^1SYSTEM", ("You do not have permission to use /aop. Current job: %s"):format(currentJob ~= "" and currentJob or "none") } })
    end
    return
  end

  local value = trim(table.concat(args or {}, " "))
  if value == "" then
    if src ~= 0 then
      TriggerClientEvent("chat:addMessage", src, { args = { "^3SYSTEM", "Usage: /aop [text] or /aop clear" } })
    else
      print("Usage: /aop [text] or /aop clear")
    end
    return
  end

  if value:lower() == "clear" then
    value = tostring(resolveSharedHudDefault("aop") or ((Config.HUD and Config.HUD.DefaultAOP) or "None Set"))
  end

  globalHudState.aop = value
  persistedHudSharedState.aop = value
  saveSharedHudStateToDisk()
  TriggerClientEvent("az-fw-hud:setAOP", -1, value)
  broadcastHudState()

  if src ~= 0 then
    TriggerClientEvent("chat:addMessage", src, { args = { "^2SYSTEM", ("AOP updated to: %s"):format(value) } })
  else
    print(("[Az-Framework] AOP updated to: %s"):format(value))
  end
end, false)

RegisterCommand("prio", function(src, args)
  local ok, currentJob = canUseSharedHudCommand(src, "prio")
  if not ok then
    if src ~= 0 then
      TriggerClientEvent("chat:addMessage", src, { args = { "^1SYSTEM", ("You do not have permission to use /prio. Current job: %s"):format(currentJob ~= "" and currentJob or "none") } })
    end
    return
  end

  local value = trim(table.concat(args or {}, " "))
  if value == "" then
    if src ~= 0 then
      TriggerClientEvent("chat:addMessage", src, { args = { "^3SYSTEM", "Usage: /prio [text] or /prio clear" } })
    else
      print("Usage: /prio [text] or /prio clear")
    end
    return
  end

  if value:lower() == "clear" then
    value = tostring(resolveSharedHudDefault("prio") or ((Config.HUD and Config.HUD.DefaultPrio) or "None Set"))
  end

  globalHudState.prio = value
  persistedHudSharedState.prio = value
  saveSharedHudStateToDisk()
  TriggerClientEvent("az-fw-hud:setPRIO", -1, value)
  broadcastHudState()

  if src ~= 0 then
    TriggerClientEvent("chat:addMessage", src, { args = { "^2SYSTEM", ("Prio updated to: %s"):format(value) } })
  else
    print(("[Az-Framework] Prio updated to: %s"):format(value))
  end
end, false)

RegisterCommand("listchars", function(src)
  if src == 0 then return end
  local did = getDiscordID(src)
  if did == "" then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","No Discord ID found. Are you Discord-linked?"} })
  end

  oxQuery("SELECT charid, name FROM user_characters WHERE discordid=?", { did }, function(rows)
    if not rows or #rows == 0 then
      return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","You have no characters. Use /registerchar to create one."} })
    end
    local list = {}
    for _, r in ipairs(rows) do list[#list+1] = (tostring(r.charid) .. ":" .. tostring(r.name)) end
    TriggerClientEvent("chat:addMessage", src, { args={"^2SYSTEM","Your characters → " .. table.concat(list, ", ")} })
  end)
end, false)

RegisterCommand("selectchar", function(src, args)
  if src == 0 then return end
  local chosen = args[1]
  if not chosen then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Usage: /selectchar <charid>"} })
  end

  local did = getDiscordID(src)
  if did == "" then
    return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","No Discord ID found. Are you Discord-linked?"} })
  end

  oxQuery("SELECT 1 FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, chosen }, function(rows)
    if not rows or #rows == 0 then
      return TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Character ID not found. Use /listchars to see yours."} })
    end

    setFrameworkActiveCharacter(src, did, chosen, "/selectchar")

    sendMoneyToClient(src, true)

    oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, chosen }, function(active_dept)
      lastDeptValue[src] = tostring(active_dept or ""):lower()
      TriggerClientEvent("hud:setDepartment", src, active_dept or "")
    end)

    TriggerClientEvent("chat:addMessage", src, { args={"^2SYSTEM","Switched to character " .. tostring(chosen)} })
  end)
end, false)

RegisterNetEvent("az-fw-money:registerCharacter", function(firstName, lastName)
  local src = source
  local did = getDiscordID(src)
  if did == "" then
    TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Could not register character: no Discord ID found."} })
    return
  end

  local charID = tostring(os.time()) .. tostring(math.random(1000, 9999))
  local fullName = trim(firstName) .. " " .. trim(lastName)

  oxInsert("INSERT INTO user_characters (discordid,charid,name,active_department,hunting_license) VALUES (?,?,?,?,?)",
    { did, charID, trim(fullName), "", (Config.Licenses and Config.Licenses.DefaultHuntingLicense == true) and 1 or 0 },
    function(ok)
      if not ok then
        TriggerClientEvent("chat:addMessage", src, { args={"^1SYSTEM","Failed to register character. Check server logs."} })
        return
      end

      oxInsert(("INSERT INTO `%s` (discordid,charid,firstname,lastname,cash,bank,last_daily,card_status) VALUES (?,?,?,?,?,?,?,?)"):format(T.money),
        { did, charID, trim(firstName), trim(lastName), 0, 0, 0, "active" },
        function()
          setFrameworkActiveCharacter(src, did, charID, "register_character", "")

          TriggerClientEvent("az-fw-money:characterRegistered", src, charID)
          sendMoneyToClient(src, true)
          TriggerClientEvent("hud:setDepartment", src, "")

          TriggerClientEvent("chat:addMessage", src, { args={"^2SYSTEM", ("Character '%s' registered (ID %s)."):format(trim(fullName), charID)} })
        end
      )
    end
  )
end)

RegisterNetEvent("az-fw-money:requestMoney", function()

  sendMoneyToClient(source, false)
end)

local function handleCoreCharacterSelected(src, charID, clientEventName)
  src = resolveSourceId(src)
  if not src then return end

  charID = tostring(charID or "")
  if charID == "" then return end

  local did = getDiscordID(src)
  if did == "" then return end

  oxQuery("SELECT 1 FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, charID }, function(rows)
    if rows and #rows > 0 then
      setFrameworkActiveCharacter(src, did, charID, "az-fw-money:selectCharacter")

      sendMoneyToClient(src, true)

      oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, charID }, function(active_dept)
        lastDeptValue[src] = tostring(active_dept or ""):lower()
        TriggerClientEvent("hud:setDepartment", src, active_dept or "")
      end)

      TriggerClientEvent(clientEventName or "az-fw-money:characterSelected", src, charID)
      TriggerEvent("Az-Framework:characterSelected", src, charID)
      TriggerEvent("Az-Framework:Bridge:characterSelected", src, charID)
    end
  end)
end

RegisterNetEvent("az-fw-money:selectCharacter", function(charID)
  handleCoreCharacterSelected(source, charID, "az-fw-money:characterSelected")
end)

RegisterNetEvent("azfw:set_active_character", function(charID)

  handleCoreCharacterSelected(source, charID, "az-fw-money:characterSelected")
end)

RegisterNetEvent("az-fw-money:RequestPlayerCharacter", function()
  local src = source
  if isDiscordCharacterMode() and (not activeCharacters[src] or activeCharacters[src] == "") then
    return ensureCharacterReady(src, function(_ok, charId)
      TriggerClientEvent("az-fw-money:ReceivePlayerCharacter", src, charId or activeCharacters[src] or nil)
    end)
  end
  TriggerClientEvent("az-fw-money:ReceivePlayerCharacter", src, activeCharacters[src] or nil)
end)

local function warmupPlayerCharacter(src)
  src = tonumber(src or 0) or 0
  if src <= 0 or not GetPlayerName(src) then return end
  if not isDiscordCharacterMode() then return end
  ensureCharacterReady(src, function(ok, charId)
    if not ok then return end
    sendMoneyToClient(src, true)
    local did = getDiscordID(src)
    if did ~= "" and charId then
      oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, charId }, function(active_dept)
        lastDeptValue[src] = tostring(active_dept or ""):lower()
        TriggerClientEvent("hud:setDepartment", src, active_dept or "")
      end)
    end
    broadcastHudState(src)
  end)
end

AddEventHandler("playerJoining", function()
  local src = source
  SetTimeout(1500, function()
    warmupPlayerCharacter(src)
  end)
end)

AddEventHandler("onResourceStart", function(resName)
  if resName ~= RESOURCE_NAME then return end
  SetTimeout(1000, function()
    for _, s in ipairs(GetPlayers()) do
      warmupPlayerCharacter(tonumber(s))
    end
  end)
end)

AddEventHandler("playerDropped", function()
  local src = source
  local did = getDiscordID(src)

  clearFrameworkActiveCharacter(src)
  lastMoneyPush[src] = nil
  lastDeptReq[src] = nil
  lastDeptSet[src] = nil
  lastDeptValue[src] = nil
end)

CreateThread(function()
  if not moduleEnabled("Paychecks", true) or PAYCHECK_CFG.Enabled == false then
    print("[Az-Framework] Paycheck thread disabled by config.")
    return
  end

  local interval = (tonumber((PAYCHECK_CFG or {}).IntervalMinutes) or tonumber(Config.PaycheckIntervalMinutes) or 60) * 60 * 1000
  print(("[Az-Framework] Paycheck thread started. Interval=%s minutes."):format(tostring((PAYCHECK_CFG or {}).IntervalMinutes or Config.PaycheckIntervalMinutes or 60)))

  while true do
    Wait(interval)

    for src, charID in pairs(activeCharacters) do
      local discordID = getDiscordID(src)
      if discordID == "" then goto continue end

      oxScalar("SELECT active_department FROM user_characters WHERE discordid=? AND charid=? LIMIT 1",
        { discordID, charID },
        function(active_department)
          if not active_department or active_department == "" then return end

          local configuredAmount = nil
          if PAYCHECK_CFG.UseConfiguredDepartmentsFirst ~= false then
            configuredAmount = getConfiguredDepartmentPaycheck(active_department)
          end

          if tonumber(configuredAmount) and tonumber(configuredAmount) > 0 then
            local amt = tonumber(configuredAmount) or 0
            addMoney_export(src, amt)
            TriggerClientEvent("chat:addMessage", src, { args={"^2PAYCHECK","Paycheck: $" .. tostring(amt)} })
            return
          end

          if PAYCHECK_CFG.UseDatabaseFallback == false then
            return
          end

          getDiscordRoleList(src, function(err, roles)
            if err or type(roles) ~= "table" then return end

            local lookupIds = { discordID }
            for _, rid in ipairs(roles) do lookupIds[#lookupIds+1] = rid end

            local marks = {}
            for i=1,#lookupIds do marks[i] = "?" end

            local sql = (("SELECT paycheck FROM `%s` WHERE department=? AND discordid IN (%s) LIMIT 1")
              :format(T.dept, table.concat(marks, ",")))

            local params = { active_department }
            for _, id in ipairs(lookupIds) do params[#params+1] = id end

            oxScalar(sql, params, function(paycheck)
              local amt = tonumber(paycheck) or 0
              if amt > 0 then
                addMoney_export(src, amt)
                TriggerClientEvent("chat:addMessage", src, { args={"^2PAYCHECK","Paycheck: $" .. tostring(amt)} })
              end
            end)
          end)
        end
      )

      ::continue::
    end
  end
end)

lib = lib or {}
if lib.callback and lib.callback.register then
  lib.callback.register("az-fw-money:fetchCharacters", function(source)
    local discordId = getDiscordID(source)
    if discordId == "" then return {} end

    local p = promise.new()
    MySQL.Async.fetchAll("SELECT * FROM user_characters WHERE discordid = ?", { discordId }, function(result)
      p:resolve(result or {})
    end)
    return Citizen.Await(p)
  end)

  lib.callback.register("az-fw-money:GetPlayerCharacterForSource", function(source)
    return activeCharacters[source] or nil
  end)

  lib.callback.register("az-fw-money:GetPlayerCharacterByDiscord", function(_, discordId)
    discordId = tostring(discordId or "")
    if discordId == "" then return nil end
    if activeCharByDiscord[discordId] then return activeCharByDiscord[discordId] end

    local p = promise.new()
    MySQL.Async.fetchAll("SELECT charid FROM user_characters WHERE discordid = ? LIMIT 2", { discordId }, function(rows)

      if rows and #rows == 1 and rows[1] and rows[1].charid then
        p:resolve(rows[1].charid)
      else
        p:resolve(nil)
      end
    end)
    return Citizen.Await(p)
  end)
end

local function GetActiveCharacter_export(...)
  local src = stripSelf(...)
  src = resolveSourceId(src)
  if not src then return nil end
  return getFrameworkActiveCharacter(src, getDiscordID(src))
end

local function SetActiveCharacter_export(...)
  local a, b = stripSelf(...)
  local src = resolveSourceId(a)
  local charId = b

  if not src and tonumber(b) then
    src = resolveSourceId(b)
    charId = a
  end

  if not src then return false, "invalid_source" end
  charId = tostring(charId or "")
  if charId == "" then return false, "missing_charid" end

  local did = getDiscordID(src)
  if did == "" then return false, "no_discord" end

  if MySQL and MySQL.scalar and type(MySQL.scalar.await) == "function" then
    local ok, exists = pcall(function()
      return MySQL.scalar.await("SELECT 1 FROM user_characters WHERE discordid=? AND charid=? LIMIT 1", { did, charId })
    end)
    if ok and not exists then return false, "not_owner" end
  end

  setFrameworkActiveCharacter(src, did, charId, "SetActiveCharacter export")
  TriggerEvent("Az-Framework:characterSelected", src, charId)
  TriggerEvent("Az-Framework:Bridge:characterSelected", src, charId)
  return true, charId
end

local function ClearActiveCharacter_export(...)
  local src = stripSelf(...)
  src = resolveSourceId(src)
  if not src then return false end
  clearFrameworkActiveCharacter(src)
  return true
end

_G.AzServerExports = {
  addMoney = addMoney_export,
  deductMoney = deductMoney_export,
  depositMoney = depositMoney_export,
  withdrawMoney = withdrawMoney_export,
  transferMoney = transferMoney_export,
  claimDailyReward = claimDailyReward_export,
  GetMoney = GetMoney,
  UpdateMoney = UpdateMoney,
  sendMoneyToClient = function(...) local src = stripSelf(...) return sendMoneyToClient(src, true) end,
  getDiscordID = function(...) local src = stripSelf(...) return getDiscordID(resolveSourceId(src) or src) end,
  isAdmin = isAdmin_export,
  GetPlayerCharacter = GetPlayerCharacter_export,
  GetActiveCharacter = GetActiveCharacter_export,
  getActiveCharacter = GetActiveCharacter_export,
  GetCharacter = GetActiveCharacter_export,
  getCharacter = GetActiveCharacter_export,
  SetActiveCharacter = SetActiveCharacter_export,
  setActiveCharacter = SetActiveCharacter_export,
  ClearActiveCharacter = ClearActiveCharacter_export,
  clearActiveCharacter = ClearActiveCharacter_export,
  GetPlayerCharacterName = GetPlayerCharacterName_export,
  GetPlayerCharacterNameSync = GetPlayerCharacterNameSync_export,
  GetPlayerMoney = GetPlayerMoney_export,
  logAdminCommand = function(...) local a,b,c,d = stripSelf(...) return logAdminCommand(a,b,c,d) end,
  getPlayerJob = getPlayerJob_export,
  setPlayerJob = setPlayerJob_export,
  hasHuntingLicense = hasHuntingLicense_export,
  setHuntingLicense = setHuntingLicense_export,
  isHuntingLicenseEnabled = isHuntingLicenseEnabled_export,
  AddMoney = addMoney_export,
  DeductMoney = deductMoney_export,
  DepositMoney = depositMoney_export,
  WithdrawMoney = withdrawMoney_export,
  TransferMoney = transferMoney_export,
  ClaimDailyReward = claimDailyReward_export,
  GetDiscordID = function(...) local src = stripSelf(...) return getDiscordID(resolveSourceId(src) or src) end,
  SetPlayerJob = setPlayerJob_export,
  HasHuntingLicense = hasHuntingLicense_export,
  SetHuntingLicense = setHuntingLicense_export,
  IsHuntingLicenseEnabled = isHuntingLicenseEnabled_export,
  getConfiguredDepartments = function(...) return getConfiguredDepartmentsExport() end,
  saveConfiguredDepartments = function(...) local list = stripSelf(...) return setConfiguredDepartmentsExport(list) end,
  upsertConfiguredDepartment = function(...) local entry = stripSelf(...) return upsertConfiguredDepartmentExport(entry) end,
  removeConfiguredDepartment = function(...) local id = stripSelf(...) return removeConfiguredDepartmentExport(id) end,
}
