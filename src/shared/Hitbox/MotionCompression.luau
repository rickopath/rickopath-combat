--!strict

-- pure math, no bytenet, no requires beyond Types - split out of Net.luau so it's testable on its
-- own without needing a live client-server round trip through an actual RemoteEvent.
--
-- swing motion gets compressed on the wire. every Types.MotionSample in a melee swing carries a
-- FULL world-space CFrame (24 bytes - checked bytenet's own cframe.luau, it's 6 float32s), but
-- MotionSampler composes every single one of those samples from the exact same `basePose *
-- attachOffset` - the only thing that actually varies sample to sample is the small keyframe
-- offset on top of it. so we send that shared base ONCE and quantize each sample's offset from it.
-- old cost: 28 bytes/sample (4 T + 24 CFrame). new cost: 16 bytes/sample (4 T + 6 position + 6
-- rotation), plus one 24-byte Base per swing - roughly a third smaller for a typical swing, more
-- for longer ones (MaxSweepSubSteps default is 12).
--
-- MOTION_OFFSET_RANGE_STUDS bounds how far a sample can legitimately drift from the swing's base
-- before this silently CLAMPS instead of corrupting - 16 studs comfortably covers any normal
-- AttachOffset + keyframe offset. authoring something with a much longer reach than that (a pike,
-- a whip)? bump this constant, don't just hope it fits. rotation always covers the full range with
-- no clamping needed - Euler angles from ToEulerAnglesXYZ are already bounded to it.
local Types = require(script.Parent.Types)

local MOTION_OFFSET_RANGE_STUDS = 16
local INT16_MAX = 32767

local function quantize(value: number, range: number): number
	return math.round(math.clamp(value, -range, range) / range * INT16_MAX)
end

local function dequantize(value: number, range: number): number
	return (value / INT16_MAX) * range
end

export type CompactMotionSample = {
	T: number,
	OffsetX: number,
	OffsetY: number,
	OffsetZ: number,
	RotX: number,
	RotY: number,
	RotZ: number,
}

export type CompactMotion = { Base: CFrame, Samples: { CompactMotionSample } }

local MotionCompression = {}

-- nil in, nil out - Hitscan/Radius/Projectile requests never have Motion at all, and an empty
-- sample array (no legitimate way to define a shared Base) is treated the same as nil, which
-- HitboxServer already handles identically to "no motion" either way
function MotionCompression.Encode(samples: { Types.MotionSample }?): CompactMotion?
	if not samples or #samples == 0 then
		return nil
	end

	local base = samples[1].CFrame
	local compact: { CompactMotionSample } = table.create(#samples)
	for i, sample in samples do
		-- relative to the shared Base, NOT to the previous sample - keeps every offset
		-- independently small and bounded instead of letting quantization error accumulate
		-- sample over sample the way a chain of relative-to-previous deltas would
		local relative = base:ToObjectSpace(sample.CFrame)
		local rx, ry, rz = relative:ToEulerAnglesXYZ()
		compact[i] = {
			T = sample.T,
			OffsetX = quantize(relative.X, MOTION_OFFSET_RANGE_STUDS),
			OffsetY = quantize(relative.Y, MOTION_OFFSET_RANGE_STUDS),
			OffsetZ = quantize(relative.Z, MOTION_OFFSET_RANGE_STUDS),
			RotX = quantize(rx, math.pi),
			RotY = quantize(ry, math.pi),
			RotZ = quantize(rz, math.pi),
		}
	end

	return { Base = base, Samples = compact }
end

function MotionCompression.Decode(motion: CompactMotion?): { Types.MotionSample }?
	if not motion then
		return nil
	end

	local samples: { Types.MotionSample } = table.create(#motion.Samples)
	for i, compact in motion.Samples do
		local offset = CFrame.new(
			dequantize(compact.OffsetX, MOTION_OFFSET_RANGE_STUDS),
			dequantize(compact.OffsetY, MOTION_OFFSET_RANGE_STUDS),
			dequantize(compact.OffsetZ, MOTION_OFFSET_RANGE_STUDS)
		) * CFrame.Angles(dequantize(compact.RotX, math.pi), dequantize(compact.RotY, math.pi), dequantize(compact.RotZ, math.pi))
		samples[i] = {
			T = compact.T,
			CFrame = motion.Base * offset,
		}
	end

	return samples
end

return MotionCompression
