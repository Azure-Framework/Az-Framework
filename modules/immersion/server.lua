local CFG = (Config and Config.Immersion) or {}
if CFG.Enabled == false then return end

local RESOURCE_NAME = GetCurrentResourceName()
local Shared = AZ_IMMERSION_SHARED or {}

local PropState = {}
local RelationshipState = {}
local ComplaintState = {}
local SaveDirty = { props = false, relationships = false, complaints = false }
local Cooldowns = {
    actions = {},
    search = {},
    social = {},
    autoReports = {},
}

local function dprint(...)
    if not CFG.Debug then return end
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    print(('^3[%s S]^7 %s'):format(RESOURCE_NAME, table.concat(args, ' ')))
end

local function fileRead(path, fallback)
    local raw = LoadResourceFile(RESOURCE_NAME, path)
    if not raw or raw == '' then return fallback end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then return decoded end
    return fallback
end

local function fileWrite(path, data)
    local encoded = json.encode(data or {})
    if not encoded then return false end
    return SaveResourceFile(RESOURCE_NAME, path, encoded, -1)
end

local function markDirty(kind)
    SaveDirty[kind] = true
end

local function flushState()
    if SaveDirty.props then
        fileWrite(CFG.Persistence.PropsFile, PropState)
        SaveDirty.props = false
    end
    if SaveDirty.relationships then
        fileWrite(CFG.Persistence.RelationshipsFile, RelationshipState)
        SaveDirty.relationships = false
    end
    if SaveDirty.complaints then
        fileWrite(CFG.Persistence.ComplaintsFile, ComplaintState)
        SaveDirty.complaints = false
    end
end

local function trim(v)
    return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function nowIso()
    return os.date('!%Y-%m-%d %H:%M:%S')
end

local function getTimeHour()
    return tonumber(os.date('%H')) or 12
end

local function bool(v)
    return v == true
end

local function coordsDistance(a, b)
    local ax, ay, az = tonumber(a.x) or 0.0, tonumber(a.y) or 0.0, tonumber(a.z) or 0.0
    local bx, by, bz = tonumber(b.x) or 0.0, tonumber(b.y) or 0.0, tonumber(b.z) or 0.0
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getPedCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
end

local function normalizeJob(job)
    if type(job) == 'table' then
        return trim(job.id or job.name or job.job or job.label)
    end
    return trim(job)
end

local function getPlayerIdentity(src)
    local fw = exports['Az-Framework']
    local charId = ''
    local discordId = ''
    local job = ''

    if fw and fw.GetPlayerCharacter then
        charId = tostring(fw:GetPlayerCharacter(src) or '')
    end
    if fw and fw.getDiscordID then
        discordId = tostring(fw:getDiscordID(src) or '')
    end
    if fw and fw.getPlayerJob then
        job = normalizeJob(fw:getPlayerJob(src))
    end

    if charId == '' then charId = ('src:%s'):format(tostring(src)) end
    return {
        charId = charId,
        discordId = discordId,
        job = job:lower(),
    }
end

local function isLawJob(job)
    return (CFG.LawJobs or {})[tostring(job or ''):lower()] == true
end

local function areaClass(zone)
    local z = tostring(zone or ''):upper()
    if z == 'BEACH' or z == 'VCANA' or z == 'DELPE' or z == 'DELBE' then return 'beach' end
    if z == 'SANDY' or z == 'GRAPES' or z == 'CHIL' or z == 'MTCHIL' or z == 'PALETO' or z == 'CMSW' then return 'rural' end
    if z == 'DOWNT' or z == 'BURTON' or z == 'ROCKF' or z == 'ALTA' or z == 'TEXTI' then return 'downtown' end
    if z == 'MIRR' or z == 'RICHM' or z == 'WVINE' or z == 'MORN' then return 'suburban' end
    return 'mixed'
end

local function isNightHour(hour)
    return hour >= 21 or hour <= 5
end

local function onCooldown(bucket, key, durationMs)
    local now = GetGameTimer()
    local expires = bucket[key] or 0
    if expires > now then
        return true, math.floor((expires - now) / 1000)
    end
    bucket[key] = now + math.max(250, tonumber(durationMs) or 1000)
    return false, 0
end

local function buildPropRecord(payload)
    return {
        key = payload.key,
        family = payload.family,
        model = tonumber(payload.model) or 0,
        coords = payload.coords,
        zone = payload.zone,
        street = payload.street,
        uses = 0,
        suspicion = 0,
        dirty = 0,
        evidence = 0,
        lastAction = '',
        lastUseAt = '',
        lastActor = '',
        lastFind = '',
        hiddenItem = '',
        notes = {},
        history = {},
    }
end

local function pushHistory(record, entry)
    record.history = record.history or {}
    table.insert(record.history, 1, entry)
    while #record.history > 8 do
        table.remove(record.history)
    end
end

local function threatText(text)
    text = tostring(text or ''):lower()
    if text == '' then return false end
    local words = { 'watch', 'hurt', 'dead', 'kill', 'follow', 'mine', 'threat', 'break', 'bleed' }
    for i = 1, #words do
        if text:find(words[i], 1, true) then return true end
    end
    return false
end

local function createComplaintRecord(src, identity, payload, category, autoCreated, autoReason)
    local entry = {
        id = tostring(os.time()) .. ':' .. tostring(math.random(1000, 9999)),
        time = nowIso(),
        reporterSrc = src,
        reporterCharId = identity.charId,
        reporterDiscord = identity.discordId,
        category = category,
        auto = autoCreated == true,
        targetId = tonumber(payload.targetId or 0) or 0,
        reason = tostring(autoReason or payload.extra or payload.reason or ''),
        action = tostring(payload.action or ''),
        family = tostring(payload.family or 'npc'),
        street = tostring(payload.street or ''),
        zone = tostring(payload.zone or ''),
        coords = payload.coords or {},
        key = tostring(payload.key or payload.npcKey or ''),
    }
    table.insert(ComplaintState, 1, entry)
    while #ComplaintState > 250 do
        table.remove(ComplaintState)
    end
    markDirty('complaints')
    return entry
end

local function frameworkCreateReport(src, payload)
    local ok, err, report = false, 'admin-report-unavailable', nil
    local creator = rawget(_G, 'AzFrameworkCreateReport')
    if type(creator) == 'function' then
        local pOk, a, b, c = pcall(creator, src, payload)
        if pOk then
            ok, err, report = a, b, c
        else
            err = tostring(a)
        end
    else
        local fw = exports['Az-Framework']
        if fw and fw.createReport then
            local pOk, a, b, c = pcall(function()
                return fw:createReport(src, payload)
            end)
            if pOk then
                ok, err, report = a, b, c
            else
                err = tostring(a)
            end
        end
    end
    return ok, err, report
end

local function maybeAutoReport(src, identity, payload, reason, category, priority)
    if CFG.AutoReport.Enabled == false then return false end
    local bucketKey = ('%s:%s'):format(identity.charId, tostring(payload.key or payload.npcKey or payload.family or 'unk'))
    local blocked = onCooldown(Cooldowns.autoReports, bucketKey, (CFG.AutoReport.WindowSeconds or 600) * 1000)
    if blocked then return false end

    createComplaintRecord(src, identity, payload, category or 'Immersion', true, reason)
    local ok = frameworkCreateReport(src, {
        targetId = tonumber(payload.targetId or 0) or 0,
        reason = Shared.sanitizePayloadText and Shared.sanitizePayloadText(reason, CFG.MaxReasonLength or 240) or trim(reason),
        category = category or 'Immersion',
        priority = priority or 'normal',
    })
    return ok == true
end

local function propFindPool(family, record, payload)
    local area = areaClass(payload.zone)
    local hour = getTimeHour()
    local night = isNightHour(hour)
    local pool = {}

    if family == 'trash' then
        pool = {
            { item = 'a damp takeout receipt', weight = 14 },
            { item = 'a torn grocery bag', weight = 12 },
            { item = 'a cracked burner phone', weight = night and 10 or 4 },
            { item = 'a blood-specked rag', weight = record.suspicion >= 20 and 8 or 3 },
            { item = 'a half-finished soda', weight = 10 },
            { item = 'a set of apartment flyers', weight = area == 'suburban' and 9 or 4 },
            { item = 'a sunscreen bottle', weight = area == 'beach' and 12 or 2 },
        }
    elseif family == 'mailbox' then
        pool = {
            { item = 'a utility bill', weight = 16 },
            { item = 'a coupon pack', weight = 12 },
            { item = 'a birthday card', weight = 8 },
            { item = 'a love letter', weight = 5 },
            { item = 'a court notice', weight = night and 7 or 4 },
            { item = 'a package pickup slip', weight = 8 },
        }
    elseif family == 'cup' then
        pool = {
            { item = 'flat cola residue', weight = 14 },
            { item = 'cheap beer smell', weight = night and 12 or 4 },
            { item = 'sweet coffee residue', weight = 11 },
            { item = 'lipstick on the rim', weight = 5 },
            { item = 'fingerprint smudges', weight = 9 },
        }
    elseif family == 'bike_rack' then
        pool = {
            { item = 'fresh chain marks', weight = 13 },
            { item = 'a faded rental tag', weight = 8 },
            { item = 'a parking warning tag', weight = 7 },
            { item = 'flower petals caught in the frame', weight = 4 },
            { item = 'fresh cut marks on a lock', weight = record.suspicion >= 15 and 10 or 3 },
        }
    elseif family == 'umbrella' then
        pool = {
            { item = 'wind-blown sand packed into the fabric', weight = 13 },
            { item = 'left-behind sunscreen streaks', weight = 11 },
            { item = 'a reservation wristband tucked in the pole', weight = 6 },
            { item = 'salt spray and sand on the stand', weight = 9 },
        }
    elseif family == 'towel' then
        pool = {
            { item = 'a warm patch where someone was laying', weight = 12 },
            { item = 'flip-flop impressions in the sand', weight = 8 },
            { item = 'a dropped room key card', weight = area == 'beach' and 8 or 3 },
            { item = 'a folded beach read with sand in the spine', weight = 7 },
        }
    elseif family == 'cooler' then
        pool = {
            { item = 'melted ice and canned drinks', weight = 14 },
            { item = 'a bag of cut fruit', weight = 10 },
            { item = 'sports drinks for a beach game', weight = 8 },
            { item = 'empty bottles and water condensation', weight = 9 },
        }
    elseif family == 'beach_bag' then
        pool = {
            { item = 'sunblock and sunglasses', weight = 13 },
            { item = 'a folded beach novel', weight = 9 },
            { item = 'hotel key cards and damp receipts', weight = 8 },
            { item = 'sand caught inside the zipper lining', weight = 10 },
        }
    elseif family == 'beach_chair' or family == 'lounger' or family == 'pool_lounger' then
        pool = {
            { item = 'warm fabric where someone just got up', weight = 12 },
            { item = 'sunscreen smears on the armrest', weight = 9 },
            { item = 'sunglasses left in the shade', weight = 6 },
            { item = 'wet footprints around the legs', weight = 8 },
        }
    elseif family == 'surfboard' then
        pool = {
            { item = 'fresh wax comb scratches', weight = 13 },
            { item = 'saltwater beading off the rail', weight = 12 },
            { item = 'a local rental tag zip-tied near the leash', weight = 9 },
            { item = 'sand caked onto the fins', weight = 7 },
        }
    elseif family == 'floatie' then
        pool = {
            { item = 'chlorine smell and wet plastic', weight = 13 },
            { item = 'a patched valve seam', weight = 8 },
            { item = 'a rental wristband tied around it', weight = 7 },
            { item = 'sun-warmed vinyl and water droplets', weight = 9 },
        }
    elseif family == 'lifeguard_post' then
        pool = {
            { item = 'a whistle lanyard and rescue notes', weight = 10 },
            { item = 'binocular scuffs on the rail', weight = 8 },
            { item = 'sun-faded warning cards', weight = 7 },
            { item = 'a red towel drying nearby', weight = 7 },
        }
    elseif family == 'shower' then
        pool = {
            { item = 'salt and sand washing into the drain', weight = 11 },
            { item = 'soap scent in the humid air', weight = 8 },
            { item = 'wet footprints leading away', weight = 10 },
            { item = 'a dropped flip-flop mark nearby', weight = 5 },
        }
    elseif family == 'changing_booth' then
        pool = {
            { item = 'damp clothes smell and sunscreen', weight = 10 },
            { item = 'a locker token under the panel', weight = 7 },
            { item = 'sand pooled in the corner', weight = 8 },
            { item = 'recently changed footprints', weight = 9 },
        }
    elseif family == 'volleyball' then
        pool = {
            { item = 'fresh palm prints in the sand', weight = 11 },
            { item = 'a score line carved nearby', weight = 8 },
            { item = 'air valve wear from repeated games', weight = 6 },
            { item = 'water bottles lined beside the court', weight = 8 },
        }
    elseif family == 'frisbee' then
        pool = {
            { item = 'a scuffed edge from repeated throws', weight = 10 },
            { item = 'sand stuck in the rim', weight = 8 },
            { item = 'a sharpie name from a beach group', weight = 6 },
            { item = 'grass streaks from a bad catch', weight = 7 },
        }
    elseif family == 'soccer_ball' or family == 'football' or family == 'yard_game' then
        pool = {
            { item = 'chalk sideline marks and cone scuffs', weight = 10 },
            { item = 'fresh grass or sand wear', weight = 10 },
            { item = 'a half-finished sports drink nearby', weight = 7 },
            { item = 'worn stitching from a long day outside', weight = 7 },
        }
    elseif family == 'speaker' then
        pool = {
            { item = 'bass vibration through the casing', weight = 10 },
            { item = 'an aux cable tucked under it', weight = 7 },
            { item = 'drink rings from people hanging around it', weight = 8 },
            { item = 'a playlist name scribbled on a sticky note', weight = 5 },
        }
    elseif family == 'bbq' then
        pool = {
            { item = 'charred hot dog ends on the grate', weight = 12 },
            { item = 'propane smell and grease splatter', weight = 10 },
            { item = 'burger wrappers stuffed underneath', weight = 8 },
            { item = 'fresh ash and still-warm coals', weight = night and 9 or 6 },
        }
    elseif family == 'gazebo' then
        pool = {
            { item = 'folding chairs and picnic clutter', weight = 12 },
            { item = 'streamers from a daytime event', weight = 7 },
            { item = 'a forgotten paper plate stack', weight = 9 },
            { item = 'cool shade and a clean setup', weight = 10 },
        }
    elseif family == 'picnic_table' or family == 'patio_table' then
        pool = {
            { item = 'paper plates, crumbs, and napkins', weight = 12 },
            { item = 'a card deck or dominoes left out', weight = 8 },
            { item = 'cold drink rings and sunscreen stains', weight = 9 },
            { item = 'a family cookout setup still half-ready', weight = 7 },
        }
    elseif family == 'blanket' then
        pool = {
            { item = 'fruit containers and napkins', weight = 11 },
            { item = 'a rolled magazine and sunscreen', weight = 8 },
            { item = 'grass and sand caught in the corners', weight = 8 },
            { item = 'fresh impressions from people lounging', weight = 9 },
        }
    elseif family == 'folding_chair' or family == 'camp_chair' or family == 'bench' or family == 'dock_spot' or family == 'playground' then
        pool = {
            { item = 'a drink spot and worn seating marks', weight = 10 },
            { item = 'fresh footprints and sunscreen scent', weight = 8 },
            { item = 'carved initials or doodles nearby', weight = 6 },
            { item = 'the feel of a spot people keep returning to', weight = 7 },
        }
    elseif family == 'tent' then
        pool = {
            { item = 'bug spray and a sleeping bag', weight = 12 },
            { item = 'a camp map with lake notes', weight = 9 },
            { item = 'packed chairs and spare blankets', weight = 8 },
            { item = "smoke smell from last night's fire", weight = night and 10 or 4 },
        }
    elseif family == 'lantern' then
        pool = {
            { item = 'warm metal and battery residue', weight = 9 },
            { item = 'bug spray and camp dust', weight = 8 },
            { item = 'a soot mark where it was hung before', weight = 7 },
            { item = 'finger smudges from someone checking the light', weight = 6 },
        }
    elseif family == 'logpile' then
        pool = {
            { item = 'split cedar and dry kindling', weight = 11 },
            { item = 'driftwood mixed into the pile', weight = 8 },
            { item = 'fresh bark peeled by hand', weight = 7 },
            { item = 'ash dust tracked back from the firepit', weight = 6 },
        }
    elseif family == 'hammock' then
        pool = {
            { item = 'deep fabric sag from recent use', weight = 10 },
            { item = 'a paperback tucked near the anchor', weight = 7 },
            { item = 'sunscreen on the rope knot', weight = 6 },
            { item = 'a slow sway still left in the frame', weight = 8 },
        }
    elseif family == 'firepit' then
        pool = {
            { item = 'charred marshmallow sticks', weight = 12 },
            { item = 'a ring of bottle caps in the ash', weight = 9 },
            { item = 'glowing coals under the sand', weight = night and 10 or 3 },
            { item = 'half-burnt driftwood', weight = 8 },
        }
    elseif family == 'boardwalk_booth' then
        pool = {
            { item = 'ticket stubs and syrup stains', weight = 12 },
            { item = 'a stack of cheap plush prizes', weight = 7 },
            { item = 'photo strip scraps under the counter', weight = 8 },
            { item = 'a vendor rag and melted ice', weight = 8 },
        }
    elseif family == 'snack_vending' or family == 'icecream_cart' or family == 'food_cart' then
        pool = {
            { item = 'wrapper scraps and spilled syrup', weight = 11 },
            { item = 'a little line of footprints waiting nearby', weight = 8 },
            { item = 'cold condensation and sticky handles', weight = 8 },
            { item = 'signs of a busy summer rush', weight = 7 },
        }
    elseif family == 'arcade_kiosk' then
        pool = {
            { item = 'ticket scraps and button wear', weight = 10 },
            { item = 'coin scuffs around the panel', weight = 8 },
            { item = 'a quick photo strip tucked underneath', weight = 6 },
            { item = 'neon grime from constant use', weight = 7 },
        }
    elseif family == 'photo_spot' then
        pool = {
            { item = 'fresh footprints where groups keep lining up', weight = 10 },
            { item = 'confetti scraps from a little celebration', weight = 6 },
            { item = 'sun-faded signage and camera chatter', weight = 8 },
            { item = 'drink cups and poses repeating all day', weight = 7 },
        }
    elseif family == 'sprinkler' or family == 'kiddie_pool' then
        pool = {
            { item = 'wet grass and splash marks', weight = 11 },
            { item = 'a popsicle stick or toy left nearby', weight = 7 },
            { item = 'water droplets catching the sun', weight = 9 },
            { item = 'a backyard setup that has seen a lot of use', weight = 7 },
        }
    end

    return pool
end

local function summerDefaults(record)
    record.coolerStock = tonumber(record.coolerStock) or (CFG.Summer and CFG.Summer.CoolerStockDefault) or 4
    record.rentalStock = tonumber(record.rentalStock) or (CFG.Summer and CFG.Summer.RentalStockDefault) or 3
    record.grillFuel = tonumber(record.grillFuel) or (CFG.Summer and CFG.Summer.GrillFuelDefault) or 3
    record.bonfireFuel = tonumber(record.bonfireFuel) or (CFG.Summer and CFG.Summer.BonfireFuelDefault) or 2
    record.floatStock = tonumber(record.floatStock) or (CFG.Summer and CFG.Summer.FloatStockDefault) or 3
    record.snackStock = tonumber(record.snackStock) or (CFG.Summer and CFG.Summer.SnackStockDefault) or 5
    record.foodStock = tonumber(record.foodStock) or (CFG.Summer and CFG.Summer.FoodStockDefault) or 5
    record.bonfireLit = record.bonfireLit == true
    record.musicOn = record.musicOn == true
    record.lanternLit = record.lanternLit == true
end

local function zoneNearBeach(zone)
    local z = tostring(zone or ''):upper()
    return z == 'BEACH' or z == 'VCANA' or z == 'DELPE' or z == 'DELBE'
end

local function resolvePropAction(src, identity, record, payload)
    local family = payload.family
    local action = payload.action
    local area = areaClass(payload.zone)
    local seed = Shared.seedFromString and Shared.seedFromString((payload.key or '') .. ':' .. os.date('%Y%m%d%H') .. ':' .. action) or math.random(1000, 9000)
    local rng = Shared.newRng and Shared.newRng(seed) or function(max) return math.random(max or 100) end
    local result = {
        type = 'inform',
        message = 'Nothing much happens.',
        reportCreated = false,
    }

    record.uses = (record.uses or 0) + 1
    record.lastAction = action
    record.lastUseAt = nowIso()
    record.lastActor = identity.charId
    record.street = payload.street
    record.zone = payload.zone
    summerDefaults(record)

    if action == 'inspect' then
        local pool = propFindPool(family, record, payload)
        local found = Shared.weightedPick and Shared.weightedPick(pool, rng) or pool[1]
        if found and found.item then
            result.message = ('You inspect the %s and notice %s.'):format(family:gsub('_', ' '), found.item)
        else
            result.message = ('You inspect the %s but nothing stands out.'):format(family:gsub('_', ' '))
        end
    elseif action == 'check_mail' then
        local found = Shared.weightedPick(propFindPool(family, record, payload), rng)
        record.lastFind = found and found.item or ''
        result.type = 'success'
        result.message = found and ('You sort through the mailbox and find %s.'):format(found.item) or 'The mailbox is mostly empty.'
    elseif action == 'leave_note' then
        local note = Shared.sanitizePayloadText and Shared.sanitizePayloadText(payload.extra, CFG.MaxNoteLength or 180) or trim(payload.extra)
        record.notes = record.notes or {}
        table.insert(record.notes, 1, {
            text = note,
            by = identity.charId,
            time = nowIso(),
        })
        while #record.notes > 6 do table.remove(record.notes) end
        result.type = 'success'
        result.message = 'You leave a note and tuck it into place.'
        if threatText(note) then
            record.suspicion = (record.suspicion or 0) + 20
            result.reportCreated = maybeAutoReport(src, identity, payload, 'Threatening note left through immersion mailbox interaction.', 'Immersion', 'high')
        else
            record.suspicion = math.max(0, (record.suspicion or 0) + 3)
        end
    elseif action == 'hide_item' then
        local item = Shared.sanitizePayloadText and Shared.sanitizePayloadText(payload.extra, 48) or trim(payload.extra)
        record.hiddenItem = item
        record.suspicion = (record.suspicion or 0) + 6
        result.message = ('You hide %s inside the %s.'):format(item ~= '' and item or 'a small item', family:gsub('_', ' '))
    elseif action == 'pry_open' then
        if payload.skillPassed then
            local found = Shared.weightedPick(propFindPool(family, record, payload), rng)
            record.lastFind = found and found.item or ''
            record.suspicion = (record.suspicion or 0) + 16
            record.evidence = (record.evidence or 0) + 2
            result.type = 'success'
            result.message = found and ('You pry it open and uncover %s.'):format(found.item) or 'You force it open, but it is mostly empty.'
        else
            record.suspicion = (record.suspicion or 0) + 24
            record.evidence = (record.evidence or 0) + 3
            result.type = 'error'
            result.message = 'You fumble the force attempt and make a lot of noise.'
        end
    elseif action == 'search' then
        local found = Shared.weightedPick(propFindPool(family, record, payload), rng)
        record.lastFind = found and found.item or ''
        record.dirty = Shared.clamp and Shared.clamp((record.dirty or 0) + 8, 0, 100) or math.min(100, (record.dirty or 0) + 8)
        record.suspicion = math.max(0, (record.suspicion or 0) + (payload.skillPassed and 4 or 10))
        result.type = found and 'success' or 'inform'
        result.message = found and ('You dig around and come up with %s.'):format(found.item) or 'You search around but come up empty.'
    elseif action == 'clean_up' then
        record.dirty = math.max(0, (record.dirty or 0) - 24)
        record.suspicion = math.max(0, (record.suspicion or 0) - 6)
        result.type = 'success'
        result.message = ('You tidy up the %s and make the area look better.'):format(family:gsub('_', ' '))
    elseif action == 'bag_evidence' then
        if not isLawJob(identity.job) then
            result.type = 'error'
            result.message = 'You are not equipped to process evidence properly.'
        else
            local value = math.max(1, record.evidence or 0)
            record.evidence = math.max(0, value - 1)
            result.type = 'success'
            result.message = value > 0 and 'You bag and tag a piece of useful evidence.' or 'You bag trace residue for follow-up.'
        end
    elseif action == 'drink' then
        record.dirty = math.max(0, (record.dirty or 0) - 2)
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You take a quick drink and toss the container back down.' or 'You take a sip, but it tastes stale.'
    elseif action == 'dispose' then
        record.dirty = math.max(0, (record.dirty or 0) - 8)
        record.hiddenItem = ''
        result.type = 'success'
        result.message = 'You dispose of it and leave the area a little cleaner.'
    elseif action == 'cut_chain' then
        record.suspicion = (record.suspicion or 0) + (payload.skillPassed and 22 or 28)
        record.evidence = (record.evidence or 0) + 2
        result.type = payload.skillPassed and 'success' or 'error'
        result.message = payload.skillPassed and 'You cut the chain free. Anybody nearby would notice the marks.' or 'The cut attempt goes badly and throws sparks.'
    elseif action == 'lock_bike' then
        record.suspicion = math.max(0, (record.suspicion or 0) - 4)
        result.type = 'success'
        result.message = 'You secure the bike rack spot and leave it looking occupied.'
    elseif action == 'leave_gift' then
        local gift = Shared.sanitizePayloadText and Shared.sanitizePayloadText(payload.extra, 48) or trim(payload.extra)
        record.notes = record.notes or {}
        table.insert(record.notes, 1, {
            text = ('Gift left: %s'):format(gift ~= '' and gift or 'flowers'),
            by = identity.charId,
            time = nowIso(),
        })
        while #record.notes > 6 do table.remove(record.notes) end
        result.type = 'success'
        result.message = ('You leave %s tucked into the bike rack.'):format(gift ~= '' and gift or 'a small gift')
    elseif action == 'cool_off' then
        record.dirty = math.max(0, (record.dirty or 0) - 2)
        result.type = 'success'
        result.message = 'You cool off in the shade for a moment and reset a little.'
    elseif action == 'reserve_spot' then
        record.lastActor = identity.charId
        result.type = 'success'
        result.message = 'You make the setup look occupied and hold the spot down.'
    elseif action == 'relax' then
        result.type = 'success'
        result.message = 'You settle in and enjoy the slower summer pace.'
    elseif action == 'tan' then
        if zoneNearBeach(payload.zone) and not isNightHour(getTimeHour()) then
            result.type = 'success'
            result.message = 'You catch some sun and let the beach vibe carry the moment.'
        else
            result.type = 'inform'
            result.message = 'It is not really the right moment for a proper sun session.'
        end
    elseif action == 'pack_up' then
        record.dirty = math.max(0, (record.dirty or 0) - 10)
        result.type = 'success'
        result.message = 'You pack the setup down and leave the area cleaner than before.'
    elseif action == 'grab_drink' then
        if (record.coolerStock or 0) <= 0 then
            result.type = 'error'
            result.message = 'The cooler is picked clean and the ice has mostly melted.'
        else
            record.coolerStock = math.max(0, (record.coolerStock or 0) - 1)
            result.type = 'success'
            result.message = ('You grab a cold drink. %s left in the cooler.'):format(record.coolerStock)
        end
    elseif action == 'stock_cooler' then
        record.coolerStock = math.min(12, (record.coolerStock or 0) + 3)
        result.type = 'success'
        result.message = ('You restock the cooler and bring it up to %s drinks.'):format(record.coolerStock)
    elseif action == 'wax_board' then
        record.suspicion = math.max(0, (record.suspicion or 0) - 1)
        result.type = 'success'
        result.message = 'You prep the board and it feels ready for the water.'
    elseif action == 'rent_board' then
        if (record.rentalStock or 0) <= 0 then
            result.type = 'error'
            result.message = 'The rental rack is sold out for now.'
        else
            record.rentalStock = math.max(0, (record.rentalStock or 0) - 1)
            result.type = 'success'
            result.message = ('You rent out a board. %s rental boards remain.'):format(record.rentalStock)
        end
    elseif action == 'start_surf' then
        if not zoneNearBeach(payload.zone) then
            result.type = 'inform'
            result.message = 'This does not really feel like a proper surf launch spot.'
        elseif payload.skillPassed then
            result.type = 'success'
            result.message = 'You paddle out and catch a clean run on the water.'
        else
            result.type = 'error'
            result.message = 'You wipe out early and end up eating water instead of style.'
        end
    elseif action == 'toss_ball' then
        result.type = 'success'
        result.message = 'You knock the ball around and draw a little attention to the area.'
    elseif action == 'play_volleyball' then
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You get a good rally going and win a few cheers from nearby people.' or 'The match starts messy, but it still gets the beach active.'
    elseif action == 'organize_match' then
        result.type = 'success'
        result.message = 'You get the court organized and make the setup feel active.'
    elseif action == 'grill_food' then
        if (record.grillFuel or 0) <= 0 then
            result.type = 'error'
            result.message = 'The grill is out of fuel and will not stay hot.'
        else
            record.grillFuel = math.max(0, (record.grillFuel or 0) - 1)
            result.type = payload.skillPassed and 'success' or 'inform'
            result.message = payload.skillPassed and 'You put out a solid summer cook and the grill smells amazing.' or 'The food cooks, but you nearly overdo it on the heat.'
        end
    elseif action == 'refuel_grill' then
        record.grillFuel = math.min(8, (record.grillFuel or 0) + 2)
        result.type = 'success'
        result.message = ('You top the grill off. Fuel level now %s.'):format(record.grillFuel)
    elseif action == 'set_picnic' then
        record.dirty = math.max(0, (record.dirty or 0) - 4)
        result.type = 'success'
        result.message = 'You set out a picnic and the spot starts to feel lived in.'
    elseif action == 'hang_out' then
        result.type = 'success'
        result.message = 'You linger under the cover and the atmosphere stays easygoing.'
    elseif action == 'set_camp' then
        result.type = 'success'
        result.message = 'You tighten up the camp and make the site feel ready for the evening.'
    elseif action == 'rest_camp' then
        result.type = 'success'
        result.message = 'You take a breather at camp and settle into the slower pace out here.'
    elseif action == 'break_camp' then
        record.dirty = math.max(0, (record.dirty or 0) - 10)
        result.type = 'success'
        result.message = 'You pack down the camp and leave less trace behind.'
    elseif action == 'start_bonfire' then
        if (record.bonfireFuel or 0) <= 0 then
            result.type = 'error'
            result.message = 'There is not enough wood or fuel left to get the fire going.'
        else
            record.bonfireFuel = math.max(0, (record.bonfireFuel or 0) - 1)
            if payload.skillPassed then
                record.bonfireLit = true
                result.type = 'success'
                result.message = 'The bonfire catches and the whole area feels more alive.'
            else
                result.type = 'error'
                result.message = 'The fire sputters out before it really catches.'
            end
        end
    elseif action == 'roast_food' then
        if record.bonfireLit ~= true then
            result.type = 'error'
            result.message = 'You need a real flame going before you can roast anything.'
        else
            result.type = 'success'
            result.message = 'You roast food over the fire and the scene gets that perfect summer-night smell.'
        end
    elseif action == 'put_out_fire' then
        record.bonfireLit = false
        result.type = 'success'
        result.message = 'You put the fire out and leave the pit safer for whoever comes next.'
    elseif action == 'buy_treat' then
        result.type = 'success'
        result.message = 'You grab a quick summer treat from the stand.'
    elseif action == 'play_ring_toss' then
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You land a clean toss and win a cheap little prize.' or 'Close, but the toss just misses the bottle neck.'
    elseif action == 'take_photo' then
        result.type = 'success'
        result.message = 'You snap a boardwalk photo and keep the memory.'
    elseif action == 'unpack_bag' then
        record.lastActor = identity.charId
        record.dirty = math.max(0, (record.dirty or 0) - 2)
        result.type = 'success'
        result.message = 'You unpack the bag and make the setup feel active.'
    elseif action == 'stash_supplies' then
        record.hiddenItem = 'summer supplies'
        result.type = 'success'
        result.message = 'You stash a few extra supplies and keep the bag ready.'
    elseif action == 'sit_down' then
        result.type = 'success'
        result.message = 'You take a seat and settle into the slower pace.'
    elseif action == 'lounge_out' then
        result.type = 'success'
        result.message = 'You stretch out and enjoy the heat for a bit.'
    elseif action == 'play_music' then
        record.musicOn = true
        result.type = 'success'
        result.message = 'Music starts up and the whole area feels more alive.'
    elseif action == 'dance' then
        result.type = record.musicOn and 'success' or 'inform'
        result.message = record.musicOn and 'You catch the beat and keep the summer energy up.' or 'You vibe a little, but the scene needs music to really land.'
    elseif action == 'rent_float' then
        if (record.floatStock or 0) <= 0 then
            result.type = 'error'
            result.message = 'There are no floats left right now.'
        else
            record.floatStock = math.max(0, (record.floatStock or 0) - 1)
            result.type = 'success'
            result.message = ('You grab a float. %s left in stock.'):format(record.floatStock)
        end
    elseif action == 'drift_float' then
        result.type = (zoneNearBeach(payload.zone) or family == 'kiddie_pool' or family == 'floatie') and 'success' or 'inform'
        result.message = (zoneNearBeach(payload.zone) or family == 'kiddie_pool' or family == 'floatie') and 'You drift for a while and keep things easy.' or 'It is not really a float spot, but you still cool off a little.'
    elseif action == 'rinse_off' then
        record.dirty = math.max(0, (record.dirty or 0) - 8)
        result.type = 'success'
        result.message = 'You rinse the salt, chlorine, and sand off.'
    elseif action == 'change_outfit' then
        result.type = 'success'
        result.message = 'You duck in, change quickly, and come back out ready to keep going.'
    elseif action == 'watch_water' then
        result.type = 'success'
        result.message = 'You keep an eye on the water and the crowd for a moment.'
    elseif action == 'toss_frisbee' then
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You get a clean frisbee toss going and pull people into it.' or 'The throw is messy, but it still gets the area moving.'
    elseif action == 'kick_ball' then
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You knock the ball around and get a real little game going.' or 'You bobble the touch, but the game still starts to form.'
    elseif action == 'throw_football' then
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You throw a clean pass and make the field feel active.' or 'The pass goes wide, but people still get into the moment.'
    elseif action == 'play_yard_game' then
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You win a few rounds and the backyard energy comes alive.' or 'The game gets messy, but everybody still has something to do.'
    elseif action == 'eat_snack' then
        if family == 'snack_vending' or family == 'icecream_cart' or family == 'boardwalk_booth' then
            if (record.snackStock or 0) <= 0 then
                result.type = 'error'
                result.message = 'The snack side is sold out for now.'
            else
                record.snackStock = math.max(0, (record.snackStock or 0) - 1)
                result.type = 'success'
                result.message = 'You grab a quick snack and keep moving.'
            end
        else
            result.type = 'success'
            result.message = 'You have a quick bite and settle back into the hangout.'
        end
    elseif action == 'buy_icecream' then
        if (record.snackStock or 0) <= 0 then
            result.type = 'error'
            result.message = 'The freezer side is basically cleaned out.'
        else
            record.snackStock = math.max(0, (record.snackStock or 0) - 1)
            result.type = 'success'
            result.message = 'You grab something cold before it melts all over your hand.'
        end
    elseif action == 'buy_food' then
        if (record.foodStock or 0) <= 0 then
            result.type = 'error'
            result.message = 'The cart is sold through its hot food for now.'
        else
            record.foodStock = math.max(0, (record.foodStock or 0) - 1)
            result.type = 'success'
            result.message = 'You pick up something hot and the whole stand smells better for it.'
        end
    elseif action == 'play_arcade' then
        result.type = payload.skillPassed and 'success' or 'inform'
        result.message = payload.skillPassed and 'You win a few tickets and make the booth feel busy again.' or 'You play a round, miss the big win, and still add life to the spot.'
    elseif action == 'set_table' then
        record.dirty = math.max(0, (record.dirty or 0) - 2)
        result.type = 'success'
        result.message = 'You set the table up and make it feel ready for food, cards, or drinks.'
    elseif action == 'sway_hammock' then
        result.type = 'success'
        result.message = 'You sink into the hammock and let the afternoon slow down.'
    elseif action == 'light_lantern' then
        record.lanternLit = true
        result.type = 'success'
        result.message = 'You light the lantern and give the camp a warmer feel.'
    elseif action == 'gather_wood' then
        record.bonfireFuel = math.min(10, (record.bonfireFuel or 0) + 2)
        result.type = 'success'
        result.message = ('You gather more wood and bring the fire stock up to %s.'):format(record.bonfireFuel)
    elseif action == 'splash_around' then
        record.dirty = math.max(0, (record.dirty or 0) - 4)
        result.type = 'success'
        result.message = 'You splash around and cool the whole scene down a little.'
    elseif action == 'enjoy_playground' then
        result.type = 'success'
        result.message = 'You hang around the playground and keep the park feeling busy.'
    elseif action == 'report' then
        local reason = Shared.sanitizePayloadText and Shared.sanitizePayloadText(payload.extra, CFG.MaxReasonLength or 240) or trim(payload.extra)
        createComplaintRecord(src, identity, payload, 'Immersion', false)
        local ok = frameworkCreateReport(src, {
            targetId = 0,
            reason = reason,
            category = 'Immersion',
            priority = 'normal',
        })
        result.type = ok and 'success' or 'inform'
        result.reportCreated = ok == true
        result.message = ok and 'Your report was filed into the admin system.' or 'The report was logged locally, but the admin report bridge was unavailable.'
    end

    pushHistory(record, {
        time = nowIso(),
        action = action,
        by = identity.charId,
        street = payload.street,
    })

    if action ~= 'report' and CFG.AutoReport.Enabled ~= false and (record.suspicion or 0) >= (CFG.AutoReport.SuspicionThreshold or 36) then
        local reason = ('Repeated suspicious %s interaction near %s (%s).'):format(family:gsub('_', ' '), tostring(payload.street or 'unknown street'), tostring(area))
        result.reportCreated = maybeAutoReport(src, identity, payload, reason, 'Immersion', 'low') or result.reportCreated
    end

    return result
end

local function relationshipKey(charId, npcKey)
    return ('%s:%s'):format(charId, npcKey)
end

local function buildNpcProfile(npcKey, model)
    local seed = Shared.seedFromString and Shared.seedFromString(('%s:%s'):format(npcKey, tostring(model))) or math.random(1000, 9000)
    local rng = Shared.newRng and Shared.newRng(seed) or function(max) return math.random(max or 100) end
    local dateIdeas = { 'coffee', 'beach', 'diner', 'drive' }
    local preferred = dateIdeas[rng(#dateIdeas)]
    return {
        seed = seed,
        preferredDate = preferred,
        patience = 20 + rng(61),
        adventurous = rng(100),
        neatness = rng(100),
        romantic = rng(100),
        guarded = rng(100),
    }
end

local function getRelationshipRecord(identity, payload)
    local key = relationshipKey(identity.charId, payload.npcKey)
    local record = RelationshipState[key]
    if not record then
        record = {
            key = key,
            charId = identity.charId,
            npcKey = payload.npcKey,
            npcModel = tonumber(payload.model) or 0,
            street = payload.street,
            zone = payload.zone,
            attraction = 0,
            trust = 0,
            comfort = 0,
            excitement = 0,
            resentment = 0,
            jealousy = 0,
            pushiness = 0,
            rejections = 0,
            acceptedDates = 0,
            status = 'stranger',
            lastContact = 0,
            lastAction = '',
            profile = buildNpcProfile(payload.npcKey, payload.model),
            history = {},
        }
        RelationshipState[key] = record
    end
    return record
end

local function decayRelationship(record)
    local now = os.time()
    local last = tonumber(record.lastContact or 0) or 0
    if last <= 0 then return end
    local hours = math.floor((now - last) / 3600)
    if hours < 48 then return end
    local steps = math.floor(hours / 48)
    if steps <= 0 then return end
    record.comfort = math.max(-100, (record.comfort or 0) - steps)
    if record.status == 'dating' then
        record.trust = math.max(-100, (record.trust or 0) - (steps * 2))
        record.excitement = math.max(-100, (record.excitement or 0) - steps)
    end
    record.lastContact = now
end

local function pushRelationshipHistory(record, entry)
    record.history = record.history or {}
    table.insert(record.history, 1, entry)
    while #record.history > 10 do
        table.remove(record.history)
    end
end

local function updateStatus(record)
    if (record.attraction or 0) >= 45 and (record.trust or 0) >= 25 then
        record.status = 'dating'
    elseif (record.attraction or 0) >= 18 or (record.comfort or 0) >= 20 then
        record.status = 'interested'
    else
        record.status = 'stranger'
    end
end

local function resolveSocialAction(src, identity, record, payload)
    local action = payload.action
    local profile = record.profile or buildNpcProfile(payload.npcKey, payload.model)
    record.profile = profile
    decayRelationship(record)

    local result = {
        type = 'inform',
        message = 'They react, but it is hard to read.',
        reportCreated = false,
    }

    local function add(field, amount)
        record[field] = Shared.clamp and Shared.clamp((record[field] or 0) + amount, -100, 100) or ((record[field] or 0) + amount)
    end

    if action == 'talk' then
        add('comfort', 4)
        add('trust', 2)
        result.type = 'success'
        result.message = 'The conversation lands fine and the vibe is a little warmer.'
    elseif action == 'compliment' then
        local boost = profile.romantic >= 45 and 7 or 3
        add('attraction', boost)
        add('comfort', 3)
        result.type = 'success'
        result.message = boost >= 6 and 'They actually seem flattered by that.' or 'The compliment lands okay, but they stay guarded.'
    elseif action == 'flirt' then
        local score = 35 + math.floor((record.attraction or 0) / 2) + math.floor((record.comfort or 0) / 3) + (payload.skillPassed and 6 or -4) - math.floor((record.resentment or 0) / 2) - math.floor(profile.guarded / 6)
        if score >= 45 then
            add('attraction', 8)
            add('comfort', 4)
            add('trust', 2)
            record.pushiness = math.max(0, (record.pushiness or 0) - 1)
            result.type = 'success'
            result.message = 'They smile back and linger in the moment.'
        else
            add('resentment', 4)
            record.rejections = (record.rejections or 0) + 1
            record.pushiness = (record.pushiness or 0) + 12
            result.type = 'error'
            result.message = 'They pull back and clearly are not into it right now.'
        end
    elseif action == 'ask_out' then
        local dateType = tostring(payload.extra or 'coffee')
        local score = 28 + (record.attraction or 0) + math.floor((record.trust or 0) / 2) + (payload.skillPassed and 8 or -5)
        if dateType == profile.preferredDate then score = score + 14 end
        if (record.resentment or 0) > 25 then score = score - 18 end
        if score >= 52 then
            add('trust', 6)
            add('attraction', 5)
            add('excitement', dateType == profile.preferredDate and 12 or 6)
            record.acceptedDates = (record.acceptedDates or 0) + 1
            record.pushiness = math.max(0, (record.pushiness or 0) - 8)
            result.type = 'success'
            result.message = ('They agree to a %s date and seem genuinely interested.'):format(dateType)
        else
            add('resentment', 6)
            record.rejections = (record.rejections or 0) + 1
            record.pushiness = (record.pushiness or 0) + 16
            result.type = 'error'
            result.message = ('They pass on the %s date and keep some distance.'):format(dateType)
        end
    elseif action == 'ask_area' then
        add('trust', 3)
        local area = areaClass(payload.zone)
        local hints = {
            beach = 'They mention people leave bottles and coolers near the beach after dark.',
            suburban = 'They mention porch packages go missing on this block when it gets quiet.',
            rural = 'They mention dumped bags and bait wrappers show up around back roads.',
            downtown = 'They mention alley dumpsters get picked over late at night.',
            mixed = 'They mention the area changes a lot depending on who is around.',
        }
        result.type = 'success'
        result.message = hints[area] or hints.mixed
    elseif action == 'report' then
        local reason = Shared.sanitizePayloadText and Shared.sanitizePayloadText(payload.extra, CFG.MaxReasonLength or 240) or trim(payload.extra)
        createComplaintRecord(src, identity, payload, 'NPC Social', false)
        local ok = frameworkCreateReport(src, {
            targetId = 0,
            reason = reason,
            category = 'NPC Social',
            priority = 'normal',
        })
        result.type = ok and 'success' or 'inform'
        result.reportCreated = ok == true
        result.message = ok and 'Your NPC interaction report was filed.' or 'The report was logged locally, but the admin bridge was unavailable.'
    end

    record.lastAction = action
    record.lastContact = os.time()
    record.street = payload.street
    record.zone = payload.zone
    summerDefaults(record)
    updateStatus(record)
    pushRelationshipHistory(record, {
        time = nowIso(),
        action = action,
        result = result.message,
    })

    if action ~= 'report' and CFG.AutoReport.Enabled ~= false and (record.pushiness or 0) >= (CFG.AutoReport.HarassmentThreshold or 55) then
        local reason = 'Repeated unwanted social interaction or harassment-style persistence detected in the immersion relationship system.'
        result.reportCreated = maybeAutoReport(src, identity, payload, reason, 'NPC Social', 'normal') or result.reportCreated
        record.pushiness = math.max(0, (record.pushiness or 0) - 20)
    end

    return result
end

local function syncEntityState(netId, family, key, suspicion)
    if not netId or netId <= 0 then return end
    if not NetworkDoesNetworkIdExist(netId) then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end
    Entity(entity).state:set('az:imm:type', family, true)
    Entity(entity).state:set('az:imm:key', key, true)
    Entity(entity).state:set('az:imm:suspicion', tonumber(suspicion) or 0, true)
end

RegisterNetEvent('azfw:immersion:server:performPropAction', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    if CFG.EnablePropInteractions == false then return end

    payload.family = trim(payload.family)
    payload.action = trim(payload.action)
    if payload.family == '' or payload.action == '' then return end
    if not Shared.familyHasModel or not Shared.familyHasModel(payload.family, tonumber(payload.model) or 0) then
        dprint('Rejected prop action due to model/family mismatch', payload.family, payload.model)
        return
    end

    local playerCoords = getPedCoords(src)
    local objectCoords = payload.coords or {}
    if not playerCoords or coordsDistance(playerCoords, objectCoords) > (CFG.ActionDistance or 3.5) then
        dprint('Rejected prop action due to distance', src)
        return
    end

    local cooldownKey = ('%s:%s:%s'):format(tostring(src), payload.family, payload.action)
    local blocked, secs = onCooldown(Cooldowns.actions, cooldownKey, CFG.ActionCooldownMs or 3500)
    if blocked then
        TriggerClientEvent('azfw:immersion:client:actionResult', src, {
            type = 'error',
            message = ('Slow down a bit (%ss cooldown).'):format(secs),
        })
        return
    end

    if payload.action == 'search' or payload.action == 'check_mail' then
        local searchKey = tostring(payload.key or '')
        local blockedSearch, left = onCooldown(Cooldowns.search, searchKey, (CFG.SearchCooldownSeconds or 75) * 1000)
        if blockedSearch then
            TriggerClientEvent('azfw:immersion:client:actionResult', src, {
                type = 'error',
                message = ('This has been picked over recently (%ss).'):format(left),
            })
            return
        end
    end

    local identity = getPlayerIdentity(src)
    local key = tostring(payload.key or Shared.makeObjectKey(payload.family, payload.model, payload.coords))
    payload.key = key

    local record = PropState[key] or buildPropRecord(payload)
    local result = resolvePropAction(src, identity, record, payload)
    PropState[key] = record
    markDirty('props')

    syncEntityState(tonumber(payload.netId) or 0, payload.family, key, record.suspicion)

    TriggerClientEvent('azfw:immersion:client:actionResult', src, result)
end)

RegisterNetEvent('azfw:immersion:server:performSocialAction', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    if CFG.EnableNPCSocial == false then return end

    payload.action = trim(payload.action)
    payload.npcKey = trim(payload.npcKey)
    if payload.action == '' or payload.npcKey == '' then return end

    local playerCoords = getPedCoords(src)
    local npcCoords = payload.coords or {}
    if not playerCoords or coordsDistance(playerCoords, npcCoords) > (CFG.ActionDistance or 3.5) then
        dprint('Rejected social action due to distance', src)
        return
    end

    local socialKey = ('%s:%s:%s'):format(tostring(src), payload.npcKey, payload.action)
    local blocked, secs = onCooldown(Cooldowns.actions, socialKey, CFG.ActionCooldownMs or 3500)
    if blocked then
        TriggerClientEvent('azfw:immersion:client:actionResult', src, {
            type = 'error',
            message = ('Let the moment breathe for %ss.'):format(secs),
        })
        return
    end

    local blockedSocial, left = onCooldown(Cooldowns.social, tostring(payload.npcKey), (CFG.SocialCooldownSeconds or 25) * 1000)
    if blockedSocial and payload.action ~= 'report' then
        TriggerClientEvent('azfw:immersion:client:actionResult', src, {
            type = 'error',
            message = ('They need a moment before another interaction (%ss).'):format(left),
        })
        return
    end

    local identity = getPlayerIdentity(src)
    local record = getRelationshipRecord(identity, payload)
    local result = resolveSocialAction(src, identity, record, payload)
    RelationshipState[record.key] = record
    markDirty('relationships')

    TriggerClientEvent('azfw:immersion:client:actionResult', src, result)
end)

exports('getImmersionRelationship', function(src, npcKey)
    local identity = getPlayerIdentity(src)
    return RelationshipState[relationshipKey(identity.charId, tostring(npcKey or ''))]
end)

CreateThread(function()
    Wait(250)
    PropState = fileRead(CFG.Persistence.PropsFile, {}) or {}
    RelationshipState = fileRead(CFG.Persistence.RelationshipsFile, {}) or {}
    ComplaintState = fileRead(CFG.Persistence.ComplaintsFile, {}) or {}
    dprint('Immersion state loaded', 'props=', type(PropState) == 'table' and tostring(#PropState) or 'n/a')

    while true do
        Wait((CFG.SaveIntervalSeconds or 45) * 1000)
        flushState()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE_NAME then return end
    flushState()
end)
