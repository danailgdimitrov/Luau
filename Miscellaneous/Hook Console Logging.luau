--!native
--!optimize 2
---@diagnostic disable: undefined-global

local events_to_suppress = {
    game:GetService("LogService").MessageOut,
    game:GetService("ScriptContext").Error
}

-- 1. Hook existing connections
for _, event in events_to_suppress do
    for _, connection in getconnections(event) do
        if not connection.Function or isexecutorclosure(connection.Function) then continue end
        if isfunctionhooked(connection.Function) then continue end

        hookfunction(connection.Function, function() end)
    end
end

-- 2. Hook Connect globally
local VanillaConnect; VanillaConnect = hookfunction(events_to_suppress[1].Connect, function(self, closure)
    if not table.find(events_to_suppress, self) or isexecutorclosure(closure) then 
        return VanillaConnect(self, closure)
    end

    return VanillaConnect(self, function() end)
end)

print("Safely hooked console logging signals")