AZH = AZH or {}
local Config = (Config and Config.Housing) or {}
if Config.Enabled == false then return end
AZH.ResName = GetCurrentResourceName()
AZH.Version = '1.0.0'
