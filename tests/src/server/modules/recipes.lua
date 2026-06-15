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
