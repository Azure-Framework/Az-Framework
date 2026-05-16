local RESOURCE_NAME = GetCurrentResourceName()

local Config = (Config and Config.IDCard) or {}
if Config.Enabled == false then return end

local DMV_LOCATIONS = {}

if Config.DMVLocations and #Config.DMVLocations > 0 then
    for _, loc in ipairs(Config.DMVLocations) do
        if loc.coords then
            DMV_LOCATIONS[#DMV_LOCATIONS + 1] = loc
        end
    end
end

if #DMV_LOCATIONS == 0 then
    DMV_LOCATIONS[1] = {
        coords = Config.DMVLocation or vector3(-268.1573, -955.4126, 31.2231),
        blip   = Config.DMVBlip or {}
    }
end

local idOpen           = false
local requestPopupOpen = false
local displayToken     = 0

local dlGate = {
    has     = false,
    status  = "UNKNOWN",
    lastReq = 0,
    pending = false
}

RegisterNetEvent("az-id:driverLicenseStatus", function(has, status)
    dlGate.has     = has and true or false
    dlGate.status  = status or "UNKNOWN"
    dlGate.lastReq = GetGameTimer()
    dlGate.pending = false
end)

local function requestDriverLicenseStatus()
    if dlGate.pending then return end
    dlGate.pending = true
    TriggerServerEvent("az-id:checkDriverLicense")
end

local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(("^3[%s C]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local function closeIdCard()
    dprint("closeIdCard: closing ID")
    idOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "hideId",
        type   = "closeID"
    })
end

local function closeRequestPopup()
    dprint("closeRequestPopup: closing request modal")
    requestPopupOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "hideRequest",
        type   = "closeRequest"
    })
end

local function openIdCard(data)
    idOpen       = true
    displayToken = (displayToken + 1) % 1000000
    local myTok  = displayToken

    dprint("openIdCard: opening with new token", myTok)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "showId",
        type   = "openID",
        data   = data
    })

    local displayTime = Config.DisplayTime or 7000
    if displayTime > 0 then
        CreateThread(function()
            Wait(displayTime)
            if idOpen and myTok == displayToken then
                dprint("openIdCard: auto-closing after", displayTime, "ms (token still", myTok, ")")
                closeIdCard()
            else
                dprint("openIdCard: skip auto-close, idOpen=", idOpen, "myTok=", myTok, "currentTok=", displayToken)
            end
        end)
    else
        dprint("openIdCard: DisplayTime <= 0, no auto-close")
    end
end

local function openRequestPopup(requesterServerId)
    dprint("openRequestPopup: requester", requesterServerId)
    requestPopupOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action    = "showRequest",
        type      = "askForID",
        requester = requesterServerId
    })
end

RegisterNetEvent("az-id:displayId", function(data)
    print("[Az-Id C] displayId event received")

    if type(data) ~= "table" then
        dprint("az-id:displayId: payload is not a table:", type(data))
    else
        local keys = {}
        for k in pairs(data) do
            keys[#keys+1] = k
        end
        table.sort(keys)
        dprint("az-id:displayId: payload keys=" .. table.concat(keys, ", "))
    end

    openIdCard(data)
end)

RegisterNetEvent("az-id:promptShowId", function(requesterServerId)
    dprint("az-id:promptShowId from", requesterServerId)
    openRequestPopup(requesterServerId)
end)

RegisterNetEvent("az-id:notify", function(msg)
    dprint("az-id:notify:", msg)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentString(msg)
    EndTextCommandThefeedPostTicker(false, true)
end)

RegisterNUICallback("idClose", function(_, cb)
    dprint("NUI cb: close")
    closeIdCard()
    closeRequestPopup()
    cb("ok")
end)

RegisterNUICallback("respondRequest", function(data, cb)
    dprint("NUI cb: respondRequest requester=", data and data.requester, "accepted=", data and data.accepted)
    closeRequestPopup()
    TriggerServerEvent("az-id:respondRequest", data.requester, data.accepted)
    cb("ok")
end)

local function getClosestPlayer(radius)
    local players       = GetActivePlayers()
    local closestDist   = radius or 3.0
    local closestPlayer = nil
    local myPed         = PlayerPedId()
    local myCoords      = GetEntityCoords(myPed)

    for _, ply in ipairs(players) do
        local ped = GetPlayerPed(ply)
        if ped ~= myPed then
            local coords = GetEntityCoords(ped)
            local dist   = #(coords - myCoords)
            if dist < closestDist then
                closestDist   = dist
                closestPlayer = ply
            end
        end
    end

    return closestPlayer, closestDist
end

RegisterCommand("ask4id", function()
    dprint("Client /ask4id")
    local target, dist = getClosestPlayer(Config.RequestDistance or 3.0)
    if not target then
        dprint("ask4id: no one nearby")
        TriggerEvent("chat:addMessage", {
            color     = { 255, 0, 0 },
            multiline = false,
            args      = { "ID", "No one nearby to ask." }
        })
        return
    end

    local serverId = GetPlayerServerId(target)
    dprint("ask4id: asking serverId", serverId, "dist", dist)
    TriggerServerEvent("az-id:requestId", serverId)
end, false)

RegisterCommand("showid", function()
    dprint("Client /showid - sending az-id:showMyIdRadius")
    TriggerServerEvent("az-id:showMyIdRadius")
end, false)

RegisterCommand("testidui", function()
    dprint("Opening test ID UI locally")
    openIdCard({
        dl        = "TEST1234",
        exp       = "01/01/2030",
        class     = "C",
        ["end"]   = "NONE",
        ln        = "PHILIPS",
        fn        = "TREVOR",
        addr1     = "186 ZANCUDO AVENUE,",
        addr2     = "SANDY SHORES, BLAINE COUNTY, SA 47229",
        dob       = "08/06/1969",
        sex       = "M",
        hgt       = "6'-01\"",
        wgt       = "206 lb",
        hair      = "BRN",
        eyes      = "BRN",
        rst       = "NONE",
        dd        = "0103/019699903/0608/69",
        iss       = "09/17/2013",
        idnum     = "080669",
        signature = "Trevor Philips"
    })
end, false)

CreateThread(function()
    for i, loc in ipairs(DMV_LOCATIONS) do
        local blipCfg = (loc.blip or Config.DMVBlip or {})
        if blipCfg.enabled ~= false then
            local coords = loc.coords
            local blip   = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, blipCfg.sprite or 498)
            SetBlipColour(blip, blipCfg.color or 3)
            SetBlipScale(blip, blipCfg.scale or 0.9)
            SetBlipAsShortRange(blip, true)

            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(blipCfg.text or ("DMV #" .. i))
            EndTextCommandSetBlipName(blip)

            dprint(("BLIP: DMV #%s at (%.2f, %.2f, %.2f) sprite=%s color=%s scale=%.2f"):format(
                i, coords.x, coords.y, coords.z,
                blipCfg.sprite or 498,
                blipCfg.color or 3,
                blipCfg.scale or 0.9
            ))
        else
            dprint("BLIP: DMV #" .. i .. " disabled via config")
        end
    end
end)

local function getNearestDMV(coords)
    local closestDist, closestLoc = nil, nil
    for _, loc in ipairs(DMV_LOCATIONS) do
        local dist = #(coords - loc.coords)
        if not closestDist or dist < closestDist then
            closestDist = dist
            closestLoc  = loc
        end
    end
    return closestLoc, closestDist or 9999.0
end

CreateThread(function()
    local markerCfg    = Config.Marker or {}
    local textCfg      = Config.MarkerText or {}
    local drawDistance = markerCfg.drawDistance or 15.0
    local interactDist = markerCfg.interactDistance or 2.0

    local cacheMs = tonumber(Config.DriverLicenseCacheMs) or 10000

    while true do
        local wait    = 1000
        local ped     = PlayerPedId()
        local pCoords = GetEntityCoords(ped)

        local loc, dist = getNearestDMV(pCoords)
        if loc and dist < drawDistance then

            local now = GetGameTimer()
            if dlGate.lastReq == 0 or (now - dlGate.lastReq) > cacheMs then
                requestDriverLicenseStatus()
            end

            if not dlGate.has then
                wait = 250
            else
                wait = 0

                local locMarker = loc.marker or markerCfg
                local locText   = loc.text   or textCfg

                local coords = loc.coords
                local mType  = locMarker.type or 1
                local size   = locMarker.size or { x = 1.2, y = 1.2, z = 0.5 }
                local col    = locMarker.color or { r = 255, g = 255, b = 0, a = 120 }
                local zOff   = locMarker.zOffset or 1.0

                DrawMarker(
                    mType,
                    coords.x, coords.y, coords.z - zOff,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    size.x, size.y, size.z,
                    col.r, col.g, col.b, col.a,
                    locMarker.bobUpAndDown or false,
                    locMarker.faceCamera ~= false,
                    2,
                    locMarker.rotate or false,
                    nil, nil, false
                )

                if dist < interactDist then
                    local font = locText.font or 4
                    local sx   = locText.scaleX or locText.scale or 0.35
                    local sy   = locText.scaleY or locText.scale or 0.35
                    local cr   = locText.colorR or 255
                    local cg   = locText.colorG or 255
                    local cb   = locText.colorB or 255
                    local ca   = locText.colorA or 215
                    local txt  = locText.text or "Press ~INPUT_CONTEXT~ to get ID"
                    local tZ   = locText.zOffset or 1.0

                    SetTextFont(font)
                    SetTextProportional(0)
                    SetTextScale(sx, sy)
                    SetTextColour(cr, cg, cb, ca)
                    SetTextCentre(true)
                    SetTextEntry("STRING")
                    AddTextComponentString(txt)
                    SetDrawOrigin(coords.x, coords.y, coords.z + tZ, 0)
                    DrawText(0.0, 0.0)
                    ClearDrawOrigin()

                    if IsControlJustReleased(0, 38) then
                        dprint("E pressed at DMV marker, starting inputDialog + mugshot")

                        local info = nil
                        if lib and lib.inputDialog then
                            local input = lib.inputDialog('San Andreas DMV – ID Application', {
                                { type = 'input', label = 'Address Line 1', required = true,
                                  default = Config.DefaultAddress or '' },
                                { type = 'input', label = 'Address Line 2', required = true,
                                  default = Config.DefaultAddress2 or '' },
                                { type = 'input', label = 'Date of Birth (MM/DD/YYYY)', required = true,
                                  default = Config.DefaultDOB or '01/01/1990' },
                                { type = 'select', label = 'Sex', required = true,
                                  options = {
                                      { label = 'Male',   value = 'M' },
                                      { label = 'Female', value = 'F' },
                                      { label = 'Other',  value = 'X' }
                                  },
                                  default = Config.DefaultSex or 'M'
                                },
                                { type = 'input', label = 'Height', required = true,
                                  default = Config.DefaultHeight or '6\'-01"' },
                                { type = 'input', label = 'Weight', required = true,
                                  default = Config.DefaultWeight or '206 lb' },
                                { type = 'input', label = 'Hair', required = true,
                                  default = Config.DefaultHair or 'BRN' },
                                { type = 'input', label = 'Eyes', required = true,
                                  default = Config.DefaultEyes or 'BRN' },
                                { type = 'input', label = 'Restrictions', required = false,
                                  default = Config.DefaultRestrictions or 'NONE' },
                                { type = 'input', label = 'Driver Class', required = true,
                                  default = Config.DefaultClass or 'C' },
                                { type = 'input', label = 'Endorsements', required = false,
                                  default = Config.DefaultEndorsements or 'NONE' },
                                { type = 'input', label = 'Document Discriminator (DD)', required = false,
                                  default = Config.DefaultDD or '' },
                                { type = 'input', label = 'Signature (printed)', required = false,
                                  description = 'Leave blank to use character name.' }
                            }, {
                                allowCancel = true,
                                size        = 'md'
                            })

                            if not input then
                                dprint("DMV inputDialog: cancelled by user")
                                goto continue_loop
                            end

                            info = {
                                addr1     = input[1],
                                addr2     = input[2],
                                dob       = input[3],
                                sex       = input[4],
                                hgt       = input[5],
                                wgt       = input[6],
                                hair      = input[7],
                                eyes      = input[8],
                                rst       = input[9],
                                class     = input[10],
                                ["end"]   = input[11],
                                dd        = input[12],
                                signature = input[13]
                            }

                            dprint("DMV inputDialog: collected info, addr1=", info.addr1, "dob=", info.dob)
                        else
                            dprint("DMV: lib.inputDialog not available, using default info only")
                        end

                        dprint("Capturing mugshot via MugShotBase64")
                        local mugshot = exports["MugShotBase64"]:GetMugShotBase64(PlayerPedId(), true)
                        if mugshot and mugshot ~= "" then
                            dprint("Mugshot captured, len=", #mugshot)
                            TriggerServerEvent("az-id:saveMugshotAndInfo", mugshot, info)
                        else
                            dprint("Mugshot capture FAILED")
                            TriggerEvent("chat:addMessage", {
                                color = { 255, 0, 0 },
                                args  = { "ID", "Failed to capture mugshot." }
                            })
                        end

                        ::continue_loop::
                    end
                end
            end
        end

        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        if idOpen or requestPopupOpen then
            if IsControlJustReleased(0, 177) or IsControlJustReleased(0, 202) then
                dprint("ESC/BACKSPACE pressed while ID/request open; closing")
                closeIdCard()
                closeRequestPopup()
            end
        end
        Wait(0)
    end
end)
