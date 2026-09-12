--!strict

-- the ONE reusable resource primitive. stamina, mana, ammo, and Health itself are all just
-- instances of this same thing - not three copy-pasted systems plus a special-cased Health bolted
-- on the side because someone thought health was "different". it isn't, stop treating it like it is
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)
local Signal = require(ReplicatedStorage.Shared.Hitbox.Signal)

export type ResourcePool = {
	Id: string,
	Current: number,
	Max: number,
	Set: (self: ResourcePool, value: number) -> (),
	Add: (self: ResourcePool, delta: number) -> number,
	TrySpend: (self: ResourcePool, amount: number) -> boolean,
	SetMax: (self: ResourcePool, newMax: number, rescaleCurrent: boolean?) -> (),
	Update: (self: ResourcePool, dt: number) -> (),
	OnChanged: any, -- fastsignal ScriptSignal(old: number, new: number), untyped - see Hitbox/Signal.luau
	OnDepleted: any, -- fastsignal ScriptSignal()
	Destroy: (self: ResourcePool) -> (),
}

local function new(definition: Types.ResourcePoolDefinition): ResourcePool
	local regenPerSecond = definition.RegenPerSecond or 0
	local regenDelay = definition.RegenDelayAfterSpendSeconds or 0
	local lastSpendAt = -math.huge

	local onChanged = Signal.new()
	local onDepleted = Signal.new()

	local self = {} :: ResourcePool
	self.Id = definition.Id
	self.Max = definition.Max
	self.Current = definition.Initial or definition.Max
	self.OnChanged = onChanged
	self.OnDepleted = onDepleted

	local function setCurrent(value: number)
		local clamped = math.clamp(value, 0, self.Max)
		if clamped == self.Current then
			return
		end
		local old = self.Current
		self.Current = clamped
		onChanged:Fire(old, clamped)
		if clamped <= 0 and old > 0 then
			onDepleted:Fire()
		end
	end

	function self.Set(_self: ResourcePool, value: number)
		setCurrent(value)
	end

	function self.Add(_self: ResourcePool, delta: number): number
		if delta < 0 then
			lastSpendAt = os.clock()
		end
		setCurrent(self.Current + delta)
		return self.Current
	end

	-- atomic check-and-subtract - stops a caller from doing "if Current >= cost then Add(-cost)" and
	-- racing itself between the check and the subtract. use this, not the two-step version
	function self.TrySpend(_self: ResourcePool, amount: number): boolean
		if self.Current < amount then
			return false
		end
		lastSpendAt = os.clock()
		setCurrent(self.Current - amount)
		return true
	end

	function self.SetMax(_self: ResourcePool, newMax: number, rescaleCurrent: boolean?)
		if rescaleCurrent and self.Max > 0 then
			local frac = self.Current / self.Max
			self.Max = newMax
			setCurrent(newMax * frac)
		else
			self.Max = newMax
			setCurrent(math.min(self.Current, newMax))
		end
	end

	-- regen tick, driven externally by whatever owns this pool's schedule - this never schedules
	-- itself, don't go looking for a hidden Heartbeat connection in here, there isn't one
	function self.Update(_self: ResourcePool, dt: number)
		if regenPerSecond <= 0 then
			return
		end
		if os.clock() - lastSpendAt < regenDelay then
			return
		end
		setCurrent(self.Current + regenPerSecond * dt)
	end

	function self.Destroy(_self: ResourcePool)
		onChanged:Destroy()
		onDepleted:Destroy()
	end

	return self
end

return { new = new }
