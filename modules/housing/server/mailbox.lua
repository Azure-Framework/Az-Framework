AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end

local function S()
  return AZH.State or {}
end

local function normIdent(v)
  if v == nil then return nil end
  local s = tostring(v)
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then return nil end
  local sl = string.lower(s)
  if sl == '0' or sl == 'null' or sl == 'none' or sl == 'false' or sl == 'nil' or sl == 'n/a' or sl == 'na' or sl == 'undefined' then
    return nil
  end
  if string.sub(s, 1, 5) == 'char:' then
    s = 'charid:' .. string.sub(s, 6)
  end
  return s
end

local function identOf(src)
  if AZH and type(AZH.getHousingIdentifier) == 'function' then
    return normIdent(AZH.getHousingIdentifier(src))
  end
  return normIdent(AZH.getIdentifier(src))
end

local function aliasSetOf(src)
  local set = {}
  local function add(v)
    v = normIdent(v)
    if v then set[v] = true end
  end

  add(identOf(src))

  if AZH and type(AZH.getIdentifierAliases) == 'function' then
    local ok, aliases = pcall(AZH.getIdentifierAliases, src)
    if ok and type(aliases) == 'table' then
      for v, _ in pairs(aliases) do
        add(v)
      end
    end
  end

  return set
end

local function aliasMatches(src, value)
  value = normIdent(value)
  if not value then return false end
  local aliases = aliasSetOf(src)
  return aliases[value] == true
end

local function aliasHasKey(src, houseId)
  local st = S()
  local map = st.Keys and st.Keys[houseId] or nil
  if not map then return false end
  local aliases = aliasSetOf(src)
  for alias, _ in pairs(aliases) do
    if map[alias] ~= nil then
      return true
    end
  end
  return false
end

local function canUseMailbox(src, houseId)
  houseId = tonumber(houseId)
  if not houseId then return false end

  local st = S()
  local h = st.Houses and st.Houses[houseId] or nil
  if not h then return false end

  if AZH.isAdmin(src) then return true end

  local ident = identOf(src)
  if not ident then return false end

  if aliasMatches(src, h.owner_identifier) then return true end

  if aliasHasKey(src, houseId) then return true end

  local r = st.Rentals and st.Rentals[houseId] or nil
  if aliasMatches(src, r and r.tenant_identifier or nil) then return true end

  return false
end

local function canSendToHouse(src, houseId)
  if AZH.isAdmin(src) or AZH.isAgent(src) or AZH.isPolice(src) then return true end
  return canUseMailbox(src, houseId)
end

local function getSenderName(src)
  local name = GetPlayerName(src)
  if name and name ~= '' then return name end
  return tostring(AZH.getIdentifier(src) or 'Unknown')
end

lib.callback.register('az_housing:cb:getMailbox', function(src, houseId)
  if not (Config.Mailbox and Config.Mailbox.Enabled) then
    return { ok = false, error = 'Mailbox disabled' }
  end
  if not canUseMailbox(src, houseId) then
    return { ok = false, error = 'No access' }
  end

  local list = AZH.Storage.listMail(houseId, 75) or {}
  local limits = AZH.getHouseLimits(houseId)
  local unread = 0
  for _, m in ipairs(list) do
    local r = m.is_read
    if r == 0 or r == false or r == nil then unread = unread + 1 end
  end

  return {
    ok = true,
    messages = list,
    unread = unread,
    capacity = limits and limits.mailboxCap or ((Config.Mailbox and Config.Mailbox.BaseCapacity) or 15)
  }
end)

RegisterNetEvent('az_housing:server:sendMail', function(houseId, subject, body)
  local src = source
  houseId = tonumber(houseId)
  subject = tostring(subject or 'Message')
  body = tostring(body or '')
  if not houseId then return end

  if not (Config.Mailbox and Config.Mailbox.Enabled) then
    AZH.notify(src, 'error', 'Mailbox', 'Mailbox is disabled.')
    return
  end

  if not canSendToHouse(src, houseId) then
    AZH.notify(src, 'error', 'Mailbox', 'You cannot send mail to this property.')
    return
  end

  local limits = AZH.getHouseLimits(houseId)
  local cap = limits and limits.mailboxCap or 25
  local existing = AZH.Storage.listMail(houseId, 500) or {}
  if #existing >= cap then
    AZH.notify(src, 'error', 'Mailbox', 'Mailbox is full.')
    return
  end

  local senderId = identOf(src) or (AZH.getIdentifier(src))
  local senderName = getSenderName(src)
  local id = AZH.Storage.addMail(houseId, senderId, senderName, subject, body)
  if not id then
    AZH.notify(src, 'error', 'Mailbox', 'Failed to send.')
    return
  end

  AZH.notify(src, 'success', 'Mailbox', 'Sent.')
  TriggerClientEvent('az_housing:client:mailChanged', -1, houseId)
end)

local function mailBelongsToHouse(mailId, houseId)
  mailId = tonumber(mailId)
  houseId = tonumber(houseId)
  if not mailId or not houseId then return false end

  if AZH.Storage.driver == 'oxmysql' then
    local rows = AZH.Storage.exec('SELECT house_id FROM az_house_mail WHERE id=? LIMIT 1', { mailId }) or {}
    return rows[1] and tonumber(rows[1].house_id) == houseId
  end

  local list = AZH.Storage.listMail(houseId, 500) or {}
  for _, m in ipairs(list) do
    if tonumber(m.id) == mailId then return true end
  end
  return false
end

RegisterNetEvent('az_housing:server:mailMarkRead', function(houseId, mailId, isRead)
  local src = source
  houseId = tonumber(houseId)
  mailId = tonumber(mailId)
  isRead = (isRead == true)
  if not houseId or not mailId then return end

  if not canUseMailbox(src, houseId) then return end
  if not mailBelongsToHouse(mailId, houseId) then return end

  AZH.Storage.markMailRead(mailId, isRead)
  TriggerClientEvent('az_housing:client:mailChanged', -1, houseId)
end)

RegisterNetEvent('az_housing:server:deleteMail', function(houseId, mailId)
  local src = source
  houseId = tonumber(houseId)
  mailId = tonumber(mailId)
  if not houseId or not mailId then return end

  if not canUseMailbox(src, houseId) then
    AZH.notify(src, 'error', 'Mailbox', 'No access.')
    return
  end

  if not mailBelongsToHouse(mailId, houseId) then
    AZH.notify(src, 'error', 'Mailbox', 'Invalid message.')
    return
  end

  AZH.Storage.deleteMail(mailId)
  AZH.notify(src, 'success', 'Mailbox', 'Deleted.')
  TriggerClientEvent('az_housing:client:mailChanged', -1, houseId)
end)
