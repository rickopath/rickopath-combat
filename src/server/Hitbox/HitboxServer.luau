--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Hitbox.Types)
local ConfigModule = require(ReplicatedStorage.Shared.Hitbox.Config)
local Net = require(ReplicatedStorage.Shared.Hitbox.Net)
local SweepResolver = require(ReplicatedStorage.Shared.Hitbox.SweepResolver)
local DebugDraw = require(ReplicatedStorage.Shared.Hitbox.DebugDraw)

local AliveRegistry = require(script.Parent.AliveRegistry)
local HitRegistry = require(script.Parent.HitRegistry)

local HitboxServer = {}

local cfg: ConfigModule.Config = ConfigModule
local alive: AliveRegistry.AliveRegistry? = nil
local registry = HitRegistry.new()
local weapons: { [string]: Types.HitboxConfig } = {}

local lastSequence: { [string]: number } = {}
local cleanupAccum = 0

local function sequenceKey(player: Player, weaponId: string): string
	return string.format("%d:%s", player.UserId, weaponId)
end

function HitboxServer.RegisterWeapon(config: Types.HitboxConfig): ()
	weapons[config.Id] = config
end

local function requestOrigin(request: Types.AttackRequest): CFrame?
	if request.Motion and #request.Motion > 0 then
		return request.Motion[1].CFrame
	end
	return request.Origin
end

local function weaponReach(config: Types.HitboxConfig): number
	return if config.Shape == "Box" then (config.HalfExtents :: Vector3).Magnitude else (config.Radius :: number)
end

local function validate(player: Player, request: Types.AttackRequest, now: number, config: Types.HitboxConfig): boolean
	local key = sequenceKey(player, request.WeaponId)
	local last = lastSequence[key] or 0
	if request.SequenceId <= last then
		return false
	end

	if request.ClientTimestamp > now + cfg.InterpolationDelaySeconds then
		return false 
	end
	if now - request.ClientTimestamp > cfg.MaxRewindSeconds then
		return false 
	end

	local origin = requestOrigin(request)
	local character = player.Character
	if not origin or not character then
		return false
	end

	local pos = character:GetPivot().Position
	local ping = player:GetNetworkPing()
	local tolerance = cfg.MaxLatencyToleranceStuds + cfg.MaxCharacterSpeed * (ping + cfg.InterpolationDelaySeconds) + weaponReach(config)
	if (origin.Position - pos).Magnitude > tolerance then
		return false 
	end

	if not cfg.IsAttackAllowed(player, request) then
		return false 
	end

	lastSequence[key] = request.SequenceId
	return true
end

local function computeRewindTimestamp(player: Player, now: number): number
	local ping = player:GetNetworkPing()
	local rewindT = now - (ping + cfg.InterpolationDelaySeconds)
	return math.clamp(rewindT, now - cfg.MaxRewindSeconds, now)
end

local function broadPhaseMargin(config: Types.HitboxConfig): number
	return weaponReach(config) + cfg.MaxCharacterSpeed * cfg.RewindBufferDepthSeconds
end

local function resolveHits(
	config: Types.HitboxConfig,
	request: Types.AttackRequest,
	rewindT: number,
	registryInstance: AliveRegistry.AliveRegistry,
	attackerCharacter: Model?
): { Types.HitResult }
	local origin = requestOrigin(request)
	if not origin then
		return {}
	end

	local candidates = registryInstance:GetCandidates(origin.Position, broadPhaseMargin(config))
	if attackerCharacter then
		for i = #candidates, 1, -1 do
			if candidates[i] == attackerCharacter then
				table.remove(candidates, i)
			end
		end
	end
	local rewindPose = function(model: Model)
		return registryInstance:GetRewindPose(model, rewindT)
	end
	local trackedParts = function(model: Model)
		return registryInstance:GetTrackedParts(model)
	end

	local alreadyHit: { [Model]: boolean } = {}
	local hits: { Types.HitResult } = {}

	if config.Kind == "Melee" then
		local motion = request.Motion
		if not motion then
			return hits
		end
		for _, seg in SweepResolver.BuildMeleeSegments(motion, cfg.MinSweepSubSteps, cfg.MaxSweepSubSteps, cfg.MaxDegreesPerSweepSubStep) do
			local segHits = SweepResolver.ConfirmRewound(config, seg.From, seg.To, seg.SubStepIndex, seg.TOI, candidates, rewindPose, trackedParts, alreadyHit)
			for _, hit in segHits do
				table.insert(hits, hit)
			end
			if #hits >= config.MaxTargetsPerSwing then
				break
			end
		end
	elseif config.Kind == "Hitscan" then
		local maxDist = request.MaxDistance
		if not maxDist then
			return hits
		end
		local to = origin + origin.LookVector * maxDist
		hits = SweepResolver.ConfirmRewound(config, origin, to, 0, 0, candidates, rewindPose, trackedParts, alreadyHit)
	elseif config.Kind == "Radius" then
		hits = SweepResolver.ConfirmRewound(config, origin, origin, 0, 0, candidates, rewindPose, trackedParts, alreadyHit)
	end

	if #hits > config.MaxTargetsPerSwing then
		local trimmed: { Types.HitResult } = table.create(config.MaxTargetsPerSwing)
		for i = 1, config.MaxTargetsPerSwing do
			trimmed[i] = hits[i]
		end
		for i = config.MaxTargetsPerSwing + 1, #hits do
			SweepResolver.ResultPool:Return(hits[i])
		end
		hits = trimmed
	end

	return hits
end

local function onAttackRequest(player: Player, request: Types.AttackRequest): ()
	local now = workspace:GetServerTimeNow()

	local config = weapons[request.WeaponId]
	local registryInstance = alive
	if not config or not registryInstance then
		return
	end

	if not validate(player, request, now, config) then
		return
	end

	local rewindT = computeRewindTimestamp(player, now)

	local hits: { Types.HitResult } = {}
	local ok, err = pcall(function()
		hits = resolveHits(config, request, rewindT, registryInstance, player.Character)
	end)
	if not ok then
		warn(string.format("[HitboxServer] resolveHits errored for weapon=%s: %s", request.WeaponId, tostring(err)))
	end

	local confirmedHits: { Types.HitResult } = {}
	if ok then
		local swingKey = string.format("%d:%s:%d", player.UserId, request.WeaponId, request.SequenceId)
		for _, hit in hits do
			if registry:TryRegisterHit(swingKey, hit.Target, now, cfg.HitRegistryTTLSeconds) then
				table.insert(confirmedHits, hit)
				hit.Meta = request.WeaponId
				cfg.OnApplyDamage(player, hit)
			end
		end
	end

	Net.FireAttackResult(player, {
		SequenceId = request.SequenceId,
		Hits = confirmedHits,
		ServerTimestamp = now,
	})

	for _, hit in hits do
		SweepResolver.ResultPool:Return(hit)
	end
end

type ProjectileState = {
	Attacker: Player,
	Config: Types.HitboxConfig,
	Pos: CFrame,
	Velocity: Vector3?,
	Path: ((t: number) -> CFrame)?,
	PathDuration: number?,
	Elapsed: number,
	MaxLifetime: number,
	Margin: number, 
}

local activeProjectiles: { ProjectileState } = {}
local projectileAlreadyHitScratch: { [Model]: boolean } = {}

function HitboxServer.SpawnProjectile(
	attacker: Player,
	config: Types.HitboxConfig,
	initialCFrame: CFrame,
	velocity: Vector3,
	maxLifetime: number
): ()
	if not alive then
		return
	end

	table.insert(activeProjectiles, {
		Attacker = attacker,
		Config = config,
		Pos = initialCFrame,
		Velocity = velocity,
		Elapsed = 0,
		MaxLifetime = maxLifetime,
		Margin = broadPhaseMargin(config),
	})
end

function HitboxServer.SpawnProjectileAlongPath(
	attacker: Player,
	config: Types.HitboxConfig,
	path: (t: number) -> CFrame,
	duration: number,
	maxLifetime: number
): ()
	if not alive then
		return
	end

	table.insert(activeProjectiles, {
		Attacker = attacker,
		Config = config,
		Pos = path(0),
		Path = path,
		PathDuration = duration,
		Elapsed = 0,
		MaxLifetime = maxLifetime,
		Margin = broadPhaseMargin(config),
	})
end

local function tickProjectiles(dt: number): ()
	local registryInstance = alive
	if not registryInstance or #activeProjectiles == 0 then
		return
	end

	local now = workspace:GetServerTimeNow()
	local rewindT = now - cfg.InterpolationDelaySeconds

	local positions = registryInstance:SnapshotPositions()

	local rewindPose = function(model: Model)
		return registryInstance:GetRewindPose(model, rewindT)
	end
	local trackedParts = function(model: Model)
		return registryInstance:GetTrackedParts(model)
	end

	for i = #activeProjectiles, 1, -1 do
		local proj = activeProjectiles[i]
		proj.Elapsed += dt

		local nextPos: CFrame
		local path = proj.Path
		if path then
			local duration = proj.PathDuration :: number
			local t = if duration > 0 then proj.Elapsed / duration else 1
			nextPos = path(t)
		else
			nextPos = proj.Pos + (proj.Velocity :: Vector3) * dt
		end

		local candidates = registryInstance:GetCandidatesFromPositions(positions, proj.Pos.Position, proj.Margin)
		local attackerCharacter = proj.Attacker.Character
		if attackerCharacter then
			for ci = #candidates, 1, -1 do
				if candidates[ci] == attackerCharacter then
					table.remove(candidates, ci)
				end
			end
		end

		table.clear(projectileAlreadyHitScratch)
		local hits = SweepResolver.ConfirmRewound(proj.Config, proj.Pos, nextPos, 0, 0, candidates, rewindPose, trackedParts, projectileAlreadyHitScratch)

		DebugDraw.Ray(proj.Pos.Position, nextPos.Position - proj.Pos.Position, Color3.new(0.3, 0.6, 1), 0.3)

		proj.Pos = nextPos

		if #hits > 0 or proj.Elapsed >= proj.MaxLifetime then
			activeProjectiles[i] = activeProjectiles[#activeProjectiles]
			table.remove(activeProjectiles)

			for _, hit in hits do
				hit.Meta = proj.Config.Id
				cfg.OnApplyDamage(proj.Attacker, hit)
				SweepResolver.ResultPool:Return(hit)
			end
		end
	end
end

function HitboxServer.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end

	alive = AliveRegistry.new(cfg.RewindBufferDepthSeconds, cfg.RewindSampleIntervalSeconds)

	Net.OnAttackRequest(onAttackRequest)

	RunService.Heartbeat:Connect(function(dt: number)
		cleanupAccum += dt
		if cleanupAccum >= cfg.HitRegistryCleanupIntervalSeconds then
			cleanupAccum = 0
			registry:CleanupExpired(workspace:GetServerTimeNow())
		end

		tickProjectiles(dt)
	end)
end

return HitboxServer
