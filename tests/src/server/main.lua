local ESX = exports["es_extended"]:getSharedObject()
local resourceName = GetCurrentResourceName()

local CraftService = require('modules.craft_service')
local CraftSound = require('modules.craft_sound')
local GuaranteeService = require('modules.guarantee_service')
local GuaranteeStore = require('modules.guarantee_store')
local Identity = require('modules.identity')
local Inventory = require('modules.inventory')
local Notifier = require('modules.notifier')
local Recipes = require('modules.recipes')
local Rng = require('modules.rng')
local SharedVault = require('modules.shared_vault')

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
