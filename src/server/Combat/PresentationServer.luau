--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PresentationTypes = require(ReplicatedStorage.Shared.Combat.Presentation.Types)
local PresentationNet = require(ReplicatedStorage.Shared.Combat.Presentation.Net)

type EffectId = PresentationTypes.EffectId
type PresentParams = PresentationTypes.PresentParams
type WireParams = PresentationNet.WireParams

local function toWireParams(params: PresentParams): WireParams
	return {
		CFrame = params.CFrame,
		Target = params.Target,
		Scale = params.Scale,
		EmitCount = params.EmitCount,
		AttachToPartName = params.AttachToPartName,
	}
end

local PresentationServer = {}

function PresentationServer.PlayEffect(effectId: EffectId, params: PresentParams): ()
	PresentationNet.FireToAll(effectId, toWireParams(params))
end

function PresentationServer.PlayEffectExcept(effectId: EffectId, params: PresentParams, exclude: Player): ()
	PresentationNet.FireToAllExcept(effectId, toWireParams(params), exclude)
end

function PresentationServer.PlayEffectTo(effectId: EffectId, params: PresentParams, players: { Player }): ()
	PresentationNet.FireTo(effectId, toWireParams(params), players)
end

return PresentationServer
