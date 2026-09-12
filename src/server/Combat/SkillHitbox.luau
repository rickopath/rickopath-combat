--!strict

-- thin wrapper a skill's Activate actually touches - a skill should NEVER reach into AliveRegistry/
-- RewindBuffer/SweepResolver/raw Net directly, just this. server half of a realm-split pair (see
-- client/Combat/SkillHitbox.luau) - one shared file branching on realm isn't even possible here,
-- HitboxServer lives under ServerScriptService which straight up doesn't exist on the client
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HitboxTypes = require(ReplicatedStorage.Shared.Hitbox.Types)
local HitboxServer = require(ServerScriptService.Server.Hitbox.HitboxServer)
local CombatDamageBridge = require(script.Parent.CombatDamageBridge)

type HitboxConfig = HitboxTypes.HitboxConfig
type DamageSpec = CombatDamageBridge.DamageSpec

-- weaponId -> the skill id that owns it, so IsAttackAllowed (CombatServer.luau) can actually find
-- the attacker's equipped Skill for a given weapon and enforce its cost/cooldown gate - without
-- this map that gate has nothing to look up and just has to trust the client, which we don't
local skillIdByWeaponId: { [string]: string } = {}

local SkillHitbox = {}

function SkillHitbox.RegisterWeapon(skillId: string, hitboxConfig: HitboxConfig, damageSpec: DamageSpec): ()
	HitboxServer.RegisterWeapon(hitboxConfig)
	CombatDamageBridge.RegisterWeaponDamage(hitboxConfig.Id, damageSpec, hitboxConfig.FriendlyFire)
	skillIdByWeaponId[hitboxConfig.Id] = skillId
end

function SkillHitbox.SpawnProjectile(
	attacker: Player,
	skillId: string,
	hitboxConfig: HitboxConfig,
	damageSpec: DamageSpec,
	initialCFrame: CFrame,
	velocity: Vector3,
	maxLifetime: number
): ()
	CombatDamageBridge.RegisterWeaponDamage(hitboxConfig.Id, damageSpec, hitboxConfig.FriendlyFire)
	skillIdByWeaponId[hitboxConfig.Id] = skillId
	HitboxServer.SpawnProjectile(attacker, hitboxConfig, initialCFrame, velocity, maxLifetime)
end

function SkillHitbox.SpawnProjectileAlongPath(
	attacker: Player,
	skillId: string,
	hitboxConfig: HitboxConfig,
	damageSpec: DamageSpec,
	path: (t: number) -> CFrame,
	duration: number,
	maxLifetime: number
): ()
	CombatDamageBridge.RegisterWeaponDamage(hitboxConfig.Id, damageSpec, hitboxConfig.FriendlyFire)
	skillIdByWeaponId[hitboxConfig.Id] = skillId
	HitboxServer.SpawnProjectileAlongPath(attacker, hitboxConfig, path, duration, maxLifetime)
end

function SkillHitbox.GetSkillIdForWeapon(weaponId: string): string?
	return skillIdByWeaponId[weaponId]
end

return SkillHitbox
