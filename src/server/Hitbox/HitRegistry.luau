--!strict

-- one hit per target per swing, that's it, that's the whole job. no per-swing task.delay timers -
-- that's N timers for N swings and it adds up. one sweep on HitboxServer's heartbeat kills expired
-- records instead. bounded memory, one connection, move on

type SwingRecord = {
	ExpiresAt: number,
	Hit: { [Model]: boolean },
}

export type HitRegistry = {
	TryRegisterHit: (self: HitRegistry, swingKey: string, target: Model, now: number, ttl: number) -> boolean,
	CleanupExpired: (self: HitRegistry, now: number) -> number,
	Destroy: (self: HitRegistry) -> (),
}

local function new(): HitRegistry
	local activeSwings: { [string]: SwingRecord } = {}

	local self = {} :: HitRegistry

	function self.TryRegisterHit(_self: HitRegistry, swingKey: string, target: Model, now: number, ttl: number): boolean
		local record = activeSwings[swingKey]
		if not record then
			record = { ExpiresAt = now + ttl, Hit = {} }
			activeSwings[swingKey] = record
		end

		if record.Hit[target] then
			return false
		end
		record.Hit[target] = true
		return true
	end

	function self.CleanupExpired(_self: HitRegistry, now: number): number
		local removed = 0
		for key, record in activeSwings do
			if now > record.ExpiresAt then
				activeSwings[key] = nil
				removed += 1
			end
		end
		return removed
	end

	function self.Destroy(_self: HitRegistry)
		table.clear(activeSwings)
	end

	return self
end

return { new = new }
