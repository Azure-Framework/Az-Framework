fx_version 'cerulean'
game 'gta5'

author 'MadeByAzure'
description 'Daily Check-in NUI v2 with MySQL tracking, Az-Framework money, animated UI, wheel spin.'
version '2.0.0'

shared_script 'config.lua'

server_script 'server.lua'
client_script 'client.lua'

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/styles.css',
  'html/app.js',

  'html/assets/icons/*',
  'html/sounds/game.mp3',
  'html/sounds/level.mp3',
  'html/sounds/spin.mp3',
}
