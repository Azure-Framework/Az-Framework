-- client.lua

-- =========================================================
-- 1) INITIAL HUD & NUI MESSAGING FOR MONEY + DEPARTMENTS
-- =========================================================

local firstSpawn = true
AddEventHandler('playerSpawned', function()
    if firstSpawn then
        firstSpawn = false
        TriggerServerEvent('az-fw-money:requestMoney')
        TriggerServerEvent('hud:requestDepartment')
    end
end)

RegisterNetEvent("updateCashHUD")
AddEventHandler("updateCashHUD", function(cash, bank)
    print(("[HUD][Client] updateCashHUD invoked → cash=%s, bank=%s"):format(cash, bank))
    SendNUIMessage({ action = "updateCash", cash = cash, bank = bank })
end)

RegisterNetEvent("az-fw-departments:refreshJob")
AddEventHandler("az-fw-departments:refreshJob", function(data)
    SendNUIMessage({ action = "updateJob", job = data.job })
end)

RegisterNetEvent("hud:setDepartment")
AddEventHandler("hud:setDepartment", function(job)
    SendNUIMessage({ action = "updateJob", job = job })
end)

RegisterCommand("movehud", function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "toggleMove" })
end, false)

RegisterNUICallback('closeUI', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)


-- =========================================================
-- 2) CHARACTER MENU: CONTEXT + DIALOG FLOW
-- =========================================================

local CHAR_MAIN       = 'char_main_menu'
local CHAR_LIST       = 'char_list_menu'
local EVENT_SHOW_LIST = 'az-fw-money:openListMenu'

-- 2.1) Main “/char” menu
lib.registerContext({
    id       = CHAR_MAIN,
    title    = '📝 Character Menu',
    canClose = true,
    options  = {
        {
            title       = '➕ Register New Character',
            description = 'Create a brand‑new character',
            icon        = 'user-plus',
            event       = 'az-fw-money:openRegisterDialog'
        },
        {
            title       = '📜 List / Select Character',
            description = 'Switch between your saved characters',
            icon        = 'users',
            event       = EVENT_SHOW_LIST
        },
    }
})


-- 2.2) “Register New Character” dialog (first+last)
RegisterNetEvent('az-fw-money:openRegisterDialog')
AddEventHandler('az-fw-money:openRegisterDialog', function()
    local inputs = lib.inputDialog('Register Character', {
        {
            type        = 'input',
            label       = 'First Name',
            placeholder = 'John',
            required    = true,
            min         = 1,
            max         = 20,
            icon        = 'id-badge'
        },
        {
            type        = 'input',
            label       = 'Last Name',
            placeholder = 'Doe',
            required    = true,
            min         = 1,
            max         = 20,
            icon        = 'id-badge'
        },
    }, { allowCancel = false })

    if inputs and inputs[1] and inputs[2]
       and #inputs[1] > 0 and #inputs[2] > 0 then
        TriggerServerEvent('az-fw-money:registerCharacter', inputs[1], inputs[2])
    end
end)

-- 2.3) “List / Select Character” submenu
RegisterNetEvent(EVENT_SHOW_LIST)
AddEventHandler(EVENT_SHOW_LIST, function()
    lib.callback('az-fw-money:fetchCharacters', {}, function(rows)
        local opts = {}
        if not rows or #rows == 0 then
            table.insert(opts, { title = '❗ You have no characters yet', disabled = true })
        else
            for _, row in ipairs(rows) do
                table.insert(opts, {
                    title       = row.name,
                    description = 'ID: ' .. row.charid,
                    icon        = 'user',
                    onSelect    = function()
                        -- switch to this character immediately
                        TriggerServerEvent('az-fw-money:selectCharacter', row.charid)
                        SendNUIMessage({ action = "updateCash", cash = cash, bank = bank })
                    end
                })
            end
        end

        lib.registerContext({
            id       = CHAR_LIST,
            title    = '🔄 Your Characters',
            menu     = CHAR_MAIN,
            canClose = true,
            options  = opts
        })
        lib.showContext(CHAR_LIST)
    end)
end)

-- 2.4) Notifications & character switch refresh
RegisterNetEvent('az-fw-money:characterRegistered')
AddEventHandler('az-fw-money:characterRegistered', function(charid)
    lib.notify({ title='Character Registered', description='Your new char ID is ' .. charid, type='success', position='top' })
end)

RegisterNetEvent('az-fw-money:characterSelected')
AddEventHandler('az-fw-money:characterSelected', function(charid)
    lib.notify({ title='Character Selected', description='Now using char ID ' .. charid, type='info', position='top'  })
    -- refresh money HUD on character switch
    TriggerServerEvent('az-fw-money:requestMoney')
end)

-- 2.5) Open the menu with /char
RegisterCommand('char', function() lib.showContext(CHAR_MAIN) end, false)

local function fetchDiscordIDFromServer()
    local p = promise.new()
    RegisterNetEvent('Az-Framework:sendDiscordID', function(discordID) p:resolve(discordID) end)
    TriggerServerEvent('Az-Framework:requestDiscordID')
    return Citizen.Await(p)
end
exports('GetDiscordID', fetchDiscordIDFromServer)