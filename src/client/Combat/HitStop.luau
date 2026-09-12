--!strict

-- hit-stop / freeze-frame: the couple-of-frames pause on a heavy connect. cheapest, highest-impact
-- "juice" technique there is - it's most of why a heavy attack reads as heavy instead of as a
-- number going down.
--
-- CLIENT side on purpose. it's a perception thing, every client freezing their own view is exactly
-- right, and freezing the server would desync everyone for real. the tradeoff: this pins WalkSpeed,
-- which the server can still override on its next movement correction - fine for the 0.05-0.15s
-- this should ever run for. don't crank the duration up to a full second and then file a bug
local HitStop = {}

-- one active freeze per character. a second hit landing mid-freeze restarts the timer rather than
-- stacking two restores that would fight each other and leave someone permanently at WalkSpeed 0 -
-- that exact bug is why this table exists
local frozen: { [Model]: { WalkSpeed: number, Token: number } } = {}
local tokenCounter = 0

function HitStop.Apply(character: Model, duration: number): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	tokenCounter += 1
	local token = tokenCounter

	local existing = frozen[character]
	-- only capture WalkSpeed if we aren't already frozen - otherwise we'd "restore" to 0 later
	local restoreTo = if existing then existing.WalkSpeed else humanoid.WalkSpeed
	frozen[character] = { WalkSpeed = restoreTo, Token = token }

	humanoid.WalkSpeed = 0

	task.delay(duration, function()
		local entry = frozen[character]
		-- a newer freeze took over while we were waiting - it owns the restore now, not us
		if not entry or entry.Token ~= token then
			return
		end
		frozen[character] = nil
		if humanoid.Parent then
			humanoid.WalkSpeed = entry.WalkSpeed
		end
	end)
end

return HitStop
