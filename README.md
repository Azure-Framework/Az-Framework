# Az-Framework

Az-Framework is a modular FiveM framework focused on character-based gameplay, money and job management, admin tooling, and compatibility for Azure-based resources.

## Features

- Character selection and spawn flow
- Active-character tracking for external resources
- Money accounts and bridge-friendly money exports
- Job and department management
- Admin tools and support/report panel
- HUD and player status data
- Discord presence integration
- Modular gameplay resources, including banking, housing, DMV, fuel, death, insurance, and chat
- Compatibility bridge support for QBCore, qb-inventory, qb-target, ESX, and ND_Core resources

## Documentation and Support

- Framework docs: https://madebyazure.com/framework/
- Discord support: https://discord.gg/tBg2U6CTHE

## Resource Name

```cfg
ensure Az-Framework
```

## Recommended Start Order

```cfg
ensure oxmysql
ensure ox_lib
ensure Az-Framework
```

Start inventory, targeting, vMenu, MDT, phone, jobs, and other gameplay resources after Az-Framework.

## Compatibility Bridges

Az-Framework bridge resources are published as standalone bridge repos for servers that still run QBCore, qb-inventory, qb-target, ESX, or ND-style resources.

```cfg
ensure Az-Framework
ensure qb-core
ensure qb-inventory
ensure qb-target
ensure es_extended
ensure ND_Core
```

Bridge repositories:

- `Az-QBCore-Bridge` provides the `qb-core` resource name.
- `Az-QBInventory-Bridge` provides the `qb-inventory` resource name.
- `Az-QBTarget-Bridge` provides the `qb-target` resource name.
- `Az-ESX-Bridge` provides the `es_extended` resource name.
- `Az-NDCore-Bridge` provides the `ND_Core` resource name.

## Summer 2.0 Pack

Summer 2.0 resources use `Az-Summer2Core` for contract registration, objective routing, rewards, cooldowns, validation, and dispatch hooks. Start the core before the activity resources.

```cfg
ensure Az-Summer2Core
ensure Az-Lifeguard
ensure Az-Marina
ensure Az-IceCream
ensure Az-Camping
ensure Az-ParkEvents
ensure Az-ResortStaff
ensure Az-FoodFestival
ensure Az-Fishing2
ensure Az-SmugglingRun
ensure Az-Boosting2
ensure Az-Burglary2
ensure Az-DrugLabs2
ensure Az-IllegalFishing
ensure Az-Poaching
ensure Az-ScrapTheft
ensure Az-FraudOps
ensure Az-StreetRacing2
ensure Az-BlackMarketBeach
```

## Folder Layout

```txt
admin/
bridge/
characterui/
config/
core/
departments/
discord/
exports/
html/
modules/
parking/
```

## Main Config Files

```txt
config/config.lua
config/character_defaults.lua
config/admin_defaults.lua
config/departments_runtime.json
config/hud_preset.json
config/hud_state.json
```

## Export Files

Public exports are registered from dedicated files so they are easy to find and maintain.

```txt
exports/server.lua
exports/client.lua
```

Core logic stays inside the framework modules. The export files register the public API only.

## Important Server Exports

```lua
exports['Az-Framework']:GetActiveCharacter(source)
exports['Az-Framework']:SetActiveCharacter(source, charid)
exports['Az-Framework']:GetPlayerCharacter(source)
exports['Az-Framework']:GetPlayerCharacterNameSync(source)
exports['Az-Framework']:getPlayerJob(source)
exports['Az-Framework']:setPlayerJob(source, job, grade)
exports['Az-Framework']:AddBridgeMoney(source, account, amount, reason)
exports['Az-Framework']:RemoveBridgeMoney(source, account, amount, reason)
exports['Az-Framework']:GetBridgePlayerSnapshot(source)
exports['Az-Framework']:GetBridgePlayers()
exports['Az-Framework']:BridgeNotify(source, message, type, duration)
```

## Important Client Exports

```lua
exports['Az-Framework']:refreshHUD()
exports['Az-Framework']:updateHUD()
exports['Az-Framework']:hudNotify(payload)
exports['Az-Framework']:IsGameplayReady()
exports['Az-Framework']:GetBridgeClientSnapshot()
```

## Active Character Handling

Selected characters are mirrored into an active-character state so dependent resources can ask Az-Framework which character is currently active instead of guessing from the database.

Use these exports whenever another resource needs character-aware data:

```lua
GetActiveCharacter
GetPlayerCharacter
GetBridgePlayerSnapshot
```

## Installation

1. Import `import.sql`.
2. Make sure `oxmysql` starts before Az-Framework.
3. Add `ensure Az-Framework` to your server config.
4. Start dependent resources after Az-Framework.
5. Review the config files listed above and adjust them for your server.

## GitHub / Repository Notes

- Do not commit live server secrets.
- Do not commit Discord bot tokens or webhooks.
- Do not commit database credentials or FiveM license keys.
- Keep runtime-only data and private config values outside the public repository.

## Troubleshooting

### Character data looks wrong
Use the active-character exports instead of selecting the first or last character from the database.

### External resource cannot read money or jobs
Make sure the resource is using Az-Framework exports and that the player already selected a character.

### vMenu bridge issues
Start Az-Framework before `vMenu-Bridge` and `vMenu`.
