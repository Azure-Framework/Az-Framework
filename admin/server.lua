local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
Config.Debug            = Config.Debug == true
Config.AcePermission    = Config.AcePermission or "adminmenu.use"
Config.ReportsFile      = Config.ReportsFile or "reports.json"
Config.DepartmentsTable = Config.DepartmentsTable or "econ_departments"
Config.ChunkMaxSize     = tonumber(Config.ChunkMaxSize) or 8000
Config.ChunkMaxParts    = tonumber(Config.ChunkMaxParts) or 600

local function dprint(...)
  if not Config.Debug then return end
  local args = { ... }
  for i = 1, #args do args[i] = tostring(args[i]) end
  print(("^3[%s]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local DISCORD_BOT_TOKEN = GetConvar("DISCORD_BOT_TOKEN", "") or ""
local DISCORD_API_BASE  = "https://discord.com/api/v10"
local AVATAR_TTL_SEC    = 60 * 30

local function trim(s)
  s = tostring(s or "")
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function nowIso()
  return os.date("!%Y-%m-%d %H:%M:%S")
end

local function resolveSourceId(arg)
  local s = tonumber(arg)
  if s and s > 0 then return s end
  local g = tonumber(_G.source)
  if g and g > 0 then return g end
  return nil
end

local function getName(src)
  local n = GetPlayerName(src)
  if n and n ~= "" then return n end
  return ("Player %s"):format(tostring(src))
end

local function sendToPlayer(targetSrc, event, ...)
  targetSrc = tonumber(targetSrc or 0) or 0
  if targetSrc <= 0 then return false end
  if GetPlayerName(targetSrc) == nil then return false end
  TriggerClientEvent(event, targetSrc, ...)
  return true
end

local function safeCall(fn, ...)
  local ok, res = pcall(fn, ...)
  if ok then return true, res end
  return false, tostring(res)
end

local function getFW()
  if GetResourceState("Az-Framework") == "started" then
    return exports["Az-Framework"]
  end
  return nil
end

local function azCall(name, ...)
  if type(Az) == "table" and type(Az[name]) == "function" then
    local ok, res = pcall(Az[name], ...)
    if ok then return true, res end
  end

  local fw = getFW()
  if not fw then return false, "Az-Framework not started" end

  local fn = fw[name]
  if type(fn) ~= "function" then
    return false, ("Az-Framework export missing: %s"):format(name)
  end

  local ok, res = pcall(fn, ...)
  if ok then return true, res end

  ok, res = pcall(fn, fw, ...)
  return ok, res
end

local function isAdmin(src)
  src = resolveSourceId(src)
  if not src then return false end
  if src == 0 then return true end

  local ok, res = azCall("isAdmin", src)
  if ok and type(res) == "boolean" then
    dprint(("[isAdmin] AzFW wrapper -> %s (src=%s)"):format(tostring(res), tostring(src)))
    return res
  end

  if not ok then
    dprint(("[isAdmin] AzFW error: %s"):format(tostring(res)))
  else
    dprint(("[isAdmin] AzFW returned non-bool: %s"):format(tostring(res)))
  end

  local perm = Config.AcePermission or "adminmenu.use"
  local ace = IsPlayerAceAllowed(src, perm)
  if ace then
    dprint(("[isAdmin] ACE allowed perm=%s src=%s"):format(perm, tostring(src)))
    return true
  end

  dprint(("[isAdmin] denied src=%s"):format(tostring(src)))
  return false
end

local function getDiscordID(src)
  src = resolveSourceId(src)
  if not src then return nil end

  local ok, id = azCall("getDiscordID", src)
  if ok and id and tostring(id) ~= "" then return tostring(id) end

  ok, id = azCall("GetDiscordID", src)
  if ok and id and tostring(id) ~= "" then return tostring(id) end

  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if type(id) == "string" and id:sub(1, 8) == "discord:" then
      return id:sub(9)
    end
  end

  return nil
end

local AvatarCache = {}

local function bigModDecimalStr(numStr, mod)
  local r = 0
  for i = 1, #numStr do
    local c = numStr:byte(i)
    if c >= 48 and c <= 57 then
      r = (r * 10 + (c - 48)) % mod
    end
  end
  return r
end

local function defaultDiscordAvatarIndex(discordId)
  local s = tostring(discordId or ""):match("%d+")
  if not s then return 0 end
  local SHIFT = 4194304
  local MOD   = 6 * SHIFT
  local m = bigModDecimalStr(s, MOD)
  return math.floor(m / SHIFT)
end

local function buildDiscordAvatarUrl(discordId, avatarHash)
  local id = tostring(discordId or ""):match("%d+")
  if not id then
    return "https://cdn.discordapp.com/embed/avatars/0.png"
  end

  if avatarHash and avatarHash ~= "" then
    local ext = (avatarHash:sub(1, 2) == "a_") and "gif" or "png"
    return ("https://cdn.discordapp.com/avatars/%s/%s.%s?size=128"):format(id, avatarHash, ext)
  end

  local idx = defaultDiscordAvatarIndex(id)
  return ("https://cdn.discordapp.com/embed/avatars/%d.png"):format(idx)
end

local function httpRequestAwait(url, method, body, headers)
  local p = promise.new()
  PerformHttpRequest(url, function(status, respBody, respHeaders)
    p:resolve({ status = status, body = respBody, headers = respHeaders })
  end, method or "GET", body or "", headers or {})
  return Citizen.Await(p)
end

local function getDiscordAvatarUrl(discordId)
  local id = tostring(discordId or ""):match("%d+")
  if not id then
    return buildDiscordAvatarUrl("", "")
  end

  local now = os.time()
  local cached = AvatarCache[id]
  if cached and cached.exp and cached.exp > now and cached.url then
    return cached.url
  end

  if DISCORD_BOT_TOKEN == "" then
    local url = buildDiscordAvatarUrl(id, "")
    AvatarCache[id] = { url = url, exp = now + AVATAR_TTL_SEC }
    return url
  end

  local res = httpRequestAwait(("%s/users/%s"):format(DISCORD_API_BASE, id), "GET", "", {
    ["Authorization"] = ("Bot %s"):format(DISCORD_BOT_TOKEN),
    ["Content-Type"]  = "application/json",
    ["User-Agent"]    = "Az-Admin (FiveM)"
  })

  if res and res.status ~= 200 then
    dprint(("[DiscordAvatar] /users/%s -> status=%s"):format(id, tostring(res.status)))
  end

  local url = buildDiscordAvatarUrl(id, "")
  if res and res.status == 200 and res.body and res.body ~= "" then
    local ok, data = pcall(json.decode, res.body)
    if ok and type(data) == "table" then
      url = buildDiscordAvatarUrl(id, data.avatar)
    end
  end

  AvatarCache[id] = { url = url, exp = now + AVATAR_TTL_SEC }
  return url
end

local function enrichReportsWithAvatarUrls(list)
  if type(list) ~= "table" then return list end

  local needed = {}

  for _, r in ipairs(list) do
    if r.reporterDiscord and r.reporterDiscord ~= "" then needed[tostring(r.reporterDiscord)] = true end
    if r.targetDiscord and r.targetDiscord ~= "" then needed[tostring(r.targetDiscord)] = true end

    if type(r.chat) == "table" then
      for _, m in ipairs(r.chat) do
        local did = m.byDiscordId or m.byDiscordID or m.discord or ""
        if did ~= "" then needed[tostring(did)] = true end
      end
    end
  end

  local urlById = {}
  for did, _ in pairs(needed) do
    urlById[did] = getDiscordAvatarUrl(did)
  end

  for _, r in ipairs(list) do
    if r.reporterDiscord and r.reporterDiscord ~= "" then
      r.reporterAvatarUrl = urlById[tostring(r.reporterDiscord)]
    end
    if r.targetDiscord and r.targetDiscord ~= "" then
      r.targetAvatarUrl = urlById[tostring(r.targetDiscord)]
    end

    if type(r.chat) == "table" then
      for _, m in ipairs(r.chat) do
        local did = m.byDiscordId or m.byDiscordID or m.discord or ""
        if did ~= "" then
          m.avatarUrl = urlById[tostring(did)]
        end
      end
    end
  end

  return list
end

local function enrichOneReport(report)
  local tmp = enrichReportsWithAvatarUrls({ report })
  return tmp and tmp[1] or report
end

local function enrichReportList(list)
  return enrichReportsWithAvatarUrls(list or {}) or (list or {})
end

local function pushReportsTo(src, list)
  TriggerClientEvent("adminmenu:nui:loadReports", src, enrichReportList(list))
end

local function pushUpsertToAll(report)
  report = enrichOneReport(report)
  TriggerClientEvent("adminmenu:nui:upsertReport", -1, report)
  return report
end

local reports = {}

local function normalizeReports(decoded)
  if type(decoded) ~= "table" then return {} end
  if decoded[1] ~= nil then return decoded end

  local out = {}
  for _, r in pairs(decoded) do
    if type(r) == "table" then out[#out + 1] = r end
  end
  table.sort(out, function(a, b) return (tonumber(a.id) or 0) > (tonumber(b.id) or 0) end)
  return out
end

local function saveReports()
  local payload = json.encode(reports)
  SaveResourceFile(RESOURCE_NAME, Config.ReportsFile, payload, -1)
end

local function loadReports()
  local raw = LoadResourceFile(RESOURCE_NAME, Config.ReportsFile)
  if not raw or raw == "" then
    reports = {}
    return
  end

  local ok, decoded = pcall(json.decode, raw)
  reports = ok and normalizeReports(decoded) or {}

  for _, r in ipairs(reports) do
    r.id = tonumber(r.id or 0) or 0
    r.reporterId = tonumber(r.reporterId or r.reporter or 0) or 0
    r.targetId = tonumber(r.targetId or r.target or 0) or 0

    if r.reporterId > 0 and (not r.reporterName or r.reporterName == "") then
      r.reporterName = getName(r.reporterId)
    end
    if r.targetId > 0 and (not r.targetName or r.targetName == "") then
      r.targetName = getName(r.targetId)
    end

    if r.reporterId > 0 and (not r.reporterDiscord or r.reporterDiscord == "") then
      r.reporterDiscord = getDiscordID(r.reporterId) or ""
    end
    if r.targetId > 0 and (not r.targetDiscord or r.targetDiscord == "") then
      r.targetDiscord = getDiscordID(r.targetId) or ""
    end

    r.chat = (type(r.chat) == "table") and r.chat or {}
    for _, m in ipairs(r.chat) do
      if m.isStaff == nil then m.isStaff = false end
      if (not m.byDiscordId or m.byDiscordId == "") and m.byId then
        m.byDiscordId = getDiscordID(tonumber(m.byId) or 0) or ""
      end
      if not m.time or m.time == "" then m.time = nowIso() end
    end

    if r.resolved == nil then r.resolved = false end
    if r.notes == nil then r.notes = "" end
  end

  saveReports()
end

local function nextReportId()
  local maxId = 0
  for _, r in ipairs(reports) do
    local id = tonumber(r.id)
    if id and id > maxId then maxId = id end
  end
  return maxId + 1
end

local function findReport(reportId)
  reportId = tonumber(reportId or 0) or 0
  if reportId <= 0 then return nil end
  for _, r in ipairs(reports) do
    if tonumber(r.id) == reportId then return r end
  end
  return nil
end

local function broadcastAdmins(event, ...)
  for _, pid in ipairs(GetPlayers()) do
    local sid = tonumber(pid)
    if sid and sid > 0 and isAdmin(sid) then
      TriggerClientEvent(event, sid, ...)
    end
  end
end

local pendingCoords = {}
RegisterNetEvent("adminmenu:clientNotify", function(notif)
  SendNUIMessage({ action = "notify", notif = notif or {} })
end)

RegisterNetEvent("adminmenu:serverCoordsReply", function(reqId, coords)
  local src = source
  if type(reqId) ~= "string" or reqId == "" then return end
  local p = pendingCoords[reqId]
  if not p then return end
  if p.expectedSrc and tonumber(p.expectedSrc) ~= tonumber(src) then return end

  if type(coords) ~= "table" then coords = {} end
  p:resolve({
    x = tonumber(coords.x) or 0.0,
    y = tonumber(coords.y) or 0.0,
    z = tonumber(coords.z) or 0.0,
  })
end)

local function requestClientCoords(target, timeoutMs)
  target = tonumber(target or 0) or 0
  if target <= 0 then return nil end
  timeoutMs = tonumber(timeoutMs) or 2500

  local reqId = ("%s:%s:%s"):format(target, os.time(), math.random(100000, 999999))
  local p = promise.new()
  p.expectedSrc = target
  pendingCoords[reqId] = p

  TriggerClientEvent("adminmenu:clientRequestCoords", target, reqId)

  SetTimeout(timeoutMs, function()
    if pendingCoords[reqId] then
      pendingCoords[reqId]:resolve(nil)
      pendingCoords[reqId] = nil
    end
  end)

  local res = Citizen.Await(p)
  pendingCoords[reqId] = nil
  return res
end

local function hasOx()
  return GetResourceState("oxmysql") == "started" and exports.oxmysql ~= nil
end

local function oxExec(query, params)
  if not hasOx() then return {} end
  params = params or {}
  local p = promise.new()
  exports.oxmysql:execute(query, params, function(res) p:resolve(res) end)
  return Citizen.Await(p)
end

local function fetchDepartments()
  if not hasOx() then return {} end
  return oxExec(
    ("SELECT discordid, charid, department, paycheck FROM `%s` ORDER BY department ASC, discordid ASC")
      :format(Config.DepartmentsTable),
    {}
  )
end

local function upsertDepartment(row)
  if not hasOx() then return end
  return oxExec(
    ("INSERT INTO `%s` (discordid, charid, department, paycheck) VALUES (?, ?, ?, ?) " ..
     "ON DUPLICATE KEY UPDATE charid = VALUES(charid), paycheck = VALUES(paycheck)")
      :format(Config.DepartmentsTable),
    { row.discordid, row.charid, row.department, tonumber(row.paycheck) or 0 }
  )
end

local function modifyDepartment(row)
  if not hasOx() then return end
  return oxExec(
    ("UPDATE `%s` SET charid = ?, paycheck = ? WHERE discordid = ? AND department = ?")
      :format(Config.DepartmentsTable),
    { row.charid, tonumber(row.paycheck) or 0, row.discordid, row.department }
  )
end

local function removeDepartment(discordid, department)
  if not hasOx() then return end
  return oxExec(
    ("DELETE FROM `%s` WHERE discordid = ? AND department = ?"):format(Config.DepartmentsTable),
    { discordid, department }
  )
end

local function getConfiguredDepartments()
  local ok, res = azCall("getConfiguredDepartments")
  if ok and type(res) == "table" then
    return res
  end
  return {}
end

local function upsertConfiguredDepartment(row)
  local ok, res, extra = azCall("upsertConfiguredDepartment", row)
  if ok and res ~= false then
    return true, res, extra
  end
  if type(res) == "string" then
    return false, res
  end
  return false, tostring(res or extra or "Failed to save configured department")
end

local function removeConfiguredDepartment(id)
  local ok, res, extra = azCall("removeConfiguredDepartment", id)
  if ok and res ~= false then
    return true, res, extra
  end
  if type(res) == "string" then
    return false, res
  end
  return false, tostring(res or extra or "Failed to remove configured department")
end

local function callBridgeMoney(fnName, target, account, amount)
  local ok, res = azCall(fnName, target, account, amount)
  if ok and res == true then return true end
  return false, ("Az-Framework %s returned %s"):format(fnName, tostring(res))
end

local function callMoney(fnName, ...)
  local ok, res = azCall(fnName, ...)
  if not ok then
    return false, tostring(res)
  end

  if res == nil or res == false then
    return false, ("Az-Framework %s returned %s"):format(fnName, tostring(res))
  end

  return true, res
end

local function trySendMoneyToClient(target)
  azCall("sendMoneyToClient", target)
end

local function doMoneyOp(adminSrc, op, target, amount, extra)
  target = tonumber(target or 0) or 0
  amount = tonumber(amount or 0) or 0
  if target <= 0 then return false, "Invalid target" end

  op = tostring(op or ""):lower()
  local map = {
    addmoney="add", add="add", givemoney="add",
    removemoney="deduct", deductmoney="deduct", deduct="deduct", removecash="deduct",
    depositmoney="deposit", deposit="deposit",
    withdrawmoney="withdraw", withdraw="withdraw",
    transfermoney="transfer", transfer="transfer",
  }
  op = map[op] or op

  if op == "add" then
    if amount == 0 then return false, "Missing amount" end
    local ok, err = callBridgeMoney("AddBridgeMoney", target, "cash", amount)
    if not ok then ok, err = callMoney("addMoney", target, amount) end
    if not ok then return false, err end

  elseif op == "deduct" then
    if amount == 0 then return false, "Missing amount" end
    local ok, err = callBridgeMoney("RemoveBridgeMoney", target, "cash", amount)
    if not ok then ok, err = callMoney("deductMoney", target, amount) end
    if not ok then return false, err end

  elseif op == "deposit" then
    if amount == 0 then return false, "Missing amount" end
    local ok, err = callMoney("depositMoney", target, amount)
    if not ok then return false, err end

  elseif op == "withdraw" then
    if amount == 0 then return false, "Missing amount" end
    local ok, err = callMoney("withdrawMoney", target, amount)
    if not ok then return false, err end

  elseif op == "transfer" then
    local toId = tonumber(extra or 0) or 0
    if toId <= 0 then return false, "Transfer requires extra = target server id" end
    if amount == 0 then return false, "Missing amount" end

    local ok, err = callMoney("transferMoney", target, toId, amount)
    if not ok then return false, err end
    trySendMoneyToClient(toId)

  else
    return false, "Unknown op"
  end

  trySendMoneyToClient(target)
  return true
end

if not lib or not lib.callback or not lib.callback.register then
  print(("^1[%s]^7 ox_lib callback system not found. Start ox_lib."):format(RESOURCE_NAME))
else
  lib.callback.register("adminmenu:announce", function(src, data)
  if not isAdmin(src) then return false, "No permission" end
  data = data or {}
  local notif = data.notif or {}

  local title = tostring(notif.title or "")
  local msg   = tostring(notif.message or "")
  if title == "" and msg == "" then
    return false, "Missing title/message"
  end

  if #title > 120 then title = title:sub(1,120) end
  if #msg > 900 then msg = msg:sub(1,900) end
  notif.title = title
  notif.message = msg

  TriggerClientEvent("adminmenu:clientNotify", -1, notif)
  return true
end)

lib.callback.register("adminmenu:notifyPlayer", function(src, data)
  if not isAdmin(src) then return false, "No permission" end
  data = data or {}

  local target = tonumber(data.target or 0) or 0
  if target <= 0 or GetPlayerName(target) == nil then
    return false, "Invalid target"
  end

  local notif = data.notif or {}
  local title = tostring(notif.title or "")
  local msg   = tostring(notif.message or "")
  if title == "" and msg == "" then
    return false, "Missing title/message"
  end

  if #title > 120 then title = title:sub(1,120) end
  if #msg > 900 then msg = msg:sub(1,900) end
  notif.title = title
  notif.message = msg

  TriggerClientEvent("adminmenu:clientNotify", target, notif)
  return true
end)

lib.callback.register("adminmenu:getReports", function(src)
  local admin = isAdmin(src)

  local out = {}
  for _, r in ipairs(reports or {}) do
    local reporterId = tonumber(r.reporterId or 0) or 0
    local targetId   = tonumber(r.targetId or 0) or 0

    if admin or reporterId == src or targetId == src then
      out[#out+1] = r
    end
  end

  table.sort(out, function(a,b)
    return (tonumber(a.id) or 0) > (tonumber(b.id) or 0)
  end)

  return out
end)

local function createReportCore(src, data)
  if type(data) ~= "table" then return false, "Invalid payload" end

  local targetId = tonumber(data.targetId or data.target or 0) or 0
  local reason   = trim(data.reason)
  if reason == "" then return false, "Reason required" end

  local category = tostring(data.category or "General")
  local priority = tostring(data.priority or "normal")

  local rid = nextReportId()
  local report = {
    id = rid,

    reporterId      = src,
    reporterName    = getName(src),
    reporterDiscord = getDiscordID(src) or "",

    targetId      = targetId,
    targetName    = (targetId > 0 and getName(targetId)) or "",
    targetDiscord = (targetId > 0 and (getDiscordID(targetId) or "")) or "",

    reason   = reason,
    category = category,
    priority = priority,

    time     = nowIso(),
    resolved = false,

    chat  = {},
    notes = "",

    claimedById   = nil,
    claimedByName = nil,
    claimedAt     = nil,
  }

  table.insert(reports, 1, report)
  saveReports()

  report = enrichOneReport(report)
  TriggerClientEvent("adminmenu:nui:newReport", -1, report)
  TriggerClientEvent("adminmenu:clientRequestScreenshot", src, rid)

  return true, nil, report
end

_G.AzFrameworkCreateReport = createReportCore
exports("createReport", function(src, data)
  return createReportCore(src, data)
end)

  lib.callback.register("adminmenu:createReport", function(src, data)
    return createReportCore(src, data)
  end)

  lib.callback.register("adminmenu:resolveReport", function(src, id)
    if not isAdmin(src) then return false, "No permission" end
    id = tonumber(id or 0) or 0

    local r = findReport(id)
    if not r then return false, "Report not found" end

    r.resolved   = true
    r.resolvedBy = getName(src)
    r.resolvedAt = nowIso()

    saveReports()
    TriggerClientEvent("adminmenu:nui:updateReport", -1, id, true)
    pushUpsertToAll(r)
    return true
  end)

  lib.callback.register("adminmenu:deleteReport", function(src, id)
    if not isAdmin(src) then return false, "No permission" end
    id = tonumber(id or 0) or 0

    for i = #reports, 1, -1 do
      if tonumber(reports[i].id) == id then
        table.remove(reports, i)
        saveReports()
        TriggerClientEvent("adminmenu:nui:removeReport", -1, id)
        return true
      end
    end

    return false, "Report not found"
  end)

  lib.callback.register("adminmenu:claimReport", function(src, id)
    if not isAdmin(src) then return false, "No permission" end
    id = tonumber(id or 0) or 0

    local r = findReport(id)
    if not r then return false, "Report not found" end
    if r.resolved then return false, "Report is resolved" end

    r.claimedById   = src
    r.claimedByName = getName(src)
    r.claimedAt     = nowIso()

    saveReports()
    pushUpsertToAll(r)
    return true, nil, r
  end)

  lib.callback.register("adminmenu:sendChat", function(src, reportId, message)
    reportId = tonumber(reportId or 0) or 0
    message  = trim(message)

    if reportId <= 0 or message == "" then
      return false, "Invalid message"
    end

    local report = findReport(reportId)
    if not report then
      return false, "Report not found"
    end

    local admin = isAdmin(src)
    local allowed = admin
      or tonumber(report.reporterId or 0) == tonumber(src)
      or (tonumber(report.targetId or 0) > 0 and tonumber(report.targetId or 0) == tonumber(src))

    if not allowed then
      return false, "No permission"
    end

    report.chat = report.chat or {}
    table.insert(report.chat, {
      byId        = src,
      byName      = getName(src),
      byDiscordId = getDiscordID(src) or "",
      isStaff     = admin and true or false,
      time        = nowIso(),
      message     = message,
    })

    saveReports()

    report = enrichOneReport(report)

    broadcastAdmins("adminmenu:nui:upsertReport", report)
    sendToPlayer(tonumber(report.reporterId or 0), "adminmenu:nui:upsertReport", report)
    if tonumber(report.targetId or 0) > 0 then
      sendToPlayer(tonumber(report.targetId or 0), "adminmenu:nui:upsertReport", report)
    end

    return true, nil, report.chat
  end)

  lib.callback.register("adminmenu:saveNotes", function(src, id, notes)
    if not isAdmin(src) then return false, "No permission" end
    id = tonumber(id or 0) or 0
    notes = tostring(notes or "")

    local r = findReport(id)
    if not r then return false, "Report not found" end

    r.notes          = notes
    r.notesUpdatedBy = getName(src)
    r.notesUpdatedAt = nowIso()

    saveReports()
    pushUpsertToAll(r)
    return true
  end)

  lib.callback.register("adminmenu:getPlayers", function(src)
    if not isAdmin(src) then return {} end
    local list = {}
    for _, pid in ipairs(GetPlayers()) do
      local sid = tonumber(pid)
      list[#list + 1] = { id = sid, name = getName(sid), discord = getDiscordID(sid) or "" }
    end
    TriggerClientEvent("adminmenu:nui:loadPlayers", src, list)
    return list
  end)

  lib.callback.register("adminmenu:getPlayerDiscord", function(src, target)
    if not isAdmin(src) then return "" end
    local t = tonumber(target or 0) or 0
    if t <= 0 then return "" end
    return getDiscordID(t) or ""
  end)

  lib.callback.register("adminmenu:getDepartments", function(src)
    if not isAdmin(src) then return {} end
    return fetchDepartments()
  end)

  lib.callback.register("adminmenu:getConfiguredDepartments", function(src)
    if not isAdmin(src) then return {} end
    return getConfiguredDepartments()
  end)

  lib.callback.register("adminmenu:upsertConfiguredDepartment", function(src, row)
    if not isAdmin(src) then return false, "No permission" end
    if type(row) ~= "table" then return false, "Invalid payload" end

    local id = trim(row.id)
    local label = trim(row.label)
    local paycheck = tonumber(row.paycheck) or 0
    if id == "" or label == "" then
      return false, "id + label required"
    end

    local ok, resultOrErr = upsertConfiguredDepartment({
      id = id,
      label = label,
      paycheck = paycheck,
      canUseAOP = row.canUseAOP == true,
      canUsePrio = row.canUsePrio == true,
      enabled = row.enabled ~= false,
    })

    if not ok then
      return false, resultOrErr
    end

    local refreshed = getConfiguredDepartments()
    TriggerClientEvent("adminmenu:nui:loadConfiguredDepartments", -1, refreshed)
    return true, nil, refreshed
  end)

  lib.callback.register("adminmenu:removeConfiguredDepartment", function(src, row)
    if not isAdmin(src) then return false, "No permission" end
    if type(row) ~= "table" then return false, "Invalid payload" end

    local id = trim(row.id)
    if id == "" then return false, "id required" end

    local ok, resultOrErr = removeConfiguredDepartment(id)
    if not ok then
      return false, resultOrErr
    end

    local refreshed = getConfiguredDepartments()
    TriggerClientEvent("adminmenu:nui:loadConfiguredDepartments", -1, refreshed)
    return true, nil, refreshed
  end)

  lib.callback.register("adminmenu:createDepartment", function(src, row)
    if not isAdmin(src) then return false, "No permission" end
    if type(row) ~= "table" then return false, "Invalid payload" end
    if not hasOx() then return false, "oxmysql not started" end

    local discordid  = trim(row.discordid):gsub("%s+", "")
    local department = trim(row.department)
    local charid     = trim(row.charid):gsub("%s+", "")
    local paycheck   = tonumber(row.paycheck) or 0

    if discordid == "" or department == "" then return false, "discordid + department required" end
    if charid == "" then charid = discordid end

    upsertDepartment({ discordid = discordid, charid = charid, department = department, paycheck = paycheck })
    TriggerClientEvent("adminmenu:nui:loadDepartments", -1, fetchDepartments())
    return true
  end)

  lib.callback.register("adminmenu:modifyDepartment", function(src, row)
    if not isAdmin(src) then return false, "No permission" end
    if type(row) ~= "table" then return false, "Invalid payload" end
    if not hasOx() then return false, "oxmysql not started" end

    local discordid  = trim(row.discordid):gsub("%s+", "")
    local department = trim(row.department)
    local charid     = trim(row.charid):gsub("%s+", "")
    local paycheck   = tonumber(row.paycheck) or 0

    if discordid == "" or department == "" then return false, "discordid + department required" end
    if charid == "" then charid = discordid end

    modifyDepartment({ discordid = discordid, charid = charid, department = department, paycheck = paycheck })
    TriggerClientEvent("adminmenu:nui:loadDepartments", -1, fetchDepartments())
    return true
  end)

  lib.callback.register("adminmenu:removeDepartment", function(src, row)
    if not isAdmin(src) then return false, "No permission" end
    if type(row) ~= "table" then return false, "Invalid payload" end
    if not hasOx() then return false, "oxmysql not started" end

    local discordid  = trim(row.discordid):gsub("%s+", "")
    local department = trim(row.department)

    if discordid == "" or department == "" then return false, "discordid + department required" end

    removeDepartment(discordid, department)
    TriggerClientEvent("adminmenu:nui:loadDepartments", -1, fetchDepartments())
    return true
  end)

  lib.callback.register("adminmenu:moneyOp", function(src, data)
    if not isAdmin(src) then return false, "No permission" end
    if type(data) ~= "table" then return false, "Invalid payload" end

    local op     = tostring(data.op or data.command or data.action or "")
    local target = tonumber(data.target or data.player or 0) or 0
    local amount = tonumber(data.amount or data.value or 0) or 0
    local extra  = data.extra

    if op == "" then return false, "Missing op" end

    local ok, err = doMoneyOp(src, op, target, amount, extra)
    if not ok then
      dprint(("Money op FAILED op=%s target=%s amount=%s extra=%s err=%s")
        :format(op, target, amount, tostring(extra), tostring(err)))
      return false, err
    end

    dprint(("Money op OK op=%s target=%s amount=%s extra=%s by=%s")
      :format(op, target, amount, tostring(extra), getName(src)))

    return true
  end)

  lib.callback.register("adminmenu:teleportTo", function(src, target)
    if not isAdmin(src) then return false, "No permission" end
    target = tonumber(target or 0) or 0
    if target <= 0 then return false, "Invalid target" end

    local coords = requestClientCoords(target, 2500)
    if not coords then return false, "Could not fetch target coords" end
    TriggerClientEvent("adminmenu:clientTeleportTo", src, coords.x, coords.y, coords.z + 1.0)
    return true
  end)

  lib.callback.register("adminmenu:bring", function(src, target)
    if not isAdmin(src) then return false, "No permission" end
    target = tonumber(target or 0) or 0
    if target <= 0 then return false, "Invalid target" end

    local coords = requestClientCoords(src, 2500)
    if not coords then return false, "Could not fetch your coords" end
    TriggerClientEvent("adminmenu:clientTeleportTo", target, coords.x, coords.y, coords.z + 1.0)
    return true
  end)

  lib.callback.register("adminmenu:freeze", function(src, target)
    if not isAdmin(src) then return false, "No permission" end
    target = tonumber(target or 0) or 0
    if target <= 0 then return false, "Invalid target" end
    TriggerClientEvent("adminmenu:clientFreezeToggle", target)
    return true
  end)

  lib.callback.register("adminmenu:kick", function(src, target)
    if not isAdmin(src) then return false, "No permission" end
    target = tonumber(target or 0) or 0
    if target <= 0 then return false, "Invalid target" end
    DropPlayer(target, "Kicked by staff.")
    return true
  end)
end

RegisterNetEvent("adminmenu:requestOpenAdmin", function()
  local src = source
  if not isAdmin(src) then
    TriggerClientEvent("adminmenu:denyOpen", src, "You do not have permission.")
    return
  end
  TriggerClientEvent("adminmenu:allowOpen", src, { myServerId = src, isAdmin = true })
end)

RegisterNetEvent("adminmenu:requestOpenUser", function()
  local src = source
  TriggerClientEvent("adminmenu:allowOpen", src, { myServerId = src, isAdmin = false })
end)

RegisterNetEvent("adminmenu:requestOpenMy", function()
  local src = source
  TriggerClientEvent("adminmenu:allowOpen", src, { myServerId = src, isAdmin = isAdmin(src) })
end)

RegisterNetEvent("adminmenu:clientOpened", function()
  local src = source

  if isAdmin(src) then
    pushReportsTo(src, reports)
    TriggerClientEvent("adminmenu:nui:loadDepartments", src, fetchDepartments())
  else
    local mine = {}
    for _, r in ipairs(reports) do
      if tonumber(r.reporterId) == tonumber(src) then
        mine[#mine + 1] = r
      end
    end
    pushReportsTo(src, mine)
    TriggerClientEvent("adminmenu:nui:loadDepartments", src, {})
  end
end)

RegisterNetEvent("adminmenu:submitReport", function(targetId, reason)
  local src = source
  targetId = tonumber(targetId or 0) or 0
  reason = trim(reason)
  if reason == "" then return end

  local rid = nextReportId()
  local report = {
    id = rid,

    reporterId      = src,
    reporterName    = getName(src),
    reporterDiscord = getDiscordID(src) or "",

    targetId      = targetId,
    targetName    = (targetId > 0 and getName(targetId)) or "",
    targetDiscord = (targetId > 0 and (getDiscordID(targetId) or "")) or "",

    reason   = reason,
    category = "General",
    priority = "normal",
    time     = nowIso(),

    resolved = false,
    chat     = {},
    notes    = "",
  }

  table.insert(reports, 1, report)
  saveReports()

  report = enrichOneReport(report)
  TriggerClientEvent("adminmenu:nui:newReport", -1, report)
  TriggerClientEvent("adminmenu:clientRequestScreenshot", src, rid)
end)

local screenshotBuffers = {}

RegisterNetEvent("adminmenu:serverReceiveScreenshotChunk", function(reportId, idx, total, chunk)
  reportId = tonumber(reportId or 0) or 0
  idx = tonumber(idx or 0) or 0
  total = tonumber(total or 0) or 0

  if reportId <= 0 or idx <= 0 or total <= 0 then return end
  if type(chunk) ~= "string" then return end

  screenshotBuffers[reportId] = screenshotBuffers[reportId] or { total = total, got = 0, parts = {} }
  local b = screenshotBuffers[reportId]
  b.total = total

  if not b.parts[idx] then
    b.parts[idx] = chunk
    b.got = b.got + 1
  end

  if b.got >= b.total then
    local dataUrl = table.concat(b.parts, "")
    screenshotBuffers[reportId] = nil

    local r = findReport(reportId)
    if r then
      r.screenshotDataUrl = dataUrl
      saveReports()

      TriggerClientEvent("adminmenu:nui:reportScreenshot", -1, reportId, dataUrl)

      pushUpsertToAll(r)
    end

    dprint(("Screenshot received for report #%s (%d chars)"):format(reportId, #dataUrl))
  end
end)

CreateThread(function()
  loadReports()
  dprint(("Loaded %d reports"):format(#reports))

  if not hasOx() then
    print(("^3[%s]^7 oxmysql not started; Departments will be disabled."):format(RESOURCE_NAME))
  end

  if DISCORD_BOT_TOKEN == "" then
    print(("^3[%s]^7 DISCORD_BOT_TOKEN not set; using default Discord avatars only."):format(RESOURCE_NAME))
  end
end)
