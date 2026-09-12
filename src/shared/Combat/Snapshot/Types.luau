--!strict

-- wire-friendly mirror of Combat/Types.CombatantSnapshot, plus a Model field the other one doesn't
-- need - a broadcast batches every tracked combatant into one packet, so each entry has to say
-- whose stats these actually are
export type ResourceSnapshot = {
	Current: number,
	Max: number,
}

export type StatusEffectSnapshot = {
	Stacks: number,
	ExpiresAt: number,
}

export type CombatantSnapshotEntry = {
	Model: Model,
	Health: number,
	MaxHealth: number,
	Resources: { [string]: ResourceSnapshot },
	StatusEffects: { [string]: StatusEffectSnapshot },
	Team: string?,
	IsInvulnerable: boolean,
}

return {}
