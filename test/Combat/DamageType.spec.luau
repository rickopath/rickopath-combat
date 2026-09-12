local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DamageType = require(ReplicatedStorage.Shared.Combat.DamageType)

return function()
	describe("DamageType.ApplyResistance", function()
		it("passes damage through unchanged with no resistance entry (implicit 1.0 multiplier)", function()
			local result = DamageType.ApplyResistance(20, DamageType.Physical, {})
			expect(result).to.equal(20)
		end)

		it("applies an explicit multiplier from the resistance table", function()
			local result = DamageType.ApplyResistance(20, DamageType.Physical, { [DamageType.Physical] = 0.5 })
			expect(result).to.equal(10)
		end)

		it("never goes negative even with a resistance multiplier below zero", function()
			local result = DamageType.ApplyResistance(20, DamageType.Physical, { [DamageType.Physical] = -5 })
			expect(result).to.equal(0)
		end)

		it("BypassResistance damage types (True) ignore the resistance table entirely", function()
			local result = DamageType.ApplyResistance(20, DamageType.True, { [DamageType.True] = 0 })
			expect(result).to.equal(20)
		end)

		it("clamps a negative base amount to zero rather than healing", function()
			local result = DamageType.ApplyResistance(-20, DamageType.Physical, {})
			expect(result).to.equal(0)
		end)

		it("Register/Get round-trips a custom damage type", function()
			DamageType.Register({ Id = "__Test_Fire", BypassResistance = false })
			local found = DamageType.Get("__Test_Fire")
			expect(found).to.be.ok()
			expect(found.Id).to.equal("__Test_Fire")
		end)

		it("Get returns nil for an unregistered id", function()
			expect(DamageType.Get("__Test_NeverRegistered")).to.equal(nil)
		end)
	end)
end
