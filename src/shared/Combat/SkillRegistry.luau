--!strict

-- Id -> constructor factory. actually shared, no realm-specific requires anywhere in here - server
-- and client both build a matching Skill instance off the same Id, so a packet only ever has to
-- carry a string, not a whole definition
local Skill = require(script.Parent.Skill)

export type SkillConstructor = (context: Skill.SkillContext) -> Skill.Skill

local constructors: { [string]: SkillConstructor } = {}

local SkillRegistry = {}

function SkillRegistry.Register(id: string, constructor: SkillConstructor): ()
	constructors[id] = constructor
end

function SkillRegistry.Create(id: string, context: Skill.SkillContext): Skill.Skill?
	local constructor = constructors[id]
	if not constructor then
		return nil
	end
	return constructor(context)
end

function SkillRegistry.IsRegistered(id: string): boolean
	return constructors[id] ~= nil
end

-- this is the whole trick: every skill file already calls SkillRegistry.Register(id, ...) at
-- module scope, so requiring it is the entire registration mechanism already. this just requires
-- every ModuleScript in a folder instead of you hand-listing them one by one somewhere - drop a
-- new skill file in the folder and it's registered, no other file ever needs to change
function SkillRegistry.RegisterFolder(folder: Instance): ()
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			require(child)
		end
	end
end

return SkillRegistry
