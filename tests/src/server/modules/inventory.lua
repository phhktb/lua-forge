local Inventory = {}

local MONEY_ACCOUNTS = {
    money = true,
    black_money = true,
}

local function getWeaponName(itemName)
    if type(itemName) == 'string' and itemName:upper():find('WEAPON_', 1, true) == 1 then
        return itemName:upper()
    end

    return nil
end

local function isWeapon(itemName)
    return getWeaponName(itemName) ~= nil
end

function Inventory.isWeapon(itemName)
    return isWeapon(itemName)
end

function Inventory.getWeaponName(itemName)
    return getWeaponName(itemName)
end

function Inventory.getCount(xPlayer, itemName)
    if not xPlayer or not itemName then
        return 0
    end

    if itemName == 'money' and xPlayer.getMoney then
        return tonumber(xPlayer.getMoney()) or 0
    end

    if MONEY_ACCOUNTS[itemName] and xPlayer.getAccount then
        local account = xPlayer.getAccount(itemName)
        return account and tonumber(account.money) or 0
    end

    local weaponName = getWeaponName(itemName)

    if weaponName and xPlayer.hasWeapon then
        return xPlayer.hasWeapon(weaponName) and 1 or 0
    end

    if xPlayer.getInventoryItem then
        local item = xPlayer.getInventoryItem(itemName)
        return item and tonumber(item.count) or 0
    end

    return 0
end

function Inventory.hasItems(xPlayer, itemList, multiplier)
    multiplier = math.max(math.floor(tonumber(multiplier) or 1), 1)

    if type(itemList) ~= 'table' then
        return true
    end

    for itemName, count in pairs(itemList) do
        local required = (tonumber(count) or 0) * multiplier

        if required > 0 and Inventory.getCount(xPlayer, itemName) < required then
            return false, itemName
        end
    end

    return true
end

function Inventory.hasMoney(xPlayer, costList, multiplier)
    multiplier = math.max(math.floor(tonumber(multiplier) or 1), 1)

    if type(costList) ~= 'table' then
        return true
    end

    for accountName, amount in pairs(costList) do
        local required = (tonumber(amount) or 0) * multiplier

        if required > 0 and Inventory.getCount(xPlayer, accountName) < required then
            return false, accountName
        end
    end

    return true
end

function Inventory.removeItem(xPlayer, itemName, count)
    count = math.floor(tonumber(count) or 0)

    if count <= 0 then
        return
    end

    local weaponName = getWeaponName(itemName)

    if weaponName and xPlayer.removeWeapon then
        for _ = 1, count do
            if xPlayer.hasWeapon and xPlayer.hasWeapon(weaponName) then
                xPlayer.removeWeapon(weaponName)
            end
        end
        return
    end

    if xPlayer.removeInventoryItem then
        xPlayer.removeInventoryItem(itemName, count)
    end
end

function Inventory.addItem(xPlayer, itemName, count)
    count = math.floor(tonumber(count) or 0)

    if count <= 0 then
        return 0
    end

    local weaponName = getWeaponName(itemName)

    if weaponName and xPlayer.addWeapon then
        local added = 0

        for _ = 1, count do
            if not xPlayer.hasWeapon or not xPlayer.hasWeapon(weaponName) then
                xPlayer.addWeapon(weaponName, 0)
                added = added + 1
            end
        end

        return added
    end

    if xPlayer.addInventoryItem then
        xPlayer.addInventoryItem(itemName, count)
        return count
    end

    return 0
end

function Inventory.removeItems(xPlayer, itemList, multiplier)
    multiplier = math.max(math.floor(tonumber(multiplier) or 1), 1)

    if type(itemList) ~= 'table' then
        return
    end

    for itemName, count in pairs(itemList) do
        Inventory.removeItem(xPlayer, itemName, (tonumber(count) or 0) * multiplier)
    end
end

function Inventory.removeMoney(xPlayer, costList, multiplier)
    multiplier = math.max(math.floor(tonumber(multiplier) or 1), 1)

    if type(costList) ~= 'table' then
        return
    end

    for accountName, amount in pairs(costList) do
        local total = (tonumber(amount) or 0) * multiplier

        if total > 0 then
            if accountName == 'money' and xPlayer.removeMoney then
                xPlayer.removeMoney(total)
            elseif xPlayer.removeAccountMoney then
                xPlayer.removeAccountMoney(accountName, total)
            end
        end
    end
end

function Inventory.canCarry(xPlayer, itemName, count)
    if not xPlayer or not itemName then
        return false
    end

    count = math.floor(tonumber(count) or 0)

    if count <= 0 then
        return true
    end

    local weaponName = getWeaponName(itemName)

    if weaponName then
        return count <= 1 and (not xPlayer.hasWeapon or not xPlayer.hasWeapon(weaponName))
    end

    if xPlayer.canCarryItem then
        return xPlayer.canCarryItem(itemName, count)
    end

    if xPlayer.getInventoryItem then
        local item = xPlayer.getInventoryItem(itemName)

        if item and item.limit ~= nil then
            local limit = tonumber(item.limit) or -1

            if limit < 0 then
                return true
            end

            return ((tonumber(item.count) or 0) + count) <= limit
        end
    end

    return true
end

return Inventory
