local core = _G.AzClientCoreExports or {}
local bridge = _G.AzBridgeClientExports or {}

local function registerExport(name, fn)
  if type(fn) == 'function' then
    exports(name, fn)
  end
end

registerExport('IsGameplayReady', core.IsGameplayReady)
registerExport('hudNotify', core.hudNotify)
registerExport('refreshHUD', core.refreshHUD)
registerExport('updateHUD', core.updateHUD)
registerExport('GetBridgeClientSnapshot', bridge.GetBridgeClientSnapshot)
registerExport('GetBridgeClientMetadata', bridge.GetBridgeClientMetadata)
registerExport('SetBridgeClientMetadata', bridge.SetBridgeClientMetadata)
