fx_version 'cerulean'
game 'gta5'

name 'Az-ID'
author 'MadeByAzure'
description 'San Andreas style ID card using Az-Framework + MugShotBase64'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

client_scripts {
    'config.lua',
    'client.lua'
}

server_scripts {
    'config.lua',
    'server.lua'
}

dependencies {
    'Az-Framework',
    'MugShotBase64'
}
