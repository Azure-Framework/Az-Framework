fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Azure(TheStoicBear)'
description 'Azure Framework'
version '1.5.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
} 

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'parking/server.lua',
    'departments/server.lua'
}

client_scripts {
    'client.lua',
    'parking/client.lua',
    'departments/client.lua'

}

ui_page 'html/index.html'

files {
    'html/index.html'
}
