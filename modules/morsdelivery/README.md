# nv_morsmutual — Mors Mutual-style Insurance Delivery (AI drives your car to you)

## What it does
- `/mors` or `/insurance` opens a NUI “Mors Mutual” panel
- Lists vehicles owned by the player from your MySQL table (`user_vehicles`)
- Player selects a **parked** vehicle to “Call”
- Plays **in-game phone audio**
- Spawns the vehicle at a **random road node** far away
- Spawns a **valet/driver ped** that **AI drives it to the player**
- Creates a blip + GPS route to the delivered vehicle
- Marks the vehicle as **unparked** in DB (`parked=0`) and updates `x,y,z,h` to its spawn coords

---

## 1) Requirements
- OneSync (recommended; most servers already run it)
- A MySQL resource:
  - **oxmysql** (recommended), or mysql-async, or ghmattimysql

---

## 2) IMPORTANT: Add a `parked` column
Your table schema doesn’t include `parked`, but you requested “mark as unparked”.

This resource can **auto-migrate** it on start if `Config.AutoMigrateParkedColumn = true` and the DB user has ALTER permissions.

Manual SQL (safe):
```sql
ALTER TABLE user_vehicles
  ADD COLUMN parked TINYINT(1) NOT NULL DEFAULT 1;
```

- `parked=1` = stored/parked (callable)
- `parked=0` = unparked/out (NOT callable)

---

## 3) Install
1. Drop folder `nv_morsmutual` into your `resources/` folder
2. Ensure your MySQL resource is started **before** this script
3. Add to server.cfg:
```
ensure oxmysql
ensure nv_morsmutual
```

---

## 4) Configure (config.lua)
Key settings:
- `Config.DB_TABLE` (supports `schema.table`)
- `Config.DB_OWNER_COLUMN` (your schema uses `discordid`)
- `Config.IdentifierType = 'discord'` (reads identifier `discord:XXXX` and stores **only the numeric** part to match your DB)
- `Config.MySQL = 'oxmysql'`

---

## 5) Notes / Tips
- If players don’t have `discord:` identifiers:
  - Make sure `sv_authMaxVariance`/discord not blocked,
  - Discord app open, and you didn’t disable it.
  - The script will fallback to `license:` if discord is missing, but your DB is discord-based by default.

- If your vehicle “mods” JSON format is custom, edit `applyVehicleProps()` in `client.lua` to match it.

---

## Commands
- `/mors`
- `/insurance`

Enjoy.
