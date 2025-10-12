# 🛡️ AZ Framework – Departments & Economy

## The Lightweight, Discord‑Driven Job & Economy System for FiveM

Az-Framework's **Departments & Economy** module is the powerful, feature-complete core of your roleplay server. It delivers a full-featured job, banking, and administrative permission system designed for performance and ease-of-use.

***

## 🚀 Overview

This module provides all the foundational features necessary to run a persistent, organized, and accountable roleplay environment on your FiveM server.

### 🔍 Core Features at a Glance

| Feature Category | Description |
| :--- | :--- |
| **Department / Job System** | Organize players into distinct jobs (departments) with custom **role‑based permissions**, configurable **paychecks**, and dynamic, **live HUD feedback** on their job status. |
| **Persistent Economy** | Full, centralized banking system. All player cash/bank balances, daily rewards, and financial transactions are stored in **MySQL** with **auto‑generated tables** for minimal setup. |
| **Discord Admin Permissions** | A secure, role-based access system where administrative power is granted based on a player's **Discord roles**, providing a reliable source of truth for staff management. |
| **Webhook‑Powered Logs** | Ensures server accountability. Every financial transaction, admin action, and critical event is recorded instantly via **Discord webhooks**. |
| **Full NUI HUD & Panel** | Features a sleek, modern **NUI (New User Interface)** for in‑game display of a player's job status, current cash/bank, and an integrated interface for administrative tools. |
| **Exportable Utility Functions** | Provides a ready-to-use **API** with export functions that allow other scripts to easily interact with the economy (e.g., to add, deduct, or transfer money). |
| **Character System Support** | Actively developed to include character separation for managing multiple player identities, banking, and names via `user_characters` (as of v2.1.0+). |

***

## ⚙️ Dependencies

This resource is designed to be the foundational layer and requires standard, modern FiveM assets.

| Dependency | Purpose |
| :--- | :--- |
| **oxmysql** | Required for all persistent data storage (economy, jobs, characters). |
| **ox_lib** | Standard library for modern UI, notifications, and client-side utility functions. |

***

## 🔒 Discord Security

For the system's core permissions and logging features, the following Discord credentials are required:

| Credential | Purpose |
| :--- | :--- |
| **`DISCORD_BOT_TOKEN`** | Used by the script to verify a player's administrative roles for access control. |
| **`DISCORD_WEBHOOK_URL`** | Used to push all in-game logs (transactions, bans, job changes) to a dedicated Discord channel. |
| **`DISCORD_GUILD_ID`** | The ID of your main server (guild) used to verify player roles. |





## ⚙️ Exports (API)

The following exports are available for other scripts to interact with the core framework logic.

All functions can be called using the standard FiveM method or the framework's custom shorthand:

1.  **Standard:** `exports['Az-Framework']:ExportName(...)`
2.  **Shorthand:** `Az.ExportName(...)` *(Requires adding `@Az-Framework/init.lua` to your resource manifest)*

> **⚠️ NOTE:** To use the global `Az.` shorthand, you **MUST** include the following file in your calling resource's `fxmanifest.lua` (client or server side, depending on where you call the export):
>
> ```lua
> server_scripts {
>     "@Az-Framework/init.lua",
> }
> ```

---

### Player Data, Identities, and Characters

| Export | Description | Example Usage |
| :--- | :--- | :--- |
| `getPlayerJob(source)` | Returns the job string for the player's active character (or `nil`). | `local job = Az.getPlayerJob(source)` |
| `GetPlayerCharacter(source)` | Returns the active character ID for the player. | `local charId = Az.GetPlayerCharacter(source)` |
| `GetPlayerCharacterName(source, callback)` | **Async:** Resolves the character's name via callback `(err, name)`. | `Az.GetPlayerCharacterName(source, function(err, name) ... end)` |
| `getDiscordID(source)` | Returns the player's Discord numeric ID (no prefix) or an empty string. | `local did = Az.getDiscordID(playerId)` |

### Economy & Money Management

| Export | Description | Example Usage |
| :--- | :--- | :--- |
| `addMoney(source, amount)` | Adds cash to the player's wallet and refreshes the HUD. | `Az.addMoney(32, 5000)` |
| `deductMoney(source, amount)` | Subtracts cash (floored at zero) and notifies the player. | `Az.deductMoney(12, 250)` |
| `depositMoney(source, amount)` | Moves cash to checking account (creates account if missing). | `Az.depositMoney(playerId, 1000)` |
| `withdrawMoney(source, amount)` | Withdraws from checking account to cash (verifies balance). | `Az.withdrawMoney(playerId, 200)` |
| `transferMoney(source, target, amount)` | Transfers cash between two players (both must be linked/online). | `Az.transferMoney(10, 25, 300)` |
| `GetPlayerMoney(source, callback)` | **Async:** Returns `{cash, bank}` via callback `(err, info)`. | `Az.GetPlayerMoney(source, function(err, info) ... end)` |

### Administration and Logging

| Export | Description | Example Usage |
| :--- | :--- | :--- |
| `isAdmin(playerSrc, cb)` | **Async:** Checks Discord roles and calls back with `(true|false)`. | `Az.isAdmin(playerId, function(isAdmin) ... end)` |
| `logAdminCommand(commandName, source, args, success)` | Sends an admin command audit to the configured Discord webhook. | `Az.logAdminCommand('kick', adminSrc, {'123'}, true)` |

### Database Operations (Advanced)

| Export | Description | Example Usage |
| :--- | :--- | :--- |
| `GetMoney(discordID, charID, callback)` | **Async:** Fetches the money row directly. Calls `callback(row)`. | `Az.GetMoney('12345...', 'char1234', function(row) ... end)` |
| `UpdateMoney(discordID, charID, data, cb)` | **Async:** Updates the money row. Calls `cb(affectedRows)`. | `local data = { cash = 100, bank = 500 } Az.UpdateMoney('12345', 'charid', data, function(affected) ... end)` |

### Utilities

| Export | Description | Example Usage |
| :--- | :--- | :--- |
| `sendMoneyToClient(playerId)` | Forces a refresh of the cash/bank HUD for the specified player. | `Az.sendMoneyToClient(playerId)` |
| `claimDailyReward(source, rewardAmount)` | Grants the daily reward if the 24h cooldown has elapsed and updates the database. | `Az.claimDailyReward(playerId, 500)` |
