Config = Config or {}

local AZ_VERBOSE = Config.AzSchemaVerbose == true
local AZ_LIVE = Config.AzSchemaLive == true
local AZ_SHOW_OK = Config.AzSchemaShowOk == true

local function awaitExec(query, params)
    params = params or {}
    local p = promise.new()
    exports.oxmysql:execute(query, params, function(res) p:resolve(res) end)
    return Citizen.Await(p)
end

local function awaitUpdate(query, params)
    params = params or {}
    local p = promise.new()
    exports.oxmysql:update(query, params, function(res) p:resolve(res) end)
    return Citizen.Await(p)
end

local function dbFetchAll(query, params)
    if exports and exports.oxmysql then
        return awaitExec(query, params)
    end
    return MySQL.Sync.fetchAll(query, params or {})
end

local function dbExecute(query, params)
    if exports and exports.oxmysql then
        return awaitUpdate(query, params)
    end
    return MySQL.Sync.execute(query, params or {})
end

local function trim(s)
    if s == nil then return "" end
    return (tostring(s):gsub("^%s*(.-)%s*$", "%1"))
end

local function normalizeDef(s)
    s = trim(s)
    s = s:gsub(",%s*$", "")
    s = s:gsub("`", "")

    s = s:gsub("current_timestamp%(%s*%)", "current_timestamp")
    s = s:gsub("%s+on%s+update%s+current_timestamp%(%s*%)", " on update current_timestamp")
    s = s:gsub("%s+on%s+update%s+current_timestamp", " on update current_timestamp")

    s = s:gsub("%s+check%s*%b()", "")
    s = s:gsub("%s+comment%s+'[^']*'", "")
    s = s:gsub('%s+comment%s+"[^"]*"', "")

    s = s:gsub("%s+collate%s+'([^']+)'", " collate %1")
    s = s:gsub("%s+character%s+set%s+'([^']+)'", " character set %1")

    s = s:gsub("%s+", " ")
    return s:lower()
end

local function quoteDefault(val)
    if val == nil then return nil end
    local s = tostring(val)
    local up = s:upper()
    if up == "CURRENT_TIMESTAMP" or up == "CURRENT_TIMESTAMP()" then return "CURRENT_TIMESTAMP" end
    if tonumber(s) then return s end
    return "'" .. s:gsub("'", "''") .. "'"
end

local function parseCreate(sql)
    if type(sql) ~= "string" then return nil, "invalid sql" end
    local tn = sql:match("CREATE%s+TABLE%s+IF%s+NOT%s+EXISTS%s+`([^`]+)`") or sql:match("CREATE%s+TABLE%s+`([^`]+)`")
    if not tn then return nil, "cannot parse table name" end

    local info = { name = tn, columns = {}, pk = nil, indexes = {}, constraints = {} }

    for line in sql:gmatch("[^\r\n]+") do
        local l = trim(line)
        if l:match("^`") then
            local col, def = l:match("^`([^`]+)`%s*(.+)$")
            if col and def then
                def = trim(def:gsub(",%s*$", ""))
                info.columns[col] = def
            end
        else
            local pkCols = l:match("^PRIMARY%s+KEY%s*%((.+)%)")
            if pkCols then
                info.pk = trim(pkCols)
            else
                local uname, ucols = l:match("^UNIQUE%s+KEY%s+`([^`]+)`%s*%((.+)%)")
                if uname and ucols then
                    info.indexes[#info.indexes+1] = { name = uname, cols = trim(ucols), unique = true }
                else
                    local kname, kcols = l:match("^KEY%s+`([^`]+)`%s*%((.+)%)") or l:match("^INDEX%s+`([^`]+)`%s*%((.+)%)")
                    if kname and kcols then
                        info.indexes[#info.indexes+1] = { name = kname, cols = trim(kcols), unique = false }
                    else
                        local cname = l:match("^CONSTRAINT%s+`([^`]+)`")
                        if cname then
                            local cdef = trim(l:gsub(",%s*$", ""))
                            info.constraints[#info.constraints+1] = { name = cname, def = cdef }
                        end
                    end
                end
            end
        end
    end

    return info
end

local function tableExists(tbl)
    local res = dbFetchAll("SELECT COUNT(*) AS cnt FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=@t", {["@t"]=tbl})
    return (res[1] and tonumber(res[1].cnt) or 0) > 0
end

local function getColumnDefs(tbl)
    local res = dbFetchAll([[
        SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA, CHARACTER_SET_NAME, COLLATION_NAME
        FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = @t
    ]], {["@t"]=tbl})

    local out = {}
    for _, r in ipairs(res or {}) do
        local parts = {}
        if r.COLUMN_TYPE then parts[#parts+1] = r.COLUMN_TYPE end
        if r.CHARACTER_SET_NAME and r.CHARACTER_SET_NAME ~= "" then parts[#parts+1] = "character set " .. r.CHARACTER_SET_NAME end
        if r.COLLATION_NAME and r.COLLATION_NAME ~= "" then parts[#parts+1] = "collate " .. r.COLLATION_NAME end
        if r.IS_NULLABLE == "NO" then parts[#parts+1] = "not null" else parts[#parts+1] = "null" end
        if r.COLUMN_DEFAULT ~= nil then parts[#parts+1] = "default " .. quoteDefault(r.COLUMN_DEFAULT) end
        if r.EXTRA and r.EXTRA ~= "" then parts[#parts+1] = r.EXTRA end
        out[r.COLUMN_NAME] = normalizeDef(table.concat(parts, " "))
    end
    return out
end

local function hasPrimaryKey(tbl)
    local res = dbFetchAll("SELECT 1 AS ok FROM information_schema.table_constraints WHERE table_schema=DATABASE() AND table_name=@t AND constraint_type='PRIMARY KEY' LIMIT 1", {["@t"]=tbl})
    return res and res[1] ~= nil
end

local function getIndexNames(tbl)
    local ok, res = pcall(function()
        return dbFetchAll("SHOW INDEX FROM `" .. tbl .. "`", {})
    end)
    local set = {}
    if ok and res then
        for _, r in ipairs(res) do
            if r.Key_name then set[r.Key_name] = true end
        end
    end
    return set
end

local function getConstraintNames(tbl)
    local res = dbFetchAll([[
        SELECT CONSTRAINT_NAME
        FROM information_schema.table_constraints
        WHERE table_schema=DATABASE() AND table_name=@t
    ]], {["@t"]=tbl})
    local set = {}
    for _, r in ipairs(res or {}) do
        if r.CONSTRAINT_NAME then set[r.CONSTRAINT_NAME] = true end
    end
    return set
end

local function safeExecute(query)
    local ok, res = pcall(function() return dbExecute(query, {}) end)
    if ok then return true, res end
    local msg = tostring(res)
    if msg:match("[Dd]uplicate%s+key%s+name") then return true, "duplicate-ignored" end
    if msg:match("[Dd]uplicate%s+foreign%s+key") then return true, "duplicate-ignored" end
    if msg:match("[Cc]an%'t%s+create%s+table") and msg:match("[Ff]oreign%s+key") then return false, msg end
    return false, msg
end

local tableResults = {}

local function ensureResult(tbl)
    tableResults[tbl] = tableResults[tbl] or { status = "unknown", msgs = {} }
    return tableResults[tbl]
end

local function pushMsg(tbl, level, txt)
    local tr = ensureResult(tbl)
    tr.msgs[#tr.msgs+1] = ("[%s] %s"):format(level, txt)
    if AZ_VERBOSE and AZ_LIVE then
        if AZ_SHOW_OK or level ~= "info" then
            print(("[Az-Schema][%s] %s: %s"):format(tbl, level, txt))
        end
    end
end

local function setStatus(tbl, status)
    ensureResult(tbl).status = status
end

local function ensureSchemaFromCreate(sql)
    local parsed, err = parseCreate(sql)
    if not parsed then
        pushMsg("PARSE_ERROR", "error", tostring(err))
        setStatus("PARSE_ERROR", "error")
        return
    end

    local tbl = parsed.name
    ensureResult(tbl)

    if not tableExists(tbl) then
        pushMsg(tbl, "info", "Table not found; creating.")
        local ok, msg = safeExecute(sql)
        if not ok then
            pushMsg(tbl, "error", "Create failed: " .. tostring(msg))
            setStatus(tbl, "error")
            return
        end
        pushMsg(tbl, "success", "Created table.")
        setStatus(tbl, "created")
        return
    end

    local changed = false
    pushMsg(tbl, "info", "Verifying schema.")

    local existingDefs = getColumnDefs(tbl)

    for col, desiredRaw in pairs(parsed.columns) do
        local desiredNorm = normalizeDef(desiredRaw)
        if not existingDefs[col] then
            local q = ("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(tbl, col, desiredRaw)
            pushMsg(tbl, "info", "Adding column '" .. col .. "'.")
            local ok, msg = safeExecute(q)
            if not ok then
                pushMsg(tbl, "error", "Add column '" .. col .. "' failed: " .. tostring(msg))
                setStatus(tbl, "error")
            else
                changed = true
                pushMsg(tbl, "success", "Added column '" .. col .. "'.")
            end
        else
            if existingDefs[col] ~= desiredNorm then
                local q = ("ALTER TABLE `%s` MODIFY COLUMN `%s` %s"):format(tbl, col, desiredRaw)
                pushMsg(tbl, "info", "Modifying column '" .. col .. "'.")
                local ok, msg = safeExecute(q)
                if not ok then
                    pushMsg(tbl, "error", "Modify column '" .. col .. "' failed: " .. tostring(msg))
                    setStatus(tbl, "error")
                else
                    changed = true
                    pushMsg(tbl, "success", "Modified column '" .. col .. "'.")
                end
            else
                if AZ_SHOW_OK then pushMsg(tbl, "info", "Column '" .. col .. "' OK.") end
            end
        end
    end

    if parsed.pk and not hasPrimaryKey(tbl) then
        local q = ("ALTER TABLE `%s` ADD PRIMARY KEY (%s)"):format(tbl, parsed.pk)
        pushMsg(tbl, "info", "Adding PRIMARY KEY.")
        local ok, msg = safeExecute(q)
        if not ok then
            pushMsg(tbl, "error", "Add PRIMARY KEY failed: " .. tostring(msg))
            setStatus(tbl, "error")
        else
            changed = true
            pushMsg(tbl, "success", "PRIMARY KEY added.")
        end
    end

    local existingIdx = getIndexNames(tbl)
    for _, idx in ipairs(parsed.indexes or {}) do
        if idx.name and idx.cols then
            if existingIdx[idx.name] then
                if AZ_SHOW_OK then pushMsg(tbl, "info", "Index '" .. idx.name .. "' OK.") end
            else
                local prefix = idx.unique and "ADD UNIQUE KEY" or "ADD KEY"
                local q = ("ALTER TABLE `%s` %s `%s` (%s)"):format(tbl, prefix, idx.name, idx.cols)
                pushMsg(tbl, "info", "Adding index '" .. idx.name .. "'.")
                local ok, msg = safeExecute(q)
                if not ok then
                    pushMsg(tbl, "error", "Add index '" .. idx.name .. "' failed: " .. tostring(msg))
                    setStatus(tbl, "error")
                else
                    changed = true
                    pushMsg(tbl, "success", "Index '" .. idx.name .. "' added.")
                end
            end
        end
    end

    local existingCons = getConstraintNames(tbl)
    for _, c in ipairs(parsed.constraints or {}) do
        if c.name and c.def then
            if existingCons[c.name] then
                if AZ_SHOW_OK then pushMsg(tbl, "info", "Constraint '" .. c.name .. "' OK.") end
            else
                local q = ("ALTER TABLE `%s` ADD %s"):format(tbl, c.def)
                pushMsg(tbl, "info", "Adding constraint '" .. c.name .. "'.")
                local ok, msg = safeExecute(q)
                if not ok then
                    pushMsg(tbl, "error", "Add constraint '" .. c.name .. "' failed: " .. tostring(msg))
                    setStatus(tbl, "error")
                else
                    changed = true
                    pushMsg(tbl, "success", "Constraint '" .. c.name .. "' added.")
                end
            end
        end
    end

    if ensureResult(tbl).status == "error" then
        return
    end

    if changed then
        setStatus(tbl, "altered")
        pushMsg(tbl, "success", "Table altered to match schema.")
    else
        setStatus(tbl, "unchanged")
        pushMsg(tbl, "success", "No changes required.")
    end
end

local function printFinalReport(schemaSqlList)
    print("--------------------------------------------------")
    print("[Az-Schema] Per-table status:")
    print("--------------------------------------------------")

    local created, altered, unchanged, errors = 0, 0, 0, 0

    for _, sql in ipairs(schemaSqlList) do
        local parsed = parseCreate(sql)
        local tbl = parsed and parsed.name or "<unknown>"
        local tr = tableResults[tbl] or { status = "missing", msgs = {} }
        local first = tr.msgs[1] or ""
        local st = tostring(tr.status or "unknown"):upper()
        print(("[Az-Schema] %-22s : %-9s %s"):format(tbl, st, first ~= "" and ("- " .. first) or ""))

        if tr.status == "created" then created = created + 1
        elseif tr.status == "altered" then altered = altered + 1
        elseif tr.status == "unchanged" then unchanged = unchanged + 1
        elseif tr.status == "error" then errors = errors + 1 end
    end

    print("--------------------------------------------------")
    print(("[Az-Schema] Summary: created=%d altered=%d unchanged=%d errors=%d"):format(created, altered, unchanged, errors))

    if errors == 0 then
        print("[Az-Schema] FINAL CHECK: OK — no errors detected.")
    else
        print("[Az-Schema] FINAL CHECK: PROBLEMS — see table errors above.")
    end

    if AZ_VERBOSE then
        print("--------------------------------------------------")
        print("[Az-Schema] Verbose details:")
        for _, sql in ipairs(schemaSqlList) do
            local parsed = parseCreate(sql)
            local tbl = parsed and parsed.name or "<unknown>"
            local tr = tableResults[tbl] or { msgs = {} }
            print(("-- %s --"):format(tbl))
            for _, m in ipairs(tr.msgs or {}) do
                if AZ_SHOW_OK or not m:match("^%[info%] Column '.-' OK%.") then
                    print("   " .. m)
                end
            end
        end
        print("--------------------------------------------------")
    end
end

local tableSchemas = {

[[
CREATE TABLE IF NOT EXISTS `agents` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `profile_picture` varchar(255) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `bio` text DEFAULT NULL,
  `discord_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `first_name` varchar(50) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `phone` varchar(15) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `agent` tinyint(1) NOT NULL DEFAULT 0,
  `role` enum('agent','tenant') NOT NULL DEFAULT 'tenant',
  `name` varchar(255) NOT NULL,
  `profile_picture` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `tenants` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `discord_id` varchar(20) DEFAULT NULL,
  `user_id` int(11) NOT NULL,
  `profile_picture` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `tenants_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `properties` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `agent_id` int(11) DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  `address` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `agent_id` (`agent_id`),
  CONSTRAINT `properties_ibfk_agent` FOREIGN KEY (`agent_id`) REFERENCES `agents` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `garages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `property_id` int(11) NOT NULL,
  `capacity` int(11) NOT NULL DEFAULT 1,
  `location` varchar(255) NOT NULL,
  `latitude` decimal(10,6) NOT NULL,
  `longitude` decimal(10,6) NOT NULL,
  `altitude` decimal(10,2) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `property_id` (`property_id`),
  CONSTRAINT `garages_ibfk_1` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `garage_vehicles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `garage_id` int(11) NOT NULL,
  `model` varchar(255) NOT NULL,
  `plate` varchar(20) NOT NULL,
  `color1` int(11) DEFAULT NULL,
  `color2` int(11) DEFAULT NULL,
  `x` decimal(10,6) NOT NULL,
  `y` decimal(10,6) NOT NULL,
  `z` decimal(10,6) NOT NULL,
  `h` decimal(10,2) NOT NULL,
  `parked` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `garage_id` (`garage_id`),
  CONSTRAINT `garage_vehicles_ibfk_1` FOREIGN KEY (`garage_id`) REFERENCES `garages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `rentals` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `property_id` int(11) NOT NULL,
  `tenant_id` int(11) NOT NULL,
  `start_date` date NOT NULL,
  `rent_amount` decimal(10,2) NOT NULL,
  `status` enum('pending','paid','overdue') DEFAULT 'pending',
  `due_date` date DEFAULT NULL,
  `payment_status` enum('pending','paid','overdue') DEFAULT 'pending',
  `agent_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `property_id` (`property_id`),
  KEY `tenant_id` (`tenant_id`),
  KEY `agent_id` (`agent_id`),
  CONSTRAINT `rentals_ibfk_1` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE,
  CONSTRAINT `rentals_ibfk_2` FOREIGN KEY (`tenant_id`) REFERENCES `tenants` (`id`) ON DELETE CASCADE,
  CONSTRAINT `rentals_ibfk_3` FOREIGN KEY (`agent_id`) REFERENCES `agents` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `role_requests` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `guildId` varchar(24) NOT NULL,
  `requesterId` varchar(24) NOT NULL,
  `targetId` varchar(24) DEFAULT NULL,
  `roleId` varchar(24) NOT NULL,
  `reason` text DEFAULT NULL,
  `status` enum('PENDING','APPROVED','DENIED') DEFAULT 'PENDING',
  `reviewedBy` varchar(24) DEFAULT NULL,
  `reviewedAt` timestamp NULL DEFAULT NULL,
  `reviewMessageId` varchar(32) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `temp_roles` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `guildId` varchar(24) NOT NULL,
  `userId` varchar(24) NOT NULL,
  `roleId` varchar(24) NOT NULL,
  `expiresAt` bigint(20) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_expiresAt` (`expiresAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `global_bans` (
  `userId` varchar(32) NOT NULL,
  `reason` text DEFAULT NULL,
  `addedBy` varchar(32) DEFAULT NULL,
  `addedAt` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`userId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `azfw_appearance` (
  `discordid` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `charid` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `appearance` longtext COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`discordid`,`charid`),
  KEY `idx_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]],
[[
CREATE TABLE IF NOT EXISTS `az_framework_setup` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `setup_key` varchar(64) NOT NULL,
  `setup_value` longtext DEFAULT NULL,
  `updated_by` varchar(128) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_setup_key` (`setup_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `azfw_lastpos` (
  `discordid` varchar(32) NOT NULL,
  `charid` varchar(64) NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` double NOT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`discordid`,`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `azfw_last_locations` (
  `discordid` varchar(64) NOT NULL,
  `charid` varchar(64) NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `h` double NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`discordid`,`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `az_blips` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `sprite` int(11) NOT NULL DEFAULT 1,
  `sprite_name` varchar(64) DEFAULT NULL,
  `color` int(11) NOT NULL DEFAULT 0,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `scale` float NOT NULL DEFAULT 1,
  `short_range` tinyint(1) NOT NULL DEFAULT 1,
  `display` int(11) NOT NULL DEFAULT 4,
  `alpha` int(11) NOT NULL DEFAULT 255,
  `friendly` tinyint(1) NOT NULL DEFAULT 1,
  `visible_for_all` tinyint(1) NOT NULL DEFAULT 1,
  `created_by` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_businesses` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(60) NOT NULL,
  `type` varchar(32) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `owner_charid` varchar(64) NOT NULL,
  `owner_discord` varchar(32) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `location_x` double DEFAULT 0,
  `location_y` double DEFAULT 0,
  `location_z` double DEFAULT 0,
  `heading` double DEFAULT 0,
  `is_open` tinyint(1) DEFAULT 0,
  `business_balance` int(11) DEFAULT 0,
  `tax_rate` double DEFAULT 0,
  `logo_url` varchar(255) DEFAULT NULL,
  `status` varchar(16) DEFAULT 'active',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_business_employees` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `business_id` int(11) NOT NULL,
  `charid` varchar(64) NOT NULL,
  `char_name` varchar(80) DEFAULT NULL,
  `discord` varchar(32) DEFAULT NULL,
  `role` varchar(16) DEFAULT 'employee',
  `is_active` tinyint(1) DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `biz_idx` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_business_inventory` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `business_id` int(11) NOT NULL,
  `item_name` varchar(60) NOT NULL,
  `item_label` varchar(80) NOT NULL,
  `category` varchar(32) DEFAULT NULL,
  `base_cost` int(11) DEFAULT 0,
  `sell_price` int(11) DEFAULT 0,
  `stock` int(11) DEFAULT 0,
  `max_stock` int(11) DEFAULT 0,
  `icon` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `biz_idx` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_business_transactions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `business_id` int(11) NOT NULL,
  `entry_type` varchar(20) NOT NULL,
  `timestamp` timestamp NULL DEFAULT current_timestamp(),
  `customer_charid` varchar(64) DEFAULT NULL,
  `customer_discord` varchar(32) DEFAULT NULL,
  `amount_total` int(11) DEFAULT 0,
  `tax_amount` int(11) DEFAULT 0,
  `items_json` longtext DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `biz_idx` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_guide_categories` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `icon` varchar(64) DEFAULT NULL,
  `parent_id` int(10) unsigned DEFAULT NULL,
  `sort_order` int(11) DEFAULT 0,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_guide_pages` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `category_id` int(10) unsigned NOT NULL,
  `title` varchar(128) NOT NULL,
  `slug` varchar(128) DEFAULT NULL,
  `icon` varchar(64) DEFAULT NULL,
  `order_number` int(11) DEFAULT 0,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `content` longtext DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `category_id` (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_guide_points` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(128) DEFAULT NULL,
  `key_name` varchar(128) DEFAULT NULL,
  `page_id` int(10) unsigned DEFAULT NULL,
  `x` double DEFAULT NULL,
  `y` double DEFAULT NULL,
  `z` double DEFAULT NULL,
  `blip_enabled` tinyint(1) DEFAULT NULL,
  `blip_sprite` int(11) DEFAULT NULL,
  `blip_color` int(11) DEFAULT NULL,
  `marker_enabled` tinyint(1) DEFAULT NULL,
  `marker_type` int(11) DEFAULT NULL,
  `marker_color` varchar(16) DEFAULT NULL,
  `marker_size_x` double DEFAULT NULL,
  `marker_size_y` double DEFAULT NULL,
  `marker_size_z` double DEFAULT NULL,
  `draw_distance` double DEFAULT NULL,
  `enabled` tinyint(1) DEFAULT NULL,
  `can_navigate` tinyint(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `az_id_cards` (
  `char_id` bigint(20) unsigned NOT NULL,
  `discord_id` varchar(32) DEFAULT NULL,
  `mugshot` longtext NOT NULL,
  `issued` int(10) unsigned NOT NULL,
  `expires` int(10) unsigned NOT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `info` longtext DEFAULT NULL,
  PRIMARY KEY (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_vehicle_maintenance` (
  `plate` varchar(16) NOT NULL,
  `mileage` float NOT NULL DEFAULT 0,
  `spark` float NOT NULL DEFAULT 1,
  `oil` float NOT NULL DEFAULT 1,
  `oil_filter` float NOT NULL DEFAULT 1,
  `air_filter` float NOT NULL DEFAULT 1,
  `tires` float NOT NULL DEFAULT 1,
  `brakes` float NOT NULL DEFAULT 1,
  `suspension` float NOT NULL DEFAULT 1,
  `clutch` float NOT NULL DEFAULT 1,
  `last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_vin_records` (
  `vin` varchar(17) NOT NULL,
  `plate` varchar(8) NOT NULL,
  `model` varchar(64) NOT NULL,
  `color` varchar(64) NOT NULL,
  `owner` varchar(64) DEFAULT NULL,
  `registered_at` datetime NOT NULL,
  PRIMARY KEY (`vin`),
  UNIQUE KEY `plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_vin_plates` (
  `plate` varchar(8) NOT NULL,
  `vin` varchar(17) NOT NULL,
  PRIMARY KEY (`plate`),
  KEY `vin` (`vin`),
  CONSTRAINT `az_vin_plates_ibfk_1` FOREIGN KEY (`vin`) REFERENCES `az_vin_records` (`vin`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `arrests` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `netId` varchar(50) DEFAULT NULL,
  `identifier` varchar(64) DEFAULT NULL,
  `first_name` varchar(32) DEFAULT NULL,
  `last_name` varchar(32) DEFAULT NULL,
  `dob` varchar(16) DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `citations` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `netId` varchar(50) DEFAULT NULL,
  `identifier` varchar(64) DEFAULT NULL,
  `reason` text DEFAULT NULL,
  `fine` int(11) DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `dispatch_calls` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `caller_identifier` varchar(64) DEFAULT NULL,
  `caller_name` varchar(128) DEFAULT NULL,
  `location` varchar(128) DEFAULT NULL,
  `message` text DEFAULT NULL,
  `status` enum('ACTIVE','ACK','CLOSED') DEFAULT 'ACTIVE',
  `assigned_to` varchar(64) DEFAULT NULL,
  `assigned_discord` varchar(255) DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `reports` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `creator_identifier` varchar(64) DEFAULT NULL,
  `creator_discord` varchar(128) DEFAULT NULL,
  `title` varchar(128) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `rtype` varchar(32) DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `id_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `netId` varchar(50) DEFAULT NULL,
  `identifier` varchar(64) DEFAULT NULL,
  `first_name` varchar(32) DEFAULT NULL,
  `last_name` varchar(32) DEFAULT NULL,
  `type` varchar(32) DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  `license_status` varchar(32) NOT NULL DEFAULT 'UNKNOWN',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `jail_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `jailer_discord` varchar(50) NOT NULL,
  `inmate_discord` varchar(50) NOT NULL,
  `time_minutes` int(11) NOT NULL,
  `date` datetime NOT NULL,
  `charges` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `plates` (
  `plate` varchar(16) NOT NULL,
  `status` enum('VALID','SUSPENDED','REVOKED') NOT NULL,
  PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `plate_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `plate` varchar(16) DEFAULT NULL,
  `identifier` varchar(64) DEFAULT NULL,
  `first_name` varchar(32) DEFAULT NULL,
  `last_name` varchar(32) DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `warrants` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `subject_name` varchar(128) DEFAULT NULL,
  `subject_netId` varchar(50) DEFAULT NULL,
  `charges` text DEFAULT NULL,
  `issued_by` varchar(64) DEFAULT NULL,
  `active` tinyint(1) DEFAULT 1,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `dmv_progress` (
  `identifier` varchar(64) NOT NULL,
  `written` tinyint(1) NOT NULL DEFAULT 0,
  `driving` tinyint(1) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `duty_hours` (
  `discordId` varchar(50) DEFAULT NULL,
  `inTime` int(11) DEFAULT NULL,
  `outTime` int(11) DEFAULT NULL,
  `department` varchar(50) DEFAULT NULL,
  KEY `idx_dept_time` (`department`,`inTime`,`outTime`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `duty_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `serverid` int(11) NOT NULL,
  `discordid` varchar(64) DEFAULT '',
  `charid` varchar(64) DEFAULT '',
  `action` varchar(16) NOT NULL,
  `timestamp` bigint(20) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `player_playtime` (
  `identifier` varchar(64) NOT NULL,
  `minutes` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `player_notes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `identifier` varchar(50) NOT NULL COMMENT 'Steam identifier',
  `note` longtext NOT NULL,
  `staff` varchar(50) NOT NULL,
  `staff_identifier` varchar(50) DEFAULT NULL,
  `added` datetime NOT NULL DEFAULT current_timestamp(),
  `kicked` tinyint(4) NOT NULL DEFAULT 0,
  `banned` tinyint(4) NOT NULL DEFAULT 0,
  `unbanned` tinyint(4) NOT NULL DEFAULT 0,
  `warned` tinyint(4) NOT NULL DEFAULT 0,
  `expiration` varchar(50) NOT NULL DEFAULT 'N/A',
  `jail` int(4) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `expiration` (`expiration`),
  KEY `idx_player_notes_ident_added` (`identifier`,`added`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `user_levels` (
  `identifier` varchar(100) NOT NULL,
  `rp_total` bigint(20) NOT NULL DEFAULT 0,
  `rp_stamina` bigint(20) NOT NULL DEFAULT 0,
  `rp_strength` bigint(20) NOT NULL DEFAULT 0,
  `rp_driving` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `daily_checkin_rewards` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `month` int(11) NOT NULL,
  `day` int(11) NOT NULL,
  `money` int(11) DEFAULT NULL,
  `weapon` varchar(100) DEFAULT NULL,
  `ammo` int(11) DEFAULT NULL,
  `keys` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `month_day_unique` (`month`,`day`),
  UNIQUE KEY `idx_daily_checkin_rewards__month_day_` (`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `daily_checkin_users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `identifier` varchar(255) NOT NULL,
  `year` int(11) NOT NULL,
  `month` int(11) NOT NULL,
  `claimed_days` text NOT NULL,
  `claimed_count` int(11) NOT NULL DEFAULT 0,
  `keys` int(11) NOT NULL DEFAULT 0,
  `last_spin` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_user_month` (`identifier`,`year`,`month`),
  UNIQUE KEY `idx_daily_checkin_users__identifier_year_month_` (`identifier`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `econ_admins` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `idx_econ_admins__username_` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_profile` (
  `discordid` varchar(255) NOT NULL,
  `user_id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  PRIMARY KEY (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_user_roles` (
  `discordid` varchar(255) NOT NULL,
  `roleid` varchar(255) NOT NULL,
  PRIMARY KEY (`discordid`,`roleid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_user_money` (
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
  KEY `idx_econ_user_money_charid` (`charid`),
  KEY `idx_econ_user_money__charid_` (`charid`),
  CONSTRAINT `chk_eum_charid_not_blank` CHECK (`charid` <> '')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_accounts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL DEFAULT '',
  `type` enum('checking','savings') NOT NULL DEFAULT 'checking',
  `balance` decimal(12,2) NOT NULL DEFAULT 0.00,
  `account_number` varchar(20) NOT NULL DEFAULT '0000000000',
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`),
  KEY `idx_econ_accounts__discordid_` (`discordid`),
  KEY `idx_econ_accounts_charid` (`charid`),
  KEY `idx_econ_accounts__charid_` (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_cards` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL DEFAULT '',
  `card_number` varchar(16) NOT NULL,
  `exp_month` tinyint(4) NOT NULL,
  `exp_year` smallint(6) NOT NULL,
  `status` enum('active','blocked') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`),
  KEY `idx_econ_cards__discordid_` (`discordid`),
  KEY `idx_econ_cards_charid` (`charid`),
  KEY `idx_econ_cards__charid_` (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_departments` (
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL DEFAULT '',
  `department` varchar(100) NOT NULL,
  `paycheck` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`discordid`,`department`),
  KEY `idx_econ_departments_charid` (`charid`),
  KEY `idx_econ_departments__charid_` (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_payments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL DEFAULT '',
  `payee` varchar(255) NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `schedule_date` date NOT NULL,
  PRIMARY KEY (`id`),
  KEY `discordid` (`discordid`),
  KEY `idx_econ_payments__discordid_` (`discordid`),
  KEY `idx_econ_payments_charid` (`charid`),
  KEY `idx_econ_payments__charid_` (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `econ_transactions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(64) DEFAULT '',
  `charid` varchar(100) DEFAULT '',
  `type` varchar(32) NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `counterparty` varchar(255) DEFAULT '',
  `account_id` int(11) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `charid` (`charid`),
  KEY `discordid` (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `user_characters` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `name` varchar(100) NOT NULL,
  `active_department` varchar(100) NOT NULL DEFAULT '',
  `license_status` varchar(32) NOT NULL DEFAULT 'UNKNOWN',
  `hunting_license` tinyint(1) NOT NULL DEFAULT 0,
  `pin_hash` varchar(128) DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `discord_char` (`discordid`,`charid`),
  UNIQUE KEY `idx_user_characters__discordid_charid_` (`discordid`,`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `user_inventory` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `item` varchar(64) NOT NULL,
  `count` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uix_inventory` (`discordid`,`charid`,`item`),
  UNIQUE KEY `idx_user_inventory__discordid_charid_item_` (`discordid`,`charid`,`item`),
  CONSTRAINT `fk_inv_characters` FOREIGN KEY (`discordid`, `charid`) REFERENCES `user_characters` (`discordid`, `charid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `user_vehicles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(64) DEFAULT NULL,
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
  `mods` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `extras` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `parked` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_vehicle` (`discordid`,`plate`),
  UNIQUE KEY `idx_user_vehicles__discordid_plate_` (`discordid`,`plate`),
  KEY `idx_discord` (`discordid`),
  KEY `idx_user_vehicles__discordid_` (`discordid`),
  KEY `idx_user_vehicles_discordid_charid` (`discordid`,`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `user_vehicle_insurance` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `discordid` varchar(32) NOT NULL,
  `charid` varchar(64) DEFAULT NULL,
  `plate` varchar(16) NOT NULL,
  `policy_type` varchar(16) NOT NULL DEFAULT 'standard',
  `premium` int(11) NOT NULL DEFAULT 0,
  `deductible` int(11) NOT NULL DEFAULT 0,
  `vehicle_props` longtext DEFAULT NULL,
  `next_payment_at` int(10) unsigned NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_discord_plate` (`discordid`,`plate`),
  KEY `idx_user_vehicle_insurance_discordid_charid` (`discordid`,`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `user_vehicle_claims` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `discordid` varchar(32) NOT NULL,
  `charid` varchar(64) DEFAULT NULL,
  `plate` varchar(16) NOT NULL,
  `policy_type` varchar(16) NOT NULL,
  `deductible_charged` int(11) NOT NULL DEFAULT 0,
  `payout_value` int(11) NOT NULL DEFAULT 0,
  `filed_at` int(10) unsigned NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'approved',
  PRIMARY KEY (`id`),
  KEY `idx_discord` (`discordid`),
  KEY `idx_user_vehicle_claims_discordid_charid` (`discordid`,`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `mdt_citizens` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `first_name` varchar(64) DEFAULT NULL,
  `last_name` varchar(64) DEFAULT NULL,
  `dob` varchar(32) DEFAULT NULL,
  `gender` varchar(16) DEFAULT NULL,
  `ethnicity` varchar(32) DEFAULT NULL,
  `phone` varchar(32) DEFAULT NULL,
  `image_url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_notes` (
  `citizen_id` int(11) NOT NULL,
  `notes` text DEFAULT NULL,
  PRIMARY KEY (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_properties` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizen_id` int(11) NOT NULL,
  `address` varchar(128) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `citizen_idx` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_vehicles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizen_id` int(11) DEFAULT NULL,
  `plate` varchar(16) NOT NULL,
  `color` varchar(64) DEFAULT NULL,
  `make` varchar(64) DEFAULT NULL,
  `model` varchar(64) DEFAULT NULL,
  `class` varchar(32) DEFAULT NULL,
  `stolen` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `plate_idx` (`plate`),
  KEY `citizen_idx` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_weapons` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizen_id` int(11) DEFAULT NULL,
  `serial` varchar(64) NOT NULL,
  `weapon` varchar(64) DEFAULT NULL,
  `stolen` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `serial_idx` (`serial`),
  KEY `citizen_idx` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_licenses` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizen_id` int(11) NOT NULL,
  `type` varchar(64) NOT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'valid',
  `issued` int(11) DEFAULT NULL,
  `expires` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `citizen_idx` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_charges` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizen_id` int(11) NOT NULL,
  `crime` varchar(128) DEFAULT NULL,
  `type` varchar(32) DEFAULT 'infractions',
  `fine` int(11) DEFAULT 0,
  `timestamp` int(11) DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `citizen_idx` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_identity_flags` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `target_type` varchar(16) NOT NULL,
  `target_value` varchar(128) NOT NULL,
  `flags_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`flags_json`)),
  `notes` text DEFAULT NULL,
  `updated_by` varchar(255) DEFAULT NULL,
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_identity` (`target_type`,`target_value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_id_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `target_type` varchar(16) NOT NULL,
  `target_value` varchar(128) NOT NULL,
  `rtype` varchar(64) NOT NULL,
  `title` varchar(255) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `creator_identifier` varchar(255) DEFAULT NULL,
  `creator_discord` varchar(255) DEFAULT NULL,
  `creator_source` int(11) DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_last_seen` (
  `charid` varchar(64) NOT NULL,
  `last_seen` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_quick_notes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `target_type` varchar(16) NOT NULL,
  `target_value` varchar(128) NOT NULL,
  `note` text NOT NULL,
  `creator_name` varchar(255) DEFAULT NULL,
  `creator_discord` varchar(64) DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_action_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `officer_name` varchar(255) DEFAULT NULL,
  `officer_discord` varchar(64) DEFAULT NULL,
  `action` varchar(255) NOT NULL,
  `target` varchar(255) DEFAULT NULL,
  `meta` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`meta`)),
  `created_at` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_live_chat` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `sender` varchar(128) DEFAULT NULL,
  `source` varchar(64) DEFAULT NULL,
  `message` text DEFAULT NULL,
  `time` varchar(16) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_bolos` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` varchar(16) NOT NULL,
  `data` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_cases` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `officer_name` varchar(64) DEFAULT NULL,
  `subject_name` varchar(64) DEFAULT NULL,
  `summary` text DEFAULT NULL,
  `charges` text DEFAULT NULL,
  `fine` int(11) DEFAULT 0,
  `jail_time` int(11) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_reports` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` varchar(32) NOT NULL,
  `data` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `mdt_warrants` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `target_name` varchar(255) NOT NULL,
  `target_charid` varchar(64) DEFAULT NULL,
  `reason` text NOT NULL,
  `status` enum('active','served','cancelled') DEFAULT 'active',
  `created_by` varchar(255) DEFAULT NULL,
  `created_discord` varchar(64) DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
}

local function ensureSchemas()
    tableResults = {}
    if AZ_VERBOSE and AZ_LIVE then
        print("[Az-Schema] Running (verbose live).")
    else
        print("[Az-Schema] Running.")
    end

    for _, sql in ipairs(tableSchemas) do
        local ok, e = pcall(function() ensureSchemaFromCreate(sql) end)
        if not ok then
            pushMsg("runtime", "error", tostring(e))
            setStatus("runtime", "error")
        end
    end

    printFinalReport(tableSchemas)
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ensureSchemas()
end)

RegisterCommand("azschema", function(_, args)
    local a = (args[1] or "run"):lower()
    if a == "run" then
        AZ_VERBOSE = false
        AZ_LIVE = false
        ensureSchemas()
        return
    end
    if a == "verbose" then
        AZ_VERBOSE = true
        AZ_LIVE = true
        ensureSchemas()
        return
    end
    if a == "status" then
        printFinalReport(tableSchemas)
        return
    end
    print("azschema run | azschema verbose | azschema status")
end, false)
