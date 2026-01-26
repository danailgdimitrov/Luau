--!native
--!optimize 2
---@diagnostic disable: undefined-global

local events_to_suppress = {
    [game:GetService("LogService").MessageOut] = true,
    [game:GetService("ScriptContext").Error] = true
}

-- 1. Hook existing connections
for event in events_to_suppress do
    for _, connection in getconnections(event) do
        if not connection.Function or isexecutorclosure(connection.Function) then continue end
        if isfunctionhooked(connection.Function) then continue end

        hookfunction(connection.Function, function() end)
    end
end

-- 2. Hook Connect globally
local VanillaConnect; VanillaConnect = hookfunction(next(events_to_suppress).Connect, function(self, closure)
    if not events_to_suppress[self] or isexecutorclosure(closure) then 
        return VanillaConnect(self, closure)
    end

    return VanillaConnect(self, function() end)
end)

print("Safely hooked console logging signals")