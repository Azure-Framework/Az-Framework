// File: decommented-pasted.lua



Config = Config or {}

local function cfgBool(key, default)
  local v = Config[key]
  if v == nil then return default end
  return v == true
end

local AZ_VERBOSE    = cfgBool("AzSchemaVerbose", false)
local AZ_LIVE       = cfgBool("AzSchemaLive", false)
local AZ_SHOW_OK    = cfgBool("AzSchemaShowOk", false)

local AZ_FIX_PK              = cfgBool("AzSchemaFixPrimaryKey", false)
local AZ_FIX_INDEXES         = cfgBool("AzSchemaFixIndexes", true)
local AZ_FIX_CONSTRAINTS     = cfgBool("AzSchemaFixConstraints", false)
local AZ_FIX_TABLE_OPTIONS   = cfgBool("AzSchemaFixTableOptions", false)

local AZ_PRUNE_EXTRA_COLUMNS      = cfgBool("AzSchemaPruneExtraColumns", false)
local AZ_PRUNE_EXTRA_INDEXES      = cfgBool("AzSchemaPruneExtraIndexes", false)
local AZ_PRUNE_EXTRA_CONSTRAINTS  = cfgBool("AzSchemaPruneExtraConstraints", false)

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

local function normalizeKeyCols(s)
  s = trim(s or "")
  s = s:gsub("`", "")
  s = s:gsub("%s+", "")
  return s:lower()
end

local function normalizeDef(s)
  s = trim(s or "")
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

local function tableExists(tbl)
  local res = dbFetchAll(
    "SELECT COUNT(*) AS cnt FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=@t",
    {["@t"]=tbl}
  )
  return (res[1] and tonumber(res[1].cnt) or 0) > 0
end

local function listAllTables()
  local res = dbFetchAll([[
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_type='BASE TABLE'
  ]], {})
  local out = {}
  for _, r in ipairs(res or {}) do
    if r.table_name then out[#out+1] = r.table_name end
  end
  table.sort(out)
  return out
end

local function getCurrentCreate(tbl)
  local ok, res = pcall(function()
    return dbFetchAll("SHOW CREATE TABLE `" .. tbl .. "`", {})
  end)
  if not ok or not res or not res[1] then return nil end

  local row = res[1]

  for k, v in pairs(row) do
    if type(v) == "string" and v:match("^CREATE%s+TABLE") then
      return v
    end
  end
  return nil
end

local function parseCreate(sql)
  if type(sql) ~= "string" then return nil, "invalid sql" end
  local tn =
    sql:match("CREATE%s+TABLE%s+IF%s+NOT%s+EXISTS%s+`([^`]+)`") or
    sql:match("CREATE%s+TABLE%s+`([^`]+)`")
  if not tn then return nil, "cannot parse table name" end

  local info = {
    name = tn,
    columns = {},
    pk = nil,
    indexes = {},
    constraints = {},
    options = { engine = nil, charset = nil, collate = nil },
  }

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

  local tail = sql:match("%)%s*(.-)%s*;?%s*$") or ""
  tail = tail:gsub("%s+", " ")

  local engine = tail:match("[Ee][Nn][Gg][Ii][Nn][Ee]%s*=%s*([%w_]+)")
  local charset = tail:match("[Cc][Hh][Aa][Rr][Ss][Ee][Tt]%s*=%s*([%w_]+)") or tail:match("[Dd][Ee][Ff][Aa][Uu][Ll][Tt]%s+[Cc][Hh][Aa][Rr][Ss][Ee][Tt]%s*=%s*([%w_]+)")
  local collate = tail:match("[Cc][Oo][Ll][Ll][Aa][Tt][Ee]%s*=%s*([%w_]+)")

  info.options.engine = engine
  info.options.charset = charset
  info.options.collate = collate

  return info
end

local function getExistingParsed(tbl)
  local createSql = getCurrentCreate(tbl)
  if not createSql then return nil end
  local parsed = select(1, parseCreate(createSql))
  return parsed
end

local function buildIndexSig(idx)
  local u = idx.unique and "u" or "n"
  return u .. ":" .. normalizeKeyCols(idx.cols or "")
end

local function buildConstraintSig(def)
  return normalizeDef(def or "")
end

local function buildColumnsSigMap(columnsMap)
  local out = {}
  for col, def in pairs(columnsMap or {}) do
    out[col] = normalizeDef(def)
  end
  return out
end

local function safeExecute(query)
  local ok, res = pcall(function() return dbExecute(query, {}) end)
  if ok then return true, res end
  local msg = tostring(res)

  if msg:match("[Dd]uplicate%s+key%s+name") then return true, "duplicate-ignored" end
  if msg:match("[Dd]uplicate%s+foreign%s+key") then return true, "duplicate-ignored" end
  if msg:match("[Dd]uplicate%s+column%s+name") then return true, "duplicate-ignored" end
  if msg:match("[Cc]olumn%s+already%s+exists") then return true, "duplicate-ignored" end

  return false, msg
end

local tableResults = {}

local function ensureResult(tbl)
  tableResults[tbl] = tableResults[tbl] or {
    status = "unknown",
    msgs = {},
    extras = { columns = {}, indexes = {}, constraints = {} },
    mismatches = { pk = false, indexes = {}, constraints = {}, options = {} },
  }
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

local function ensureTableOptions(tbl, desiredOpts, existingOpts)
  if not desiredOpts then return false end
  if not existingOpts then return false end

  local changed = false
  local dE, dC, dCo = desiredOpts.engine, desiredOpts.charset, desiredOpts.collate
  local eE, eC, eCo = existingOpts.engine, existingOpts.charset, existingOpts.collate

  local function neq(a, b)
    a = trim(a or ""):lower()
    b = trim(b or ""):lower()
    if a == "" and b == "" then return false end
    return a ~= b
  end

  if (dE and neq(dE, eE)) or (dC and neq(dC, eC)) or (dCo and neq(dCo, eCo)) then
    ensureResult(tbl).mismatches.options = { desired = desiredOpts, existing = existingOpts }

    if not AZ_FIX_TABLE_OPTIONS then
      pushMsg(tbl, "warn", ("Table options differ (engine/charset/collate). Existing: %s/%s/%s, Desired: %s/%s/%s")
        :format(tostring(eE), tostring(eC), tostring(eCo), tostring(dE), tostring(dC), tostring(dCo)))
      return false
    end

    if dE and neq(dE, eE) then
      local q = ("ALTER TABLE `%s` ENGINE=%s"):format(tbl, dE)
      pushMsg(tbl, "info", "Fixing ENGINE.")
      local ok, msg = safeExecute(q)
      if ok then
        changed = true
        pushMsg(tbl, "success", "ENGINE updated.")
      else
        pushMsg(tbl, "error", "ENGINE update failed: " .. tostring(msg))
        setStatus(tbl, "error")
      end
    end

    if (dC and neq(dC, eC)) or (dCo and neq(dCo, eCo)) then
      local parts = {}
      if dC then parts[#parts+1] = "DEFAULT CHARACTER SET " .. dC end
      if dCo then parts[#parts+1] = "COLLATE " .. dCo end

      local q = ("ALTER TABLE `%s` %s"):format(tbl, table.concat(parts, " "))
      pushMsg(tbl, "info", "Fixing DEFAULT CHARSET/COLLATE.")
      local ok, msg = safeExecute(q)
      if ok then
        changed = true
        pushMsg(tbl, "success", "DEFAULT CHARSET/COLLATE updated.")
      else
        pushMsg(tbl, "error", "DEFAULT CHARSET/COLLATE update failed: " .. tostring(msg))
        setStatus(tbl, "error")
      end
    end
  end

  return changed
end

local function dropIndex(tbl, name)
  local q = ("ALTER TABLE `%s` DROP INDEX `%s`"):format(tbl, name)
  return safeExecute(q)
end

local function dropPrimaryKey(tbl)
  local q = ("ALTER TABLE `%s` DROP PRIMARY KEY"):format(tbl)
  return safeExecute(q)
end

local function dropConstraint(tbl, cname, cdefNorm)

  local isFK = (cdefNorm or ""):find("foreign key", 1, true) ~= nil
  local q
  if isFK then
    q = ("ALTER TABLE `%s` DROP FOREIGN KEY `%s`"):format(tbl, cname)
  else

    q = ("ALTER TABLE `%s` DROP CONSTRAINT `%s`"):format(tbl, cname)
  end
  return safeExecute(q)
end

local function ensureSchemaFromCreate(sql, phase)
  local parsed, err = parseCreate(sql)
  if not parsed then
    pushMsg("PARSE_ERROR", "error", tostring(err))
    setStatus("PARSE_ERROR", "error")
    return
  end

  local tbl = parsed.name
  ensureResult(tbl)

  if not tableExists(tbl) then

    if phase ~= 1 then return end

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

  local existingParsed = getExistingParsed(tbl)
  if not existingParsed then
    pushMsg(tbl, "error", "Could not read current schema (SHOW CREATE TABLE failed).")
    setStatus(tbl, "error")
    return
  end

  local changed = false

  if phase == 1 then
    pushMsg(tbl, "info", "Verifying table/columns/indexes/pk/options.")

    local desiredColsNorm = buildColumnsSigMap(parsed.columns)
    local existingColsNorm = buildColumnsSigMap(existingParsed.columns)

    for col, desiredRaw in pairs(parsed.columns) do
      local desiredNorm = desiredColsNorm[col]
      if not existingColsNorm[col] then
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
        if existingColsNorm[col] ~= desiredNorm then
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

    for col, _ in pairs(existingParsed.columns or {}) do
      if not parsed.columns[col] then
        ensureResult(tbl).extras.columns[#ensureResult(tbl).extras.columns+1] = col
      end
    end
    table.sort(ensureResult(tbl).extras.columns)

    if AZ_PRUNE_EXTRA_COLUMNS and #ensureResult(tbl).extras.columns > 0 then
      for _, col in ipairs(ensureResult(tbl).extras.columns) do
        local q = ("ALTER TABLE `%s` DROP COLUMN `%s`"):format(tbl, col)
        pushMsg(tbl, "warn", "Dropping extra column '" .. col .. "'.")
        local ok, msg = safeExecute(q)
        if ok then
          changed = true
          pushMsg(tbl, "success", "Dropped extra column '" .. col .. "'.")
        else
          pushMsg(tbl, "error", "Drop extra column '" .. col .. "' failed: " .. tostring(msg))
          setStatus(tbl, "error")
        end
      end
    end

    local desiredPK = normalizeKeyCols(parsed.pk or "")
    local existingPK = normalizeKeyCols(existingParsed.pk or "")

    if parsed.pk and (existingParsed.pk == nil or existingParsed.pk == "") then
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
    elseif parsed.pk and existingParsed.pk and desiredPK ~= "" and existingPK ~= "" and desiredPK ~= existingPK then
      ensureResult(tbl).mismatches.pk = true
      if AZ_FIX_PK then
        pushMsg(tbl, "warn", "PRIMARY KEY mismatch — fixing (drop + add).")
        local ok1, msg1 = dropPrimaryKey(tbl)
        if not ok1 then
          pushMsg(tbl, "error", "Drop PRIMARY KEY failed: " .. tostring(msg1))
          setStatus(tbl, "error")
        else
          local q = ("ALTER TABLE `%s` ADD PRIMARY KEY (%s)"):format(tbl, parsed.pk)
          local ok2, msg2 = safeExecute(q)
          if not ok2 then
            pushMsg(tbl, "error", "Re-add PRIMARY KEY failed: " .. tostring(msg2))
            setStatus(tbl, "error")
          else
            changed = true
            pushMsg(tbl, "success", "PRIMARY KEY fixed.")
          end
        end
      else
        pushMsg(tbl, "warn", ("PRIMARY KEY differs. Existing=(%s) Desired=(%s) (enable AzSchemaFixPrimaryKey to auto-fix)")
          :format(tostring(existingParsed.pk), tostring(parsed.pk)))
      end
    else
      if AZ_SHOW_OK and parsed.pk then pushMsg(tbl, "info", "PRIMARY KEY OK.") end
    end

    local desiredIdxMap = {}
    for _, idx in ipairs(parsed.indexes or {}) do
      desiredIdxMap[idx.name] = buildIndexSig(idx)
    end

    local existingIdxMap = {}
    for _, idx in ipairs(existingParsed.indexes or {}) do
      existingIdxMap[idx.name] = buildIndexSig(idx)
    end

    for _, idx in ipairs(parsed.indexes or {}) do
      if idx.name and idx.cols then
        local dSig = desiredIdxMap[idx.name]
        local eSig = existingIdxMap[idx.name]

        if not eSig then
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
        else
          if eSig ~= dSig then
            ensureResult(tbl).mismatches.indexes[idx.name] = { existing = eSig, desired = dSig }
            if AZ_FIX_INDEXES then
              pushMsg(tbl, "warn", "Index '" .. idx.name .. "' differs — fixing (drop + add).")
              local ok1, msg1 = dropIndex(tbl, idx.name)
              if not ok1 then
                pushMsg(tbl, "error", "Drop index '" .. idx.name .. "' failed: " .. tostring(msg1))
                setStatus(tbl, "error")
              else
                local prefix = idx.unique and "ADD UNIQUE KEY" or "ADD KEY"
                local q = ("ALTER TABLE `%s` %s `%s` (%s)"):format(tbl, prefix, idx.name, idx.cols)
                local ok2, msg2 = safeExecute(q)
                if not ok2 then
                  pushMsg(tbl, "error", "Re-add index '" .. idx.name .. "' failed: " .. tostring(msg2))
                  setStatus(tbl, "error")
                else
                  changed = true
                  pushMsg(tbl, "success", "Index '" .. idx.name .. "' fixed.")
                end
              end
            else
              pushMsg(tbl, "warn", "Index '" .. idx.name .. "' differs (AzSchemaFixIndexes disabled).")
            end
          else
            if AZ_SHOW_OK then pushMsg(tbl, "info", "Index '" .. idx.name .. "' OK.") end
          end
        end
      end
    end

    for name, _ in pairs(existingIdxMap) do
      if name ~= "PRIMARY" and not desiredIdxMap[name] then
        ensureResult(tbl).extras.indexes[#ensureResult(tbl).extras.indexes+1] = name
      end
    end
    table.sort(ensureResult(tbl).extras.indexes)

    if AZ_PRUNE_EXTRA_INDEXES and #ensureResult(tbl).extras.indexes > 0 then
      for _, name in ipairs(ensureResult(tbl).extras.indexes) do

        pushMsg(tbl, "warn", "Dropping extra index '" .. name .. "'.")
        local ok, msg = dropIndex(tbl, name)
        if ok then
          changed = true
          pushMsg(tbl, "success", "Dropped extra index '" .. name .. "'.")
        else
          pushMsg(tbl, "error", "Drop extra index '" .. name .. "' failed: " .. tostring(msg))
          setStatus(tbl, "error")
        end
      end
    end

    local optChanged = ensureTableOptions(tbl, parsed.options, existingParsed.options)
    if optChanged then changed = true end

    if ensureResult(tbl).status == "error" then
      return
    end

    if changed then
      if ensureResult(tbl).status ~= "created" then
        setStatus(tbl, "altered")
      end
      pushMsg(tbl, "success", "Phase 1 complete.")
    else
      if ensureResult(tbl).status ~= "created" then
        setStatus(tbl, "unchanged")
      end
      pushMsg(tbl, "success", "No changes required (phase 1).")
    end

  elseif phase == 2 then

    pushMsg(tbl, "info", "Verifying constraints (phase 2).")

    local desiredConsMap = {}
    for _, c in ipairs(parsed.constraints or {}) do
      desiredConsMap[c.name] = buildConstraintSig(c.def)
    end

    local existingConsMap = {}
    for _, c in ipairs(existingParsed.constraints or {}) do
      existingConsMap[c.name] = buildConstraintSig(c.def)
    end

    local phase2Changed = false

    for _, c in ipairs(parsed.constraints or {}) do
      if c.name and c.def then
        local dSig = desiredConsMap[c.name]
        local eSig = existingConsMap[c.name]

        if not eSig then
          local q = ("ALTER TABLE `%s` ADD %s"):format(tbl, c.def)
          pushMsg(tbl, "info", "Adding constraint '" .. c.name .. "'.")
          local ok, msg = safeExecute(q)
          if not ok then
            pushMsg(tbl, "error", "Add constraint '" .. c.name .. "' failed: " .. tostring(msg))
            setStatus(tbl, "error")
          else
            phase2Changed = true
            pushMsg(tbl, "success", "Constraint '" .. c.name .. "' added.")
          end
        else
          if eSig ~= dSig then
            ensureResult(tbl).mismatches.constraints[c.name] = { existing = eSig, desired = dSig }
            if AZ_FIX_CONSTRAINTS then
              pushMsg(tbl, "warn", "Constraint '" .. c.name .. "' differs — fixing (drop + add).")
              local ok1, msg1 = dropConstraint(tbl, c.name, eSig)
              if not ok1 then
                pushMsg(tbl, "error", "Drop constraint '" .. c.name .. "' failed: " .. tostring(msg1))
                setStatus(tbl, "error")
              else
                local q = ("ALTER TABLE `%s` ADD %s"):format(tbl, c.def)
                local ok2, msg2 = safeExecute(q)
                if not ok2 then
                  pushMsg(tbl, "error", "Re-add constraint '" .. c.name .. "' failed: " .. tostring(msg2))
                  setStatus(tbl, "error")
                else
                  phase2Changed = true
                  pushMsg(tbl, "success", "Constraint '" .. c.name .. "' fixed.")
                end
              end
            else
              pushMsg(tbl, "warn", "Constraint '" .. c.name .. "' differs (AzSchemaFixConstraints disabled).")
            end
          else
            if AZ_SHOW_OK then pushMsg(tbl, "info", "Constraint '" .. c.name .. "' OK.") end
          end
        end
      end
    end

    for name, _ in pairs(existingConsMap) do

      if name ~= "PRIMARY" and not desiredConsMap[name] then
        ensureResult(tbl).extras.constraints[#ensureResult(tbl).extras.constraints+1] = name
      end
    end
    table.sort(ensureResult(tbl).extras.constraints)

    if AZ_PRUNE_EXTRA_CONSTRAINTS and #ensureResult(tbl).extras.constraints > 0 then
      for _, name in ipairs(ensureResult(tbl).extras.constraints) do
        local eSig = existingConsMap[name] or ""
        pushMsg(tbl, "warn", "Dropping extra constraint '" .. name .. "'.")
        local ok, msg = dropConstraint(tbl, name, eSig)
        if ok then
          phase2Changed = true
          pushMsg(tbl, "success", "Dropped extra constraint '" .. name .. "'.")
        else
          pushMsg(tbl, "error", "Drop extra constraint '" .. name .. "' failed: " .. tostring(msg))
          setStatus(tbl, "error")
        end
      end
    end

    if ensureResult(tbl).status == "error" then
      return
    end

    if phase2Changed then
      if ensureResult(tbl).status == "unchanged" then setStatus(tbl, "altered") end
      pushMsg(tbl, "success", "Phase 2 complete.")
    else
      pushMsg(tbl, "success", "No changes required (phase 2).")
    end
  end
end

local function printFinalReport(schemaSqlList, desiredTableSet)
  print("
  print("[Az-Schema] Per-table status:")
  print("

  local created, altered, unchanged, errors = 0, 0, 0, 0

  for _, sql in ipairs(schemaSqlList) do
    local parsed = select(1, parseCreate(sql))
    local tbl = parsed and parsed.name or "<unknown>"
    local tr = tableResults[tbl] or { status = "missing", msgs = {}, extras = {columns={},indexes={},constraints={}} }
    local first = tr.msgs[1] or ""
    local st = tostring(tr.status or "unknown"):upper()
    print(("[Az-Schema] %-22s : %-9s %s"):format(tbl, st, first ~= "" and ("- " .. first) or ""))

    if tr.status == "created" then created = created + 1
    elseif tr.status == "altered" then altered = altered + 1
    elseif tr.status == "unchanged" then unchanged = unchanged + 1
    elseif tr.status == "error" then errors = errors + 1 end

    local exCols = tr.extras and tr.extras.columns or {}
    local exIdx  = tr.extras and tr.extras.indexes or {}
    local exCon  = tr.extras and tr.extras.constraints or {}

    if #exCols > 0 then
      print(("  -> EXTRA COLUMNS (%d): %s"):format(#exCols, table.concat(exCols, ", ")))
    end
    if #exIdx > 0 then
      print(("  -> EXTRA INDEXES (%d): %s"):format(#exIdx, table.concat(exIdx, ", ")))
    end
    if #exCon > 0 then
      print(("  -> EXTRA CONSTRAINTS (%d): %s"):format(#exCon, table.concat(exCon, ", ")))
    end
  end

  print("
  print(("[Az-Schema] Summary: created=%d altered=%d unchanged=%d errors=%d"):format(created, altered, unchanged, errors))

  local allTables = listAllTables()
  local extraTables = {}
  for _, t in ipairs(allTables) do
    if not desiredTableSet[t] then
      extraTables[#extraTables+1] = t
    end
  end

  if #extraTables > 0 then
    print("
    print(("[Az-Schema] EXTRA TABLES in DB not in schema list (%d):"):format(#extraTables))
    print("  " .. table.concat(extraTables, ", "))
  end

  if errors == 0 then
    print("[Az-Schema] FINAL CHECK: OK — no errors detected.")
  else
    print("[Az-Schema] FINAL CHECK: PROBLEMS — see table errors above.")
  end

  if AZ_VERBOSE then
    print("
    print("[Az-Schema] Verbose details:")
    for _, sql in ipairs(schemaSqlList) do
      local parsed = select(1, parseCreate(sql))
      local tbl = parsed and parsed.name or "<unknown>"
      local tr = tableResults[tbl] or { msgs = {} }
      print(("
      for _, m in ipairs(tr.msgs or {}) do
        if AZ_SHOW_OK or not m:match("^%[info%] Column '.-' OK%.") then
          print("   " .. m)
        end
      end
    end
    print("
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
CREATE TABLE IF NOT EXISTS `azfw_characters` (
  `discordid` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `charid` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `first` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `last` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`discordid`,`charid`),
  KEY `idx_discordid` (`discordid`),
  KEY `idx_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
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
CREATE TABLE IF NOT EXISTS `az_houses` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `label` varchar(128) DEFAULT NULL,
  `price` int(11) NOT NULL DEFAULT 0,
  `interior` varchar(32) NOT NULL DEFAULT 'apt_basic',
  `locked` tinyint(1) NOT NULL DEFAULT 1,
  `owner_identifier` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  `image_url` text DEFAULT NULL,
  `image_data` longtext DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_apps` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `house_id` int(11) NOT NULL,
  `applicant_identifier` varchar(64) NOT NULL,
  `message` text DEFAULT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'pending',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_house_id` (`house_id`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_doors` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `house_id` int(11) NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` double NOT NULL DEFAULT 0,
  `radius` double NOT NULL DEFAULT 2,
  `label` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_house_id` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_furniture` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `house_id` int(11) NOT NULL,
  `owner_identifier` varchar(64) DEFAULT NULL,
  `model` varchar(96) NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` double NOT NULL DEFAULT 0,
  `rot_x` double NOT NULL DEFAULT 0,
  `rot_y` double NOT NULL DEFAULT 0,
  `rot_z` double NOT NULL DEFAULT 0,
  `meta_json` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_house_id` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_garages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `house_id` int(11) NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` double NOT NULL DEFAULT 0,
  `spawn_x` double NOT NULL,
  `spawn_y` double NOT NULL,
  `spawn_z` double NOT NULL,
  `spawn_h` double NOT NULL DEFAULT 0,
  `radius` double NOT NULL DEFAULT 2.2,
  `label` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_house_id` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_keys` (
  `house_id` int(11) NOT NULL,
  `identifier` varchar(64) NOT NULL,
  `perms` varchar(16) NOT NULL DEFAULT 'enter',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`house_id`,`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_mail` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `house_id` int(11) NOT NULL,
  `sender_identifier` varchar(64) DEFAULT NULL,
  `sender_name` varchar(64) DEFAULT NULL,
  `subject` varchar(96) NOT NULL,
  `body` text DEFAULT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_house_id` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_rentals` (
  `house_id` int(11) NOT NULL,
  `is_listed` tinyint(1) NOT NULL DEFAULT 0,
  `rent_per_week` int(11) NOT NULL DEFAULT 0,
  `deposit` int(11) NOT NULL DEFAULT 0,
  `tenant_identifier` varchar(64) DEFAULT NULL,
  `agent_identifier` varchar(64) DEFAULT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'available',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  PRIMARY KEY (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_upgrades` (
  `house_id` int(11) NOT NULL,
  `mailbox_level` int(11) NOT NULL DEFAULT 0,
  `decor_level` int(11) NOT NULL DEFAULT 0,
  `storage_level` int(11) NOT NULL DEFAULT 0,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_house_vehicles` (
  `house_id` int(11) NOT NULL,
  `plate` varchar(16) NOT NULL,
  `owner_identifier` varchar(64) NOT NULL,
  `props_json` longtext NOT NULL,
  `stored` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  PRIMARY KEY (`house_id`,`plate`),
  UNIQUE KEY `uniq_house_plate` (`house_id`,`plate`),
  KEY `idx_owner` (`owner_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],

[[
CREATE TABLE IF NOT EXISTS `az_marketplace_listings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `listing_type` varchar(16) NOT NULL DEFAULT 'item',
  `category` varchar(32) NOT NULL DEFAULT 'classifieds',
  `title` varchar(64) NOT NULL,
  `price` int(11) NOT NULL DEFAULT 0,
  `currency` varchar(8) NOT NULL DEFAULT '$',
  `condition` varchar(24) NOT NULL DEFAULT 'Used - Good',
  `description` varchar(800) DEFAULT NULL,
  `images` longtext DEFAULT NULL,
  `location_x` double NOT NULL DEFAULT 0,
  `location_y` double NOT NULL DEFAULT 0,
  `location_z` double NOT NULL DEFAULT 0,
  `location_label` varchar(64) NOT NULL DEFAULT '',
  `seller_discord` varchar(64) NOT NULL,
  `seller_charid` varchar(64) DEFAULT NULL,
  `seller_name` varchar(100) DEFAULT NULL,
  `source_ref` varchar(64) DEFAULT NULL,
  `source_json` longtext DEFAULT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`),
  KEY `idx_category` (`category`),
  KEY `idx_listing_type` (`listing_type`),
  KEY `idx_seller` (`seller_discord`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `az_marketplace_messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `listing_id` int(11) NOT NULL,
  `seller_discord` varchar(64) NOT NULL,
  `buyer_discord` varchar(64) NOT NULL,
  `sender_discord` varchar(64) NOT NULL,
  `message` varchar(1000) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_listing` (`listing_id`),
  KEY `idx_pair` (`seller_discord`,`buyer_discord`),
  KEY `idx_sender` (`sender_discord`)
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
  `charid` varchar(100) NOT NULL DEFAULT '',
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
  KEY `idx_user_vehicles__discordid_` (`discordid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `user_vehicle_insurance` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `discordid` varchar(32) NOT NULL,
  `plate` varchar(16) NOT NULL,
  `policy_type` varchar(16) NOT NULL DEFAULT 'standard',
  `premium` int(11) NOT NULL DEFAULT 0,
  `deductible` int(11) NOT NULL DEFAULT 0,
  `vehicle_props` longtext DEFAULT NULL,
  `next_payment_at` int(10) unsigned NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_discord_plate` (`discordid`,`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]],
[[
CREATE TABLE IF NOT EXISTS `user_vehicle_claims` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `discordid` varchar(32) NOT NULL,
  `plate` varchar(16) NOT NULL,
  `policy_type` varchar(16) NOT NULL,
  `deductible_charged` int(11) NOT NULL DEFAULT 0,
  `payout_value` int(11) NOT NULL DEFAULT 0,
  `filed_at` int(10) unsigned NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'approved',
  PRIMARY KEY (`id`),
  KEY `idx_discord` (`discordid`)
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

  local desiredTableSet = {}
  for _, sql in ipairs(tableSchemas) do
    local parsed = select(1, parseCreate(sql))
    if parsed and parsed.name then desiredTableSet[parsed.name] = true end
  end

  if AZ_VERBOSE and AZ_LIVE then
    print("[Az-Schema] Running (verbose live).")
  else
    print("[Az-Schema] Running.")
  end

  for _, sql in ipairs(tableSchemas) do
    local ok, e = pcall(function() ensureSchemaFromCreate(sql, 1) end)
    if not ok then
      pushMsg("runtime", "error", "Phase1 error: " .. tostring(e))
      setStatus("runtime", "error")
    end
  end

  for _, sql in ipairs(tableSchemas) do
    local ok, e = pcall(function() ensureSchemaFromCreate(sql, 2) end)
    if not ok then
      pushMsg("runtime", "error", "Phase2 error: " .. tostring(e))
      setStatus("runtime", "error")
    end
  end

  printFinalReport(tableSchemas, desiredTableSet)
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

    local desiredTableSet = {}
    for _, sql in ipairs(tableSchemas) do
      local parsed = select(1, parseCreate(sql))
      if parsed and parsed.name then desiredTableSet[parsed.name] = true end
    end
    printFinalReport(tableSchemas, desiredTableSet)
    return
  end

  print("azschema run | azschema verbose | azschema status")
end, false)