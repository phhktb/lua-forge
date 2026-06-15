local Notifier = {
    resourceName = nil,
}

function Notifier.init(resourceName)
    Notifier.resourceName = resourceName
end

function Notifier.debug(message)
    if Config.Debug then
        print(('[%s] %s'):format(Notifier.resourceName or GetCurrentResourceName(), message))
    end
end

return Notifier
