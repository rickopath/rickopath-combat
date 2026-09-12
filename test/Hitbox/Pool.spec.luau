local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pool = require(ReplicatedStorage.Shared.Hitbox.Pool)

local function newTestPool(initialSize: number, growthIncrement: number, maxSize: number)
	local resetCount = 0
	local pool = Pool.new(function()
		return { Tag = "fresh" }
	end, function(item)
		item.Tag = "reset"
		resetCount += 1
	end, initialSize, growthIncrement, maxSize)
	return pool, function()
		return resetCount
	end
end

return function()
	describe("Pool", function()
		it("prewarms exactly initialSize items on construction", function()
			local pool = newTestPool(4, 2, 100)
			expect(pool:InUseCount()).to.equal(0)
			-- checkout all 4 prewarmed items without triggering a growth error
			for _ = 1, 4 do
				pool:Checkout()
			end
			expect(pool:InUseCount()).to.equal(4)
		end)

		it("grows in growthIncrement chunks once the free list is exhausted", function()
			local pool = newTestPool(1, 3, 100)
			pool:Checkout() -- consumes the 1 prewarmed item, free list now empty
			-- next checkout should trigger a grow(3), giving us 2 more free after taking 1
			local item = pool:Checkout()
			expect(item).to.be.ok()
			expect(pool:InUseCount()).to.equal(2)
		end)

		it("errors when checked out past maxSize with nothing returned", function()
			local pool = newTestPool(2, 2, 2) -- ceiling of 2, no room to grow past it
			pool:Checkout()
			pool:Checkout()
			expect(function()
				pool:Checkout()
			end).to.throw()
		end)

		it("Return resets the item before it goes back on the free list", function()
			local pool, getResetCount = newTestPool(1, 1, 10)
			local item = pool:Checkout()
			expect(item.Tag).to.equal("fresh")
			pool:Return(item)
			expect(item.Tag).to.equal("reset")
			expect(getResetCount()).to.equal(1)
		end)

		it("Return decrements InUseCount so the slot is actually reusable", function()
			local pool = newTestPool(1, 1, 1) -- ceiling of exactly 1
			local item = pool:Checkout()
			expect(pool:InUseCount()).to.equal(1)
			pool:Return(item)
			expect(pool:InUseCount()).to.equal(0)
			-- would error if Return hadn't freed the slot, since maxSize is 1
			expect(function()
				pool:Checkout()
			end).never.to.throw()
		end)
	end)
end
