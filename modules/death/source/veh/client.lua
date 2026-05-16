local Config = (Config and Config.Death) or {}
if Config.Enabled == false then return end

Config.BlackoutTime = tonumber(Config.BlackoutTime) or 1000
Config.ScreenShakeMultiplier = tonumber(Config.ScreenShakeMultiplier) or 1.0
Config.TimeLeftToEnableControls = tonumber(Config.TimeLeftToEnableControls) or 2
Config.DisableControlsOnBlackout = Config.DisableControlsOnBlackout == true
Config.BlackoutDamageRequiredLevel1 = tonumber(Config.BlackoutDamageRequiredLevel1) or 25.0
Config.BlackoutDamageRequiredLevel2 = tonumber(Config.BlackoutDamageRequiredLevel2) or 45.0
Config.BlackoutDamageRequiredLevel3 = tonumber(Config.BlackoutDamageRequiredLevel3) or 70.0
Config.BlackoutDamageRequiredLevel4 = tonumber(Config.BlackoutDamageRequiredLevel4) or 95.0
Config.BlackoutDamageRequiredLevel5 = tonumber(Config.BlackoutDamageRequiredLevel5) or 130.0
Config.BlackoutSpeedRequiredLevel1 = tonumber(Config.BlackoutSpeedRequiredLevel1) or 18.0
Config.BlackoutSpeedRequiredLevel2 = tonumber(Config.BlackoutSpeedRequiredLevel2) or 28.0
Config.BlackoutSpeedRequiredLevel3 = tonumber(Config.BlackoutSpeedRequiredLevel3) or 40.0
Config.BlackoutSpeedRequiredLevel4 = tonumber(Config.BlackoutSpeedRequiredLevel4) or 52.0
Config.BlackoutSpeedRequiredLevel5 = tonumber(Config.BlackoutSpeedRequiredLevel5) or 65.0
Config.EffectTimeLevel1 = tonumber(Config.EffectTimeLevel1) or 3
Config.EffectTimeLevel2 = tonumber(Config.EffectTimeLevel2) or 4
Config.EffectTimeLevel3 = tonumber(Config.EffectTimeLevel3) or 5
Config.EffectTimeLevel4 = tonumber(Config.EffectTimeLevel4) or 6
Config.EffectTimeLevel5 = tonumber(Config.EffectTimeLevel5) or 7

local effectActive = false
local blackoutActive = false
local currentAccidentLevel = 0
local wasInCar = false
local oldBodyDamage = 0.0
local oldSpeed = 0.0
local currentDamage = 0.0
local currentSpeed = 0.0
local vehicle
local disableControls = false

local function isCar(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)
    return (vehicleClass >= 0 and vehicleClass <= 7) or
           (vehicleClass >= 9 and vehicleClass <= 12) or
           (vehicleClass >= 17 and vehicleClass <= 20)
end

local function notify(text)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(text)
    DrawNotification(false, false)
end

RegisterNetEvent("crashEffect")
AddEventHandler("crashEffect", function(countDown, accidentLevel)
    if not effectActive or (accidentLevel > currentAccidentLevel) then
        currentAccidentLevel = accidentLevel
        disableControls = true
        effectActive = true
        blackoutActive = true
        DoScreenFadeOut(100)
        Wait(Config.BlackoutTime)
        DoScreenFadeIn(250)
        blackoutActive = false

        StartScreenEffect('PeyoteEndOut', 0, true)
        StartScreenEffect('Dont_tazeme_bro', 0, true)
        StartScreenEffect('MP_race_crash', 0, true)

        while countDown > 0 do
            if countDown > (3.5 * accidentLevel)   then
                ShakeGameplayCam("MEDIUM_EXPLOSION_SHAKE", (accidentLevel * Config.ScreenShakeMultiplier))
            end
            Wait(750)
            countDown = countDown - 1

            if countDown < Config.TimeLeftToEnableControls and disableControls then
                disableControls = false
            end

            if countDown <= 1 then
                StopScreenEffect('PeyoteEndOut')
                StopScreenEffect('Dont_tazeme_bro')
                StopScreenEffect('MP_race_crash')
            end
        end
        currentAccidentLevel = 0
        effectActive = false
    end
end)

Citizen.CreateThread(function()
	while true do
        local sleep = 250
        local ped = PlayerPedId()

        if disableControls and Config.DisableControlsOnBlackout then
            sleep = 0

			DisableControlAction(0, 71, true)
			DisableControlAction(0, 72, true)
			DisableControlAction(0, 63, true)
			DisableControlAction(0, 64, true)
			DisableControlAction(0, 75, true)
		end

        vehicle = GetVehiclePedIsIn(ped, false)
        if DoesEntityExist(vehicle) and (wasInCar or isCar(vehicle)) then
            wasInCar = true
            if sleep > 50 then sleep = 50 end

            oldSpeed = currentSpeed
            oldBodyDamage = currentDamage
            currentDamage = GetVehicleBodyHealth(vehicle)
            currentSpeed = GetEntitySpeed(vehicle) * 2.23

            if currentDamage ~= oldBodyDamage then
                if not effectActive and currentDamage < oldBodyDamage then
                    if (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel5 or
                       (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel5
                    then
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel5, 5)

                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel4 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel4
                    then
                        TriggerEvent("crashEffect", Config.EffectTimeLevel4, 4)
                        oldBodyDamage = currentDamage

                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel3 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel3
                    then
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel3, 3)

                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel2 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel2
                    then
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel2, 2)

                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel1 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel1
                    then
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel1, 1)
                    end
                end
            end
        elseif wasInCar then
            wasInCar = false
            currentDamage = 0
            oldBodyDamage = 0
            currentSpeed = 0
            oldSpeed = 0
        end

        Citizen.Wait(sleep)
	end
end)
