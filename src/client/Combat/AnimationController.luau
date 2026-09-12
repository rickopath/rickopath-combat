--!strict

-- generic per-character animation track manager. NOT wired to any specific skill or animation id -
-- you hand it a {name -> assetId} table, then call Play/Stop by name from wherever you decide an
-- animation should happen (your own OnEffectRequested subscriber, most likely). tracks are cached
-- per character so playing the same name twice doesn't reload the asset, and the cache is cleared
-- when the character is destroyed so this doesn't leak one table of AnimationTracks per corpse.
--
-- doesn't replace AnimationPreloader - preload the asset ids once on a loading screen, THEN use
-- this to actually play them during gameplay. two different jobs, use both together.
local AnimationController = {}

export type AnimationController = {
	Register: (self: AnimationController, name: string, animationId: string) -> (),
	Play: (self: AnimationController, character: Model, name: string, fadeTime: number?) -> AnimationTrack?,
	Stop: (self: AnimationController, character: Model, name: string, fadeTime: number?) -> (),
	StopAll: (self: AnimationController, character: Model, fadeTime: number?) -> (),
}

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		-- this used to fail completely silently - indistinguishable from "the AnimationId is bad",
		-- which is the actual most common cause but not the ONLY one. a character mid-respawn (no
		-- Humanoid replicated yet) hits this too, and previously you'd have no way to tell the two
		-- apart. now you can: this warns, a bad asset id doesn't warn anywhere, it just plays nothing
		warn(string.format("AnimationController: %s has no Humanoid yet, animation dropped", character.Name))
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- most rigs already have one, Roblox adds it automatically - this only fires for a rig
		-- built without one, and creating it here is the normal fix, not a workaround
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

function AnimationController.new(animationIds: { [string]: string }?): AnimationController
	local ids: { [string]: string } = if animationIds then table.clone(animationIds) else {}
	-- tracks[character][name] - cleared per-character on Destroying, not held forever
	local tracks: { [Model]: { [string]: AnimationTrack } } = {}

	local function tracksFor(character: Model): { [string]: AnimationTrack }
		local existing = tracks[character]
		if existing then
			return existing
		end
		local created: { [string]: AnimationTrack } = {}
		tracks[character] = created
		character.Destroying:Connect(function()
			tracks[character] = nil
		end)
		return created
	end

	local self = {} :: AnimationController

	function self.Register(_self: AnimationController, name: string, animationId: string): ()
		ids[name] = animationId
	end

	function self.Play(_self: AnimationController, character: Model, name: string, fadeTime: number?): AnimationTrack?
		local id = ids[name]
		if not id then
			warn(string.format("AnimationController: no animation id registered for %q - call :Register first", name))
			return nil
		end

		local byName = tracksFor(character)
		local track = byName[name]
		if not track then
			local animator = getAnimator(character)
			if not animator then
				return nil
			end
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			track = animator:LoadAnimation(animation)
			byName[name] = track
		end

		track:Play(fadeTime)
		return track
	end

	function self.Stop(_self: AnimationController, character: Model, name: string, fadeTime: number?): ()
		local byName = tracks[character]
		local track = byName and byName[name]
		if track then
			track:Stop(fadeTime)
		end
	end

	function self.StopAll(_self: AnimationController, character: Model, fadeTime: number?): ()
		local byName = tracks[character]
		if not byName then
			return
		end
		for _, track in byName do
			track:Stop(fadeTime)
		end
	end

	return self
end

return AnimationController
