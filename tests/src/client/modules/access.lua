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
