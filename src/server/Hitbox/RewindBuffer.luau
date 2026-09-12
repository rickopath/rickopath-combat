--!strict

-- server side authority for one Alive-folder model's history. fixed-capacity ring, allocated once,
-- never grows after that - if you need it bigger, change the config, don't make this dynamic
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Hitbox.Types)

export type RewindBuffer = {
	Record: (self: RewindBuffer, now: number, pose: { [string]: CFrame }) -> (),
	SampleAt: (self: RewindBuffer, timestamp: number) -> Types.RewindResult,
	Destroy: (self: RewindBuffer) -> (),
}

local function new(depthSeconds: number, sampleInterval: number): RewindBuffer
	-- ~1.5s @ 60hz by default. push depth much higher and the gc starts crying, don't do it
	local capacity = math.max(math.ceil(depthSeconds / sampleInterval), 2)

	local slots: { Types.PoseSample } = table.create(capacity)
	for i = 1, capacity do
		slots[i] = { Timestamp = 0, Parts = {} }
	end

	local writeIndex = 0
	local count = 0
	local lastSampleTime = -math.huge

	-- logical index 1 = oldest sample we've still got, logical index count = newest
	local function logicalToSlot(logical: number): Types.PoseSample
		local oldestIndex = (writeIndex - count + capacity) % capacity + 1
		local slotIndex = (oldestIndex - 1 + logical - 1) % capacity + 1
		return slots[slotIndex]
	end

	local self = {} :: RewindBuffer
	-- reused for the interpolated case in SampleAt. only safe because every caller (ConfirmRewound)
	-- fully drains Pose synchronously before the next SampleAt call ever fires - don't yield between
	-- getting this and using it or you'll hand someone else's data to the wrong caller
	local scratchPose: { [string]: CFrame } = {}

	function self.Record(_self: RewindBuffer, now: number, pose: { [string]: CFrame })
		if now - lastSampleTime < sampleInterval then
			return -- throttled - keeps buffer coverage sane regardless of heartbeat dt jitter
		end
		lastSampleTime = now

		writeIndex = (writeIndex % capacity) + 1
		local slot = slots[writeIndex]
		slot.Timestamp = now

		-- overwrite the slot table in place, don't reallocate Parts every single tick, that's just waste
		for name in slot.Parts do
			if not pose[name] then
				slot.Parts[name] = nil
			end
		end
		for name, cf in pose do
			slot.Parts[name] = cf
		end

		count = math.min(count + 1, capacity)
	end

	function self.SampleAt(_self: RewindBuffer, timestamp: number): Types.RewindResult
		if count == 0 then
			return { Found = false, Pose = {}, ClampedToOldest = false, ClampedToNewest = false }
		end

		local oldest = logicalToSlot(1)
		local newest = logicalToSlot(count)

		if timestamp <= oldest.Timestamp then
			return { Found = true, Pose = oldest.Parts, ClampedToOldest = true, ClampedToNewest = false }
		end
		if timestamp >= newest.Timestamp then
			return { Found = true, Pose = newest.Parts, ClampedToOldest = false, ClampedToNewest = true }
		end

		-- binary search for the bracketing pair, oldest -> newest logical order
		local lo, hi = 1, count
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if logicalToSlot(mid).Timestamp <= timestamp then
				lo = mid
			else
				hi = mid
			end
		end

		local a = logicalToSlot(lo)
		local b = logicalToSlot(hi)
		local span = b.Timestamp - a.Timestamp
		local alpha = if span > 0 then (timestamp - a.Timestamp) / span else 0

		-- CFrame:Lerp already does correct translation lerp + rotation slerp, don't reinvent that.
		-- scratch table reused, not reallocated per call - this is the hottest path in the whole
		-- library (every candidate, every sub-step, every swing), see scratchPose's declaration above
		table.clear(scratchPose)
		for name, cfA in a.Parts do
			local cfB = b.Parts[name]
			scratchPose[name] = if cfB then cfA:Lerp(cfB, alpha) else cfA
		end

		return { Found = true, Pose = scratchPose, ClampedToOldest = false, ClampedToNewest = false }
	end

	function self.Destroy(_self: RewindBuffer)
		table.clear(slots)
	end

	return self
end

return { new = new }
