--!strict

-- reusable Id -> skill list bundle, deliberately decoupled from any one character class - two
-- classes can share a moveset, an NPC can steal a player class's moveset, whatever. this file is
-- JUST the registry. actually equipping one onto a model is realm-specific (CombatantSkills vs
-- ClientSkills) - client half's in ClientMoveset.luau, server half's small enough it just lives
-- inline in CharacterLifecycle.luau, didn't need its own file

export type MovesetDefinition = {
	Id: string,
	SkillIds: { string },
}

local movesets: { [string]: MovesetDefinition } = {}

local Moveset = {}

function Moveset.Register(definition: MovesetDefinition): ()
	movesets[definition.Id] = definition
end

function Moveset.Get(id: string): MovesetDefinition?
	return movesets[id]
end

-- same trick as SkillRegistry.RegisterFolder - a moveset definition file's entire job is calling
-- Moveset.Register at module scope, so requiring every file in the folder IS the registration.
-- drop a new moveset file in the folder and it's registered, no manifest file to remember to edit
function Moveset.RegisterFolder(folder: Instance): ()
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			require(child)
		end
	end
end

return Moveset
