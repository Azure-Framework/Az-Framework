fx_version 'cerulean'
game 'gta5'

name 'Az-Insurance'
author 'Azure Framework'
description 'Vehicle insurance system tied into Az-Parking and Az-Framework money'
version '1.0.0'

lua54 'yes'

shared_script 'config.lua'

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}
