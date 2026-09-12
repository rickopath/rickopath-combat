-- this is the highest-risk pure-logic module in the codebase to get wrong: it's the wire format
-- for melee hit detection. if Encode/Decode silently corrupt a CFrame, swings desync between
-- client prediction and server confirmation. these tests exist specifically to catch that.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MotionCompression = require(ReplicatedStorage.Shared.Hitbox.MotionCompression)

-- position error + LookVector error combined into one number - bounds both translation and
-- rotation drift in a single assertion instead of needing four separate near() checks per sample
local function cframeError(a: CFrame, b: CFrame): number
	local positionError = (a.Position - b.Position).Magnitude
	local lookError = (a.LookVector - b.LookVector).Magnitude
	return positionError + lookError
end

return function()
	describe("MotionCompression", function()
		it("passes nil straight through both directions", function()
			expect(MotionCompression.Encode(nil)).to.equal(nil)
			expect(MotionCompression.Decode(nil)).to.equal(nil)
		end)

		it("treats an empty sample array the same as nil - no legitimate Base to define", function()
			expect(MotionCompression.Encode({})).to.equal(nil)
		end)

		it("round-trips a single sample within quantization tolerance", function()
			local original = {
				{ T = 0, CFrame = CFrame.new(100, 5, 50) * CFrame.Angles(0, math.rad(30), 0) },
			}
			local decoded = MotionCompression.Decode(MotionCompression.Encode(original))
			expect(decoded).to.be.ok()
			expect(#decoded).to.equal(1)
			expect(decoded[1].T).to.equal(0)
			expect(cframeError(decoded[1].CFrame, original[1].CFrame) < 0.01).to.equal(true)
		end)

		it("round-trips a realistic multi-sample swing (rotation-only offsets, matching MotionSampler's shape)", function()
			local basePose = CFrame.new(20, 4, -8) * CFrame.Angles(0, math.rad(75), 0)
			local attachOffset = CFrame.new(0, 0, -3)
			local base = basePose * attachOffset

			local original = {
				{ T = 0, CFrame = base * CFrame.Angles(0, math.rad(-50), 0) },
				{ T = 0.1, CFrame = base * CFrame.Angles(0, math.rad(-20), 0) },
				{ T = 0.2, CFrame = base * CFrame.Angles(0, math.rad(50), 0) },
			}

			local decoded = MotionCompression.Decode(MotionCompression.Encode(original))
			expect(#decoded).to.equal(3)
			for i, sample in original do
				expect(decoded[i].T).to.equal(sample.T)
				expect(cframeError(decoded[i].CFrame, sample.CFrame) < 0.01).to.equal(true)
			end
		end)

		it("preserves sample order", function()
			local base = CFrame.new(0, 0, 0)
			local original = {
				{ T = 0, CFrame = base },
				{ T = 0.05, CFrame = base * CFrame.new(1, 0, 0) },
				{ T = 0.1, CFrame = base * CFrame.new(2, 0, 0) },
			}
			local decoded = MotionCompression.Decode(MotionCompression.Encode(original))
			expect(decoded[1].T).to.equal(0)
			expect(decoded[2].T).to.equal(0.05)
			expect(decoded[3].T).to.equal(0.1)
		end)

		it("clamps an offset beyond MOTION_OFFSET_RANGE_STUDS instead of corrupting or overflowing it", function()
			-- second sample is 500 studs from the base - no real weapon reaches that far, this is
			-- specifically exercising the clamp path, not a realistic swing
			local base = CFrame.new(0, 0, 0)
			local original = {
				{ T = 0, CFrame = base },
				{ T = 0.1, CFrame = base * CFrame.new(0, 0, -500) },
			}

			local decoded = MotionCompression.Decode(MotionCompression.Encode(original))
			local decodedOffsetDistance = (decoded[2].CFrame.Position - decoded[1].CFrame.Position).Magnitude

			-- clamped to (approximately) the documented 16-stud range, not wrapped/overflowed to
			-- something wild and not silently truncated to 0 either
			expect(decodedOffsetDistance <= 17).to.equal(true)
			expect(decodedOffsetDistance > 15).to.equal(true)
		end)

		it("a swing with only one sample still produces a valid Base with no offset to decode", function()
			local only = { { T = 0, CFrame = CFrame.new(5, 5, 5) } }
			local decoded = MotionCompression.Decode(MotionCompression.Encode(only))
			expect(#decoded).to.equal(1)
			expect(cframeError(decoded[1].CFrame, only[1].CFrame) < 0.01).to.equal(true)
		end)
	end)
end
