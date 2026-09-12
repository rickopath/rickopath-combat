--!strict

-- pure types, no runtime logic, no requires. same job Hitbox/Types.luau does for that layer, just
-- one level up the stack

export type DamageTypeId = string
export type ResistanceTable = { [DamageTypeId]: number } -- multiplier, missing key means 1.0

export type ResourcePoolDefinition = {
	Id: string,
	Max: number,
	Initial: number?, -- defaults to Max
	RegenPerSecond: number?, -- nil/0 = no passive regen
	RegenDelayAfterSpendSeconds: number?, -- stamina style delay-then-regen
}

export type StackRule = "Refresh" | "Stack" | "Ignore"

-- hooks take `any` for the combatant param, not by choice really - the real Combatant type lives in
-- CombatantRegistry.luau (server only), and this file can't require that back without a cycle. so, any
export type StatusEffectDefinition = {
	Id: string,
	Duration: number, -- math.huge = permanent until RemoveStatusEffect
	MaxStacks: number,
	StackRule: StackRule,
	OnApply: ((combatant: any, stacks: number) -> ())?,
	OnStack: ((combatant: any, stacks: number) -> ())?,
	OnExpire: ((combatant: any) -> ())?,
	OnTick: ((combatant: any, dt: number) -> ())?,
}

export type ActiveStatusEffect = {
	Definition: StatusEffectDefinition,
	Stacks: number,
	ExpiresAt: number, -- workspace:GetServerTimeNow() based, server authoritative
}

export type CombatantDefinition = {
	MaxHealth: number,
	InitialHealth: number?,
	Resources: { ResourcePoolDefinition }?,
	Resistances: ResistanceTable?,
}

export type CombatantSnapshot = {
	Health: number,
	MaxHealth: number,
	Resources: { [string]: { Current: number, Max: number } },
	StatusEffects: { [string]: { Stacks: number, ExpiresAt: number } },
	Team: string?,
	IsInvulnerable: boolean,
}

return {}
