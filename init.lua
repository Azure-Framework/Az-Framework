local RESOURCE = "Az-Framework"
local az_core = exports[RESOURCE]

local function makeWrapper(name)
    return function(...)
        local ok, fn = pcall(function() return az_core[name] end)
        if not ok or type(fn) ~= "function" then
            error(("%s export '%s' was not found."):format(RESOURCE, tostring(name)))
        end
        return fn(az_core, ...)
    end
end

Az = rawget(_G, "Az") or {}

setmetatable(Az, {
    __index = function(self, index)
        local wrapper = makeWrapper(index)
        rawset(self, index, wrapper)
        return wrapper
    end
})

local aliases = {
    AddMoney = 'AddMoney', addMoney = 'addMoney',
    DeductMoney = 'DeductMoney', deductMoney = 'deductMoney',
    DepositMoney = 'DepositMoney', depositMoney = 'depositMoney',
    WithdrawMoney = 'WithdrawMoney', withdrawMoney = 'withdrawMoney',
    TransferMoney = 'TransferMoney', transferMoney = 'transferMoney',
    ClaimDailyReward = 'ClaimDailyReward', claimDailyReward = 'claimDailyReward',
    GetDiscordID = 'GetDiscordID', getDiscordID = 'getDiscordID',
}

for k, exportName in pairs(aliases) do
    if rawget(Az, k) == nil then
        rawset(Az, k, makeWrapper(exportName))
    end
end

return Az
