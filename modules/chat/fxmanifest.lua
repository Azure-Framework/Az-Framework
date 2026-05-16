fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Azure'
description 'Az-Chat - Transparent custom NUI chat with emoji picker and admin moderation tools'
version '1.1.1'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'html/index.html',
    'html/app.js',
    'html/style.css',
    'html/assets/icons/chat.svg',
    'html/assets/icons/admin.svg',
    'html/assets/icons/dm.svg',
    'html/assets/icons/announce.svg',
    'html/assets/icons/system.svg',
    'html/assets/icons/local.svg',
    'html/assets/icons/jobs/fire.svg',
    'html/assets/icons/jobs/ems.svg',
    'html/assets/icons/jobs/police.svg',
    'html/assets/icons/jobs/civ.svg'
}

dependencies {
    'Az-Framework',
    'ox_lib'
}
