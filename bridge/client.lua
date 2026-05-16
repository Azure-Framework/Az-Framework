Config = Config or {}
Config.FrameworkBridge = Config.FrameworkBridge or {}
if Config.FrameworkBridge.Enabled == false then return end

local snapshot = {
  source = 0,
  name = "",
  firstname = "",
  lastname = "",
  fullname = "",
  cash = 0,
  bank = 0,
  money = { cash = 0, bank = 0, crypto = 0 },
  job = "unemployed",
  jobInfo = {
    name = "unemployed",
    label = "Unemployed",
    rank = 0,
    rankName = "Member",
    onduty = false,
  },
  metadata = {},
}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end

  local out = {}
  seen[value] = out
  for k, v in pairs(value) do
    out[copy(k, seen)] = copy(v, seen)
  end
  return out
end

local function applyJob(job)
  job = tostring(job or ""):lower()
  snapshot.job = job ~= "" and job or "unemployed"
  snapshot.jobInfo = snapshot.jobInfo or {}
  snapshot.jobInfo.name = snapshot.job
  snapshot.jobInfo.label = snapshot.job
  snapshot.jobInfo.onduty = job ~= ""
end

local function requestSnapshot()
  TriggerServerEvent("Az-Framework:Bridge:RequestSnapshot")
end

RegisterNetEvent("Az-Framework:Bridge:Snapshot", function(data)
  if type(data) ~= "table" then return end
  snapshot = copy(data)
end)

RegisterNetEvent("Az-Framework:Bridge:MetadataUpdated", function(metadata)
  snapshot.metadata = copy(metadata or {})
end)

RegisterNetEvent("updateCashHUD", function(cash, bank, playerName)
  snapshot.cash = tonumber(cash) or 0
  snapshot.bank = tonumber(bank) or 0
  snapshot.money = snapshot.money or {}
  snapshot.money.cash = snapshot.cash
  snapshot.money.bank = snapshot.bank
  snapshot.money.crypto = tonumber(snapshot.money.crypto) or 0
  if playerName and tostring(playerName) ~= "" then
    snapshot.name = tostring(playerName)
    snapshot.fullname = snapshot.name
  end
end)

RegisterNetEvent("hud:setDepartment", function(job)
  applyJob(job)
end)

RegisterNetEvent("az-fw-money:characterSelected", requestSnapshot)
RegisterNetEvent("az-fw-money:characterRegistered", requestSnapshot)

AddEventHandler("playerSpawned", function()
  SetTimeout(750, requestSnapshot)
end)

AddEventHandler("onClientResourceStart", function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  SetTimeout(750, requestSnapshot)
end)

_G.AzBridgeClientExports = {
  GetBridgeClientSnapshot = function() return copy(snapshot) end,
  GetBridgeClientMetadata = function(key)
    if key == nil then return copy(snapshot.metadata or {}) end
    return copy((snapshot.metadata or {})[tostring(key)])
  end,
  SetBridgeClientMetadata = function(key, value)
    key = tostring(key or "")
    if key == "" then return false end
    snapshot.metadata = snapshot.metadata or {}
    snapshot.metadata[key] = value
    TriggerServerEvent("Az-Framework:Bridge:SetMetadata", key, value)
    return true
  end,
}
