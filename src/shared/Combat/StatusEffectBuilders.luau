--!strict

-- toolkit for the status effect patterns that show up over and over - a new effect should be a
-- one-liner, not another hand-rolled OnApply/OnTick/OnExpire closure every damn time. all built on
-- Combatant's already-public ApplyDamage/Heal/SetResistance/GetResource, no new Combatant methods
local Types = require(script.Parent.Types)

type StatusEffectDefinition = Types.StatusEffectDefinition
type StackRule = Types.StackRule
type OnExpireCallback = ((combatant: any) -> ())?

local StatusEffectBuilders = {}

-- amountPerTick is per Config.CombatantTickInterval TICK, not per second - the real rate scales
-- with however often CombatantRegistry actually ticks. saying it here so nobody gets bit by it later
--
-- onExpire is optional and purely additive - every existing call site that doesn't pass one keeps
-- working exactly as before. it's the sanctioned way to get "run this when the effect wears off"
-- without abandoning the builder and hand-writing the whole definition table yourself
function StatusEffectBuilders.DamageOverTime(
	id: string,
	damageType: string,
	amountPerTick: number,
	duration: number,
	stackRule: StackRule,
	onExpire: OnExpireCallback
): StatusEffectDefinition
	return {
		Id = id,
		Duration = duration,
		MaxStacks = 999,
		StackRule = stackRule,
		OnTick = function(combatant: any, _dt: number)
			combatant:ApplyDamage(amountPerTick, damageType, nil)
		end,
		OnExpire = onExpire,
	}
end

function StatusEffectBuilders.HealOverTime(
	id: string,
	amountPerTick: number,
	duration: number,
	stackRule: StackRule,
	onExpire: OnExpireCallback
): StatusEffectDefinition
	return {
		Id = id,
		Duration = duration,
		MaxStacks = 999,
		StackRule = stackRule,
		OnTick = function(combatant: any, _dt: number)
			combatant:Heal(amountPerTick, nil)
		end,
		OnExpire = onExpire,
	}
end

-- temporarily overrides one damage type's resistance multiplier, puts the old value back on expiry.
-- previousByCombatant is keyed per-combatant with weak keys ON PURPOSE - this SAME definition table
-- gets shared across every combatant who picks up the buff, so a single shared upvalue would leak
-- one guy's prior value into some other guy's restore. learned that one the hard way, don't undo it
--
-- onExpire here COMPOSES with the resistance-restore logic, it doesn't replace it - your callback
-- always runs AFTER the resistance is already put back, never instead of that happening
function StatusEffectBuilders.ResistanceModifier(
	id: string,
	damageType: string,
	multiplier: number,
	duration: number,
	onExpire: OnExpireCallback
): StatusEffectDefinition
	local previousByCombatant: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

	return {
		Id = id,
		Duration = duration,
		MaxStacks = 1,
		StackRule = "Refresh",
		OnApply = function(combatant: any, _stacks: number)
			previousByCombatant[combatant] = combatant.Resistances[damageType] or 1
			combatant:SetResistance(damageType, multiplier)
		end,
		OnExpire = function(combatant: any)
			combatant:SetResistance(damageType, previousByCombatant[combatant] or 1)
			previousByCombatant[combatant] = nil
			if onExpire then
				onExpire(combatant)
			end
		end,
	}
end

-- hardcoded to Id "Stunned" - Skill.luau's base CanActivate checks this exact id, so it's the one
-- reserved name in the whole status effect space, don't reuse it for something unrelated. want a
-- differently-flavored "can't act" effect? still use this id, the mechanic (blocked activation) is
-- what matters, nobody cares what you call the particle effect on top of it
--
-- onExpire is your hook for "the stun just wore off, do something" - a UI re-enable, a "stun
-- broken" VFX, whatever. this is per-application: it fires for THIS specific stun expiring, not
-- every status effect on the combatant. for something coarser ("tell me any time anything expires
-- on this combatant"), Combatant.OnStatusEffectExpired already exists and works today - see
-- server/Docs/Tutorial.luau section 7
function StatusEffectBuilders.ActivationBlocker(duration: number, onExpire: OnExpireCallback): StatusEffectDefinition
	return {
		Id = "Stunned",
		Duration = duration,
		MaxStacks = 1,
		StackRule = "Refresh",
		OnExpire = onExpire,
	}
end

-- temporarily applies a generic stat modifier (CombatantRegistry.Combatant:AddStatModifier) and
-- removes it on expiry - the same OnApply/OnExpire shape as ResistanceModifier above, just for
-- the general stat system instead of the Resistances table specifically. uses the effect's own id
-- as the modifierId too - one status effect application is one modifier instance, that's the whole
-- relationship, no reason to make the caller track two ids for the price of one
function StatusEffectBuilders.StatModifier(
	id: string,
	statId: string,
	value: number,
	mode: "Add" | "Multiply",
	duration: number,
	onExpire: OnExpireCallback
): StatusEffectDefinition
	return {
		Id = id,
		Duration = duration,
		MaxStacks = 1,
		StackRule = "Refresh",
		OnApply = function(combatant: any, _stacks: number)
			combatant:AddStatModifier(statId, id, value, mode)
		end,
		OnExpire = function(combatant: any)
			combatant:RemoveStatModifier(statId, id)
			if onExpire then
				onExpire(combatant)
			end
		end,
	}
end

-- physics-authoritative movement lock (CombatantRegistry.Combatant:SetMovementEnabled) - see
-- MovementLock.luau for why this isn't just WalkSpeed=0. Id "Rooted" is a sane default, NOT a
-- reserved/enforced id the way ActivationBlocker's "Stunned" is - nothing else in the framework
-- checks for this name specifically, the mechanism here is entirely OnApply/OnExpire side effects
function StatusEffectBuilders.Root(duration: number, onExpire: OnExpireCallback): StatusEffectDefinition
	return {
		Id = "Rooted",
		Duration = duration,
		MaxStacks = 1,
		StackRule = "Refresh",
		OnApply = function(combatant: any, _stacks: number)
			combatant:SetMovementEnabled(false)
		end,
		OnExpire = function(combatant: any)
			combatant:SetMovementEnabled(true)
			if onExpire then
				onExpire(combatant)
			end
		end,
	}
end

return StatusEffectBuilders
