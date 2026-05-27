local Config = Config or {}
Config.Plates = Config.Plates or {}
if Config.Plates.Enabled == false then return end

local function getDiscordId(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'discord:' then
            return id:sub(9)
        end
    end
    return nil
end

local function getCharId(src)
    if GetResourceState('Az-Framework') == 'started' then
        local fw = exports['Az-Framework']
        if fw and fw.GetPlayerCharacter then
            local ok, cid = pcall(function() return fw:GetPlayerCharacter(src) end)
            if ok and cid and tostring(cid) ~= '' then
                return tostring(cid)
            end
        end
    end
    return nil
end

local function normalizePlate(plate)
    plate = tostring(plate or '')
    plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' then return nil end
    return plate:upper()
end

local function kvpKey(src)
    local did = getDiscordId(src) or ('src:' .. tostring(src))
    local cid = getCharId(src) or 'nochar'
    return ('azfw:removedplates:%s:%s'):format(did, cid)
end

local function loadList(src)
    local raw = GetResourceKvpString(kvpKey(src))
    if not raw or raw == '' then return {} end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then return data end
    return {}
end

local function saveList(src, list)
    SetResourceKvp(kvpKey(src), json.encode(list or {}))
end

local function pushPlate(list, text, meta)
    text = normalizePlate(text)
    if not text then return list end
    list[#list + 1] = {
        id = ('%s:%s'):format(os.time(), math.random(1000, 999999)),
        text = text,
        removedAt = os.time(),
        meta = meta or {},
    }
    return list
end

lib.callback.register('azfw:plates:getList', function(src)
    return loadList(src)
end)

lib.callback.register('azfw:plates:removePlate', function(src, currentPlate, modelName)
    currentPlate = normalizePlate(currentPlate)
    if not currentPlate or currentPlate == normalizePlate(Config.Plates.BlankPlateText or 'NO PLATE') then
        return { ok = false, error = 'No removable plate found.' }
    end

    local list = loadList(src)
    pushPlate(list, currentPlate, { model = tostring(modelName or ''), removedFrom = currentPlate })
    saveList(src, list)
    return { ok = true, blankPlateText = tostring(Config.Plates.BlankPlateText or 'NO PLATE') }
end)

lib.callback.register('azfw:plates:installPlate', function(src, selectedId, currentPlate, modelName)
    local list = loadList(src)
    local selected, idx
    for i = 1, #list do
        if tostring(list[i].id) == tostring(selectedId) then
            selected = list[i]
            idx = i
            break
        end
    end
    if not selected then
        return { ok = false, error = 'Saved plate not found.' }
    end

    currentPlate = normalizePlate(currentPlate)
    local blank = normalizePlate(Config.Plates.BlankPlateText or 'NO PLATE')
    if Config.Plates.AllowSwap ~= false and currentPlate and currentPlate ~= blank then
        pushPlate(list, currentPlate, { model = tostring(modelName or ''), swapped = true })
    end

    table.remove(list, idx)
    saveList(src, list)
    return { ok = true, plate = tostring(selected.text), plates = list }
end)
