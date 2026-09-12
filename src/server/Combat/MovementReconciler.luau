--!strict

-- server authority for skill-driven movement: validates a requested displacement against real world
-- geometry before accepting it, reusing Hitbox's SpatialQuery.Spherecast instead of hand-rolling yet
-- another raycast. true rollback (full state resimulation) just isn't practical on Roblox - there's
-- no deterministic physics resimulation API to build it on - so this follows the pattern that's
-- actually achievable and actually shipped: predict, then reconcile
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitboxTypes = require(ReplicatedStorage.Shared.Hitbox.Types)
local SpatialQuery = require(ReplicatedStorage.Shared.Hitbox.SpatialQuery)
local ConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local MovementTypes = require(ReplicatedStorage.Shared.Combat.Movement.Types)
local MovementNet = require(ReplicatedStorage.Shared.Combat.Movement.Net)
local CombatantRegistry = require(script.Parent.CombatantRegistry)
local CombatantSkills = require(script.Parent.CombatantSkills)

type QueryFilter = HitboxTypes.QueryFilter
type MovementRequest = MovementTypes.MovementRequest

local cfg: ConfigModule.Config = ConfigModule

local function pathBlocked(from: CFrame, to: CFrame, exclude: { Instance }): boolean
	local filter: QueryFilter = { ExcludeInstances = exclude, IncludeInstances = nil }
	local res = SpatialQuery.Spherecast(from.Position, cfg.MovementProbeRadius, to.Position - from.Position, filter)
	return res ~= nil
end

local function onMovementRequest(player: Player, request: MovementRequest): ()
	local character = player.Character
	if not character then
		return
	end

	local combatant = CombatantRegistry.Get(character)
	if not combatant then
		return -- no combatant, nothing to reconcile against, reject silently and move on
	end

	-- rooted - reject BEFORE even trying to activate the skill, not after. checking this later
	-- (down where `accepted` gets computed) would still let TryActivate spend the skill's Stamina
	-- and start its cooldown for a dash that was never going anywhere - charging someone for a move
	-- they didn't get is a real fairness bug, not just a wasted spherecast
	if combatant.IsMovementLocked then
		MovementNet.FireMovementResult(player, {
			SequenceId = request.SequenceId,
			Accepted = false,
			AuthoritativeCFrame = character:GetPivot(),
			ServerTimestamp = workspace:GetServerTimeNow(),
		})
		return
	end

	-- same reasoning as CombatServer's isAttackAllowed, go read that comment if this feels
	-- redundant: a client that only ever fires raw MovementRequests and never sends ActivateSkill
	-- would otherwise never pay Stamina or start Dash's cooldown at all, because nothing
	-- else calls TryActivate for a request-less SkillId. calling it right here is what makes this
	-- gate self-sufficient and order-independent, actually closing that off instead of hoping for
	-- the best. short-circuits before the pathBlocked spherecast below when the skill doesn't check
	-- out, so a request that's getting rejected for cost/cooldown anyway doesn't also pay for a
	-- query it was never going to need
	local skill = CombatantSkills.Get(character, request.SkillId)
	local skillAllows = false
	if skill then
		local activated, reason = skill:TryActivate()
		skillAllows = activated or reason == "cooldown"
	end

	local now = workspace:GetServerTimeNow()
	local dist = (request.To.Position - request.From.Position).Magnitude

	-- reject, don't error - this is adversarial input, same posture HitboxServer.validate takes
	local accepted = skillAllows
		and dist <= request.MaxDistance
		and not combatant.IsDead
		and not pathBlocked(request.From, request.To, { character })

	local authoritative = if accepted then request.To else character:GetPivot()

	MovementNet.FireMovementResult(player, {
		SequenceId = request.SequenceId,
		Accepted = accepted,
		AuthoritativeCFrame = authoritative,
		ServerTimestamp = now,
	})
end

local MovementReconciler = {}

function MovementReconciler.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end
	MovementNet.OnMovementRequest(onMovementRequest)
end

return MovementReconciler
