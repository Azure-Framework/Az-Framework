local Config = (Config and Config.Chat) or {}
if Config.Enabled == false then return end

local mutedPlayers = {}

local function trim(str)
    return (tostring(str or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function now()
    return os.time()
end

local function isAdmin(src)
    if src == 0 then return true end

    local ok, result = pcall(function()
        return exports['Az-Framework']:isAdmin(src)
    end)

    if ok then
        return result == true
    end

    return false
end

local function normalizeKey(value)
    value = trim(value):lower()
    return value
end

local function titleCaseWords(value)
    local out = tostring(value or ''):gsub('[%s_%-]+', ' ')
    out = out:gsub('(%a)([%w_]*)', function(a, b)
        return a:upper() .. b:lower()
    end)
    return out
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

local function nl2br(value)
    return escapeHtml(value):gsub('\n', '<br>')
end

local function rgbToCss(color)
    if type(color) == 'table' then
        return ('rgb(%s,%s,%s)'):format(color[1] or 255, color[2] or 255, color[3] or 255)
    end
    if type(color) == 'string' and color ~= '' then
        return color
    end
    return '#ffffff'
end

local function getPlayerCharacterName(src)
    if src == 0 then
        return 'Console'
    end

    local ok, name = pcall(function()
        return exports['Az-Framework']:GetPlayerCharacterNameSync(src)
    end)

    if ok and type(name) == 'string' and name ~= '' then
        return name
    end

    local fallback = GetPlayerName(src)
    if fallback and fallback ~= '' then
        return fallback
    end

    return ('Player %s'):format(src)
end

local function getPlayerJobName(src)
    if src == 0 then
        return 'admin'
    end

    local ok, job = pcall(function()
        return exports['Az-Framework']:getPlayerJob(src)
    end)

    if ok and type(job) == 'string' and job ~= '' then
        return job
    end

    local player = Player(src)
    local state = player and player.state or nil
    if state then
        local direct = state.jobName or state.job_name or state.jobname
        if type(direct) == 'string' and direct ~= '' then
            return direct
        end

        local nested = state.job
        if type(nested) == 'table' then
            if type(nested.name) == 'string' and nested.name ~= '' then
                return nested.name
            end
            if type(nested.job) == 'string' and nested.job ~= '' then
                return nested.job
            end
        elseif type(nested) == 'string' and nested ~= '' then
            return nested
        end
    end

    return 'civ'
end

local function getRoleBadge(src)
    local rawJob = getPlayerJobName(src)
    local key = normalizeKey(rawJob)
    local icon = (Config.JobRoleIcons or {})[key] or (Config.JobRoleIcons or {}).default
    local label = (Config.JobRoleLabels or {})[key]

    if not label or label == '' then
        local pretty = titleCaseWords(rawJob)
        if pretty == '' then
            pretty = 'CIV'
        end
        label = pretty:upper()
    end

    return label, icon, rawJob
end

local function getPlayerLabel(src)
    if src == 0 then
        return 'Console'
    end
    return getPlayerCharacterName(src)
end

local function sendTo(target, message)
    TriggerClientEvent('az-chat:client:receiveMessage', target, message)
end

local function sendSystem(target, text, level, color)
    sendTo(target, {
        mode = level or 'SYSTEM',
        badge = level or 'SYSTEM',
        badgeIcon = (Config.ModeIcons or {})[level or 'SYSTEM'] or (Config.ModeIcons or {}).SYSTEM,
        color = color or { 230, 57, 70 },
        author = '',
        text = text
    })
end

local function refreshCommandSuggestions(target)
    if not GetRegisteredCommands or not target or target <= 0 then return end

    local suggestions = {}
    for _, command in ipairs(GetRegisteredCommands() or {}) do
        local name = tostring(command.name or '')
        if name ~= '' and IsPlayerAceAllowed(target, ('command.%s'):format(name)) then
            suggestions[#suggestions + 1] = {
                name = '/' .. name,
                help = ''
            }
        end
    end

    TriggerClientEvent('chat:addSuggestions', target, suggestions)
end

local function addMute(target, minutes, reason)
    if minutes == 0 then
        mutedPlayers[target] = {
            untilTime = false,
            reason = reason,
        }
        return
    end

    mutedPlayers[target] = {
        untilTime = now() + math.max(1, minutes) * 60,
        reason = reason,
    }
end

local function clearMute(target)
    mutedPlayers[target] = nil
end

local function getMuteState(src)
    local state = mutedPlayers[src]
    if not state then return false, nil end

    if state.untilTime and state.untilTime <= now() then
        mutedPlayers[src] = nil
        return false, nil
    end

    return true, state
end

local function broadcastAdmin(author, text)
    TriggerClientEvent('az-chat:client:receiveMessage', -1, {
        mode = 'ADMIN',
        badge = 'ADMIN',
        badgeIcon = (Config.ModeIcons or {}).ADMIN,
        color = { 255, 180, 84 },
        author = author,
        text = text
    })
end

local function getSourceCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if not coords then return nil end
    return coords
end

local function makePlayerChatPayload(src, text, channel)
    local badge, badgeIcon = getRoleBadge(src)
    return {
        mode = channel or Config.DefaultModeLabel or 'CHAT',
        badge = badge,
        badgeIcon = badgeIcon,
        color = { 230, 57, 70 },
        author = getPlayerLabel(src),
        text = text
    }
end

local function getRpColor(key, fallback)
    local colors = Config.RP and Config.RP.Colors or {}
    if key == 'do' then
        return colors.do_ or fallback
    end
    return colors[key] or fallback
end

local function buildBadgeHtml(label, icon, accentColor)
    local iconHtml = ''
    if icon and icon ~= '' then
        iconHtml = ('<img class="message-badge-icon" src="%s" alt="">'):format(escapeHtml(icon))
    end

    return ('<span class="message-badge" style="color:%s;">%s<span>%s</span></span>')
        :format(rgbToCss(accentColor), iconHtml, escapeHtml(label or 'CHAT'))
end

local function buildRpHtml(src, rpType, text, opts)
    opts = opts or {}
    local badge, badgeIcon = getRoleBadge(src)
    local author = getPlayerLabel(src)
    local accentColor = opts.accentColor or { 230, 57, 70 }
    local toneColor = opts.toneColor or accentColor
    local badgeHtml = buildBadgeHtml(badge, badgeIcon, accentColor)
    local modeLabel = tostring(rpType or 'RP'):upper()
    local suffix = opts.suffix or ''
    local bodyClass = opts.bodyClass or ('rp-' .. tostring(rpType or 'rp'):lower())

    return ([[<div class="message-row rp-row %s">%s<span class="message-author" style="color:%s;">%s</span><span class="rp-chip %s">%s</span><span class="message-text rp-body %s" style="color:%s;">%s%s</span></div>]])
        :format(
            escapeHtml(bodyClass),
            badgeHtml,
            rgbToCss(accentColor),
            escapeHtml(author),
            escapeHtml(bodyClass),
            escapeHtml(modeLabel),
            escapeHtml(bodyClass),
            rgbToCss(toneColor),
            nl2br(text or ''),
            suffix
        )
end

local function sendPayloadToNearby(src, payload, range)
    local origin = getSourceCoords(src)
    if not origin then
        sendTo(src, payload)
        return
    end

    local radius = tonumber(range or Config.ProximityRange or 24.0) or 24.0
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local targetCoords = getSourceCoords(target)
        if targetCoords then
            local dist = #(origin - targetCoords)
            if dist <= radius then
                sendTo(target, payload)
            end
        end
    end
end

local function sendRpPayload(src, rpType, text, opts)
    opts = opts or {}
    local payload = {
        mode = tostring(rpType or 'RP'):upper(),
        html = buildRpHtml(src, rpType, text, opts),
    }

    if opts.global == true then
        TriggerClientEvent('az-chat:client:receiveMessage', -1, payload)
    else
        sendPayloadToNearby(src, payload, opts.range)
    end
end

local function parseLeadingNumber(args)
    local first = args and args[1]
    local number = tonumber(first)
    if number then
        table.remove(args, 1)
        return math.floor(number)
    end
    return nil
end

local function isMutedWithFeedback(src)
    local muted, state = getMuteState(src)
    if not muted then
        return false
    end

    if state.untilTime then
        local secondsLeft = math.max(0, state.untilTime - now())
        local minutesLeft = math.max(1, math.ceil(secondsLeft / 60))
        sendSystem(src, ('You are muted from chat for about %s more minute(s). %s'):format(minutesLeft, state.reason and ('Reason: ' .. state.reason) or ''), 'MUTED', { 255, 103, 103 })
    else
        sendSystem(src, ('You are muted from chat. %s'):format(state.reason and ('Reason: ' .. state.reason) or ''), 'MUTED', { 255, 103, 103 })
    end

    return true
end

local function sendChatMessage(src, text)
    if Config.UseProximity then
        local origin = getSourceCoords(src)
        if origin then
            local range = tonumber(Config.ProximityRange or 24.0) or 24.0
            local payload = makePlayerChatPayload(src, text, 'LOCAL')
            for _, playerId in ipairs(GetPlayers()) do
                local target = tonumber(playerId)
                local targetCoords = getSourceCoords(target)
                if targetCoords then
                    local dist = #(origin - targetCoords)
                    if dist <= range then
                        sendTo(target, payload)
                    end
                end
            end
            return
        end
    end

    TriggerClientEvent('az-chat:client:receiveMessage', -1, makePlayerChatPayload(src, text, Config.DefaultModeLabel or 'CHAT'))
end

RegisterNetEvent('az-chat:server:submit', function(payload)
    local src = source
    if src <= 0 then return end

    local text = trim(type(payload) == 'table' and payload.text or '')
    if text == '' then return end

    if isMutedWithFeedback(src) then
        return
    end

    sendChatMessage(src, text)
end)

RegisterCommand('mute', function(src, args)
    if not isAdmin(src) then
        sendSystem(src, 'You do not have permission to use /mute.', 'DENIED', { 255, 103, 103 })
        return
    end

    local target = tonumber(args[1])
    local minutes = tonumber(args[2]) or 10
    local reason = trim(table.concat(args, ' ', 3))

    if not target or not GetPlayerName(target) then
        sendSystem(src, 'Usage: /mute <id> <minutes> [reason]', 'USAGE', { 255, 180, 84 })
        return
    end

    addMute(target, math.max(0, minutes), reason ~= '' and reason or nil)

    local targetName = getPlayerLabel(target)
    local durationText = minutes == 0 and 'permanently' or ('for %s minute(s)'):format(minutes)
    sendSystem(src, ('Muted %s %s.'):format(targetName, durationText), 'SUCCESS', { 89, 217, 142 })
    sendSystem(target, ('You were muted %s by %s. %s'):format(durationText, src == 0 and 'Console' or getPlayerLabel(src), reason ~= '' and ('Reason: ' .. reason) or ''), 'MUTED', { 255, 103, 103 })
end, false)

RegisterCommand('unmute', function(src, args)
    if not isAdmin(src) then
        sendSystem(src, 'You do not have permission to use /unmute.', 'DENIED', { 255, 103, 103 })
        return
    end

    local target = tonumber(args[1])
    if not target then
        sendSystem(src, 'Usage: /unmute <id>', 'USAGE', { 255, 180, 84 })
        return
    end

    clearMute(target)
    sendSystem(src, ('Removed chat mute for %s.'):format(getPlayerLabel(target)), 'SUCCESS', { 89, 217, 142 })
    if GetPlayerName(target) then
        sendSystem(target, ('Your chat mute was removed by %s.'):format(src == 0 and 'Console' or getPlayerLabel(src)), 'SUCCESS', { 89, 217, 142 })
    end
end, false)

RegisterCommand('purge', function(src, args)
    if not isAdmin(src) then
        sendSystem(src, 'You do not have permission to use /purge.', 'DENIED', { 255, 103, 103 })
        return
    end

    local keepLast = tonumber(args[1]) or 0
    TriggerClientEvent('az-chat:client:clear', -1, keepLast)

    local actor = src == 0 and 'Console' or getPlayerLabel(src)
    broadcastAdmin(actor, keepLast > 0 and ('trimmed chat to the last %s messages.'):format(keepLast) or 'cleared the chat for everyone.')
end, false)

RegisterCommand('dm', function(src, args)
    if not isAdmin(src) then
        sendSystem(src, 'You do not have permission to use /dm.', 'DENIED', { 255, 103, 103 })
        return
    end

    local target = tonumber(args[1])
    local message = trim(table.concat(args, ' ', 2))

    if not target or message == '' or not GetPlayerName(target) then
        sendSystem(src, 'Usage: /dm <id> <message>', 'USAGE', { 255, 180, 84 })
        return
    end

    local sender = src == 0 and 'Console' or getPlayerLabel(src)
    local targetName = getPlayerLabel(target)
    local inboundAuthor = ('Staff DM%s'):format(Config.ShowPlayerIdInAdminDM and (' [' .. sender .. ']') or '')
    local outboundAuthor = ('DM -> %s%s'):format(targetName, Config.ShowPlayerIdInAdminDM and (' [' .. target .. ']') or '')

    sendTo(target, {
        mode = 'DM',
        badge = 'DM',
        badgeIcon = (Config.ModeIcons or {}).DM,
        color = { 116, 185, 255 },
        author = inboundAuthor,
        text = message
    })

    if src ~= 0 then
        sendTo(src, {
            mode = 'DM',
            badge = 'DM',
            badgeIcon = (Config.ModeIcons or {}).DM,
            color = { 116, 185, 255 },
            author = outboundAuthor,
            text = message
        })
    end
end, false)

RegisterCommand('announce', function(src, args)
    if not isAdmin(src) then
        sendSystem(src, 'You do not have permission to use /announce.', 'DENIED', { 255, 103, 103 })
        return
    end

    local message = trim(table.concat(args, ' '))
    if message == '' then
        sendSystem(src, 'Usage: /announce <message>', 'USAGE', { 255, 180, 84 })
        return
    end

    local actor = src == 0 and 'Console' or getPlayerLabel(src)
    TriggerClientEvent('az-chat:client:receiveMessage', -1, {
        mode = 'ANNOUNCEMENT',
        badge = 'ANNOUNCEMENT',
        badgeIcon = (Config.ModeIcons or {}).ANNOUNCEMENT,
        color = { 255, 180, 84 },
        author = actor,
        text = message
    })
end, false)

RegisterCommand('me', function(src, args)
    if src <= 0 then return end
    if isMutedWithFeedback(src) then return end

    local text = trim(table.concat(args or {}, ' '))
    if text == '' then
        sendSystem(src, 'Usage: /me <action>', 'USAGE', { 255, 180, 84 })
        return
    end

    sendRpPayload(src, 'ME', text, {
        range = Config.RP and Config.RP.MeRange or 20.0,
        accentColor = getRpColor('me', { 230, 57, 70 }),
        toneColor = getRpColor('me', { 230, 57, 70 }),
        bodyClass = 'rp-me'
    })
end, false)

RegisterCommand('do', function(src, args)
    if src <= 0 then return end
    if isMutedWithFeedback(src) then return end

    local text = trim(table.concat(args or {}, ' '))
    if text == '' then
        sendSystem(src, 'Usage: /do <description>', 'USAGE', { 255, 180, 84 })
        return
    end

    local suffix = (' <span class="rp-tail">(%s)</span>'):format(escapeHtml(getPlayerLabel(src)))
    sendRpPayload(src, 'DO', text, {
        range = Config.RP and Config.RP.DoRange or 20.0,
        accentColor = getRpColor('do', { 116, 185, 255 }),
        toneColor = getRpColor('do', { 116, 185, 255 }),
        bodyClass = 'rp-do',
        suffix = suffix
    })
end, false)

RegisterCommand('ooc', function(src, args)
    if src <= 0 then return end
    if isMutedWithFeedback(src) then return end

    local text = trim(table.concat(args or {}, ' '))
    if text == '' then
        sendSystem(src, 'Usage: /ooc <message>', 'USAGE', { 255, 180, 84 })
        return
    end

    sendRpPayload(src, 'OOC', ('(( %s ))'):format(text), {
        range = Config.RP and Config.RP.OocRange or 24.0,
        global = Config.RP and Config.RP.OocGlobal == true or false,
        accentColor = getRpColor('ooc', { 255, 255, 255 }),
        toneColor = 'rgba(255,255,255,0.82)',
        bodyClass = 'rp-ooc'
    })
end, false)

if Config.RP and Config.RP.AllowLoocCommand ~= false then
    RegisterCommand('looc', function(src, args)
        if src <= 0 then return end
        if isMutedWithFeedback(src) then return end

        local text = trim(table.concat(args or {}, ' '))
        if text == '' then
            sendSystem(src, 'Usage: /looc <message>', 'USAGE', { 255, 180, 84 })
            return
        end

        sendRpPayload(src, 'OOC', ('(( %s ))'):format(text), {
            range = Config.RP and Config.RP.OocRange or 24.0,
            global = false,
            accentColor = getRpColor('ooc', { 255, 255, 255 }),
            toneColor = 'rgba(255,255,255,0.82)',
            bodyClass = 'rp-ooc'
        })
    end, false)
end

if Config.RP and Config.RP.AllowBCommand ~= false then
    RegisterCommand('b', function(src, args)
        if src <= 0 then return end
        if isMutedWithFeedback(src) then return end

        local text = trim(table.concat(args or {}, ' '))
        if text == '' then
            sendSystem(src, 'Usage: /b <message>', 'USAGE', { 255, 180, 84 })
            return
        end

        sendRpPayload(src, 'OOC', ('(( %s ))'):format(text), {
            range = Config.RP and Config.RP.OocRange or 24.0,
            global = false,
            accentColor = getRpColor('ooc', { 255, 255, 255 }),
            toneColor = 'rgba(255,255,255,0.82)',
            bodyClass = 'rp-ooc'
        })
    end, false)
end

RegisterCommand('try', function(src, args)
    if src <= 0 then return end
    if isMutedWithFeedback(src) then return end

    local text = trim(table.concat(args or {}, ' '))
    if text == '' then
        sendSystem(src, 'Usage: /try <action>', 'USAGE', { 255, 180, 84 })
        return
    end

    local success = math.random(0, 1) == 1
    local outcome = success and 'SUCCESS' or 'FAIL'
    local tone = success and getRpColor('trySuccess', { 89, 217, 142 }) or getRpColor('tryFail', { 255, 103, 103 })
    local suffix = (' <span class="rp-result rp-%s">[%s]</span>'):format(success and 'success' or 'fail', outcome)

    sendRpPayload(src, 'TRY', text, {
        range = Config.RP and Config.RP.TryRange or 20.0,
        accentColor = tone,
        toneColor = tone,
        bodyClass = success and 'rp-try-success' or 'rp-try-fail',
        suffix = suffix
    })
end, false)

RegisterCommand('roll', function(src, args)
    if src <= 0 then return end
    if isMutedWithFeedback(src) then return end

    local parts = {}
    for i = 1, #(args or {}) do
        parts[i] = args[i]
    end

    local max = parseLeadingNumber(parts) or 100
    max = math.min(math.max(2, max), 10000)

    local reason = trim(table.concat(parts, ' '))
    local rolled = math.random(1, max)
    local text = ('rolled %s/%s'):format(rolled, max)
    if reason ~= '' then
        text = ('%s for %s'):format(text, reason)
    end

    local suffix = (' <span class="rp-result rp-roll">[%s/%s]</span>'):format(rolled, max)
    sendRpPayload(src, 'ROLL', text, {
        range = Config.RP and Config.RP.RollRange or 20.0,
        accentColor = getRpColor('roll', { 255, 180, 84 }),
        toneColor = getRpColor('roll', { 255, 180, 84 }),
        bodyClass = 'rp-roll',
        suffix = suffix
    })
end, false)

AddEventHandler('playerDropped', function()
    clearMute(tonumber(source) or source)
end)

local function getNearestMdtResourceName()
    for _, name in ipairs({ 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' }) do
        if name and name ~= '' then
            local state = GetResourceState(name)
            if state == 'started' or state == 'starting' then
                return name
            end
        end
    end
    return nil
end

RegisterNetEvent('az-chat:server:submit911', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}

    local department = normalizeKey(payload.department or payload.service or 'police')
    if department ~= 'police' and department ~= 'ems' and department ~= 'fire' then
        department = 'police'
    end

    local message = trim(payload.message or payload.details or '')
    local location = trim(payload.location or '')
    local coords = type(payload.coords) == 'table' and payload.coords or {}

    if message == '' then
        sendSystemTo(src, 'Please enter call details before sending 911.', 'DENIED', { 255, 103, 103 })
        return
    end

    local mdtResource = getNearestMdtResourceName()
    if not mdtResource then
        sendSystemTo(src, 'Az-MDT is not running, so the 911 call could not be delivered.', 'DENIED', { 57, 112, 230 })
        return
    end

    local callerName = getPlayerCharacterName(src)
    local displayDepartment = titleCaseWords(department)
    local callId = nil
    local ok, result = pcall(function()
        return exports[mdtResource]:CreateExternalCall({
            department = department,
            service = department,
            caller = callerName,
            callerName = callerName,
            title = displayDepartment .. ' 911 Call',
            message = message,
            details = message,
            description = message,
            location = location ~= '' and location or 'Unknown location',
            coords = coords,
            sourceResource = 'Az-Framework/911',
            externalSource = 'Az-Framework/911',
            quickRespond = true,
            status = 'PENDING'
        })
    end)

    if ok and result then
        if type(result) == 'table' then
            callId = tonumber(result.id or result.callId or result.call_id)
        elseif tonumber(result) then
            callId = tonumber(result)
        end
    end

    if not ok or not result then
        sendSystemTo(src, 'The 911 call failed to create in MDT.', 'DENIED', { 255, 103, 103 })
        print(('[Az-Chat] submit911 failed for %s: %s'):format(tostring(src), tostring(result)))
        return
    end

    sendSystemTo(src, ('911 sent to %s%s.'):format(displayDepartment, callId and (' as call #' .. tostring(callId)) or ''), 'SUCCESS', { 89, 217, 142 })
end)

RegisterNetEvent('az-chat:init')
AddEventHandler('az-chat:init', function()
    local src = source
    if src and src > 0 then
        refreshCommandSuggestions(src)
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    if src and src > 0 then
        SetTimeout(1500, function()
            refreshCommandSuggestions(src)
        end)
    end
end)

AddEventHandler('onServerResourceStart', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    SetTimeout(500, function()
        for _, playerId in ipairs(GetPlayers()) do
            refreshCommandSuggestions(tonumber(playerId))
        end
    end)
end)
