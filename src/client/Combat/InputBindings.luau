--!strict

-- EXAMPLE input scheme, throw the whole thing out for a real game, don't build on top of it. binds
-- a moveset's skill ids to keys 1-4 by slot order, once - RequestActivate looks up the current
-- ClientSkills instance by id at call time, so this never needs rebinding after a respawn even
-- though the underlying Skill instance gets torn down and rebuilt (see CombatClient.luau's
-- equip-on-CharacterAdded)
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Moveset = require(ReplicatedStorage.Shared.Combat.Moveset)
local ClientSkills = require(script.Parent.ClientSkills)

local KEY_ORDER =
	{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

local InputBindings = {}

function InputBindings.BindMoveset(movesetId: string): ()
	local definition = Moveset.Get(movesetId)
	if not definition then
		return
	end

	for index, skillId in definition.SkillIds do
		local key = KEY_ORDER[index]
		if not key then
			break
		end

		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or input.KeyCode ~= key then
				return
			end
			ClientSkills.RequestActivate(skillId)
		end)
	end
end

return InputBindings
