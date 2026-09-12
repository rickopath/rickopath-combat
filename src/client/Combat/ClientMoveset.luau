--!strict

-- client half of equipping a moveset. server half's small enough it just lives inline in
-- CharacterLifecycle.luau instead of its own file. split by realm for the same reason SkillHitbox
-- is - there's no magic file that reaches across client and server both, stop looking for one
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Moveset = require(ReplicatedStorage.Shared.Combat.Moveset)
local ClientSkills = require(script.Parent.ClientSkills)

local ClientMoveset = {}

function ClientMoveset.EquipTo(movesetId: string): ()
	local definition = Moveset.Get(movesetId)
	if not definition then
		return
	end
	for _, skillId in definition.SkillIds do
		ClientSkills.Equip(skillId)
	end
end

return ClientMoveset
