-- init.lua (place in the Az-Framework resource)
local az_core = exports["Az-Framework"]

Az = setmetatable({}, {
    __index = function(self, index)
        local fn = az_core[index]
        if type(fn) ~= "function" then
            -- cache non-functions directly
            rawset(self, index, fn)
            return fn
        end

        -- cache a thin wrapper for functions
        local wrapper = function(...)
            -- match ND_Core style: call exported function with nil as 'self'
            return fn(nil, ...)
        end

        rawset(self, index, wrapper)
        return wrapper
    end
})

return Az
