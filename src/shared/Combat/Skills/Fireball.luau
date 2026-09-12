--!strict
-- Projectile skill example.
-- 
-- Projectiles are server-driven.
-- The client's `Activate` function triggers local VFX.
-- The server spawns the projectile, updates it, and broadcasts hits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)
local DamageType = require(ReplicatedStorage.Shared.Combat.DamageType)
local Trajectory = require(ReplicatedStorage.Shared.Combat.Trajectory)
local StatusEffectBuilders = require(ReplicatedStorage.Shared.Combat.StatusEffectBuilders)
local HitboxTypes = require(ReplicatedStorage.Shared.Hitbox.Types)

type SkillContext = SkillModule.SkillContext
type HitboxConfig = HitboxTypes.HitboxConfig

local ID = "Fireball"

-- a real game-content damage type, not one of the two the framework itself registers - resistances
-- keyed by "Fire" work exactly like resistances keyed by "Physical" the instant this call runs,
-- nothing else needs to know about it ahead of time
local FIRE = "Fire"
DamageType.Register({ Id = FIRE })

local HITBOX_CONFIG: HitboxConfig = {
	Id = ID,
	Kind = "Projectile",
	Shape = "Capsule",
	Radius = 1,
	AttachOffset = CFrame.new(),
	MaxTargetsPerSwing = 3,
	FriendlyFire = false,
}

-- built ONCE, reused every hit - a StatusEffectDefinition is immutable data, no reason to
-- construct a fresh one per hit. see APIReference.luau's Status Effects section
local BURNING = StatusEffectBuilders.DamageOverTime("Burning", FIRE, 3, 4, "Refresh")

local DAMAGE_SPEC = {
	DamageType = FIRE,
	Amount = 15,
	-- server only, fires once per confirmed hit target. `helpers` is CombatDamageBridge's
	-- OnHitHelpers - the sanctioned way to reach Presentation from OnHit without this file ever
	-- hardcoding a ServerScriptService path itself (this file is SHARED, required on the client
	-- too, where ServerScriptService doesn't exist at all)
	OnHit = function(target: any, _attacker: Player, helpers): ()
		target:ApplyStatusEffect(BURNING)
		-- default (no options): broadcasts to everyone, nobody predicted "the victim caught fire"
		-- locally the way the caster's own cast VFX would be
		helpers.PlayEffect("Fireball_Impact", { Target = target.Model })
	end,
}

local RANGE = 60
local ARC_HEIGHT = 8
local FLIGHT_DURATION = 0.6
local MAX_LIFETIME = 3

local Fireball = SkillModule.extend("Fireball")

-- Luau strict-mode class assignment.
;(Fireball :: any).Activate = function(self: SkillModule.Skill): boolean
	local hitbox = self.Context.Hitbox
	local player = self.Context.Player
	local origin = self.Context.Owner:GetPivot() * CFrame.new(0, 2, -2)
	local forward = origin.LookVector
	local p0 = origin.Position
	local p2 = p0 + forward * RANGE
	local p1 = p0 + forward * (RANGE * 0.5) + Vector3.new(0, ARC_HEIGHT, 0)
	local path = Trajectory.QuadraticBezier(p0, p1, p2)

	if hitbox.SpawnProjectileAlongPath and player then -- server only
		hitbox.SpawnProjectileAlongPath(player, self.Id, HITBOX_CONFIG, DAMAGE_SPEC, path, FLIGHT_DURATION, MAX_LIFETIME)
	end
	return true
end

SkillRegistry.Register(ID, function(context: SkillContext): SkillModule.Skill
	context.Hitbox.RegisterWeapon(ID, HITBOX_CONFIG, DAMAGE_SPEC)
	return Fireball.new({
		Id = ID,
		DisplayName = "Fireball",
		Cooldown = 1.5,
		Costs = { { ResourceId = "Mana", Amount = 20 } },
	}, context)
end)

return Fireball
