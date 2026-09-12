--!strict

-- generic uniform grid for "what's near this position" queries. bucket space into fixed-size
-- cells, insert once, then a radius query only walks the handful of cells that could possibly
-- overlap it instead of checking every entry against every query - that's the entire point of
-- "spatial partitioning" as an optimization, and the thing a brute-force distance loop can't do.
--
-- 2D on purpose: cells are keyed by X/Z only, Y is ignored for bucketing. a query radius is a
-- horizontal circle, not a 3D sphere - fine for "who's near me" on a normal Roblox map where
-- vertical range is usually small next to horizontal range. if you need a true 3D sphere query
-- (flight, space, tall vertical builds), this isn't quite it - go bucket Y too.
--
-- pure data structure, no Roblox services touched beyond Vector3 math - safe on either realm,
-- though SnapshotReplicator (the thing this was built for) only ever needs it server side
local SpatialGrid = {}

export type Grid<T> = {
	Insert: (self: Grid<T>, key: T, position: Vector3) -> (),
	QueryRadius: (self: Grid<T>, position: Vector3, radius: number) -> { T },
	Clear: (self: Grid<T>) -> (),
}

type Entry<T> = { Key: T, Position: Vector3 }

local function cellKey(cellX: number, cellZ: number): string
	return cellX .. ":" .. cellZ
end

-- cellSize should be roughly your query radius, maybe a bit smaller. too small and QueryRadius
-- walks dozens of mostly-empty cells; too big and each cell holds nearly everything, which is
-- just a brute-force loop with extra steps
function SpatialGrid.new<T>(cellSize: number): Grid<T>
	local cells: { [string]: { Entry<T> } } = {}

	local function cellOf(position: Vector3): (number, number)
		return math.floor(position.X / cellSize), math.floor(position.Z / cellSize)
	end

	local self = {} :: Grid<T>

	function self.Insert(_self: Grid<T>, key: T, position: Vector3): ()
		local cx, cz = cellOf(position)
		local k = cellKey(cx, cz)
		local bucket = cells[k]
		if not bucket then
			bucket = {}
			cells[k] = bucket
		end
		table.insert(bucket, { Key = key, Position = position })
	end

	-- walks every cell that could overlap a circle of `radius` around `position` - ceil(radius /
	-- cellSize) cells out in each direction, not the whole grid. still does a real distance check
	-- per candidate inside those cells (a cell is a square, the query is a circle, corners of the
	-- outer cells are further than `radius` away) - same broad-phase-then-narrow-phase shape as
	-- Hitbox's own AliveRegistry, just for a different problem
	function self.QueryRadius(_self: Grid<T>, position: Vector3, radius: number): { T }
		local result: { T } = {}
		local reach = math.ceil(radius / cellSize)
		local originX, originZ = cellOf(position)
		local radiusSquared = radius * radius

		for dx = -reach, reach do
			for dz = -reach, reach do
				local bucket = cells[cellKey(originX + dx, originZ + dz)]
				if bucket then
					for _, entry in bucket do
						local deltaX = entry.Position.X - position.X
						local deltaZ = entry.Position.Z - position.Z
						if deltaX * deltaX + deltaZ * deltaZ <= radiusSquared then
							table.insert(result, entry.Key)
						end
					end
				end
			end
		end

		return result
	end

	function self.Clear(_self: Grid<T>): ()
		table.clear(cells)
	end

	return self
end

return SpatialGrid
