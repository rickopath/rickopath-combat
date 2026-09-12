--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Hitbox.Signal)

export type SkillState = "Idle" | "Active" | "Cooldown" | "Disabled"

export type SkillContext = {
	Combatant: any, 
	Owner: Model,
	Player: Player?,
	Hitbox: any,
	Movement: any?,
	Presentation: { PlayEffect: (effectId: string, params: any) -> () },
}

export type SkillCost = {
	ResourceId: string,
	Amount: number,
}

export type SkillDefinition = {
	Id: string,
	DisplayName: string,
	Cooldown: number,
	Costs: { SkillCost },
}

export type Skill = {
	Id: string,
	Definition: SkillDefinition,
	Context: SkillContext,
	State: SkillState,
	CooldownExpiresAt: number,

	CanActivate: (self: Skill, ...any) -> (boolean, string?),
	Activate: (self: Skill, ...any) -> boolean,
	OnCancel: (self: Skill, reason: string?) -> (),
	Tick: (self: Skill, dt: number) -> (),
	OnDestroy: (self: Skill) -> (),

	Cancel: (self: Skill, reason: string?) -> (),
	Destroy: (self: Skill) -> (),
	OnCancelled: any, 

	TryActivate: (self: Skill, ...any) -> (boolean, string?),
	PayCost: (self: Skill) -> boolean,
	StartCooldown: (self: Skill) -> (),
	IsOnCooldown: (self: Skill) -> boolean,
	CooldownRemaining: (self: Skill) -> number,
}

export type SkillClass = {
	__index: SkillClass,
	ClassName: string,
	new: (definition: SkillDefinition, context: SkillContext) -> Skill,
}

local SkillBase = {}
SkillBase.__index = SkillBase

function SkillBase:CanActivate(...: any): (boolean, string?)
	local self = self :: Skill
	if self.Context.Combatant:HasStatusEffect("Stunned") then
		return false, "stunned"
	end
	if self:IsOnCooldown() then
		return false, "cooldown"
	end
	return true, nil
end

function SkillBase:Activate(...: any): boolean
	error(string.format("Skill %s did not override Activate", (self :: Skill).Id))
end

function SkillBase:OnCancel(_reason: string?): () end

function SkillBase:Cancel(reason: string?): ()
	local self = self :: Skill
	self.OnCancelled:Fire(reason)
	self:OnCancel(reason)
end

function SkillBase:Tick(_dt: number): () end

function SkillBase:OnDestroy(): () end

function SkillBase:Destroy(): ()
	local self = self :: Skill
	self.OnCancelled:Destroy()
	self:OnDestroy()
end

function SkillBase:PayCost(): boolean
	local self = self :: Skill
	for _, cost in self.Definition.Costs do
		local pool = self.Context.Combatant:GetResource(cost.ResourceId)
		if not pool or pool.Current < cost.Amount then
			return false
		end
	end
	for _, cost in self.Definition.Costs do
		self.Context.Combatant:GetResource(cost.ResourceId):TrySpend(cost.Amount)
	end
	return true
end

function SkillBase:StartCooldown(): ()
	local self = self :: Skill
	self.CooldownExpiresAt = os.clock() + self.Definition.Cooldown
	self.State = "Cooldown"
end

function SkillBase:IsOnCooldown(): boolean
	return os.clock() < (self :: Skill).CooldownExpiresAt
end

function SkillBase:CooldownRemaining(): number
	return math.max((self :: Skill).CooldownExpiresAt - os.clock(), 0)
end

function SkillBase:TryActivate(...: any): (boolean, string?)
	local self = self :: Skill
	local canActivate, reason = self:CanActivate(...)
	if not canActivate then
		return false, reason
	end
	if not self:PayCost() then
		return false, "cost"
	end
	local activated = self:Activate(...)
	if activated then
		self:StartCooldown()
		return true, nil
	end
	return false, "activate-returned-false"
end

local function construct(class: any, definition: SkillDefinition, context: SkillContext): Skill
	local self = setmetatable({
		Id = definition.Id,
		Definition = definition,
		Context = context,
		State = "Idle" :: SkillState,
		CooldownExpiresAt = 0,
		OnCancelled = Signal.new(),
	}, class)
	return (self :: any) :: Skill
end

local Skill = {}

function Skill.new(definition: SkillDefinition, context: SkillContext): Skill
	return construct(SkillBase, definition, context)
end

function Skill.extend(className: string): SkillClass
	local class = setmetatable({}, { __index = SkillBase })
	;(class :: any).__index = class
	;(class :: any).ClassName = className
	;(class :: any).new = function(definition: SkillDefinition, context: SkillContext): Skill
		return construct(class, definition, context)
	end
	return class :: any
end

return Skill
