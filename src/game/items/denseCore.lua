--- A tougher cut of core than usual -- needs a bit of practice fighting to
-- know how to handle safely. The one item currently gated by a `requires`:
-- combat is the only skill anything grants XP for yet (see Play:collect),
-- so it's the only requirement actually reachable through real play today.
return { id = "denseCore", stack = 16, sides = 6, color = "energy",
         requires = { skill = "combat", level = 2 } }
