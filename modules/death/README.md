# Az-Death (missing files pack)

This pack adds the typical missing root files for the provided `Az-Death.rar`:
- `fxmanifest.lua`
- `config.lua`

## How to use
1. Extract your `Az-Death.rar` on your PC.
2. Copy **these** files into the root `Az-Death/` folder (same level as `html/` and `source/`).
3. Ensure your folder structure looks like:

```
Az-Death/
  fxmanifest.lua
  config.lua
  html/
    index.html
  source/
    clie/
      client.lua
    veh/
      client.lua
    serv/
      server.lua
```

4. Add to `server.cfg`:
```
ensure Az-Death
```

## Notes
- If your scripts require `ox_lib`, uncomment the `@ox_lib/init.lua` line in `fxmanifest.lua`.
- If your scripts require `oxmysql`, uncomment the `@oxmysql/lib/MySQL.lua` line in `fxmanifest.lua`.
