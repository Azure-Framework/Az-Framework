Config = Config or {}
Config.Immersion = Config.Immersion or {}
local Config = Config.Immersion

Config.Enabled = Config.Enabled ~= false
Config.Debug = Config.Debug == true
Config.UseOxTarget = Config.UseOxTarget ~= false
Config.EnablePropInteractions = Config.EnablePropInteractions ~= false
Config.EnableNPCSocial = Config.EnableNPCSocial ~= false
Config.ManualReports = Config.ManualReports ~= false

Config.TargetDistance = tonumber(Config.TargetDistance) or 1.9
Config.NPCDistance = tonumber(Config.NPCDistance) or 2.2
Config.ActionDistance = tonumber(Config.ActionDistance) or 3.5
Config.SaveIntervalSeconds = tonumber(Config.SaveIntervalSeconds) or 45
Config.ActionCooldownMs = tonumber(Config.ActionCooldownMs) or 3500
Config.SearchCooldownSeconds = tonumber(Config.SearchCooldownSeconds) or 75
Config.SocialCooldownSeconds = tonumber(Config.SocialCooldownSeconds) or 25
Config.MaxNoteLength = tonumber(Config.MaxNoteLength) or 180
Config.MaxReasonLength = tonumber(Config.MaxReasonLength) or 240

Config.Summer = Config.Summer or {}
Config.Summer.Enabled = Config.Summer.Enabled ~= false
Config.Summer.Beach = Config.Summer.Beach ~= false
Config.Summer.Water = Config.Summer.Water ~= false
Config.Summer.Games = Config.Summer.Games ~= false
Config.Summer.Picnic = Config.Summer.Picnic ~= false
Config.Summer.Camp = Config.Summer.Camp ~= false
Config.Summer.Boardwalk = Config.Summer.Boardwalk ~= false
Config.Summer.Pool = Config.Summer.Pool ~= false
Config.Summer.Vendors = Config.Summer.Vendors ~= false
Config.Summer.Backyard = Config.Summer.Backyard ~= false
Config.Summer.Seating = Config.Summer.Seating ~= false
Config.Summer.Playground = Config.Summer.Playground ~= false
Config.Summer.Cleanup = Config.Summer.Cleanup ~= false
Config.Summer.RelationshipFlavor = Config.Summer.RelationshipFlavor ~= false
Config.Summer.RentalStockDefault = tonumber(Config.Summer.RentalStockDefault) or 3
Config.Summer.CoolerStockDefault = tonumber(Config.Summer.CoolerStockDefault) or 4
Config.Summer.GrillFuelDefault = tonumber(Config.Summer.GrillFuelDefault) or 3
Config.Summer.BonfireFuelDefault = tonumber(Config.Summer.BonfireFuelDefault) or 2
Config.Summer.FloatStockDefault = tonumber(Config.Summer.FloatStockDefault) or 3
Config.Summer.SnackStockDefault = tonumber(Config.Summer.SnackStockDefault) or 5
Config.Summer.FoodStockDefault = tonumber(Config.Summer.FoodStockDefault) or 5

Config.AutoReport = Config.AutoReport or {}
Config.AutoReport.Enabled = Config.AutoReport.Enabled ~= false
Config.AutoReport.SuspicionThreshold = tonumber(Config.AutoReport.SuspicionThreshold) or 36
Config.AutoReport.HarassmentThreshold = tonumber(Config.AutoReport.HarassmentThreshold) or 55
Config.AutoReport.WindowSeconds = tonumber(Config.AutoReport.WindowSeconds) or 600

Config.Persistence = Config.Persistence or {}
Config.Persistence.PropsFile = Config.Persistence.PropsFile or 'modules/immersion/data/props_state.json'
Config.Persistence.RelationshipsFile = Config.Persistence.RelationshipsFile or 'modules/immersion/data/relationships.json'
Config.Persistence.ComplaintsFile = Config.Persistence.ComplaintsFile or 'modules/immersion/data/complaints.json'

Config.LawJobs = Config.LawJobs or {
    police = true,
    bcso = true,
    state = true,
    sast = true,
    park = true,
    ranger = true,
}

Config.PropFamilies = Config.PropFamilies or {
    mailbox = {
        label = 'Mailbox',
        icon = 'fa-solid fa-envelope',
        targetDistance = 1.7,
        models = {
            'prop_mailbox_01a',
            'prop_mailbox_01b',
            'prop_postbox_01a',
            'prop_postbox_ss_1',
        }
    },
    trash = {
        label = 'Trash / Dumpster',
        icon = 'fa-solid fa-trash',
        targetDistance = 1.85,
        models = {
            'prop_bin_01a',
            'prop_bin_05a',
            'prop_bin_07b',
            'prop_bin_08a',
            'prop_dumpster_01a',
            'prop_dumpster_02a',
            'prop_dumpster_3a',
            'prop_dumpster_4a',
            'prop_cs_dumpster_01a',
        }
    },
    cup = {
        label = 'Cup / Bottle',
        icon = 'fa-solid fa-glass-water',
        targetDistance = 1.4,
        models = {
            'prop_cs_paper_cup',
            'prop_plastic_cup_02',
            'prop_ld_can_01',
            'prop_energy_drink',
            'prop_ecola_can',
            'prop_orang_can_01',
            'ng_proc_sodacan_01b',
        }
    },
    bike_rack = {
        label = 'Bike Rack',
        icon = 'fa-solid fa-bicycle',
        targetDistance = 1.85,
        models = {
            'prop_bikerack_1a',
            'prop_bikerack_2',
        }
    }
}

local function addSummerFamily(name, data)
    if Config.PropFamilies[name] ~= nil then return end
    Config.PropFamilies[name] = data
end

if Config.Summer.Enabled ~= false then
    if Config.Summer.Beach ~= false then
        addSummerFamily('umbrella', {
            label = 'Beach Umbrella',
            icon = 'fa-solid fa-umbrella-beach',
            targetDistance = 1.9,
            models = { 'prop_parasol_01', 'prop_parasol_02', 'prop_parasol_03', 'p_amb_brolly_01', 'p_amb_brolly_01_s' }
        })
        addSummerFamily('towel', {
            label = 'Beach Towel',
            icon = 'fa-solid fa-person-sun',
            targetDistance = 1.6,
            models = { 'prop_beach_towel_01', 'prop_beach_towel_02', 'prop_beach_towel_03', 'prop_beach_towel_04', 'prop_cs_beachtowel_01' }
        })
        addSummerFamily('cooler', {
            label = 'Cooler',
            icon = 'fa-solid fa-box-open',
            targetDistance = 1.8,
            models = { 'prop_coolbox_01', 'prop_coolbox_01_l1', 'prop_ice_box_01', 'prop_cs_box_clothes' }
        })
        addSummerFamily('beach_bag', {
            label = 'Beach Bag',
            icon = 'fa-solid fa-bag-shopping',
            targetDistance = 1.55,
            models = { 'prop_beach_bag_01a', 'prop_beach_bag_01b', 'prop_cs_beach_bag_01', 'prop_cs_shopping_bags' }
        })
        addSummerFamily('beach_chair', {
            label = 'Beach Chair',
            icon = 'fa-solid fa-chair',
            targetDistance = 1.85,
            models = { 'prop_skid_chair_01', 'prop_skid_chair_02', 'prop_gc_chair02', 'prop_chair_01a', 'prop_chair_04a' }
        })
        addSummerFamily('lounger', {
            label = 'Sun Lounger',
            icon = 'fa-solid fa-couch',
            targetDistance = 2.0,
            models = { 'prop_ld_lounger', 'prop_yacht_lounger', 'prop_yacht_lounger_01', 'prop_yacht_lounger_02' }
        })
    end

    if Config.Summer.Water ~= false then
        addSummerFamily('surfboard', {
            label = 'Surfboard',
            icon = 'fa-solid fa-water',
            targetDistance = 1.85,
            models = { 'prop_surf_board_01', 'prop_surf_board_02', 'prop_surf_board_ldn_03', 'prop_surf_board_ldn_04', 'prop_beach_lg_surf' }
        })
        addSummerFamily('floatie', {
            label = 'Pool Float / Ring',
            icon = 'fa-solid fa-life-ring',
            targetDistance = 1.8,
            models = { 'prop_air_lilo_01', 'prop_air_lilo_02', 'prop_pool_ring_01', 'prop_beach_lg_float' }
        })
        addSummerFamily('lifeguard_post', {
            label = 'Lifeguard Post',
            icon = 'fa-solid fa-binoculars',
            targetDistance = 2.2,
            models = { 'prop_beach_lg_float', 'prop_beach_lg_stool', 'prop_beach_lg_surf' }
        })
        addSummerFamily('shower', {
            label = 'Beach / Pool Shower',
            icon = 'fa-solid fa-shower',
            targetDistance = 1.8,
            models = { 'prop_beach_shower', 'prop_shower_rack_01', 'prop_poolside_shower' }
        })
        addSummerFamily('changing_booth', {
            label = 'Changing Booth',
            icon = 'fa-solid fa-shirt',
            targetDistance = 1.9,
            models = { 'prop_beach_cabine_01', 'prop_change_room_01', 'prop_change_room_02' }
        })
    end

    if Config.Summer.Games ~= false then
        addSummerFamily('volleyball', {
            label = 'Beach Volleyball',
            icon = 'fa-solid fa-volleyball',
            targetDistance = 1.8,
            models = { 'prop_beach_volball01', 'prop_beach_volball02' }
        })
        addSummerFamily('frisbee', {
            label = 'Frisbee',
            icon = 'fa-solid fa-compact-disc',
            targetDistance = 1.5,
            models = { 'prop_toy_frisbee', 'prop_frisbee_01' }
        })
        addSummerFamily('soccer_ball', {
            label = 'Soccer Ball',
            icon = 'fa-solid fa-futbol',
            targetDistance = 1.5,
            models = { 'stt_prop_stunt_soccer_ball', 'prop_foot_ball', 'p_ld_soc_ball_01' }
        })
        addSummerFamily('football', {
            label = 'Football',
            icon = 'fa-solid fa-football',
            targetDistance = 1.5,
            models = { 'prop_football', 'prop_football_01' }
        })
        addSummerFamily('yard_game', {
            label = 'Yard Game',
            icon = 'fa-solid fa-gamepad',
            targetDistance = 1.8,
            models = { 'prop_cornhole_01', 'prop_badminton_net_01', 'prop_boogieboard_01' }
        })
        addSummerFamily('speaker', {
            label = 'Portable Speaker',
            icon = 'fa-solid fa-music',
            targetDistance = 1.7,
            models = { 'prop_boombox_01', 'prop_portable_hifi_01', 'prop_speaker_05', 'prop_speaker_06' }
        })
    end

    if Config.Summer.Picnic ~= false then
        addSummerFamily('bbq', {
            label = 'BBQ Grill',
            icon = 'fa-solid fa-fire-burner',
            targetDistance = 1.9,
            models = { 'prop_bbq_1', 'prop_bbq_2', 'prop_bbq_3', 'prop_bbq_4', 'prop_bbq_5' }
        })
        addSummerFamily('gazebo', {
            label = 'Picnic Gazebo',
            icon = 'fa-solid fa-campground',
            targetDistance = 2.4,
            models = { 'prop_gazebo_01', 'prop_gazebo_02' }
        })
        addSummerFamily('picnic_table', {
            label = 'Picnic Table',
            icon = 'fa-solid fa-table-picnic',
            targetDistance = 2.0,
            models = { 'prop_table_01', 'prop_table_02', 'prop_table_03', 'prop_table_04', 'prop_rub_table_01' }
        })
        addSummerFamily('blanket', {
            label = 'Picnic Blanket',
            icon = 'fa-solid fa-rug',
            targetDistance = 1.6,
            models = { 'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03', 'prop_beach_towel_04' }
        })
        addSummerFamily('folding_chair', {
            label = 'Folding Chair',
            icon = 'fa-solid fa-chair',
            targetDistance = 1.8,
            models = { 'prop_skid_chair_03', 'prop_skid_chair_04', 'prop_chair_01b', 'prop_ld_farm_chair01' }
        })
        addSummerFamily('patio_table', {
            label = 'Patio Table',
            icon = 'fa-solid fa-utensils',
            targetDistance = 1.95,
            models = { 'v_ret_ml_tablec', 'prop_table_03b', 'prop_table_03_chr', 'prop_table_tennis' }
        })
    end

    if Config.Summer.Camp ~= false then
        addSummerFamily('tent', {
            label = 'Camp Tent',
            icon = 'fa-solid fa-tents',
            targetDistance = 2.1,
            models = { 'prop_skid_tent_01', 'prop_skid_tent_03', 'prop_military_pickup_01' }
        })
        addSummerFamily('firepit', {
            label = 'Bonfire / Firepit',
            icon = 'fa-solid fa-fire',
            targetDistance = 2.0,
            models = { 'prop_beach_fire', 'prop_logpile_06b', 'prop_firepit_01' }
        })
        addSummerFamily('camp_chair', {
            label = 'Camp Chair',
            icon = 'fa-solid fa-campground',
            targetDistance = 1.8,
            models = { 'prop_skid_chair_01', 'prop_skid_chair_02', 'prop_gc_chair02' }
        })
        addSummerFamily('lantern', {
            label = 'Lantern / Camp Light',
            icon = 'fa-solid fa-lightbulb',
            targetDistance = 1.55,
            models = { 'prop_oldlight_01b', 'prop_worklight_03b', 'prop_worklight_04a' }
        })
        addSummerFamily('logpile', {
            label = 'Firewood / Log Pile',
            icon = 'fa-solid fa-tree',
            targetDistance = 1.9,
            models = { 'prop_logpile_06b', 'prop_logpile_07b', 'prop_rub_cabinet02' }
        })
        addSummerFamily('hammock', {
            label = 'Hammock',
            icon = 'fa-solid fa-bed',
            targetDistance = 2.0,
            models = { 'prop_hammock_01', 'prop_hammock_02', 'prop_hammock_03' }
        })
    end

    if Config.Summer.Boardwalk ~= false or Config.Summer.Vendors ~= false then
        addSummerFamily('boardwalk_booth', {
            label = 'Boardwalk Booth',
            icon = 'fa-solid fa-ticket',
            targetDistance = 2.0,
            models = { 'prop_kiosk_01', 'prop_vend_snak_01', 'prop_vend_soda_01', 'prop_vend_water_01' }
        })
        addSummerFamily('snack_vending', {
            label = 'Snack / Drink Stand',
            icon = 'fa-solid fa-cookie-bite',
            targetDistance = 1.8,
            models = { 'prop_vend_snak_01', 'prop_vend_snak_01_tu', 'prop_vend_soda_02', 'prop_vend_water_01' }
        })
        addSummerFamily('icecream_cart', {
            label = 'Ice Cream Stand',
            icon = 'fa-solid fa-ice-cream',
            targetDistance = 1.9,
            models = { 'prop_ice_box_01', 'prop_vend_fridge01', 'prop_vend_coffe_01' }
        })
        addSummerFamily('food_cart', {
            label = 'Food Cart',
            icon = 'fa-solid fa-hotdog',
            targetDistance = 2.0,
            models = { 'prop_hotdogstand_01', 'prop_food_bs_cart_01', 'prop_food_cb_cart_01', 'prop_food_van_01' }
        })
        addSummerFamily('arcade_kiosk', {
            label = 'Arcade / Photo Kiosk',
            icon = 'fa-solid fa-camera-retro',
            targetDistance = 1.8,
            models = { 'prop_arcade_01', 'prop_arcade_02', 'prop_kiosk_01' }
        })
        addSummerFamily('photo_spot', {
            label = 'Photo Spot',
            icon = 'fa-solid fa-image',
            targetDistance = 2.0,
            models = { 'prop_beachflag_01', 'prop_beachflag_02', 'prop_beachflag_le', 'prop_beachflag_ca' }
        })
    end

    if Config.Summer.Pool ~= false or Config.Summer.Backyard ~= false then
        addSummerFamily('pool_lounger', {
            label = 'Poolside Lounger',
            icon = 'fa-solid fa-couch',
            targetDistance = 2.0,
            models = { 'prop_ld_lounger', 'prop_yacht_lounger', 'prop_yacht_lounger_01' }
        })
        addSummerFamily('sprinkler', {
            label = 'Sprinkler / Water Toy',
            icon = 'fa-solid fa-droplet',
            targetDistance = 1.8,
            models = { 'prop_golf_sprinkler_01', 'prop_sprink_golf_01', 'prop_watercooler' }
        })
        addSummerFamily('kiddie_pool', {
            label = 'Kiddie Pool / Backyard Splash',
            icon = 'fa-solid fa-water-ladder',
            targetDistance = 1.9,
            models = { 'prop_pool_ring_01', 'prop_air_lilo_01', 'prop_air_lilo_02' }
        })
    end

    if Config.Summer.Seating ~= false then
        addSummerFamily('bench', {
            label = 'Park / Boardwalk Bench',
            icon = 'fa-solid fa-person-seat',
            targetDistance = 1.95,
            models = { 'prop_bench_01a', 'prop_bench_01b', 'prop_bench_01c', 'prop_bench_02', 'prop_bench_03', 'prop_bench_04', 'prop_bench_05' }
        })
        addSummerFamily('dock_spot', {
            label = 'Dock / Waterside Spot',
            icon = 'fa-solid fa-water',
            targetDistance = 2.0,
            models = { 'prop_dock_01', 'prop_dock_02', 'prop_dock_float_01', 'prop_dock_float_02' }
        })
    end

    if Config.Summer.Playground ~= false then
        addSummerFamily('playground', {
            label = 'Playground',
            icon = 'fa-solid fa-child-reaching',
            targetDistance = 2.0,
            models = { 'prop_playground_01', 'prop_playground_02', 'prop_swingset_01', 'prop_slide_01' }
        })
    end
end
