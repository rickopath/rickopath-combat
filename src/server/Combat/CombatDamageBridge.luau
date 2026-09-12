--!strict

-- bridges Config.OnApplyDamage (Hitbox is deliberately damage-agnostic, a HitResult carries no
-- weapon identity of its own) to a registered per-weapon DamageSpec, using HitResult.Meta - stamped
-- by HitboxServer with the weaponId right before it calls OnApplyDamage - to find the right spec.
-- no per-attacker cache, no ordering assumptions, the weapon id just travels WITH the hit itself, so
-- this works identically for Melee/Hitscan/Radius (resolved synchronously off one AttackRequest) and
-- Projectile (resolved ticks later, maybe after the same attacker's already fired several more shots
-- of a totally different spec). that used to be a genuine race - a per-attacker "last weapon id"
-- cache getting clobbered by a second in-flight projectile - fixed by just threading Meta through
-- instead of guessing which weapon fired based on whoever asked last
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitboxTypes = require(ReplicatedStorage.Shared.Hitbox.Types)
local CombatantRegistry = require(script.Parent.CombatantRegistry)
local Knockback = require(script.Parent.Knockback)
local PresentationServer = require(script.Parent.PresentationServer)

type HitResult = HitboxTypes.HitResult

-- who receives a PlayEffect call fired from OnHit. omit entirely and it broadcasts to literally
-- everyone (the sane default here - nobody predicted "the victim got hit" locally the way a caster
-- predicts their own swing, so there's no caster copy to avoid doubling up). Only takes priority
-- over ExcludeCaster if both are somehow set - pick one
export type PlayEffectOptions = {
	ExcludeCaster: boolean?,
	Only: { Player }?,
}

-- the sanctioned way OnHit reaches server-only helpers - Knockback and PresentationServer both
-- live under ServerScriptService, and Skills/*.luau is SHARED (required on the client too, where
-- ServerScriptService doesn't exist) so OnHit can never safely require them directly itself. this
-- file already IS server-only and already owns the one call site that invokes OnHit, so it's the
-- correct place to resolve them once and hand a safe, capability-scoped table down instead
export type OnHitHelpers = {
	ApplyKnockback: (character: Model, direction: Vector3, speed: number) -> (),
	PlayEffect: (effectId: string, params: any, options: PlayEffectOptions?) -> (),
}

export type DamageSpec = {
	DamageType: string,
	Amount: number,
	-- fires only when damage actually applies - skipped for a friendly-fire-blocked hit. this is how
	-- Fireball applies Burning on hit without this file needing to know what "Burning" even is,
	-- it's just handed a closure and told to run it. target is the victim's Combatant, typed `any`
	-- purely to dodge a require cycle with CombatantRegistry, not because we don't know the type.
	-- helpers is optional in the SIGNATURE only for old callers that don't declare it - Luau just
	-- ignores an argument a function doesn't ask for, it's always actually passed
	OnHit: ((target: any, attacker: Player, helpers: OnHitHelpers) -> ())?,
}

-- internal only - FriendlyFire gets derived from HitboxConfig by SkillHitbox.RegisterWeapon, it's
-- NEVER a caller-facing DamageSpec field, so whoever's authoring a skill doesn't have to think
-- about it twice, or even once
type StoredSpec = {
	DamageType: string,
	Amount: number,
	FriendlyFire: boolean,
	OnHit: ((target: any, attacker: Player, helpers: OnHitHelpers) -> ())?,
}

local damageSpecByWeaponId: { [string]: StoredSpec } = {}

local CombatDamageBridge = {}

function CombatDamageBridge.RegisterWeaponDamage(weaponId: string, spec: DamageSpec, friendlyFire: boolean): ()
	damageSpecByWeaponId[weaponId] = {
		DamageType = spec.DamageType,
		Amount = spec.Amount,
		FriendlyFire = friendlyFire,
		OnHit = spec.OnHit,
	}
end

-- installed as Config.OnApplyDamage
function CombatDamageBridge.Dispatch(attacker: Player, hit: HitResult): ()
	local weaponId = hit.Meta :: string?
	if not weaponId then
		return
	end

	local spec = damageSpecByWeaponId[weaponId]
	if not spec then
		return
	end

	local combatant = CombatantRegistry.Get(hit.Target)
	if not combatant then
		return
	end

	-- i-frames. same posture as the FriendlyFire check right below - the hit landed, it registered,
	-- DebugDraw drew it, the attacker's client saw it confirm. only the damage is skipped. note this
	-- returns BEFORE spec.OnHit runs, so an invulnerable target doesn't eat the Poison/Stun/whatever
	-- either - that's the intended read of "invulnerable", but if you want i-frames that only stop
	-- raw damage and still let procs through, move this check below the ApplyDamage call
	if combatant.IsInvulnerable then
		return
	end

	-- looked up once, used for both the FriendlyFire team check below and firing OnDamageDealt after
	-- a successful hit - an attacker with no Character or no registered Combatant (e.g. a
	-- projectile confirming after they've already left) just means neither reads anything from it
	local attackerCharacter = attacker.Character
	local attackerCombatant = if attackerCharacter then CombatantRegistry.Get(attackerCharacter) else nil

	-- hit detection already happened and it stands regardless - only the damage APPLICATION gets
	-- skipped here, for a non-FriendlyFire weapon landing on a same-team target
	if not spec.FriendlyFire then
		if attackerCombatant and attackerCombatant.Team and attackerCombatant.Team == combatant.Team then
			return
		end
	end

	local dealt = combatant:ApplyDamage(spec.Amount, spec.DamageType, attacker.Character)

	-- mirrors the `if dealt > 0` guard CombatantRegistry.ApplyDamage already applies before firing
	-- its own OnDamaged - a fully-resisted hit (dealt == 0) shouldn't tell a passive it dealt damage
	if dealt > 0 and attackerCombatant then
		attackerCombatant.OnDamageDealt:Fire(dealt, spec.DamageType, combatant)
	end

	if spec.OnHit then
		-- built fresh per hit, not once at module scope - it has to close over THIS hit's actual
		-- attacker so ExcludeCaster resolves to the right player, not whoever happened to be
		-- attacking the last time this ran. cheap: two closures and a table, same cost class as the
		-- Combatant lookup already happening above it
		local helpers: OnHitHelpers = {
			ApplyKnockback = Knockback.Apply,
			PlayEffect = function(effectId: string, params: any, options: PlayEffectOptions?)
				if options and options.Only then
					PresentationServer.PlayEffectTo(effectId, params, options.Only)
				elseif options and options.ExcludeCaster then
					PresentationServer.PlayEffectExcept(effectId, params, attacker)
				else
					PresentationServer.PlayEffect(effectId, params)
				end
			end,
		}
		spec.OnHit(combatant, attacker, helpers)
	end
end

return CombatDamageBridge
