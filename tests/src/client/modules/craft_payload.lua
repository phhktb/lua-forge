local Payload = {
    playerCache = nil,
}

function Payload.init(playerCache)
    Payload.playerCache = playerCache
end

local function getItemImage(itemName)
    if not itemName then
        return nil
    end

    return ('%s%s.png'):format(Config.imagePath or '', itemName)
end

local function getLabel(itemName)
    if not itemName then
        return nil
    end

    return Payload.playerCache.getLabel(itemName)
end

local function getCount(itemName)
    if not itemName then
        return 0
    end

    return Payload.playerCache.getCount(itemName)
end

local function isWeapon(itemName)
    return type(itemName) == 'string' and itemName:upper():find('WEAPON_', 1, true) == 1
end

local function getRecipeOutputAmount(recipe)
    local outputAmount = math.max(math.floor(tonumber(recipe and recipe.amount) or 1), 1)

    if isWeapon(recipe and recipe.item) then
        return 1
    end

    return outputAmount
end

local function getRecipeMaxAmountInput(recipe)
    if isWeapon(recipe and recipe.item) then
        return 1
    end

    return recipe and recipe.max_amount_input or nil
end

local function formatNumber(value)
    local formatted = tostring(math.floor(tonumber(value) or 0))

    while true do
        local nextFormatted, changed = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        formatted = nextFormatted

        if changed == 0 then
            break
        end
    end

    return formatted
end

local function getSortedKeys(sourceList)
    local keys = {}

    if type(sourceList) ~= 'table' then
        return keys
    end

    for key in pairs(sourceList) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    return keys
end

local function getSharedCount(sharedCounts, itemName)
    if type(sharedCounts) ~= 'table' or not itemName then
        return 0
    end

    return tonumber(sharedCounts[itemName]) or 0
end

local function getMaterialPayload(sourceList, sharedCounts)
    local items = {}

    if type(sourceList) ~= 'table' then
        return items
    end

    for _, itemName in ipairs(getSortedKeys(sourceList)) do
        local required = tonumber(sourceList[itemName]) or 0
        local inventoryOwned = getCount(itemName)
        local sharedOwned = getSharedCount(sharedCounts, itemName)
        local owned = inventoryOwned + sharedOwned

        items[#items + 1] = {
            id = itemName,
            itemName = itemName,
            name = getLabel(itemName),
            count = ('%s/%s'):format(owned, required),
            inventoryOwned = inventoryOwned,
            sharedOwned = sharedOwned,
            owned = owned,
            required = required,
            image = getItemImage(itemName),
            active = owned >= required,
        }
    end

    return items
end

local function getItemConfigs(sourceList, defaultCount)
    local items = {}

    if type(sourceList) ~= 'table' then
        return items
    end

    if sourceList.item then
        return {
            {
                itemName = sourceList.item,
                count = tonumber(sourceList.count) or defaultCount or 1,
            }
        }
    end

    for _, itemConfig in ipairs(sourceList) do
        if type(itemConfig) == 'table' and itemConfig.item then
            items[#items + 1] = {
                itemName = itemConfig.item,
                count = tonumber(itemConfig.count) or defaultCount or 1,
            }
        elseif type(itemConfig) == 'string' then
            items[#items + 1] = {
                itemName = itemConfig,
                count = defaultCount or 1,
            }
        end
    end

    for _, itemName in ipairs(getSortedKeys(sourceList)) do
        if type(itemName) ~= 'number' and itemName ~= 'item' and itemName ~= 'count' then
            local count = sourceList[itemName]

            if count == true then
                count = defaultCount or 1
            end

            items[#items + 1] = {
                itemName = itemName,
                count = tonumber(count) or defaultCount or 1,
            }
        end
    end

    return items
end

local function getFailItemPayload(sourceList)
    local items = {}

    for index, itemConfig in ipairs(getItemConfigs(sourceList, 1)) do
        items[#items + 1] = {
            id = ('fail:%s:%s'):format(itemConfig.itemName, index),
            itemName = itemConfig.itemName,
            name = getLabel(itemConfig.itemName),
            count = tostring(itemConfig.count),
            image = getItemImage(itemConfig.itemName),
            variant = 'Fails',
        }
    end

    return items
end

local function getEquipmentPayload(sourceList, sharedCounts)
    local items = {}

    for index, itemConfig in ipairs(getItemConfigs(sourceList, 1)) do
        local required = tonumber(itemConfig.count) or 0
        local inventoryOwned = getCount(itemConfig.itemName)
        local sharedOwned = getSharedCount(sharedCounts, itemConfig.itemName)
        local owned = inventoryOwned + sharedOwned

        items[#items + 1] = {
            id = ('equip:%s:%s'):format(itemConfig.itemName, index),
            itemName = itemConfig.itemName,
            name = getLabel(itemConfig.itemName),
            count = ('%s/%s'):format(owned, required),
            inventoryOwned = inventoryOwned,
            sharedOwned = sharedOwned,
            owned = owned,
            required = required,
            image = getItemImage(itemConfig.itemName),
            variant = 'Equip',
            active = owned >= required,
        }
    end

    return items
end

local function getBonusItemPayload(sourceList)
    local items = {}

    if type(sourceList) ~= 'table' then
        return items
    end

    for _, itemName in ipairs(getSortedKeys(sourceList)) do
        local bonusConfig = sourceList[itemName]
        local count = 1
        local rate = 0

        if type(bonusConfig) == 'table' then
            count = tonumber(bonusConfig.count) or 1
            rate = tonumber(bonusConfig.rate) or 0
        end

        items[#items + 1] = {
            id = itemName,
            itemName = itemName,
            name = getLabel(itemName),
            count = count,
            rate = rate,
            image = getItemImage(itemName),
            active = getCount(itemName) >= count,
        }
    end

    return items
end

local function getCostPayload(sourceList)
    local costs = {}

    if type(sourceList) ~= 'table' then
        return costs
    end

    for _, accountName in ipairs(getSortedKeys(sourceList)) do
        local amount = tonumber(sourceList[accountName]) or 0
        local owned = getCount(accountName)

        costs[#costs + 1] = {
            id = accountName,
            accountName = accountName,
            label = accountName == 'money' and 'USE CASH' or 'USE BLACK',
            amount = amount,
            displayAmount = tostring(amount),
            owned = owned,
            type = accountName == 'black_money' and 'black' or 'cash',
            active = owned >= amount,
        }
    end

    return costs
end

function Payload.getCraftKey(categoryId, recipeIndex, itemName)
    return ('%s:%s:%s'):format(categoryId, recipeIndex, itemName or 'unknown')
end

function Payload.getRecipe(recipe, categoryId, recipeIndex, guaranteeProgress, sharedCounts)
    local itemName = recipe.item
    local craftKey = Payload.getCraftKey(categoryId, recipeIndex, itemName)
    local guaranteedCount = tonumber(recipe.guaranteed_count) or 0
    local outputAmount = getRecipeOutputAmount(recipe)
    local resultOwned = getCount(itemName)
    local denyIfHasResult = recipe.deny_if_has_result == true

    return {
        id = craftKey,
        craftKey = craftKey,
        itemName = itemName,
        name = getLabel(itemName),
        count = tostring(outputAmount),
        amount = outputAmount,
        deny_if_has_result = denyIfHasResult,
        resultOwned = resultOwned,
        resultBlocked = denyIfHasResult and resultOwned > 0,
        time_required = recipe.time_required,
        max_amount_input = getRecipeMaxAmountInput(recipe),
        costs = getCostPayload(recipe.cost),
        rate = recipe.rate or 0,
        guaranteed_count = recipe.guaranteed_count,
        guaranteed_progress = guaranteedCount > 0 and ((guaranteeProgress or {})[craftKey] or 0) or nil,
        image = getItemImage(itemName),
        blueprint = getMaterialPayload(recipe.blueprint, sharedCounts),
        failItems = getFailItemPayload(recipe.fail_to_get),
        equipment = getEquipmentPayload(recipe.equipment, sharedCounts),
        enhancements = getBonusItemPayload(recipe.bonus_item_rate),
    }
end

function Payload.getCategory(categoryId, guaranteeProgress, sharedCounts)
    local category = Config.category and Config.category[categoryId]

    if not category then
        return nil
    end

    local recipes = {}

    for recipeIndex, recipe in ipairs(category.list or {}) do
        recipes[#recipes + 1] = Payload.getRecipe(recipe, categoryId, recipeIndex, guaranteeProgress, sharedCounts)
    end

    return {
        id = categoryId,
        name = category.name or ('CATEGORY ' .. categoryId),
        items = recipes,
    }
end

function Payload.isCategoryAllowed(craftTable, categoryId)
    for _, allowedCategoryId in ipairs(craftTable.limit_category or {}) do
        if allowedCategoryId == categoryId then
            return true
        end
    end

    return false
end

function Payload.getBalances()
    return {
        cash = formatNumber(getCount('money')),
        black = formatNumber(getCount('black_money')),
    }
end

function Payload.getCraftTable(index, craftTable, guaranteeProgress, sharedCounts)
    local activeCategoryId = craftTable.limit_category and craftTable.limit_category[1] or nil
    local categories = {}

    for _, categoryId in ipairs(craftTable.limit_category or {}) do
        local category = Config.category and Config.category[categoryId]

        if category then
            local items = {}

            if categoryId == activeCategoryId then
                local categoryPayload = Payload.getCategory(categoryId, guaranteeProgress, sharedCounts)
                items = categoryPayload and categoryPayload.items or {}
            end

            categories[#categories + 1] = {
                id = categoryId,
                name = category.name or ('CATEGORY ' .. categoryId),
                items = items,
            }
        end
    end

    local balances = Payload.getBalances()

    return {
        index = index,
        name = craftTable.name,
        desc = craftTable.desc,
        limit_category = craftTable.limit_category or {},
        imagePath = Config.imagePath,
        cash = balances.cash,
        black = balances.black,
        categories = categories,
    }
end

return Payload
