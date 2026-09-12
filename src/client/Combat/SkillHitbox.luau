--!strict

-- thin wrapper a skill's Activate actually touches on the client. server half's a separate file
-- (server/Combat/SkillHitbox.luau) - HitboxClient lives under each player's own PlayerScripts copy,
-- there's no fixed path a shared module could reach cleanly to grab it.
--
-- IMPORTANT: reached via a path RELATIVE to script, NOT an absolute StarterPlayerScripts path. this
-- file and HitboxClient.luau are both descendants of the SAME running Client LocalScript instance -
-- the live copy under PlayerScripts, not the template sitting in StarterPlayerScripts. go absolute
-- and you'd require the template instead, which spins up a second, completely separate,
-- never-initialized HitboxClient. that's a real bug that'll waste an hour of your life, not a style nit
local HitboxTypes = require(game:GetService("ReplicatedStorage").Shared.Hitbox.Types)
local HitboxClient = require(script.Parent.Parent.Hitbox.HitboxClient)

type HitboxConfig = HitboxTypes.HitboxConfig
type MotionSample = HitboxTypes.MotionSample

local SkillHitbox = {}

-- signature mirrors the server half's RegisterWeapon(skillId, hitboxConfig, damageSpec) on purpose.
-- shared Skills/*.luau content calls context.Hitbox.RegisterWeapon(...) positionally with no idea
-- which realm it's in, so both realms have to take the same argument order even though the client
-- only actually wants hitboxConfig out of it - no damage bridge, no weaponId->skillId anti-cheat
-- map client side, that stuff doesn't belong here
function SkillHitbox.RegisterWeapon(_skillId: string, hitboxConfig: HitboxConfig, _damageSpec: any): ()
	HitboxClient.RegisterWeapon(hitboxConfig)
end

function SkillHitbox.RequestAttack(
	weaponId: string,
	motion: { MotionSample }?,
	origin: CFrame?,
	maxDistance: number?,
	velocity: Vector3?
): ()
	HitboxClient.RequestAttack(weaponId, motion, origin, maxDistance, velocity)
end

return SkillHitbox
