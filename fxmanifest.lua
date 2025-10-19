fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Azure(TheStoicBear)'
description 'Azure Framework'
version '1.9.1'

shared_scripts {
    '@ox_lib/init.lua',
    "@Az-Framework/init.lua",
    'config.lua',
} 

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'init.lua',        -- <--- add this
    'schema.lua',
    'server.lua',
    'parking/server.lua',
    'departments/server.lua',

}

client_scripts {
    'client.lua',
    'parking/client.lua',
    'departments/client.lua',
    'presence.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'init.lua'
}


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


