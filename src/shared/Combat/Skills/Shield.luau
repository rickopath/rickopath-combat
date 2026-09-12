--!strict
-- Applies a StatusEffect to the player.
-- Creates a 50% damage reduction StatusEffect.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)
local DamageType = require(ReplicatedStorage.Shared.Combat.DamageType)
local StatusEffectBuilders = require(ReplicatedStorage.Shared.Combat.StatusEffectBuilders)

type SkillContext = SkillModule.SkillContext

local ID = "Shield"
local SHIELD_DURATION_SECONDS = 5

-- built ONCE, reused every activation - a StatusEffectDefinition is immutable data. 0.5 multiplier
-- = 50% Physical damage reduction while active; OnExpire (built into ResistanceModifier) restores
-- whatever resistance value was set before this ran, no manual bookkeeping needed here
local SHIELD = StatusEffectBuilders.ResistanceModifier("Shielded", DamageType.Physical, 0.5, SHIELD_DURATION_SECONDS)

local Shield = SkillModule.extend("Shield")

-- Luau strict-mode class assignment.
;(Shield :: any).Activate = function(self: SkillModule.Skill): boolean
	local combatant = self.Context.Combatant
	if combatant.ApplyStatusEffect then -- server only
		combatant:ApplyStatusEffect(SHIELD)
	end

	self.Context.Presentation.PlayEffect("Shield_Cast", { Target = self.Context.Owner })

	return true
end

SkillRegistry.Register(ID, function(context: SkillContext): SkillModule.Skill
	return Shield.new({
		Id = ID,
		DisplayName = "Shield",
		Cooldown = 10,
		Costs = { { ResourceId = "Mana", Amount = 20 } },
	}, context)
end)

return Shield
