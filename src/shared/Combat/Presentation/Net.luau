--!strict

-- bare minimum wire schema, this is NOT the full PresentParams. Attachment/Color get resolved client
-- side by effect id convention instead of crossing the wire - bytenet doesn't even have a public
-- color3 dataType, so Color was never going over the network anyway
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)

local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("bytenet"))

local Packets = ByteNet.defineNamespace("CombatPresentation", function()
	return {
		Present = ByteNet.definePacket({
			reliabilityType = "unreliable", -- dropping a cosmetic effect packet is fine
			value = ByteNet.struct({
				EffectId = ByteNet.string,
				CFrame = ByteNet.optional(ByteNet.cframe),
				Target = ByteNet.optional(ByteNet.inst),
				Scale = ByteNet.optional(ByteNet.float32),
				EmitCount = ByteNet.optional(ByteNet.uint16),
				AttachToPartName = ByteNet.optional(ByteNet.string),
			}),
		}),
	}
end)

export type WireParams = {
	CFrame: CFrame?,
	Target: Instance?,
	Scale: number?,
	EmitCount: number?,
	AttachToPartName: string?,
}

local Net = {}

function Net.FireToAll(effectId: Types.EffectId, params: WireParams): ()
	Packets.Present.sendToAll({
		EffectId = effectId,
		CFrame = params.CFrame,
		Target = params.Target,
		Scale = params.Scale,
		EmitCount = params.EmitCount,
		AttachToPartName = params.AttachToPartName,
	})
end

function Net.FireToAllExcept(effectId: Types.EffectId, params: WireParams, except: Player): ()
	Packets.Present.sendToAllExcept({
		EffectId = effectId,
		CFrame = params.CFrame,
		Target = params.Target,
		Scale = params.Scale,
		EmitCount = params.EmitCount,
		AttachToPartName = params.AttachToPartName,
	}, except)
end

function Net.FireTo(effectId: Types.EffectId, params: WireParams, players: { Player }): ()
	Packets.Present.sendToList({
		EffectId = effectId,
		CFrame = params.CFrame,
		Target = params.Target,
		Scale = params.Scale,
		EmitCount = params.EmitCount,
		AttachToPartName = params.AttachToPartName,
	}, players)
end

function Net.OnPresent(handler: (effectId: Types.EffectId, params: WireParams) -> ()): ()
	Packets.Present.listen(function(data)
		handler(data.EffectId, {
			CFrame = data.CFrame,
			Target = data.Target,
			Scale = data.Scale,
			EmitCount = data.EmitCount,
			AttachToPartName = data.AttachToPartName,
		})
	end)
end

return Net
