local Config = (Config and Config.Fuel) or {}
if Config.Enabled == false then return end

local RESOURCE_NAME = GetCurrentResourceName()
local debug = Config.Debug

local function dprint(...)
    if not debug then return end
    local args = { ... }
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    print(("^3[%s C]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local currentVehicle      = nil

local hoseObj             = nil
local hosePumpPos         = nil
local hosePumpEntity      = nil
local hosePumpAnchorObj   = nil
local hoseRopeId          = nil
local hoseVehicle         = nil
local hoseState           = "IDLE"

local sessionCost         = 0.0
local sessionLiters       = 0.0

local uiSX                = 0.5
local uiSY                = 0.5

local nearestPumpPos      = nil
local nearestPumpDist     = math.huge
local nearestPumpEnt      = nil
local nearestVehicle      = nil
local nearestVehicleDist  = math.huge
local lastPedCoords       = nil

local electricModelCache  = {}

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function helpText(msg)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function loadModel(hash)
    if not IsModelValid(hash) then
        dprint("Model invalid:", hash)
        return false
    end

    if HasModelLoaded(hash) then
        return true
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            dprint("Model failed to load in time:", hash)
            return false
        end
        Wait(25)
    end
    return true
end

local function ensureFuelLevel(veh)
    if not DoesEntityExist(veh) then return end
    local fuel = GetVehicleFuelLevel(veh)
    if fuel <= 0.0 then
        fuel = 75.0
        SetVehicleFuelLevel(veh, fuel)
    end
end

local function isElectricVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return false
    end

    local model = GetEntityModel(veh)
    local cached = electricModelCache[model]
    if cached ~= nil then
        return cached
    end

    local isEV = false

    if GetIsVehicleElectric ~= nil then
        isEV = GetIsVehicleElectric(model) == true
    end

    if not isEV and Config.ElectricModels then
        for i = 1, #Config.ElectricModels do
            if Config.ElectricModels[i] == model then
                isEV = true
                break
            end
        end
    end

    electricModelCache[model] = isEV
    return isEV
end

local function clearPumpCache()
    nearestPumpPos  = nil
    nearestPumpDist = math.huge
    nearestPumpEnt  = nil
end

local function clearVehicleCache()
    nearestVehicle     = nil
    nearestVehicleDist = math.huge
end

local function findClosestPump(maxDist, pCoords)
    pCoords = pCoords or GetEntityCoords(PlayerPedId())
    maxDist = maxDist or Config.MaxPumpDistance

    local bestPos, bestDist, bestEnt
    local searchRadius = maxDist + 5.0

    for i = 1, #Config.PumpModels do
        local model = Config.PumpModels[i]
        local obj = GetClosestObjectOfType(
            pCoords.x, pCoords.y, pCoords.z,
            searchRadius,
            model, false, false, false
        )

        if obj ~= 0 and DoesEntityExist(obj) then
            local oCoords = GetEntityCoords(obj)
            local dist = distance(pCoords, oCoords)
            if dist <= maxDist and (not bestDist or dist < bestDist) then
                bestPos  = oCoords
                bestDist = dist
                bestEnt  = obj
            end
        end
    end

    return bestPos, bestDist, bestEnt
end

local function getClosestVehicle(maxDist, pCoords)
    pCoords = pCoords or GetEntityCoords(PlayerPedId())
    maxDist = maxDist or Config.MaxVehicleDistance

    local veh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, maxDist, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then
        local dist = distance(pCoords, GetEntityCoords(veh))
        return veh, dist
    end

    return nil, math.huge
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)
        lastPedCoords = pedCoords

        local sleep = Config.CacheRefreshFar or 1250
        local inVehicle = IsPedInAnyVehicle(ped, false)

        if hoseState == "FUELING" or hoseState == "ATTACHED" then
            sleep = Config.CacheRefreshActive or 250
        elseif hoseState == "HELD" then
            sleep = Config.CacheRefreshNear or 300
        elseif not inVehicle then
            sleep = Config.CacheRefreshNear or 300
        end

        local pumpSearchDist = 0.0

        if hoseState == "HELD" and hosePumpPos then
            pumpSearchDist = math.max(Config.MaxPumpDistance + 0.5, Config.PumpMarkerDrawDistance or 0.0)
        elseif hoseState == "ATTACHED" or hoseState == "FUELING" then
            pumpSearchDist = Config.MaxHoseStretch + 2.0
        elseif not inVehicle then
            pumpSearchDist = Config.MaxPumpDistance + 0.75
            if Config.ShowPumpMarkers then
                pumpSearchDist = math.max(pumpSearchDist, Config.PumpMarkerDrawDistance or 20.0)
            end
        end

        if pumpSearchDist > 0.0 then
            nearestPumpPos, nearestPumpDist, nearestPumpEnt = findClosestPump(pumpSearchDist, pedCoords)
            if not nearestPumpPos then
                clearPumpCache()
            end
        else
            clearPumpCache()
        end

        if hoseState == "HELD" and not inVehicle then
            nearestVehicle, nearestVehicleDist = getClosestVehicle(Config.MaxVehicleDistance, pedCoords)
            if not nearestVehicle then
                clearVehicleCache()
            end
        else
            clearVehicleCache()
        end

        Wait(sleep)
    end
end)

local function deleteRope()
    if hoseRopeId and hoseRopeId ~= 0 then
        DeleteRope(hoseRopeId)
    end
    hoseRopeId = nil

    if hosePumpAnchorObj and DoesEntityExist(hosePumpAnchorObj) then
        DeleteObject(hosePumpAnchorObj)
    end
    hosePumpAnchorObj = nil
end

local function createRope()
    deleteRope()
    if not Config.DrawHoseRope then return end
    if not hosePumpPos or not hoseObj or not DoesEntityExist(hoseObj) then return end

    local anchorModel = `prop_weight_15k`
    if not loadModel(anchorModel) then return end

    local pumpAnchorPos = hosePumpPos + vector3(0.0, 0.0, 1.0)
    hosePumpAnchorObj = CreateObjectNoOffset(anchorModel, pumpAnchorPos.x, pumpAnchorPos.y, pumpAnchorPos.z, false, false, false)
    SetModelAsNoLongerNeeded(anchorModel)
    SetEntityVisible(hosePumpAnchorObj, false, false)
    FreezeEntityPosition(hosePumpAnchorObj, true)

    RopeLoadTextures()

    local hosePos = GetEntityCoords(hoseObj)
    local length  = distance(pumpAnchorPos, hosePos) + 1.0

    hoseRopeId = AddRope(
        pumpAnchorPos.x, pumpAnchorPos.y, pumpAnchorPos.z,
        0.0, 0.0, 0.0,
        length,
        4,
        length,
        0.5,
        false, false, true,
        1.0,
        false,
        0
    )

    if hoseRopeId and hoseRopeId ~= 0 then
        AttachEntitiesToRope(
            hoseRopeId,
            hosePumpAnchorObj, hoseObj,
            pumpAnchorPos.x, pumpAnchorPos.y, pumpAnchorPos.z,
            hosePos.x, hosePos.y, hosePos.z,
            length,
            false, false,
            nil, nil
        )
        dprint("Created hose rope with id", hoseRopeId)
    else
        dprint("Failed to create hose rope")
        deleteRope()
    end
end

local function deleteHose()
    if hoseObj and DoesEntityExist(hoseObj) then
        DeleteObject(hoseObj)
    end
    hoseObj        = nil
    hosePumpPos    = nil
    hosePumpEntity = nil
    hoseVehicle    = nil
    hoseState      = "IDLE"
    sessionCost    = 0.0
    sessionLiters  = 0.0
    deleteRope()
    SendNUIMessage({ action = "fuel_close" })
end

local function attachHoseToPlayer(pumpPos, pumpEnt)
    if hoseState ~= "IDLE" then return end

    local ped = PlayerPedId()
    if not loadModel(Config.HoseModel) then return end

    local spawnPos = pumpPos + vector3(0.0, 0.0, 1.0)
    local obj = CreateObjectNoOffset(Config.HoseModel, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
    SetModelAsNoLongerNeeded(Config.HoseModel)
    if obj == 0 then
        dprint("Failed to create hose object")
        return
    end

    SetEntityCollision(obj, false, false)

    local handBone = GetPedBoneIndex(ped, 0x49D9)
    AttachEntityToEntity(
        obj, ped, handBone,
        0.10, 0.02, 0.02,
        90.0, 40.0, 170.0,
        true, true, false, true, 1, true
    )

    hoseObj        = obj
    hosePumpPos    = pumpPos
    hosePumpEntity = pumpEnt
    hoseState      = "HELD"

    createRope()
    dprint("Hose picked up near pump", pumpPos.x, pumpPos.y, pumpPos.z)
end

local function attachHoseToVehicle(veh)
    if hoseState ~= "HELD" then return end
    if not hoseObj or not DoesEntityExist(hoseObj) then return end
    if not DoesEntityExist(veh) then return end

    DetachEntity(hoseObj, true, true)

    local capBone = GetEntityBoneIndexByName(veh, "petrolcap")
    if capBone == -1 then
        capBone = GetEntityBoneIndexByName(veh, "wheel_rr")
    end

    local offset = vector3(0.05, 0.0, 0.10)
    AttachEntityToEntity(
        hoseObj, veh, capBone,
        offset.x, offset.y, offset.z,
        0.0, 0.0, 0.0,
        true, true, false, true, 1, true
    )

    hoseVehicle = veh
    hoseState   = "ATTACHED"

    createRope()
    dprint("Hose attached to vehicle", veh)
end

local function returnHoseToPump()
    if hoseState ~= "HELD" then return end
    deleteHose()
    dprint("Hose returned to pump")
end

local function startFueling()
    if hoseState ~= "ATTACHED" then
        helpText("Attach the nozzle to the vehicle first.")
        return
    end
    if not hoseVehicle or not DoesEntityExist(hoseVehicle) then
        helpText("No vehicle to fuel/charge.")
        return
    end

    sessionCost   = 0.0
    sessionLiters = 0.0
    hoseState     = "FUELING"

    local fuel = GetVehicleFuelLevel(hoseVehicle)
    local ev   = isElectricVehicle(hoseVehicle)

    local uiWorld = hosePumpPos + vector3(0.3, 0.0, 1.5)
    local onScreen; onScreen, uiSX, uiSY = GetScreenCoordFromWorldCoord(uiWorld.x, uiWorld.y, uiWorld.z)
    if not onScreen then
        uiSX, uiSY = 0.5, 0.5
    end

    SendNUIMessage({
        action = "fuel_open",
        fuel   = fuel,
        cost   = sessionCost,
        liters = sessionLiters,
        isEV   = ev,
        sx     = uiSX,
        sy     = uiSY
    })

    dprint("Fueling/charging started")
end

local function stopFueling()
    if hoseState ~= "FUELING" then return end

    local ped = PlayerPedId()

    if Config.UseBilling and sessionCost > 0.0 then
        local finalCost = math.floor(sessionCost + 0.5)
        TriggerServerEvent("az_fuelpump:chargeFuelFinal", finalCost)
        dprint(("Sent final fuel/charge cost to server: $%d"):format(finalCost))
    end

    sessionCost   = 0.0
    sessionLiters = 0.0

    SendNUIMessage({ action = "fuel_close" })

    if hoseObj and DoesEntityExist(hoseObj) and hoseVehicle and DoesEntityExist(hoseVehicle) then
        DetachEntity(hoseObj, true, true)

        local handBone = GetPedBoneIndex(ped, 0x49D9)
        AttachEntityToEntity(
            hoseObj, ped, handBone,
            0.10, 0.02, 0.02,
            90.0, 40.0, 170.0,
            true, true, false, true, 1, true
        )

        hoseState   = "HELD"
        hoseVehicle = nil
        createRope()
        dprint("Fueling/charging stopped, hose back in hand")
    else
        deleteHose()
    end
end

CreateThread(function()
    while true do
        Wait(Config.FuelTickInterval)

        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                currentVehicle = veh
                ensureFuelLevel(veh)

                local speed = GetEntitySpeed(veh) * 3.6
                local fuel  = GetVehicleFuelLevel(veh)

                local drain = Config.FuelDrainIdle
                if speed > 2.0 then
                    drain = Config.FuelDrainDriving
                end
                if speed > 80.0 then
                    drain = Config.FuelDrainHighSpeed
                end

                local seconds = Config.FuelTickInterval / 1000.0
                fuel = fuel - (drain * seconds)

                if fuel <= 0.0 then
                    fuel = 0.0
                    SetVehicleEngineOn(veh, false, false, true)
                end

                SetVehicleFuelLevel(veh, fuel)
            end
        else
            currentVehicle = nil
        end
    end
end)

local function getHudVehicle()
    if hoseVehicle and DoesEntityExist(hoseVehicle) then
        return hoseVehicle
    end
    if currentVehicle and DoesEntityExist(currentVehicle) then
        return currentVehicle
    end
    return nil
end

local function drawFuelHud()
    if not Config.EnableHUD then return end
    if hoseState == "FUELING" then return end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end

    local veh = getHudVehicle()
    if not veh then return end

    local fuel = GetVehicleFuelLevel(veh)
    if fuel < 0.0 then fuel = 0.0 end
    if fuel > Config.MaxFuel then fuel = Config.MaxFuel end

    local pct       = (fuel / Config.MaxFuel)
    local value     = math.floor(pct * 100.0 + 0.5)
    local isEV      = isElectricVehicle(veh)
    local labelName = isEV and "Charge" or "Fuel"

    local barW = 0.165
    local barH = 0.010
    local barX = 0.145 + (Config.HUD.offsetX or 0.0)
    local barY = 0.990 + (Config.HUD.offsetY or 0.0)

    DrawRect(barX, barY, barW + 0.006, barH + 0.006, 0, 0, 0, 180)
    DrawRect(barX, barY, barW,         barH,         20, 20, 20, 220)

    local fillW = barW * pct
    if fillW > 0.0 then
        local leftEdge = barX - barW / 2.0
        local fillX    = leftEdge + fillW / 2.0
        DrawRect(fillX, barY, fillW, barH, 90, 180, 255, 220)
    end

    local text = ("%s %d"):format(labelName, value)
    local textX = barX
    local textY = barY - 0.016

    SetTextFont(4)
    SetTextScale(0.28, 0.28)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)

    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(textX, textY)
end

CreateThread(function()
    while true do
        local sleep = 500

        if Config.EnableHUD and hoseState ~= "FUELING" then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                sleep = 0
                drawFuelHud()
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 750

        if Config.ShowPumpMarkers and nearestPumpPos and nearestPumpDist <= (Config.PumpMarkerDrawDistance or 20.0) then
            sleep = 0
            DrawMarker(
                Config.PumpMarker.type,
                nearestPumpPos.x, nearestPumpPos.y, nearestPumpPos.z + 0.1,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                Config.PumpMarker.scale.x, Config.PumpMarker.scale.y, Config.PumpMarker.scale.z,
                Config.PumpMarker.rgba[1], Config.PumpMarker.rgba[2],
                Config.PumpMarker.rgba[3], Config.PumpMarker.rgba[4],
                false, false, 2, false, nil, nil, false
            )
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if not IsPedInAnyVehicle(ped, false) then
            if hoseState == "IDLE" then
                if nearestPumpPos and nearestPumpDist <= Config.MaxPumpDistance then
                    sleep = 0
                    helpText(("Press %s to pick up nozzle"):format(Config.Keys.Use))
                    if IsControlJustReleased(0, 38) then
                        attachHoseToPlayer(nearestPumpPos, nearestPumpEnt)
                    end
                elseif nearestPumpPos and nearestPumpDist <= ((Config.PumpMarkerDrawDistance or 20.0) + 5.0) then
                    sleep = 250
                end

            elseif hoseState == "HELD" then
                if hosePumpPos and lastPedCoords and distance(lastPedCoords, hosePumpPos) <= Config.MaxPumpDistance then
                    sleep = 0
                    helpText(("Press %s to hang up nozzle"):format(Config.Keys.Use))
                    if IsControlJustReleased(0, 38) then
                        returnHoseToPump()
                    end
                elseif nearestVehicle and nearestVehicleDist <= Config.MaxVehicleDistance then
                    sleep = 0
                    helpText(("Press %s to attach nozzle to vehicle"):format(Config.Keys.Use))
                    if IsControlJustReleased(0, 38) then
                        attachHoseToVehicle(nearestVehicle)
                    end
                else
                    sleep = 250
                end

            elseif hoseState == "ATTACHED" then
                sleep = 0
                local ev = hoseVehicle and isElectricVehicle(hoseVehicle)
                local action = ev and "start charging" or "start fueling"
                helpText(("Press %s to %s"):format(Config.Keys.Start, action))
                if IsControlJustReleased(0, 22) then
                    startFueling()
                end

            elseif hoseState == "FUELING" then
                sleep = 0
                local ev = hoseVehicle and isElectricVehicle(hoseVehicle)
                local action = ev and "stop charging" or "stop fueling"
                helpText(("Press %s to %s"):format(Config.Keys.Start, action))
                if IsControlJustReleased(0, 22) then
                    stopFueling()
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 500

        if hoseState == "ATTACHED" or hoseState == "FUELING" then
            sleep = Config.HologramRefreshMs or 100

            if hosePumpPos then
                local uiWorld = hosePumpPos + vector3(0.3, 0.0, 1.5)
                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(uiWorld.x, uiWorld.y, uiWorld.z)
                if onScreen then
                    if math.abs(sx - uiSX) > 0.0005 or math.abs(sy - uiSY) > 0.0005 then
                        uiSX, uiSY = sx, sy
                        SendNUIMessage({
                            action = "fuel_pos",
                            sx     = uiSX,
                            sy     = uiSY
                        })
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if hoseState == "FUELING" then
            sleep = 100
        end
        Wait(sleep)

        if hoseState ~= "FUELING" then
            goto continue
        end

        if not hoseVehicle or not DoesEntityExist(hoseVehicle) then
            dprint("Fueling aborted: vehicle gone")
            helpText("Stopped: vehicle moved.")
            stopFueling()
            goto continue
        end

        if not hosePumpPos then
            dprint("Fueling aborted: pump position lost")
            helpText("Stopped: pump lost.")
            stopFueling()
            goto continue
        end

        local vehPos  = GetEntityCoords(hoseVehicle)
        local stretch = distance(hosePumpPos, vehPos)

        if stretch > Config.MaxHoseStretch then
            dprint("Fueling aborted: hose stretched too far", stretch)
            helpText("Stopped: too far from pump.")
            stopFueling()
            goto continue
        end

        local fuel = GetVehicleFuelLevel(hoseVehicle)
        if fuel >= Config.MaxFuel then
            local ev = isElectricVehicle(hoseVehicle)
            dprint("Full, stopping fueling/charging")
            helpText(ev and "Battery is full." or "Tank is full.")
            stopFueling()
            goto continue
        end

        local ev        = isElectricVehicle(hoseVehicle)
        local perSecond = ev and Config.EVChargePerSecond or Config.FuelPerSecondAtPump
        local seconds   = 0.10
        local addedFuel = perSecond * seconds
        local newFuel   = fuel + addedFuel
        if newFuel > Config.MaxFuel then
            addedFuel = Config.MaxFuel - fuel
            newFuel   = Config.MaxFuel
        end

        local litersPerUnit = (Config.TankCapacityLiters or 60.0) / Config.MaxFuel
        local addedLiters   = addedFuel * litersPerUnit

        if Config.UseBilling then
            local price = ev and Config.PricePerUnitElectric or Config.PricePerUnitFuel
            local cost  = addedFuel * price
            if cost > 0.0 then
                sessionCost = sessionCost + cost
            end
        end

        sessionLiters = sessionLiters + addedLiters
        SetVehicleFuelLevel(hoseVehicle, newFuel)

        SendNUIMessage({
            action = "fuel_update",
            fuel   = newFuel,
            cost   = sessionCost,
            liters = sessionLiters,
            isEV   = ev
        })

        ::continue::
    end
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= RESOURCE_NAME then return end
    deleteHose()
end)
