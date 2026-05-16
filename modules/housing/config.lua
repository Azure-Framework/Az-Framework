Config = Config or {}
Config.Housing = Config.Housing or {}
local Config = Config.Housing
Config.Enabled = Config.Enabled ~= false

Config.Debug = (Config.Debug == true)
Config.UseOxLib = (Config.UseOxLib ~= false)
Config.UseOxTarget = (Config.UseOxTarget ~= false)
Config.UseDatabase = (Config.UseDatabase ~= false)

Config.IdentifierPriority = { 'license', 'discord', 'fivem', 'steam' }

Config.CharacterScopedOwnership = (Config.CharacterScopedOwnership ~= false)

Config.Commands = {
  Portal = 'housing',
  Placement = 'housingedit',
}

Config.Interact = {
  DoorDistance = 2.0,
  KnockDistance = 2.5,
  GarageDistance = 4.0,
  MarkerDistance = 25.0,
}

Config.Buckets = {
  Base = 500000,
  UsePerHouse = true,
}

Config.Police = {
  Jobs = { 'police', 'sheriff', 'state', 'lspd', 'bcso' },
  BreachCooldownSec = 30,
  BreachUnlockSeconds = 120,
  BreachBlipSeconds = 180,
  RequireItem = false,
  BreachItem = 'ram',
}

Config.Blips = {
  Enabled = true,
  Sprite = 40,
  Color = 2,
  Scale = 0.65,
  ShortRange = true,
  ShowOnlyIfDiscovered = false,
}

Config.Defaults = {
  SalePrice = 75000,
  RentPerWeek = 2500,
  Deposit = 2500,
}

Config.Money = {

  Mode = 'azfw',

  Account = 'cash',
}

Config.Perms = {
  AdminRoleIds = { },
  AgentRoleIds = { "1437877826706604115"},
}

Config.Mailbox = {
  Enabled = true,
  BaseCapacity = 15,
  CapacityPerLevel = 10,
}

Config.Upgrades = {
  Levels = {

    mailbox = {
      { price = 0,   capacityBonus = 0 },
      { price = 2500, capacityBonus = 10 },
      { price = 5000, capacityBonus = 20 },
      { price = 9000, capacityBonus = 35 },
    },
    decor = {
      { price = 0,    furnitureLimit = 25 },
      { price = 7500, furnitureLimit = 50 },
      { price = 15000, furnitureLimit = 85 },
      { price = 25000, furnitureLimit = 130 },
    },
    storage = {
      { price = 0,    stashSlots = 20, stashWeight = 20000 },
      { price = 12500, stashSlots = 40, stashWeight = 40000 },
      { price = 25000, stashSlots = 60, stashWeight = 70000 },
    },
  }
}

Config.Furniture = {
  Enabled = true,

  Catalog = {
    { label = 'Sofa (Modern)', model = 'v_res_mp_sofa' },
    { label = 'Coffee Table', model = 'v_res_fh_coftableb' },
    { label = 'TV Stand', model = 'v_res_tre_tvstand' },
    { label = 'Flat TV', model = 'prop_tv_flat_01' },
    { label = 'Bed (Simple)', model = 'v_res_msonbed' },
    { label = 'Lamp', model = 'v_res_d_lampa' },
    { label = 'Plant', model = 'prop_plant_int_02a' },
    { label = 'Rug', model = 'v_res_m_rugrug' },
  },
  AllowCustomModelForAdmins = true,
}

Config.Ace = {
  Admin = 'azhousing.admin',
}

Config.Agent = {
  Jobs = { 'realestate', 'realtor' },
}

Config.Interiors = {
  apt_basic = {
    label = 'Basic Apartment',
    entry = vector4(266.0388, -1007.5456, -101.0085, 355.15),
    exit  = vector4(266.0388, -1007.5456, -101.0085, 175.15),
    stash = vector3(265.90, -999.50, -99.00),
    wardrobe = vector3(259.70, -1004.00, -99.00),
  },

  apt_mid = {
    label = 'Mid Apartment',
    entry = vector4(346.5221, -1012.7787, -99.1962, 0.0),
    exit  = vector4(346.5221, -1012.7787, -99.1962, 180.0),
    stash = vector3(350.80, -993.70, -99.20),
    wardrobe = vector3(350.6, -993.76, -99.2),
  },

  apt_highend = {
    label = 'High-End Apartment',
    entry = vector4(-785.17, 323.61, 212, 276.93),
    exit  = vector4(-785.17, 323.61, 212, 276.93),
    stash = vector3(-765.12, 326.44, 211.4),
    wardrobe = vector3(-793.41, 326.29, 210.8),
  }
}

Config.Garage = {
  SpawnClearance = 3.0,
  DefaultRadius = 2.2,
}

Config.Markers = {
  Enabled = true,
  DoorType = 2,
  GarageType = 36,
  Scale = vec3(0.25, 0.25, 0.25),
}
