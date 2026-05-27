Config = Config or {}
Config.DailyRewards = Config.DailyRewards or {}
local Config = Config.DailyRewards
Config.Enabled = Config.Enabled ~= false

Config.ResourceName = 'Az-Framework'

Config.DefaultRewards = {}
for m=1,12 do
  Config.DefaultRewards[m] = {}
  for d=1,31 do
    Config.DefaultRewards[m][d] = { money = math.random(50,500), keys = 0 }
  end
end

Config.DefaultRewards[1][1] = { money = 200, keys = 1 }
Config.DefaultRewards[1][7] = { money = 750, weapon = 'WEAPON_PUMPSHOTGUN', ammo = 10, keys = 2 }
Config.DefaultRewards[1][15] = { money = 1500, keys = 3 }
Config.DefaultRewards[1][25] = { money = 1000, weapon = 'WEAPON_ASSAULTRIFLE', ammo = 30, keys = 5 }

Config.WheelPrizes = {
  { type = 'money', amount = 500 },
  { type = 'money', amount = 1000 },
  { type = 'money', amount = 250 },
  { type = 'weapon', weapon = 'WEAPON_PISTOL', ammo = 12 },
  { type = 'keys', amount = 2 },
  { type = 'money', amount = 2000 },
  { type = 'weapon', weapon = 'WEAPON_SMG', ammo = 30 },
  { type = 'keys', amount = 5 }
}

Config.DefaultClaimKeys = 0

Config.AutoCreateTables = true

Config.CurrencyName = '$'
