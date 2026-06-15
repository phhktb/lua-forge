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
