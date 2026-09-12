--!strict

local Types = require(script.Parent.Types)

export type Config = {
	CombatantTickInterval: number,
	MovementProbeRadius: number,
	MovementReconcileTimeoutSeconds: number,
	SnapshotBroadcastInterval: number, 
	SnapshotReplicationRadius: number?,
	DefaultMovesetId: string?,
	DefaultCombatantDefinition: Types.CombatantDefinition?,
	MirrorHealthToHumanoid: boolean?,
	OnCombatantDied: (model: Model, source: Model?) -> (),
}

local Default: Config = {
	CombatantTickInterval = 0,
	MovementProbeRadius = 0,
	MovementReconcileTimeoutSeconds = 1,
	SnapshotBroadcastInterval = 0,
	SnapshotReplicationRadius = nil,
	DefaultMovesetId = nil,
	DefaultCombatantDefinition = nil,
	MirrorHealthToHumanoid = nil,
	OnCombatantDied = function(_model: Model, _source: Model?) end,
}

return Default
