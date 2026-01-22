local az_core = exports["Az-Framework"]

Az = setmetatable({}, {
    __index = function(self, index)
        local fn = az_core[index]
        if type(fn) ~= "function" then
            rawset(self, index, fn)
            return fn
        end

        local wrapper = function(...)
            return fn(nil, ...)
        end

        rawset(self, index, wrapper)
        return wrapper
    end
})

return Az
