local CraftSound = {
    resourceName = nil,
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

local function getDistanceToCoords(coords)
    if type(coords) ~= 'table' or not coords.x or not coords.y or not coords.z then
        return nil
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local soundCoords = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    return #(playerCoords - soundCoords)
end

local function getDistanceVolume(baseVolume, distance, maxDistance)
    baseVolume = clamp(baseVolume, 0.0, 1.0)

    if not distance or not maxDistance or maxDistance <= 0 then
        return baseVolume
    end

    local falloff = 1.0 - (distance / maxDistance)

    return clamp(baseVolume * falloff, 0.0, 1.0)
end

local function getNearbyPlayerServerIds(coords, maxDistance)
    local targets = {}

    if type(coords) ~= 'table' or not coords.x or not coords.y or not coords.z or maxDistance <= 0 then
        return targets
    end

    local soundCoords = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local ownPlayerId = PlayerId()

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= ownPlayerId then
            local playerPed = GetPlayerPed(playerId)

            if playerPed and playerPed ~= 0 then
                local distance = #(GetEntityCoords(playerPed) - soundCoords)

                if distance <= maxDistance then
                    targets[#targets + 1] = GetPlayerServerId(playerId)
                end
            end
        end
    end

    return targets
end

function CraftSound.init(resourceName)
    CraftSound.resourceName = resourceName
end

function CraftSound.registerEvents()
    RegisterNetEvent(CraftSound.resourceName .. ':collectCraftSoundTargets', function(payload)
        if type(payload) ~= 'table' then
            return
        end

        local maxDistance = tonumber(payload.distance) or tonumber(Config.soundDistance) or 0
        local targets = getNearbyPlayerServerIds(payload.coords, maxDistance)

        TriggerServerEvent(CraftSound.resourceName .. ':sendCraftResultSoundTargets', {
            targets = targets,
        })
    end)

    RegisterNetEvent(CraftSound.resourceName .. ':playCraftResultSound', function(payload)
        if type(payload) ~= 'table' then
            return
        end

        if tonumber(payload.source) == GetPlayerServerId(PlayerId()) then
            return
        end

        local distance = payload.coords and getDistanceToCoords(payload.coords) or 0
        local maxDistance = tonumber(payload.distance) or tonumber(Config.soundDistance) or 0

        if payload.coords and (not distance or maxDistance <= 0 or distance > maxDistance) then
            return
        end

        SendNUIMessage({
            action = 'playSound',
            name = payload.name,
            volume = getDistanceVolume(payload.volume or Config.soundVolume, distance, maxDistance),
        })
    end)
end

return CraftSound
