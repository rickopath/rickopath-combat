--!strict

-- server-side authoritative combatant runtime. Create hard-errors if the model isn't already under
-- workspace.Alive - that's a setup bug on YOUR end, not adversarial input, same posture as
-- AliveRegistry's missing-folder check. this thing attaches to Alive's contract, it doesn't own or
-- populate that folder itself, don't go looking here for where characters get parented
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Hitbox.Signal)
local Types = require(ReplicatedStorage.Shared.Combat.Types)
local ResourcePool = require(ReplicatedStorage.Shared.Combat.ResourcePool)
local DamageType = require(ReplicatedStorage.Shared.Combat.DamageType)
local ConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local MovementLock = require(script.Parent.MovementLock)

type StatusEffectDefinition = Types.StatusEffectDefinition

-- generic stat modifier system - the framework doesn't know what "AttackMultiplier" or "Strength"
-- means, it just knows how to combine numbers tagged onto a name. deliberately NOT built on top of
-- Resistances (that table's damage-pipeline-critical, already shipped, already tested, not touching
-- it) - this is a separate, more general primitive that supports MULTIPLE simultaneous modifiers
-- from different sources composing together, which Resistances' single-value-per-key design can't
export type StatModifier = {
	Value: number,
	Mode: "Add" | "Multiply",
}

export type Combatant = {
	Model: Model,
	Player: Player?,
	Health: ResourcePool.ResourcePool,
	Resistances: Types.ResistanceTable,
	IsDead: boolean,
	Team: string?,
	-- i-frames. nothing sets this for you - a dodge roll skill would flip it true on Activate and
	-- false when the roll ends, a respawn might hold it for a second or two. CombatDamageBridge
	-- checks it and skips damage application; the hit still lands and still registers, exactly like
	-- the FriendlyFire path. it does NOT block status effects, only damage - if you want a dodge to
	-- dodge Poison too, check this yourself in your OnHit
	IsInvulnerable: boolean,
	-- the TRUE pre-damage modifier hook - runs INSIDE ApplyDamage, before health changes, before
	-- Resistances even apply. this is what a real block/parry has to be built on: DamageSpec.OnHit
	-- fires AFTER ApplyDamage already happened, so reacting to a hit there means refunding damage
	-- after the fact, which desyncs anyone listening to OnDamaged and just feels wrong. this
	-- doesn't. single slot, not a list - if you need block AND some other reduction stacking,
	-- compose them into one function yourself, the order they apply in is your call, not this file's
	DamageModifier: ((amount: number, damageType: string, attackerCharacter: Model?) -> number)?,
	-- physics-authoritative root - see MovementLock.luau for why this isn't just WalkSpeed=0.
	-- MovementReconciler also rejects skill-driven movement (Dash etc.) while this is true, not
	-- just raw walking
	IsMovementLocked: boolean,
	-- pure bookkeeping, not a mechanic - the framework doesn't decide what a combo IS or how long
	-- the window is, it just remembers a number and a timestamp so you don't have to wire your own
	ComboIndex: number,
	LastAttackTime: number,

	GetResource: (self: Combatant, id: string) -> ResourcePool.ResourcePool?,
	-- both of these hand back the live internal table by reference, not a copy - read-only by
	-- convention, nothing stops you from mutating it, so don't. same tradeoff CombatantRegistry.GetAll
	-- makes, needed so SnapshotReplicator can just enumerate everything without a copy every tick
	GetAllResources: (self: Combatant) -> { [string]: ResourcePool.ResourcePool },
	GetActiveStatusEffects: (self: Combatant) -> { [string]: Types.ActiveStatusEffect },
	ApplyDamage: (self: Combatant, amount: number, damageType: string, source: Model?) -> number,
	Heal: (self: Combatant, amount: number, source: Model?) -> number,
	Die: (self: Combatant, source: Model?) -> (),
	Revive: (self: Combatant, healthFraction: number?) -> (),

	ApplyStatusEffect: (self: Combatant, definition: Types.StatusEffectDefinition) -> (),
	RemoveStatusEffect: (self: Combatant, id: string) -> (),
	HasStatusEffect: (self: Combatant, id: string) -> boolean,
	SetResistance: (self: Combatant, damageType: string, multiplier: number) -> (),
	SetTeam: (self: Combatant, team: string?) -> (),
	SetInvulnerable: (self: Combatant, value: boolean) -> (),
	SetDamageModifier: (self: Combatant, modifier: ((amount: number, damageType: string, attackerCharacter: Model?) -> number)?) -> (),
	SetMovementEnabled: (self: Combatant, enabled: boolean) -> (),

	-- modifierId is how ONE specific buff removes exactly its own contribution later without
	-- touching any other source's modifier on the same stat - mirrors HitResult.Meta's "tag it so
	-- you can find it again" idiom. GetStat's baseValue is explicit, not assumed: the framework
	-- doesn't know if "AttackMultiplier"'s neutral value is 1 or if "BonusDamage"'s is 0, same
	-- reasoning DamageType.ApplyResistance already uses for its own baseAmount parameter
	AddStatModifier: (self: Combatant, statId: string, modifierId: string, value: number, mode: "Add" | "Multiply") -> (),
	RemoveStatModifier: (self: Combatant, statId: string, modifierId: string) -> (),
	GetStat: (self: Combatant, statId: string, baseValue: number) -> number,

	AdvanceCombo: (self: Combatant) -> number,
	ResetCombo: (self: Combatant) -> (),

	Update: (self: Combatant, dt: number) -> (),

	OnDamaged: any, -- fastsignal ScriptSignal(amount: number, damageType: string, source: Model?)
	OnHealed: any, -- fastsignal ScriptSignal(amount: number, source: Model?)
	OnDied: any, -- fastsignal ScriptSignal(source: Model?)
	OnStatusEffectApplied: any, -- fastsignal ScriptSignal(id: string, stacks: number)
	OnStatusEffectExpired: any, -- fastsignal ScriptSignal(id: string)
	-- fired by CombatDamageBridge on the ATTACKER's Combatant after a successful ApplyDamage on
	-- someone else - the OnDamaged/OnHealed pair above are both victim-side, this is the one
	-- attacker-side signal, mainly for CombatantPassives' OnDamageDealt hook
	OnDamageDealt: any, -- fastsignal ScriptSignal(amount: number, damageType: string, target: any)

	Destroy: (self: Combatant) -> (),
}

local ALIVE_FOLDER_NAME = "Alive" -- matches Hitbox's own convention, duplicated on purpose - this
-- module doesn't otherwise depend on the Hitbox server layer at all, and one string constant isn't
-- worth dragging in a dependency just to avoid typing "Alive" twice

local cfg: ConfigModule.Config = ConfigModule
local combatants: { [Model]: Combatant } = {}
local tickAccum = 0

local function isUnderAlive(model: Model): boolean
	local alive = workspace:FindFirstChild(ALIVE_FOLDER_NAME)
	if not alive then
		return false
	end
	return model:IsDescendantOf(alive)
end

local function newCombatant(model: Model, definition: Types.CombatantDefinition, player: Player?): Combatant
	local health = ResourcePool.new({
		Id = "Health",
		Max = definition.MaxHealth,
		Initial = definition.InitialHealth or definition.MaxHealth,
	})

	local resources: { [string]: ResourcePool.ResourcePool } = {}
	if definition.Resources then
		for _, resourceDef in definition.Resources do
			resources[resourceDef.Id] = ResourcePool.new(resourceDef)
		end
	end

	local resistances: Types.ResistanceTable = {}
	if definition.Resistances then
		for damageType, multiplier in definition.Resistances do
			resistances[damageType] = multiplier
		end
	end

	local statusEffects: { [string]: Types.ActiveStatusEffect } = {}
	local statModifiers: { [string]: { [string]: StatModifier } } = {}

	local onDamaged = Signal.new()
	local onHealed = Signal.new()
	local onDied = Signal.new()
	local onStatusEffectApplied = Signal.new()
	local onStatusEffectExpired = Signal.new()
	local onDamageDealt = Signal.new()

	local self = {} :: Combatant
	self.Model = model
	self.Player = player
	self.Health = health
	self.Resistances = resistances
	self.IsDead = false
	self.Team = nil
	self.IsInvulnerable = false
	self.DamageModifier = nil
	self.IsMovementLocked = false
	self.ComboIndex = 0
	self.LastAttackTime = 0
	self.OnDamaged = onDamaged
	self.OnHealed = onHealed
	self.OnDied = onDied
	self.OnStatusEffectApplied = onStatusEffectApplied
	self.OnStatusEffectExpired = onStatusEffectExpired
	self.OnDamageDealt = onDamageDealt

	-- health hitting zero through ANY path - ApplyDamage, a status effect tick, whatever - dies.
	-- one funnel. not "every damage source has to remember to check and call Die itself", that's
	-- how you get a combatant walking around at -40 health because someone forgot the check
	health.OnDepleted:Connect(function()
		(self :: Combatant):Die(nil)
	end)

	function self.GetResource(_self: Combatant, id: string): ResourcePool.ResourcePool?
		if id == "Health" then
			return health
		end
		return resources[id]
	end

	function self.GetAllResources(_self: Combatant): { [string]: ResourcePool.ResourcePool }
		return resources
	end

	function self.GetActiveStatusEffects(_self: Combatant): { [string]: Types.ActiveStatusEffect }
		return statusEffects
	end

	function self.ApplyDamage(_self: Combatant, amount: number, damageType: string, source: Model?): number
		if self.IsDead then
			return 0
		end
		-- DamageModifier runs FIRST, before passive Resistances - a block/parry deciding "does this
		-- hit even count" happens before armor-style flat reduction gets a chance to matter. your
		-- modifier gets the RAW amount and the attacker's character, so a facing check works here
		if self.DamageModifier then
			amount = self.DamageModifier(amount, damageType, source)
		end
		local resolved = DamageType.ApplyResistance(amount, damageType, self.Resistances)
		local before = health.Current
		health:Add(-resolved)
		local dealt = before - health.Current
		if dealt > 0 then
			onDamaged:Fire(dealt, damageType, source)
		end
		return dealt
	end

	function self.Heal(_self: Combatant, amount: number, source: Model?): number
		if self.IsDead then
			return 0
		end
		local before = health.Current
		health:Add(amount)
		local healed = health.Current - before
		if healed > 0 then
			onHealed:Fire(healed, source)
		end
		return healed
	end

	-- idempotent on purpose - two hits landing the same frame both trying to kill this thing
	-- shouldn't fire OnDied twice, that second call's just a no-op
	function self.Die(_self: Combatant, source: Model?): ()
		if self.IsDead then
			return
		end
		self.IsDead = true
		onDied:Fire(source)
		cfg.OnCombatantDied(model, source)
	end

	function self.Revive(_self: Combatant, healthFraction: number?): ()
		self.IsDead = false
		health:Set(health.Max * (healthFraction or 1))
	end

	function self.ApplyStatusEffect(_self: Combatant, def: StatusEffectDefinition): ()
		local now = workspace:GetServerTimeNow()
		local existing = statusEffects[def.Id]

		if not existing then
			local active: Types.ActiveStatusEffect = {
				Definition = def,
				Stacks = 1,
				ExpiresAt = now + def.Duration,
			}
			statusEffects[def.Id] = active
			if def.OnApply then
				def.OnApply(self, 1)
			end
			onStatusEffectApplied:Fire(def.Id, 1)
			return
		end

		if def.StackRule == "Refresh" then
			existing.ExpiresAt = now + def.Duration
		elseif def.StackRule == "Stack" then
			existing.Stacks = math.min(existing.Stacks + 1, def.MaxStacks)
			existing.ExpiresAt = now + def.Duration
			if def.OnStack then
				def.OnStack(self, existing.Stacks)
			end
		end
		-- "Ignore" rule: leave the existing effect exactly as-is, just re-fire the applied signal
		-- so listeners know someone tried to reapply it

		onStatusEffectApplied:Fire(def.Id, existing.Stacks)
	end

	function self.RemoveStatusEffect(_self: Combatant, id: string): ()
		local existing = statusEffects[id]
		if not existing then
			return
		end
		statusEffects[id] = nil
		if existing.Definition.OnExpire then
			existing.Definition.OnExpire(self)
		end
		onStatusEffectExpired:Fire(id)
	end

	function self.HasStatusEffect(_self: Combatant, id: string): boolean
		return statusEffects[id] ~= nil
	end

	function self.SetResistance(_self: Combatant, damageType: string, multiplier: number): ()
		self.Resistances[damageType] = multiplier
	end

	function self.SetTeam(_self: Combatant, team: string?): ()
		self.Team = team
	end

	function self.SetInvulnerable(_self: Combatant, value: boolean): ()
		self.IsInvulnerable = value
	end

	function self.SetDamageModifier(
		_self: Combatant,
		modifier: ((amount: number, damageType: string, attackerCharacter: Model?) -> number)?
	): ()
		self.DamageModifier = modifier
	end

	function self.SetMovementEnabled(_self: Combatant, enabled: boolean): ()
		if enabled == not self.IsMovementLocked then
			return -- already in the requested state, don't re-anchor/re-own for nothing
		end
		self.IsMovementLocked = not enabled
		if enabled then
			MovementLock.Release(model)
		else
			MovementLock.Apply(model)
		end
	end

	function self.AddStatModifier(_self: Combatant, statId: string, modifierId: string, value: number, mode: "Add" | "Multiply"): ()
		local byModifier = statModifiers[statId]
		if not byModifier then
			byModifier = {}
			statModifiers[statId] = byModifier
		end
		byModifier[modifierId] = { Value = value, Mode = mode }
	end

	function self.RemoveStatModifier(_self: Combatant, statId: string, modifierId: string): ()
		local byModifier = statModifiers[statId]
		if not byModifier then
			return
		end
		byModifier[modifierId] = nil
	end

	-- (baseValue + sum of every "Add" modifier) * (product of every "Multiply" modifier) - the
	-- standard, expected combine order. a stat with zero modifiers just returns baseValue unchanged
	function self.GetStat(_self: Combatant, statId: string, baseValue: number): number
		local byModifier = statModifiers[statId]
		if not byModifier then
			return baseValue
		end
		local additive = baseValue
		local multiplicative = 1
		for _, modifier in byModifier do
			if modifier.Mode == "Add" then
				additive += modifier.Value
			else
				multiplicative *= modifier.Value
			end
		end
		return additive * multiplicative
	end

	function self.AdvanceCombo(_self: Combatant): number
		self.ComboIndex += 1
		self.LastAttackTime = workspace:GetServerTimeNow()
		return self.ComboIndex
	end

	function self.ResetCombo(_self: Combatant): ()
		self.ComboIndex = 0
	end

	function self.Update(_self: Combatant, dt: number): ()
		if self.IsDead then
			return
		end

		health:Update(dt)
		for _, pool in resources do
			pool:Update(dt)
		end

		local now = workspace:GetServerTimeNow()
		local expired: { string } = {}
		for id, active in statusEffects do
			if active.Definition.OnTick then
				active.Definition.OnTick(self, dt)
			end
			if now >= active.ExpiresAt then
				table.insert(expired, id)
			end
		end
		-- remove AFTER the loop finishes - mutating statusEffects while iterating it above is exactly
		-- the kind of thing that works fine in testing and blows up in prod
		for _, id in expired do
			(self :: Combatant):RemoveStatusEffect(id)
		end
	end

	function self.Destroy(_self: Combatant): ()
		health:Destroy()
		for _, pool in resources do
			pool:Destroy()
		end
		onDamaged:Destroy()
		onHealed:Destroy()
		onDied:Destroy()
		onStatusEffectApplied:Destroy()
		onStatusEffectExpired:Destroy()
		onDamageDealt:Destroy()
	end

	return self
end

local CombatantRegistry = {}

function CombatantRegistry.Create(model: Model, definition: Types.CombatantDefinition, player: Player?): Combatant
	if not isUnderAlive(model) then
		error("Combat: Combatant model must already be a descendant of workspace.Alive")
	end

	local combatant = newCombatant(model, definition, player)
	combatants[model] = combatant
	return combatant
end

function CombatantRegistry.Get(model: Model): Combatant?
	return combatants[model]
end

-- SnapshotReplicator uses this to broadcast every tracked combatant. returns the live internal
-- table directly, not a defensive copy every single call - read-only by convention, not enforced,
-- so don't be the one who breaks that convention
function CombatantRegistry.GetAll(): { [Model]: Combatant }
	return combatants
end

function CombatantRegistry.Destroy(model: Model): ()
	local combatant = combatants[model]
	if combatant then
		combatant:Destroy()
	end
	combatants[model] = nil
end

function CombatantRegistry.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end

	RunService.Heartbeat:Connect(function(dt: number)
		tickAccum += dt
		if tickAccum >= cfg.CombatantTickInterval then
			local step = tickAccum
			tickAccum = 0
			for _, combatant in combatants do
				combatant:Update(step)
			end
		end
	end)
end

return CombatantRegistry
