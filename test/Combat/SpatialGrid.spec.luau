local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpatialGrid = require(ReplicatedStorage.Shared.Combat.SpatialGrid)

local function contains(list: { string }, value: string): boolean
	for _, v in list do
		if v == value then
			return true
		end
	end
	return false
end

return function()
	describe("SpatialGrid", function()
		it("returns nothing on an empty grid", function()
			local grid = SpatialGrid.new(50)
			expect(#grid:QueryRadius(Vector3.new(0, 0, 0), 1000)).to.equal(0)
		end)

		it("finds an entry well within radius", function()
			local grid = SpatialGrid.new(50)
			grid:Insert("Near", Vector3.new(10, 0, 0))
			local found = grid:QueryRadius(Vector3.new(0, 0, 0), 20)
			expect(contains(found, "Near")).to.equal(true)
		end)

		it("excludes an entry well outside radius", function()
			local grid = SpatialGrid.new(50)
			grid:Insert("Far", Vector3.new(1000, 0, 0))
			local found = grid:QueryRadius(Vector3.new(0, 0, 0), 20)
			expect(contains(found, "Far")).to.equal(false)
		end)

		it("still finds an entry that's near but in an adjacent cell", function()
			-- cellSize 50: querying from (49, 0, 0) with radius 5 should still reach an entry at
			-- (52, 0, 0), which sits in the NEXT cell over - this is the whole reason QueryRadius
			-- walks neighboring cells instead of just the origin cell
			local grid = SpatialGrid.new(50)
			grid:Insert("JustAcrossTheBoundary", Vector3.new(52, 0, 0))
			local found = grid:QueryRadius(Vector3.new(49, 0, 0), 5)
			expect(contains(found, "JustAcrossTheBoundary")).to.equal(true)
		end)

		it("ignores Y entirely - it's a horizontal grid", function()
			local grid = SpatialGrid.new(50)
			grid:Insert("FarAbove", Vector3.new(0, 10000, 0))
			local found = grid:QueryRadius(Vector3.new(0, 0, 0), 10)
			expect(contains(found, "FarAbove")).to.equal(true)
		end)

		it("returns multiple matches when several entries are in range", function()
			local grid = SpatialGrid.new(50)
			grid:Insert("A", Vector3.new(5, 0, 0))
			grid:Insert("B", Vector3.new(-5, 0, 0))
			grid:Insert("C", Vector3.new(0, 0, 5))
			local found = grid:QueryRadius(Vector3.new(0, 0, 0), 20)
			expect(#found).to.equal(3)
		end)

		it("Clear empties the grid completely", function()
			local grid = SpatialGrid.new(50)
			grid:Insert("Gone", Vector3.new(0, 0, 0))
			grid:Clear()
			expect(#grid:QueryRadius(Vector3.new(0, 0, 0), 1000)).to.equal(0)
		end)
	end)
end
