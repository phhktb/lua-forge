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
