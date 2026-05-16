local RESOURCE_NAME = GetCurrentResourceName()
local Config = (Config and Config.Insurance) or {}
if Config.Enabled == false then return end
if Config.Debug == nil then Config.Debug = true end

local function dprint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    print(("^3[%s]^7 %s"):format(RESOURCE_NAME, table.concat(args, " ")))
end

local fw

do
    local state = GetResourceState("Az-Framework")
    if state == "started" or state == "starting" then
        fw = exports["Az-Framework"]
        dprint("Az-Framework detected – money helpers enabled.")
    else
        dprint("Az-Framework NOT running (" .. state .. ") – money helpers disabled.")
    end
end

local PARKING_RESOURCE = Config.ParkingResource or "Az-Framework"

local function getParkingExports()
    local state = GetResourceState(PARKING_RESOURCE)
    if state ~= "started" and state ~= "starting" then
        dprint(("Parking resource %s not running (%s)"):format(PARKING_RESOURCE, state))
        return nil
    end

    local parkingExports = exports[PARKING_RESOURCE]
    if not parkingExports then
        dprint(("Parking exports not found on %s"):format(PARKING_RESOURCE))
        return nil
    end

    return parkingExports
end

local vehicleTableHasCharId = false
local insuranceTablesReady = false

local function getActiveCharId(src)
    if fw and fw.GetPlayerCharacter then
        local ok, cid = pcall(function()
            return fw:GetPlayerCharacter(src)
        end)
        if ok and cid ~= nil and tostring(cid) ~= '' then
            return tostring(cid)
        end
    end
    return nil
end

local function ensureVehicleTableSchema(cb)
    MySQL.Async.fetchAll("SHOW COLUMNS FROM user_vehicles LIKE 'charid'", {}, function(rows)
        vehicleTableHasCharId = rows and rows[1] ~= nil or false
        if not vehicleTableHasCharId then
            MySQL.Async.execute("ALTER TABLE user_vehicles ADD COLUMN charid VARCHAR(64) NULL DEFAULT NULL AFTER discordid", {}, function()
                MySQL.Async.execute("ALTER TABLE user_vehicles ADD KEY idx_user_vehicles_discordid_charid (discordid, charid)", {}, function()
                    MySQL.Async.fetchAll("SHOW COLUMNS FROM user_vehicles LIKE 'charid'", {}, function(rows2)
                        vehicleTableHasCharId = rows2 and rows2[1] ~= nil or false
                        if cb then cb() end
                    end)
                end)
            end)
        else
            if cb then cb() end
        end
    end)
end

local function ensureInsuranceSchema(cb)
    if insuranceTablesReady then
        if cb then cb() end
        return
    end

    local function finish()
        insuranceTablesReady = true
        if cb then cb() end
    end

    ensureVehicleTableSchema(function()
        MySQL.Async.fetchAll("SHOW COLUMNS FROM user_vehicle_insurance LIKE 'charid'", {}, function(rows)
            local hasPolicyChar = rows and rows[1] ~= nil or false
            local function nextClaims()
                MySQL.Async.fetchAll("SHOW COLUMNS FROM user_vehicle_claims LIKE 'charid'", {}, function(rows2)
                    local hasClaimChar = rows2 and rows2[1] ~= nil or false
                    local function addClaimIndexes()
                        MySQL.Async.fetchAll("SHOW INDEX FROM user_vehicle_insurance", {}, function(policyIndexes)
                            local function hasComposite(rows, keyName)
                                local seen = {}
                                for _, row in ipairs(rows or {}) do
                                    if tostring(row.Key_name or '') == keyName then
                                        seen[tonumber(row.Seq_in_index) or 0] = tostring(row.Column_name or '')
                                    end
                                end
                                return seen[1] == 'discordid' and seen[2] == 'charid'
                            end

                            local function ensureClaimsIndex()
                                MySQL.Async.fetchAll("SHOW INDEX FROM user_vehicle_claims", {}, function(claimIndexes)
                                    if hasComposite(claimIndexes, 'idx_user_vehicle_claims_discordid_charid') then
                                        finish()
                                    else
                                        MySQL.Async.execute("ALTER TABLE user_vehicle_claims ADD KEY idx_user_vehicle_claims_discordid_charid (discordid, charid)", {}, function()
                                            finish()
                                        end)
                                    end
                                end)
                            end

                            if hasComposite(policyIndexes, 'idx_user_vehicle_insurance_discordid_charid') then
                                ensureClaimsIndex()
                            else
                                MySQL.Async.execute("ALTER TABLE user_vehicle_insurance ADD KEY idx_user_vehicle_insurance_discordid_charid (discordid, charid)", {}, function()
                                    ensureClaimsIndex()
                                end)
                            end
                        end)
                    end

                    if not hasClaimChar then
                        MySQL.Async.execute("ALTER TABLE user_vehicle_claims ADD COLUMN charid VARCHAR(64) NULL DEFAULT NULL AFTER discordid", {}, function()
                            addClaimIndexes()
                        end)
                    else
                        addClaimIndexes()
                    end
                end)
            end

            if not hasPolicyChar then
                MySQL.Async.execute("ALTER TABLE user_vehicle_insurance ADD COLUMN charid VARCHAR(64) NULL DEFAULT NULL AFTER discordid", {}, function()
                    nextClaims()
                end)
            else
                nextClaims()
            end
        end)
    end)
end

local function getIdentityContext(src)
    local discordId = nil
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == "discord:" then
            discordId = id:sub(9)
            break
        end
    end
    local charId = getActiveCharId(src)
    return { discordId = discordId and tostring(discordId) or nil, charId = charId and tostring(charId) or nil }
end

local function adoptLegacyVehicleRows(discordId, charId, cb)
    if not vehicleTableHasCharId or not discordId or discordId == '' or not charId or charId == '' then
        if cb then cb() end
        return
    end

    MySQL.Async.execute([[
        UPDATE user_vehicles
        SET charid = @charid
        WHERE discordid = @discordid AND (charid IS NULL OR charid = '')
    ]], {
        ['@discordid'] = discordId,
        ['@charid'] = charId,
    }, function()
        if cb then cb() end
    end)
end

local function adoptLegacyInsuranceRows(discordId, charId, cb)
    if not discordId or discordId == '' or not charId or charId == '' then
        if cb then cb() end
        return
    end

    MySQL.Async.execute([[
        UPDATE user_vehicle_insurance
        SET charid = @charid
        WHERE discordid = @discordid AND (charid IS NULL OR charid = '')
    ]], { ['@discordid'] = discordId, ['@charid'] = charId }, function()
        MySQL.Async.execute([[
            UPDATE user_vehicle_claims
            SET charid = @charid
            WHERE discordid = @discordid AND (charid IS NULL OR charid = '')
        ]], { ['@discordid'] = discordId, ['@charid'] = charId }, function()
            if cb then cb() end
        end)
    end)
end

local function chargePlayer(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    if not fw then
        dprint("chargePlayer: fw is nil – skipping charge (" .. amount .. ")")
        return true
    end

    local ok, err = pcall(function()
        fw:deductMoney(src, amount, reason or "Insurance premium")
    end)

    if not ok then
        dprint(("chargePlayer failed for %s: %s"):format(src, tostring(err)))
        return false
    end

    return true
end

local function payPlayer(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    if not fw then
        dprint("payPlayer: fw is nil – skipping payout (" .. amount .. ")")
        return
    end

    local ok, err = pcall(function()
        fw:addMoney(src, amount, reason or "Insurance payout")
    end)

    if not ok then
        dprint(("payPlayer failed for %s: %s"):format(src, tostring(err)))
    end
end

local function getLicenseIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == "license:" then
            return id
        end
    end
    return "src:" .. tostring(src)
end

local function getDiscordID(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == "discord:" then
            return id:sub(9)
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

local function decodeParkedRows(rows)
    rows = rows or {}
    for _, v in ipairs(rows) do
        v.plate = normalizePlate(v.plate) or tostring(v.plate or '')
        v.props = v.props or (json.decode(v.mods or '{}') or {})
        v.extras = v.extras or (json.decode(v.extras or '{}') or {})
    end
    return rows
end

local function notifyInsurance(src, message)
    TriggerClientEvent('chat:addMessage', src, {
        args = { '^1Insurance', tostring(message or '') }
    })
end

local function createExternalPoliceCall(payload)
    if GetResourceState('Az-MDT') ~= 'started' then
        return false, 'Az-MDT not running'
    end

    local ok, result = pcall(function()
        return exports['Az-MDT']:CreateExternalCall(payload)
    end)
    if not ok then
        return false, result
    end
    return result and true or false, result
end

local function fetchActivePolicies(discordId, charId, cb)
    if not discordId or discordId == "" then
        if cb then cb({}) end
        return
    end

    local query, params
    if charId and charId ~= "" then
        query = [[
            SELECT id, discordid, charid, plate, policy_type, premium, deductible,
                   vehicle_props, next_payment_at, active
            FROM user_vehicle_insurance
            WHERE discordid = @discordid AND charid = @charid AND active = 1
        ]]
        params = { ['@discordid'] = discordId, ['@charid'] = charId }
    else
        query = [[
            SELECT id, discordid, charid, plate, policy_type, premium, deductible,
                   vehicle_props, next_payment_at, active
            FROM user_vehicle_insurance
            WHERE discordid = @discordid AND active = 1
        ]]
        params = { ['@discordid'] = discordId }
    end

    MySQL.Async.fetchAll(query, params, function(rows)
        rows = rows or {}
        for _, row in ipairs(rows) do
            if row.vehicle_props and row.vehicle_props ~= "" then
                local ok, decoded = pcall(json.decode, row.vehicle_props)
                row.props = ok and decoded or {}
            else
                row.props = {}
            end
        end
        if cb then cb(rows) end
    end)
end

local function fetchClaims(discordId, charId, cb)
    if not discordId or discordId == "" then
        if cb then cb({}) end
        return
    end

    local query, params
    if charId and charId ~= "" then
        query = [[
            SELECT id, discordid, charid, plate, policy_type,
                   deductible_charged, payout_value, filed_at, status
            FROM user_vehicle_claims
            WHERE discordid = @discordid AND charid = @charid
            ORDER BY filed_at DESC
            LIMIT 20
        ]]
        params = { ['@discordid'] = discordId, ['@charid'] = charId }
    else
        query = [[
            SELECT id, discordid, charid, plate, policy_type,
                   deductible_charged, payout_value, filed_at, status
            FROM user_vehicle_claims
            WHERE discordid = @discordid
            ORDER BY filed_at DESC
            LIMIT 20
        ]]
        params = { ['@discordid'] = discordId }
    end

    MySQL.Async.fetchAll(query, params, function(rows)
        if cb then cb(rows or {}) end
    end)
end

local function fetchLastClaimTime(discordId, charId, plate, cb)
    if not discordId or not plate or plate == "" then
        if cb then cb(nil) end
        return
    end

    local query, params
    if charId and charId ~= "" then
        query = [[
            SELECT filed_at
            FROM user_vehicle_claims
            WHERE discordid = @discordid AND charid = @charid AND plate = @plate
            ORDER BY filed_at DESC
            LIMIT 1
        ]]
        params = { ['@discordid'] = discordId, ['@charid'] = charId, ['@plate'] = plate }
    else
        query = [[
            SELECT filed_at
            FROM user_vehicle_claims
            WHERE discordid = @discordid AND plate = @plate
            ORDER BY filed_at DESC
            LIMIT 1
        ]]
        params = { ['@discordid'] = discordId, ['@plate'] = plate }
    end

    MySQL.Async.fetchScalar(query, params, function(ts)
        if cb then cb(tonumber(ts)) end
    end)
end

local function upsertPolicy(discordId, charId, plate, policyType, premium, deductible, props, cb)
    local propsJson     = json.encode(props or {})
    local nextPaymentAt = os.time() + (Config.PremiumIntervalMinutes or 10) * 60

    if charId and charId ~= "" then
        MySQL.Async.execute([[
            INSERT INTO user_vehicle_insurance
                (discordid, charid, plate, policy_type, premium, deductible, vehicle_props, next_payment_at, active)
            VALUES
                (@discordid, @charid, @plate, @policy_type, @premium, @deductible, @vehicle_props, @next_payment_at, 1)
            ON DUPLICATE KEY UPDATE
                charid          = VALUES(charid),
                policy_type     = VALUES(policy_type),
                premium         = VALUES(premium),
                deductible      = VALUES(deductible),
                vehicle_props   = VALUES(vehicle_props),
                next_payment_at = VALUES(next_payment_at),
                active          = 1
        ]], {
            ['@discordid']       = discordId,
            ['@charid']          = charId,
            ['@plate']           = plate,
            ['@policy_type']     = policyType,
            ['@premium']         = premium,
            ['@deductible']      = deductible,
            ['@vehicle_props']   = propsJson,
            ['@next_payment_at'] = nextPaymentAt
        }, function(_)
            if cb then cb() end
        end)
        return
    end

    MySQL.Async.execute([[
        INSERT INTO user_vehicle_insurance
            (discordid, plate, policy_type, premium, deductible, vehicle_props, next_payment_at, active)
        VALUES
            (@discordid, @plate, @policy_type, @premium, @deductible, @vehicle_props, @next_payment_at, 1)
        ON DUPLICATE KEY UPDATE
            policy_type     = VALUES(policy_type),
            premium         = VALUES(premium),
            deductible      = VALUES(deductible),
            vehicle_props   = VALUES(vehicle_props),
            next_payment_at = VALUES(next_payment_at),
            active          = 1
    ]], {
        ['@discordid']       = discordId,
        ['@plate']           = plate,
        ['@policy_type']     = policyType,
        ['@premium']         = premium,
        ['@deductible']      = deductible,
        ['@vehicle_props']   = propsJson,
        ['@next_payment_at'] = nextPaymentAt
    }, function(_)
        if cb then cb() end
    end)
end

local function deactivatePolicy(discordId, charId, plate, cb)
    local query, params
    if charId and charId ~= "" then
        query = [[
            UPDATE user_vehicle_insurance
            SET active = 0
            WHERE discordid = @discordid AND charid = @charid AND plate = @plate
        ]]
        params = { ['@discordid'] = discordId, ['@charid'] = charId, ['@plate'] = plate }
    else
        query = [[
            UPDATE user_vehicle_insurance
            SET active = 0
            WHERE discordid = @discordid AND plate = @plate
        ]]
        params = { ['@discordid'] = discordId, ['@plate'] = plate }
    end

    MySQL.Async.execute(query, params, function(_)
        if cb then cb() end
    end)
end

local function fetchPolicy(discordId, charId, plate, cb)
    if not discordId or not plate or plate == "" then
        if cb then cb(nil) end
        return
    end

    local query, params
    if charId and charId ~= "" then
        query = [[
            SELECT id, discordid, charid, plate, policy_type, premium, deductible,
                   vehicle_props, next_payment_at, active
            FROM user_vehicle_insurance
            WHERE discordid = @discordid AND charid = @charid AND plate = @plate AND active = 1
            LIMIT 1
        ]]
        params = { ['@discordid'] = discordId, ['@charid'] = charId, ['@plate'] = plate }
    else
        query = [[
            SELECT id, discordid, charid, plate, policy_type, premium, deductible,
                   vehicle_props, next_payment_at, active
            FROM user_vehicle_insurance
            WHERE discordid = @discordid AND plate = @plate AND active = 1
            LIMIT 1
        ]]
        params = { ['@discordid'] = discordId, ['@plate'] = plate }
    end

    MySQL.Async.fetchAll(query, params, function(rows)
        local row = rows and rows[1] or nil
        if row and row.vehicle_props and row.vehicle_props ~= "" then
            local ok, decoded = pcall(json.decode, row.vehicle_props)
            row.props = ok and decoded or {}
        elseif row then
            row.props = {}
        end
        if cb then cb(row) end
    end)
end

local function insertClaim(discordId, charId, plate, policyType, deductibleCharged, payoutValue, status, cb)
    if charId and charId ~= "" then
        MySQL.Async.execute([[
            INSERT INTO user_vehicle_claims
                (discordid, charid, plate, policy_type, deductible_charged, payout_value, filed_at, status)
            VALUES
                (@discordid, @charid, @plate, @policy_type, @deductible_charged, @payout_value, @filed_at, @status)
        ]], {
            ['@discordid']          = discordId,
            ['@charid']             = charId,
            ['@plate']              = plate,
            ['@policy_type']        = policyType,
            ['@deductible_charged'] = deductibleCharged or 0,
            ['@payout_value']       = payoutValue or 0,
            ['@filed_at']           = os.time(),
            ['@status']             = status or "approved"
        }, function(_)
            if cb then cb() end
        end)
        return
    end

    MySQL.Async.execute([[
        INSERT INTO user_vehicle_claims
            (discordid, plate, policy_type, deductible_charged, payout_value, filed_at, status)
        VALUES
            (@discordid, @plate, @policy_type, @deductible_charged, @payout_value, @filed_at, @status)
    ]], {
        ['@discordid']          = discordId,
        ['@plate']              = plate,
        ['@policy_type']        = policyType,
        ['@deductible_charged'] = deductibleCharged or 0,
        ['@payout_value']       = payoutValue or 0,
        ['@filed_at']           = os.time(),
        ['@status']             = status or "approved"
    }, function(_)
        if cb then cb() end
    end)
end

local function fetchParkedVehiclesForCharacter(discordId, charId, cb)
    if not discordId or discordId == "" then
        if cb then cb({}) end
        return
    end

    local parkingExports = getParkingExports()
    if parkingExports and parkingExports.GetPlayerParkedVehicles then
        local ok = pcall(function()
            parkingExports:GetPlayerParkedVehicles(discordId, charId, function(results)
                if cb then cb(decodeParkedRows(results or {})) end
            end)
        end)
        if ok then
            return
        end
    end

    local function runDirectQuery()
        local query, params
        if vehicleTableHasCharId and charId and charId ~= "" then
            query = [[
                SELECT discordid, charid, plate, model, x, y, z, h,
                       color1, color2, pearlescent, wheelColor, wheelType, windowTint,
                       mods, extras
                FROM user_vehicles
                WHERE discordid = @discordid AND charid = @charid
            ]]
            params = { ['@discordid'] = discordId, ['@charid'] = charId }
        else
            query = [[
                SELECT discordid, charid, plate, model, x, y, z, h,
                       color1, color2, pearlescent, wheelColor, wheelType, windowTint,
                       mods, extras
                FROM user_vehicles
                WHERE discordid = @discordid
            ]]
            params = { ['@discordid'] = discordId }
        end

        MySQL.Async.fetchAll(query, params, function(results)
            if cb then cb(decodeParkedRows(results or {})) end
        end)
    end

    adoptLegacyVehicleRows(discordId, charId, runDirectQuery)
end

local function fetchPropsForPlate(discordId, charId, plate, cb)
    fetchParkedVehiclesForCharacter(discordId, charId, function(results)
        local found = nil
        for _, row in ipairs(results or {}) do
            if normalizePlate(row.plate) == normalizePlate(plate) then
                found = row
                break
            end
        end
        local props = found and (found.props or {}) or nil
        if cb then cb(props) end
    end)
end

local function isPlateParked(discordId, charId, plate, cb)
    fetchParkedVehiclesForCharacter(discordId, charId, function(results)
        local parked = false
        for _, row in ipairs(results or {}) do
            if normalizePlate(row.plate) == normalizePlate(plate) then
                parked = true
                break
            end
        end
        if cb then cb(parked) end
    end)
end

local function buildSnapshot(src, cb)
    ensureInsuranceSchema(function()
        local identity = getIdentityContext(src)
        local discordId = identity.discordId
        local charId = identity.charId
        if not discordId then
            dprint(("buildSnapshot: no discord ID for %s"):format(src))
            if cb then cb({
                vehicles               = {},
                claims                 = {},
                premiumIntervalMinutes = Config.PremiumIntervalMinutes or 10,
                serverTime             = os.time(),
                policyTypes            = Config.PolicyTypes or {},
                claimCooldownMinutes   = Config.ClaimCooldownMinutes or 30,
                insuredCount           = 0,
                parkedCount            = 0,
                activeCharId           = charId,
            }) end
            return
        end

        adoptLegacyInsuranceRows(discordId, charId, function()
            fetchActivePolicies(discordId, charId, function(policies)
                fetchParkedVehiclesForCharacter(discordId, charId, function(parkedRows)
                    fetchClaims(discordId, charId, function(claimRows)
                policies   = policies   or {}
                parkedRows = parkedRows or {}
                claimRows  = claimRows  or {}

                local policiesByPlate = {}
                for _, p in ipairs(policies) do
                    policiesByPlate[normalizePlate(p.plate) or tostring(p.plate or '')] = p
                end

                local vehicles  = {}
                local seenPlate = {}

                for _, row in ipairs(parkedRows) do
                    local plate = normalizePlate(row.plate) or "UNKNOWN"
                    seenPlate[plate] = true

                    local policy  = policiesByPlate[plate]
                    local insured = policy ~= nil
                    local props   = (policy and policy.props) or row.props or {}

                    table.insert(vehicles, {
                        plate       = plate,
                        model       = row.model or (props and (props.model or props.modelHash)) or "Vehicle",
                        garage      = nil,
                        stored      = true,
                        parked      = true,
                        insured     = insured,
                        policyType  = policy and policy.policy_type or nil,
                        premium     = policy and policy.premium or 0,
                        deductible  = policy and policy.deductible or 0,
                        nextPaymentAt = policy and policy.next_payment_at or 0,

                        props       = props,
                        rawParking  = row,
                        rawPolicy   = policy,
                    })
                end

                for _, policy in ipairs(policies) do
                    local policyPlate = normalizePlate(policy.plate) or tostring(policy.plate or '')
                    if not seenPlate[policyPlate] then
                        local props = policy.props or {}

                        table.insert(vehicles, {
                            plate       = policyPlate,
                            model       = (props and (props.model or props.modelHash)) or "Vehicle",
                            garage      = nil,
                            stored      = false,
                            parked      = false,
                            insured     = true,
                            policyType  = policy.policy_type,
                            premium     = policy.premium,
                            deductible  = policy.deductible,
                            nextPayment = policy.next_payment_at,
                            props       = props,
                            rawPolicy   = policy,
                        })
                    end
                end

                local insuredCount = 0
                local parkedCount  = 0

                for _, v in ipairs(vehicles) do
                    if v.insured then
                        insuredCount = insuredCount + 1
                    end
                    if v.stored then
                        parkedCount = parkedCount + 1
                    end
                end

                local claims = {}
                for _, c in ipairs(claimRows) do
table.insert(claims, {
    id         = c.id,
    plate      = c.plate,
    policyType = c.policy_type,
    filedAt    = c.filed_at,
    filed_at   = c.filed_at,
    status     = c.status or "approved",
})

                end

                local snapshot = {
                    vehicles               = vehicles,
                    claims                 = claims,
                    premiumIntervalMinutes = Config.PremiumIntervalMinutes or 10,
                    serverTime             = os.time(),
                    policyTypes            = Config.PolicyTypes or {},
                    claimCooldownMinutes   = Config.ClaimCooldownMinutes or 30,
                    insuredCount           = insuredCount,
                    parkedCount            = parkedCount,
                    activeCharId           = charId,
                }

                if cb then cb(snapshot) end
                    end)
                end)
            end)
        end)
    end)
end

local function getPlayerSpawnPoint(src)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local coords  = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        return {
            x = coords.x or coords[1] or 0.0,
            y = coords.y or coords[2] or 0.0,
            z = coords.z or coords[3] or 72.0,
            h = heading or 0.0
        }
    end

    return { x = 0.0, y = 0.0, z = 72.0, h = 0.0 }
end

local function spawnClaimVehicle(src, plate, props)
    local spawn = getPlayerSpawnPoint(src)

    TriggerClientEvent("az_insurance:spawnInsuredVehicle", src, {
        plate = plate,
        props = props or {},
        spawn = spawn
    })

    buildSnapshot(src, function(snapshot)
        TriggerClientEvent("az_insurance:openUI", src, snapshot)
    end)
end

CreateThread(function()
    ensureInsuranceSchema(function()
        dprint(('Insurance schema ready. user_vehicles.charid=%s'):format(tostring(vehicleTableHasCharId)))
    end)
end)

RegisterNetEvent("az_insurance:requestOpen", function()
    local src = source
    dprint(("requestOpen from %s"):format(src))

    buildSnapshot(src, function(snapshot)
        TriggerClientEvent("az_insurance:openUI", src, snapshot)
    end)
end)

RegisterNetEvent("az_insurance:startPolicy", function(plate, policyType)
    local src = source
    plate = normalizePlate(type(plate) == "string" and plate or nil)
    if not plate or plate == "" then return end

    ensureInsuranceSchema(function()
        local identity = getIdentityContext(src)
        local discordId = identity.discordId
        local charId = identity.charId
        if not discordId then
            TriggerClientEvent("chat:addMessage", src, {
                args = { "^1Insurance", "Discord is required for insurance." }
            })
            return
        end

        policyType = policyType or "standard"
        local licenseIdent = getLicenseIdentifier(src)
        local policyCfg = (Config.PolicyTypes or {})[policyType] or {}
        local basePremium = tonumber(policyCfg.premium or policyCfg.basePremium or Config.DefaultPremium or Config.BasePremium or 250) or 250
        local premium = math.floor(tonumber(policyCfg.premium or (basePremium * tonumber(policyCfg.premiumMultiplier or 1.0))) or basePremium)
        local deductible = math.floor(tonumber(policyCfg.deductible or Config.DefaultDeductible or 0) or 0)

        dprint(("startPolicy: src=%s lic=%s discord=%s charid=%s plate=%s type=%s premium=%s deduct=%s"):
            format(src, licenseIdent, discordId, tostring(charId), plate, policyType, premium, deductible))

        adoptLegacyInsuranceRows(discordId, charId, function()
            fetchPropsForPlate(discordId, charId, plate, function(props)
                if not props or next(props) == nil then
                    TriggerClientEvent("chat:addMessage", src, {
                        args = { "^1Insurance", "Park your vehicle first using the parking script before starting coverage." }
                    })
                    return
                end

                if not chargePlayer(src, premium, "Insurance premium") then
                    TriggerClientEvent("chat:addMessage", src, {
                        args = { "^1Insurance", "Unable to start policy – payment failed." }
                    })
                    return
                end

                upsertPolicy(discordId, charId, plate, policyType, premium, deductible, props, function()
                    buildSnapshot(src, function(snapshot)
                        TriggerClientEvent("az_insurance:openUI", src, snapshot)
                    end)
                end)
            end)
        end)
    end)
end)

RegisterNetEvent("az_insurance:cancelPolicy", function(plate)
    local src = source
    plate = normalizePlate(type(plate) == "string" and plate or nil)
    if not plate or plate == "" then return end

    ensureInsuranceSchema(function()
        local identity = getIdentityContext(src)
        local discordId = identity.discordId
        local charId = identity.charId
        if not discordId then return end

        dprint(("cancelPolicy: src=%s discord=%s charid=%s plate=%s"):format(src, discordId, tostring(charId), plate))

        adoptLegacyInsuranceRows(discordId, charId, function()
            deactivatePolicy(discordId, charId, plate, function()
                buildSnapshot(src, function(snapshot)
                    TriggerClientEvent("az_insurance:openUI", src, snapshot)
                end)
            end)
        end)
    end)
end)

RegisterNetEvent("az_insurance:fileClaim", function(plate)
    local src = source
    plate = normalizePlate(type(plate) == "string" and plate or nil)
    if not plate or plate == "" then return end

    ensureInsuranceSchema(function()
        local identity = getIdentityContext(src)
        local discordId = identity.discordId
        local charId = identity.charId
        if not discordId then
            TriggerClientEvent("chat:addMessage", src, {
                args = { "^1Insurance", "Discord is required for insurance." }
            })
            return
        end

        adoptLegacyInsuranceRows(discordId, charId, function()
            fetchPolicy(discordId, charId, plate, function(policy)
                if not policy then
                    TriggerClientEvent("chat:addMessage", src, {
                        args = { "^1Insurance", "You don't have an active policy for this vehicle." }
                    })
                    return
                end

                local now = os.time()
                local cooldownS = (Config.ClaimCooldownMinutes or 30) * 60

                fetchLastClaimTime(discordId, charId, plate, function(lastClaimAt)
                    if lastClaimAt and (now - lastClaimAt) < cooldownS then
                        local remaining = math.floor((cooldownS - (now - lastClaimAt)) / 60)
                        TriggerClientEvent("chat:addMessage", src, {
                            args = { "^1Insurance", ("You must wait %d more minute(s) before filing another claim."):format(remaining) }
                        })
                        return
                    end

                    isPlateParked(discordId, charId, plate, function(parked)
                        if parked then
                            TriggerClientEvent("chat:addMessage", src, {
                                args = { "^1Insurance", "This vehicle is still parked. You can only file a THEFT claim when the vehicle is missing." }
                            })
                            return
                        end

                        local deductible = policy.deductible or 0
                        if deductible > 0 then
                            if not chargePlayer(src, deductible, "Insurance deductible") then
                                TriggerClientEvent("chat:addMessage", src, {
                                    args = { "^1Insurance", "Unable to charge deductible for this claim." }
                                })
                                return
                            end
                        end

                        local payoutValue = 0

                        insertClaim(discordId, charId, plate, policy.policy_type, deductible, payoutValue, "approved", function()
                            dprint(("fileClaim: src=%s discord=%s charid=%s plate=%s policy=%s deduct=%s payout=%s (NOT parked, spawning at player)"):
                                format(src, discordId, tostring(charId), plate, policy.policy_type, deductible, payoutValue))

                            local props = policy.props or {}
                            spawnClaimVehicle(src, plate, props)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)

RegisterNetEvent('az_insurance:wreckExchangeComplete', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}
    local plate = normalizePlate(payload.playerPlate or payload.plate)
    if not plate then return end

    ensureInsuranceSchema(function()
        local identity = getIdentityContext(src)
        local discordId = identity.discordId
        local charId = identity.charId
        if not discordId then
            notifyInsurance(src, 'Discord is required for collision claims.')
            return
        end

        adoptLegacyInsuranceRows(discordId, charId, function()
            fetchPolicy(discordId, charId, plate, function(policy)
                if not policy then
                    notifyInsurance(src, ('Insurance information exchanged for %s, but there is no active policy on that vehicle.'):format(plate))
                    return
                end

                local deductible = math.floor(tonumber(policy.deductible or 0) or 0)
                if deductible > 0 then
                    if not chargePlayer(src, deductible, 'Collision insurance deductible') then
                        notifyInsurance(src, 'Unable to charge your collision deductible.')
                        return
                    end
                end

                insertClaim(discordId, charId, plate, policy.policy_type, deductible, 0, 'collision_exchange', function()
                    if ((Config.WreckSystem or {}).AutoRepairOnExchange) ~= false then
                        SetTimeout(12000, function()
                            TriggerClientEvent('az_insurance:repairVehicle', src, { plate = plate })
                        end)
                    end

                    notifyInsurance(src, ('Insurance was exchanged for %s. The claim was recorded and the repair will be processed shortly.'):format(plate))
                end)
            end)
        end)
    end)
end)

RegisterNetEvent('az_insurance:reportHitAndRun', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}

    local coords = payload.coords or {}
    local suspectPlate = normalizePlate(payload.playerPlate or payload.suspectPlate)
    local color = tostring(payload.playerColor or payload.suspectColor or 'unknown color')
    local model = tostring(payload.playerModel or payload.suspectModel or 'vehicle')
    local location = tostring(payload.location or payload.street or 'Unknown location')

    local pieces = { ('Hit and run after collision with AI driver'), ('vehicle %s'):format(model), ('color %s'):format(color) }
    if suspectPlate and suspectPlate ~= '' then
        pieces[#pieces + 1] = ('plate %s'):format(suspectPlate)
    end

    local ok, result = createExternalPoliceCall({
        department = tostring((((Config.WreckSystem or {}).ReportDepartment) or 'police')),
        caller = 'Civilian Driver',
        title = 'Hit and Run',
        message = table.concat(pieces, ', '),
        location = location,
        coords = {
            x = tonumber(coords.x) or 0.0,
            y = tonumber(coords.y) or 0.0,
            z = tonumber(coords.z) or 0.0,
        },
        sourceResource = 'Az-Framework/InsuranceWreck',
        externalResource = 'Az-Framework/InsuranceWreck',
        metadata = {
            plate = suspectPlate,
            color = color,
            model = model,
            department = tostring((((Config.WreckSystem or {}).ReportDepartment) or 'police')),
        }
    })

    if ok then
        notifyInsurance(src, 'The other driver reported the hit and run to police.')
    else
        notifyInsurance(src, ('The other driver tried to call police, but MDT call creation failed: %s'):format(tostring(result)))
    end
end)
