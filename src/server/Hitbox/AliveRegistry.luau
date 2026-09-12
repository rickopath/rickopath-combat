--!strict

-- workspace.Alive is THE single source of truth for "can this get hit" - every player character and
-- NPC that should be hittable gets parented there by whatever spawns it, that part's on you, not this
-- library. hard errors if the folder's missing - that's a place setup mistake, not something to
-- quietly swallow and let someone spend an afternoon debugging why nothing ever registers a hit
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Trove = require(ReplicatedStorage.Packages.trove)
local Config = require(ReplicatedStorage.Shared.Hitbox.Config)
local RewindBuffer = require(script.Parent.RewindBuffer)

local ALIVE_FOLDER_NAME = "Alive"

export type AliveRegistry = {
	GetCandidates: (self: AliveRegistry, origin: Vector3, margin: number) -> { Model },
	SnapshotPositions: (self: AliveRegistry) -> { [Model]: Vector3 },
	GetCandidatesFromPositions: (self: AliveRegistry, positions: { [Model]: Vector3 }, origin: Vector3, margin: number) -> { Model },
	GetRewindPose: (self: AliveRegistry, model: Model, timestamp: number) -> { [string]: CFrame }?,
	GetTrackedParts: (self: AliveRegistry, model: Model) -> { [string]: BasePart }?,
	Destroy: (self: AliveRegistry) -> (),
}

-- every BasePart under the model, keyed by name. assumes the rig doesn't change shape after spawn -
-- if you're hot-swapping parts on a live character, this cache goes stale and nobody warns you
local function cacheParts(model: Model): { [string]: BasePart }
	local parts: { [string]: BasePart } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			parts[inst.Name] = inst
		end
	end
	return parts
end

local function new(depthSeconds: number, sampleInterval: number): AliveRegistry
	local alive = workspace:FindFirstChild(ALIVE_FOLDER_NAME)
	if not alive then
		error("Hitbox: workspace.Alive folder not found - required for hittable entity tracking")
	end

	-- tags it here instead of in default.project.json - rojo 7.7.0 just doesn't have $tags support,
	-- and this is already the one place that's authoritative for "yes, Alive exists", so the tag
	-- replicates from right here instead of some second setup step someone forgets
	CollectionService:AddTag(alive, Config.AliveFolderTag)

	local trove = Trove.new()
	local buffers: { [Model]: RewindBuffer.RewindBuffer } = {}
	local trackedParts: { [Model]: { [string]: BasePart } } = {}
	local scratchPose: { [string]: CFrame } = {}

	local function onAdded(inst: Instance)
		if not inst:IsA("Model") then
			return
		end
		local model = inst :: Model
		buffers[model] = RewindBuffer.new(depthSeconds, sampleInterval)
		trackedParts[model] = cacheParts(model)
	end

	local function onRemoved(inst: Instance)
		-- ChildRemoved only ever hands us an Instance, but the only things that ever got added as
		-- The keys are always Models.
		local model = inst :: Model
		local hb = buffers[model]
		if hb then
			hb:Destroy()
		end
		buffers[model] = nil
		trackedParts[model] = nil
	end

	trove:Add(alive.ChildAdded:Connect(onAdded))
	trove:Add(alive.ChildRemoved:Connect(onRemoved))
	for _, child in alive:GetChildren() do
		onAdded(child)
	end

	-- one shared heartbeat for every tracked model, not one connection per model - that doesn't scale
	-- and never will. scratch table's reused so gathering a pose doesn't allocate every tick,
	-- RewindBuffer.Record is the only thing that actually keeps any of this data around after
	trove:Add(RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for model, hb in buffers do
			local parts = trackedParts[model]
			if parts then
				table.clear(scratchPose)
				for name, part in parts do
					scratchPose[name] = part.CFrame
				end
				hb:Record(now, scratchPose)
			end
		end
	end))

	local self = {} :: AliveRegistry

	-- broad phase: a cheap distance cull over whatever's currently tracked, NOT a WorldRoot query.
	-- margin has to cover "target already dodged out of the live swing path" or the whole lag comp
	-- system is pointless theater. fine for a one-shot caller (a single melee/hitscan/radius swing) -
	-- a per-tick caller running many concurrent queries the same frame (projectiles, looking at you)
	-- should use SnapshotPositions + GetCandidatesFromPositions instead.
	function self.GetCandidates(_self: AliveRegistry, origin: Vector3, margin: number): { Model }
		local out: { Model } = {}
		for model in buffers do
			local pos = model:GetPivot().Position
			if (pos - origin).Magnitude <= margin then
				table.insert(out, model)
			end
		end
		return out
	end

	-- one GetPivot() per tracked model, meant to be called ONCE per frame and reused across every
	-- candidate query that frame. this is the whole trick that turns "N projectiles times M tracked
	-- models" GetPivot() calls into just M, no matter how many projectiles happen to be in flight
	function self.SnapshotPositions(_self: AliveRegistry): { [Model]: Vector3 }
		local positions: { [Model]: Vector3 } = {}
		for model in buffers do
			positions[model] = model:GetPivot().Position
		end
		return positions
	end

	function self.GetCandidatesFromPositions(
		_self: AliveRegistry,
		positions: { [Model]: Vector3 },
		origin: Vector3,
		margin: number
	): { Model }
		local out: { Model } = {}
		for model, pos in positions do
			if (pos - origin).Magnitude <= margin then
				table.insert(out, model)
			end
		end
		return out
	end

	function self.GetRewindPose(_self: AliveRegistry, model: Model, timestamp: number): { [string]: CFrame }?
		local hb = buffers[model]
		if not hb then
			return nil
		end
		local res = hb:SampleAt(timestamp)
		if not res.Found then
			return nil
		end
		return res.Pose
	end

	function self.GetTrackedParts(_self: AliveRegistry, model: Model): { [string]: BasePart }?
		return trackedParts[model]
	end

	function self.Destroy(_self: AliveRegistry)
		trove:Destroy()
		table.clear(buffers)
		table.clear(trackedParts)
	end

	return self
end

return { new = new }
