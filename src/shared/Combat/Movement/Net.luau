--!strict

-- reliable channel, same call as Hitbox's AttackRequest/AttackResult - drop one of these and the
-- client/server positions actually desync, this isn't some cosmetic hiccup you can shrug off
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)

local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("bytenet"))

local Packets = ByteNet.defineNamespace("CombatMovement", function()
	return {
		MovementRequest = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				SkillId = ByteNet.string,
				SequenceId = ByteNet.uint32,
				ClientTimestamp = ByteNet.float64,
				From = ByteNet.cframe,
				To = ByteNet.cframe,
				MaxDistance = ByteNet.float32,
			}),
		}),
		MovementResult = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				SequenceId = ByteNet.uint32,
				Accepted = ByteNet.bool,
				AuthoritativeCFrame = ByteNet.cframe,
				ServerTimestamp = ByteNet.float64,
			}),
		}),
	}
end)

local Net = {}

function Net.FireMovementRequest(request: Types.MovementRequest): ()
	Packets.MovementRequest.send({
		SkillId = request.SkillId,
		SequenceId = request.SequenceId,
		ClientTimestamp = request.ClientTimestamp,
		From = request.From,
		To = request.To,
		MaxDistance = request.MaxDistance,
	})
end

function Net.OnMovementRequest(handler: (player: Player, request: Types.MovementRequest) -> ()): ()
	Packets.MovementRequest.listen(function(data, player)
		if not player then
			return
		end
		handler(player, {
			SkillId = data.SkillId,
			SequenceId = data.SequenceId,
			ClientTimestamp = data.ClientTimestamp,
			From = data.From,
			To = data.To,
			MaxDistance = data.MaxDistance,
		})
	end)
end

function Net.FireMovementResult(player: Player, result: Types.MovementResult): ()
	Packets.MovementResult.sendTo({
		SequenceId = result.SequenceId,
		Accepted = result.Accepted,
		AuthoritativeCFrame = result.AuthoritativeCFrame,
		ServerTimestamp = result.ServerTimestamp,
	}, player)
end

function Net.OnMovementResult(handler: (result: Types.MovementResult) -> ()): ()
	Packets.MovementResult.listen(function(data)
		handler({
			SequenceId = data.SequenceId,
			Accepted = data.Accepted,
			AuthoritativeCFrame = data.AuthoritativeCFrame,
			ServerTimestamp = data.ServerTimestamp,
		})
	end)
end

return Net
