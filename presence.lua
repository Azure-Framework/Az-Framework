-- ==========================
-- Debug helper
-- ==========================
local DEBUG = true
if type(Config) == "table" and Config.DEBUG == false then DEBUG = false end

local function dbg(...)
  if not DEBUG then return end
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  print("[presence] " .. table.concat(parts, " "))
end

RegisterCommand("presence_debug", function(_, args)
  local a = args[1] and tostring(args[1]):lower() or "toggle"
  if a == "on" then DEBUG = true
  elseif a == "off" then DEBUG = false
  else DEBUG = not DEBUG
  end
  print(("[presence] debug %s"):format(DEBUG and "ENABLED" or "DISABLED"))
end, false)

-- ==========================
-- Citizen.InvokeNative helper (safe)
-- ==========================
local function invokeNativeSafe(hash, ...)
  if type(Citizen) ~= "table" or type(Citizen.InvokeNative) ~= "function" then
    return false, "Citizen.InvokeNative not available"
  end
  local ok, res = pcall(Citizen.InvokeNative, hash, ...)
  if ok then return true, res end
  return false, tostring(res)
end

-- ==========================
-- Native availability helper
-- ==========================
local function nativeAvailable(name)
  return type(_G[name]) == "function"
end

local HASH_SET_DISCORD_APP_ID = 0x6A02254D
local HASH_SET_RICH_PRESENCE = 0x7BDCBD45
local HASH_SET_DISCORD_RICH_PRESENCE_ASSET = 0x53DFD530

local function trySetAppId(id)
  if not id or id == "" then
    dbg("No DISCORD_APP_ID provided; skipping SetDiscordAppId.")
    return false
  end

  if nativeAvailable("SetDiscordAppId") then
    local ok, err = pcall(SetDiscordAppId, tostring(id))
    if ok then
      dbg("SetDiscordAppId called (%s)", tostring(id))
      return true
    else
      dbg("SetDiscordAppId error:", tostring(err))
    end
  end

  local succ, info = invokeNativeSafe(HASH_SET_DISCORD_APP_ID, tostring(id))
  if succ then
    dbg("SetDiscordAppId via InvokeNative called (%s)", tostring(id))
    return true
  end

  dbg("SetDiscordAppId: no working native (fallback info: " .. tostring(info) .. ")")
  return false
end

local function trySetPresence(str)
  if not str or str == "" then
    dbg("trySetPresence called with empty string; skipping.")
    return false
  end
  if nativeAvailable("SetDiscordRichPresence") then
    local ok, err = pcall(SetDiscordRichPresence, tostring(str))
    if ok then dbg("SetDiscordRichPresence called."); return true
    else dbg("SetDiscordRichPresence error:", tostring(err)) end
  end


  if nativeAvailable("SetRichPresence") then
    local ok, err = pcall(SetRichPresence, tostring(str))
    if ok then dbg("SetRichPresence called."); return true
    else dbg("SetRichPresence error:", tostring(err)) end
  end


  local succ, info = invokeNativeSafe(HASH_SET_RICH_PRESENCE, tostring(str))
  if succ then dbg("SetRichPresence via InvokeNative called."); return true end

  dbg("trySetPresence failed; no working native (info: " .. tostring(info) .. ")")
  return false
end

local function trySetPresenceAsset(assetName)
  if not assetName or assetName == "" then
    dbg("trySetPresenceAsset called with empty asset; skipping.")
    return false
  end

  if nativeAvailable("SetDiscordRichPresenceAsset") then
    local ok, err = pcall(SetDiscordRichPresenceAsset, tostring(assetName))
    if ok then dbg("SetDiscordRichPresenceAsset called: " .. tostring(assetName)); return true
    else dbg("SetDiscordRichPresenceAsset error:", tostring(err)) end
  end

  -- Fallback: use known hash if available
  local succ, info = invokeNativeSafe(HASH_SET_DISCORD_RICH_PRESENCE_ASSET, tostring(assetName))
  if succ then dbg("SetDiscordRichPresenceAsset via InvokeNative called: " .. tostring(assetName)); return true end

  dbg("trySetPresenceAsset failed; native missing or fallback failed (" .. tostring(info) .. ")")
  return false
end

local function trySetPresenceAssetSmall(assetName)
  if not assetName or assetName == "" then
    dbg("trySetPresenceAssetSmall called with empty asset; skipping.")
    return false
  end
  if nativeAvailable("SetDiscordRichPresenceAssetSmall") then
    local ok, err = pcall(SetDiscordRichPresenceAssetSmall, tostring(assetName))
    if ok then dbg("SetDiscordRichPresenceAssetSmall called: " .. tostring(assetName)); return true
    else dbg("SetDiscordRichPresenceAssetSmall error:", tostring(err)) end
  end
  -- no widely-known small-asset hash; skip fallback
  dbg("SetDiscordRichPresenceAssetSmall native not exposed; skipping.")
  return false
end

local function trySetPresenceAssetSmallText(text)
  if not text then text = "" end
  if nativeAvailable("SetDiscordRichPresenceAssetSmallText") then
    local ok, err = pcall(SetDiscordRichPresenceAssetSmallText, tostring(text))
    if ok then dbg("SetDiscordRichPresenceAssetSmallText called."); return true
    else dbg("SetDiscordRichPresenceAssetSmallText error:", tostring(err)) end
  end
  if nativeAvailable("SetDiscordRichPresenceAssetSmallText") == false then
    dbg("SetDiscordRichPresenceAssetSmallText native not exposed; skipping.")
  end
  return false
end

local function trySetPresenceAssetText(text)
  if not text then text = "" end
  if nativeAvailable("SetDiscordRichPresenceAssetText") then
    local ok, err = pcall(SetDiscordRichPresenceAssetText, tostring(text))
    if ok then dbg("SetDiscordRichPresenceAssetText called."); return true
    else dbg("SetDiscordRichPresenceAssetText error:", tostring(err)) end
  end
  dbg("SetDiscordRichPresenceAssetText native not exposed; skipping.")
  return false
end

-- ==========================
-- Safe coord + info readers
-- ==========================
local function safeGetCoords()
  local ok, x, y, z = pcall(function()
    local ped = PlayerPedId()
    if not ped or ped == 0 then return 0.0, 0.0, 0.0 end
    local v = GetEntityCoords(ped, false)
    if type(v) == "vector3" then
      return v.x or 0.0, v.y or 0.0, v.z or 0.0
    elseif type(v) == "table" then
      return v[1] or v.x or 0.0, v[2] or v.y or 0.0, v[3] or v.z or 0.0
    else
      local x2, y2, z2 = GetEntityCoords(ped, false)
      return x2 or 0.0, y2 or 0.0, z2 or 0.0
    end
  end)
  if ok and x and y and z then return x, y, z end
  return 0.0, 0.0, 0.0
end

local function getStreetAndZone()
  local x, y, z = safeGetCoords()
  local street = "Unknown"
  local ok, s1, s2 = pcall(GetStreetNameAtCoord, x, y, z)
  if ok and s1 and s1 ~= 0 then
    local name = GetStreetNameFromHashKey(s1)
    if name and name ~= "" then street = name end
  elseif ok and s2 and s2 ~= 0 then
    local name = GetStreetNameFromHashKey(s2)
    if name and name ~= "" then street = name end
  end
  local zoneName = GetNameOfZone(x, y, z) or "UNKNOWN"
  local label = GetLabelText(zoneName)
  if (not label) or label == "NULL" or label == "" then label = zoneName end
  return street, label
end



local function getMovementAndVehicleInfo()
  local ped = PlayerPedId()
  if not ped or ped == 0 then return "Idle", false, 0, false end

  if IsPedInAnyVehicle(ped, false) then
    local veh = GetVehiclePedIsIn(ped, false)

    -- speed (m/s -> mph)
    local speedMs = 0
    do
      local ok, s = pcall(GetEntitySpeed, veh)
      if ok and type(s) == "number" then speedMs = s end
    end
    local speedMph = math.floor(speedMs * 2.236936 + 0.5)

    -- siren (pcall)
    local siren = false
    do
      local ok, v = pcall(IsVehicleSirenOn, veh)
      if ok and type(v) == "boolean" then siren = v end
    end

    -- lights state fallback (pcall). GetVehicleLightsState can return different values depending on build.
    local emergencyLights = false
    do
      local ok, lightsState = pcall(GetVehicleLightsState, veh)
      if ok and type(lightsState) == "number" then
        if lightsState ~= 0 then emergencyLights = true end
      end
    end

    -- vehicle class check: Emergency class is 18
    local isEmergencyClass = false
    do
      local ok, cls = pcall(GetVehicleClass, veh)
      if ok and type(cls) == "number" and cls == 18 then
        isEmergencyClass = true
      end
    end

    -- Final lights-on logic: only show lights ON for emergency-class vehicles with siren or lights
    local lightsOn = false
    if isEmergencyClass and (siren or emergencyLights) then
      lightsOn = true
    end

    return "Driving", true, speedMph, lightsOn
  else
    -- on foot
    local speedMs = 0
    do
      local ok, s = pcall(GetEntitySpeed, ped)
      if ok and type(s) == "number" then speedMs = s end
    end
    local state = "Idle"
    if speedMs < 1.0 then state = "Idle"
    elseif speedMs < 3.0 then state = "Walking"
    else state = "Running" end
    return state, false, 0, false
  end
end


-- ==========================
-- Presence builder + API (framework-free)
-- ==========================
local _lastPresence = nil
local _externalPresence = nil
local _jobLabel = nil

local function buildPresence()
  if _externalPresence and _externalPresence ~= "" then return tostring(_externalPresence) end

  local ok, street, zone = pcall(getStreetAndZone)
  if not ok then dbg("getStreetAndZone failed; using Unknown"); street, zone = "Unknown", "UNKNOWN" end

  local movement, inVehicle, speed, siren = getMovementAndVehicleInfo()
  local emojis = (Config and Config.EMOJIS) or {}

  local moveEmoji = emojis.idle or "🧍"
  if movement == "Driving" then moveEmoji = emojis.driving or "🚗"
  elseif movement == "Walking" then moveEmoji = emojis.walking or "🚶"
  elseif movement == "Running" then moveEmoji = emojis.running or "🏃" end

  local lightsEmoji = siren and (emojis.lights_on or "🚨") or (emojis.lights_off or "🔕")
  local jobPart = (Config and Config.SHOW_JOB and _jobLabel) and (" • " .. _jobLabel) or ""

  local details = string.format("%s %s on %s%s", moveEmoji, movement, street or "Unknown", jobPart)
  local speedPart = inVehicle and (string.format(" • %s %d mph", emojis.speed or "💨", speed)) or ""
  local lightsPart = string.format(" %s %s", lightsEmoji, siren and "Lights ON" or "Lights OFF")
  local server = (Config and Config.SERVER_NAME) and Config.SERVER_NAME or "Server"
  local state = string.format("%s %s%s%s • %s", (emojis.zone or "📌"), zone or "UNKNOWN", lightsPart, speedPart, server)

  local combined = details .. " — " .. state
  if #combined > 120 then combined = combined:sub(1, 120) end
  return combined
end

-- Exports / events
function RefreshDiscordPresence()
  local ok, text = pcall(buildPresence)
  if ok and text then
    local succ = trySetPresence(text)
    if succ then
      _lastPresence = text
      dbg("RefreshPresence: %s", text)
      return true
    else
      dbg("RefreshPresence: native failed; presence not set on Discord.")
      return false
    end
  end
  dbg("RefreshPresence failed or returned nil.")
  return false
end
exports("RefreshDiscordPresence", RefreshDiscordPresence)

function SetDiscordPresenceOverride(txt)
  _externalPresence = txt and tostring(txt) or nil
  dbg("External presence override set:", tostring(_externalPresence))
  if _externalPresence and _externalPresence ~= "" then
    local succ = trySetPresence(_externalPresence)
    if succ then _lastPresence = _externalPresence end
  else
    RefreshDiscordPresence()
  end
end
exports("SetDiscordPresenceOverride", SetDiscordPresenceOverride)

function SetDiscordJob(jobLabel)
  if jobLabel == nil or jobLabel == "" then
    _jobLabel = nil
    dbg("Job label cleared.")
  else
    _jobLabel = tostring(jobLabel)
    dbg("Job label set:", _jobLabel)
  end
  RefreshDiscordPresence()
end
exports("SetDiscordJob", SetDiscordJob)

RegisterNetEvent("presence:setJob")
AddEventHandler("presence:setJob", function(jobLabel) SetDiscordJob(jobLabel) end)

-- Optional asset setup (call once after app id if you want to show assets):
local function trySetupAssets()
  if not Config then return end
  if Config.ASSET_LARGE then trySetPresenceAsset(Config.ASSET_LARGE) end
  if Config.ASSET_SMALL then trySetPresenceAssetSmall(Config.ASSET_SMALL) end
  if Config.ASSET_SMALL_TEXT then trySetPresenceAssetSmallText(Config.ASSET_SMALL_TEXT) end
  if Config.ASSET_TEXT then trySetPresenceAssetText(Config.ASSET_TEXT) end
end

-- Commands
RegisterCommand("presence_status", function()
  local ok, text = pcall(buildPresence)
  if ok and text then print("[presence] current presence: " .. tostring(text)) else print("[presence] buildPresence failed or returned nil") end
end, false)

RegisterCommand("presence_forceupdate", function() RefreshDiscordPresence() end, false)

-- ==========================
-- Main loop
-- ==========================
Citizen.CreateThread(function()
  if type(PlayerPedId) ~= "function" then
    print("[presence] PlayerPedId is NOT a function (script running server-side). Move file to client_scripts.")
    return
  end

  if type(Config) == "table" and Config.DEBUG == false then DEBUG = false end
  dbg("Presence script starting. DEBUG=" .. tostring(DEBUG))

  -- Try to set App ID (named native or hash fallback)
  local appOk = trySetAppId(Config and Config.DISCORD_APP_ID)
  if not appOk then dbg("App ID not set via native; presence may not display without a valid app id.") end

  -- Try optional assets (will no-op gracefully if natives not exposed)
  trySetupAssets()

  local interval = (Config and tonumber(Config.UPDATE_INTERVAL)) or 5
  if interval < 3 then interval = 3 end
  local waitMs = interval * 1000

  while true do
    local ok, text = pcall(buildPresence)
    if ok and text then
      if text ~= _lastPresence then
        local succ = trySetPresence(text)
        if succ then
          dbg("Presence set:", text)
          _lastPresence = text
        else
          dbg("Presence NOT set (native missing or error). Will retry next interval.")
        end
      else
        dbg("Presence unchanged; skipping native call.")
      end
    else
      dbg("Presence build failed or returned nil; skipping set.")
    end
    Citizen.Wait(waitMs)
  end
end)
