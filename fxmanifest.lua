fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Azure(TheStoicBear)'
description 'Azure Framework'
version '1.5.5'

shared_scripts {
    '@ox_lib/init.lua',
    "@Az-Framework/init.lua",
    'config/config.lua',
} 

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'init.lua',
    'schema.lua',
    'core/server.lua',
    'parking/server.lua',
    'departments/server.lua',

}

client_scripts {
    'core/client.lua',
    'parking/client.lua',
    'departments/client.lua',
    'discord/presence.lua',
}

files {
    'html/config.js',
    'html/index.html',
    'init.lua',

}


ui_page 'html/index.html'

client_exports {
    "refreshHUD",
    "updateHUD",
    "RefreshDiscordPresence",
    "SetDiscordPresenceOverride",
    "SetDiscordJob"
}

server_exports {
    -- preferred camelCase exports
    "addMoney",
    "deductMoney",
    "depositMoney",
    "withdrawMoney",
    "transferMoney",
    "GetMoney",
    "UpdateMoney",
    "sendMoneyToClient",
    "claimDailyReward",
    "getDiscordID",
    "GetDiscordID",
    "isAdmin",
    "GetPlayerCharacter",
    "GetPlayerCharacterName",
    "GetPlayerCharacterNameSync",
    "GetPlayerMoney",
    "logAdminCommand",
    "getPlayerJob",

    -- compatibility aliases for resources expecting capitalized names
    "AddMoney",
    "DeductMoney",
    "DepositMoney",
    "WithdrawMoney",
    "TransferMoney",
    "ClaimDailyReward"
}
