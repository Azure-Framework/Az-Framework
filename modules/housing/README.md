# az_housing

Housing / Apartment script for FiveM with **routing bucket interiors**, **knocking**, **police breach**, **sales + rentals portal**, **agent portal**, and **placeable doors & garages**.

**Tech:** ox_lib + ox_target + oxmysql (with an **az-econ** money adapter built in)

---

## Features
- Instanced interiors using **routing buckets** (shared interior coords, unique bucket per house).
- Door interaction (enter / lock / knock).
- Police breach (temporary forced unlock + forced entry).
- Clean NUI portal (dark glass theme) for:
  - Browse properties (for sale / for rent)
  - My properties
  - My rentals
  - Agent portal (approve/deny rental applications)
  - **Property Manager** (Mailbox, Upgrades, Furniture)
- Garages per house (placeable), store/retrieve vehicles.
- Blips + names on map for each house.
- **Mailbox system** (messages persisted per house).
- **Upgrades system** (mailbox capacity, decor/furniture limits, storage tiers).
- **Furniture placement** (ghost placement mode, persisted & reloaded on entry).
- Admin placement commands to create houses and place doors/garages nearly anywhere.

---

## Dependencies
- **ox_lib**
- **ox_target**
- **oxmysql**

---

## Installation
1) Import SQL:
- Run `sql/install.sql` in your database.

2) Add to `server.cfg` (start order):
```cfg
ensure oxmysql
ensure ox_lib
ensure ox_target
ensure az_housing
```

3) Configure `config.lua`:
- Set `Config.Money.Mode` (default **az-econ**)
- Configure job names for **police** and **real-estate agents**
- Add/edit interiors in `Config.Interiors`

---

## Money (az-econ)
By default, this resource uses **az-econ**.

`shared/money.lua` tries several common export names automatically:
- Take: `RemoveMoney`, `TakeMoney`, `removeMoney`, etc.
- Give: `AddMoney`, `GiveMoney`, `addMoney`, etc.

If your az-econ uses different exports, update the adapter in `shared/money.lua` or switch `Config.Money.Mode`.

---

## Player Usage
- Use target interactions at **doors** and **garages**.
- Use **Housing Portal** target option or `/housing` to open the NUI.
- **Mailbox** is available from the door target option or inside the Property Manager.
- **Furniture placement**:
  - Open Property Manager → Furniture → pick an item → **Start Placement**
  - Controls shown on screen (confirm/cancel/rotate/raise).

---

## Admin Placement
Requires ACE:
```cfg
add_ace group.admin az_housing.admin allow
```

Commands:
- `/housingedit` – opens admin placement menu
  - Create house
  - Place door (entrance)
  - Place garage
  - Delete house

Tip: Stand where you want the **door** / **garage** and run the menu option.

---

## Notes
- Interiors are shared coordinates, but separated by routing buckets so players only see others inside the same property.
- Garage storage uses `ox_lib` vehicle properties. It saves to DB and re-spawns at the configured garage spawn.
- Add more interiors in `Config.Interiors` and assign them per house.

---

## Roadmap Ideas
Easy additions on top of this base:
- stash/inventory integration
- wardrobe integration
- billing scheduler for weekly rent
- doorlock integration
- realtor commissions

