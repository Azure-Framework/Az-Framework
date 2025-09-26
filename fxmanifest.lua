fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Azure(TheStoicBear)'
description 'Azure Framework'
version '1.7.9'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'client.lua',
} 

server_scripts {
    '@oxmysql/lib/MySQL.lua',
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
    'note.lua'

}

ui_page 'html/index.html'

files {
    'html/index.html'
}
