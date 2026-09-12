--!strict

-- read-only predicted mirror, fed entirely by SnapshotReplicator's broadcast - this is NEVER
-- authoritative on its own, don't start trusting it for anything that matters. entries for a model
-- we've never seen before get created on demand, so nobody has to pre-register a combatant client side
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Combat.Types)
local SnapshotNet = require(ReplicatedStorage.Shared.Combat.Snapshot.Net)

type CombatantSnapshot = Types.CombatantSnapshot

-- local predicted-spend view of one resource. TrySpend here is NOT authoritative, it's just an
-- instant UI forecast (grey out a dash button right away instead of waiting on a round trip).
-- ApplySnapshot always stomps Current/Max with the server's real state, so a wrong local guess
-- self-corrects within one round trip and nobody has to care. Health's just an entry keyed "Health"
-- same as the server's Combatant - no special case, don't add one
export type ResourceView = {
	Current: number,
	Max: number,
	TrySpend: (self: ResourceView, amount: number) -> boolean,
}

export type ClientCombatant = {
	Model: Model,
	Team: string?,
	IsInvulnerable: boolean,
	GetResource: (self: ClientCombatant, id: string) -> ResourceView?,
	-- includes "Health" alongside every real ResourcePool id, same as GetResource - what
	-- DebugOverlay iterates to print a line per resource without hardcoding resource ids
	GetAllResources: (self: ClientCombatant) -> { [string]: ResourceView },
	HasStatusEffect: (self: ClientCombatant, id: string) -> boolean,
	-- ExpiresAt is workspace:GetServerTimeNow()-relative, same clock DebugOverlay/anything else
	-- reads workspace:GetServerTimeNow() against - subtract the two for a countdown, don't assume
	-- os.clock() or tick() line up with it
	GetStatusEffects: (self: ClientCombatant) -> { [string]: { Stacks: number, ExpiresAt: number } },
	ApplySnapshot: (self: ClientCombatant, snapshot: CombatantSnapshot) -> (),
}

local combatants: { [Model]: ClientCombatant } = {}

local function newResourceView(current: number, max: number): ResourceView
	local self = {} :: ResourceView
	self.Current = current
	self.Max = max

	function self.TrySpend(_self: ResourceView, amount: number): boolean
		if self.Current < amount then
			return false
		end
		self.Current -= amount
		return true
	end

	return self
end

local function new(model: Model): ClientCombatant
	local resourceViews: { [string]: ResourceView } = {}
	local statusEffects: { [string]: { Stacks: number, ExpiresAt: number } } = {}

	local self = {} :: ClientCombatant
	self.Model = model
	self.Team = nil
	self.IsInvulnerable = false

	function self.GetResource(_self: ClientCombatant, id: string): ResourceView?
		return resourceViews[id]
	end

	function self.GetAllResources(_self: ClientCombatant): { [string]: ResourceView }
		return resourceViews
	end

	function self.HasStatusEffect(_self: ClientCombatant, id: string): boolean
		return statusEffects[id] ~= nil
	end

	function self.GetStatusEffects(_self: ClientCombatant): { [string]: { Stacks: number, ExpiresAt: number } }
		return statusEffects
	end

	-- server's answer always wins, no arguing with it - stomps Current/Max even over a local
	-- predicted TrySpend. that stomp IS the self-correction, that's the whole mechanism
	function self.ApplySnapshot(_self: ClientCombatant, snapshot: CombatantSnapshot): ()
		local health = resourceViews["Health"]
		if health then
			health.Current = snapshot.Health
			health.Max = snapshot.MaxHealth
		else
			resourceViews["Health"] = newResourceView(snapshot.Health, snapshot.MaxHealth)
		end

		for id, resource in snapshot.Resources do
			local view = resourceViews[id]
			if view then
				view.Current = resource.Current
				view.Max = resource.Max
			else
				resourceViews[id] = newResourceView(resource.Current, resource.Max)
			end
		end

		table.clear(statusEffects)
		for id, effect in snapshot.StatusEffects do
			statusEffects[id] = { Stacks = effect.Stacks, ExpiresAt = effect.ExpiresAt }
		end

		self.Team = snapshot.Team
		self.IsInvulnerable = snapshot.IsInvulnerable
	end

	return self
end

local ClientCombatant = {}

function ClientCombatant.GetOrCreate(model: Model): ClientCombatant
	local existing = combatants[model]
	if existing then
		return existing
	end
	local created = new(model)
	combatants[model] = created
	return created
end

function ClientCombatant.Get(model: Model): ClientCombatant?
	return combatants[model]
end

function ClientCombatant.Destroy(model: Model): ()
	combatants[model] = nil
end

function ClientCombatant.Init(): ()
	SnapshotNet.OnSnapshots(function(entries)
		for _, entry in entries do
			if entry.Model then
				ClientCombatant.GetOrCreate(entry.Model):ApplySnapshot({
					Health = entry.Health,
					MaxHealth = entry.MaxHealth,
					Resources = entry.Resources,
					StatusEffects = entry.StatusEffects,
					Team = entry.Team,
					IsInvulnerable = entry.IsInvulnerable,
				})
			end
		end
	end)
end

return ClientCombatant
