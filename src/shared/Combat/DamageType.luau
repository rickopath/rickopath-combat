--!strict

-- open registry, not a closed union like Hitbox's AttackKind - damage types are game content, they
-- need to grow every time a new skill ships, they shouldn't be gated on editing some shared enum file
local Types = require(script.Parent.Types)

export type DamageTypeDefinition = {
	Id: string,
	BypassResistance: boolean?, -- "true damage" semantics
}

local registry: { [string]: DamageTypeDefinition } = {}

local DamageType = {}

function DamageType.Register(definition: DamageTypeDefinition): ()
	registry[definition.Id] = definition
end

function DamageType.Get(id: string): DamageTypeDefinition?
	return registry[id]
end

-- pure function, no side effects - reused both inside Combatant:ApplyDamage and standalone (a UI
-- damage preview, say), keep it that way so it's safe to call from anywhere without consequence
function DamageType.ApplyResistance(baseAmount: number, damageType: Types.DamageTypeId, resistances: Types.ResistanceTable): number
	local definition = registry[damageType]
	if definition and definition.BypassResistance then
		return math.max(baseAmount, 0)
	end

	local multiplier = resistances[damageType]
	if multiplier == nil then
		multiplier = 1
	end

	return math.max(baseAmount * multiplier, 0)
end

DamageType.Physical = "Physical"
DamageType.True = "True"

DamageType.Register({ Id = DamageType.Physical })
DamageType.Register({ Id = DamageType.True, BypassResistance = true })

return DamageType
