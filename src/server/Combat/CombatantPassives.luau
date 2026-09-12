--!strict

-- server-only, mirrors CombatantSkills.luau's shape - OnEquipped fires immediately on Equip,
-- OnDamageTaken/OnDamageDealt wire automatically to the Combatant's OnDamaged/OnDamageDealt
-- signals (already exist), OnUnequipped fires and both connections drop on Unequip. no client-side
-- equivalent this round - passives react to server-authoritative combat events (damage
-- taken/dealt), same scope boundary DamageSpec.OnHit already has
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local PassiveRegistry = require(ReplicatedStorage.Shared.Combat.PassiveRegistry)
local PassiveSkillModule = require(ReplicatedStorage.Shared.Combat.PassiveSkill)
local CombatantRegistry = require(script.Parent.CombatantRegistry)
local SkillHitbox = require(script.Parent.SkillHitbox)
local PresentationFacade = require(script.Parent.PresentationFacade)

type SkillContext = SkillModule.SkillContext
type PassiveDefinition = PassiveSkillModule.PassiveDefinition

type EquippedPassive = {
	Definition: PassiveDefinition,
	Context: SkillContext,
	DamagedConn: any?,
	DamageDealtConn: any?,
}

local passivesByModel: { [Model]: { [string]: EquippedPassive } } = {}

local CombatantPassives = {}

function CombatantPassives.Equip(model: Model, passiveId: string): PassiveDefinition?
	local combatant = CombatantRegistry.Get(model)
	if not combatant then
		-- same silent-failure trap CombatantSkills.Equip already guards against - warn instead of
		-- letting this vanish quietly
		warn(
			string.format(
				"Combat: CombatantPassives.Equip(%s, %q) - no Combatant registered for this model yet, nothing equipped",
				model.Name,
				passiveId
			)
		)
		return nil
	end

	local context: SkillContext = {
		Combatant = combatant,
		Owner = model,
		Player = combatant.Player,
		Hitbox = SkillHitbox,
		Movement = nil,
		Presentation = PresentationFacade.Build(combatant),
	}

	local definition = PassiveRegistry.Create(passiveId, context)
	if not definition then
		return nil
	end

	local damagedConn = nil
	if definition.OnDamageTaken then
		damagedConn = combatant.OnDamaged:Connect(function(amount: number, damageType: string, source: Model?)
			(definition.OnDamageTaken :: any)(context, amount, damageType, source)
		end)
	end

	local damageDealtConn = nil
	if definition.OnDamageDealt then
		damageDealtConn = combatant.OnDamageDealt:Connect(function(amount: number, damageType: string, target: any)
			(definition.OnDamageDealt :: any)(context, amount, damageType, target)
		end)
	end

	local byId = passivesByModel[model]
	if not byId then
		byId = {}
		passivesByModel[model] = byId
	end
	byId[passiveId] = {
		Definition = definition,
		Context = context,
		DamagedConn = damagedConn,
		DamageDealtConn = damageDealtConn,
	}

	if definition.OnEquipped then
		definition.OnEquipped(context)
	end

	return definition
end

function CombatantPassives.Get(model: Model, passiveId: string): PassiveDefinition?
	local byId = passivesByModel[model]
	if not byId then
		return nil
	end
	local equipped = byId[passiveId]
	return if equipped then equipped.Definition else nil
end

function CombatantPassives.Unequip(model: Model, passiveId: string): ()
	local byId = passivesByModel[model]
	if not byId then
		return
	end
	local equipped = byId[passiveId]
	if not equipped then
		return
	end

	if equipped.DamagedConn then
		equipped.DamagedConn:Disconnect()
	end
	if equipped.DamageDealtConn then
		equipped.DamageDealtConn:Disconnect()
	end
	if equipped.Definition.OnUnequipped then
		equipped.Definition.OnUnequipped(equipped.Context)
	end

	byId[passiveId] = nil
end

return CombatantPassives
