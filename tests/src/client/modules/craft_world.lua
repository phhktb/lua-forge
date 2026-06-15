local World = {
    notifier = nil,
    spawnedObjects = {},
    createdBlips = {},
}

function World.init(notifier)
    World.notifier = notifier
end

function World.getVector3(coords)
    if not coords then
        return nil
    end

    return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

local function getModelHash(model)
    if type(model) == 'number' then
        return model
    end

    if type(model) == 'string' then
        return GetHashKey(model)
    end

    return nil
end

local function requestModel(modelHash)
    if not modelHash or not IsModelInCdimage(modelHash) then
        return false
    end

    RequestModel(modelHash)

    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > timeout then
            return false
        end

        Wait(10)
    end

    return true
end

local function createCraftObject(index, craftTable)
    if craftTable.disable_model or not craftTable.model then
        return
    end

    local coords = World.getVector3(craftTable.position)
    local modelHash = getModelHash(craftTable.model)

    if not coords or not modelHash then
        World.notifier.debug(('Craft table %s has invalid model or position'):format(index))
        return
    end

    if not requestModel(modelHash) then
        World.notifier.debug(('Failed to load model for craft table %s'):format(index))
        return
    end

    local object = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(object, craftTable.heading or 0.0)
    FreezeEntityPosition(object, true)
    SetEntityAsMissionEntity(object, true, true)

    World.spawnedObjects[#World.spawnedObjects + 1] = object
    SetModelAsNoLongerNeeded(modelHash)
end

local function createCraftBlip(index, craftTable)
    local blipConfig = craftTable.map_blip
    local coords = World.getVector3(craftTable.position)

    if not blipConfig or not coords then
        return
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, blipConfig.blip_sprite or 1)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipConfig.blip_scale or 0.8)
    SetBlipColour(blip, blipConfig.blip_color or 0)
    SetBlipAsShortRange(blip, true)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(blipConfig.blip_name or craftTable.name or ('Craft Table ' .. index))
    EndTextCommandSetBlipName(blip)

    World.createdBlips[#World.createdBlips + 1] = blip
end

function World.setup(craftTables)
    for index, craftTable in ipairs(craftTables or {}) do
        createCraftObject(index, craftTable)
        createCraftBlip(index, craftTable)
    end
end

function World.cleanup()
    for _, object in ipairs(World.spawnedObjects) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end

    for _, blip in ipairs(World.createdBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    World.spawnedObjects = {}
    World.createdBlips = {}
end

return World
