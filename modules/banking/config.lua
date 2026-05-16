Config = Config or {}
Config.Banking = Config.Banking or {}
local Config = Config.Banking
Config.Enabled = Config.Enabled ~= false

Config.Brand = Config.Brand or {
  appName = 'State Bank',
  shortName = 'Bank',
  supportText = 'Premium digital banking'
}

Config.ATMModels = Config.ATMModels or { `prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm` }
Config.UseKey = Config.UseKey or 38
Config.PromptDist = Config.PromptDist or 3.0
Config.BlipDist = Config.BlipDist or 50.0
Config.Blip = Config.Blip or { sprite = 108, color = 2, scale = 0.8, text = "Bank ATM" }

Config.GlitchCircuitParams = Config.GlitchCircuitParams or {2, 1, 1000, 3000, 3000, 0, 10000, 3000, 30000}
Config.SkillCheckSeq = Config.SkillCheckSeq or {'easy', { areaSize = 80, speedMultiplier = 0.8 }}
Config.SkillCheckInputs = Config.SkillCheckInputs or {'e'}

Config.atmRobberyCooldown = Config.atmRobberyCooldown or 600
Config.atmMinReward = Config.atmMinReward or 500
Config.atmMaxReward = Config.atmMaxReward or 3000
Config.atmDispatchOnFail = Config.atmDispatchOnFail ~= false
Config.atmDispatchBlipDuration = Config.atmDispatchBlipDuration or 30
Config.atmDispatchJobs = Config.atmDispatchJobs or {
  police = true,
  sheriff = true,
  leo = true,
  state = true,
  trooper = true,
  highway = true,
  bcso = true,
  sasp = true,
  lspd = true,
  lsso = true,
  pbso = true,
  sahp = true
}
Config.atmDispatchDepartments = Config.atmDispatchDepartments or {
  police = true,
  sheriff = true,
  leo = true,
  state = true,
  trooper = true,
  highway = true,
  bcso = true,
  sasp = true,
  lspd = true,
  lsso = true,
  pbso = true,
  sahp = true
}

Config.Transfer = Config.Transfer or {
  allowManualCharId = true,
  defaultRecipientDestination = 'checking',
  maxTransfer = 250000,
  maxOnlineRecipients = 24
}

Config.InvestmentPlans = Config.InvestmentPlans or {
  secure = {
    code = 'secure',
    label = 'Secure Bond',
    description = 'Low-risk state backed notes with smaller returns.',
    risk = 'Low',
    min = 2500,
    max = 100000,
    durationHours = 8,
    returnRate = 4.0,
    color = '#65d9a5'
  },
  balanced = {
    code = 'balanced',
    label = 'Balanced Fund',
    description = 'Diversified medium-risk portfolio with stable growth.',
    risk = 'Medium',
    min = 5000,
    max = 250000,
    durationHours = 12,
    returnRate = 8.5,
    color = '#52c7ff'
  },
  aggressive = {
    code = 'aggressive',
    label = 'Aggressive Growth',
    description = 'High-risk play with the strongest upside once matured.',
    risk = 'High',
    min = 10000,
    max = 500000,
    durationHours = 18,
    returnRate = 15.0,
    color = '#ff8c6b'
  }
}
