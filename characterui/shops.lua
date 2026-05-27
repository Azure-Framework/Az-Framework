local json = json
local RESOURCE_NAME = GetCurrentResourceName()

local Config = {
  UseAppearance = true,
  Price = 250,
  Key = 38,
  InteractDistance = 2.0,
  MarkerDistance = 25.0,
  MarkerType = 1,
  MarkerScale = vector3(1.0, 1.0, 1.0),
  MarkerColor = { r = 0, g = 150, b = 255, a = 180 },
  TextZOffset = 1.0,

  AutoOpenCustomizationIfMissing = false,
  AutoOpenDelayMs = 1200,
  AutoOpenFree = true,

  EnableCustomizationCommand = true,
  CustomizationCommand = "customization",

  Blips = {
    Enabled = true,
    Sprite = 73,
    Color  = 47,
    Scale  = 0.8
  },

  Shops = {
    { label = "Clothing Store", coords = vector3(72.3, -1399.1, 29.4) },
    { label = "Clothing Store", coords = vector3(-703.8, -152.3, 37.4) },
    { label = "Clothing Store", coords = vector3(-167.9, -299.0, 39.7) },
    { label = "Clothing Store", coords = vector3(425.6, -806.3, 29.5) },
    { label = "Clothing Store", coords = vector3(-822.4, -1073.7, 11.3) },
    { label = "Clothing Store", coords = vector3(-1193.4, -772.3, 17.3) },
    { label = "Clothing Store", coords = vector3(11.6, 6514.2, 31.9) },
    { label = "Clothing Store", coords = vector3(1696.3, 4829.3, 42.1) },
    { label = "Clothing Store", coords = vector3(125.8, -223.8, 54.6) },
    { label = "Clothing Store", coords = vector3(614.2, 2761.1, 42.1) },
    { label = "Clothing Store", coords = vector3(1190.6, 2713.4, 38.2) },
  }
}

local currentCharId = nil

local pending = {
  active = false,
  appearance = nil,
  startedAt = 0
}

local isCustomizing = false
local lastSentAppearanceJson = nil
local lastSentAt = 0

local missingAppearance = {}
local autoOpenedFor = {}

local function feed(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, true)
end

local function fa()
  return exports and exports["fivem-appearance"]
end

local function customizationAvailable()
  if GetResourceState("fivem-appearance") ~= "started" then return false end
  return (GetConvarInt("fivem-appearance:customization", 0) == 1)
end

local function warnCustomizationDisabled()
  print(("[%s][clothing] fivem-appearance customization disabled/missing. Enable in server.cfg: setr fivem-appearance:customization 1")
    :format(RESOURCE_NAME))
  feed("~r~Customization disabled.~s~ Set ~y~fivem-appearance:customization 1~s~ in server.cfg.")
end

local function getAppearanceKvpKey(charId)
  if not charId then return nil end
  return ("azfw_char_appearance_%s"):format(tostring(charId))
end

local function saveAppearanceKvp(charId, appearance)
  if not charId or type(appearance) ~= "table" then return false end
  local key = getAppearanceKvpKey(charId)
  if not key then return false end

  local ok, encoded = pcall(function() return json.encode(appearance) end)
  if not ok or type(encoded) ~= "string" or encoded == "" then return false end

  SetResourceKvp(key, encoded)
  return true
end

local function applyAppearance(appearance)
  if type(appearance) ~= "table" then return false end
  local e = fa()
  if not e then return false end

  local ok = pcall(function()
    e:setPlayerAppearance(appearance)
  end)

  return ok and true or false
end

local function getAppearanceSnapshot()
  local e = fa()
  if not e then return nil end

  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return nil end

  local ap = nil
  if e.getPedAppearance then
    local ok, v = pcall(function() return e:getPedAppearance(ped) end)
    if ok and type(v) == "table" then ap = v end
  end

  ap = ap or {}

  if ap.model == nil and e.getPedModel then pcall(function() ap.model = e:getPedModel(ped) end) end
  if type(ap.components) ~= "table" and e.getPedComponents then pcall(function() ap.components = e:getPedComponents(ped) end) end
  if type(ap.props) ~= "table" and e.getPedProps then pcall(function() ap.props = e:getPedProps(ped) end) end
  if ap.headBlend == nil and e.getPedHeadBlend then pcall(function() ap.headBlend = e:getPedHeadBlend(ped) end) end
  if ap.faceFeatures == nil and e.getPedFaceFeatures then pcall(function() ap.faceFeatures = e:getPedFaceFeatures(ped) end) end
  if ap.headOverlays == nil and e.getPedHeadOverlays then pcall(function() ap.headOverlays = e:getPedHeadOverlays(ped) end) end
  if ap.hair == nil and e.getPedHair then pcall(function() ap.hair = e:getPedHair(ped) end) end
  if ap.tattoos == nil and e.getPedTattoos then pcall(function() ap.tattoos = e:getPedTattoos(ped) end) end

  local hasSomething = false
  for _ in pairs(ap) do hasSomething = true break end
  return hasSomething and ap or nil
end

local function applyThenSnapshot(appearance)
  if type(appearance) ~= "table" then return nil end
  applyAppearance(appearance)
  Wait(0)
  applyAppearance(appearance)
  Wait(60)
  local snap = getAppearanceSnapshot()
  return snap or appearance
end

local function saveAppearanceToServerWith(appearance, reason, force)
  if not currentCharId then
    print(("[%s][clothing] save blocked: no currentCharId (%s)"):format(RESOURCE_NAME, tostring(reason)))
    return false
  end
  if type(appearance) ~= "table" then return false end

  local ok, encoded = pcall(function() return json.encode(appearance) end)
  if not ok or type(encoded) ~= "string" or encoded == "" then return false end

  local now = GetGameTimer()
  if not force then
    if encoded == lastSentAppearanceJson then return false end
    if (now - lastSentAt) < 15000 then return false end
  end

  lastSentAppearanceJson = encoded
  lastSentAt = now

  TriggerServerEvent("azfw:appearance:save", tostring(currentCharId), encoded)
  saveAppearanceKvp(currentCharId, appearance)

  print(("[%s][clothing] saved cid=%s bytes=%d reason=%s"):format(
    RESOURCE_NAME, tostring(currentCharId), #encoded, tostring(reason or "unknown")
  ))

  return true
end

local function saveAppearanceToServer(reason, force)
  if not currentCharId then return false end
  if pending.active then return false end
  if isCustomizing then return false end

  local ap = getAppearanceSnapshot()
  if not ap then return false end
  return saveAppearanceToServerWith(ap, reason, force and true or false)
end

local function setCurrentCharId(charid, reason)
  if not charid then return end
  currentCharId = tostring(charid)
  print(("[%s][clothing] currentCharId=%s (%s)"):format(RESOURCE_NAME, tostring(currentCharId), tostring(reason or "event")))
end

RegisterNetEvent("az-fw-money:characterSelected", function(charid)
  setCurrentCharId(charid, "az-fw-money:characterSelected")
end)

RegisterNetEvent("azfw:character_confirmed", function(charid)
  setCurrentCharId(charid, "azfw:character_confirmed")
end)

RegisterNetEvent("azfw:receive_active_character", function(charid)
  setCurrentCharId(charid, "azfw:receive_active_character")
end)

RegisterNetEvent("azfw:activeAppearance", function(charid, appearanceJsonOrNil)
  if charid == nil or tostring(charid) == "" then
    print(("[%s][clothing] activeAppearance ignored (no active char yet)"):format(RESOURCE_NAME))
    return
  end

  setCurrentCharId(charid, "azfw:activeAppearance")

  local cid = tostring(currentCharId)
  if cid == "" then return end

  local has = (type(appearanceJsonOrNil) == "string" and appearanceJsonOrNil ~= "")
  if has then
    local ok, appearance = pcall(function() return json.decode(appearanceJsonOrNil) end)
    if ok and type(appearance) == "table" then
      missingAppearance[cid] = nil
      saveAppearanceKvp(cid, appearance)

      return
    end
  end

  missingAppearance[cid] = true
  print(("[%s][clothing] ACTIVE AP none cid=%s"):format(RESOURCE_NAME, cid))
end)

RegisterNetEvent("az_clothing:purchaseResult", function(ok, reason)
  if not pending.active then return end

  local appearance = pending.appearance
  pending.active = false
  pending.appearance = nil

  if not ok then
    print(("[%s][clothing] purchaseResult FAILED reason=%s"):format(RESOURCE_NAME, tostring(reason)))
    feed(("~r~Purchase failed.~s~ %s"):format(tostring(reason or "")))
    return
  end

  if currentCharId and type(appearance) == "table" then
    local snap = applyThenSnapshot(appearance)
    saveAppearanceToServerWith(snap, "purchase_confirmed", true)
    missingAppearance[currentCharId] = nil
    feed("~g~Outfit saved!~s~")
  else
    saveAppearanceToServer("purchase_confirmed_fallback", true)
    feed("~g~Outfit saved!~s~")
  end
end)

local function openCustomizationEditor(tag, chargePrice)
  if not Config.UseAppearance then return end

  local okExport, exportedCid = pcall(function()
    if exports[RESOURCE_NAME] and exports[RESOURCE_NAME].getCurrentCharId then
      return exports[RESOURCE_NAME]:getCurrentCharId()
    end
  end)
  if okExport and exportedCid then
    currentCharId = tostring(exportedCid)
  end

  if not customizationAvailable() then
    warnCustomizationDisabled()
    return
  end

  if pending.active then
    feed("~y~Please wait...~s~ Saving previous purchase.")
    return
  end

  if not currentCharId then
    feed("~r~No character active.~s~ Select a character first.")
    return
  end

  local appearanceConfig = {
    ped = true,
    headBlend = true,
    faceFeatures = true,
    headOverlays = true,
    components = true,
    props = true,
    tattoos = true,
    allowExit = true
  }

  isCustomizing = true
  exports["fivem-appearance"]:startPlayerCustomization(function(appearance)
    isCustomizing = false
    if not appearance then
      print(("[%s][clothing] customization canceled (%s)"):format(RESOURCE_NAME, tostring(tag)))
      return
    end

    if not chargePrice then
      local snap = applyThenSnapshot(appearance)
      saveAppearanceToServerWith(snap, tostring(tag or "customization"), true)
      missingAppearance[currentCharId] = nil
      feed("~g~Saved.~s~")
      return
    end

    pending.active = true
    pending.appearance = appearance
    pending.startedAt = GetGameTimer()

    TriggerServerEvent("az_clothing:purchaseOutfit", tonumber(Config.Price) or 0, tostring(currentCharId), appearance)
  end, appearanceConfig)
end

local function openClothingEditor(shop)
  print(("[%s][clothing] Opening at '%s' cid=%s price=$%d"):format(
    RESOURCE_NAME,
    shop.label or "Clothing Store",
    tostring(currentCharId),
    tonumber(Config.Price) or 0
  ))

  if Config.AutoOpenFree then
    openCustomizationEditor("shop_free", false)
  else
    openCustomizationEditor("shop_paid", true)
  end
end

Citizen.CreateThread(function()
  Citizen.Wait(0)
  if not Config.EnableCustomizationCommand then return end

  local cmd = tostring(Config.CustomizationCommand or "customization")
  if cmd == "" then cmd = "customization" end

  RegisterCommand(cmd, function()
    openCustomizationEditor("command", false)
  end, false)
end)

local function DrawText3D(x, y, z, text)
  local onScreen, _x, _y = World3dToScreen2d(x, y, z)
  if not onScreen then return end
  SetTextScale(0.35, 0.35)
  SetTextFont(4)
  SetTextProportional(1)
  SetTextColour(255, 255, 255, 215)
  SetTextDropshadow(0, 0, 0, 0, 255)
  SetTextEdge(2, 0, 0, 0, 150)
  SetTextDropShadow()
  SetTextOutline()
  SetTextEntry("STRING")
  AddTextComponentString(text)
  DrawText(_x, _y)
end

Citizen.CreateThread(function()
  if not Config.Blips or not Config.Blips.Enabled then return end
  for _, shop in ipairs(Config.Shops) do
    local blip = AddBlipForCoord(shop.coords.x, shop.coords.y, shop.coords.z)
    SetBlipSprite(blip, Config.Blips.Sprite or 73)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, Config.Blips.Scale or 0.8)
    SetBlipColour(blip, Config.Blips.Color or 47)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(shop.label or "Clothing Store")
    EndTextCommandSetBlipName(blip)
  end
end)

Citizen.CreateThread(function()
  while true do
    local sleep = 1000
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    local closestShopIndex = nil
    local closestDist = 9999.0

    for i, shop in ipairs(Config.Shops) do
      local dist = #(pCoords - shop.coords)

      if dist < Config.MarkerDistance then
        sleep = 0
        DrawMarker(
          Config.MarkerType,
          shop.coords.x, shop.coords.y, shop.coords.z - 1.0,
          0.0, 0.0, 0.0,
          0.0, 0.0, 0.0,
          Config.MarkerScale.x, Config.MarkerScale.y, Config.MarkerScale.z,
          Config.MarkerColor.r, Config.MarkerColor.g, Config.MarkerColor.b, Config.MarkerColor.a,
          false, true, 2, nil, nil, false
        )
      end

      if dist < Config.InteractDistance and dist < closestDist then
        closestDist = dist
        closestShopIndex = i
      end
    end

    if closestShopIndex then
      local shop = Config.Shops[closestShopIndex]
      local textZ = shop.coords.z + Config.TextZOffset
      DrawText3D(shop.coords.x, shop.coords.y, textZ, ("~w~Press ~y~[E]~w~ to change clothes ~c~($%d)"):format(tonumber(Config.Price) or 0))

      if IsControlJustReleased(0, Config.Key) then
        openClothingEditor(shop)
      end
    end

    Citizen.Wait(sleep)
  end
end)

AddEventHandler("onResourceStop", function(res)
  if res ~= RESOURCE_NAME then return end
  saveAppearanceToServer("resourceStop", true)
end)

RegisterNetEvent("txAdmin:events:serverShuttingDown", function()
  saveAppearanceToServer("txAdminShutdown", true)
end)

RegisterNetEvent("txAdmin:events:scheduledRestart", function()
  saveAppearanceToServer("txAdminRestart", true)
end)

print(("^2[%s][clothing] Clothing store client loaded.^7"):format(RESOURCE_NAME))
