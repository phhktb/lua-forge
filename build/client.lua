local __mod_access_0 = (function()
  local Access = {
      playerCache = nil,
  }
  
  function Access.init(playerCache)
      Access.playerCache = playerCache
  end
  
  function Access.canUseCraftTable(craftTable)
      if not craftTable.job then
          return true
      end
  
      local jobName = Access.playerCache and Access.playerCache.getJobName()
  
      return jobName and craftTable.job[jobName] == true
  end
  
  return Access
end)()

local __mod_craft_payload_1 = (function()
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
end)()

local __mod_craft_sound_2 = (function()
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
end)()

local __mod_craft_ui_3 = (function()
  local CraftUI = {
      esx = nil,
      resourceName = nil,
      playerCache = nil,
      guaranteeCache = nil,
      payload = nil,
      access = nil,
      notifier = nil,
      isOpen = false,
      currentCraftTableIndex = nil,
      currentCraftTable = nil,
      sharedVaultEnabled = false,
      sharedVaultCounts = {},
  }
  
  local REASON_MESSAGES = {
      already_crafting = 'กำลังคราฟอยู่',
      already_has_result = 'คุณมีไอเทมนี้อยู่แล้ว',
      cannot_carry_fail = 'ช่องเก็บของไม่พอสำหรับไอเทมที่ได้รับเมื่อล้มเหลว',
      cannot_carry_result = 'ช่องเก็บของไม่พอสำหรับไอเทมที่จะได้รับ',
      invalid_category = 'หมวดคราฟไม่ถูกต้อง',
      invalid_recipe = 'สูตรคราฟไม่ถูกต้อง',
      missing_bonus = 'ไอเทมเพิ่มเรทไม่เพียงพอ',
      missing_equipment = 'อุปกรณ์ที่ต้องใช้ไม่เพียงพอ',
      missing_material = 'วัตถุดิบไม่เพียงพอ',
      missing_money = 'เงินไม่เพียงพอ',
      no_access = 'คุณไม่มีสิทธิ์ใช้โต๊ะคราฟนี้',
      not_open = 'ยังไม่ได้เปิดโต๊ะคราฟ',
      roll_failed = 'คำนวณผลคราฟไม่สำเร็จ',
      server_error = 'ระบบคราฟขัดข้อง',
  }
  
  REASON_MESSAGES.too_far = 'คุณอยู่ไกลโต๊ะคราฟเกินไป'
  REASON_MESSAGES.shared_vault_unavailable = 'ไม่พบระบบตู้เซฟ'
  
  local function getReasonMessage(reason)
      return REASON_MESSAGES[reason] or 'ไม่สามารถคราฟได้'
  end
  
  local function getActiveSharedCounts()
      return CraftUI.sharedVaultEnabled and CraftUI.sharedVaultCounts or nil
  end
  
  local function sendCategoryUpdate(categoryId)
      if not CraftUI.isOpen or not CraftUI.currentCraftTable or not categoryId then
          return
      end
  
      SendNUIMessage({
          action = 'updateCraftCategory',
          category = CraftUI.payload.getCategory(categoryId, CraftUI.guaranteeCache.get(), getActiveSharedCounts()),
          cash = CraftUI.payload.getBalances().cash,
          black = CraftUI.payload.getBalances().black,
          sharedVaultEnabled = CraftUI.sharedVaultEnabled,
      })
  end
  
  local function loadSharedVaultCounts(categoryId, cb)
      CraftUI.esx.TriggerServerCallback(CraftUI.resourceName .. ':getSharedVaultCounts', function(result)
          if not result or not result.ok then
              cb(false, result and result.reason or 'server_error')
              return
          end
  
          CraftUI.sharedVaultCounts = type(result.counts) == 'table' and result.counts or {}
          cb(true)
      end, {
          tableIndex = CraftUI.currentCraftTableIndex,
          categoryId = categoryId,
      })
  end
  
  function CraftUI.init(options)
      CraftUI.esx = options.esx
      CraftUI.resourceName = options.resourceName
      CraftUI.playerCache = options.playerCache
      CraftUI.guaranteeCache = options.guaranteeCache
      CraftUI.payload = options.payload
      CraftUI.access = options.access
      CraftUI.notifier = options.notifier
  end
  
  function CraftUI.isCraftOpen()
      return CraftUI.isOpen
  end
  
  function CraftUI.close()
      if not CraftUI.isOpen then
          return
      end
  
      CraftUI.isOpen = false
      CraftUI.currentCraftTableIndex = nil
      CraftUI.currentCraftTable = nil
      CraftUI.sharedVaultEnabled = false
      CraftUI.sharedVaultCounts = {}
      SetNuiFocus(false, false)
      SendNUIMessage({
          action = 'closeCraftTable',
      })
  end
  
  function CraftUI.open(index, craftTable)
      if CraftUI.isOpen then
          return
      end
  
      if not CraftUI.access.canUseCraftTable(craftTable) then
          CraftUI.notifier.push({
              title = 'ไม่สามารถใช้งานได้',
              description = 'คุณไม่มีสิทธิ์ใช้โต๊ะคราฟนี้',
              type = 'warning',
              duration = 4000,
          })
          return
      end
  
      if not CraftUI.guaranteeCache.isLoaded() then
          CraftUI.guaranteeCache.request()
      end
  
      CraftUI.playerCache.refresh()
  
      CraftUI.isOpen = true
      CraftUI.currentCraftTableIndex = index
      CraftUI.currentCraftTable = craftTable
      CraftUI.sharedVaultEnabled = false
      CraftUI.sharedVaultCounts = {}
  
      SetNuiFocus(true, true)
      SendNUIMessage({
          action = 'openCraftTable',
          craftTable = CraftUI.payload.getCraftTable(index, craftTable, CraftUI.guaranteeCache.get()),
          sharedVaultEnabled = false,
      })
  end
  
  function CraftUI.setGuaranteeCache(progressMap)
      CraftUI.guaranteeCache.set(progressMap)
  
      if CraftUI.isOpen and CraftUI.currentCraftTableIndex and CraftUI.currentCraftTable then
          SendNUIMessage({
              action = 'updateGuaranteeProgress',
              guaranteeProgress = CraftUI.guaranteeCache.get(),
          })
      end
  end
  
  function CraftUI.registerCallbacks()
      RegisterNUICallback('closeCraftTable', function(_, cb)
          CraftUI.close()
          cb('ok')
      end)
  
      RegisterNUICallback('close', function(_, cb)
          CraftUI.close()
          cb('ok')
      end)
  
      RegisterNUICallback('loadCraftCategory', function(data, cb)
          local categoryId = tonumber(data and data.categoryId)
          local tableIndex = tonumber(data and data.tableIndex)
  
          if not CraftUI.isOpen
              or not CraftUI.currentCraftTable
              or not categoryId
              or tableIndex ~= CraftUI.currentCraftTableIndex
          then
              cb({ ok = false })
              return
          end
  
          if not CraftUI.payload.isCategoryAllowed(CraftUI.currentCraftTable, categoryId) then
              cb({ ok = false })
              return
          end
  
          CraftUI.playerCache.refresh()
  
          if CraftUI.sharedVaultEnabled then
              loadSharedVaultCounts(categoryId, function(ok)
                  if not ok then
                      cb({ ok = false })
                      return
                  end
  
                  cb({
                      ok = true,
                      category = CraftUI.payload.getCategory(categoryId, CraftUI.guaranteeCache.get(), getActiveSharedCounts()),
                  })
              end)
              return
          end
  
          cb({
              ok = true,
              category = CraftUI.payload.getCategory(categoryId, CraftUI.guaranteeCache.get(), getActiveSharedCounts()),
          })
      end)
  
      RegisterNUICallback('toggleSharedVault', function(data, cb)
          local categoryId = tonumber(data and data.categoryId)
          local enabled = data and data.enabled == true
  
          if not CraftUI.isOpen or not CraftUI.currentCraftTable or not categoryId then
              cb({ ok = false, reason = 'not_open' })
              return
          end
  
          if not enabled then
              CraftUI.sharedVaultEnabled = false
              CraftUI.sharedVaultCounts = {}
  
              cb({
                  ok = true,
                  enabled = false,
                  category = CraftUI.payload.getCategory(categoryId, CraftUI.guaranteeCache.get()),
              })
              return
          end
  
          loadSharedVaultCounts(categoryId, function(ok, reason)
              if not ok then
                  CraftUI.notifier.push({
                      title = 'ไม่สามารถใช้งานตู้เซฟได้',
                      description = getReasonMessage(reason or 'server_error'),
                      type = 'error',
                      duration = 4000,
                  })
  
                  cb({ ok = false, reason = reason or 'server_error' })
                  return
              end
  
              CraftUI.sharedVaultEnabled = true
  
              cb({
                  ok = true,
                  enabled = true,
                  category = CraftUI.payload.getCategory(categoryId, CraftUI.guaranteeCache.get(), CraftUI.sharedVaultCounts),
              })
          end)
      end)
  
      RegisterNUICallback('startCraft', function(data, cb)
          if not CraftUI.isOpen or not CraftUI.currentCraftTable then
              cb({ ok = false, reason = 'not_open' })
              return
          end
  
          data = type(data) == 'table' and data or {}
          data.tableIndex = CraftUI.currentCraftTableIndex
          data.useSharedVault = CraftUI.sharedVaultEnabled
  
          CraftUI.esx.TriggerServerCallback(CraftUI.resourceName .. ':startCraft', function(result)
              if not result or not result.ok then
                  CraftUI.notifier.push({
                      title = 'ไม่สามารถคราฟได้',
                      description = getReasonMessage(result and result.reason or 'server_error'),
                      type = 'error',
                      duration = 4000,
                  })
              end
  
              cb(result or { ok = false, reason = 'server_error' })
          end, data)
      end)
  end
  
  function CraftUI.handleCraftFinished(result)
      CraftUI.playerCache.refresh()
  
      if result and result.counts then
          CraftUI.playerCache.applyCounts(result.counts)
      end
  
      if result and result.ok == false then
          CraftUI.notifier.push({
              title = 'ยกเลิกการคราฟ',
              description = getReasonMessage(result.reason),
              type = 'error',
              duration = 4000,
          })
  
          if CraftUI.isOpen and CraftUI.currentCraftTable and result.categoryId then
              sendCategoryUpdate(result.categoryId)
          end
  
          SendNUIMessage({
              action = 'craftFinished',
              result = result,
          })
          return
      end
  
      if CraftUI.isOpen and CraftUI.currentCraftTable and result and result.categoryId then
          if CraftUI.sharedVaultEnabled and type(result.vaultCounts) == 'table' then
              for itemName, count in pairs(result.vaultCounts) do
                  CraftUI.sharedVaultCounts[itemName] = count
              end
          end
  
          sendCategoryUpdate(result.categoryId)
      end
  
      SendNUIMessage({
          action = 'craftFinished',
          result = result or {},
      })
  end
  
  return CraftUI
end)()

local __mod_craft_world_4 = (function()
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
end)()

local __mod_guarantee_cache_5 = (function()
  local GuaranteeCache = {
      resourceName = nil,
      loaded = false,
      progress = {},
  }
  
  function GuaranteeCache.init(resourceName)
      GuaranteeCache.resourceName = resourceName
  end
  
  function GuaranteeCache.request()
      if GuaranteeCache.resourceName then
          TriggerServerEvent(GuaranteeCache.resourceName .. ':requestGuaranteeCache')
      end
  end
  
  function GuaranteeCache.set(progressMap)
      GuaranteeCache.progress = type(progressMap) == 'table' and progressMap or {}
      GuaranteeCache.loaded = true
  end
  
  function GuaranteeCache.get()
      return GuaranteeCache.progress
  end
  
  function GuaranteeCache.isLoaded()
      return GuaranteeCache.loaded
  end
  
  return GuaranteeCache
end)()

local __mod_interaction_6 = (function()
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
end)()

local __mod_notifier_7 = (function()
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
  
  function Notifier.push(options)
      if GetResourceState('nc_notify') ~= 'started' then
          Notifier.debug('nc_notify is not started')
          return
      end
  
      exports.nc_notify:PushNotification({
          title = options.title or 'แจ้งเตือน',
          description = options.description or '',
          type = options.type or 'info',
          duration = options.duration or 4000,
      })
  end
  
  return Notifier
end)()

local __mod_player_cache_8 = (function()
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
end)()

local ESX = exports["es_extended"]:getSharedObject()
local resourceName = GetCurrentResourceName()

local Access = __mod_access_0
local CraftPayload = __mod_craft_payload_1
local CraftSound = __mod_craft_sound_2
local CraftUI = __mod_craft_ui_3
local CraftWorld = __mod_craft_world_4
local GuaranteeCache = __mod_guarantee_cache_5
local Interaction = __mod_interaction_6
local Notifier = __mod_notifier_7
local PlayerCache = __mod_player_cache_8

local OPEN_KEY = 38 -- E

Notifier.init(resourceName)
PlayerCache.init(ESX)
GuaranteeCache.init(resourceName)
Access.init(PlayerCache)
CraftPayload.init(PlayerCache)
CraftWorld.init(Notifier)
CraftSound.init(resourceName)
CraftUI.init({
    esx = ESX,
    resourceName = resourceName,
    playerCache = PlayerCache,
    guaranteeCache = GuaranteeCache,
    payload = CraftPayload,
    access = Access,
    notifier = Notifier,
})
Interaction.init({
    access = Access,
    world = CraftWorld,
    openCraftTable = CraftUI.open,
    isCraftOpen = CraftUI.isCraftOpen,
    openKey = OPEN_KEY,
})

CraftUI.registerCallbacks()
CraftSound.registerEvents()

RegisterNetEvent(resourceName .. ':setGuaranteeCache', function(progressMap)
    CraftUI.setGuaranteeCache(progressMap)
end)

RegisterNetEvent(resourceName .. ':craftFinished', function(result)
    CraftUI.handleCraftFinished(result)
end)

RegisterNetEvent('esx:playerLoaded', function(playerData)
    PlayerCache.refresh(playerData)
    SetTimeout(500, function()
        GuaranteeCache.request()
    end)
end)

RegisterNetEvent('esx:setPlayerData', function()
    SetTimeout(0, function()
        PlayerCache.refresh()
    end)
end)

CreateThread(function()
    Wait(1000)
    PlayerCache.refresh()
    GuaranteeCache.request()
end)

CreateThread(function()
    CraftWorld.setup(Config.craftTable)
    Interaction.start(Config.craftTable)
end)

RegisterCommand('qubit_close_crafting', function()
    CraftUI.close()
end, false)

RegisterKeyMapping('qubit_close_crafting', 'Close Qubit Crafting', 'keyboard', 'ESCAPE')

AddEventHandler('onResourceStart', function(resource)
    if resource == "qubit_drawtext" then
        Wait(500)
        Interaction.restart()
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then
        return
    end

    Interaction.stop()
    CraftUI.close()
    CraftWorld.cleanup()
end)
