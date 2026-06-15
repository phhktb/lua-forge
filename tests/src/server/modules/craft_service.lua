local CraftService = {
    esx = nil,
    inventory = nil,
    guaranteeService = nil,
    craftSound = nil,
    sharedVault = nil,
    recipes = nil,
    pending = {},
}

local function parseCraftKey(craftKey)
    local categoryId, recipeIndex = tostring(craftKey or ''):match('^(%d+):(%d+):')

    return tonumber(categoryId), tonumber(recipeIndex)
end

local function isCategoryAllowed(craftTable, categoryId)
    for _, allowedCategoryId in ipairs(craftTable.limit_category or {}) do
        if allowedCategoryId == categoryId then
            return true
        end
    end

    return false
end

local function canUseCraftTable(xPlayer, craftTable)
    if not craftTable.job then
        return true
    end

    local jobName = xPlayer and xPlayer.job and xPlayer.job.name

    return jobName and craftTable.job[jobName] == true
end

local function getVector3(coords)
    if not coords or not coords.x or not coords.y or not coords.z then
        return nil
    end

    return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

local function isPlayerNearCraftTable(source, craftTable)
    local tableCoords = getVector3(craftTable and craftTable.position)
    local playerPed = GetPlayerPed(source)

    if not tableCoords or not playerPed or playerPed == 0 then
        return false
    end

    local maxDistance = tonumber(craftTable.max_distance) or 2.0
    local distance = #(GetEntityCoords(playerPed) - tableCoords)

    return distance <= (maxDistance + 0.75)
end

local function isWeapon(itemName)
    return CraftService.inventory and CraftService.inventory.isWeapon and CraftService.inventory.isWeapon(itemName)
end

local function getRecipeOutputAmount(recipe)
    local outputAmount = math.max(math.floor(tonumber(recipe and recipe.amount) or 1), 1)

    if isWeapon(recipe and recipe.item) then
        return 1
    end

    return outputAmount
end

local function hasBlockedResultItem(xPlayer, recipe)
    return recipe
        and recipe.deny_if_has_result == true
        and CraftService.inventory.getCount(xPlayer, recipe.item) > 0
end

local function canCarryRequestedResult(xPlayer, recipe, amount)
    local resultAmount = getRecipeOutputAmount(recipe) * math.max(math.floor(tonumber(amount) or 1), 1)

    if resultAmount > 0 and not CraftService.inventory.canCarry(xPlayer, recipe.item, resultAmount) then
        return false, 'cannot_carry_result', recipe.item
    end

    return true
end

local function getBlueprintUsagePlan(source, xPlayer, itemList, multiplier, useSharedVault)
    local plan = {
        inventory = {},
        vault = {},
    }

    multiplier = math.max(math.floor(tonumber(multiplier) or 1), 1)

    if type(itemList) ~= 'table' then
        return plan
    end

    for itemName, count in pairs(itemList) do
        local required = (tonumber(count) or 0) * multiplier

        if required > 0 then
            local inventoryCount = CraftService.inventory.getCount(xPlayer, itemName)
            local vaultCount = 0

            if useSharedVault and CraftService.sharedVault then
                vaultCount = CraftService.sharedVault.getItemCount(source, itemName)
            end

            if (inventoryCount + vaultCount) < required then
                return nil, itemName
            end

            local inventoryAmount = math.min(inventoryCount, required)
            local vaultAmount = required - inventoryAmount

            if inventoryAmount > 0 then
                plan.inventory[itemName] = inventoryAmount
            end

            if vaultAmount > 0 then
                plan.vault[itemName] = vaultAmount
            end
        end
    end

    return plan
end

local function hasEntries(sourceList)
    return type(sourceList) == 'table' and next(sourceList) ~= nil
end

local function getUsableItemCount(source, xPlayer, itemName, useSharedVault)
    local inventoryCount = CraftService.inventory.getCount(xPlayer, itemName)

    if useSharedVault and CraftService.sharedVault then
        return inventoryCount + CraftService.sharedVault.getItemCount(source, itemName)
    end

    return inventoryCount
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

local function getBonusConfig(recipe, bonusItemName)
    if not bonusItemName or type(recipe.bonus_item_rate) ~= 'table' then
        return nil
    end

    local bonusConfig = recipe.bonus_item_rate[bonusItemName]

    if type(bonusConfig) ~= 'table' then
        return nil
    end

    return {
        itemName = bonusItemName,
        count = tonumber(bonusConfig.count) or 1,
        rate = tonumber(bonusConfig.rate) or 0,
    }
end

function CraftService.canUse(source, tableIndex, categoryId)
    local xPlayer = CraftService.esx.GetPlayerFromId(source)
    local craftTable = tableIndex and Config.craftTable and Config.craftTable[tableIndex] or nil

    if not xPlayer or not craftTable then
        return false
    end

    if not canUseCraftTable(xPlayer, craftTable) then
        return false
    end

    if not isCategoryAllowed(craftTable, categoryId) then
        return false
    end

    if not isPlayerNearCraftTable(source, craftTable) then
        return false
    end

    return true
end

local function validateRequest(source, request)
    local xPlayer = CraftService.esx.GetPlayerFromId(source)
    local tableIndex = tonumber(request and request.tableIndex)
    local craftKey = request and request.craftKey
    local amount = math.max(math.floor(tonumber(request and request.amount) or 1), 1)
    local categoryId = parseCraftKey(craftKey)
    local craftTable = tableIndex and Config.craftTable and Config.craftTable[tableIndex] or nil
    local recipe = CraftService.recipes.get(craftKey)
    local useSharedVault = request and request.useSharedVault == true

    if CraftService.pending[source] then
        return nil, 'already_crafting'
    end

    if not xPlayer or not craftTable or not recipe or not categoryId then
        return nil, 'invalid_recipe'
    end

    if not canUseCraftTable(xPlayer, craftTable) then
        return nil, 'no_access'
    end

    if not isPlayerNearCraftTable(source, craftTable) then
        return nil, 'too_far'
    end

    if not isCategoryAllowed(craftTable, categoryId) then
        return nil, 'invalid_category'
    end

    local maxAmount = tonumber(recipe.max_amount_input)

    if maxAmount and maxAmount > 0 and amount > maxAmount then
        return nil, 'amount_too_high'
    end

    if isWeapon(recipe.item) and amount > 1 then
        return nil, 'amount_too_high'
    end

    if hasBlockedResultItem(xPlayer, recipe) then
        return nil, 'already_has_result', recipe.item
    end

    local canCarryResult, carryReason, carryDetail = canCarryRequestedResult(xPlayer, recipe, amount)
    if not canCarryResult then
        return nil, carryReason, carryDetail
    end

    local blueprintPlan, missingBlueprint = getBlueprintUsagePlan(source, xPlayer, recipe.blueprint, amount, useSharedVault)
    if not blueprintPlan then
        return nil, 'missing_material', missingBlueprint
    end

    local hasCost, missingCost = CraftService.inventory.hasMoney(xPlayer, recipe.cost, amount)
    if not hasCost then
        return nil, 'missing_money', missingCost
    end

    for _, equipment in ipairs(getItemConfigs(recipe.equipment, 1)) do
        if getUsableItemCount(source, xPlayer, equipment.itemName, useSharedVault) < equipment.count then
            return nil, 'missing_equipment', equipment.itemName
        end
    end

    local bonus = getBonusConfig(recipe, request and request.bonusItemName)
    if bonus and CraftService.inventory.getCount(xPlayer, bonus.itemName) < (bonus.count * amount) then
        return nil, 'missing_bonus', bonus.itemName
    end

    return {
        source = source,
        xPlayer = xPlayer,
        tableIndex = tableIndex,
        categoryId = categoryId,
        craftKey = craftKey,
        recipe = recipe,
        amount = amount,
        bonus = bonus,
        useSharedVault = useSharedVault,
    }
end

local function addResultItem(xPlayer, itemName, count, checkCarry)
    if not itemName or count <= 0 then
        return 0
    end

    if checkCarry ~= false and not CraftService.inventory.canCarry(xPlayer, itemName, count) then
        return 0
    end

    return CraftService.inventory.addItem(xPlayer, itemName, count)
end

local function canCarryCraftResults(xPlayer, context, successCount)
    local resultAmount = getRecipeOutputAmount(context.recipe) * successCount

    if resultAmount > 0 and not CraftService.inventory.canCarry(xPlayer, context.recipe.item, resultAmount) then
        return false, 'cannot_carry_result', context.recipe.item
    end

    return true
end

local function collectUpdatedCounts(xPlayer, context, failItems)
    local itemNames = {}

    local function addName(itemName)
        if itemName then
            itemNames[itemName] = true
        end
    end

    addName(context.recipe.item)

    if type(context.recipe.blueprint) == 'table' then
        for itemName in pairs(context.recipe.blueprint) do
            addName(itemName)
        end
    end

    if type(context.recipe.cost) == 'table' then
        for accountName in pairs(context.recipe.cost) do
            addName(accountName)
        end
    end

    for _, equipment in ipairs(getItemConfigs(context.recipe.equipment, 1)) do
        addName(equipment.itemName)
    end

    if context.bonus then
        addName(context.bonus.itemName)
    end

    for _, failItem in ipairs(failItems or {}) do
        addName(failItem.itemName)
    end

    local counts = {}

    for itemName in pairs(itemNames) do
        counts[itemName] = CraftService.inventory.getCount(xPlayer, itemName)
    end

    return counts
end

local function collectUpdatedVaultCounts(context)
    if not context.useSharedVault or not CraftService.sharedVault or type(context.recipe.blueprint) ~= 'table' then
        return nil
    end

    local counts = {}

    for itemName in pairs(context.recipe.blueprint) do
        counts[itemName] = CraftService.sharedVault.getItemCount(context.source, itemName)
    end

    return counts
end

local function validateFinishInventory(xPlayer, context)
    if hasBlockedResultItem(xPlayer, context.recipe) then
        return false, 'already_has_result', context.recipe.item
    end

    local canCarryResult, carryReason, carryDetail = canCarryRequestedResult(xPlayer, context.recipe, context.amount)
    if not canCarryResult then
        return false, carryReason, carryDetail
    end

    local blueprintPlan, missingBlueprint = getBlueprintUsagePlan(
        context.source,
        xPlayer,
        context.recipe.blueprint,
        context.amount,
        context.useSharedVault
    )

    if not blueprintPlan then
        return false, 'missing_material', missingBlueprint
    end

    local hasCost, missingCost = CraftService.inventory.hasMoney(xPlayer, context.recipe.cost, context.amount)
    if not hasCost then
        return false, 'missing_money', missingCost
    end

    for _, equipment in ipairs(getItemConfigs(context.recipe.equipment, 1)) do
        if getUsableItemCount(context.source, xPlayer, equipment.itemName, context.useSharedVault) < equipment.count then
            return false, 'missing_equipment', equipment.itemName
        end
    end

    if context.bonus and CraftService.inventory.getCount(xPlayer, context.bonus.itemName) < (context.bonus.count * context.amount) then
        return false, 'missing_bonus', context.bonus.itemName
    end

    return true, nil, nil, blueprintPlan
end

local function removeInventoryBlueprint(xPlayer, blueprintPlan)
    for itemName, count in pairs((blueprintPlan and blueprintPlan.inventory) or {}) do
        CraftService.inventory.removeItem(xPlayer, itemName, count)
    end
end

local function removeFinishCost(xPlayer, context, blueprintPlan, cb)
    local function removePlayerCosts()
        removeInventoryBlueprint(xPlayer, blueprintPlan)
        CraftService.inventory.removeMoney(xPlayer, context.recipe.cost, context.amount)

        if context.bonus then
            CraftService.inventory.removeItem(xPlayer, context.bonus.itemName, context.bonus.count * context.amount)
        end

        cb(true)
    end

    if context.useSharedVault and blueprintPlan and hasEntries(blueprintPlan.vault) then
        CraftService.sharedVault.consumeItems(context.source, blueprintPlan.vault, function(success, reason, detail)
            if not success then
                cb(false, reason or 'missing_material', detail)
                return
            end

            removePlayerCosts()
        end)
        return
    end

    removePlayerCosts()
end

local function getCraftTableCoords(tableIndex)
    local craftTable = Config.craftTable and Config.craftTable[tableIndex]
    local position = craftTable and craftTable.position

    if not position then
        return nil
    end

    return {
        x = position.x,
        y = position.y,
        z = position.z,
    }
end

local function requestCraftResultSound(context, successCount)
    local coords = getCraftTableCoords(context.tableIndex)

    if not coords or not CraftService.craftSound then
        return
    end

    CraftService.craftSound.requestTargets(context.source, {
        coords = coords,
        name = (tonumber(successCount) or 0) > 0 and 'craftSuccess' or 'craftFail',
        distance = tonumber(Config.soundDistance) or 0,
        volume = tonumber(Config.soundVolume) or 0.5,
    })
end

local function sendCraftFailed(context, reason, detail)
    CraftService.pending[context.source] = nil

    TriggerClientEvent(CraftService.resourceName .. ':craftFinished', context.source, {
        ok = false,
        craftKey = context.craftKey,
        categoryId = context.categoryId,
        itemName = context.recipe and context.recipe.item or nil,
        reason = reason,
        detail = detail,
    })
end

local function finishCraft(context)
    local xPlayer = CraftService.esx.GetPlayerFromId(context.source)

    if not xPlayer then
        CraftService.pending[context.source] = nil
        return
    end

    local canFinish, reason, detail, blueprintPlan = validateFinishInventory(xPlayer, context)

    if not canFinish then
        sendCraftFailed(context, reason, detail)
        return
    end

    local failItems = getItemConfigs(context.recipe.fail_to_get, 1)
    local bonusRate = context.bonus and context.bonus.rate or 0

    CraftService.guaranteeService.rollBatch(context.source, context.craftKey, bonusRate, context.amount, function(rollResult)
        if not rollResult or not rollResult.ok then
            sendCraftFailed(context, rollResult and rollResult.message or 'roll_failed')
            return
        end

        local successCount = tonumber(rollResult.successCount) or 0
        local failCount = tonumber(rollResult.failCount) or 0
        local canCarry, carryReason, carryDetail = canCarryCraftResults(xPlayer, context, successCount)

        if not canCarry then
            sendCraftFailed(context, carryReason, carryDetail)
            return
        end

        removeFinishCost(xPlayer, context, blueprintPlan, function(removeSuccess, removeReason, removeDetail)
            if not removeSuccess then
                sendCraftFailed(context, removeReason or 'missing_material', removeDetail)
                return
            end

            local resultAmount = getRecipeOutputAmount(context.recipe) * successCount
            local addedFail = 0

            local addedResult = addResultItem(xPlayer, context.recipe.item, resultAmount)

            for _, failItem in ipairs(failItems) do
                addedFail = addedFail + addResultItem(xPlayer, failItem.itemName, failItem.count * failCount, false)
            end

            local updatedCounts = collectUpdatedCounts(xPlayer, context, failItems)
            local updatedVaultCounts = collectUpdatedVaultCounts(context)

            CraftService.guaranteeService.commitProgress(context.source, context.craftKey, rollResult.finalProgress, function()
                CraftService.pending[context.source] = nil
                requestCraftResultSound(context, successCount)

                TriggerClientEvent(CraftService.resourceName .. ':craftFinished', context.source, {
                    ok = true,
                    craftKey = context.craftKey,
                    categoryId = context.categoryId,
                    itemName = context.recipe.item,
                    successCount = successCount,
                    failCount = failCount,
                    addedResult = addedResult,
                    addedFail = addedFail,
                    counts = updatedCounts,
                    vaultCounts = updatedVaultCounts,
                    rate = rollResult.rate,
                    guaranteedUsed = rollResult.guaranteedUsed,
                })
            end)
        end)
    end)
end

function CraftService.init(options)
    CraftService.esx = options.esx
    CraftService.inventory = options.inventory
    CraftService.guaranteeService = options.guaranteeService
    CraftService.craftSound = options.craftSound
    CraftService.sharedVault = options.sharedVault
    CraftService.recipes = options.recipes
    CraftService.resourceName = options.resourceName
end

function CraftService.start(source, request, cb)
    local context, reason, detail = validateRequest(source, request)

    if not context then
        cb({
            ok = false,
            reason = reason,
            detail = detail,
        })
        return
    end

    local durationMs = math.max((tonumber(context.recipe.time_required) or 0) * context.amount * 1000, 100)

    CraftService.pending[source] = context
    SetTimeout(durationMs, function()
        finishCraft(context)
    end)

    cb({
        ok = true,
        durationMs = durationMs,
        craftKey = context.craftKey,
        categoryId = context.categoryId,
    })
end

function CraftService.clear(source)
    CraftService.pending[source] = nil
end

return CraftService
