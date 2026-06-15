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
