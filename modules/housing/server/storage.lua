AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end

local RESOURCE = GetCurrentResourceName()

local Storage = {}
Storage.driver = 'json'

local function jpath(name)
  return ('data/%s.json'):format(name)
end

local function readJson(file, fallback)
  local raw = LoadResourceFile(RESOURCE, file)
  if not raw or raw == '' then return fallback end
  local ok, data = pcall(json.decode, raw)
  if not ok then return fallback end
  return data
end

local function writeJson(file, data)
  SaveResourceFile(RESOURCE, file, json.encode(data or {}, { indent = true }), -1)
end

local function hasOxMySQL()
  return AZH.hasResource('oxmysql') and exports.oxmysql ~= nil
end

local function awaitMySQL(fn)
  local p = promise.new()
  fn(function(res)
    p:resolve(res)
  end)
  return Citizen.Await(p)
end

function Storage.exec(query, params)
  params = params or {}
  if Storage.driver ~= 'oxmysql' then return nil end
  return awaitMySQL(function(cb)
    exports.oxmysql:execute(query, params, cb)
  end)
end

function Storage.insert(query, params)
  params = params or {}
  if Storage.driver ~= 'oxmysql' then return nil end
  return awaitMySQL(function(cb)
    exports.oxmysql:insert(query, params, cb)
  end)
end

function Storage.ensureTables()
  if Storage.driver ~= 'oxmysql' then return true end

  local stmts = {
    [[CREATE TABLE IF NOT EXISTS `az_houses` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `name` VARCHAR(64) NOT NULL,
      `label` VARCHAR(128) NULL,
      `price` INT NOT NULL DEFAULT 0,
      `interior` VARCHAR(32) NOT NULL DEFAULT 'apt_basic',
      `locked` TINYINT(1) NOT NULL DEFAULT 1,
      `owner_identifier` VARCHAR(64) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
      `image_url` TEXT NULL,
      `image_data` LONGTEXT NULL,
      PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[ALTER TABLE `az_houses` ADD COLUMN IF NOT EXISTS `image_url` TEXT NULL;]],
    [[ALTER TABLE `az_houses` ADD COLUMN IF NOT EXISTS `image_data` LONGTEXT NULL;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_doors` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `house_id` INT NOT NULL,
      `x` DOUBLE NOT NULL,
      `y` DOUBLE NOT NULL,
      `z` DOUBLE NOT NULL,
      `heading` DOUBLE NOT NULL DEFAULT 0,
      `radius` DOUBLE NOT NULL DEFAULT 2.0,
      `label` VARCHAR(64) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `idx_house_id` (`house_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_garages` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `house_id` INT NOT NULL,
      `x` DOUBLE NOT NULL,
      `y` DOUBLE NOT NULL,
      `z` DOUBLE NOT NULL,
      `heading` DOUBLE NOT NULL DEFAULT 0,
      `spawn_x` DOUBLE NOT NULL,
      `spawn_y` DOUBLE NOT NULL,
      `spawn_z` DOUBLE NOT NULL,
      `spawn_h` DOUBLE NOT NULL DEFAULT 0,
      `radius` DOUBLE NOT NULL DEFAULT 2.2,
      `label` VARCHAR(64) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `idx_house_id` (`house_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_keys` (
      `house_id` INT NOT NULL,
      `identifier` VARCHAR(64) NOT NULL,
      `perms` VARCHAR(16) NOT NULL DEFAULT 'enter',
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`house_id`, `identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_rentals` (
      `house_id` INT NOT NULL,
      `is_listed` TINYINT(1) NOT NULL DEFAULT 0,
      `rent_per_week` INT NOT NULL DEFAULT 0,
      `deposit` INT NOT NULL DEFAULT 0,
      `tenant_identifier` VARCHAR(64) NULL,
      `agent_identifier` VARCHAR(64) NULL,
      `status` VARCHAR(16) NOT NULL DEFAULT 'available',
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`house_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_apps` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `house_id` INT NOT NULL,
      `applicant_identifier` VARCHAR(64) NOT NULL,
      `message` TEXT NULL,
      `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `idx_house_id` (`house_id`),
      KEY `idx_status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_vehicles` (
      `house_id` INT NOT NULL,
      `plate` VARCHAR(16) NOT NULL,
      `owner_identifier` VARCHAR(64) NOT NULL,
      `props_json` LONGTEXT NOT NULL,
      `stored` TINYINT(1) NOT NULL DEFAULT 1,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`house_id`, `plate`),
      KEY `idx_owner` (`owner_identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_upgrades` (
      `house_id` INT NOT NULL,
      `mailbox_level` INT NOT NULL DEFAULT 0,
      `decor_level` INT NOT NULL DEFAULT 0,
      `storage_level` INT NOT NULL DEFAULT 0,
      `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`house_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_mail` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `house_id` INT NOT NULL,
      `sender_identifier` VARCHAR(64) NULL,
      `sender_name` VARCHAR(64) NULL,
      `subject` VARCHAR(96) NOT NULL,
      `body` TEXT NULL,
      `is_read` TINYINT(1) NOT NULL DEFAULT 0,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `idx_house_id` (`house_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `az_house_furniture` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `house_id` INT NOT NULL,
      `owner_identifier` VARCHAR(64) NULL,
      `model` VARCHAR(96) NOT NULL,
      `x` DOUBLE NOT NULL,
      `y` DOUBLE NOT NULL,
      `z` DOUBLE NOT NULL,
      `heading` DOUBLE NOT NULL DEFAULT 0,
      `rot_x` DOUBLE NOT NULL DEFAULT 0,
      `rot_y` DOUBLE NOT NULL DEFAULT 0,
      `rot_z` DOUBLE NOT NULL DEFAULT 0,
      `meta_json` LONGTEXT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `idx_house_id` (`house_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
  }

  for _, q in ipairs(stmts) do
    local ok, err = pcall(function() Storage.exec(q, {}) end)
    if not ok then
      print(('^1[%s]^7 Failed to ensure table: %s'):format(RESOURCE, tostring(err)))
    end
  end

  return true
end

function Storage.init()
  if Config and Config.UseDatabase and hasOxMySQL() then
    Storage.driver = 'oxmysql'
  else
    Storage.driver = 'json'
  end

  AZH.dprint('Storage driver:', Storage.driver)

  if Storage.driver == 'oxmysql' then
    Storage.ensureTables()
  end

  return true
end

function Storage.loadAll()
  if Storage.driver == 'oxmysql' then
    local houses = Storage.exec('SELECT * FROM az_houses', {}) or {}
    local doors  = Storage.exec('SELECT * FROM az_house_doors', {}) or {}
    local garages = Storage.exec('SELECT * FROM az_house_garages', {}) or {}
    local keys = Storage.exec('SELECT * FROM az_house_keys', {}) or {}
    local rentals = Storage.exec('SELECT * FROM az_house_rentals', {}) or {}
    local apps = Storage.exec('SELECT * FROM az_house_apps', {}) or {}
    local vehicles = Storage.exec('SELECT * FROM az_house_vehicles', {}) or {}
    local upgrades = Storage.exec('SELECT * FROM az_house_upgrades', {}) or {}
    local mail = Storage.exec('SELECT * FROM az_house_mail', {}) or {}
    local furniture = Storage.exec('SELECT * FROM az_house_furniture', {}) or {}
    return {
      houses = houses,
      doors = doors,
      garages = garages,
      keys = keys,
      rentals = rentals,
      apps = apps,
      vehicles = vehicles,
      upgrades = upgrades,
      mail = mail,
      furniture = furniture,
    }
  end

  return {
    houses = readJson(jpath('houses'), {}),
    doors = readJson(jpath('doors'), {}),
    garages = readJson(jpath('garages'), {}),
    keys = readJson(jpath('keys'), {}),
    rentals = readJson(jpath('rentals'), {}),
    apps = readJson(jpath('apps'), {}),
    vehicles = readJson(jpath('vehicles'), {}),
    upgrades = readJson(jpath('upgrades'), {}),
    mail = readJson(jpath('mail'), {}),
    furniture = readJson(jpath('furniture'), {}),
  }
end

local function upsertJson(list, key, row)
  list = list or {}
  local id = row[key]
  local found = false
  for i = 1, #list do
    if list[i][key] == id then
      list[i] = row
      found = true
      break
    end
  end
  if not found then
    table.insert(list, row)
  end
  return list
end

function Storage.saveHouse(row)
  if Storage.driver == 'oxmysql' then
    if not row.id then
      local id = Storage.insert(
        'INSERT INTO az_houses (name,label,price,interior,locked,owner_identifier,created_at) VALUES (?,?,?,?,?,?,NOW())',
        { row.name, row.label, row.price, row.interior, row.locked and 1 or 0, row.owner_identifier }
      )
      return id
    end

    Storage.exec(
      'UPDATE az_houses SET name=?, label=?, price=?, interior=?, locked=?, owner_identifier=? WHERE id=?',
      { row.name, row.label, row.price, row.interior, row.locked and 1 or 0, row.owner_identifier, row.id }
    )
    return row.id
  end

  local houses = readJson(jpath('houses'), {})
  if not row.id then
    local max = 0
    for _, h in ipairs(houses) do max = math.max(max, tonumber(h.id) or 0) end
    row.id = max + 1
  end
  houses = upsertJson(houses, 'id', row)
  writeJson(jpath('houses'), houses)
  return row.id
end

function Storage.deleteHouse(id)
  if Storage.driver == 'oxmysql' then
    Storage.exec('DELETE FROM az_houses WHERE id=?', { id })
    Storage.exec('DELETE FROM az_house_doors WHERE house_id=?', { id })
    Storage.exec('DELETE FROM az_house_garages WHERE house_id=?', { id })
    Storage.exec('DELETE FROM az_house_keys WHERE house_id=?', { id })
    Storage.exec('DELETE FROM az_house_rentals WHERE house_id=?', { id })
    Storage.exec('DELETE FROM az_house_apps WHERE house_id=?', { id })
    Storage.exec('DELETE FROM az_house_vehicles WHERE house_id=?', { id })
    return true
  end

  local houses = readJson(jpath('houses'), {})
  local doors = readJson(jpath('doors'), {})
  local garages = readJson(jpath('garages'), {})
  local keys = readJson(jpath('keys'), {})
  local rentals = readJson(jpath('rentals'), {})
  local apps = readJson(jpath('apps'), {})
  local vehicles = readJson(jpath('vehicles'), {})

  local function filter(list, fn)
    local out = {}
    for _, r in ipairs(list or {}) do
      if fn(r) then out[#out+1] = r end
    end
    return out
  end

  houses = filter(houses, function(r) return r.id ~= id end)
  doors = filter(doors, function(r) return r.house_id ~= id end)
  garages = filter(garages, function(r) return r.house_id ~= id end)
  keys = filter(keys, function(r) return r.house_id ~= id end)
  rentals = filter(rentals, function(r) return r.house_id ~= id end)
  apps = filter(apps, function(r) return r.house_id ~= id end)
  vehicles = filter(vehicles, function(r) return r.house_id ~= id end)

  writeJson(jpath('houses'), houses)
  writeJson(jpath('doors'), doors)
  writeJson(jpath('garages'), garages)
  writeJson(jpath('keys'), keys)
  writeJson(jpath('rentals'), rentals)
  writeJson(jpath('apps'), apps)
  writeJson(jpath('vehicles'), vehicles)
  return true
end

function Storage.saveDoor(row)
  if Storage.driver == 'oxmysql' then
    if not row.id then
      local id = Storage.insert(
        'INSERT INTO az_house_doors (house_id,x,y,z,heading,radius,label,created_at) VALUES (?,?,?,?,?,?,?,NOW())',
        { row.house_id, row.x, row.y, row.z, row.heading, row.radius, row.label }
      )
      return id
    end

    Storage.exec('UPDATE az_house_doors SET x=?,y=?,z=?,heading=?,radius=?,label=? WHERE id=?',
      { row.x, row.y, row.z, row.heading, row.radius, row.label, row.id })
    return row.id
  end

  local doors = readJson(jpath('doors'), {})
  if not row.id then
    local max = 0
    for _, h in ipairs(doors) do max = math.max(max, tonumber(h.id) or 0) end
    row.id = max + 1
  end
  doors = upsertJson(doors, 'id', row)
  writeJson(jpath('doors'), doors)
  return row.id
end

function Storage.deleteDoor(id)
  if Storage.driver == 'oxmysql' then
    Storage.exec('DELETE FROM az_house_doors WHERE id=?', { id })
    return true
  end
  local doors = readJson(jpath('doors'), {})
  local out = {}
  for _, r in ipairs(doors) do if r.id ~= id then out[#out+1] = r end end
  writeJson(jpath('doors'), out)
  return true
end

function Storage.saveGarage(row)
  if Storage.driver == 'oxmysql' then
    if not row.id then
      local id = Storage.insert(
        'INSERT INTO az_house_garages (house_id,x,y,z,heading,spawn_x,spawn_y,spawn_z,spawn_h,radius,label,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,NOW())',
        { row.house_id, row.x, row.y, row.z, row.heading, row.spawn_x, row.spawn_y, row.spawn_z, row.spawn_h, row.radius, row.label }
      )
      return id
    end

    Storage.exec('UPDATE az_house_garages SET x=?,y=?,z=?,heading=?,spawn_x=?,spawn_y=?,spawn_z=?,spawn_h=?,radius=?,label=? WHERE id=?',
      { row.x, row.y, row.z, row.heading, row.spawn_x, row.spawn_y, row.spawn_z, row.spawn_h, row.radius, row.label, row.id })
    return row.id
  end

  local garages = readJson(jpath('garages'), {})
  if not row.id then
    local max = 0
    for _, h in ipairs(garages) do max = math.max(max, tonumber(h.id) or 0) end
    row.id = max + 1
  end
  garages = upsertJson(garages, 'id', row)
  writeJson(jpath('garages'), garages)
  return row.id
end

function Storage.deleteGarage(id)
  if Storage.driver == 'oxmysql' then
    Storage.exec('DELETE FROM az_house_garages WHERE id=?', { id })
    return true
  end
  local garages = readJson(jpath('garages'), {})
  local out = {}
  for _, r in ipairs(garages) do if r.id ~= id then out[#out+1] = r end end
  writeJson(jpath('garages'), out)
  return true
end

function Storage.setKey(houseId, identifier, perms)
  perms = perms or 'enter'
  if Storage.driver == 'oxmysql' then
    Storage.exec('INSERT INTO az_house_keys (house_id,identifier,perms,created_at) VALUES (?,?,?,NOW()) ON DUPLICATE KEY UPDATE perms=?',
      { houseId, identifier, perms, perms })
    return true
  end

  local keys = readJson(jpath('keys'), {})
  local found = false
  for i = 1, #keys do
    if keys[i].house_id == houseId and keys[i].identifier == identifier then
      keys[i].perms = perms
      found = true
      break
    end
  end
  if not found then keys[#keys+1] = { house_id = houseId, identifier = identifier, perms = perms } end
  writeJson(jpath('keys'), keys)
  return true
end

function Storage.revokeKey(houseId, identifier)
  if Storage.driver == 'oxmysql' then
    Storage.exec('DELETE FROM az_house_keys WHERE house_id=? AND identifier=?', { houseId, identifier })
    return true
  end

  local keys = readJson(jpath('keys'), {})
  local out = {}
  for _, r in ipairs(keys) do
    if not (r.house_id == houseId and r.identifier == identifier) then
      out[#out+1] = r
    end
  end
  writeJson(jpath('keys'), out)
  return true
end

function Storage.submitApplication(houseId, applicantId, message)
  message = tostring(message or '')
  if Storage.driver == 'oxmysql' then
    Storage.exec('INSERT INTO az_house_apps (house_id,applicant_identifier,message,status,created_at) VALUES (?,?,?,?,NOW())',
      { houseId, applicantId, message, 'pending' })
    return true
  end

  local apps = readJson(jpath('apps'), {})
  apps[#apps+1] = { id = (#apps+1), house_id = houseId, applicant_identifier = applicantId, message = message, status = 'pending' }
  writeJson(jpath('apps'), apps)
  return true
end

function Storage.setApplicationStatus(appId, status)
  status = status or 'pending'
  if Storage.driver == 'oxmysql' then
    Storage.exec('UPDATE az_house_apps SET status=? WHERE id=?', { status, appId })
    return true
  end

  local apps = readJson(jpath('apps'), {})
  for i = 1, #apps do
    if apps[i].id == appId then apps[i].status = status end
  end
  writeJson(jpath('apps'), apps)
  return true
end

function Storage.upsertRental(row)
  if Storage.driver == 'oxmysql' then
    Storage.exec(
      'INSERT INTO az_house_rentals (house_id,is_listed,rent_per_week,deposit,tenant_identifier,agent_identifier,status,updated_at,created_at) VALUES (?,?,?,?,?,?,?,NOW(),NOW()) ' ..
      'ON DUPLICATE KEY UPDATE is_listed=VALUES(is_listed), rent_per_week=VALUES(rent_per_week), deposit=VALUES(deposit), tenant_identifier=VALUES(tenant_identifier), agent_identifier=VALUES(agent_identifier), status=VALUES(status), updated_at=NOW()',
      { row.house_id, row.is_listed and 1 or 0, row.rent_per_week, row.deposit, row.tenant_identifier, row.agent_identifier, row.status }
    )
    return true
  end

  local rentals = readJson(jpath('rentals'), {})
  local found = false
  for i = 1, #rentals do
    if rentals[i].house_id == row.house_id then
      rentals[i] = row
      found = true
      break
    end
  end
  if not found then rentals[#rentals+1] = row end
  writeJson(jpath('rentals'), rentals)
  return true
end

function Storage.getUpgrades(houseId)
  houseId = tonumber(houseId)
  if not houseId then return { house_id = houseId, mailbox_level = 0, decor_level = 0, storage_level = 0 } end

  if Storage.driver == 'oxmysql' then
    local rows = Storage.exec('SELECT * FROM az_house_upgrades WHERE house_id=? LIMIT 1', { houseId }) or {}
    return rows[1] or { house_id = houseId, mailbox_level = 0, decor_level = 0, storage_level = 0 }
  end

  local upgrades = readJson(jpath('upgrades'), {})
  for _, u in ipairs(upgrades) do
    if tonumber(u.house_id) == houseId then return u end
  end
  return { house_id = houseId, mailbox_level = 0, decor_level = 0, storage_level = 0 }
end

function Storage.setUpgradeLevels(houseId, mailboxLevel, decorLevel, storageLevel)
  houseId = tonumber(houseId)
  if not houseId then return false end
  mailboxLevel = tonumber(mailboxLevel) or 0
  decorLevel = tonumber(decorLevel) or 0
  storageLevel = tonumber(storageLevel) or 0

  if Storage.driver == 'oxmysql' then
    Storage.exec(
      'INSERT INTO az_house_upgrades (house_id,mailbox_level,decor_level,storage_level,updated_at,created_at) VALUES (?,?,?,?,NOW(),NOW()) ' ..
      'ON DUPLICATE KEY UPDATE mailbox_level=VALUES(mailbox_level), decor_level=VALUES(decor_level), storage_level=VALUES(storage_level), updated_at=NOW()',
      { houseId, mailboxLevel, decorLevel, storageLevel }
    )
    return true
  end

  local upgrades = readJson(jpath('upgrades'), {})
  local found = false
  for i = 1, #upgrades do
    if tonumber(upgrades[i].house_id) == houseId then
      upgrades[i].mailbox_level = mailboxLevel
      upgrades[i].decor_level = decorLevel
      upgrades[i].storage_level = storageLevel
      found = true
      break
    end
  end
  if not found then
    upgrades[#upgrades+1] = { house_id = houseId, mailbox_level = mailboxLevel, decor_level = decorLevel, storage_level = storageLevel }
  end
  writeJson(jpath('upgrades'), upgrades)
  return true
end

function Storage.listMail(houseId, limit)
  houseId = tonumber(houseId)
  limit = tonumber(limit) or 50
  if not houseId then return {} end

  if Storage.driver == 'oxmysql' then
    return Storage.exec('SELECT * FROM az_house_mail WHERE house_id=? ORDER BY id DESC LIMIT ' .. tostring(limit), { houseId }) or {}
  end

  local mail = readJson(jpath('mail'), {})
  local out = {}
  for i = #mail, 1, -1 do
    local m = mail[i]
    if tonumber(m.house_id) == houseId then
      out[#out+1] = m
      if #out >= limit then break end
    end
  end
  return out
end

function Storage.addMail(houseId, senderId, senderName, subject, body)
  houseId = tonumber(houseId)
  if not houseId then return false end
  subject = tostring(subject or 'Message')
  body = tostring(body or '')

  if Storage.driver == 'oxmysql' then
    local id = Storage.insert(
      'INSERT INTO az_house_mail (house_id,sender_identifier,sender_name,subject,body,is_read,created_at) VALUES (?,?,?,?,?,0,NOW())',
      { houseId, senderId, senderName, subject, body }
    )
    return id
  end

  local mail = readJson(jpath('mail'), {})
  local id = 1
  for _, m in ipairs(mail) do id = math.max(id, tonumber(m.id) or 0) end
  id = id + 1
  mail[#mail+1] = { id = id, house_id = houseId, sender_identifier = senderId, sender_name = senderName, subject = subject, body = body, is_read = false, created_at = os.time() }
  writeJson(jpath('mail'), mail)
  return id
end

function Storage.markMailRead(mailId, isRead)
  mailId = tonumber(mailId)
  if not mailId then return false end
  isRead = (isRead == true)

  if Storage.driver == 'oxmysql' then
    Storage.exec('UPDATE az_house_mail SET is_read=? WHERE id=?', { isRead and 1 or 0, mailId })
    return true
  end

  local mail = readJson(jpath('mail'), {})
  for i = 1, #mail do
    if tonumber(mail[i].id) == mailId then
      mail[i].is_read = isRead
    end
  end
  writeJson(jpath('mail'), mail)
  return true
end

function Storage.deleteMail(mailId)
  mailId = tonumber(mailId)
  if not mailId then return false end

  if Storage.driver == 'oxmysql' then
    Storage.exec('DELETE FROM az_house_mail WHERE id=?', { mailId })
    return true
  end

  local mail = readJson(jpath('mail'), {})
  local out = {}
  for _, m in ipairs(mail) do
    if tonumber(m.id) ~= mailId then out[#out+1] = m end
  end
  writeJson(jpath('mail'), out)
  return true
end

function Storage.listFurniture(houseId)
  houseId = tonumber(houseId)
  if not houseId then return {} end

  if Storage.driver == 'oxmysql' then
    return Storage.exec('SELECT * FROM az_house_furniture WHERE house_id=? ORDER BY id ASC', { houseId }) or {}
  end

  local furn = readJson(jpath('furniture'), {})
  local out = {}
  for _, f in ipairs(furn) do
    if tonumber(f.house_id) == houseId then out[#out+1] = f end
  end
  table.sort(out, function(a,b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
  return out
end

function Storage.addFurniture(houseId, ownerId, model, coords, heading, rot, meta)
  houseId = tonumber(houseId)
  if not houseId then return nil end
  model = tostring(model or '')
  if model == '' then return nil end
  coords = coords or {}
  rot = rot or {}
  meta = meta or {}

  if Storage.driver == 'oxmysql' then
    local id = Storage.insert(
      'INSERT INTO az_house_furniture (house_id,owner_identifier,model,x,y,z,heading,rot_x,rot_y,rot_z,meta_json,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,NOW())',
      { houseId, ownerId, model, coords.x, coords.y, coords.z, heading or 0.0, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0, json.encode(meta) }
    )
    return id
  end

  local furn = readJson(jpath('furniture'), {})
  local id = 0
  for _, f in ipairs(furn) do id = math.max(id, tonumber(f.id) or 0) end
  id = id + 1
  furn[#furn+1] = {
    id = id,
    house_id = houseId,
    owner_identifier = ownerId,
    model = model,
    x = coords.x, y = coords.y, z = coords.z,
    heading = heading or 0.0,
    rot_x = rot.x or 0.0,
    rot_y = rot.y or 0.0,
    rot_z = rot.z or 0.0,
    meta_json = json.encode(meta),
    created_at = os.time(),
  }
  writeJson(jpath('furniture'), furn)
  return id
end

function Storage.deleteFurniture(id)
  id = tonumber(id)
  if not id then return false end

  if Storage.driver == 'oxmysql' then
    Storage.exec('DELETE FROM az_house_furniture WHERE id=?', { id })
    return true
  end

  local furn = readJson(jpath('furniture'), {})
  local out = {}
  for _, f in ipairs(furn) do
    if tonumber(f.id) ~= id then out[#out+1] = f end
  end
  writeJson(jpath('furniture'), out)
  return true
end

function Storage.saveVehicle(houseId, ownerId, plate, props)
  plate = tostring(plate or '')
  props = props or {}
  if plate == '' then return false end

  if Storage.driver == 'oxmysql' then
    Storage.exec('INSERT INTO az_house_vehicles (house_id,owner_identifier,plate,props_json,stored,updated_at,created_at) VALUES (?,?,?,?,1,NOW(),NOW()) ON DUPLICATE KEY UPDATE owner_identifier=?, props_json=?, stored=1, updated_at=NOW()',
      { houseId, ownerId, plate, json.encode(props), ownerId, json.encode(props) })
    return true
  end

  local vehicles = readJson(jpath('vehicles'), {})
  local found = false
  for i = 1, #vehicles do
    if vehicles[i].house_id == houseId and vehicles[i].plate == plate then
      vehicles[i].owner_identifier = ownerId
      vehicles[i].props_json = json.encode(props)
      vehicles[i].stored = true
      found = true
      break
    end
  end
  if not found then
    vehicles[#vehicles+1] = { house_id = houseId, owner_identifier = ownerId, plate = plate, props_json = json.encode(props), stored = true }
  end
  writeJson(jpath('vehicles'), vehicles)
  return true
end

function Storage.listVehicles(houseId)
  if Storage.driver == 'oxmysql' then
    return Storage.exec('SELECT * FROM az_house_vehicles WHERE house_id=? AND stored=1', { houseId }) or {}
  end

  local vehicles = readJson(jpath('vehicles'), {})
  local out = {}
  for _, v in ipairs(vehicles) do
    if v.house_id == houseId and v.stored == true then out[#out+1] = v end
  end
  return out
end

function Storage.getVehicle(houseId, plate)
  plate = tostring(plate or '')
  if plate == '' then return nil end

  if Storage.driver == 'oxmysql' then
    local rows = Storage.exec('SELECT * FROM az_house_vehicles WHERE house_id=? AND plate=? LIMIT 1', { houseId, plate }) or {}
    return rows[1]
  end

  local vehicles = readJson(jpath('vehicles'), {})
  for _, v in ipairs(vehicles) do
    if v.house_id == houseId and v.plate == plate then return v end
  end
  return nil
end

function Storage.markVehicleOut(houseId, plate)
  plate = tostring(plate or '')
  if Storage.driver == 'oxmysql' then
    Storage.exec('UPDATE az_house_vehicles SET stored=0, updated_at=NOW() WHERE house_id=? AND plate=?', { houseId, plate })
    return true
  end

  local vehicles = readJson(jpath('vehicles'), {})
  for i = 1, #vehicles do
    if vehicles[i].house_id == houseId and vehicles[i].plate == plate then
      vehicles[i].stored = false
    end
  end
  writeJson(jpath('vehicles'), vehicles)
  return true
end

AZH.Storage = Storage
