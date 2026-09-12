--!strict

-- per-local-combatant Skill instances - predictive TryActivate, then tells the server "hey I'm
-- activating this" so the real authoritative gate (CombatantSkills.luau) can actually run. mirrors
-- HitboxClient.RequestAttack's predict-then-send shape, same pattern, different system
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)
local SkillNet = require(ReplicatedStorage.Shared.Combat.SkillNet)
local ClientCombatant = require(script.Parent.ClientCombatant)
local SkillHitbox = require(script.Parent.SkillHitbox)
local ClientMovement = require(script.Parent.ClientMovement)
local PresentationClient = require(script.Parent.PresentationClient)

type SkillInstance = SkillModule.Skill
type SkillContext = SkillModule.SkillContext
type SkillActivationResult = SkillNet.SkillActivationResult

local skills: { [string]: SkillInstance } = {}
local pendingActivations: { [number]: SkillInstance } = {}
local sequenceCounter = 0

local ClientSkills = {}

function ClientSkills.Equip(skillId: string): SkillInstance?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local combatant = ClientCombatant.GetOrCreate(character)

	local context: SkillContext = {
		Combatant = combatant,
		Owner = character,
		Player = Players.LocalPlayer,
		Hitbox = SkillHitbox,
		Movement = ClientMovement,
		Presentation = {
			PlayEffect = function(effectId: string, params: any)
				PresentationClient.PlayEffect(effectId, params)
			end,
		},
	}

	local skill = SkillRegistry.Create(skillId, context)
	if not skill then
		return nil
	end

	skills[skillId] = skill
	return skill
end

function ClientSkills.Get(skillId: string): SkillInstance?
	return skills[skillId]
end

-- read-only view of every skill the local player currently has equipped, keyed by skill id - what
-- DebugOverlay iterates to print a per-skill cooldown line. returns the live internal table, not a
-- copy - same "read-only by convention, not by enforcement" posture as everything else this
-- lightweight in the framework, don't mutate what you get back
function ClientSkills.GetAll(): { [string]: SkillInstance }
	return skills
end

-- predicted local activation (instant feedback through the skill's own Activate override), then
-- tells the server so its actual authoritative TryActivate gate gets to run too. a dropped
-- SkillActivationResult packet leaves a stale pendingActivations entry behind - that's a bounded
-- leak (a disconnected player isn't sending more requests, it just stops growing), not worth adding
-- a whole sweep for a channel that resolves in basically no time anyway
function ClientSkills.RequestActivate(skillId: string): boolean
	local skill = skills[skillId]
	if not skill then
		return false
	end

	local activated = skill:TryActivate()
	if not activated then
		return false
	end

	sequenceCounter += 1
	pendingActivations[sequenceCounter] = skill
	SkillNet.FireActivateSkill({ SkillId = skillId, SequenceId = sequenceCounter })

	return true
end

local function onSkillActivationResult(result: SkillActivationResult): ()
	local skill = pendingActivations[result.SequenceId]
	pendingActivations[result.SequenceId] = nil
	if skill and not result.Accepted then
		-- server disagreed after we already predicted + activated locally - cancel it, the server's
		-- word is final here same as everywhere else
		skill:Cancel("server rejected activation")
	end
end

function ClientSkills.Init(): ()
	SkillNet.OnSkillActivationResult(onSkillActivationResult)
end

return ClientSkills
