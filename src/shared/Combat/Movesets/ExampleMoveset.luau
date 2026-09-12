--!strict

-- example content - one moveset bundling all five example skills, not one-per-class. there is no
-- class system in this framework (see APIReference.luau's Movesets section) - a moveset is just a
-- named list of skill ids, so shipping three class-flavored movesets would have quietly undermined
-- that point with the example content itself. delete/replace freely, nothing else references this
-- file by name - see Skills/{Punch,Dash,Fireball,Heal,Shield}.luau for what each id actually does
local Moveset = require(script.Parent.Parent.Moveset)

Moveset.Register({
	Id = "ExampleMoveset",
	SkillIds = { "Punch", "Dash", "Fireball", "Heal", "Shield" }, -- ORDER MATTERS: index -> key, see InputBindings.luau
})

return true
