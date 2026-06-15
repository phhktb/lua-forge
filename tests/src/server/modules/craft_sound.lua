local CraftSound = {
    resourceName = nil,
    pending = {},
}

local function clamp(value, minValue, maxValue)
    value = tonumber(value)

    if not value then
        return minValue
    end

    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

local function normalizeTargets(targets, source)
    local normalized = {}

    if type(targets) ~= 'table' then
        return normalized
    end

    for _, target in ipairs(targets) do
        target = tonumber(target)

        if target and target > 0 and target ~= source then
            normalized[target] = true
        end
    end

    return normalized
end

function CraftSound.init(resourceName)
    CraftSound.resourceName = resourceName
end

function CraftSound.requestTargets(source, payload)
    if type(payload) ~= 'table' then
        return
    end

    CraftSound.pending[source] = {
        name = payload.name,
        coords = payload.coords,
        distance = tonumber(payload.distance) or tonumber(Config.soundDistance) or 0,
        volume = clamp(payload.volume or Config.soundVolume, 0.0, 1.0),
    }

    TriggerClientEvent(CraftSound.resourceName .. ':collectCraftSoundTargets', source, CraftSound.pending[source])

    SetTimeout(3000, function()
        CraftSound.pending[source] = nil
    end)
end

function CraftSound.registerEvents()
    RegisterNetEvent(CraftSound.resourceName .. ':sendCraftResultSoundTargets', function(payload)
        local source = source
        local pendingPayload = CraftSound.pending[source]

        if not pendingPayload then
            return
        end

        CraftSound.pending[source] = nil

        for target in pairs(normalizeTargets(payload and payload.targets, source)) do
            TriggerClientEvent(CraftSound.resourceName .. ':playCraftResultSound', target, {
                source = source,
                name = pendingPayload.name,
                coords = pendingPayload.coords,
                distance = pendingPayload.distance,
                volume = pendingPayload.volume,
            })
        end
    end)
end

function CraftSound.clear(source)
    CraftSound.pending[source] = nil
end

return CraftSound
