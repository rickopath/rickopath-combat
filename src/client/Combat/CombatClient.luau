--!strict

-- top-level entry point for the combat framework's client half, wired from
-- src/client/init.client.luau. OWNS calling HitboxClient.Init() itself, same deal as CombatServer
-- owning HitboxServer.Init(). HitboxClient's reached via a path relative to script, NOT an absolute
-- one - see client/Combat/SkillHitbox.luau for why an absolute StarterPlayerScripts path here would
-- be a real bug that costs you an hour, not a style nit you can ignore
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitboxConfigModule = require(ReplicatedStorage.Shared.Hitbox.Config)
local CombatConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)
local Moveset = require(ReplicatedStorage.Shared.Combat.Moveset)
local Observers = require(ReplicatedStorage.Packages.observers)

local HitboxClient = require(script.Parent.Parent.Hitbox.HitboxClient)
local ClientMovement = require(script.Parent.ClientMovement)
local ClientSkills = require(script.Parent.ClientSkills)
local ClientCombatant = require(script.Parent.ClientCombatant)
local ClientMoveset = require(script.Parent.ClientMoveset)
local InputBindings = require(script.Parent.InputBindings)
local PresentationClient = require(script.Parent.PresentationClient)
local DebugOverlay = require(script.Parent.DebugOverlay)

type InitOptions = { SkillsFolder: Instance?, MovesetsFolder: Instance? }

local CombatClient = {}

function CombatClient.Init(combatConfig: CombatConfigModule.Config?, hitboxConfig: HitboxConfigModule.Config?, options: InitOptions?): ()
	local cfg = combatConfig or CombatConfigModule

	-- same conventional-folder scan as CombatServer.Init - each realm runs its own separate VM, so
	-- each realm needs its own scan, this isn't redundant even though it looks like it. see
	-- CombatServer.Init's comment for why this replaced a named require entirely
	local skillsFolder = (options and options.SkillsFolder) or ReplicatedStorage.Shared.Combat.Skills
	local movesetsFolder = (options and options.MovesetsFolder) or ReplicatedStorage.Shared.Combat.Movesets
	SkillRegistry.RegisterFolder(skillsFolder)
	Moveset.RegisterFolder(movesetsFolder)

	HitboxClient.Init(hitboxConfig)
	ClientMovement.Init(combatConfig)
	ClientSkills.Init()
	ClientCombatant.Init()
	PresentationClient.Init()
	-- pure dev tool, does nothing until F9/F10 are actually pressed - same "wired by default, strip
	-- before shipping" posture as InputBindings below, see DebugOverlay.luau's own header
	DebugOverlay.Init()

	-- has to be the SAME id the server has, or you'll predict skills locally that the server never
	-- equipped and watch every single one get rejected. warn matches CharacterLifecycle's
	local movesetId = cfg.DefaultMovesetId
	if not movesetId then
		warn("Combat: Config.DefaultMovesetId is not set - no moveset equipped locally, no keys bound.")
		return
	end

	-- re-equips on every single (re)spawn - ClientSkills.RequestActivate resolves the current Skill
	-- instance by id at call time, so InputBindings only ever needs to bind keys to skill ids ONCE,
	-- not per spawn. observeLocalCharacter (src/Packages/observers) replaces what used to be a
	-- hand-rolled `if player.Character then equip() end` + `player.CharacterAdded:Connect(equip)` -
	-- same effect, less code, and it's the well-tested primitive instead of two connections to keep
	-- straight ourselves
	Observers.observeLocalCharacter(function(_character: Model)
		ClientMoveset.EquipTo(movesetId)
	end)

	InputBindings.BindMoveset(movesetId)
end

return CombatClient
