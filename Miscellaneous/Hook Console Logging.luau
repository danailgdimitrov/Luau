local events_to_suppress = {
    game:GetService("LogService").MessageOut,
    game:GetService("ScriptContext").Error
}

for _, event in events_to_suppress do
    for _, connection in getconnections(event) do
        if not connection.Function then continue end
        if isexecutorclosure(connection.Function) then continue end
        if isfunctionhooked(connection.Function) then continue end

        hookfunction(connection.Function, function() end)
    end

    local VanillaConnect; VanillaConnect = hookfunction(event.Connect, function(self, closure)
        if not isexecutorclosure(closure) then 
            closure = function() end
        end

        return VanillaConnect(self, closure)
    end)
end

print("Hooked for potential console logging")