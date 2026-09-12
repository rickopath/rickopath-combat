--!strict

local Types = require(script.Parent.Types)

-- reset happens on Return, not Checkout - the free list always holds clean items, no exceptions.
-- forget to call Return somewhere and you leak one item, that's it, it doesn't corrupt anything
-- for the next guy who checks one out. annoying, not catastrophic
local function new<T>(
	constructor: () -> T,
	reset: (T) -> (),
	initialSize: number,
	growthIncrement: number,
	maxSize: number
): Types.PoolHandle<T>
	local free: { T } = {}
	local inUse = 0

	local function grow(count: number)
		local room = maxSize - inUse - #free
		local n = math.max(math.min(count, room), 0)
		for _ = 1, n do
			table.insert(free, constructor())
		end
	end

	local self = {} :: Types.PoolHandle<T>

	function self.Prewarm(_self: Types.PoolHandle<T>, count: number)
		grow(count)
	end

	function self.Checkout(_self: Types.PoolHandle<T>): T
		if #free == 0 then
			-- grow in fixed chunks up to a hard ceiling - demand's bounded (concurrent swings * candidates),
			-- it doesn't spike out of nowhere
			grow(growthIncrement)
		end
		if #free == 0 then
			-- hit the ceiling with nothing free. either something forgot to call Return, or the Config
			-- limit's just too low for how hard this is getting hit - go find out which
			error("Hitbox: pool exhausted at max size, raise Config pool limits or check for a Return leak")
		end
		local n = #free
		local item = free[n]
		free[n] = nil
		inUse += 1
		return item
	end

	function self.Return(_self: Types.PoolHandle<T>, item: T)
		reset(item)
		table.insert(free, item)
		inUse -= 1
	end

	function self.InUseCount(_self: Types.PoolHandle<T>): number
		return inUse
	end

	self:Prewarm(initialSize)

	return self
end

return { new = new }
