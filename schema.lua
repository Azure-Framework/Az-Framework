local tableSchemas = {
    [[
CREATE TABLE IF NOT EXISTS `econ_accounts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `type` enum('checking','savings') NOT NULL DEFAULT 'checking',
  `balance` decimal(12,2) NOT NULL DEFAULT 0.00,
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`)
) ENGINE=InnoDB AUTO_INCREMENT=131 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_admins` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_cards` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `card_number` varchar(16) NOT NULL,
  `exp_month` tinyint(4) NOT NULL,
  `exp_year` smallint(6) NOT NULL,
  `status` enum('active','blocked') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`)
) ENGINE=InnoDB AUTO_INCREMENT=66 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_departments` (
  `discordid` varchar(255) NOT NULL,
  `department` varchar(100) NOT NULL,
  `paycheck` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`discordid`,`department`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_payments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `payee` varchar(255) NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `schedule_date` date NOT NULL,
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_profile` (
  `discordid` varchar(255) NOT NULL,
  `user_id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  PRIMARY KEY (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `econ_user_money` (
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `firstname` varchar(100) NOT NULL DEFAULT '',
  `lastname` varchar(100) NOT NULL DEFAULT '',
  `profile_picture` varchar(255) DEFAULT NULL,
  `cash` int(11) NOT NULL DEFAULT 0,
  `bank` int(11) NOT NULL DEFAULT 0,
  `last_daily` bigint(20) NOT NULL DEFAULT 0,
  `card_number` varchar(16) DEFAULT NULL,
  `exp_month` tinyint(4) DEFAULT NULL,
  `exp_year` smallint(6) DEFAULT NULL,
  `card_status` enum('active','blocked') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`discordid`,`charid`),
  CONSTRAINT `chk_eum_charid_not_blank` CHECK (`charid` <> '')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `jail_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `jailer_discord` varchar(50) NOT NULL,
  `inmate_discord` varchar(50) NOT NULL,
  `time_minutes` int(11) NOT NULL,
  `date` datetime NOT NULL,
  `charges` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_characters` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `name` varchar(100) NOT NULL,
  `active_department` varchar(100) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `discord_char` (`discordid`,`charid`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_inventory` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `item` varchar(64) NOT NULL,
  `count` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uix_inventory` (`discordid`,`charid`,`item`),
  CONSTRAINT `fk_inv_characters` FOREIGN KEY (`discordid`, `charid`) REFERENCES `user_characters` (`discordid`, `charid`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_levels` (
  `identifier` varchar(100) NOT NULL,
  `rp_total` bigint(20) NOT NULL DEFAULT 0,
  `rp_stamina` bigint(20) NOT NULL DEFAULT 0,
  `rp_strength` bigint(20) NOT NULL DEFAULT 0,
  `rp_driving` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_vehicles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `plate` varchar(20) NOT NULL,
  `model` varchar(50) NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `h` double NOT NULL,
  `color1` int(11) NOT NULL,
  `color2` int(11) NOT NULL,
  `pearlescent` int(11) NOT NULL,
  `wheelColor` int(11) NOT NULL,
  `wheelType` int(11) NOT NULL,
  `windowTint` int(11) NOT NULL,
  `mods` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`mods`)),
  `extras` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`extras`)),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_vehicle` (`discordid`,`plate`),
  KEY `idx_discord` (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
}

local function trim(s) return (s and s:gsub("^%s*(.-)%s*$", "%1") or s) end

local function splitTopLevel(body)
    local parts = {}
    local last = 1
    local depth = 0
    local len = #body
    for i = 1, len do
        local c = body:sub(i,i)
        if c == '(' then depth = depth + 1
        elseif c == ')' then if depth > 0 then depth = depth - 1 end
        elseif c == ',' and depth == 0 then
            table.insert(parts, trim(body:sub(last, i - 1)))
            last = i + 1
        end
    end
    if last <= len then table.insert(parts, trim(body:sub(last, len))) end
    return parts
end

local function parseCreate(sql)
    if not sql or type(sql) ~= "string" then return nil, "invalid sql" end
    local info = { name = nil, columns = {}, indexes = {}, constraints = {} }

    local tn = sql:match("CREATE%s+TABLE%s+IF%s+NOT%s+EXISTS%s+`([^`]+)`")
             or sql:match("CREATE%s+TABLE%s+`([^`]+)`")
    if not tn then return nil, "cannot parse table name" end
    info.name = tn

    local bodyWithParens = sql:match("%b()")
    if not bodyWithParens then return nil, "cannot find column body for table "..tn end
    local body = bodyWithParens:sub(2, -2) -- remove surrounding parentheses

    local parts = splitTopLevel(body)
    for _, part in ipairs(parts) do
        local p = trim(part)
        if p:match("^`") then
            local colname = p:match("^`([^`]+)`")
            if colname then
                local def = p:match("^`[^`]+`%s*(.*)$") or ""
                def = trim(def:gsub(",$", ""))
                info.columns[colname] = def
            end
        else
            local clean = p:gsub(",$", "")
            if clean:match("^PRIMARY%s+KEY") then
                info.indexes.primary = clean
            elseif clean:match("^UNIQUE%s+KEY") or clean:match("^UNIQUE") then
                table.insert(info.indexes, clean)
            elseif clean:match("^KEY") or clean:match("^INDEX") then
                table.insert(info.indexes, clean)
            elseif clean:match("^CONSTRAINT") then
                table.insert(info.constraints, clean)
            else
                table.insert(info.indexes, clean)
            end
        end
    end

    return info
end

-- DB query helpers
local function tableExists(tbl)
    local res = MySQL.Sync.fetchAll("SELECT COUNT(*) AS cnt FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=@t", {["@t"]=tbl})
    return (res[1] and tonumber(res[1].cnt) or 0) > 0
end

local function getExistingColumns(tbl)
    local res = MySQL.Sync.fetchAll("SELECT COLUMN_NAME FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name=@t", {["@t"]=tbl})
    local set = {}
    for _, r in ipairs(res) do set[r.COLUMN_NAME] = true end
    return set
end

local function hasPrimaryKey(tbl)
    local res = MySQL.Sync.fetchAll("SELECT CONSTRAINT_NAME FROM information_schema.table_constraints WHERE table_schema=DATABASE() AND table_name=@t AND constraint_type='PRIMARY KEY'", {["@t"]=tbl})
    return (#res > 0)
end

local function indexExists(tbl, idxName)
    local ok, res = pcall(function() return MySQL.Sync.fetchAll("SHOW INDEX FROM `" .. tbl .. "`") end)
    if not ok or not res then return false end
    for _, r in ipairs(res) do
        if r.Key_name == idxName then return true end
    end
    return false
end

local function constraintExists(tbl, constraintName)
    local res = MySQL.Sync.fetchAll("SELECT CONSTRAINT_NAME FROM information_schema.table_constraints WHERE table_schema=DATABASE() AND table_name=@t AND CONSTRAINT_NAME=@c", {["@t"]=tbl, ["@c"]=constraintName})
    return (#res > 0)
end

-- safe execute that treats duplicate-key as success
local function safeExecute(query)
    local ok, res = pcall(function() return MySQL.Sync.execute(query, {}) end)
    if ok then return true, res end
    local msg = tostring(res)
    if msg:match("[Dd]uplicate%s+key%s+name") then return true, "duplicate-ignored" end
    return false, msg
end


local attemptedIndexes = {} -- per-run cache

local function ensureSchemaFromCreate(sql)
    local parsed, err = parseCreate(sql)
    if not parsed then
        print(("[Az-Schema] parse error for SQL: %s"):format(tostring(err)))
        return
    end
    local tbl = parsed.name

    if not tableExists(tbl) then
        print(("[Az-Schema] Table '%s' not found. Creating table..."):format(tbl))
        local ok, res = pcall(function() return MySQL.Sync.execute(sql, {}) end)
        if not ok then
            print(("[Az-Schema] ERROR: Failed to create table '%s' — %s"):format(tbl, tostring(res)))
        else
            print(("[Az-Schema] SUCCESS: Created table '%s'"):format(tbl))
        end
        return
    end

    print(("[Az-Schema] Table '%s' exists — checking columns/indexes/constraints"):format(tbl))

    -- add missing columns
    local existingCols = getExistingColumns(tbl)
    for colName, def in pairs(parsed.columns) do
        if not existingCols[colName] then
            local alter = string.format("ALTER TABLE `%s` ADD COLUMN `%s` %s", tbl, colName, def)
            print(("[Az-Schema] Column '%s' missing in '%s' — adding column with definition: %s"):format(colName, tbl, def))
            local ok, res = pcall(function() return MySQL.Sync.execute(alter, {}) end)
            if not ok then
                print(("[Az-Schema] ERROR: Failed to add column '%s' to '%s' — %s"):format(colName, tbl, tostring(res)))
            else
                print(("[Az-Schema] SUCCESS: Added column '%s' to '%s'"):format(colName, tbl))
            end
        end
    end

    -- primary key
    if parsed.indexes.primary and not hasPrimaryKey(tbl) then
        local cols = parsed.indexes.primary:match("%((.*)%)")
        if cols then
            local q = string.format("ALTER TABLE `%s` ADD PRIMARY KEY (%s)", tbl, cols)
            print(("[Az-Schema] Primary key missing on '%s' — adding PRIMARY KEY on columns: %s"):format(tbl, cols))
            local ok, msg = safeExecute(q)
            if not ok then
                print(("[Az-Schema] ERROR: Failed to add PRIMARY KEY on '%s' — %s"):format(tbl, tostring(msg)))
            else
                print(("[Az-Schema] SUCCESS: PRIMARY KEY added to '%s'"):format(tbl))
            end
        end
    end

    -- other indexes / uniques
    for _, idx in ipairs(parsed.indexes) do
        local name, cols = idx:match("KEY%s+`([^`]+)`%s*%((.-)%)")
                      or idx:match("UNIQUE%s+KEY%s+`([^`]+)`%s*%((.-)%)")
                      or idx:match("UNIQUE%s+`([^`]+)`%s*%((.-)%)")
        if name and cols then
            if indexExists(tbl, name) then
                print(("[Az-Schema] Index '%s' already present on '%s' — skipping"):format(name, tbl))
            else
                local prefix = idx:match("^UNIQUE") and "ADD UNIQUE KEY" or "ADD KEY"
                local q = string.format("ALTER TABLE `%s` %s `%s` (%s)", tbl, prefix, name, cols)
                print(("[Az-Schema] Index '%s' missing on '%s' — adding index on columns: %s"):format(name, tbl, cols))
                local ok, msg = safeExecute(q)
                if not ok then
                    print(("[Az-Schema] ERROR: Failed to add index '%s' to '%s' — %s"):format(name, tbl, tostring(msg)))
                else
                    print(("[Az-Schema] SUCCESS: Index '%s' added to '%s'"):format(name, tbl))
                end
            end
        else
            local colsOnly = idx:match("%((.-)%)")
            if colsOnly then
                local generated = "idx_"..tbl.."_"..colsOnly:gsub("[^%w]+","_")
                if not attemptedIndexes[generated] then
                    attemptedIndexes[generated] = true
                    if indexExists(tbl, generated) then
                        print(("[Az-Schema] Generated index '%s' already exists on '%s' — skipping"):format(generated, tbl))
                    else
                        local isunique = idx:match("^UNIQUE") and "ADD UNIQUE KEY" or "ADD KEY"
                        local q = string.format("ALTER TABLE `%s` %s `%s` (%s)", tbl, isunique, generated, colsOnly)
                        print(("[Az-Schema] Adding unnamed index as '%s' on '%s' for columns: %s"):format(generated, tbl, colsOnly))
                        local ok, msg = safeExecute(q)
                        if not ok then
                            print(("[Az-Schema] ERROR: Failed to add generated index '%s' — %s"):format(generated, tostring(msg)))
                        else
                            if msg == "duplicate-ignored" then
                                print(("[Az-Schema] NOTICE: Generated index '%s' already existed (ignored)"):format(generated))
                            else
                                print(("[Az-Schema] SUCCESS: Generated index '%s' added to '%s'"):format(generated, tbl))
                            end
                        end
                    end
                else
                    print(("[Az-Schema] Skipping repeated attempt to add generated index '%s' in this run"):format(generated))
                end
            end
        end
    end

    -- constraints (best-effort)
    for _, constraint in ipairs(parsed.constraints) do
        local cname = constraint:match("^CONSTRAINT%s+`([^`]+)`")
        if cname and not constraintExists(tbl, cname) then
            local q = "ALTER TABLE `" .. tbl .. "` ADD " .. constraint
            print(("[Az-Schema] Constraint '%s' missing on '%s' — attempting to add"):format(cname, tbl))
            local ok, msg = safeExecute(q)
            if not ok then
                print(("[Az-Schema] ERROR: Failed to add constraint '%s' on '%s' — %s"):format(cname, tbl, tostring(msg)))
            else
                print(("[Az-Schema] SUCCESS: Constraint '%s' added to '%s'"):format(cname, tbl))
            end
        elseif cname then
            print(("[Az-Schema] Constraint '%s' already exists on '%s' — skipping"):format(cname, tbl))
        end
    end
end

function ensureSchemas()
    attemptedIndexes = {}
    print("[Az-Schema] Beginning schema verification and enforcement for configured tables...")
    for _, sql in ipairs(tableSchemas) do
        local ok, err = pcall(function() ensureSchemaFromCreate(sql) end)
        if not ok then
            print(("[Az-Schema] ERROR: schema ensure pass failed — %s"):format(tostring(err)))
        end
    end
    print("[Az-Schema] Schema verification/enforcement run completed.")
end

-- ensure on resource start (keeps previous behavior)
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    ensureSchemas()
end)