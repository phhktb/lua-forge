local Store = {
    resourceName = nil,
    identity = nil,
    recipes = nil,
    tableName = 'qubit_crafting_guarantee',
    cache = {},
    sourceIdentifiers = {},
}

function Store.init(options)
    Store.resourceName = options.resourceName
    Store.identity = options.identity
    Store.recipes = options.recipes
    Store.tableName = options.tableName or Store.tableName
end

function Store.normalizeProgress(progress, guaranteedCount)
    progress = math.floor(tonumber(progress) or 0)
    guaranteedCount = math.floor(tonumber(guaranteedCount) or 0)

    if progress < 0 then
        return 0
    end

    if guaranteedCount > 0 and progress > guaranteedCount then
        return guaranteedCount
    end

    return progress
end

local function sanitizeRows(rows)
    local progressMap = {}

    for _, row in ipairs(rows or {}) do
        local recipe = Store.recipes.get(row.craft_key)
        local guaranteedCount = recipe and tonumber(recipe.guaranteed_count) or 0

        if recipe and guaranteedCount > 0 then
            progressMap[row.craft_key] = Store.normalizeProgress(row.progress, guaranteedCount)
        end
    end

    return progressMap
end

function Store.push(source, identifier)
    if source and identifier then
        TriggerClientEvent(Store.resourceName .. ':setGuaranteeCache', source, Store.cache[identifier] or {})
    end
end

function Store.load(source, cb)
    local identifier = Store.identity.getIdentifier(source)

    if not identifier then
        if cb then
            cb({})
        end
        return
    end

    Store.sourceIdentifiers[source] = identifier

    MySQL.query(
        ('SELECT `craft_key`, `progress` FROM `%s` WHERE `identifier` = ?'):format(Store.tableName),
        { identifier },
        function(rows)
            Store.cache[identifier] = sanitizeRows(rows)
            Store.push(source, identifier)

            if cb then
                cb(Store.cache[identifier])
            end
        end
    )
end

function Store.getCache(identifier)
    return Store.cache[identifier]
end

function Store.clear(source)
    local identifier = Store.sourceIdentifiers[source] or Store.identity.getIdentifier(source)

    if identifier then
        Store.cache[identifier] = nil
    end

    Store.sourceIdentifiers[source] = nil
end

function Store.getProgress(identifier, craftKey, cb)
    if Store.cache[identifier] then
        cb(tonumber(Store.cache[identifier][craftKey]) or 0)
        return
    end

    MySQL.scalar(
        ('SELECT `progress` FROM `%s` WHERE `identifier` = ? AND `craft_key` = ?'):format(Store.tableName),
        { identifier, craftKey },
        function(progress)
            cb(tonumber(progress) or 0)
        end
    )
end

function Store.setProgress(source, identifier, craftKey, progress, cb)
    Store.cache[identifier] = Store.cache[identifier] or {}
    Store.cache[identifier][craftKey] = progress

    MySQL.query(
        ([[
            INSERT INTO `%s` (`identifier`, `craft_key`, `progress`)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE `progress` = VALUES(`progress`)
        ]]):format(Store.tableName),
        { identifier, craftKey, progress },
        function()
            Store.push(source, identifier)

            if cb then
                cb(progress)
            end
        end
    )
end

return Store
