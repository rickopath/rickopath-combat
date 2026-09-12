--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitboxTypes = require(ReplicatedStorage.Shared.Hitbox.Types)
local HitboxServer = require(ServerScriptService.Server.Hitbox.HitboxServer)
local HitboxConfigModule = require(ReplicatedStorage.Shared.Hitbox.Config)
local CombatConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local ServerHitboxConfig = require(ServerScriptService.Server.Hitbox.ServerConfig)
local ServerCombatConfig = require(script.Parent.ServerConfig)

local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)
local Moveset = require(ReplicatedStorage.Shared.Combat.Moveset)
local PassiveRegistry = require(ReplicatedStorage.Shared.Combat.PassiveRegistry)
local CombatantRegistry = require(script.Parent.CombatantRegistry)
local CombatDamageBridge = require(script.Parent.CombatDamageBridge)
local MovementReconciler = require(script.Parent.MovementReconciler)
local CombatantSkills = require(script.Parent.CombatantSkills)
local CharacterLifecycle = require(script.Parent.CharacterLifecycle)
local SnapshotReplicator = require(script.Parent.SnapshotReplicator)
local DummyCombatants = require(script.Parent.DummyCombatants)

require(script.Parent.PresentationServer)

type AttackRequest = HitboxTypes.AttackRequest
type InitOptions = { SkillsFolder: Instance?, MovesetsFolder: Instance?, PassivesFolder: Instance? }

local function isAttackAllowed(player: Player, request: AttackRequest): boolean
	local character = player.Character
	if not character then
		return false
	end

	local skill = CombatantSkills.FindByWeaponId(character, request.WeaponId)
	if not skill then
		warn(string.format("Combat: %s has no equipped skill for weapon %q - attack rejected", player.Name, request.WeaponId))
		return false
	end

	local accepted, reason = skill:TryActivate()
	if not accepted and reason ~= "cooldown" then
		warn(string.format("Combat: %s's attack with %q rejected - %s", player.Name, request.WeaponId, reason or "unknown"))
	end
	return accepted or reason == "cooldown"
end

local function mergeServerOverrides(base: { [string]: any }, overrides: { [string]: any }): { [string]: any }
	local merged = table.clone(base)
	for key, value in overrides do
		merged[key] = value
	end
	return merged
end

local CombatServer = {}

function CombatServer.Init(combatConfig: CombatConfigModule.Config?, hitboxConfig: HitboxConfigModule.Config?, options: InitOptions?): ()
	local finalCombatConfig = mergeServerOverrides(combatConfig or CombatConfigModule, ServerCombatConfig) :: CombatConfigModule.Config

	local skillsFolder = (options and options.SkillsFolder) or ReplicatedStorage.Shared.Combat.Skills
	local movesetsFolder = (options and options.MovesetsFolder) or ReplicatedStorage.Shared.Combat.Movesets
	local passivesFolder = (options and options.PassivesFolder) or ReplicatedStorage.Shared.Combat.Passives
	SkillRegistry.RegisterFolder(skillsFolder)
	Moveset.RegisterFolder(movesetsFolder)
	PassiveRegistry.RegisterFolder(passivesFolder)

	CombatantRegistry.Init(finalCombatConfig)
	MovementReconciler.Init(finalCombatConfig)
	CombatantSkills.Init()
	SnapshotReplicator.Init(finalCombatConfig)
	CharacterLifecycle.Init(finalCombatConfig)
	DummyCombatants.Init(finalCombatConfig)

	local finalHitboxConfig =
		mergeServerOverrides(hitboxConfig or HitboxConfigModule, ServerHitboxConfig) :: HitboxConfigModule.Config
	finalHitboxConfig.OnApplyDamage = CombatDamageBridge.Dispatch
	finalHitboxConfig.IsAttackAllowed = isAttackAllowed
	HitboxServer.Init(finalHitboxConfig)
end

return CombatServer
