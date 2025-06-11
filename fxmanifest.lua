fx_version 'cerulean'
game 'gta5'
author 'Azure(TheStoicBear)'
description 'Azure Framework'
version '1.0.0'

shared_script 'config.lua'

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
