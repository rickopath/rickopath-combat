--!strict

-- continuous swept-volume resolution, shared by all four attack kinds. melee loops this across
-- sub-steps of an arc, projectile drives it every tick, hitscan just calls it once and moves on
local Types = require(script.Parent.Types)
local SpatialQuery = require(script.Parent.SpatialQuery)
local Pool = require(script.Parent.Pool)
local Config = require(script.Parent.Config)

local SweepResolver = {}

local function newHitResult(): Types.HitResult
	return {
		Target = nil :: any,
		HitPart = nil :: any,
		Point = Vector3.zero,
		Normal = Vector3.zero,
		TOI = 0,
		SubStepIndex = 0,
		Distance = 0,
		Meta = nil,
	}
end

local function resetHitResult(hit: Types.HitResult): ()
	hit.Target = nil :: any
	hit.HitPart = nil :: any
	hit.Point = Vector3.zero
	hit.Normal = Vector3.zero
	hit.TOI = 0
	hit.SubStepIndex = 0
	hit.Distance = 0
	hit.Meta = nil
end

-- pool size comes straight from the Default Config table - this pool gets built once at module
-- load, BEFORE any HitboxServer.Init(customConfig) override could ever apply. so no, a runtime
-- override can't resize it, don't waste time trying to make that work
local resultPool: Types.PoolHandle<Types.HitResult> = Pool.new(
	newHitResult,
	resetHitResult,
	Config.HitResultPoolInitialSize,
	Config.HitResultPoolGrowthIncrement,
	Config.HitResultPoolMaxSize
)

SweepResolver.ResultPool = resultPool

-- box goes straight through Blockcast (CFrame+size, no proxy Instance needed at all), capsule maps
-- directly onto Spherecast - a swept sphere already IS a capsule, nobody needs to hand-roll capsule
-- math for that, Roblox already did it
local function castSegment(params: Types.SweepParams): (BasePart?, Vector3?, Vector3?, number?)
	local disp = params.To.Position - params.From.Position

	if params.Shape == "Box" then
		assert(params.HalfExtents, "box sweep needs HalfExtents")
		local res = SpatialQuery.Blockcast(params.From, (params.HalfExtents :: Vector3) * 2, disp, params.Filter)
		if res then
			return res.Instance, res.Position, res.Normal, res.Distance
		end
		return nil
	end

	assert(params.Radius, "capsule sweep needs Radius")
	local res = SpatialQuery.Spherecast(params.From.Position, params.Radius :: number, disp, params.Filter)
	if res then
		return res.Instance, res.Position, res.Normal, res.Distance
	end
	return nil
end

-- resolves one segment into a pooled HitResult, or nil. dedupe against alreadyHit BEFORE the cast
-- runs, so a target that already resolved this swing skips the narrow-phase work entirely instead
-- of paying for a cast we're just going to throw away
function SweepResolver.ResolveSegment(
	params: Types.SweepParams,
	subStepIndex: number,
	toi: number,
	alreadyHit: { [Model]: boolean }?
): Types.HitResult?
	local hitPart, point, normal, dist = castSegment(params)
	if not hitPart then
		return nil
	end

	local target = SpatialQuery.ResolveHittableModel(hitPart)
	if not target then
		return nil
	end

	if alreadyHit and alreadyHit[target] then
		return nil
	end

	local hit = resultPool:Checkout()
	hit.Target = target
	hit.HitPart = hitPart
	hit.Point = point :: Vector3
	hit.Normal = normal :: Vector3
	hit.TOI = toi
	hit.SubStepIndex = subStepIndex
	hit.Distance = dist :: number
	return hit
end

-- single-pose overlap, no sweep involved - the Radius/AoE kind uses this, still funneled through
-- ResolveHittableModel same as everything else, no special-casing here either
function SweepResolver.ResolveStationary(
	shape: Types.HitboxShape,
	halfExtents: Vector3?,
	radius: number?,
	cf: CFrame,
	filter: Types.QueryFilter
): { Types.HitResult }
	local parts: { BasePart }
	if shape == "Box" then
		assert(halfExtents, "box overlap needs HalfExtents")
		parts = SpatialQuery.Box(cf, (halfExtents :: Vector3) * 2, filter)
	else
		assert(radius, "capsule overlap needs Radius")
		parts = SpatialQuery.Radius(cf.Position, radius :: number, filter)
	end

	local seen: { [Model]: boolean } = {}
	local hits: { Types.HitResult } = {}
	for _, part in parts do
		local target = SpatialQuery.ResolveHittableModel(part)
		if target and not seen[target] then
			seen[target] = true
			local hit = resultPool:Checkout()
			hit.Target = target
			hit.HitPart = part
			hit.Point = part.Position
			hit.Normal = Vector3.yAxis
			hit.TOI = 0
			hit.SubStepIndex = 0
			hit.Distance = (part.Position - cf.Position).Magnitude
			table.insert(hits, hit)
		end
	end
	return hits
end

local function angleBetween(a: CFrame, b: CFrame): number
	local dot = a.LookVector:Dot(b.LookVector)
	return math.acos(math.clamp(dot, -1, 1))
end

export type MeleeSegment = {
	From: CFrame,
	To: CFrame,
	SubStepIndex: number,
	TOI: number,
}

-- sub-step count is derived from the angular delta, not some flat constant we picked and forgot
-- about. shapecast already gives tunnel-proof translation on its own - sub-stepping here only
-- exists to bound the arc's chord error. shared by the live resolver below AND the server's
-- rewind-confirmed path, so both walk the exact same arc, don't let them drift apart
function SweepResolver.BuildMeleeSegments(
	motion: { Types.MotionSample },
	minSubSteps: number,
	maxSubSteps: number,
	maxDegreesPerSubStep: number
): { MeleeSegment }
	local segments: { MeleeSegment } = {}
	if #motion < 2 then
		return segments
	end

	local totalT = motion[#motion].T - motion[1].T
	if totalT <= 0 then
		return segments
	end

	local globalStep = 0
	for i = 1, #motion - 1 do
		local a = motion[i]
		local b = motion[i + 1]

		local deg = math.deg(angleBetween(a.CFrame, b.CFrame))
		local subSteps = math.clamp(math.ceil(deg / maxDegreesPerSubStep), minSubSteps, maxSubSteps)

		for s = 1, subSteps do
			globalStep += 1
			local alpha0 = (s - 1) / subSteps
			local alpha1 = s / subSteps
			local t = a.T + (b.T - a.T) * alpha1

			table.insert(segments, {
				From = a.CFrame:Lerp(b.CFrame, alpha0),
				To = a.CFrame:Lerp(b.CFrame, alpha1),
				SubStepIndex = globalStep,
				TOI = (t - motion[1].T) / totalT,
			})
		end
	end

	return segments
end

function SweepResolver.ResolveMelee(
	config: Types.HitboxConfig,
	motion: { Types.MotionSample },
	filter: Types.QueryFilter,
	minSubSteps: number,
	maxSubSteps: number,
	maxDegreesPerSubStep: number
): { Types.HitResult }
	local hits: { Types.HitResult } = {}
	local alreadyHit: { [Model]: boolean } = {}

	for _, seg in SweepResolver.BuildMeleeSegments(motion, minSubSteps, maxSubSteps, maxDegreesPerSubStep) do
		local hit = SweepResolver.ResolveSegment({
			Shape = config.Shape,
			HalfExtents = config.HalfExtents,
			Radius = config.Radius,
			From = seg.From,
			To = seg.To,
			Filter = filter,
		}, seg.SubStepIndex, seg.TOI, alreadyHit)

		if hit then
			alreadyHit[hit.Target] = true
			table.insert(hits, hit)
			if #hits >= config.MaxTargetsPerSwing then
				return hits
			end
		end
	end

	return hits
end

-- === rewind-aware narrow phase ===
-- broad phase (AliveRegistry.GetCandidates) already figured out "who's plausibly nearby" using live
-- position plus a speed-based margin. everything below just answers "was this candidate actually
-- there back then" with pure math against a rewound pose - zero more WorldRoot calls, and no,
-- nothing ever actually gets moved back in time, it's all math on cached CFrames

-- 15-axis SAT, textbook oriented-box-vs-oriented-box test, nothing clever going on here
local function obbOverlap(cfA: CFrame, heA: Vector3, cfB: CFrame, heB: Vector3): boolean
	local d = cfB.Position - cfA.Position

	local axesA = { cfA.RightVector, cfA.UpVector, -cfA.LookVector }
	local axesB = { cfB.RightVector, cfB.UpVector, -cfB.LookVector }
	local heAArr = { heA.X, heA.Y, heA.Z }
	local heBArr = { heB.X, heB.Y, heB.Z }

	local function overlapOnAxis(axis: Vector3): boolean
		if axis.Magnitude < 1e-6 then
			return true -- degenerate cross product, parallel edges - skip it, it's not a real separating axis anyway
		end
		axis = axis.Unit
		local projD = math.abs(d:Dot(axis))

		local ra = 0
		for i = 1, 3 do
			ra += heAArr[i] * math.abs(axesA[i]:Dot(axis))
		end
		local rb = 0
		for i = 1, 3 do
			rb += heBArr[i] * math.abs(axesB[i]:Dot(axis))
		end

		return projD <= ra + rb
	end

	for i = 1, 3 do
		if not overlapOnAxis(axesA[i]) then
			return false
		end
	end
	for i = 1, 3 do
		if not overlapOnAxis(axesB[i]) then
			return false
		end
	end
	for i = 1, 3 do
		for j = 1, 3 do
			if not overlapOnAxis(axesA[i]:Cross(axesB[j])) then
				return false
			end
		end
	end

	return true
end

-- clamp into the box's local space, the usual closest-point-on-obb trick, nothing exotic
local function closestPointOnObb(cf: CFrame, he: Vector3, point: Vector3): Vector3
	local localPoint = cf:PointToObjectSpace(point)
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -he.X, he.X),
		math.clamp(localPoint.Y, -he.Y, he.Y),
		math.clamp(localPoint.Z, -he.Z, he.Z)
	)
	return cf:PointToWorldSpace(clamped)
end

-- endpoint-sampled segment-vs-obb distance, NOT a true continuous segment-box distance - and that's
-- fine. sub-steps already keep segments short, and this only gates the historical confirm - the real
-- continuous tunneling-proof check already happened at broad phase, against live geometry
local function segmentObbDistance(p0: Vector3, p1: Vector3, cf: CFrame, he: Vector3): number
	local c0 = closestPointOnObb(cf, he, p0)
	local c1 = closestPointOnObb(cf, he, p1)
	return math.min((p0 - c0).Magnitude, (p1 - c1).Magnitude)
end

local function volumeHitsPart(config: Types.HitboxConfig, segFrom: CFrame, segTo: CFrame, tcf: CFrame, he: Vector3): boolean
	if config.Shape == "Box" then
		-- weapon box only tested at the segment's two endpoint poses, same tradeoff as above, live with it
		return obbOverlap(segFrom, config.HalfExtents :: Vector3, tcf, he)
			or obbOverlap(segTo, config.HalfExtents :: Vector3, tcf, he)
	end
	return segmentObbDistance(segFrom.Position, segTo.Position, tcf, he) <= (config.Radius :: number)
end

export type RewindPoseLookup = (model: Model) -> { [string]: CFrame }?
export type TrackedPartsLookup = (model: Model) -> { [string]: BasePart }?

-- confirms one segment (a melee sub-step, or the single segment a hitscan/projectile/radius kind
-- reduces down to) against a candidate list, using each candidate's rewound pose. alreadyHit gets
-- shared across the WHOLE swing by the caller, so later segments skip targets already confirmed -
-- don't reset it per-segment or you'll double-hit people
function SweepResolver.ConfirmRewound(
	config: Types.HitboxConfig,
	segFrom: CFrame,
	segTo: CFrame,
	subStepIndex: number,
	toi: number,
	candidates: { Model },
	rewindPose: RewindPoseLookup,
	trackedParts: TrackedPartsLookup,
	alreadyHit: { [Model]: boolean }
): { Types.HitResult }
	local hits: { Types.HitResult } = {}
	local dir = segTo.Position - segFrom.Position
	local normal = if dir.Magnitude > 1e-4 then dir.Unit else Vector3.yAxis

	for _, model in candidates do
		if not alreadyHit[model] then
			local pose = rewindPose(model)
			local parts = trackedParts(model)
			if pose and parts then
				for name, tcf in pose do
					local part = parts[name]
					if part and volumeHitsPart(config, segFrom, segTo, tcf, part.Size / 2) then
						local hit = resultPool:Checkout()
						hit.Target = model
						hit.HitPart = part
						hit.Point = tcf.Position
						hit.Normal = normal
						hit.TOI = toi
						hit.SubStepIndex = subStepIndex
						hit.Distance = (tcf.Position - segFrom.Position).Magnitude

						table.insert(hits, hit)
						alreadyHit[model] = true
						break
					end
				end
			end
		end
	end

	return hits
end

-- muzzle to max range, effectively zero duration - still a real sweep, not just a raw raycast we
-- pretend is good enough
function SweepResolver.ResolveHitscan(
	config: Types.HitboxConfig,
	origin: CFrame,
	maxDistance: number,
	filter: Types.QueryFilter
): { Types.HitResult }
	local to = origin + origin.LookVector * maxDistance
	local hit = SweepResolver.ResolveSegment({
		Shape = config.Shape,
		HalfExtents = config.HalfExtents,
		Radius = config.Radius,
		From = origin,
		To = to,
		Filter = filter,
	}, 0, 0, nil)

	if hit then
		return { hit }
	end
	return {}
end

-- one tick of a server-owned projectile - same tunnel-proof primitive as a single melee sub-step,
-- no separate code path needed just because it's a projectile
function SweepResolver.ResolveProjectileStep(
	config: Types.HitboxConfig,
	from: CFrame,
	to: CFrame,
	filter: Types.QueryFilter
): Types.HitResult?
	return SweepResolver.ResolveSegment({
		Shape = config.Shape,
		HalfExtents = config.HalfExtents,
		Radius = config.Radius,
		From = from,
		To = to,
		Filter = filter,
	}, 0, 0, nil)
end

function SweepResolver.ResolveRadius(config: Types.HitboxConfig, center: CFrame, filter: Types.QueryFilter): { Types.HitResult }
	return SweepResolver.ResolveStationary(config.Shape, config.HalfExtents, config.Radius, center, filter)
end

return SweepResolver
