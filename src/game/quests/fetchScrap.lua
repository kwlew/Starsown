--- The Hub elder's starter quest -- a fetch quest against the most common
-- gathered material, so it's completable from a single early run.
return {
    id = "fetchScrap",
    objective = { type = "collect", item = "scrap", count = 10 },
    reward = { xp = { skill = "foraging", amount = 50 }, currency = 20,
               items = { { id = "core", count = 1 } } },
}
