--!strict

local Types = require(script.Parent.Types)

type HitResult = Types.HitResult
type AttackRequest = Types.AttackRequest

export type Config = {
	RewindBufferDepthSeconds: number,
	RewindSampleIntervalSeconds: number,
	MaxRewindSeconds: number,
	InterpolationDelaySeconds: number,

	MaxLatencyToleranceStuds: number,
	MaxCharacterSpeed: number, 

	MinSweepSubSteps: number,
	MaxSweepSubSteps: number,
	MaxDegreesPerSweepSubStep: number, 

	HitResultPoolInitialSize: number,
	HitResultPoolGrowthIncrement: number,
	HitResultPoolMaxSize: number,

	HitRegistryTTLSeconds: number,
	HitRegistryCleanupIntervalSeconds: number,
	ClientReconcileTimeoutSeconds: number,

	DebugDrawForceOn: boolean,
	DebugDrawAllowInStudio: boolean,

	AliveFolderTag: string,

	OnApplyDamage: (attacker: Player, hit: Types.HitResult) -> (),
	IsAttackAllowed: (player: Player, request: Types.AttackRequest) -> boolean,
}

local Default: Config = {
	RewindBufferDepthSeconds = 0,
	RewindSampleIntervalSeconds = 0,
	MaxRewindSeconds = 0,
	InterpolationDelaySeconds = 0,

	MaxLatencyToleranceStuds = 0,
	MaxCharacterSpeed = 0,

	MinSweepSubSteps = 1,
	MaxSweepSubSteps = 12,
	MaxDegreesPerSweepSubStep = 15, 

	HitResultPoolInitialSize = 32,
	HitResultPoolGrowthIncrement = 16,
	HitResultPoolMaxSize = 256,

	HitRegistryTTLSeconds = 0,
	HitRegistryCleanupIntervalSeconds = 1,
	ClientReconcileTimeoutSeconds = 1,

	DebugDrawForceOn = false,
	DebugDrawAllowInStudio = true,

	AliveFolderTag = "HitboxAliveFolder",

	OnApplyDamage = function(_attacker: Player, _hit: HitResult) end,
	IsAttackAllowed = function(_player: Player, _request: AttackRequest): boolean
		return true
	end,
}

return Default
