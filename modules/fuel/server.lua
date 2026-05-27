local Config = (Config and Config.Fuel) or {}
if Config.Enabled == false then return end

local RESOURCE_NAME = GetCurrentResourceName()

local function dprint(...)
    if not Config or not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    print(("^3[%s S]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local fw = exports['Az-Framework']

AddEventHandler('onResourceStart', function(res)
    if res ~= RESOURCE_NAME then return end

    dprint("Az-FuelPump server.lua loaded.")
    dprint("Resource started, checking Az-Framework exports...")

    if not fw then
        dprint("fw == nil (exports['Az-Framework'] missing?)")
        return
    end

    dprint("fw handle:", tostring(fw))
    dprint("Has deductMoney?", fw.deductMoney and "yes" or "no")
end)

RegisterNetEvent("az_fuelpump:chargeFuelFinal", function(cost)
    if not Config or not Config.UseBilling then return end
    if not fw or not fw.deductMoney then
        dprint("Billing: fw or deductMoney missing, skipping charge.")
        return
    end

    local src = source
    cost = tonumber(cost) or 0.0
    cost = math.floor(cost + 0.5)
    if cost <= 0 then return end

    fw:deductMoney(src, cost)

    dprint(("[Billing] Charged player %d $%d for fuel/charge session"):format(src, cost))
end)
