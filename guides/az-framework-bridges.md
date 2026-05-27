# Az-Framework Bridge Guide

Az-Framework bridge resources live in the KSRP-Core folder locally and are published as standalone bridge repositories in the Azure-Framework GitHub organization.

Docs: https://madebyazure.com/framework/  
Discord: https://discord.gg/tBg2U6CTHE

## Bridge Repositories

| Repo | Runtime resource | Purpose |
| --- | --- | --- |
| `Az-QBCore-Bridge` | `qb-core` | QBCore object, player, job, money, metadata compatibility |
| `Az-QBInventory-Bridge` | `qb-inventory` | qb-inventory compatibility on top of Az-Framework inventory/player data |
| `Az-QBTarget-Bridge` | `qb-target` | qb-target style targeting compatibility |
| `Az-ESX-Bridge` | `es_extended` | ESX Legacy API compatibility |
| `Az-NDCore-Bridge` | `ND_Core` | ND_Core style player/framework compatibility |

## Start Order

```cfg
ensure oxmysql
ensure ox_lib
ensure Az-Framework
ensure qb-core
ensure qb-inventory
ensure qb-target
ensure es_extended
ensure ND_Core
```

Start legacy resources after the bridge they expect.

<details>
<summary>QBCore resources</summary>

Use `Az-QBCore-Bridge` when a resource expects `exports['qb-core']:GetCoreObject()` or common QBCore player/job/money functions.

The runtime folder must be named `qb-core`.

</details>

<details>
<summary>Inventory resources</summary>

Use `Az-QBInventory-Bridge` when a resource expects `qb-inventory` events, exports, or item lookups.

For ox_inventory-first servers, keep ox_inventory started before inventory-dependent resources and only enable the bridge for resources that need the qb-inventory surface.

</details>

<details>
<summary>Target resources</summary>

Use `Az-QBTarget-Bridge` when a resource expects qb-target exports. It should start after `ox_target` and before qb-target-dependent scripts.

</details>

<details>
<summary>ESX and ND resources</summary>

Use `Az-ESX-Bridge` for resources looking for `es_extended`.

Use `Az-NDCore-Bridge` for resources looking for `ND_Core`.

Start only the bridge layers your server actually needs.

</details>
