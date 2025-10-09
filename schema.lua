local AZ_VERBOSE = false -- true = print detailed step-by-step (also prints per-table messages as they happen)

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
    [[CREATE TABLE IF NOT EXISTS `econ_user_roles` (
  `discordid` varchar(255) NOT NULL,
  `roleid` varchar(255) NOT NULL,
  PRIMARY KEY (`discordid`,`roleid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[CREATE TABLE IF NOT EXISTS `user_characters` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `discordid` varchar(255) NOT NULL,
  `charid` varchar(100) NOT NULL,
  `name` varchar(100) NOT NULL,
  `active_department` varchar(100) NOT NULL DEFAULT '',
  `license_status` varchar(32) NOT NULL DEFAULT 'UNKNOWN',
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

-- helpers
local function trim(s) return (s and s:gsub("^%s*(.-)%s*$", "%1") or s) end
local function logVerbose(...) if AZ_VERBOSE then print(...) end end
local function formatLine(...) return table.concat({...}, " ") end

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

-- DB query helpers (unchanged)
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

local function safeExecute(query)
    local ok, res = pcall(function() return MySQL.Sync.execute(query, {}) end)
    if ok then return true, res end
    local msg = tostring(res)
    if msg:match("[Dd]uplicate%s+key%s+name") then return true, "duplicate-ignored" end
    return false, msg
end

local function normalizeDef(s)
    if not s then return "" end
    s = s:gsub("^%s*", ""):gsub("%s*$", "")            -- trim
    s = s:gsub(",%s*$", "")                           -- remove trailing comma
    s = s:gsub("`", "")                               -- remove backticks
    s = s:gsub("%s+", " ")                            -- collapse whitespace
    s = s:lower()
    return s
end

local function quoteDefault(val)
    if val == nil then return nil end
    if tostring(val):upper() == "CURRENT_TIMESTAMP" then return "CURRENT_TIMESTAMP" end
    if tonumber(val) then return tostring(val) end
    return "'" .. tostring(val):gsub("'", "''") .. "'"
end

local function getExistingColumnDef(tbl, col)
    local res = MySQL.Sync.fetchAll([[
        SELECT COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA, CHARACTER_SET_NAME, COLLATION_NAME
        FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = @t AND column_name = @c
    ]], {["@t"] = tbl, ["@c"] = col})

    if not res or not res[1] then return nil end
    local r = res[1]
    local parts = {}

    if r.COLUMN_TYPE then table.insert(parts, r.COLUMN_TYPE) end

    if r.CHARACTER_SET_NAME and r.CHARACTER_SET_NAME ~= "" then
        table.insert(parts, "character set " .. r.CHARACTER_SET_NAME)
    end
    if r.COLLATION_NAME and r.COLLATION_NAME ~= "" then
        table.insert(parts, "collate " .. r.COLLATION_NAME)
    end

    if r.IS_NULLABLE == "NO" then table.insert(parts, "not null")
    else table.insert(parts, "null") end

    if r.COLUMN_DEFAULT ~= nil then
        table.insert(parts, "default " .. quoteDefault(r.COLUMN_DEFAULT))
    end

    if r.EXTRA and r.EXTRA ~= "" then table.insert(parts, r.EXTRA) end

    return normalizeDef(table.concat(parts, " "))
end

local attemptedIndexes = {} -- per-run cache

-- per-table result storage
local tableResults = {} -- tableResults[tableName] = { status = "created"/"altered"/"unchanged"/"error", msgs = { ... } }

local function ensureTableResult(tbl)
    tableResults[tbl] = tableResults[tbl] or { status = "unknown", msgs = {} }
    return tableResults[tbl]
end

local function addTableMsg(tbl, level, txt)
    local tr = ensureTableResult(tbl)
    tr.msgs[#tr.msgs + 1] = ("[%s] %s"):format(level or "info", tostring(txt))
    if AZ_VERBOSE then
        print(("[Az-Schema][%s] %s: %s"):format(tbl, level or "info", txt))
    end
end

local function setTableStatus(tbl, status)
    local tr = ensureTableResult(tbl)
    tr.status = status
end

-- main ensure routine (uses addTableMsg / setTableStatus to record)
local function ensureSchemaFromCreate(sql)
    local parsed, err = parseCreate(sql)
    if not parsed then
        addTableMsg("PARSE_ERROR", "error", tostring(err))
        return
    end
    local tbl = parsed.name
    ensureTableResult(tbl) -- init

    if not tableExists(tbl) then
        -- create
        addTableMsg(tbl, "info", "Table not found; attempting to create.")
        local ok, res = pcall(function() return MySQL.Sync.execute(sql, {}) end)
        if not ok then
            local msg = tostring(res)
            setTableStatus(tbl, "error")
            addTableMsg(tbl, "error", "Failed to create: " .. msg)
            return
        end
        setTableStatus(tbl, "created")
        addTableMsg(tbl, "success", "Created table.")
        return
    end

    -- table exists -> check & mutate
    addTableMsg(tbl, "info", "Table exists; verifying columns/indexes/constraints.")
    local tableChanged = false

    -- columns
    local existingCols = getExistingColumns(tbl)
    for colName, def in pairs(parsed.columns) do
        local desiredDefRaw = trim(def:gsub(",$", ""))
        local desiredNorm = normalizeDef(desiredDefRaw)
        if not existingCols[colName] then
            local q = string.format("ALTER TABLE `%s` ADD COLUMN `%s` %s", tbl, colName, desiredDefRaw)
            addTableMsg(tbl, "info", "Adding missing column '" .. colName .. "'.")
            local ok, res = pcall(function() return MySQL.Sync.execute(q, {}) end)
            if not ok then
                local msg = tostring(res)
                addTableMsg(tbl, "error", ("Failed to add column '%s': %s"):format(colName, msg))
                setTableStatus(tbl, "error")
            else
                tableChanged = true
                addTableMsg(tbl, "success", ("Added column '%s'."):format(colName))
            end
        else
            local existingDef = getExistingColumnDef(tbl, colName)
            if existingDef and existingDef ~= desiredNorm then
                local q = string.format("ALTER TABLE `%s` MODIFY COLUMN `%s` %s", tbl, colName, desiredDefRaw)
                addTableMsg(tbl, "info", ("Column '%s' differs; attempting MODIFY."):format(colName))
                local ok, res = pcall(function() return MySQL.Sync.execute(q, {}) end)
                if not ok then
                    local msg = tostring(res)
                    addTableMsg(tbl, "error", ("Failed to MODIFY column '%s': %s"):format(colName, msg))
                    setTableStatus(tbl, "error")
                else
                    tableChanged = true
                    addTableMsg(tbl, "success", ("Modified column '%s' to match expected definition."):format(colName))
                end
            else
                addTableMsg(tbl, "info", ("Column '%s' OK."):format(colName))
            end
        end
    end

    -- primary key
    if parsed.indexes.primary and not hasPrimaryKey(tbl) then
        local cols = parsed.indexes.primary:match("%((.*)%)")
        if cols then
            local q = string.format("ALTER TABLE `%s` ADD PRIMARY KEY (%s)", tbl, cols)
            addTableMsg(tbl, "info", "Adding PRIMARY KEY: " .. cols)
            local ok, msg = safeExecute(q)
            if not ok then
                addTableMsg(tbl, "error", "Failed to add PRIMARY KEY: " .. tostring(msg))
                setTableStatus(tbl, "error")
            else
                tableChanged = true
                addTableMsg(tbl, "success", "PRIMARY KEY added.")
            end
        end
    else
        addTableMsg(tbl, "info", "PRIMARY KEY present or not defined in schema.")
    end

    -- indexes & uniques (best-effort)
    for _, idx in ipairs(parsed.indexes) do
        local name, cols = idx:match("KEY%s+`([^`]+)`%s*%((.-)%)")
                      or idx:match("UNIQUE%s+KEY%s+`([^`]+)`%s*%((.-)%)")
                      or idx:match("UNIQUE%s+`([^`]+)`%s*%((.-)%)")
        if name and cols then
            if indexExists(tbl, name) then
                addTableMsg(tbl, "info", ("Index '%s' exists."):format(name))
            else
                local prefix = idx:match("^UNIQUE") and "ADD UNIQUE KEY" or "ADD KEY"
                local q = string.format("ALTER TABLE `%s` %s `%s` (%s)", tbl, prefix, name, cols)
                addTableMsg(tbl, "info", ("Adding index '%s' on %s"):format(name, cols))
                local ok, msg = safeExecute(q)
                if not ok then
                    addTableMsg(tbl, "error", ("Failed to add index '%s': %s"):format(name, tostring(msg)))
                    setTableStatus(tbl, "error")
                else
                    tableChanged = true
                    addTableMsg(tbl, "success", ("Index '%s' added."):format(name))
                end
            end
        else
            local colsOnly = idx:match("%((.-)%)")
            if colsOnly then
                local generated = "idx_"..tbl.."_"..colsOnly:gsub("[^%w]+","_")
                if not attemptedIndexes[generated] then
                    attemptedIndexes[generated] = true
                    if indexExists(tbl, generated) then
                        addTableMsg(tbl, "info", ("Generated index '%s' already exists."):format(generated))
                    else
                        local isunique = idx:match("^UNIQUE") and "ADD UNIQUE KEY" or "ADD KEY"
                        local q = string.format("ALTER TABLE `%s` %s `%s` (%s)", tbl, isunique, generated, colsOnly)
                        addTableMsg(tbl, "info", ("Adding generated index '%s'."):format(generated))
                        local ok, msg = safeExecute(q)
                        if not ok then
                            addTableMsg(tbl, "error", ("Failed to add generated index '%s': %s"):format(generated, tostring(msg)))
                            setTableStatus(tbl, "error")
                        else
                            if msg == "duplicate-ignored" then
                                addTableMsg(tbl, "info", ("Generated index '%s' already existed (ignored)."):format(generated))
                            else
                                tableChanged = true
                                addTableMsg(tbl, "success", ("Generated index '%s' added."):format(generated))
                            end
                        end
                    end
                else
                    addTableMsg(tbl, "info", ("Skipping repeated attempt to add generated index '%s' in this run."):format(generated))
                end
            end
        end
    end

    -- constraints (best-effort)
    for _, constraint in ipairs(parsed.constraints) do
        local cname = constraint:match("^CONSTRAINT%s+`([^`]+)`")
        if cname and not constraintExists(tbl, cname) then
            local q = "ALTER TABLE `" .. tbl .. "` ADD " .. constraint
            addTableMsg(tbl, "info", ("Adding constraint '%s'."):format(cname))
            local ok, msg = safeExecute(q)
            if not ok then
                addTableMsg(tbl, "error", ("Failed to add constraint '%s': %s"):format(cname, tostring(msg)))
                setTableStatus(tbl, "error")
            else
                tableChanged = true
                addTableMsg(tbl, "success", ("Constraint '%s' added."):format(cname))
            end
        else
            if cname then addTableMsg(tbl, "info", ("Constraint '%s' present."):format(cname)) end
        end
    end

    -- final per-table status
    if tableResults[tbl].status == "error" then
        -- prior errors already marked
        addTableMsg(tbl, "info", "Completed checks; encountered errors.")
    elseif tableChanged then
        setTableStatus(tbl, "altered")
        addTableMsg(tbl, "success", "Table altered to match schema.")
    else
        setTableStatus(tbl, "unchanged")
        addTableMsg(tbl, "success", "No changes required.")
    end
end

-- Prints a neat line-by-line table report and a final verification checklist
local function printFinalReport()
    print("--------------------------------------------------")
    print("[Az-Schema] Per-table status (one line each):")
    print("--------------------------------------------------")
    -- print all tables in order of tableSchemas so output is predictable
    for _, sql in ipairs(tableSchemas) do
        local parsed = parseCreate(sql)
        local tbl = parsed and parsed.name or "<unknown>"
        local tr = tableResults[tbl] or { status = "missing", msgs = {} }
        local shortMsg = (tr.msgs and tr.msgs[1]) and tr.msgs[1] or ""
        print(("[Az-Schema] %-20s : %-8s %s"):format(tbl, tr.status:upper(), shortMsg and ("- " .. shortMsg) or ""))
    end

    print("--------------------------------------------------")
    -- summary counts
    local counts = { created=0, altered=0, unchanged=0, error=0, unknown=0 }
    for tbl, tr in pairs(tableResults) do
        counts[tr.status] = (counts[tr.status] or 0) + 1
    end
    print(("[Az-Schema] Summary: created=%d  altered=%d  unchanged=%d  errors=%d"):format(counts.created, counts.altered, counts.unchanged, counts.error))

    -- final "good to go" decision
    if counts.error == 0 then
        print("[Az-Schema] FINAL CHECK: OK — no errors detected. Your DB schema is good to go.")
    else
        print(("[Az-Schema] FINAL CHECK: PROBLEMS — %d table(s) reported errors. See details below (use AZ_VERBOSE=true for full logs)."):format(counts.error))
        print("  Tables with errors:")
        for tbl, tr in pairs(tableResults) do
            if tr.status == "error" then
                print(("   - %s (first msg: %s)"):format(tbl, tr.msgs[1] or "no message"))
            end
        end
    end

    print("--------------------------------------------------")
    if AZ_VERBOSE then
        print("[Az-Schema] Full per-table messages (verbose):")
        for _, sql in ipairs(tableSchemas) do
            local parsed = parseCreate(sql)
            local tbl = parsed and parsed.name or "<unknown>"
            local tr = tableResults[tbl] or { msgs = {} }
            print(("-- %s --"):format(tbl))
            for _, m in ipairs(tr.msgs) do
                print("   " .. m)
            end
        end
        print("--------------------------------------------------")
    else
        print("[Az-Schema] For step-by-step details enable AZ_VERBOSE = true.")
    end
end

-- main entrypoint
local function ensureSchemas()
    attemptedIndexes = {}
    tableResults = {}

    print("[Az-Schema] Starting schema verification/enforcement...")
    for _, sql in ipairs(tableSchemas) do
        local ok, err = pcall(function() ensureSchemaFromCreate(sql) end)
        if not ok then
            addTableMsg("runtime", "error", tostring(err))
        end
    end

    print("[Az-Schema] Completed pass; generating report...")
    printFinalReport()
end

-- ensure on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    ensureSchemas()
end)

-- optionally expose a command to re-run and/or print verbose results:
RegisterCommand("azschema", function(source, args)
    local action = args[1]
    if action == "run" or action == nil then
        ensureSchemas()
    elseif action == "verbose" then
        AZ_VERBOSE = true
        ensureSchemas()
    elseif action == "status" then
        printFinalReport()
    else
        print("Usage: azschema [run|verbose|status]")
    end
end, false)