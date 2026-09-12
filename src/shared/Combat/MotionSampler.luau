--!strict

-- builds the {MotionSample} array RequestAttack's motion param wants. authored-curve only right now -
-- just interpolates between a few hand-authored relative keyframes over a duration. no dependency on
-- real AnimationTrack assets because none exist in this project yet. a live RunService-sampled
-- version (record a real swinging weapon part's CFrame while an actual animation plays) is the
-- obvious next step - not built, there's no rig/animation to test it against, would just be guessing
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitboxTypes = require(ReplicatedStorage.Shared.Hitbox.Types)

type MotionSample = HitboxTypes.MotionSample

export type Keyframe = {
	T: number,
	Offset: CFrame,
}

local MotionSampler = {}

-- basePose * attachOffset * keyframe.Offset per sample. this is the thing that actually wires up
-- HitboxConfig.AttachOffset - nothing else in the library ever touches that field, it just sat
-- there dead until this existed
function MotionSampler.FromKeyframes(basePose: CFrame, attachOffset: CFrame, keyframes: { Keyframe }): { MotionSample }
	local samples: { MotionSample } = table.create(#keyframes)
	for i, keyframe in keyframes do
		samples[i] = {
			T = keyframe.T,
			CFrame = basePose * attachOffset * keyframe.Offset,
		}
	end
	return samples
end

return MotionSampler
