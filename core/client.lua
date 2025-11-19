-- client.lua (refactored, same behavior)
local RESOURCE = GetCurrentResourceName()
print(("[az-fw-hud] client.lua (cookies-only) loaded. Resource=%s IsDuplicity=%s"):format(RESOURCE, tostring(IsDuplicityVersion())))

if IsDuplicityVersion() then
  print(("[az-fw-hud] ERROR: client.lua executed server-side. Move this file to client_scripts in fxmanifest.lua."):format(RESOURCE))
  return
end

-- ==== Utilities & Constants ====
local function safePrint(msg)
  print("[az-fw-hud] " .. tostring(msg))
end

local function sendNui(msg)
  SendNUIMessage(msg)
end

local function pushNoSettingsToNui()
  sendNui({ action = "loadSettings", settings = nil })
  safePrint("Sent empty HUD settings to NUI (cookies/localStorage mode).")
end

local function trim(s)
  return (s and s:gsub("^%s*(.-)%s*$", "%1") or "")
end

-- small helper to register network events + handler in one line (keeps behavior same)
local function onNet(eventName, handler)
  RegisterNetEvent(eventName)
  AddEventHandler(eventName, handler)
end

-- ==== NUI callbacks ====
if type(RegisterNUICallback) ~= "function" then
  safePrint("WARNING: RegisterNUICallback not available; NUI callbacks won't be registered.")
else
  local function registerNuiCallbacks()
    RegisterNUICallback("saveHUD", function(data, cb)
      safePrint("Received saveHUD from NUI (cookies/localStorage mode).")
      SetNuiFocus(false, false)
      sendNui({ action = "saved", ok = true })
      if cb then cb({ ok = true }) end
    end)

    RegisterNUICallback("resetDefaults", function(_, cb)
      safePrint("Received resetDefaults from NUI (cookies/localStorage mode).")
      SetNuiFocus(false, false)
      if cb then cb({ ok = true }) end
    end)

    RegisterNUICallback("closeUI", function(_, cb)
      SetNuiFocus(false, false)
      if cb then cb({ ok = true }) end
    end)

    RegisterNUICallback("requestSettings", function(_, cb)
      pushNoSettingsToNui()
      if cb then cb({ ok = true }) end
    end)
  end

  registerNuiCallbacks()
end

-- ==== Net events (HUD updates / job / cash) ====
onNet("updateCashHUD", function(cash, bank, playerName)
  sendNui({ action = "updateCash", cash = cash, bank = bank, playerName = playerName })
end)

onNet("az-fw-departments:refreshJob", function(data)
  sendNui({ action = "updateJob", job = data.job })
  TriggerServerEvent("az-fw-departments:setActive", data.job)
end)

onNet("hud:setDepartment", function(job)
  sendNui({ action = "updateJob", job = job })
end)

-- ==== First spawn department request ====
local firstSpawn = true
AddEventHandler("playerSpawned", function()
  if firstSpawn then
    firstSpawn = false
    TriggerServerEvent("hud:requestDepartment")
  end
end)

-- ==== Commands ====
RegisterCommand("movehud", function()
  SetNuiFocus(true, true)
  sendNui({ action = "toggleMove" })
end, false)

-- ==== Character menu & context helpers ====
local CHAR_MAIN = "char_main_menu"
local CHAR_LIST = "char_list_menu"
local EVENT_SHOW_LIST = "az-fw-money:openListMenu"
-- lib.registerContext is used later to register contexts

-- Pre-register the main context (structure kept the same)
lib.registerContext({
  id = CHAR_MAIN,
  title = "📝 Character Menu",
  canClose = true,
  options = {
    {
      title = "➕ Register New Character",
      description = "Create a brand-new character",
      icon = "user-plus",
      event = "az-fw-money:openRegisterDialog"
    },
    {
      title = "📜 List / Select Character",
      description = "Switch between your saved characters",
      icon = "users",
      event = EVENT_SHOW_LIST
    }
  }
})

-- ==== Register dialog for new characters ====
onNet("az-fw-money:openRegisterDialog", function()
  local title = "Register Character"
  local fields = {
    {
      type = "input",
      label = "First Name",
      placeholder = "John",
      required = true,
      min = 1,
      max = 20,
      icon = "id-badge"
    },
    {
      type = "input",
      label = "Last Name",
      placeholder = "Doe",
      required = true,
      min = 1,
      max = 20,
      icon = "id-badge"
    }
  }
  local opts = { allowCancel = true }

  while true do
    local inputs = lib.inputDialog(title, fields, opts)

    if not inputs then
      lib.notify({
        title = "Registration",
        description = "Registration cancelled.",
        type = "inform"
      })
      break
    end

    local first = trim(inputs[1] or "")
    local last = trim(inputs[2] or "")

    if first ~= "" and last ~= "" then
      TriggerServerEvent("az-fw-money:registerCharacter", first, last)
      break
    else
      lib.notify({
        title = "Registration",
        description = "First and last name are required and cannot be empty.",
        type = "error"
      })
      Citizen.Wait(150)
    end
  end
end)

-- ==== Show list / select character ====
onNet(EVENT_SHOW_LIST, function()
  lib.callback("az-fw-money:fetchCharacters", {}, function(rows)
    local opts = {}

    if not rows or #rows == 0 then
      table.insert(opts, { title = "❗ You have no characters yet", disabled = true })
    else
      for _, row in ipairs(rows) do
        table.insert(opts, {
          title = row.name,
          description = "ID: " .. row.charid,
          icon = "user",
          onSelect = function()
            TriggerServerEvent("az-fw-money:selectCharacter", row.charid)
          end
        })
      end
    end

    lib.registerContext({
      id = CHAR_LIST,
      title = "🔄 Your Characters",
      menu = CHAR_MAIN,
      canClose = true,
      options = opts
    })
    lib.showContext(CHAR_LIST)
  end)
end)

-- ==== Character notifications (registered / selected) ====
onNet("az-fw-money:characterRegistered", function(charid)
  lib.notify({
    title = "Character Registered",
    description = "Your new char ID is " .. charid,
    type = "success"
  })
  TriggerServerEvent("az-fw-money:requestMoney")
end)

onNet("az-fw-money:characterSelected", function(charid)
  lib.notify({
    title = "Character Selected",
    description = "Now using char ID " .. charid,
    type = "info"
  })
  TriggerServerEvent("az-fw-money:requestMoney")
end)

-- ==== Client export: refresh / update HUD ====
local function refreshHUD()
  safePrint("refreshHUD export called; requesting money and department from server.")
  -- Ask server to resend money + job/department info, which will in turn hit the NUI events above
  TriggerServerEvent("az-fw-money:requestMoney")
  TriggerServerEvent("hud:requestDepartment")
end

-- Exports usable from other client scripts:
--   exports['az-fw-hud']:refreshHUD()
--   exports['az-fw-hud']:updateHUD()
exports('refreshHUD', refreshHUD)
exports('updateHUD', refreshHUD)

safePrint("client.lua (cookies-only) initialized.")
