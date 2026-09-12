--!strict

-- warms Roblox's asset cache for animation ids before you actually need them. an animation played
-- cold has to fetch the asset first, which is exactly the wrong moment for a network round trip -
-- the swing happens, the animation shows up a beat later, and it feels broken even though nothing
-- is. call this during a loading screen or right after spawn with everything you know you'll use.
--
-- nothing calls this for you. it can't - only you know which animation ids your game has
local ContentProvider = game:GetService("ContentProvider")

local AnimationPreloader = {}

-- YIELDS until every id is fetched (or fails). that's the point - you want the wait up front, on a
-- loading screen, not mid-fight. wrap it in task.spawn if you'd rather not block your init path.
-- bad/unpublished ids don't error, PreloadAsync just logs and moves on, so one typo won't take the
-- whole batch down with it
function AnimationPreloader.Preload(animationIds: { string }): ()
	local instances = table.create(#animationIds)
	for i, id in animationIds do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		instances[i] = animation
	end
	ContentProvider:PreloadAsync(instances)
end

return AnimationPreloader
