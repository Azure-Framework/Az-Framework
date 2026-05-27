Config = Config or {}
Config.Chat = Config.Chat or {}
local Config = Config.Chat
Config.Enabled = Config.Enabled ~= false

Config.OpenKey = 't'
Config.UseOpenControlFallback = true
Config.OpenControl = 245
Config.VisibilityCycleKey = 'SEMICOLON'
Config.CommandPrefix = '/'
Config.MaxMessages = 150
Config.FadeAfterMs = 18000
Config.UseProximity = false
Config.ProximityRange = 24.0
Config.ShowPlayerIdInAdminDM = true
Config.WarnIfStockChatRunning = true
Config.StopStockChat = true
Config.DisableNativeTextChat = true
Config.DefaultModeLabel = 'CHAT'
Config.DefaultVisibilityMode = 'always'
Config.VisibilityModeKvp = 'azchat:visibilityMode'
Config.InputHistoryMax = 50

Config.Style = {
    chatWidth = '30vw',
    maxWidth = '640px',
    inputWidth = '34vw',
    inputMaxWidth = '700px',
    top = '1.25vh',
    left = '1.25vw',
    stackMaxHeight = '28vh',
    roleIconSize = '18px',
    messageGap = 8,
    fontFamily = "Inter, Segoe UI Emoji, Apple Color Emoji, Noto Color Emoji, Arial, sans-serif",
    shadow = 'none',
    accent = '#3970e6',
    text = '#ffffff',
    textMuted = 'rgba(255,255,255,0.72)',
    bubble = 'rgba(10,10,12,0.18)',
    bubbleBorder = 'rgba(255,255,255,0.08)',
    inputBg = 'rgba(9,9,11,0.42)',
    inputBorder = 'rgba(255,255,255,0.10)',
    success = '#59d98e',
    warning = '#74b9ff',
    danger = '#3970e6',
    info = '#5bc0ff'
}

Config.ModeIcons = {
    CHAT = 'assets/icons/chat.svg',
    LOCAL = 'assets/icons/local.svg',
    SYSTEM = 'assets/icons/system.svg',
    SUCCESS = 'assets/icons/system.svg',
    MUTED = 'assets/icons/system.svg',
    DENIED = 'assets/icons/system.svg',
    USAGE = 'assets/icons/system.svg',
    DM = 'assets/icons/dm.svg',
    ADMIN = 'assets/icons/admin.svg',
    ANNOUNCEMENT = 'assets/icons/announce.svg'
}

Config.JobRoleIcons = {
    police = 'assets/icons/jobs/police.svg',
    leo = 'assets/icons/jobs/police.svg',
    sheriff = 'assets/icons/jobs/police.svg',
    state = 'assets/icons/jobs/police.svg',
    trooper = 'assets/icons/jobs/police.svg',
    fire = 'assets/icons/jobs/fire.svg',
    ems = 'assets/icons/jobs/ems.svg',
    ambulance = 'assets/icons/jobs/ems.svg',
    medic = 'assets/icons/jobs/ems.svg',
    doctor = 'assets/icons/jobs/ems.svg',
    civ = 'assets/icons/jobs/civ.svg',
    civilian = 'assets/icons/jobs/civ.svg',
    unemployed = 'assets/icons/jobs/civ.svg',
    default = 'assets/icons/jobs/civ.svg'
}

Config.JobRoleLabels = {
    police = 'POLICE',
    leo = 'LEO',
    sheriff = 'SHERIFF',
    state = 'STATE',
    trooper = 'TROOPER',
    fire = 'FIRE',
    ems = 'EMS',
    ambulance = 'EMS',
    medic = 'MEDIC',
    doctor = 'DOCTOR',
    civ = 'CIV',
    civilian = 'CIV',
    unemployed = 'CIV'
}

Config.RP = {
    MeRange = 20.0,
    DoRange = 20.0,
    OocRange = 24.0,
    OocGlobal = false,
    TryRange = 20.0,
    RollRange = 20.0,
    AllowBCommand = true,
    AllowLoocCommand = true,
    Colors = {
        me = { 230, 57, 70 },
        do_ = { 116, 185, 255 },
        ooc = { 255, 255, 255 },
        trySuccess = { 89, 217, 142 },
        tryFail = { 255, 103, 103 },
        roll = { 255, 180, 84 }
    }
}

Config.EmojiAliases = {
    [':smile:'] = '😄',
    [':grin:'] = '😁',
    [':joy:'] = '😂',
    [':sob:'] = '😭',
    [':heart:'] = '❤️',
    [':thumbsup:'] = '👍',
    [':thumbsdown:'] = '👎',
    [':fire:'] = '🔥',
    [':100:'] = '💯',
    [':eyes:'] = '👀',
    [':wave:'] = '👋',
    [':ok:'] = '👌',
    [':clap:'] = '👏',
    [':pray:'] = '🙏',
    [':skull:'] = '💀',
    [':laugh:'] = '🤣',
    [':thinking:'] = '🤔',
    [':salute:'] = '🫡',
    [':rocket:'] = '🚀',
    [':car:'] = '🚗',
    [':police:'] = '🚓',
    [':ambulance:'] = '🚑',
    [':house:'] = '🏠',
    [':tools:'] = '🛠️'
}

Config.EmojiPicker = {
    '😀','😁','😂','🤣','😊','😍','😘','😎','🤔','🫡','😭','😡',
    '👍','👎','👏','🙌','🙏','👀','💀','❤️','🔥','💯','✨','⚡',
    '🚗','🚓','🚑','🚒','🏠','🔧','🛠️','📦','📍','💬','📢','✅',
    '❌','⚠️','⭐','🎉','🧠','💼','💸','🕒','📱','💻','🎮','🌙'
}

Config.BuiltInSuggestions = {
    {
        name = '/mute',
        help = 'Mute a player from global chat.',
        params = {
            { name = 'id', help = 'Player server ID' },
            { name = 'minutes', help = 'How long to mute them for. Use 0 for permanent.' },
            { name = 'reason', help = 'Optional mute reason' }
        }
    },
    {
        name = '/unmute',
        help = 'Remove a player mute.',
        params = {
            { name = 'id', help = 'Player server ID' }
        }
    },
    {
        name = '/purge',
        help = 'Clear chat for everyone or trim it to the last X messages.',
        params = {
            { name = 'amount', help = 'Optional number of latest messages to keep. Default 0 clears all.' }
        }
    },
    {
        name = '/dm',
        help = 'Send a staff direct message to a player.',
        params = {
            { name = 'id', help = 'Player server ID' },
            { name = 'message', help = 'Message to send' }
        }
    },
    {
        name = '/announce',
        help = 'Broadcast a highlighted admin announcement.',
        params = {
            { name = 'message', help = 'Announcement text' }
        }
    },
    {
        name = '/me',
        help = 'Send a nearby action emote in character.',
        params = {
            { name = 'action', help = 'What your character does' }
        }
    },
    {
        name = '/do',
        help = 'Describe the nearby scene or outcome.',
        params = {
            { name = 'description', help = 'What is seen, heard, or true in the scene' }
        }
    },
    {
        name = '/ooc',
        help = 'Out of character chat. Local by default in this resource.',
        params = {
            { name = 'message', help = 'What you want to say out of character' }
        }
    },
    {
        name = '/try',
        help = 'Attempt an action with a random success or fail result.',
        params = {
            { name = 'action', help = 'What your character is trying to do' }
        }
    },
    {
        name = '/roll',
        help = 'Roll a number for RP interactions. Defaults to 100 max.',
        params = {
            { name = 'max', help = 'Optional max value such as 20 or 100' },
            { name = 'reason', help = 'Optional context for the roll' }
        }
    },
    {
        name = '/chatstate',
        help = 'Set passive chat visibility state.',
        params = {
            { name = 'active|disabled|always', help = 'Only when active, hidden, or always visible' }
        }
    },
    {
        name = '/chatstatecycle',
        help = 'Cycle chat visibility: active, disabled, always.',
        params = {}
    },
    {
        name = '/911',
        help = 'Open the emergency call dialog and choose Police, EMS, or Fire.',
        params = {}
    }
}
