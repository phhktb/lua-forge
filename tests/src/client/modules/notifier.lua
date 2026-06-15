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

function Notifier.push(options)
    if GetResourceState('nc_notify') ~= 'started' then
        Notifier.debug('nc_notify is not started')
        return
    end

    exports.nc_notify:PushNotification({
        title = options.title or 'แจ้งเตือน',
        description = options.description or '',
        type = options.type or 'info',
        duration = options.duration or 4000,
    })
end

return Notifier
