local RESOURCE_NAME = GetCurrentResourceName()
Config = Config or {}

local function getCutsceneCfg()
  local cfg = Config.IntroCutscene or {}
  cfg.StateFile = tostring(cfg.StateFile or "characterui/cutscene_seen.json")
  return cfg
end

local function getDiscordID(src)
  local ids = GetPlayerIdentifiers(src) or {}
  for _, id in ipairs(ids) do
    if type(id) == "string" and id:sub(1, 8) == "discord:" then
      return id:sub(9)
    end
  end
  for _, id in ipairs(ids) do
    if type(id) == "string" and id:match("^%d+$") then
      return id
    end
  end
  return ""
end

local function dprint(fmt, ...)
  local cfg = getCutsceneCfg()
  if cfg.Debug ~= true then return end
  local ok, msg = pcall(string.format, fmt, ...)
  print(("^5[%s cutscene]^7 %s"):format(RESOURCE_NAME, ok and msg or tostring(fmt)))
end

local introState = { seen = {} }

local function encodeState()
  local ok, out = pcall(json.encode, introState)
  if not ok or type(out) ~= "string" or out == "" then
    return '{"seen":{}}'
  end
  return out
end

local function saveState()
  local cfg = getCutsceneCfg()
  SaveResourceFile(RESOURCE_NAME, cfg.StateFile, encodeState(), -1)
end

local function loadState()
  local cfg = getCutsceneCfg()
  local raw = LoadResourceFile(RESOURCE_NAME, cfg.StateFile)
  if type(raw) ~= "string" or raw == "" then
    introState = { seen = {} }
    saveState()
    return
  end

  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == "table" then
    decoded.seen = type(decoded.seen) == "table" and decoded.seen or {}
    introState = decoded
    return
  end

  introState = { seen = {} }
  saveState()
end

local function hasSeenIntro(discordId)
  if discordId == "" then return false end
  local entry = introState.seen and introState.seen[tostring(discordId)]
  if type(entry) == "table" then
    return entry.seen == true
  end
  return entry == true
end

local function markSeenIntro(discordId, meta)
  discordId = tostring(discordId or "")
  if discordId == "" then return false end
  introState.seen = introState.seen or {}
  introState.seen[discordId] = {
    seen = true,
    playedAt = os.time(),
    name = tostring((meta and meta.name) or ""),
    charid = tostring((meta and meta.charid) or ""),
  }
  saveState()
  return true
end

AddEventHandler("onResourceStart", function(res)
  if res ~= RESOURCE_NAME then return end
  loadState()
end)

if lib and lib.callback and type(lib.callback.register) == "function" then
  lib.callback.register("azfw:intro:shouldPlay", function(src, context)
    local cfg = getCutsceneCfg()
    if cfg.Enabled ~= true then
      return { play = false, reason = "disabled" }
    end

    local did = tostring(getDiscordID(src) or "")
    if did == "" then
      return { play = false, reason = "no_discord" }
    end

    local ctx = type(context) == "table" and context or {}
    local mode = tostring(ctx.mode or "ui")
    local isNewCharacter = ctx.isNewCharacter == true

    if mode == "ui" and cfg.RequireNewCharacterInCharacterUi ~= false and not isNewCharacter then
      return { play = false, reason = "not_new_character", discordId = did }
    end

    if mode ~= "ui" and cfg.AllowInDiscordMode ~= true then
      return { play = false, reason = "discord_mode_disabled", discordId = did }
    end

    if cfg.OnlyFirstJoinPerDiscord ~= false and hasSeenIntro(did) then
      return { play = false, reason = "already_seen", discordId = did }
    end

    return {
      play = true,
      discordId = did,
      reason = "ok",
      showDeathScreenAfter = cfg.ShowSpawnDeathScreenAfter ~= false,
    }
  end)
end

RegisterNetEvent("azfw:intro:markSeen", function(meta)
  local src = source
  local did = tostring(getDiscordID(src) or "")
  if did == "" then return end
  markSeenIntro(did, meta)
  dprint("marked seen did=%s charid=%s", did, tostring(type(meta) == "table" and meta.charid or ""))
end)
