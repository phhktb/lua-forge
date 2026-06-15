local __mod_craft_service_0 = (function()
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
end)()

local __mod_craft_sound_1 = (function()
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
end)()

local __mod_guarantee_service_2 = (function()
  local Service = {
      identity = nil,
      recipes = nil,
      store = nil,
      rng = nil,
  }
  
  function Service.init(options)
      Service.identity = options.identity
      Service.recipes = options.recipes
      Service.store = options.store
      Service.rng = options.rng
  end
  
  function Service.recordResult(source, craftKey, success, cb)
      local identifier = Service.identity.getIdentifier(source)
      local recipe = Service.recipes.get(craftKey)
      local guaranteedCount = recipe and math.floor(tonumber(recipe.guaranteed_count) or 0) or 0
  
      if not identifier or not recipe then
          if cb then
              cb(false, 0, false)
          end
          return
      end
  
      if guaranteedCount <= 0 then
          if cb then
              cb(true, 0, false)
          end
          return
      end
  
      if success then
          Service.store.setProgress(source, identifier, craftKey, 0, function(progress)
              if cb then
                  cb(true, progress, false)
              end
          end)
          return
      end
  
      Service.store.getProgress(identifier, craftKey, function(currentProgress)
          local nextProgress = Service.store.normalizeProgress(currentProgress + 1, guaranteedCount)
          local isReady = nextProgress >= guaranteedCount
  
          Service.store.setProgress(source, identifier, craftKey, nextProgress, function(progress)
              if cb then
                  cb(true, progress, isReady)
              end
          end)
      end)
  end
  
  function Service.resolveCraftSuccess(source, craftKey, bonusRate, cb)
      local identifier = Service.identity.getIdentifier(source)
      local recipe = Service.recipes.get(craftKey)
  
      if not identifier or not recipe then
          cb({
              ok = false,
              message = 'invalid_recipe',
              success = false,
              progress = 0,
              guaranteed = false,
          })
          return
      end
  
      local guaranteedCount = math.floor(tonumber(recipe.guaranteed_count) or 0)
      local baseRate = tonumber(recipe.rate) or 0
      local finalRate = Service.rng.clampRate(baseRate + (tonumber(bonusRate) or 0))
  
      if guaranteedCount <= 0 then
          local success = Service.rng.rollPercent(finalRate)
  
          cb({
              ok = true,
              success = success,
              progress = 0,
              guaranteed = false,
              rate = finalRate,
          })
          return
      end
  
      Service.store.getProgress(identifier, craftKey, function(currentProgress)
          currentProgress = Service.store.normalizeProgress(currentProgress, guaranteedCount)
  
          if currentProgress >= guaranteedCount then
              Service.store.setProgress(source, identifier, craftKey, 0, function(progress)
                  cb({
                      ok = true,
                      success = true,
                      progress = progress,
                      guaranteed = true,
                      rate = finalRate,
                  })
              end)
              return
          end
  
          local success = Service.rng.rollPercent(finalRate)
  
          Service.recordResult(source, craftKey, success, function(ok, progress, isReady)
              cb({
                  ok = ok,
                  success = success,
                  progress = progress,
                  guaranteed = false,
                  guaranteedReady = isReady,
                  rate = finalRate,
              })
          end)
      end)
  end
  
  function Service.rollBatch(source, craftKey, bonusRate, amount, cb)
      local identifier = Service.identity.getIdentifier(source)
      local recipe = Service.recipes.get(craftKey)
  
      if not identifier or not recipe then
          cb({
              ok = false,
              message = 'invalid_recipe',
          })
          return
      end
  
      amount = math.max(math.floor(tonumber(amount) or 1), 1)
  
      local guaranteedCount = math.floor(tonumber(recipe.guaranteed_count) or 0)
      local baseRate = tonumber(recipe.rate) or 0
      local finalRate = Service.rng.clampRate(baseRate + (tonumber(bonusRate) or 0))
  
      Service.store.getProgress(identifier, craftKey, function(currentProgress)
          currentProgress = Service.store.normalizeProgress(currentProgress, guaranteedCount)
  
          local results = {}
          local successCount = 0
          local failCount = 0
          local guaranteedUsed = 0
  
          for index = 1, amount do
              local success = false
              local guaranteed = false
              local roll = nil
  
              if guaranteedCount > 0 and currentProgress >= guaranteedCount then
                  success = true
                  guaranteed = true
                  guaranteedUsed = guaranteedUsed + 1
                  currentProgress = 0
              else
                  success, _, roll = Service.rng.rollPercent(finalRate)
  
                  if guaranteedCount > 0 then
                      if success then
                          currentProgress = 0
                      else
                          currentProgress = Service.store.normalizeProgress(currentProgress + 1, guaranteedCount)
                      end
                  end
              end
  
              if success then
                  successCount = successCount + 1
              else
                  failCount = failCount + 1
              end
  
              results[#results + 1] = {
                  index = index,
                  success = success,
                  guaranteed = guaranteed,
                  roll = roll,
                  progress = currentProgress,
              }
          end
  
          cb({
              ok = true,
              results = results,
              successCount = successCount,
              failCount = failCount,
              guaranteedUsed = guaranteedUsed,
              finalProgress = guaranteedCount > 0 and currentProgress or 0,
              guaranteedCount = guaranteedCount,
              rate = finalRate,
          })
      end)
  end
  
  function Service.commitProgress(source, craftKey, progress, cb)
      local identifier = Service.identity.getIdentifier(source)
      local recipe = Service.recipes.get(craftKey)
      local guaranteedCount = recipe and math.floor(tonumber(recipe.guaranteed_count) or 0) or 0
  
      if not identifier or not recipe then
          if cb then
              cb(false, 0)
          end
          return
      end
  
      if guaranteedCount <= 0 then
          if cb then
              cb(true, 0)
          end
          return
      end
  
      local normalizedProgress = Service.store.normalizeProgress(progress, guaranteedCount)
  
      Service.store.setProgress(source, identifier, craftKey, normalizedProgress, function(savedProgress)
          if cb then
              cb(true, savedProgress)
          end
      end)
  end
  
  return Service
end)()

local __mod_guarantee_store_3 = (function()
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
end)()

local __mod_identity_4 = (function()
  local Identity = {
      esx = nil,
  }
  
  function Identity.init(esx)
      Identity.esx = esx
  end
  
  function Identity.getIdentifier(source)
      local xPlayer = Identity.esx.GetPlayerFromId(source)
  
      return xPlayer and xPlayer.identifier or nil
  end
  
  return Identity
end)()

local __mod_inventory_5 = (function()
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
end)()

local __mod_notifier_6 = (function()
  local Notifier = {
      resourceName = nil,
  }
  
  function Notifier.init(resourceName)
      Notifier.resourceName = resourceName
  end
  
  function Notifier.debug(message)
      if Config.Debug then
          print(('[%s] %s'):format(Notifier.resourceName or GetCurrentResourceName(), message))
      end
  end
  
  return Notifier
end)()

local __mod_recipes_7 = (function()
  local Recipes = {
      byKey = {},
  }
  
  function Recipes.getCraftKey(categoryId, recipeIndex, itemName)
      return ('%s:%s:%s'):format(categoryId, recipeIndex, itemName or 'unknown')
  end
  
  function Recipes.rebuild()
      Recipes.byKey = {}
  
      for categoryId, category in pairs(Config.category or {}) do
          if type(category) == 'table' and type(category.list) == 'table' then
              for recipeIndex, recipe in ipairs(category.list) do
                  if type(recipe) == 'table' then
                      local craftKey = Recipes.getCraftKey(categoryId, recipeIndex, recipe.item)
                      Recipes.byKey[craftKey] = recipe
                  end
              end
          end
      end
  end
  
  function Recipes.get(craftKey)
      if not next(Recipes.byKey) then
          Recipes.rebuild()
      end
  
      return Recipes.byKey[craftKey]
  end
  
  return Recipes
end)()

local __mod_rng_8 = (function()
  local Rng = {
      initialized = false,
  }
  
  local function clampRate(rate)
      rate = tonumber(rate) or 0
  
      if rate < 0 then
          return 0
      end
  
      if rate > 100 then
          return 100
      end
  
      return rate
  end
  
  function Rng.init()
      if Rng.initialized then
          return
      end
  
      local seed = os.time() + GetGameTimer() + math.random(1, 1000000)
      math.randomseed(seed)
  
      for _ = 1, 5 do
          math.random()
      end
  
      Rng.initialized = true
  end
  
  function Rng.rollPercent(rate)
      Rng.init()
  
      rate = clampRate(rate)
  
      if rate <= 0 then
          return false, rate, 10000
      end
  
      if rate >= 100 then
          return true, rate, 0
      end
  
      local threshold = math.floor(rate * 100)
      local roll = math.random(1, 10000)
  
      return roll <= threshold, rate, roll
  end
  
  function Rng.clampRate(rate)
      return clampRate(rate)
  end
  
  return Rng
end)()

local __mod_shared_vault_9 = (function()
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
end)()

local ESX = exports["es_extended"]:getSharedObject()
local resourceName = GetCurrentResourceName()

local CraftService = __mod_craft_service_0
local CraftSound = __mod_craft_sound_1
local GuaranteeService = __mod_guarantee_service_2
local GuaranteeStore = __mod_guarantee_store_3
local Identity = __mod_identity_4
local Inventory = __mod_inventory_5
local Notifier = __mod_notifier_6
local Recipes = __mod_recipes_7
local Rng = __mod_rng_8
local SharedVault = __mod_shared_vault_9

Notifier.init(resourceName)
CraftSound.init(resourceName)
SharedVault.init()
Identity.init(ESX)
Rng.init()
GuaranteeStore.init({
    resourceName = resourceName,
    identity = Identity,
    recipes = Recipes,
    tableName = 'qubit_crafting_guarantee',
})
GuaranteeService.init({
    identity = Identity,
    recipes = Recipes,
    store = GuaranteeStore,
    rng = Rng,
})
CraftService.init({
    esx = ESX,
    inventory = Inventory,
    guaranteeService = GuaranteeService,
    craftSound = CraftSound,
    sharedVault = SharedVault,
    recipes = Recipes,
    resourceName = resourceName,
})

CraftSound.registerEvents()

CreateThread(function()
    Recipes.rebuild()

    Wait(1000)

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if xPlayer and xPlayer.source then
            GuaranteeStore.load(xPlayer.source)
        end
    end
end)

ESX.RegisterServerCallback(resourceName .. ':getGuaranteeProgress', function(source, cb)
    local identifier = Identity.getIdentifier(source)

    if not identifier then
        cb({})
        return
    end

    local cachedProgress = GuaranteeStore.getCache(identifier)

    if cachedProgress then
        cb(cachedProgress)
        return
    end

    GuaranteeStore.load(source, cb)
end)

RegisterNetEvent(resourceName .. ':requestGuaranteeCache', function()
    GuaranteeStore.load(source)
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    local playerSource = tonumber(playerId) or source

    SetTimeout(500, function()
        GuaranteeStore.load(playerSource)
    end)
end)

ESX.RegisterServerCallback(resourceName .. ':recordGuaranteeResult', function(source, cb, craftKey, success)
    GuaranteeService.recordResult(source, craftKey, success == true, function(ok, progress, isReady)
        cb({
            ok = ok,
            progress = progress,
            guaranteedReady = isReady,
        })
    end)
end)

ESX.RegisterServerCallback(resourceName .. ':resolveCraftSuccess', function(source, cb, craftKey, bonusRate)
    GuaranteeService.resolveCraftSuccess(source, craftKey, bonusRate, cb)
end)

ESX.RegisterServerCallback(resourceName .. ':startCraft', function(source, cb, request)
    CraftService.start(source, request, cb)
end)

local function collectConfiguredItems(itemNames, sourceList)
    if type(sourceList) ~= 'table' then
        return
    end

    if sourceList.item then
        itemNames[sourceList.item] = true
        return
    end

    for _, itemConfig in ipairs(sourceList) do
        if type(itemConfig) == 'table' and itemConfig.item then
            itemNames[itemConfig.item] = true
        elseif type(itemConfig) == 'string' then
            itemNames[itemConfig] = true
        end
    end

    for itemName in pairs(sourceList) do
        if type(itemName) ~= 'number' and itemName ~= 'item' and itemName ~= 'count' then
            itemNames[itemName] = true
        end
    end
end

local function collectCategoryBlueprintItems(categoryId)
    local itemNames = {}
    local category = Config.category and Config.category[categoryId]

    if type(category) ~= 'table' or type(category.list) ~= 'table' then
        return itemNames
    end

    for _, recipe in ipairs(category.list) do
        if type(recipe.blueprint) == 'table' then
            for itemName in pairs(recipe.blueprint) do
                itemNames[itemName] = true
            end
        end

        collectConfiguredItems(itemNames, recipe.equipment)
    end

    return itemNames
end

ESX.RegisterServerCallback(resourceName .. ':getSharedVaultCounts', function(source, cb, request)
    local tableIndex = tonumber(request and request.tableIndex)
    local categoryId = tonumber(request and request.categoryId)

    if not tableIndex or not categoryId or not CraftService.canUse(source, tableIndex, categoryId) then
        cb({ ok = false, reason = 'invalid_category', counts = {} })
        return
    end

    if not SharedVault.isAvailable() then
        cb({ ok = false, reason = 'shared_vault_unavailable', counts = {} })
        return
    end

    SharedVault.getCounts(source, collectCategoryBlueprintItems(categoryId), function(counts)
        cb({
            ok = true,
            counts = counts,
        })
    end)
end)

RegisterNetEvent(resourceName .. ':recordGuaranteeResult', function(craftKey, success)
    local source = source

    GuaranteeService.recordResult(source, craftKey, success == true, function(ok)
        if not ok then
            Notifier.debug(('Failed to record guarantee progress for %s'):format(tostring(craftKey)))
        end
    end)
end)

exports('ResolveCraftSuccess', function(source, craftKey, bonusRate, cb)
    GuaranteeService.resolveCraftSuccess(source, craftKey, bonusRate, cb)
end)

exports('RecordGuaranteeResult', function(source, craftKey, success, cb)
    GuaranteeService.recordResult(source, craftKey, success == true, cb)
end)

AddEventHandler('playerDropped', function()
    CraftService.clear(source)
    CraftSound.clear(source)
    GuaranteeStore.clear(source)
end)
