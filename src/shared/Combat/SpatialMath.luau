--!strict

local SpatialMath = {}

function SpatialMath.AngleBetween(a: CFrame, b: CFrame): number
	local dot = math.clamp(a.LookVector:Dot(b.LookVector), -1, 1)
	return math.deg(math.acos(dot))
end

function SpatialMath.IsFacing(observer: CFrame, targetPosition: Vector3, maxAngleDegrees: number): boolean
	local toTarget = targetPosition - observer.Position
	if toTarget.Magnitude < 1e-4 then
		return true 
	end

	local dot = math.clamp(observer.LookVector:Dot(toTarget.Unit), -1, 1)
	return math.deg(math.acos(dot)) <= maxAngleDegrees
end

function SpatialMath.HorizontalDistance(a: Vector3, b: Vector3): number
	local delta = b - a
	return Vector2.new(delta.X, delta.Z).Magnitude
end

return SpatialMath
