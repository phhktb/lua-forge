local ESX = exports["es_extended"]:getSharedObject()
local resourceName = GetCurrentResourceName()

local Access = require('modules.access')
local CraftPayload = require('modules.craft_payload')
local CraftSound = require('modules.craft_sound')
local CraftUI = require('modules.craft_ui')
local CraftWorld = require('modules.craft_world')
local GuaranteeCache = require('modules.guarantee_cache')
local Interaction = require('modules.interaction')
local Notifier = require('modules.notifier')
local PlayerCache = require('modules.player_cache')

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
