--!strict

-- CombatantSkills.Equip and CombatantPassives.Equip both need to build the exact same server-side
-- context.Presentation.PlayEffect closure - default excludes the caster (who already saw their own
-- predicted copy, if this is being called from something they cast), options let you override.
-- extracted here instead of copy-pasted in both files
local PresentationServer = require(script.Parent.PresentationServer)
local CombatDamageBridge = require(script.Parent.CombatDamageBridge)

type PlayEffectOptions = CombatDamageBridge.PlayEffectOptions

local PresentationFacade = {}

function PresentationFacade.Build(combatant: any): { PlayEffect: (effectId: string, params: any, options: PlayEffectOptions?) -> () }
	return {
		PlayEffect = function(effectId: string, params: any, options: PlayEffectOptions?)
			if options and options.Only then
				PresentationServer.PlayEffectTo(effectId, params, options.Only)
				return
			end
			local excludeCaster = if options and options.ExcludeCaster ~= nil then options.ExcludeCaster else true
			if excludeCaster and combatant.Player then
				PresentationServer.PlayEffectExcept(effectId, params, combatant.Player)
			else
				-- either ExcludeCaster was explicitly turned off, or there's no owning Player to
				-- exclude in the first place (an NPC/dummy) - broadcast to everyone
				PresentationServer.PlayEffect(effectId, params)
			end
		end,
	}
end

return PresentationFacade
