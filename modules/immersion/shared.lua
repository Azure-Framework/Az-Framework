Config = Config or {}
local CFG = (Config and Config.Immersion) or {}
if CFG.Enabled == false then return end

AZ_IMMERSION_SHARED = AZ_IMMERSION_SHARED or {}
local Shared = AZ_IMMERSION_SHARED

Shared.PropActions = Shared.PropActions or {
    inspect = {
        label = 'Inspect',
        icon = 'fa-solid fa-magnifying-glass',
        description = 'Take a closer look and read the scene.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    check_mail = {
        label = 'Check Mail',
        icon = 'fa-solid fa-envelope-open-text',
        description = 'Check what is sitting in the mailbox.',
        duration = 2600,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    leave_note = {
        label = 'Leave Note',
        icon = 'fa-solid fa-note-sticky',
        description = 'Leave a note or message behind.',
        duration = 2600,
        prompt = 'note',
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    hide_item = {
        label = 'Hide Small Item',
        icon = 'fa-solid fa-box-open',
        description = 'Tuck something small out of sight.',
        duration = 3100,
        prompt = 'item',
        scenario = 'WORLD_HUMAN_BUM_WASH'
    },
    pry_open = {
        label = 'Pry Open',
        icon = 'fa-solid fa-screwdriver-wrench',
        description = 'Force the prop open and risk attention.',
        duration = 5400,
        skill = { 'easy', 'medium', 'hard' },
        risky = true,
        scenario = 'WORLD_HUMAN_WELDING'
    },
    search = {
        label = 'Search',
        icon = 'fa-solid fa-boxes-stacked',
        description = 'Dig through it and see what is there.',
        duration = 4200,
        skill = { 'easy', 'easy', 'medium' },
        scenario = 'PROP_HUMAN_BUM_BIN'
    },
    clean_up = {
        label = 'Clean Up',
        icon = 'fa-solid fa-soap',
        description = 'Tidy the area and reduce the mess.',
        duration = 3600,
        scenario = 'WORLD_HUMAN_JANITOR'
    },
    bag_evidence = {
        label = 'Bag Evidence',
        icon = 'fa-solid fa-fingerprint',
        description = 'Collect possible evidence from the item.',
        duration = 3200,
        scenario = 'CODE_HUMAN_MEDIC_TEND_TO_DEAD'
    },
    drink = {
        label = 'Drink',
        icon = 'fa-solid fa-mug-hot',
        description = 'Take a quick drink if there is anything left.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_DRINKING'
    },
    dispose = {
        label = 'Dispose',
        icon = 'fa-solid fa-recycle',
        description = 'Throw it away or tidy up after yourself.',
        duration = 1800,
        scenario = 'PROP_HUMAN_BUM_BIN'
    },
    cut_chain = {
        label = 'Cut Chain',
        icon = 'fa-solid fa-link-slash',
        description = 'Cut a lock or chain free. Very suspicious.',
        duration = 5800,
        skill = { 'medium', 'medium', 'hard' },
        risky = true,
        scenario = 'WORLD_HUMAN_WELDING'
    },
    lock_bike = {
        label = 'Lock Bike',
        icon = 'fa-solid fa-lock',
        description = 'Secure your bike or make it look occupied.',
        duration = 2400,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    leave_gift = {
        label = 'Leave Gift',
        icon = 'fa-solid fa-gift',
        description = 'Leave flowers, a note, or something sentimental.',
        duration = 2500,
        prompt = 'gift',
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    report = {
        label = 'Report Suspicious Activity',
        icon = 'fa-solid fa-triangle-exclamation',
        description = 'File a player report into Az-Framework admin reports.',
        duration = 1200,
        prompt = 'report'
    },
    cool_off = {
        label = 'Cool Off',
        icon = 'fa-solid fa-snowflake',
        description = 'Step into the shade and cool down a bit.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    reserve_spot = {
        label = 'Reserve Spot',
        icon = 'fa-solid fa-map-pin',
        description = 'Claim the setup for your group and keep it occupied.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    relax = {
        label = 'Relax',
        icon = 'fa-solid fa-face-smile-beam',
        description = 'Kick back and enjoy the summer weather.',
        duration = 2600,
        scenario = 'WORLD_HUMAN_SUNBATHE_BACK'
    },
    tan = {
        label = 'Sunbathe',
        icon = 'fa-solid fa-sun',
        description = 'Lay out in the sun for a while.',
        duration = 3200,
        scenario = 'WORLD_HUMAN_SUNBATHE'
    },
    pack_up = {
        label = 'Pack Up',
        icon = 'fa-solid fa-box',
        description = 'Tidy the setup and clear the area out.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_GARDENER_PLANT'
    },
    grab_drink = {
        label = 'Grab Cold Drink',
        icon = 'fa-solid fa-bottle-water',
        description = 'Take a chilled drink out of the cooler.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_DRINKING'
    },
    stock_cooler = {
        label = 'Restock Cooler',
        icon = 'fa-solid fa-boxes-stacked',
        description = 'Top the cooler back up for the group.',
        duration = 2600,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    wax_board = {
        label = 'Wax Board',
        icon = 'fa-solid fa-soap',
        description = 'Prep the board so it grips better in the water.',
        duration = 2500,
        scenario = 'WORLD_HUMAN_HAMMERING'
    },
    rent_board = {
        label = 'Rent Board',
        icon = 'fa-solid fa-file-signature',
        description = 'Check whether any boards are still available today.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    start_surf = {
        label = 'Ride Out',
        icon = 'fa-solid fa-water',
        description = 'Head into the water and try to catch a wave.',
        duration = 3400,
        skill = { 'easy', 'medium', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    toss_ball = {
        label = 'Toss Ball',
        icon = 'fa-solid fa-baseball',
        description = 'Knock the ball around casually.',
        duration = 1700,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    play_volleyball = {
        label = 'Play Volleyball',
        icon = 'fa-solid fa-volleyball',
        description = 'Jump into a quick beach match.',
        duration = 3000,
        skill = { 'easy', 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    organize_match = {
        label = 'Organize Match',
        icon = 'fa-solid fa-people-group',
        description = 'Get the court going and pull people in.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    grill_food = {
        label = 'Grill Food',
        icon = 'fa-solid fa-burger',
        description = 'Throw some food on the grill.',
        duration = 3200,
        skill = { 'easy', 'medium' },
        scenario = 'PROP_HUMAN_BBQ'
    },
    refuel_grill = {
        label = 'Refuel Grill',
        icon = 'fa-solid fa-gas-pump',
        description = 'Top off the fuel so it can keep cooking.',
        duration = 2500,
        scenario = 'WORLD_HUMAN_HAMMERING'
    },
    set_picnic = {
        label = 'Set Picnic',
        icon = 'fa-solid fa-utensils',
        description = 'Lay out food and get the hangout ready.',
        duration = 2600,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    hang_out = {
        label = 'Hang Out',
        icon = 'fa-solid fa-champagne-glasses',
        description = 'Enjoy the moment with the people around you.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_PARTYING'
    },
    set_camp = {
        label = 'Set Camp',
        icon = 'fa-solid fa-campground',
        description = 'Straighten the site and make it usable for the night.',
        duration = 3000,
        scenario = 'WORLD_HUMAN_GARDENER_PLANT'
    },
    rest_camp = {
        label = 'Rest At Camp',
        icon = 'fa-solid fa-moon',
        description = 'Take a breather at the camp setup.',
        duration = 2400,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    break_camp = {
        label = 'Break Camp',
        icon = 'fa-solid fa-box-archive',
        description = 'Pack the site down and leave less behind.',
        duration = 2600,
        scenario = 'WORLD_HUMAN_GARDENER_PLANT'
    },
    start_bonfire = {
        label = 'Start Bonfire',
        icon = 'fa-solid fa-fire',
        description = 'Try to get the firepit going.',
        duration = 2800,
        skill = { 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_FIRE'
    },
    roast_food = {
        label = 'Roast Food',
        icon = 'fa-solid fa-hotdog',
        description = 'Cook something over the fire.',
        duration = 2400,
        scenario = 'WORLD_HUMAN_STAND_FIRE'
    },
    put_out_fire = {
        label = 'Put Out Fire',
        icon = 'fa-solid fa-fire-extinguisher',
        description = 'Put the fire down before it becomes a problem.',
        duration = 2300,
        scenario = 'WORLD_HUMAN_CONST_DRILL'
    },
    buy_treat = {
        label = 'Buy Treat',
        icon = 'fa-solid fa-ice-cream',
        description = 'Grab a summer snack or cold drink.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    play_ring_toss = {
        label = 'Play Ring Toss',
        icon = 'fa-solid fa-bullseye',
        description = 'Try your luck at a booth game.',
        duration = 2200,
        skill = { 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    take_photo = {
        label = 'Take Photo',
        icon = 'fa-solid fa-camera-retro',
        description = 'Snap a summer memory at the boardwalk.',
        duration = 1600,
        scenario = 'WORLD_HUMAN_TOURIST_MAP'
    },
    sit_down = {
        label = 'Sit Down',
        icon = 'fa-solid fa-person-seat',
        description = 'Take a seat and stay awhile.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_PICNIC'
    },
    lounge_out = {
        label = 'Lounge Out',
        icon = 'fa-solid fa-couch',
        description = 'Stretch out and enjoy the heat.',
        duration = 2400,
        scenario = 'WORLD_HUMAN_SUNBATHE_BACK'
    },
    unpack_bag = {
        label = 'Unpack Bag',
        icon = 'fa-solid fa-bag-shopping',
        description = 'Pull out supplies and make the spot look in use.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    stash_supplies = {
        label = 'Stash Supplies',
        icon = 'fa-solid fa-box-open',
        description = 'Tuck snacks or extras into the bag.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    play_music = {
        label = 'Play Music',
        icon = 'fa-solid fa-music',
        description = 'Turn on something summery for the area.',
        duration = 1600,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    dance = {
        label = 'Dance / Vibe',
        icon = 'fa-solid fa-compact-disc',
        description = 'Catch the beat and liven the area up.',
        duration = 2100,
        scenario = 'WORLD_HUMAN_PARTYING'
    },
    rent_float = {
        label = 'Rent Float',
        icon = 'fa-solid fa-life-ring',
        description = 'Grab a float or ring for the water.',
        duration = 2000,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    drift_float = {
        label = 'Drift In Water',
        icon = 'fa-solid fa-water',
        description = 'Take it easy and float around for a bit.',
        duration = 2600,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    rinse_off = {
        label = 'Rinse Off',
        icon = 'fa-solid fa-shower',
        description = 'Wash the salt, chlorine, or sand off.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_BUM_WASH'
    },
    change_outfit = {
        label = 'Change Outfit',
        icon = 'fa-solid fa-shirt',
        description = 'Duck in and change into something else.',
        duration = 2600,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    watch_water = {
        label = 'Watch Water',
        icon = 'fa-solid fa-binoculars',
        description = 'Keep an eye on the water and the crowd.',
        duration = 2200,
        scenario = 'WORLD_HUMAN_GUARD_STAND'
    },
    toss_frisbee = {
        label = 'Throw Frisbee',
        icon = 'fa-solid fa-compact-disc',
        description = 'Start a casual frisbee toss.',
        duration = 1800,
        skill = { 'easy', 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    kick_ball = {
        label = 'Kick Ball',
        icon = 'fa-solid fa-futbol',
        description = 'Pass or dribble around with it.',
        duration = 1900,
        skill = { 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    throw_football = {
        label = 'Throw Football',
        icon = 'fa-solid fa-football',
        description = 'Run a few routes and toss it around.',
        duration = 1900,
        skill = { 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    play_yard_game = {
        label = 'Play Yard Game',
        icon = 'fa-solid fa-gamepad',
        description = 'Jump into an easy backyard summer game.',
        duration = 2200,
        skill = { 'easy', 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    eat_snack = {
        label = 'Eat Snack',
        icon = 'fa-solid fa-cookie-bite',
        description = 'Have a quick bite and relax.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_DRINKING'
    },
    buy_icecream = {
        label = 'Buy Ice Cream',
        icon = 'fa-solid fa-ice-cream',
        description = 'Grab something cold before it melts.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    buy_food = {
        label = 'Buy Food',
        icon = 'fa-solid fa-hotdog',
        description = 'Pick up something hot from the stand.',
        duration = 2000,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    play_arcade = {
        label = 'Play Booth Game',
        icon = 'fa-solid fa-ticket',
        description = 'Try a quick game or machine nearby.',
        duration = 2000,
        skill = { 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    set_table = {
        label = 'Set Table',
        icon = 'fa-solid fa-table-picnic',
        description = 'Set the table up for drinks, cards, or food.',
        duration = 2400,
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    },
    sway_hammock = {
        label = 'Rest In Hammock',
        icon = 'fa-solid fa-bed',
        description = 'Lean back and enjoy the slower pace.',
        duration = 2400,
        scenario = 'WORLD_HUMAN_SUNBATHE_BACK'
    },
    light_lantern = {
        label = 'Light Lantern',
        icon = 'fa-solid fa-lightbulb',
        description = 'Get a little evening light going.',
        duration = 2100,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    gather_wood = {
        label = 'Gather Firewood',
        icon = 'fa-solid fa-tree',
        description = 'Move some wood over for the fire.',
        duration = 2300,
        scenario = 'WORLD_HUMAN_GARDENER_PLANT'
    },
    splash_around = {
        label = 'Splash Around',
        icon = 'fa-solid fa-droplet',
        description = 'Cool off and make a little summer chaos.',
        duration = 2000,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    },
    enjoy_playground = {
        label = 'Use Playground',
        icon = 'fa-solid fa-child-reaching',
        description = 'Take in the park energy and hang around.',
        duration = 2100,
        scenario = 'WORLD_HUMAN_PICNIC'
    }
}

Shared.PropFamilyActions = Shared.PropFamilyActions or {
    mailbox = { 'inspect', 'check_mail', 'leave_note', 'hide_item', 'pry_open', 'bag_evidence', 'report' },
    trash = { 'inspect', 'search', 'hide_item', 'clean_up', 'bag_evidence', 'report' },
    cup = { 'inspect', 'drink', 'dispose', 'bag_evidence', 'report' },
    bike_rack = { 'inspect', 'lock_bike', 'cut_chain', 'leave_gift', 'report' },
    umbrella = { 'inspect', 'cool_off', 'reserve_spot', 'clean_up', 'report' },
    towel = { 'inspect', 'relax', 'tan', 'pack_up', 'report' },
    cooler = { 'inspect', 'grab_drink', 'stock_cooler', 'clean_up', 'report' },
    beach_bag = { 'inspect', 'unpack_bag', 'stash_supplies', 'reserve_spot', 'pack_up', 'report' },
    beach_chair = { 'inspect', 'sit_down', 'relax', 'tan', 'reserve_spot', 'report' },
    lounger = { 'inspect', 'lounge_out', 'relax', 'tan', 'cool_off', 'report' },
    surfboard = { 'inspect', 'wax_board', 'rent_board', 'start_surf', 'report' },
    floatie = { 'inspect', 'rent_float', 'drift_float', 'cool_off', 'report' },
    lifeguard_post = { 'inspect', 'watch_water', 'take_photo', 'report' },
    shower = { 'inspect', 'rinse_off', 'cool_off', 'report' },
    changing_booth = { 'inspect', 'change_outfit', 'report' },
    volleyball = { 'inspect', 'toss_ball', 'play_volleyball', 'organize_match', 'clean_up', 'report' },
    frisbee = { 'inspect', 'toss_frisbee', 'organize_match', 'clean_up', 'report' },
    soccer_ball = { 'inspect', 'kick_ball', 'organize_match', 'clean_up', 'report' },
    football = { 'inspect', 'throw_football', 'organize_match', 'clean_up', 'report' },
    yard_game = { 'inspect', 'play_yard_game', 'organize_match', 'clean_up', 'report' },
    speaker = { 'inspect', 'play_music', 'dance', 'hang_out', 'report' },
    bbq = { 'inspect', 'grill_food', 'refuel_grill', 'clean_up', 'report' },
    gazebo = { 'inspect', 'set_picnic', 'hang_out', 'clean_up', 'report' },
    picnic_table = { 'inspect', 'set_table', 'set_picnic', 'hang_out', 'clean_up', 'report' },
    blanket = { 'inspect', 'set_picnic', 'relax', 'tan', 'pack_up', 'report' },
    folding_chair = { 'inspect', 'sit_down', 'hang_out', 'pack_up', 'report' },
    patio_table = { 'inspect', 'set_table', 'hang_out', 'eat_snack', 'clean_up', 'report' },
    tent = { 'inspect', 'set_camp', 'rest_camp', 'break_camp', 'clean_up', 'report' },
    camp_chair = { 'inspect', 'sit_down', 'rest_camp', 'hang_out', 'report' },
    lantern = { 'inspect', 'light_lantern', 'pack_up', 'report' },
    logpile = { 'inspect', 'gather_wood', 'clean_up', 'report' },
    hammock = { 'inspect', 'sway_hammock', 'relax', 'pack_up', 'report' },
    firepit = { 'inspect', 'start_bonfire', 'roast_food', 'put_out_fire', 'clean_up', 'report' },
    boardwalk_booth = { 'inspect', 'buy_treat', 'play_ring_toss', 'take_photo', 'clean_up', 'report' },
    snack_vending = { 'inspect', 'buy_treat', 'eat_snack', 'clean_up', 'report' },
    icecream_cart = { 'inspect', 'buy_icecream', 'eat_snack', 'take_photo', 'report' },
    food_cart = { 'inspect', 'buy_food', 'eat_snack', 'take_photo', 'report' },
    arcade_kiosk = { 'inspect', 'play_arcade', 'take_photo', 'report' },
    photo_spot = { 'inspect', 'take_photo', 'hang_out', 'report' },
    pool_lounger = { 'inspect', 'lounge_out', 'cool_off', 'tan', 'report' },
    sprinkler = { 'inspect', 'cool_off', 'splash_around', 'report' },
    kiddie_pool = { 'inspect', 'splash_around', 'cool_off', 'clean_up', 'report' },
    bench = { 'inspect', 'sit_down', 'hang_out', 'take_photo', 'report' },
    dock_spot = { 'inspect', 'sit_down', 'relax', 'take_photo', 'report' },
    playground = { 'inspect', 'enjoy_playground', 'hang_out', 'take_photo', 'report' },
}

Shared.SocialActions = Shared.SocialActions or {
    talk = {
        label = 'Talk',
        icon = 'fa-solid fa-comments',
        description = 'Break the ice and see how they respond.',
        duration = 1600,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT'
    },
    compliment = {
        label = 'Compliment',
        icon = 'fa-solid fa-heart',
        description = 'Offer a compliment and test the waters.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT'
    },
    flirt = {
        label = 'Flirt',
        icon = 'fa-solid fa-face-smile',
        description = 'Push the interaction toward romantic interest.',
        duration = 2200,
        skill = { 'easy', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT'
    },
    ask_out = {
        label = 'Ask Out',
        icon = 'fa-solid fa-calendar-heart',
        description = 'Ask them out and choose a date idea.',
        duration = 2400,
        prompt = 'date',
        skill = { 'easy', 'medium', 'medium' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT'
    },
    ask_area = {
        label = 'Ask About Area',
        icon = 'fa-solid fa-map-pin',
        description = 'Ask what they have seen nearby.',
        duration = 1800,
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT'
    },
    report = {
        label = 'Report Harassment / Suspicion',
        icon = 'fa-solid fa-triangle-exclamation',
        description = 'Send a report if the interaction feels off.',
        duration = 1200,
        prompt = 'report'
    }
}

Shared.SocialActionOrder = Shared.SocialActionOrder or { 'talk', 'compliment', 'flirt', 'ask_out', 'ask_area', 'report' }

local modelHashCache = {}
local familyHashCache = nil

local function lower(v)
    return tostring(v or ''):lower()
end

function Shared.trim(v)
    return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function Shared.clamp(v, minVal, maxVal)
    v = tonumber(v) or 0
    if v < minVal then return minVal end
    if v > maxVal then return maxVal end
    return v
end

function Shared.round(v, precision)
    local p = 10 ^ (precision or 0)
    return math.floor((tonumber(v) or 0) * p + 0.5) / p
end

function Shared.hashModel(model)
    if type(model) == 'number' then return model end
    local key = tostring(model or '')
    if key == '' then return 0 end
    local cached = modelHashCache[key]
    if cached then return cached end
    local hash = joaat and joaat(key) or GetHashKey(key)
    modelHashCache[key] = hash
    return hash
end

function Shared.seedFromString(value)
    local str = tostring(value or '')
    local acc = 0
    for i = 1, #str do
        acc = (acc * 131 + str:byte(i)) % 2147483647
    end
    return acc
end

function Shared.newRng(seed)
    local state = (tonumber(seed) or 1) % 2147483647
    if state <= 0 then state = 1 end

    return function(max)
        state = (state * 48271) % 2147483647
        if max then
            max = tonumber(max) or 1
            if max < 1 then max = 1 end
            return (state % max) + 1
        end
        return state / 2147483647
    end
end

local function buildFamilyHashCache()
    familyHashCache = {}
    for family, data in pairs(CFG.PropFamilies or {}) do
        familyHashCache[family] = {}
        for _, model in ipairs(data.models or {}) do
            familyHashCache[family][Shared.hashModel(model)] = true
        end
    end
end

function Shared.getFamilyHashes(family)
    if not familyHashCache then buildFamilyHashCache() end
    return familyHashCache[family] or {}
end

function Shared.familyHasModel(family, modelHash)
    if not familyHashCache then buildFamilyHashCache() end
    return familyHashCache[family] and familyHashCache[family][tonumber(modelHash) or 0] == true or false
end

function Shared.getModelsForTarget(family)
    local out = {}
    local data = (CFG.PropFamilies or {})[family]
    for _, model in ipairs((data and data.models) or {}) do
        out[#out + 1] = Shared.hashModel(model)
    end
    return out
end

function Shared.makeObjectKey(family, modelHash, coords)
    coords = coords or {}
    local x = Shared.round(coords.x or 0.0, 1)
    local y = Shared.round(coords.y or 0.0, 1)
    local z = Shared.round(coords.z or 0.0, 1)
    return ('%s:%s:%.1f:%.1f:%.1f'):format(tostring(family or 'unknown'), tostring(modelHash or 0), x, y, z)
end

function Shared.sanitizePayloadText(value, maxLen)
    local text = Shared.trim(value)
    maxLen = tonumber(maxLen) or 180
    if #text > maxLen then
        text = text:sub(1, maxLen)
    end
    return text
end

function Shared.weightedPick(entries, rng)
    if type(entries) ~= 'table' or #entries == 0 then return nil end
    local total = 0
    for i = 1, #entries do
        total = total + math.max(1, tonumber(entries[i].weight) or 1)
    end
    if total <= 0 then return entries[1] end
    local roll = math.floor((rng and rng() or math.random()) * total) + 1
    local acc = 0
    for i = 1, #entries do
        acc = acc + math.max(1, tonumber(entries[i].weight) or 1)
        if roll <= acc then
            return entries[i]
        end
    end
    return entries[#entries]
end

function Shared.getPropActionsForFamily(family)
    local out = {}
    for _, actionName in ipairs(Shared.PropFamilyActions[family] or {}) do
        local data = Shared.PropActions[actionName]
        if data then
            out[#out + 1] = {
                name = actionName,
                label = data.label,
                icon = data.icon,
                description = data.description,
                duration = data.duration,
                prompt = data.prompt,
                skill = data.skill,
                risky = data.risky,
                scenario = data.scenario,
            }
        end
    end
    return out
end

function Shared.getSocialActions()
    local out = {}
    for _, actionName in ipairs(Shared.SocialActionOrder or {}) do
        local data = Shared.SocialActions[actionName]
        if data then
            out[#out + 1] = {
                name = actionName,
                label = data.label,
                icon = data.icon,
                description = data.description,
                duration = data.duration,
                prompt = data.prompt,
                skill = data.skill,
                scenario = data.scenario,
            }
        end
    end
    return out
end
