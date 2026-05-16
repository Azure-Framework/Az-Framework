fx_version 'cerulean'
game 'gta5'

author 'MadeByAzure'
description 'Az-FuelPump – simple fuel system with pump interaction & HUD'
version '1.0.0'

lua54 'yes'

ui_page 'html/index.html'

files {
    'html/index.html'
}

client_scripts {
    'config.lua',
    'client.lua'
}

server_scripts {
    'config.lua',
    'server.lua'
}
