local PlayerCache = {
    esx = nil,
    loaded = false,
    labels = {},
    counts = {},
    jobName = nil,
}

function PlayerCache.init(esx)
    PlayerCache.esx = esx
end

local function getWeaponName(itemName)
    if type(itemName) == 'string' and itemName:upper():find('WEAPON_', 1, true) == 1 then
        return itemName:upper()
    end

    return nil
end

local function getCurrentWeaponCount(weaponName)
    if not weaponName
        or type(PlayerPedId) ~= 'function'
        or type(GetHashKey) ~= 'function'
        or type(HasPedGotWeapon) ~= 'function'
    then
        return nil
    end

    local playerPed = PlayerPedId()

    if not playerPed or playerPed == 0 then
        return nil
    end

    if HasPedGotWeapon(playerPed, GetHashKey(weaponName), false) then
        return 1
    end

    return nil
end

local function cacheItem(labels, counts, itemName, label, count)
    labels[itemName] = label or labels[itemName]
    counts[itemName] = tonumber(count) or 0

    local weaponName = getWeaponName(itemName)

    if weaponName then
        labels[weaponName] = label or labels[weaponName]
        counts[weaponName] = tonumber(count) or 0
    end
end

function PlayerCache.refresh(playerData)
    local esx = PlayerCache.esx

    playerData = type(playerData) == 'table' and playerData or (esx and esx.GetPlayerData and esx.GetPlayerData())

    local labels = {}
    local counts = {}

    if type(playerData) ~= 'table' then
        PlayerCache.loaded = false
        PlayerCache.labels = labels
        PlayerCache.counts = counts
        PlayerCache.jobName = nil
        return
    end

    if type(playerData.inventory) == 'table' then
        for _, item in pairs(playerData.inventory) do
            if type(item) == 'table' and item.name then
                cacheItem(labels, counts, item.name, item.label, item.count)
            end
        end
    end

    if type(playerData.accounts) == 'table' then
        for _, account in pairs(playerData.accounts) do
            if type(account) == 'table' and account.name then
                cacheItem(labels, counts, account.name, account.label, account.money)
            end
        end
    end

    if type(playerData.loadout) == 'table' then
        for _, weapon in pairs(playerData.loadout) do
            if type(weapon) == 'table' and weapon.name then
                cacheItem(labels, counts, weapon.name, weapon.label, 1)
            end
        end
    end

    PlayerCache.loaded = true
    PlayerCache.labels = labels
    PlayerCache.counts = counts
    PlayerCache.jobName = playerData.job and playerData.job.name or nil
end

function PlayerCache.applyCounts(counts)
    if type(counts) ~= 'table' then
        return
    end

    PlayerCache.counts = PlayerCache.counts or {}

    for itemName, count in pairs(counts) do
        if itemName then
            PlayerCache.counts[itemName] = tonumber(count) or 0

            local weaponName = getWeaponName(itemName)

            if weaponName then
                PlayerCache.counts[weaponName] = tonumber(count) or 0
            end
        end
    end

    PlayerCache.loaded = true
end

function PlayerCache.ensure()
    if not PlayerCache.loaded then
        PlayerCache.refresh()
    end
end

function PlayerCache.getJobName()
    PlayerCache.ensure()

    return PlayerCache.jobName
end

function PlayerCache.getLabel(itemName)
    if not itemName then
        return nil
    end

    PlayerCache.ensure()

    if PlayerCache.labels[itemName] then
        return PlayerCache.labels[itemName]
    end

    local esx = PlayerCache.esx

    local weaponName = getWeaponName(itemName)

    if weaponName and PlayerCache.labels[weaponName] then
        return PlayerCache.labels[weaponName]
    end

    if weaponName and esx and esx.GetWeaponLabel then
        local weaponLabel = esx.GetWeaponLabel(itemName:upper())
        if weaponLabel then
            return weaponLabel
        end
    end

    return itemName
end

function PlayerCache.getCount(itemName)
    if not itemName then
        return 0
    end

    PlayerCache.ensure()

    local weaponName = getWeaponName(itemName)
    local currentWeaponCount = getCurrentWeaponCount(weaponName)

    if currentWeaponCount ~= nil then
        return currentWeaponCount
    end

    if PlayerCache.counts[itemName] then
        return tonumber(PlayerCache.counts[itemName]) or 0
    end

    if weaponName and PlayerCache.counts[weaponName] then
        return tonumber(PlayerCache.counts[weaponName]) or 0
    end

    return 0
end

return PlayerCache
