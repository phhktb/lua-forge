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
