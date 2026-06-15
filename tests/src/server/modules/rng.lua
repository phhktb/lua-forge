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
