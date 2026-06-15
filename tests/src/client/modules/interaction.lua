local Interaction = {
    access = nil,
    world = nil,
    openCraftTable = nil,
    isCraftOpen = nil,
    openKey = 38,
    craftTables = nil,
}

function Interaction.init(options)
    Interaction.access = options.access
    Interaction.world = options.world
    Interaction.openCraftTable = options.openCraftTable
    Interaction.isCraftOpen = options.isCraftOpen
    Interaction.openKey = options.openKey or Interaction.openKey
end

local CRAFT_POINT_PREFIX = "crafting:"

local function parseCraftIndex(...)
    local pointId = tostring(select(1, ...) or "")
    return tonumber((pointId:gsub("^" .. CRAFT_POINT_PREFIX, "")))
end

local function resolveDistance(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "number" then return v end
    end
    return math.huge
end

local function IsCraftDisabled(...)
    local index = parseCraftIndex(...)
    local distance = resolveDistance(...)
    if not index or not Interaction.craftTables or not Interaction.craftTables[index] then return true end
    local craftTable = Interaction.craftTables[index]
    return distance > (craftTable.max_distance or 2.0) or not Interaction.access.canUseCraftTable(craftTable)
end

local function HandleCraftPointPress(...)
    local index = parseCraftIndex(...)
    if not index or not Interaction.craftTables or not Interaction.craftTables[index] then return end
    if Interaction.isCraftOpen() then return end
    Interaction.openCraftTable(index, Interaction.craftTables[index])
end

local function buildCraftText(craftTable)
    local parts = {}
    if craftTable.name then
        table.insert(parts, craftTable.name)
    end
    if craftTable.desc then
        table.insert(parts, craftTable.desc)
    end
    table.insert(parts, '[E] เปิดโต๊ะคราฟ')
    return table.concat(parts, '~n~')
end

local function registerAllCraftPoints()
    if not Interaction.craftTables then return end
    for index, craftTable in ipairs(Interaction.craftTables) do
        local coords = Interaction.world.getVector3(craftTable.position)
        if coords then
            exports["qubit_drawtext"]:RegisterPoint(CRAFT_POINT_PREFIX .. index, {
                coords = coords,
                key = Interaction.openKey,
                text = buildCraftText(craftTable),
                visibleDistance = (craftTable.max_distance or 2.0) + 5,
                promptDistance = craftTable.max_distance or 2.0,
                zOffset = craftTable.name_height or 0.8,
                isDisabledExport = "IsCraftDisabled",
                onPressExport = "HandleCraftPointPress",
            })
        end
    end
end

function Interaction.start(craftTables)
    Interaction.craftTables = craftTables
    registerAllCraftPoints()
    exports("IsCraftDisabled", IsCraftDisabled)
    exports("HandleCraftPointPress", HandleCraftPointPress)
end

function Interaction.stop()
    if not Interaction.craftTables then return end
    for index in ipairs(Interaction.craftTables) do
        exports["qubit_drawtext"]:RemovePoint(CRAFT_POINT_PREFIX .. index)
    end
end

function Interaction.restart()
    registerAllCraftPoints()
end

return Interaction
