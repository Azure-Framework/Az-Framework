local firstSpawn = true

AddEventHandler('playerSpawned', function()
    if firstSpawn then
        firstSpawn = false
        TriggerServerEvent('hud:requestDepartment')
    end
end)

RegisterNetEvent("updateCashHUD")
AddEventHandler("updateCashHUD", function(cash, bank)
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

-- Toggle HUD-move mode
RegisterCommand("movehud", function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "toggleMove" })
end, false)

RegisterNUICallback('closeUI', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

local CHAR_MAIN       = 'char_main_menu'
local CHAR_LIST       = 'char_list_menu'
local EVENT_SHOW_LIST = 'az-fw-money:openListMenu'


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

RegisterNetEvent('az-fw-money:openRegisterDialog')
AddEventHandler('az-fw-money:openRegisterDialog', function()
    local inputs = lib.inputDialog('Register Character', {
        { type = 'input', label = 'First Name',  placeholder = 'John',  required = true, min = 1, max = 20, icon = 'id-badge' },
        { type = 'input', label = 'Last Name',   placeholder = 'Doe',   required = true, min = 1, max = 20, icon = 'id-badge' },
    }, { allowCancel = false })

    if inputs and inputs[1] ~= '' and inputs[2] ~= '' then
        TriggerServerEvent('az-fw-money:registerCharacter', inputs[1], inputs[2])
    end
end)

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
                        TriggerServerEvent('az-fw-money:selectCharacter', row.charid)
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

RegisterNetEvent('az-fw-money:characterRegistered')
AddEventHandler('az-fw-money:characterRegistered', function(charid)
    lib.notify({
        title       = 'Character Registered',
        description = 'Your new char ID is ' .. charid,
        type        = 'success'
    })
    TriggerServerEvent('az-fw-money:requestMoney')
end)

RegisterNetEvent('az-fw-money:characterSelected')
AddEventHandler('az-fw-money:characterSelected', function(charid)
    lib.notify({
        title       = 'Character Selected',
        description = 'Now using char ID ' .. charid,
        type        = 'info'
    })
    TriggerServerEvent('az-fw-money:requestMoney')
end)

RegisterCommand('char', function()
    lib.showContext(CHAR_MAIN)
end, false)
