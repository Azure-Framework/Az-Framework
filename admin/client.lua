local RESOURCE_NAME = GetCurrentResourceName()

Config = Config or {}
local DEBUG = Config.Debug == true

local function dprint(...)
  if not DEBUG then return end
  local args = {...}
  for i=1,#args do args[i]=tostring(args[i]) end
  print(("^3[%s]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local uiOpen = false
local myServerId = nil
local myIsAdmin = false
local isAdmin = false

local function nui(action, payload)
  SendNUIMessage({ action = action, payload = payload })
end

local function setFocus(state)
  SetNuiFocus(state, state)
  SetNuiFocusKeepInput(false)
end

local function isGameplayReady()
  local stateVal = nil
  pcall(function()
    if LocalPlayer and LocalPlayer.state then
      stateVal = LocalPlayer.state.azfwGameplayReady
    end
  end)
  return stateVal == true
end

local function requireGameplayReady(label)
  if isGameplayReady() then return true end
  local msg = tostring(label or 'This menu') .. ' is only available after you finish selecting a character and spawn into the world.'
  TriggerEvent('chat:addMessage', { args = { '^1AZ-FRAMEWORK', msg } })
  return false
end

local controlThread = nil
local function startControlLock()
  if controlThread then return end
  controlThread = CreateThread(function()
    while uiOpen do
      DisableAllControlActions(0)
      EnableControlAction(0, 322, true)
      EnableControlAction(0, 200, true)
      Wait(0)
    end
    controlThread = nil
  end)
end

local function openUI()
  if uiOpen then return end
  uiOpen = true
  setFocus(true)
  startControlLock()
  nui("openMenu", { myServerId = myServerId, isAdmin = isAdmin })
end

local function closeUI()
  if not uiOpen then return end
  uiOpen = false
  setFocus(false)
  nui("closeShell", {})
end

RegisterCommand("adminmenu", function()
  if not requireGameplayReady("Admin menu") then return end
  TriggerServerEvent("adminmenu:requestOpenAdmin")
end, false)

RegisterKeyMapping("adminmenu", "Open Admin Menu", "keyboard", "PAGEUP")

RegisterCommand("report", function(_, args)
  if not requireGameplayReady("Reports") then return end
  if not args or #args == 0 then
    TriggerServerEvent("adminmenu:requestOpenUser")
    return
  end

  local target = tonumber(args[1])
  if target then
    table.remove(args, 1)
  else
    target = 0
  end

  local reason = table.concat(args, " ")
  reason = tostring(reason or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if reason == "" then
    TriggerEvent('chat:addMessage', { args = { "^1REPORT", "Usage: /report [serverId] <reason>" } })
    return
  end

  TriggerServerEvent("adminmenu:submitReport", target, reason)

  TriggerServerEvent("adminmenu:requestOpenUser")
end, false)

RegisterCommand("reports", function()
  if not requireGameplayReady("Reports") then return end
  TriggerServerEvent("adminmenu:requestOpenUser")
end, false)

RegisterNetEvent("adminmenu:allowOpen", function(payload)
  myServerId = (payload and payload.myServerId) or GetPlayerServerId(PlayerId())
  isAdmin = (payload and payload.isAdmin) == true
  openUI()
end)
RegisterNetEvent("adminmenu:clientNotify", function(notif)
  SendNUIMessage({ action = "notify", payload = notif or {} })
end)

RegisterNetEvent("adminmenu:denyOpen", function(msg)
  TriggerEvent('chat:addMessage', { args = { "^1ADMIN", msg or "No permission." } })
end)

RegisterNUICallback("closeMenu", function(_, cb)
  closeUI()
  cb({ ok = true })
end)

RegisterNUICallback("adminAnnounce", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:announce", false, data or {})
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("notifyPlayer", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:notifyPlayer", false, data or {})
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("openMenu", function(_, cb)

  TriggerServerEvent("adminmenu:clientOpened")
  cb({ ok = true })
end)

RegisterNUICallback("getReports", function(_, cb)
  local reports = lib.callback.await("adminmenu:getReports", false) or {}
  cb({ ok = true, reports = reports })
end)

RegisterNUICallback("createReport", function(data, cb)
  local ok, err, report = lib.callback.await("adminmenu:createReport", false, data or {})
  cb({ ok = ok and true or false, error = err, report = report })
end)

RegisterNUICallback("resolveReport", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:resolveReport", false, tonumber(data.id or 0))
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("deleteReport", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:deleteReport", false, tonumber(data.id or 0))
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("claimReport", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:claimReport", false, tonumber(data.id or 0))
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("sendChat", function(data, cb)
  local id = tonumber(data.id or 0)
  local msg = tostring(data.message or "")
  local ok, err, chat = lib.callback.await("adminmenu:sendChat", false, id, msg)
  cb({ ok = ok and true or false, error = err, chat = chat or {} })
end)

RegisterNUICallback("saveNotes", function(data, cb)
  local id = tonumber(data.id or 0)
  local notes = tostring(data.notes or "")
  local ok, err = lib.callback.await("adminmenu:saveNotes", false, id, notes)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("getPlayers", function(_, cb)
  local players = lib.callback.await("adminmenu:getPlayers", false)
  cb({ ok = true, players = players or {} })
end)

RegisterNUICallback("requestPlayerDiscord", function(data, cb)
  local target = tonumber(data.target or 0)
  local discord = lib.callback.await("adminmenu:getPlayerDiscord", false, target)
  cb({ ok = true, discord = discord or "" })
end)

RegisterNUICallback("teleport", function(data, cb)
  local target = tonumber(data.target or 0)
  local ok, err = lib.callback.await("adminmenu:teleportTo", false, target)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("bring", function(data, cb)
  local target = tonumber(data.target or 0)
  local ok, err = lib.callback.await("adminmenu:bring", false, target)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("freeze", function(data, cb)
  local target = tonumber(data.target or 0)
  local ok, err = lib.callback.await("adminmenu:freeze", false, target)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("kick", function(data, cb)
  local target = tonumber(data.target or 0)
  local ok, err = lib.callback.await("adminmenu:kick", false, target)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNetEvent("Az-Admin:sendChat", function(reportId, message)
  local src = source
  reportId = tonumber(reportId)
  message = tostring(message or ""):gsub("^%s+", ""):gsub("%s+$", "")

  if not reportId or message == "" then return end

  local report = Reports[reportId]
  if not report then return end

  report.chat = report.chat or {}

  local entry = {
    byId       = src,
    byName     = GetPlayerName(src) or ("Player " .. tostring(src)),
    byDiscord  = getDiscordId(src),
    isStaff    = isStaff(src) or false,
    time       = nowString(),
    message    = message
  }

  table.insert(report.chat, entry)

  saveReports()

  TriggerClientEvent("Az-Admin:ui:upsertReport", -1, report)
end)

RegisterNetEvent("Az-Admin:requestReports", function()
  local src = source
  local out = {}
  for id, r in pairs(Reports) do out[#out + 1] = r end
  table.sort(out, function(a,b) return (tonumber(a.id) or 0) > (tonumber(b.id) or 0) end)
  TriggerClientEvent("Az-Admin:ui:loadReports", src, out)
end)

RegisterNUICallback("moneyOp", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:moneyOp", false, data)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("getDepartments", function(_, cb)
  local departments = lib.callback.await("adminmenu:getDepartments", false)
  cb({ ok = true, departments = departments or {} })
end)

RegisterNUICallback("getConfiguredDepartments", function(_, cb)
  local departments = lib.callback.await("adminmenu:getConfiguredDepartments", false)
  cb({ ok = true, departments = departments or {} })
end)

RegisterNUICallback("upsertConfiguredDepartment", function(data, cb)
  local ok, err, departments = lib.callback.await("adminmenu:upsertConfiguredDepartment", false, data or {})
  cb({ ok = ok and true or false, error = err, departments = departments or {} })
end)

RegisterNUICallback("removeConfiguredDepartment", function(data, cb)
  local ok, err, departments = lib.callback.await("adminmenu:removeConfiguredDepartment", false, data or {})
  cb({ ok = ok and true or false, error = err, departments = departments or {} })
end)

RegisterNUICallback("createDepartment", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:createDepartment", false, data)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("modifyDepartment", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:modifyDepartment", false, data)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback("removeDepartment", function(data, cb)
  local ok, err = lib.callback.await("adminmenu:removeDepartment", false, data)
  cb({ ok = ok and true or false, error = err })
end)

RegisterNetEvent("adminmenu:nui:loadReports", function(reports)
  if not uiOpen then return end
  SendNUIMessage({ action = "loadReports", reports = reports or {} })
end)

RegisterNetEvent("adminmenu:nui:newReport", function(report)
  if not uiOpen then return end
  SendNUIMessage({ action = "newReport", report = report })
end)

RegisterNetEvent("adminmenu:nui:updateReport", function(id, resolved)
  if not uiOpen then return end
  SendNUIMessage({ action = "updateReport", id = id, resolved = resolved })
end)

RegisterNetEvent("adminmenu:nui:upsertReport", function(report)
  if not uiOpen then return end

  if (not isAdmin) and report and tonumber(report.reporterId) ~= tonumber(myServerId) then
    return
  end
  SendNUIMessage({ action = "upsertReport", report = report })
end)

RegisterNetEvent("adminmenu:nui:removeReport", function(id)
  if not uiOpen then return end
  SendNUIMessage({ action = "removeReport", id = id })
end)

RegisterNetEvent("adminmenu:nui:loadPlayers", function(players)
  if not uiOpen then return end
  SendNUIMessage({ action = "loadPlayers", players = players or {} })
end)

RegisterNetEvent("adminmenu:nui:playerDiscord", function(target, discord)
  if not uiOpen then return end
  SendNUIMessage({ action = "playerDiscord", target = target, discord = discord or "" })
end)

RegisterNetEvent("adminmenu:nui:loadDepartments", function(departments)
  if not uiOpen then return end
  SendNUIMessage({ action = "loadDepartments", departments = departments or {} })
end)

RegisterNetEvent("adminmenu:nui:loadConfiguredDepartments", function(departments)
  if not uiOpen then return end
  SendNUIMessage({ action = "loadConfiguredDepartments", departments = departments or {} })
end)

RegisterNetEvent("adminmenu:nui:reportScreenshot", function(id, image)
  if not uiOpen then return end
  SendNUIMessage({ action = "reportScreenshot", id = id, image = image })
end)

RegisterNetEvent("adminmenu:clientRequestScreenshot", function(reportId)
  local rid = tonumber(reportId or 0)
  if rid <= 0 then return end

  if GetResourceState("screenshot-basic") ~= "started" then
    dprint("screenshot-basic not started; skipping screenshot.")
    return
  end

  exports["screenshot-basic"]:requestScreenshot(function(data)
    if not data or data == "" then return end

    local max = tonumber(Config.ChunkMaxSize) or 8000
    local parts = {}
    for i = 1, #data, max do
      parts[#parts+1] = data:sub(i, i + max - 1)
      if #parts > (tonumber(Config.ChunkMaxParts) or 600) then break end
    end

    for idx, chunk in ipairs(parts) do
      TriggerServerEvent("adminmenu:serverReceiveScreenshotChunk", rid, idx, #parts, chunk)
      Wait(0)
    end
  end)
end)

AddEventHandler("onResourceStop", function(res)
  if res ~= RESOURCE_NAME then return end
  if uiOpen then
    setFocus(false)
  end
end)

RegisterNetEvent("adminmenu:clientTeleportTo", function(x, y, z)
  local ped = PlayerPedId()
  SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false)
end)

local frozen = false
RegisterNetEvent("adminmenu:clientFreezeToggle", function()
  frozen = not frozen
  FreezeEntityPosition(PlayerPedId(), frozen)
end)

RegisterNetEvent("adminmenu:clientRequestCoords", function(reqId)
  if not reqId then return end
  local ped = PlayerPedId()
  local c = GetEntityCoords(ped)
  TriggerServerEvent("adminmenu:serverCoordsReply", reqId, { x = c.x, y = c.y, z = c.z })
end)
RegisterCommand("testnotify", function()
  SendNUIMessage({
    action = "notify",
    payload = {
      icon = "🧪",
      title = "Test Notify",
      message = "If you see this, the overlay renderer works.",
      position = "top-right",
      duration = 6000,
      progress = true
    }
  })
end, false)
