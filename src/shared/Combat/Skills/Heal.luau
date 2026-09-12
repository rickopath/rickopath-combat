--!strict
-- Modifies the Combatant's health directly. 
-- 
-- The client handles VFX (`PlayEffect`). The server handles healing.
-- The check `if combatant.Heal then` ensures healing logic only runs on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)

type SkillContext = SkillModule.SkillContext

local ID = "Heal"
local HEAL_AMOUNT = 30

local Heal = SkillModule.extend("Heal")

-- Luau strict-mode class assignment.
;(Heal :: any).Activate = function(self: SkillModule.Skill): boolean
	local combatant = self.Context.Combatant
	if combatant.Heal then -- server only
		combatant:Heal(HEAL_AMOUNT, self.Context.Owner)
	end

	-- runs on BOTH realms same as any other skill's cast VFX - client gets instant local feedback,
	-- server broadcasts to everyone else. this is the only thing the client half of this skill does
	self.Context.Presentation.PlayEffect("Heal_Cast", { Target = self.Context.Owner })

	return true
end

SkillRegistry.Register(ID, function(context: SkillContext): SkillModule.Skill
	return Heal.new({
		Id = ID,
		DisplayName = "Heal",
		Cooldown = 6,
		Costs = { { ResourceId = "Mana", Amount = 25 } },
	}, context)
end)

return Heal
