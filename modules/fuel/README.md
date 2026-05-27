# Az-FuelPump – Simple Fuel System & Pump Interaction (FiveM)

Az-FuelPump is a lightweight fuel system that:

- Monitors a vehicle's fuel level using GTA's native fuel functions.
- Shows a small on-screen fuel HUD while driving.
- Adds interactive fuel pumps placed around the map.
- Lets players:
  - Park near a pump.
  - Get out and press **E** at the pump to grab the nozzle.
  - Walk to their vehicle and press **E** to attach the nozzle.
  - Press **SPACE** to start fueling.
  - Automatically stop fueling when the tank is full.
  - Then walk back to the pump and press **E** again to hang up the nozzle.

No external framework is required. You can expand it later to charge money using your own framework exports.

---

## Installation

1. Drop the folder into your `resources` directory, e.g.:

   ```text
   resources/[az]/az_fuelpump
   ```

2. Add the resource to your server config:

   ```text
   ensure az_fuelpump
   ```

3. Restart your server.

---

## Usage In-Game

1. **Driving & fuel drain**
   - Get in any vehicle and drive.
   - Fuel drains slowly over time based on speed:
     - Idle / barely moving
     - Normal driving
     - High speed
   - When fuel reaches **0**, the engine shuts off.

2. **Fuel HUD**
   - While you are the **driver**, a small HUD line shows:
     - `Fuel: XX%` near the radar (or top-left if configured).
   - You can tweak the HUD position and alignment in `config.lua`.

3. **Refueling at pumps**
   - Drive to one of the configured pumps (see `Config.Pumps`).
   - Park the vehicle within hose distance of the pump.
   - Get out of the vehicle.
   - Near the pump, press **E** to pick up the nozzle.
   - Walk to your vehicle and press **E** again to attach the nozzle to the car.
   - Press **SPACE** to start fueling.
   - The vehicle's fuel level will increase automatically.
   - Fueling stops if:
     - The tank is full.
     - You press **SPACE** again to cancel.
     - The vehicle moves too far from the pump (hose stretch).
   - After fueling, the nozzle is back in your hand.
   - Walk back to the pump and press **E** to hang up the nozzle.

---

## Configuration

All tunables live in **`config.lua`**:

- **Fuel behavior**
  - `Config.MaxFuel` – max fuel level (default `100.0`).
  - `Config.FuelDrainIdle` – per-second fuel drain when almost not moving.
  - `Config.FuelDrainDriving` – normal driving drain.
  - `Config.FuelDrainHighSpeed` – high-speed drain.
  - `Config.FuelTickInterval` – how often the script updates (ms).

- **Pump behavior**
  - `Config.FuelPerSecondAtPump` – how fast fuel is added while fueling.
  - `Config.MaxPumpDistance` – how close you must stand to use a pump.
  - `Config.MaxVehicleDistance` – how close the vehicle must be to attach the nozzle.
  - `Config.MaxHoseStretch` – maximum allowed distance between pump and vehicle before fueling stops.

- **HUD**
  - `Config.EnableHUD` – toggle HUD on/off.
  - `Config.HUD.alignRight` – draw near radar (true) or top-left (false).
  - `Config.HUD.offsetX / offsetY` – fine-tune HUD position.

- **Pumps & models**
  - `Config.HoseModel` – change this to any nozzle-style model you like.
  - `Config.PumpModels` – a list of pump models if you want to use them for future auto-detection logic.
  - `Config.Pumps` – list of pump `coords` and `heading` for interaction.
    - Add, move, or delete entries to match your map.
  - `Config.ShowPumpMarkers` – if `true`, small markers appear over pumps.
    - Useful for testing; you can disable it later.

- **Keybinds**
  - `Config.Keys.Use` – label used in help text for picking up / attaching / hanging up.
  - `Config.Keys.Start` – label used in help text for starting / stopping fueling.

---

## Notes & Tips

- The resource uses **`GetVehicleFuelLevel`** and **`SetVehicleFuelLevel`** natives.
  - Most vehicles start with fuel level `0`. The first time a player drives a vehicle, this script will give it a default fuel (75%) so you don't spawn with an empty tank.
- All logic is client-side for simplicity.
  - If you want **economy integration**:
    - Add a server event that charges the player per liter / per second of fueling using your framework's money exports.
    - Only start fueling if the charge succeeds.
- If you add custom pump MLOs:
  - Simply add new entries to `Config.Pumps` with their XYZ and heading.

---

## Files

- `fxmanifest.lua` – standard FiveM manifest.
- `config.lua` – all configurable options.
- `client.lua` – fuel logic, HUD, pump & nozzle interactions.
- `server.lua` – light debug + placeholder for future persistence / billing.

Enjoy!
