--- The Hub blacksmith's stock (see game/npcs/blacksmith.lua): buys the two
-- common gathered materials, sells the one weapon in the game so far.
return {
    id = "blacksmithWares",
    sell = { { id = "core", price = 5 }, { id = "scrap", price = 1 } },
    buy  = { { id = "ironSword", price = 40 } },
}
