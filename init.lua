
local RESOURCE = "Az-Framework"
local az_core = exports[RESOURCE]

local function makeWrapper(name)
    return function(...)
        local fn = az_core[name]
        if type(fn) ~= "function" then
            error(("%s export '%s' was not found."):format(RESOURCE, tostring(name)))
        end
        return fn(az_core, ...)
    end
end

Az = rawget(_G, "Az") or {}

setmetatable(Az, {
    __index = function(self, index)
        local value = az_core[index]
        if type(value) == "function" then
            local wrapper = makeWrapper(index)
            rawset(self, index, wrapper)
            return wrapper
        end
        rawset(self, index, value)
        return value
    end
})

-- Convenience aliases so both camelCase and PascalCase work.
Az.AddMoney        = Az.AddMoney        or makeWrapper("AddMoney")
Az.addMoney        = Az.addMoney        or makeWrapper("addMoney")
Az.DeductMoney     = Az.DeductMoney     or makeWrapper("DeductMoney")
Az.deductMoney     = Az.deductMoney     or makeWrapper("deductMoney")
Az.DepositMoney    = Az.DepositMoney    or makeWrapper("DepositMoney")
Az.depositMoney    = Az.depositMoney    or makeWrapper("depositMoney")
Az.WithdrawMoney   = Az.WithdrawMoney   or makeWrapper("WithdrawMoney")
Az.withdrawMoney   = Az.withdrawMoney   or makeWrapper("withdrawMoney")
Az.TransferMoney   = Az.TransferMoney   or makeWrapper("TransferMoney")
Az.transferMoney   = Az.transferMoney   or makeWrapper("transferMoney")
Az.ClaimDailyReward = Az.ClaimDailyReward or makeWrapper("ClaimDailyReward")
Az.claimDailyReward = Az.claimDailyReward or makeWrapper("claimDailyReward")
Az.GetDiscordID    = Az.GetDiscordID    or makeWrapper("GetDiscordID")
Az.getDiscordID    = Az.getDiscordID    or makeWrapper("getDiscordID")

return Az
