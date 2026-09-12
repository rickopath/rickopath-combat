--!strict

-- passives are NOT bolted onto Skill.extend's OOP hierarchy - a passive has no Activate, no
-- Cooldown, no Costs, forcing it through that machinery just to get four reaction hooks means
-- meaningless boilerplate on every single passive. this is the closure-factory shape instead,
-- same as everything else in this codebase except Skill.luau itself. reuses SkillContext's exact
-- shape though (Combatant/Owner/Player/Hitbox/Movement/Presentation) - a passive can still
-- legitimately want context.Presentation.PlayEffect ("shield block" VFX on OnDamageTaken, say),
-- no reason to invent a second context type for that
local SkillModule = require(script.Parent.Skill)

type SkillContext = SkillModule.SkillContext

export type PassiveDefinition = {
	Id: string,
	OnEquipped: ((context: SkillContext) -> ())?,
	OnUnequipped: ((context: SkillContext) -> ())?,
	-- fires off Combatant.OnDamaged (already exists) - this combatant took damage
	OnDamageTaken: ((context: SkillContext, amount: number, damageType: string, source: Model?) -> ())?,
	-- fires off the new Combatant.OnDamageDealt - this combatant's owner dealt damage to someone
	-- else. target is the victim's Combatant, typed `any` for the same require-cycle reason
	-- DamageSpec.OnHit's target parameter is
	OnDamageDealt: ((context: SkillContext, amount: number, damageType: string, target: any) -> ())?,
}

return {}
