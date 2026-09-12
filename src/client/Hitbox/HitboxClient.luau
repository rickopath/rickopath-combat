--!strict

-- predicted feedback + server reconciliation, entry point wired from src/client/init.client.luau.
-- NEVER mutates health here - the predicted pass is purely cosmetic, the server is the only
-- authority that's allowed to actually apply damage, don't get any ideas
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Hitbox.Types)
local ConfigModule = require(ReplicatedStorage.Shared.Hitbox.Config)
local Net = require(ReplicatedStorage.Shared.Hitbox.Net)
local SweepResolver = require(ReplicatedStorage.Shared.Hitbox.SweepResolver)
local DebugDraw = require(ReplicatedStorage.Shared.Hitbox.DebugDraw)
local Signal = require(ReplicatedStorage.Shared.Hitbox.Signal)

local HitboxClient = {}

local cfg: ConfigModule.Config = ConfigModule
local weapons: { [string]: Types.HitboxConfig } = {}
local sequenceCounter = 0

type PendingSwing = {
	PredictedTargets: { [Model]: boolean },
	StartTime: number,
}

local pending: { [number]: PendingSwing } = {}

-- (target: Model, state: "Predicted" | "Confirmed" | "Retracted") - your game hooks its own
-- VFX/damage numbers off this signal, this module has zero opinion on presentation
HitboxClient.OnHitFeedback = Signal.new()

function HitboxClient.RegisterWeapon(config: Types.HitboxConfig): ()
	weapons[config.Id] = config
end

local function localFilter(): Types.QueryFilter
	local character = Players.LocalPlayer.Character
	return {
		ExcludeInstances = if character then { character } else nil,
		IncludeInstances = nil,
	}
end

-- predicted pass against whatever's currently rendered, zero input lag, purely cosmetic - if this
-- disagrees with the server later, the server wins, no exceptions
local function predictLocally(config: Types.HitboxConfig, request: Types.AttackRequest): { Types.HitResult }
	local filter = localFilter()

	if config.Kind == "Melee" and request.Motion then
		return SweepResolver.ResolveMelee(
			config,
			request.Motion,
			filter,
			cfg.MinSweepSubSteps,
			cfg.MaxSweepSubSteps,
			cfg.MaxDegreesPerSweepSubStep
		)
	elseif config.Kind == "Hitscan" and request.Origin and request.MaxDistance then
		return SweepResolver.ResolveHitscan(config, request.Origin, request.MaxDistance, filter)
	elseif config.Kind == "Radius" and request.Origin then
		return SweepResolver.ResolveRadius(config, request.Origin, filter)
	end

	return {}
end

function HitboxClient.RequestAttack(
	weaponId: string,
	motion: { Types.MotionSample }?,
	origin: CFrame?,
	maxDistance: number?,
	velocity: Vector3?
): ()
	local config = weapons[weaponId]
	if not config then
		return
	end

	sequenceCounter += 1
	local request: Types.AttackRequest = {
		WeaponId = weaponId,
		Kind = config.Kind,
		SequenceId = sequenceCounter,
		ClientTimestamp = workspace:GetServerTimeNow(),
		Motion = motion,
		Origin = origin,
		MaxDistance = maxDistance,
		Velocity = velocity,
	}

	local predicted = predictLocally(config, request)
	local predictedTargets: { [Model]: boolean } = {}
	for _, hit in predicted do
		predictedTargets[hit.Target] = true
		HitboxClient.OnHitFeedback:Fire(hit.Target, "Predicted")
		DebugDraw.Ray(hit.Point - hit.Normal, hit.Normal, Color3.new(1, 1, 0))
		SweepResolver.ResultPool:Return(hit)
	end

	pending[request.SequenceId] = {
		PredictedTargets = predictedTargets,
		StartTime = os.clock(),
	}

	Net.FireAttackRequest(request)
end

local function onAttackResult(result: Types.AttackResult): ()
	local swing = pending[result.SequenceId]
	pending[result.SequenceId] = nil

	local confirmedTargets: { [Model]: boolean } = {}
	for _, hit in result.Hits do
		confirmedTargets[hit.Target] = true
		if not swing or not swing.PredictedTargets[hit.Target] then
			-- rewind gave the attacker a hit the live client view never predicted - fine, confirm
			-- it late, the server's allowed to know things the client's eyes didn't catch
			HitboxClient.OnHitFeedback:Fire(hit.Target, "Confirmed")
		end
	end

	if swing then
		for target in swing.PredictedTargets do
			if not confirmedTargets[target] then
				HitboxClient.OnHitFeedback:Fire(target, "Retracted")
			end
		end
	end
end

-- how many predicted swings are still waiting on a server AttackResult right now - what
-- DebugOverlay's "Pending attacks" line reads. counts pending, not iterates it, so this stays cheap
-- to poll every overlay refresh tick
function HitboxClient.GetPendingCount(): number
	local count = 0
	for _ in pending do
		count += 1
	end
	return count
end

function HitboxClient.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end

	Net.OnAttackResult(onAttackResult)

	-- periodic sweep for dropped responses (packet lost, server never replied) - one sweep, not a
	-- task.delay per swing, same pattern as everywhere else in this library
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for sequenceId, swing in pending do
			if now - swing.StartTime > cfg.ClientReconcileTimeoutSeconds then
				pending[sequenceId] = nil
			end
		end
	end)
end

return HitboxClient
