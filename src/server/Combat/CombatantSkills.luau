--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)
local SkillNet = require(ReplicatedStorage.Shared.Combat.SkillNet)
local CombatantRegistry = require(script.Parent.CombatantRegistry)
local SkillHitbox = require(script.Parent.SkillHitbox)
local PresentationFacade = require(script.Parent.PresentationFacade)

type SkillInstance = SkillModule.Skill
type SkillContext = SkillModule.SkillContext
type ActivateSkillRequest = SkillNet.ActivateSkillRequest

local skillsByModel: { [Model]: { [string]: SkillInstance } } = {}

local CombatantSkills = {}

function CombatantSkills.Equip(model: Model, skillId: string): SkillInstance?
	local combatant = CombatantRegistry.Get(model)
	if not combatant then
		warn(string.format("Combat: CombatantSkills.Equip(%s, %q) - no Combatant registered for this model yet.", model.Name, skillId))
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

	local skill = SkillRegistry.Create(skillId, context)
	if not skill then
		return nil
	end

	local bySkillId = skillsByModel[model]
	if not bySkillId then
		bySkillId = {}
		skillsByModel[model] = bySkillId
	end
	bySkillId[skillId] = skill

	return skill
end

function CombatantSkills.Get(model: Model, skillId: string): SkillInstance?
	local bySkillId = skillsByModel[model]
	if not bySkillId then
		return nil
	end
	return bySkillId[skillId]
end

function CombatantSkills.FindByWeaponId(model: Model, weaponId: string): SkillInstance?
	local skillId = SkillHitbox.GetSkillIdForWeapon(weaponId)
	if not skillId then
		return nil
	end
	return CombatantSkills.Get(model, skillId)
end

function CombatantSkills.Unequip(model: Model, skillId: string): ()
	local bySkillId = skillsByModel[model]
	if not bySkillId then
		return
	end
	local skill = bySkillId[skillId]
	if skill then
		skill:Destroy()
	end
	bySkillId[skillId] = nil
end

local function onActivateSkill(player: Player, request: ActivateSkillRequest): ()
	local character = player.Character
	if not character then
		return
	end

	local skill = CombatantSkills.Get(character, request.SkillId)
	if not skill then
		warn(string.format("Combat: %s tried to activate %q - not equipped", player.Name, request.SkillId))
		SkillNet.FireSkillActivationResult(player, { SequenceId = request.SequenceId, Accepted = false })
		return
	end

	local accepted, reason = skill:TryActivate()
	if not accepted and reason ~= "cooldown" then
		warn(string.format("Combat: %s's activation of %q rejected - %s", player.Name, request.SkillId, reason or "unknown"))
	end

	SkillNet.FireSkillActivationResult(player, {
		SequenceId = request.SequenceId,
		Accepted = accepted or reason == "cooldown",
	})
end

function CombatantSkills.Init(): ()
	SkillNet.OnActivateSkill(onActivateSkill)
end

return CombatantSkills
