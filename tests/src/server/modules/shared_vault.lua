local SharedVault = {
    resourceName = 'qubit_vault',
}

local function getResourceName()
    if type(Config.sharedVault) == 'table' and Config.sharedVault.resource then
        return Config.sharedVault.resource
    end

    return Config.sharedVaultResource or SharedVault.resourceName
end

local function isEnabled()
    if type(Config.sharedVault) == 'table' and Config.sharedVault.enabled == false then
        return false
    end

    return true
end

local function isAvailable()
    local resourceName = getResourceName()

    return isEnabled() and resourceName and GetResourceState(resourceName) == 'started'
end

function SharedVault.init()
    SharedVault.resourceName = getResourceName()
end

function SharedVault.isAvailable()
    return isAvailable()
end

function SharedVault.getItemCount(source, itemName)
    if not itemName or not isAvailable() then
        return 0
    end

    local ok, count = pcall(function()
        return exports[SharedVault.resourceName]:GetItemCount(source, itemName, 'items')
    end)

    if not ok then
        return 0
    end

    return tonumber(count) or 0
end

function SharedVault.getCounts(source, itemNames, cb)
    local counts = {}

    if type(itemNames) ~= 'table' or not isAvailable() then
        cb(counts)
        return
    end

    local ok = pcall(function()
        exports[SharedVault.resourceName]:GetItems(source, 'items', function(success, vaultItems)
            vaultItems = success == true and type(vaultItems) == 'table' and vaultItems or {}

            for itemName in pairs(itemNames) do
                counts[itemName] = tonumber(vaultItems[itemName]) or 0
            end

            cb(counts)
        end)
    end)

    if not ok then
        cb(counts)
    end
end

local function consumeNext(source, entries, index, cb)
    local entry = entries[index]

    if not entry then
        cb(true)
        return
    end

    local ok = pcall(function()
        exports[SharedVault.resourceName]:ConsumeItem(source, entry.itemName, entry.count, 'items', function(success, movedCount, reason)
            if not success or (tonumber(movedCount) or 0) < entry.count then
                cb(false, reason or 'shared_vault_consume_failed', entry.itemName)
                return
            end

            consumeNext(source, entries, index + 1, cb)
        end)
    end)

    if not ok then
        cb(false, 'shared_vault_unavailable', entry.itemName)
    end
end

function SharedVault.consumeItems(source, itemCounts, cb)
    local entries = {}

    if type(itemCounts) ~= 'table' then
        cb(true)
        return
    end

    if not isAvailable() then
        cb(false, 'shared_vault_unavailable')
        return
    end

    for itemName, count in pairs(itemCounts) do
        count = math.floor(tonumber(count) or 0)

        if itemName and count > 0 then
            entries[#entries + 1] = {
                itemName = itemName,
                count = count,
            }
        end
    end

    table.sort(entries, function(left, right)
        return tostring(left.itemName) < tostring(right.itemName)
    end)

    consumeNext(source, entries, 1, cb)
end

return SharedVault
