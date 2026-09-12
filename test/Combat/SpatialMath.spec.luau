local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpatialMath = require(ReplicatedStorage.Shared.Combat.SpatialMath)

return function()
	describe("SpatialMath.AngleBetween", function()
		it("is 0 for two identical facings", function()
			local cf = CFrame.new(0, 0, 0)
			expect(SpatialMath.AngleBetween(cf, cf)).to.be.near(0, 0.01)
		end)

		it("is 90 for perpendicular facings", function()
			local a = CFrame.new()
			local b = CFrame.Angles(0, math.rad(90), 0)
			expect(SpatialMath.AngleBetween(a, b)).to.be.near(90, 0.01)
		end)

		it("is 180 for dead-opposite facings", function()
			local a = CFrame.new()
			local b = CFrame.Angles(0, math.rad(180), 0)
			expect(SpatialMath.AngleBetween(a, b)).to.be.near(180, 0.01)
		end)
	end)

	describe("SpatialMath.IsFacing", function()
		it("is true for a target directly ahead", function()
			local observer = CFrame.new(0, 0, 0) -- default LookVector is -Z
			expect(SpatialMath.IsFacing(observer, Vector3.new(0, 0, -10), 45)).to.equal(true)
		end)

		it("is false for a target directly behind, within a narrow cone", function()
			local observer = CFrame.new(0, 0, 0)
			expect(SpatialMath.IsFacing(observer, Vector3.new(0, 0, 10), 45)).to.equal(false)
		end)

		it("is true for a target directly behind when the cone is wide enough (180)", function()
			local observer = CFrame.new(0, 0, 0)
			expect(SpatialMath.IsFacing(observer, Vector3.new(0, 0, 10), 180)).to.equal(true)
		end)

		it("treats standing on top of the target as facing (degenerate direction)", function()
			local observer = CFrame.new(5, 0, 5)
			expect(SpatialMath.IsFacing(observer, Vector3.new(5, 0, 5), 1)).to.equal(true)
		end)

		it("respects the edge of the cone (a target exactly on the boundary counts as facing)", function()
			local observer = CFrame.new(0, 0, 0)
			-- 45 degrees off dead-ahead (-Z), to the +X side
			local target = Vector3.new(10, 0, -10)
			expect(SpatialMath.IsFacing(observer, target, 45)).to.equal(true)
			expect(SpatialMath.IsFacing(observer, target, 44)).to.equal(false)
		end)
	end)

	describe("SpatialMath.HorizontalDistance", function()
		it("ignores vertical separation entirely", function()
			local a = Vector3.new(0, 0, 0)
			local b = Vector3.new(0, 500, 0) -- straight up, same X/Z
			expect(SpatialMath.HorizontalDistance(a, b)).to.equal(0)
		end)

		it("matches straight-line distance for two points at the same height", function()
			local a = Vector3.new(0, 10, 0)
			local b = Vector3.new(3, 10, 4) -- 3-4-5 triangle
			expect(SpatialMath.HorizontalDistance(a, b)).to.be.near(5, 0.001)
		end)
	end)
end
