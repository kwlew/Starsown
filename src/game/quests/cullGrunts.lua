--- The Hub warden's quest -- thin out the grunts pressing in from the
-- Wastes. `enemy` narrows checkObjective's count to just this type; a
-- future kill quest naming a different enemy (or none, for "kill anything")
-- reuses the same objective.type without any engine change.
return {
    id = "cullGrunts",
    objective = { type = "kill", enemy = "grunt", count = 5 },
    reward = { xp = { skill = "combat", amount = 40 }, currency = 15 },
}
