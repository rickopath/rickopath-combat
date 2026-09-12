--!strict

-- physics knockback. server-only, has to be - this mutates a real BasePart's velocity, and a
-- client-authoritative version of that is just a movement exploit with extra steps. nothing calls
-- this automatically, wire it into a skill's OnHit yourself: Knockback.Apply(target.Model, dir, speed)
local Knockback = {}

-- overwrites horizontal velocity, preserves vertical - a knockback that also cancels your jump/fall
-- feels awful and isn't what "knockback" means to anyone. direction gets normalized here so callers
-- can pass a raw displacement vector (attacker -> target, say) without normalizing it themselves
function Knockback.Apply(character: Model, direction: Vector3, speed: number): ()
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	if direction.Magnitude < 1e-4 then
		return -- degenerate direction (attacker standing exactly on top of target) - nothing sane to push toward
	end

	local horizontal = direction.Unit * speed
	local current = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(horizontal.X, current.Y, horizontal.Z)
end

return Knockback
