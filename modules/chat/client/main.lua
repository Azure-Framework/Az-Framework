local Config = (Config and Config.Chat) or {}
if Config.Enabled == false then return end

local chatOpen = false
local suggestions = {}
local isReady = false
local visibilityMode = 'always'
local controlLockThread = nil

local function jsonClone(tbl)
    return json.decode(json.encode(tbl or {}))
end

local function trim(str)
    return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function escapeHtml(value)
    value = tostring(value or '')
    value = value:gsub('&', '&amp;')
    value = value:gsub('<', '&lt;')
    value = value:gsub('>', '&gt;')
    value = value:gsub('"', '&quot;')
    value = value:gsub("'", '&#39;')
    return value
end

local function applyEmojiAliases(text)
    if type(text) ~= 'string' or text == '' then
        return ''
    end

    for alias, emoji in pairs(Config.EmojiAliases or {}) do
        text = text:gsub(alias, emoji)
    end

    return text
end

local function rgbToCss(color)
    if type(color) == 'table' then
        return ('rgb(%s,%s,%s)'):format(color[1] or 255, color[2] or 255, color[3] or 255)
    end

    if type(color) == 'string' and color ~= '' then
        return color
    end

    return Config.Style and Config.Style.accent or '#ffffff'
end

local function getLib()
    if type(lib) == 'table' and type(lib.inputDialog) == 'function' then
        return lib
    end
    local ok, exported = pcall(function()
        return exports['ox_lib']
    end)
    if ok and type(exported) == 'table' and type(exported.inputDialog) == 'function' then
        return exported
    end
    return nil
end

local function buildStreetLocation(coords)
    if type(coords) ~= 'vector3' and type(coords) ~= 'vector4' and type(coords) ~= 'table' then
        return 'Unknown location'
    end
    local x = coords.x or coords[1] or 0.0
    local y = coords.y or coords[2] or 0.0
    local z = coords.z or coords[3] or 0.0
    local streetHash, crossingHash = GetStreetNameAtCoord(x + 0.0, y + 0.0, z + 0.0)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash and crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or ''
    street = trim(street)
    crossing = trim(crossing)
    if street ~= '' and crossing ~= '' then
        return ('%s / %s'):format(street, crossing)
    end
    if street ~= '' then
        return street
    end
    return 'Unknown location'
end

local function open911Dialog()
    local ox = getLib()
    if not ox then
        TriggerEvent('az-chat:client:receiveMessage', {
            mode = 'SYSTEM',
            badge = 'SYSTEM',
            color = { 255, 103, 103 },
            author = '',
            text = '911 dialog unavailable because ox_lib is not loaded in Az-Framework/modules/chat.'
        })
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local location = buildStreetLocation(coords)
    local result = ox.inputDialog('911 Emergency Call', {
        {
            type = 'select',
            label = 'Department',
            required = true,
            default = 'police',
            options = {
                { value = 'police', label = 'Police' },
                { value = 'ems', label = 'EMS' },
                { value = 'fire', label = 'Fire' }
            }
        },
        {
            type = 'textarea',
            label = 'Description',
            description = 'What is happening right now?',
            required = true,
            min = 5,
            max = 500,
            placeholder = 'Describe the emergency, suspects, injuries, fire conditions, weapons, vehicles, or anything responders should know.'
        }
    })

    if not result then return end

    local department = trim(result[1] or ''):lower()
    local description = trim(result[2] or '')
    if department == '' or description == '' then return end

    TriggerServerEvent('az-chat:server:submit911', {
        department = department,
        message = description,
        location = location,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
    })
end

local legacyColorMap = {
    ['0'] = '#111111',
    ['1'] = '#3970e6',
    ['2'] = '#7CFC00',
    ['3'] = '#5bc0ff',
    ['4'] = '#42a5f5',
    ['5'] = '#4dd0e1',
    ['6'] = '#ce93d8',
    ['7'] = '#ffffff',
    ['8'] = '#3970e6',
    ['9'] = '#64b5f6'
}

local function legacyFormattedHtml(value, fallbackColor)
    value = tostring(value or ''):gsub('~n~', '\n')

    local state = {
        color = fallbackColor and rgbToCss(fallbackColor) or nil,
        bold = false,
        underline = false,
        italic = false
    }

    local parts = {}
    local buffer = ''

    local function flush()
        if buffer == '' then return end
        local styleParts = {}
        if state.color and state.color ~= '' then
            styleParts[#styleParts + 1] = 'color:' .. state.color
        end
        if state.bold then
            styleParts[#styleParts + 1] = 'font-weight:700'
        end
        if state.underline then
            styleParts[#styleParts + 1] = 'text-decoration:underline'
        end
        if state.italic then
            styleParts[#styleParts + 1] = 'font-style:italic'
        end

        local escaped = escapeHtml(buffer):gsub('\n', '<br>')
        if #styleParts > 0 then
            parts[#parts + 1] = ('<span style="%s;">%s</span>'):format(table.concat(styleParts, ';'), escaped)
        else
            parts[#parts + 1] = escaped
        end
        buffer = ''
    end

    local i = 1
    while i <= #value do
        local char = value:sub(i, i)
        local nextChar = value:sub(i + 1, i + 1)

        if char == '^' and nextChar ~= '' then
            local lower = nextChar:lower()
            if legacyColorMap[nextChar] then
                flush()
                state.color = legacyColorMap[nextChar]
                i = i + 2
            elseif lower == 'r' then
                flush()
                state.color = fallbackColor and rgbToCss(fallbackColor) or nil
                state.bold = false
                state.underline = false
                state.italic = false
                i = i + 2
            elseif nextChar == '*' then
                flush()
                state.bold = not state.bold
                i = i + 2
            elseif nextChar == '_' then
                flush()
                state.underline = not state.underline
                i = i + 2
            elseif nextChar == '~' then
                flush()
                state.italic = not state.italic
                i = i + 2
            else
                buffer = buffer .. char
                i = i + 1
            end
        else
            buffer = buffer .. char
            i = i + 1
        end
    end

    flush()
    return table.concat(parts)
end

local function normalizeVisibilityMode(mode)
    mode = tostring(mode or ''):lower()
    if mode == 'active' or mode == 'disabled' or mode == 'always' then
        return mode
    end
    return tostring(Config.DefaultVisibilityMode or 'always'):lower()
end

local function pushMessage(payload)
    if not isReady then
        CreateThread(function()
            while not isReady do Wait(50) end
            SendNUIMessage(payload)
        end)
        return
    end

    SendNUIMessage(payload)
end

local function updateVisibilityState()
    pushMessage({
        action = 'visibility',
        visibilityMode = visibilityMode,
        chatOpen = chatOpen
    })
end

local function buildDefaultHtml(author, text, color, badge, badgeIcon)
    local accent = rgbToCss(color)
    local badgeHtml = ''

    if badge and badge ~= '' then
        local iconHtml = ''
        if badgeIcon and badgeIcon ~= '' then
            iconHtml = ('<img class="message-badge-icon" src="%s" alt="">'):format(escapeHtml(badgeIcon))
        end

        badgeHtml = ('<span class="message-badge" style="color:%s;">%s<span>%s</span></span>')
            :format(accent, iconHtml, escapeHtml(badge))
    end

    local authorHtml = ''
    if author and author ~= '' then
        authorHtml = ('<span class="message-author">%s</span>')
            :format(legacyFormattedHtml(author, accent))
    end

    return ('<div class="message-row">%s%s<span class="message-text">%s</span></div>')
        :format(badgeHtml, authorHtml, legacyFormattedHtml(text or '', nil))
end

local function applyTemplate(template, args)
    local output = tostring(template or '')
    local safeArgs = {}

    for i = 1, #(args or {}) do
        safeArgs[i] = legacyFormattedHtml(applyEmojiAliases(args[i]), nil)
    end

    output = output:gsub('{(%d+)}', function(index)
        index = tonumber(index)
        if not index then return '' end
        return safeArgs[index + 1] or ''
    end)

    return output
end

local function syncSuggestions()
    pushMessage({
        action = 'suggestions',
        suggestions = suggestions
    })
end

local function normalizeMessage(msg)
    if type(msg) == 'string' then
        local defaultMode = Config.DefaultModeLabel or 'CHAT'
        local defaultIcon = ((Config.ModeIcons or {})[defaultMode] or (Config.ModeIcons or {})[string.lower(defaultMode or '')])
        return {
            html = buildDefaultHtml('', applyEmojiAliases(msg), nil, defaultMode, defaultIcon),
            mode = defaultMode
        }
    end

    local mode = msg.mode or msg.tag or msg.channel or msg.class or nil
    local badge = msg.badge or msg.roleLabel or msg.jobLabel or mode
    local badgeIcon = msg.badgeIcon or msg.roleIcon or msg.jobIcon or msg.icon
    if (not badgeIcon or badgeIcon == '') and mode then
        badgeIcon = (Config.ModeIcons or {})[mode] or (Config.ModeIcons or {})[string.lower(tostring(mode))]
    end

    if msg.html and msg.html ~= '' then
        return {
            html = tostring(msg.html),
            mode = mode
        }
    end

    if msg.template and msg.template ~= '' then
        return {
            html = applyTemplate(msg.template, msg.args or {}),
            mode = mode
        }
    end

    local author = msg.author or ''
    local text = msg.text or ''
    local color = msg.color

    if msg.args and #msg.args > 0 then
        if #msg.args == 1 then
            author = ''
            if msg.text == nil then
                text = tostring(msg.args[1] or '')
            end
        else
            author = msg.args[1] or author
            if msg.text == nil then
                local parts = {}
                for i = 2, #msg.args do
                    parts[#parts + 1] = tostring(msg.args[i])
                end
                text = table.concat(parts, ' ')
            end
        end
    end

    text = applyEmojiAliases(text)

    return {
        html = buildDefaultHtml(author, text, color, badge, badgeIcon),
        mode = mode
    }
end

local function setNativeTextChatEnabled(enabled)
    if Config.DisableNativeTextChat == false then return end
    pcall(function()
        SetTextChatEnabled(enabled == true)
    end)
end

local function suppressNativeTextChat()
    setNativeTextChatEnabled(false)
end

local function startControlLock()
    if controlLockThread then return end
    controlLockThread = CreateThread(function()
        while chatOpen do
            DisableAllControlActions(0)
            EnableControlAction(0, 200, true)
            EnableControlAction(0, 322, true)
            Wait(0)
        end
        controlLockThread = nil
    end)
end

local function openChat(prefill)
    if chatOpen or IsPauseMenuActive() then return end
    chatOpen = true
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('azChatOpen', true, false)
        LocalPlayer.state:set('azUiBusy', true, false)
    end
    suppressNativeTextChat()
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(true, true)
    startControlLock()
    pushMessage({
        action = 'open',
        prefill = prefill or '',
        suggestions = suggestions,
        emojiPicker = Config.EmojiPicker or {},
        visibilityMode = visibilityMode,
        chatOpen = true
    })
    updateVisibilityState()
end

local function closeChat()
    if not chatOpen then return end
    chatOpen = false
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('azChatOpen', false, false)
        LocalPlayer.state:set('azUiBusy', false, false)
    end
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(false, false)
    suppressNativeTextChat()
    pushMessage({ action = 'close' })
    updateVisibilityState()
end

local function nextVisibilityMode(mode)
    mode = normalizeVisibilityMode(mode)
    if mode == 'active' then
        return 'disabled'
    elseif mode == 'disabled' then
        return 'always'
    end
    return 'active'
end

local function setVisibilityMode(mode, notify)
    visibilityMode = normalizeVisibilityMode(mode)
    SetResourceKvp(Config.VisibilityModeKvp or 'azchat:visibilityMode', visibilityMode)
    updateVisibilityState()

    if notify ~= false then
        local label = visibilityMode == 'active' and 'Only while chat is open' or (visibilityMode == 'disabled' and 'Hidden unless you open input' or 'Always visible')
        TriggerEvent('az-chat:client:receiveMessage', {
            mode = 'SYSTEM',
            badge = 'SYSTEM',
            color = { 89, 217, 142 },
            author = '',
            text = ('Chat visibility set to %s. %s.'):format(visibilityMode, label)
        })
    end
end

local function cycleVisibilityMode(notify)
    setVisibilityMode(nextVisibilityMode(visibilityMode), notify)
end

RegisterCommand('azchat_open', function()
    openChat('')
end, false)

RegisterCommand('+azchat', function()
    openChat('')
end, false)

RegisterCommand('-azchat', function()
end, false)

RegisterCommand('chat', function()
    openChat('')
end, false)

RegisterCommand('+chat', function()
    openChat('')
end, false)

RegisterCommand('-chat', function()
end, false)

RegisterCommand('chatstate', function(_, args)
    local mode = normalizeVisibilityMode(args and args[1])
    setVisibilityMode(mode, true)
end, false)

RegisterCommand('chatdisplay', function(_, args)
    local mode = normalizeVisibilityMode(args and args[1])
    setVisibilityMode(mode, true)
end, false)

RegisterCommand('911', function()
    open911Dialog()
end, false)

TriggerEvent('chat:addSuggestion', '/911', 'Open the emergency call dialog and choose Police, EMS, or Fire.', {})

RegisterCommand('chatstatecycle', function()
    cycleVisibilityMode(true)
end, false)

RegisterCommand('+azchat_visibility_cycle', function()
    cycleVisibilityMode(true)
end, false)

RegisterCommand('-azchat_visibility_cycle', function()
end, false)

RegisterKeyMapping('+azchat', 'Open Az Chat', 'keyboard', tostring(Config.OpenKey or 't'))
RegisterKeyMapping('+azchat_visibility_cycle', 'Cycle Az Chat Visibility', 'keyboard', Config.VisibilityCycleKey or 'SEMICOLON')

RegisterNUICallback('azchat:ready', function(_, cb)
    isReady = true
    pushMessage({
        action = 'bootstrap',
        style = jsonClone(Config.Style),
        maxMessages = Config.MaxMessages,
        fadeAfterMs = Config.FadeAfterMs,
        inputHistoryMax = Config.InputHistoryMax or 50,
        emojiPicker = Config.EmojiPicker or {},
        suggestions = suggestions,
        visibilityMode = visibilityMode,
        chatOpen = chatOpen
    })
    cb({ ok = true })
end)

RegisterNUICallback('azchat:close', function(_, cb)
    closeChat()
    cb({ ok = true })
end)

RegisterNUICallback('azchat:submit', function(data, cb)
    local text = trim(tostring((data or {}).text or ''))
    closeChat()

    if text == '' then
        cb({ ok = true })
        return
    end

    text = applyEmojiAliases(text)

    if text:sub(1, 1) == (Config.CommandPrefix or '/') then
        local commandText = trim(text:sub(2))
        if commandText ~= '' then
            local ok, err = pcall(function()
                ExecuteCommand(commandText)
            end)
            if not ok then
                TriggerEvent('az-chat:client:receiveMessage', {
                    mode = 'SYSTEM',
                    badge = 'SYSTEM',
                    color = { 255, 103, 103 },
                    author = '',
                    text = ('Failed to run command: %s'):format(tostring(err or 'unknown error'))
                })
            end
        end
    else
        TriggerServerEvent('az-chat:server:submit', {
            text = text
        })
    end

    cb({ ok = true })
end)

RegisterNetEvent('az-chat:client:receiveMessage', function(message)
    local normalized = normalizeMessage(message)
    pushMessage({
        action = 'message',
        message = normalized
    })
end)

RegisterNetEvent('az-chat:client:clear', function(keepLast)
    pushMessage({
        action = 'clear',
        keepLast = tonumber(keepLast) or 0
    })
end)

AddEventHandler('chat:addMessage', function(message)
    local normalized = normalizeMessage(message)
    pushMessage({
        action = 'message',
        message = normalized
    })
end)

AddEventHandler('chat:addSuggestion', function(name, help, params)
    suggestions[name] = {
        name = name,
        help = help,
        params = params or {}
    }
    syncSuggestions()
end)

AddEventHandler('chat:addSuggestions', function(items)
    for _, item in ipairs(items or {}) do
        if item.name then
            suggestions[item.name] = {
                name = item.name,
                help = item.help,
                params = item.params or {}
            }
        end
    end
    syncSuggestions()
end)

AddEventHandler('chat:removeSuggestion', function(name)
    suggestions[name] = nil
    syncSuggestions()
end)

exports('addMessage', function(message)
    local normalized = normalizeMessage(message)
    pushMessage({
        action = 'message',
        message = normalized
    })
end)

CreateThread(function()
    visibilityMode = normalizeVisibilityMode(GetResourceKvpString(Config.VisibilityModeKvp or 'azchat:visibilityMode'))

    if Config.WarnIfStockChatRunning and GetResourceState('chat') == 'started' then
        print('^3[Az-Chat]^7 Stock resource ^1chat^7 is still running. Stop or remove it in server.cfg so Az-Chat is the only active chat UI.')
    end

    suppressNativeTextChat()

    Wait(500)
    TriggerEvent('chat:addSuggestions', Config.BuiltInSuggestions or {})
    TriggerServerEvent('az-chat:init')
    updateVisibilityState()
end)

CreateThread(function()
    while true do
        if Config.UseOpenControlFallback == true and not chatOpen and not IsPauseMenuActive() then
            Wait(0)
            local control = tonumber(Config.OpenControl) or 245
            if IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control) or IsControlJustReleased(0, control) or IsDisabledControlJustReleased(0, control) then
                openChat('')
                Wait(150)
            end
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(chatOpen and 10000 or 2000)
        if not chatOpen then
            suppressNativeTextChat()
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if Config.DisableNativeTextChat == false then return end
    setNativeTextChatEnabled(true)
end)
