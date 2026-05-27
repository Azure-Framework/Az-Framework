fx_version 'cerulean'
game 'gta5'

name 'az_housing'
author 'MadeByAzure'
description 'Housing / Apartment system: routing buckets interiors, knocking, police breach, sales/rentals portals, agent portal, placeable doors & garages.'
version '1.0.0'

lua54 'yes'
shared_script '@Az-Framework/init.lua'

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'shared/framework.lua',
  'server/storage.lua',
  'server/main.lua',
  'server/garage.lua',
  'server/portal.lua',
  'server/upgrades.lua',
  'server/mailbox.lua',
  'server/furniture.lua',

}
shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/init.lua',
  'shared/utils.lua',
  'shared/money.lua'
}

client_scripts {
  'client/state.lua',
  'client/ui.lua',
  'client/target.lua',
  'client/garage.lua',
  'client/furniture.lua',
  'client/placement.lua',
  'client/main.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/app.css',
  'html/app.js',
  'sql/install.sql',
  'html/icons/*',
  'html/assets/*'
}
