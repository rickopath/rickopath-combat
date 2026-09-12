local HitRegistry = require(game:GetService("ServerScriptService").Server.Hitbox.HitRegistry)

return function()
	describe("HitRegistry", function()
		it("allows the first hit on a target for a given swing", function()
			local registry = HitRegistry.new()
			local target = Instance.new("Model")
			expect(registry:TryRegisterHit("swing-1", target, 0, 1)).to.equal(true)
			registry:Destroy()
			target:Destroy()
		end)

		it("rejects a second hit on the SAME target within the SAME swing", function()
			local registry = HitRegistry.new()
			local target = Instance.new("Model")
			registry:TryRegisterHit("swing-1", target, 0, 1)
			expect(registry:TryRegisterHit("swing-1", target, 0, 1)).to.equal(false)
			registry:Destroy()
			target:Destroy()
		end)

		it("allows the same target to be hit again under a DIFFERENT swing key", function()
			local registry = HitRegistry.new()
			local target = Instance.new("Model")
			registry:TryRegisterHit("swing-1", target, 0, 1)
			expect(registry:TryRegisterHit("swing-2", target, 0, 1)).to.equal(true)
			registry:Destroy()
			target:Destroy()
		end)

		it("allows two DIFFERENT targets under the same swing key independently", function()
			local registry = HitRegistry.new()
			local targetA = Instance.new("Model")
			local targetB = Instance.new("Model")
			expect(registry:TryRegisterHit("swing-1", targetA, 0, 1)).to.equal(true)
			expect(registry:TryRegisterHit("swing-1", targetB, 0, 1)).to.equal(true)
			registry:Destroy()
			targetA:Destroy()
			targetB:Destroy()
		end)

		it("CleanupExpired removes only swings past their TTL, and freed keys act fresh again", function()
			local registry = HitRegistry.new()
			local targetA = Instance.new("Model")
			local targetB = Instance.new("Model")

			registry:TryRegisterHit("expires-at-10", targetA, 0, 10) -- ExpiresAt = 10
			registry:TryRegisterHit("expires-at-100", targetB, 0, 100) -- ExpiresAt = 100

			local removed = registry:CleanupExpired(50) -- past 10, not past 100
			expect(removed).to.equal(1)

			-- the surviving swing key should still remember its hit and keep deduping
			expect(registry:TryRegisterHit("expires-at-100", targetB, 50, 100)).to.equal(false)
			-- the expired one was actually removed, not just marked - it's a clean slate now
			expect(registry:TryRegisterHit("expires-at-10", targetA, 50, 10)).to.equal(true)

			registry:Destroy()
			targetA:Destroy()
			targetB:Destroy()
		end)

		it("Destroy clears every tracked swing", function()
			local registry = HitRegistry.new()
			local target = Instance.new("Model")
			registry:TryRegisterHit("swing-1", target, 0, 1)
			registry:Destroy()
			-- after Destroy, the same swing key should behave as never-seen (fresh internal state)
			expect(registry:TryRegisterHit("swing-1", target, 0, 1)).to.equal(true)
			target:Destroy()
		end)
	end)
end
