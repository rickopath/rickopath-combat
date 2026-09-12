--!strict

-- typed wrapper over bytenet packets. keeps the wire format contained to this ONE file - if you're
-- reaching for ByteNet anywhere else in Hitbox, stop, that's not where it belongs
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)
local MotionCompression = require(script.Parent.MotionCompression)

type AttackKind = Types.AttackKind

local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("bytenet"))

-- defined once, required identically by both HitboxServer and HitboxClient - the server assigns
-- the real packet/struct ids and replicates the name -> id mapping over, field names just have to
-- match between the two, that's the whole contract
local Packets = ByteNet.defineNamespace("Hitbox", function()
	-- MUST be built INSIDE this callback, never hoisted above defineNamespace. learned this one
	-- the hard way: ByteNet.struct reads an implicit "current namespace" upvalue that's only valid
	-- while this callback is actively running. build it outside and the client branch looks up a
	-- nil namespace name and blows up on valueFolder:FindFirstChild(nil) - it will not give you a
	-- useful error message when it does. order matters too: bytenet matches structs to the server's
	-- schema POSITIONALLY (Nth struct built = Nth schema entry), so these have to stay ahead of the
	-- packet structs referencing them, same relative order on both realms, don't reorder casually
	-- COMPACT motion sample - see MOTION_OFFSET_RANGE_STUDS below for the encode/decode math and why
	-- this exists at all. NOT the same shape as Types.MotionSample - this is wire-only, the
	-- conversion happens entirely in this file, nothing else in the library ever sees this struct
	local CompactMotionSampleType = ByteNet.struct({
		T = ByteNet.float32,
		OffsetX = ByteNet.int16,
		OffsetY = ByteNet.int16,
		OffsetZ = ByteNet.int16,
		RotX = ByteNet.int16,
		RotY = ByteNet.int16,
		RotZ = ByteNet.int16,
	})

	local MotionType = ByteNet.struct({
		Base = ByteNet.cframe,
		Samples = ByteNet.array(CompactMotionSampleType),
	})

	local HitResultType = ByteNet.struct({
		Target = ByteNet.inst,
		HitPart = ByteNet.inst,
		Point = ByteNet.vec3,
		Normal = ByteNet.vec3,
		TOI = ByteNet.float32,
		SubStepIndex = ByteNet.uint16,
		Distance = ByteNet.float32,
	})

	return {
		AttackRequest = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				WeaponId = ByteNet.string,
				Kind = ByteNet.uint8,
				SequenceId = ByteNet.uint32,
				ClientTimestamp = ByteNet.float64,
				Motion = ByteNet.optional(MotionType),
				Origin = ByteNet.optional(ByteNet.cframe),
				MaxDistance = ByteNet.optional(ByteNet.float32),
				Velocity = ByteNet.optional(ByteNet.vec3),
			}),
		}),
		AttackResult = ByteNet.definePacket({
			reliabilityType = "reliable",
			value = ByteNet.struct({
				SequenceId = ByteNet.uint32,
				ServerTimestamp = ByteNet.float64,
				Hits = ByteNet.array(HitResultType),
			}),
		}),
	}
end)

-- AttackKind has no native bytenet type so it's packed as a uint8 - the conversion lives entirely
-- in this file, don't duplicate this table anywhere else
local KIND_TO_ID: { [AttackKind]: number } = {
	Melee = 0,
	Hitscan = 1,
	Projectile = 2,
	Radius = 3,
}
local ID_TO_KIND: { [number]: AttackKind } = {
	[0] = "Melee",
	[1] = "Hitscan",
	[2] = "Projectile",
	[3] = "Radius",
}

local Net = {}

function Net.FireAttackRequest(request: Types.AttackRequest): ()
	Packets.AttackRequest.send({
		WeaponId = request.WeaponId,
		Kind = KIND_TO_ID[request.Kind],
		SequenceId = request.SequenceId,
		ClientTimestamp = request.ClientTimestamp,
		Motion = MotionCompression.Encode(request.Motion) :: any,
		Origin = request.Origin,
		MaxDistance = request.MaxDistance,
		Velocity = request.Velocity,
	})
end

function Net.OnAttackRequest(handler: (player: Player, request: Types.AttackRequest) -> ()): ()
	Packets.AttackRequest.listen(function(data, player)
		if not player then
			return
		end
		handler(player, {
			WeaponId = data.WeaponId,
			Kind = ID_TO_KIND[data.Kind] or "Melee",
			SequenceId = data.SequenceId,
			ClientTimestamp = data.ClientTimestamp,
			Motion = MotionCompression.Decode(data.Motion :: any),
			Origin = data.Origin,
			MaxDistance = data.MaxDistance,
			Velocity = data.Velocity,
		})
	end)
end

-- fire-before-pool-return ordering ACTUALLY matters here: bytenet's struct writer walks these
-- HitResult fields synchronously inside sendTo, so this call has to run before HitboxServer hands
-- them back to ResultPool - swap the order and you're serializing a result someone already reset
function Net.FireAttackResult(player: Player, result: Types.AttackResult): ()
	Packets.AttackResult.sendTo({
		SequenceId = result.SequenceId,
		ServerTimestamp = result.ServerTimestamp,
		Hits = result.Hits :: any,
	}, player)
end

function Net.OnAttackResult(handler: (result: Types.AttackResult) -> ()): ()
	Packets.AttackResult.listen(function(data)
		handler({
			SequenceId = data.SequenceId,
			Hits = data.Hits :: any,
			ServerTimestamp = data.ServerTimestamp,
		})
	end)
end

return Net
