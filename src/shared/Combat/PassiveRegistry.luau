--!strict

-- Id -> constructor factory, identical shape to SkillRegistry.luau on purpose - same
-- RegisterFolder trick applies (a Passives/ folder, auto-scanned by CombatServer.Init the same way
-- Skills/Movesets are, if you wire it in - see server/Docs/Tutorial.luau)
local PassiveSkill = require(script.Parent.PassiveSkill)

export type PassiveConstructor = (context: any) -> PassiveSkill.PassiveDefinition

local constructors: { [string]: PassiveConstructor } = {}

local PassiveRegistry = {}

function PassiveRegistry.Register(id: string, constructor: PassiveConstructor): ()
	constructors[id] = constructor
end

function PassiveRegistry.Create(id: string, context: any): PassiveSkill.PassiveDefinition?
	local constructor = constructors[id]
	if not constructor then
		return nil
	end
	return constructor(context)
end

function PassiveRegistry.IsRegistered(id: string): boolean
	return constructors[id] ~= nil
end

-- same trick as SkillRegistry.RegisterFolder - a passive file's entire job is calling
-- PassiveRegistry.Register at module scope, so requiring every file in the folder IS the registration
function PassiveRegistry.RegisterFolder(folder: Instance): ()
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			require(child)
		end
	end
end

return PassiveRegistry
