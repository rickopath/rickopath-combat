--!strict

-- periodic throttled broadcast of every tracked combatant's snapshot to clients. two modes:
--
-- Config.SnapshotReplicationRadius == nil (default before ServerConfig.luau's override applies):
-- broadcast-to-all, exactly the old behavior, one sendToAll for everyone.
--
-- Config.SnapshotReplicationRadius == a number (the actual shipped default, see ServerConfig.luau):
-- each player only gets entries for combatants within that many studs of their OWN character,
-- using SpatialGrid so this doesn't cost players*combatants distance checks every tick. players
-- always see their own combatant regardless of distance - you always know your own health.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SnapshotTypes = require(ReplicatedStorage.Shared.Combat.Snapshot.Types)
local SnapshotNet = require(ReplicatedStorage.Shared.Combat.Snapshot.Net)
local SpatialGrid = require(ReplicatedStorage.Shared.Combat.SpatialGrid)
local ConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local CombatantRegistry = require(script.Parent.CombatantRegistry)

type CombatantSnapshotEntry = SnapshotTypes.CombatantSnapshotEntry

local cfg: ConfigModule.Config = ConfigModule
local accum = 0

-- rebuilt every broadcast tick, not held across ticks - positions move, and the tick interval is
-- already throttled (SnapshotBroadcastInterval), so there's no reuse to be had by keeping it warm
local grid: SpatialGrid.Grid<Model> = SpatialGrid.new(100)

local function buildEntry(model: Model, combatant): CombatantSnapshotEntry
	local resourceSnapshots: { [string]: { Current: number, Max: number } } = {}
	for id, pool in combatant:GetAllResources() do
		resourceSnapshots[id] = { Current = pool.Current, Max = pool.Max }
	end

	local statusEffectSnapshots: { [string]: { Stacks: number, ExpiresAt: number } } = {}
	for id, active in combatant:GetActiveStatusEffects() do
		statusEffectSnapshots[id] = { Stacks = active.Stacks, ExpiresAt = active.ExpiresAt }
	end

	return {
		Model = model,
		Health = combatant.Health.Current,
		MaxHealth = combatant.Health.Max,
		Resources = resourceSnapshots,
		StatusEffects = statusEffectSnapshots,
		Team = combatant.Team,
		IsInvulnerable = combatant.IsInvulnerable,
	}
end

local function broadcastToAll(): ()
	local entries: { CombatantSnapshotEntry } = {}
	for model, combatant in CombatantRegistry.GetAll() do
		table.insert(entries, buildEntry(model, combatant))
	end
	if #entries > 0 then
		SnapshotNet.FireSnapshots(entries)
	end
end

local function broadcastFiltered(radius: number): ()
	-- one entry table built once and reused across every player this tick - avoids re-deriving
	-- the same combatant's snapshot table once per nearby player. keyed by Model since that's
	-- what the grid hands back
	local entryByModel: { [Model]: CombatantSnapshotEntry } = {}

	grid:Clear()
	for model, combatant in CombatantRegistry.GetAll() do
		grid:Insert(model, model:GetPivot().Position)
		entryByModel[model] = buildEntry(model, combatant)
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		-- querying around your OWN position always finds your OWN combatant too (distance to
		-- yourself is 0) - no separate "always include self" special case needed, it falls out
		-- of the query for free as long as you're in the grid, which you always are
		local nearby = grid:QueryRadius(character:GetPivot().Position, radius)
		local entries: { CombatantSnapshotEntry } = table.create(#nearby)
		for _, model in nearby do
			table.insert(entries, entryByModel[model])
		end

		if #entries > 0 then
			SnapshotNet.FireSnapshotsTo(player, entries)
		end
	end
end

local SnapshotReplicator = {}

function SnapshotReplicator.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end

	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum >= cfg.SnapshotBroadcastInterval then
			accum = 0
			if cfg.SnapshotReplicationRadius then
				broadcastFiltered(cfg.SnapshotReplicationRadius)
			else
				broadcastToAll()
			end
		end
	end)
end

return SnapshotReplicator
