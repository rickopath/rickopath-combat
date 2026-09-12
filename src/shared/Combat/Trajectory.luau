--!strict

-- Helpers for HitboxServer.SpawnProjectileAlongPath.

export type Path = (t: number) -> CFrame

local Trajectory = {}

local function pathFromPointFunction(pointAt: (t: number) -> Vector3): Path
	return function(t: number): CFrame
		local clamped = math.clamp(t, 0, 1)
		local pos = pointAt(clamped)

		local aheadT = math.min(clamped + 0.01, 1)
		local behindT = math.max(clamped - 0.01, 0)
		local dir = pointAt(aheadT) - pointAt(behindT)

		if dir.Magnitude < 1e-4 then
			return CFrame.new(pos)
		end
		return CFrame.lookAt(pos, pos + dir)
	end
end

-- Linear interpolation.
function Trajectory.Linear(p0: Vector3, p1: Vector3): Path
	return pathFromPointFunction(function(t: number): Vector3
		return p0:Lerp(p1, t)
	end)
end

-- Quadratic bezier curve.
function Trajectory.QuadraticBezier(p0: Vector3, p1: Vector3, p2: Vector3): Path
	return pathFromPointFunction(function(t: number): Vector3
		local oneMinusT = 1 - t
		return oneMinusT * oneMinusT * p0 + 2 * oneMinusT * t * p1 + t * t * p2
	end)
end

-- Cubic bezier curve.
function Trajectory.CubicBezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3): Path
	return pathFromPointFunction(function(t: number): Vector3
		local oneMinusT = 1 - t
		local a = oneMinusT * oneMinusT * oneMinusT
		local b = 3 * oneMinusT * oneMinusT * t
		local c = 3 * oneMinusT * t * t
		local d = t * t * t
		return a * p0 + b * p1 + c * p2 + d * p3
	end)
end

return Trajectory
