Config = Config or {}
Config.IDCard = Config.IDCard or {}
local Config = Config.IDCard
Config.Enabled = Config.Enabled ~= false

Config.Debug = false
Config.DriverLicenseCacheMs = 10000

Config.DriverLicenseAllowedStatuses = { "VALID", "ACTIVE", "APPROVED", "PASSED" }

Config.DMVLocations = {
    {
        coords = vector3(239.290, -1381.063, 33.742),
        blip = {
            enabled = true,
            sprite  = 498,
            color   = 5,
            scale   = 0.9,
            text    = "DMV - City"
        }
    }
}

Config.DMVBlip = {
    enabled = true,
    sprite  = 498,
    color   = 3,
    scale   = 0.9,
    text    = "DMV"
}

Config.Marker = {
    type            = 1,
    size            = { x = 1.2, y = 1.2, z = 0.5 },
    color           = { r = 255, g = 255, b = 0, a = 120},
    drawDistance    = 15.0,
    interactDistance= 2.0,
    zOffset         = 1.0,
    bobUpAndDown    = false,
    faceCamera      = true,
    rotate          = false
}

Config.MarkerText = {
    text    = "Press [E] to get ID",
    font    = 4,
    scale   = 0.35,
    colorR  = 255,
    colorG  = 255,
    colorB  = 255,
    colorA  = 215,
    zOffset = 1.0
}

Config.DisplayTime = 8000

Config.ShowRadius = 5.0

Config.RequestDistance = 3.0

Config.ExpiryDays = 365 * 5

Config.DefaultAddress       = "186 ZancUDO Avenue, Sandy Shores, Blaine County, SA 47229"
Config.DefaultClass         = "C"
Config.DefaultEndorsements  = "NONE"
Config.DefaultRestrictions  = "NONE"
Config.DefaultSex           = "M"
Config.DefaultHeight        = "6'-01\""
Config.DefaultWeight        = "206 lb"
Config.DefaultHair          = "BRN"
Config.DefaultEyes          = "BRN"
Config.DefaultDD            = "01/03/1969 99093/06/08/69"
Config.DefaultDOB           = "08/06/1969"
