--!strict

-- generic "activate skill X" pipe - this is what CombatantSkills.luau's TryActivate gate is actually
-- reacting to over the wire. kept dumb on purpose: an aim direction, a target, whatever a specific
-- skill needs - none of that belongs on a generic channel, that's each skill's own problem
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("bytenet"))

local Packets = ByteNet.defineNamespace("CombatSkills", function()
	return {
		ActivateSkill = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				SkillId = ByteNet.string,
				SequenceId = ByteNet.uint32,
			}),
		}),
		SkillActivationResult = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				SequenceId = ByteNet.uint32,
				Accepted = ByteNet.bool,
			}),
		}),
	}
end)

export type ActivateSkillRequest = {
	SkillId: string,
	SequenceId: number,
}

export type SkillActivationResult = {
	SequenceId: number,
	Accepted: boolean,
}

local Net = {}

function Net.FireActivateSkill(request: ActivateSkillRequest): ()
	Packets.ActivateSkill.send({ SkillId = request.SkillId, SequenceId = request.SequenceId })
end

function Net.OnActivateSkill(handler: (player: Player, request: ActivateSkillRequest) -> ()): ()
	Packets.ActivateSkill.listen(function(data, player)
		if not player then
			return
		end
		handler(player, { SkillId = data.SkillId, SequenceId = data.SequenceId })
	end)
end

function Net.FireSkillActivationResult(player: Player, result: SkillActivationResult): ()
	Packets.SkillActivationResult.sendTo({ SequenceId = result.SequenceId, Accepted = result.Accepted }, player)
end

function Net.OnSkillActivationResult(handler: (result: SkillActivationResult) -> ()): ()
	Packets.SkillActivationResult.listen(function(data)
		handler({ SequenceId = data.SequenceId, Accepted = data.Accepted })
	end)
end

return Net
