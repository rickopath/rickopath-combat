--!strict
-- Base melee skill example.
-- 
-- `Activate` runs on both client and server.
-- Capability checks (e.g. `if hitbox.RequestAttack then`) are used instead of `RunService:IsServer()`. 
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)
local MotionSampler = require(ReplicatedStorage.Shared.Combat.MotionSampler)
local DamageType = require(ReplicatedStorage.Shared.Combat.DamageType)
local HitboxTypes = require(ReplicatedStorage.Shared.Hitbox.Types)

type SkillContext = SkillModule.SkillContext
type HitboxConfig = HitboxTypes.HitboxConfig
type Keyframe = MotionSampler.Keyframe

local ID = "Punch"

local HITBOX_CONFIG: HitboxConfig = {
	Id = ID,
	Kind = "Melee",
	Shape = "Box",
	HalfExtents = Vector3.new(2, 2.5, 3),
	AttachOffset = CFrame.new(0, 0, -2.5),
	MaxTargetsPerSwing = 5,
	FriendlyFire = false,
}

local DAMAGE_SPEC = {
	DamageType = DamageType.Physical,
	Amount = 12,
}

-- a swing needs a motion arc so the server can sweep it. T is seconds from swing start
local SWING_DURATION = 0.2
local KEYFRAMES: { Keyframe } = {
	{ T = 0, Offset = CFrame.Angles(0, math.rad(-40), 0) },
	{ T = SWING_DURATION, Offset = CFrame.Angles(0, math.rad(40), 0) },
}

local Punch = SkillModule.extend("Punch")

-- Luau strict-mode class assignment.
;(Punch :: any).Activate = function(self: SkillModule.Skill): boolean
	local hitbox = self.Context.Hitbox
	if hitbox.RequestAttack then
		local basePose = self.Context.Owner:GetPivot()
		local motion = MotionSampler.FromKeyframes(basePose, HITBOX_CONFIG.AttachOffset, KEYFRAMES)
		-- (weaponId, motion, origin, maxDistance, velocity) - melee only needs motion
		hitbox.RequestAttack(self.Id, motion, nil, nil, nil)
	end
	return true -- false = activation failed, no cooldown starts
end

SkillRegistry.Register(ID, function(context: SkillContext): SkillModule.Skill
	context.Hitbox.RegisterWeapon(ID, HITBOX_CONFIG, DAMAGE_SPEC)
	return Punch.new({
		Id = ID,
		DisplayName = "Punch",
		Cooldown = 0.6,
		Costs = { { ResourceId = "Stamina", Amount = 8 } },
	}, context)
end)

return Punch
