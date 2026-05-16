Config = Config or {}
Config.Debug = Config.Debug == true
Config.AcePermission = tostring(Config.AcePermission or Config.AdminAcePermission or "adminmenu.use")
Config.ReportsFile = tostring(Config.ReportsFile or "admin/reports.json")
Config.ChunkMaxSize = tonumber(Config.ChunkMaxSize) or tonumber(GetConvar('ADMIN_REPORT_CHUNK_MAX', '8000')) or 8000
Config.ChunkMaxParts = tonumber(Config.ChunkMaxParts) or tonumber(GetConvar('ADMIN_REPORT_CHUNK_PARTS', '600')) or 600
Config.DepartmentsTable = tostring(Config.DepartmentsTable or GetConvar('ADMIN_DEPARTMENTS_TABLE', 'econ_departments'))
