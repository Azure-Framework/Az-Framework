fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Azure(TheStoicBear)'
description 'Azure Framework'
version 'v1.9.2'

shared_scripts {
    '@ox_lib/init.lua',
    "@Az-Framework/init.lua",
    'config/config.lua',
} 

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'init.lua',        -- <--- add this
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

exports {
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
    "isAdmin",
    "GetPlayerCharacter",
    "GetDiscordID",
    "GetPlayerCharacterName",
    "GetPlayerMoney",
    "logAdminCommand"
}
