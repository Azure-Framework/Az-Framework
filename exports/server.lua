local core = _G.AzServerExports or {}
local bridge = _G.AzBridgeServerExports or {}

local function registerExport(name, fn)
  if type(fn) == 'function' then
    exports(name, fn)
  end
end

local names = {
  'addMoney', 'deductMoney', 'depositMoney', 'withdrawMoney', 'transferMoney',
  'GetMoney', 'UpdateMoney', 'sendMoneyToClient', 'claimDailyReward',
  'getDiscordID', 'GetDiscordID', 'isAdmin',
  'GetPlayerCharacter', 'GetPlayerCharacterName', 'GetPlayerCharacterNameSync',
  'getActiveCharacter', 'GetActiveCharacter', 'GetCharacter', 'getCharacter',
  'SetActiveCharacter', 'setActiveCharacter', 'ClearActiveCharacter', 'clearActiveCharacter',
  'GetPlayerMoney', 'logAdminCommand', 'getPlayerJob', 'setPlayerJob',
  'hasHuntingLicense', 'setHuntingLicense', 'isHuntingLicenseEnabled',
  'getConfiguredDepartments', 'saveConfiguredDepartments', 'upsertConfiguredDepartment', 'removeConfiguredDepartment',
  'AddMoney', 'DeductMoney', 'DepositMoney', 'WithdrawMoney', 'TransferMoney', 'ClaimDailyReward',
  'HasHuntingLicense', 'SetHuntingLicense', 'IsHuntingLicenseEnabled', 'SetPlayerJob',
}

for _, name in ipairs(names) do
  registerExport(name, core[name])
end

local bridgeNames = {
  'GetBridgePlayerSnapshot', 'GetBridgePlayers', 'GetBridgeMoney',
  'AddBridgeMoney', 'RemoveBridgeMoney', 'SetBridgeMoney',
  'GetBridgeMetadata', 'SetBridgeMetadata', 'BridgeNotify',
  'GetBridgeItemCount', 'HasBridgeItem', 'GetBridgeItem',
  'AddBridgeItem', 'RemoveBridgeItem',
}

for _, name in ipairs(bridgeNames) do
  registerExport(name, bridge[name])
end
