local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trajectory = require(ReplicatedStorage.Shared.Combat.Trajectory)

local function expectPositionNear(cframe: CFrame, expected: Vector3, epsilon: number)
	expect((cframe.Position - expected).Magnitude).to.be.near(0, epsilon)
end

return function()
	describe("Trajectory.Linear", function()
		local p0 = Vector3.new(0, 5, 0)
		local p1 = Vector3.new(0, 5, -20)
		local path = Trajectory.Linear(p0, p1)

		it("starts exactly at p0", function()
			expectPositionNear(path(0), p0, 0.001)
		end)

		it("ends exactly at p1", function()
			expectPositionNear(path(1), p1, 0.001)
		end)

		it("is the midpoint at t=0.5", function()
			expectPositionNear(path(0.5), p0:Lerp(p1, 0.5), 0.001)
		end)

		it("clamps t below 0 to the start", function()
			expectPositionNear(path(-5), p0, 0.001)
		end)

		it("clamps t above 1 to the end", function()
			expectPositionNear(path(5), p1, 0.001)
		end)

		it("faces the direction of travel", function()
			-- traveling straight down -Z, LookVector should point roughly that way
			local look = path(0).LookVector
			expect((look - Vector3.new(0, 0, -1)).Magnitude).to.be.near(0, 0.05)
		end)
	end)

	describe("Trajectory.QuadraticBezier", function()
		local p0 = Vector3.new(0, 0, 0)
		local p1 = Vector3.new(0, 20, -15) -- arc peak
		local p2 = Vector3.new(0, 0, -30)
		local path = Trajectory.QuadraticBezier(p0, p1, p2)

		it("starts exactly at p0 and ends exactly at p2 (control point is never reached)", function()
			expectPositionNear(path(0), p0, 0.001)
			expectPositionNear(path(1), p2, 0.001)
		end)

		it("rises above the start/end height partway through the arc", function()
			expect(path(0.5).Position.Y).to.be.near(p1.Y * 0.5, 0.5) -- t=0.5 quadratic weight on p1 is 0.5
			expect(path(0.5).Position.Y > p0.Y).to.equal(true)
		end)
	end)

	describe("Trajectory.CubicBezier", function()
		local p0 = Vector3.new(0, 0, 0)
		local p1 = Vector3.new(10, 0, -5)
		local p2 = Vector3.new(-10, 0, -15)
		local p3 = Vector3.new(0, 0, -20)
		local path = Trajectory.CubicBezier(p0, p1, p2, p3)

		it("starts exactly at p0 and ends exactly at p3", function()
			expectPositionNear(path(0), p0, 0.001)
			expectPositionNear(path(1), p3, 0.001)
		end)

		it("can bend one way then the other (an S-curve), unlike a quadratic", function()
			-- p1/p2 pull in opposite X directions - the path should cross back over X=0 somewhere
			-- in the middle rather than monotonically drifting to one side
			local midX = path(0.5).Position.X
			expect(math.abs(midX) < math.abs(p1.X)).to.equal(true)
		end)
	end)
end
