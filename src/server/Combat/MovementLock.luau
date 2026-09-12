--!strict

-- physics-authoritative root, not `WalkSpeed = 0`. Roblox's default character networking gives a
-- player's own client ownership of their character's physics - WalkSpeed=0 is a suggestion the
-- client's Humanoid mostly respects, not a hard block, and a client-side exploit can still move the
-- character via raw force/velocity manipulation the Humanoid movement system doesn't gate. this
-- takes the root part's network ownership away from the player first, so the SERVER's physics
-- becomes authoritative for the transition, then anchors it - an anchored part isn't simulated at
-- all, there's no path for a client-side exploit to move something that's not being simulated
local MovementLock = {}

function MovementLock.Apply(character: Model): ()
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart then
		return
	end

	-- can reject on some rig/streaming configurations - fails soft, Anchored below is what actually
	-- matters, ownership transfer is belt-and-suspenders for the moment right before it takes effect
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
	rootPart.Anchored = true

	if humanoid then
		humanoid.WalkSpeed = 0 -- belt and suspenders, doesn't hurt, costs nothing
	end
end

function MovementLock.Release(character: Model): ()
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	rootPart.Anchored = false
	-- nil = automatic ownership, hands it back to the player for their own character - don't pass
	-- the Player instance explicitly, automatic assignment is what Roblox expects for a live player
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
end

return MovementLock
