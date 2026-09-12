--!strict

-- pure types, no runtime logic, no requires. every other module in this library leans on this file
-- without risking a require cycle - keep it that way, don't sneak logic in here

export type HitboxShape = "Box" | "Capsule"
export type AttackKind = "Melee" | "Hitscan" | "Projectile" | "Radius"

export type HitboxConfig = {
	Id: string,
	Kind: AttackKind,
	Shape: HitboxShape,
	HalfExtents: Vector3?, -- box only
	Radius: number?, -- capsule/spherecast radius
	CapsuleLength: number?, -- capsule only, currently informational (spherecast doesn't need segment length)
	AttachOffset: CFrame,
	MaxTargetsPerSwing: number,
	FriendlyFire: boolean,
}

export type MotionSample = {
	T: number, -- seconds since swing start
	CFrame: CFrame, -- world space hitbox pose at T
}

export type AttackRequest = {
	WeaponId: string,
	Kind: AttackKind,
	SequenceId: number, -- monotonic per player+weapon, rejects replay/out of order
	ClientTimestamp: number,
	Motion: { MotionSample }?, -- melee only
	Origin: CFrame?, -- hitscan / radius / projectile spawn pose
	MaxDistance: number?, -- hitscan only
	Velocity: Vector3?, -- projectile only
}

export type HitResult = {
	Target: Model,
	HitPart: BasePart,
	Point: Vector3,
	Normal: Vector3,
	TOI: number, -- 0..1 fraction into the swing, 0 for stationary/radius kind
	SubStepIndex: number, -- 0 for stationary/radius kind
	Distance: number,
	-- caller-stamped - Hitbox itself doesn't know or care what's in here. HitboxServer sets it to the
	-- weaponId right before calling Config.OnApplyDamage, so a damage-agnostic HitResult can still
	-- carry "which weapon actually did this" through to whatever's consuming OnApplyDamage, no
	-- per-attacker side-cache needed upstream. reset to nil on pool return, same as every other field -
	-- don't let a stale Meta from the last checkout leak into someone else's hit
	Meta: any?,
}

export type AttackResult = {
	SequenceId: number,
	Hits: { HitResult },
	ServerTimestamp: number,
}

export type QueryFilter = {
	-- ExcludeInstances/IncludeInstances supersede the old FilterType+FilterDescendantsInstances combo.
	-- normally you only ever set one of the two, not both
	ExcludeInstances: { Instance }?,
	IncludeInstances: { Instance }?,
	MaxParts: number?,
	RespectCanCollide: boolean?, -- default false, hurtboxes shouldn't need CanCollide
	CollisionGroup: string?,
}

export type SweepParams = {
	Shape: HitboxShape,
	HalfExtents: Vector3?,
	Radius: number?,
	From: CFrame,
	To: CFrame,
	Filter: QueryFilter,
}

export type PoseSample = {
	Timestamp: number,
	Parts: { [string]: CFrame }, -- keyed by hitbox part name, root included, not just root
}

export type RewindResult = {
	Found: boolean,
	Pose: { [string]: CFrame },
	ClampedToOldest: boolean,
	ClampedToNewest: boolean,
}

export type PoolHandle<T> = {
	Checkout: (self: PoolHandle<T>) -> T,
	Return: (self: PoolHandle<T>, item: T) -> (),
	Prewarm: (self: PoolHandle<T>, count: number) -> (),
	InUseCount: (self: PoolHandle<T>) -> number,
}

return {}
