local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResourcePool = require(ReplicatedStorage.Shared.Combat.ResourcePool)

return function()
	describe("ResourcePool", function()
		it("clamps Current to [0, Max] on Add", function()
			local pool = ResourcePool.new({ Id = "Stamina", Max = 100 })
			pool:Add(-9999)
			expect(pool.Current).to.equal(0)
			pool:Add(9999)
			expect(pool.Current).to.equal(100)
			pool:Destroy()
		end)

		it("defaults Current to Max when Initial is omitted", function()
			local pool = ResourcePool.new({ Id = "Health", Max = 150 })
			expect(pool.Current).to.equal(150)
			pool:Destroy()
		end)

		it("honors an explicit Initial", function()
			local pool = ResourcePool.new({ Id = "Ammo", Max = 30, Initial = 6 })
			expect(pool.Current).to.equal(6)
			pool:Destroy()
		end)

		it("TrySpend fails and leaves Current untouched when unaffordable", function()
			local pool = ResourcePool.new({ Id = "Mana", Max = 50, Initial = 10 })
			local ok = pool:TrySpend(20)
			expect(ok).to.equal(false)
			expect(pool.Current).to.equal(10)
			pool:Destroy()
		end)

		it("TrySpend succeeds and deducts exactly when affordable", function()
			local pool = ResourcePool.new({ Id = "Mana", Max = 50, Initial = 30 })
			local ok = pool:TrySpend(20)
			expect(ok).to.equal(true)
			expect(pool.Current).to.equal(10)
			pool:Destroy()
		end)

		it("fires OnDepleted only on the transition into empty, not every zero-clamp", function()
			local pool = ResourcePool.new({ Id = "Health", Max = 100, Initial = 5 })
			local depletedCount = 0
			local connection = pool.OnDepleted:Connect(function()
				depletedCount += 1
			end)

			pool:Add(-5) -- 5 -> 0, real transition
			pool:Add(-50) -- already 0, clamps to 0, no new transition
			task.wait() -- Allow deferred signals to fire if FastSignal is set to Deferred
			expect(depletedCount).to.equal(1)

			connection:Disconnect()
			pool:Destroy()
		end)

		it("Update does nothing when RegenPerSecond is unset (finite resource, e.g. ammo)", function()
			local pool = ResourcePool.new({ Id = "Ammo", Max = 30, Initial = 10 })
			pool:Update(10) -- 10 seconds, would matter a lot if regen were silently on
			expect(pool.Current).to.equal(10)
			pool:Destroy()
		end)

		it("Update regenerates over time once past RegenDelayAfterSpendSeconds", function()
			local pool = ResourcePool.new({
				Id = "Stamina",
				Max = 100,
				Initial = 100,
				RegenPerSecond = 10,
				RegenDelayAfterSpendSeconds = 0,
			})
			pool:TrySpend(50) -- Current = 50, lastSpendAt = now
			pool:Update(1) -- delay is 0, so this tick regenerates immediately
			expect(pool.Current).to.equal(60)
			pool:Destroy()
		end)

		it("SetMax with rescaleCurrent preserves the fraction, not the absolute amount", function()
			local pool = ResourcePool.new({ Id = "Health", Max = 100, Initial = 50 }) -- 50%
			pool:SetMax(200, true)
			expect(pool.Max).to.equal(200)
			expect(pool.Current).to.equal(100) -- still 50%, not still 50 flat
			pool:Destroy()
		end)

		it("SetMax without rescaleCurrent just clamps Current down if it now exceeds the new Max", function()
			local pool = ResourcePool.new({ Id = "Health", Max = 100, Initial = 80 })
			pool:SetMax(50)
			expect(pool.Max).to.equal(50)
			expect(pool.Current).to.equal(50)
			pool:Destroy()
		end)
	end)
end
