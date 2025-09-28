local RESOURCE = GetCurrentResourceName()

print(("[az-fw-hud] client.lua (cookies-only) loaded. Resource=%s IsDuplicity=%s"):format(RESOURCE, tostring(IsDuplicityVersion())))


if IsDuplicityVersion() then
  print(("[az-fw-hud] ERROR: client.lua executed server-side. Move this file to client_scripts in fxmanifest.lua."):format(RESOURCE))
  return
end


local function pushNoSettingsToNui()
  SendNUIMessage({ action = "loadSettings", settings = nil })
  print("[az-fw-hud] Sent empty HUD settings to NUI (cookies/localStorage mode).")
end


if type(RegisterNUICallback) ~= "function" then
  print("[az-fw-hud] WARNING: RegisterNUICallback not available; NUI callbacks won't be registered.")
else
  RegisterNUICallback("saveHUD", function(data, cb)
    
    
    print("[az-fw-hud] Received saveHUD from NUI (cookies/localStorage mode).")
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "saved", ok = true })
    if cb then cb({ ok = true }) end
  end)

  
  RegisterNUICallback("resetDefaults", function(_, cb)
    print("[az-fw-hud] Received resetDefaults from NUI (cookies/localStorage mode).")
    
    
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


RegisterNetEvent("updateCashHUD")
AddEventHandler("updateCashHUD", function(cash, bank, playerName)
  SendNUIMessage({ action = "updateCash", cash = cash, bank = bank, playerName = playerName })
end)

RegisterNetEvent("az-fw-departments:refreshJob")
AddEventHandler("az-fw-departments:refreshJob", function(data)
  SendNUIMessage({ action = "updateJob", job = data.job })
  TriggerServerEvent("az-fw-departments:setActive", data.job)
end)

RegisterNetEvent("hud:setDepartment")
AddEventHandler("hud:setDepartment", function(job)
  SendNUIMessage({ action = "updateJob", job = job })
end)



local firstSpawn = true

AddEventHandler(
    "playerSpawned",
    function()
        if firstSpawn then
            firstSpawn = false
            TriggerServerEvent("hud:requestDepartment")
        end
    end
)


RegisterNetEvent("az-fw-money:openRegisterDialog")




RegisterCommand(
    "movehud",
    function()
        SetNuiFocus(true, true)
        SendNUIMessage({action = "toggleMove"})
    end,
    false
)



local CHAR_MAIN = "char_main_menu"
local CHAR_LIST = "char_list_menu"
local EVENT_SHOW_LIST = "az-fw-money:openListMenu"

lib.registerContext(
    {
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
    }
)


RegisterNetEvent("az-fw-money:openRegisterDialog")
AddEventHandler(
    "az-fw-money:openRegisterDialog",
    function()
        local function trim(s)
            return (s and s:gsub("^%s*(.-)%s*$", "%1") or "")
        end

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
        local opts = {allowCancel = true}

        while true do
            local inputs = lib.inputDialog(title, fields, opts)

            if not inputs then
                lib.notify(
                    {
                        title = "Registration",
                        description = "Registration cancelled.",
                        type = "inform"
                    }
                )
                break
            end

            local first = trim(inputs[1] or "")
            local last = trim(inputs[2] or "")

            if first ~= "" and last ~= "" then
                TriggerServerEvent("az-fw-money:registerCharacter", first, last)
                break
            else
                lib.notify(
                    {
                        title = "Registration",
                        description = "First and last name are required and cannot be empty.",
                        type = "error"
                    }
                )
                Citizen.Wait(150)
            end
        end
    end
)


RegisterNetEvent(EVENT_SHOW_LIST)
AddEventHandler(
    EVENT_SHOW_LIST,
    function()
        lib.callback(
            "az-fw-money:fetchCharacters",
            {},
            function(rows)
                local opts = {}

                if not rows or #rows == 0 then
                    table.insert(opts, {title = "❗ You have no characters yet", disabled = true})
                else
                    for _, row in ipairs(rows) do
                        table.insert(
                            opts,
                            {
                                title = row.name,
                                description = "ID: " .. row.charid,
                                icon = "user",
                                onSelect = function()
                                    TriggerServerEvent("az-fw-money:selectCharacter", row.charid)
                                end
                            }
                        )
                    end
                end

                lib.registerContext(
                    {
                        id = CHAR_LIST,
                        title = "🔄 Your Characters",
                        menu = CHAR_MAIN,
                        canClose = true,
                        options = opts
                    }
                )
                lib.showContext(CHAR_LIST)
            end
        )
    end
)

RegisterNetEvent("az-fw-money:characterRegistered")
AddEventHandler(
    "az-fw-money:characterRegistered",
    function(charid)
        lib.notify(
            {
                title = "Character Registered",
                description = "Your new char ID is " .. charid,
                type = "success"
            }
        )
        TriggerServerEvent("az-fw-money:requestMoney")
    end
)

RegisterNetEvent("az-fw-money:characterSelected")
AddEventHandler(
    "az-fw-money:characterSelected",
    function(charid)
        lib.notify(
            {
                title = "Character Selected",
                description = "Now using char ID " .. charid,
                type = "info"
            }
        )
        TriggerServerEvent("az-fw-money:requestMoney")
    end
)

RegisterCommand(
    "char",
    function()
        lib.showContext(CHAR_MAIN)
    end,
    false
)

print("[az-fw-hud] client.lua (cookies-only) initialized.")
