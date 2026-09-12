--!strict

-- registers any non-player Model already sitting in workspace.Alive (a hand-placed training dummy,
-- say) as a basic Combatant. CharacterLifecycle only ever wires up real Players - AliveRegistry
-- will happily track and hit-detect ANY Model parented under Alive, no questions asked, but
-- CombatantRegistry (the actual health/damage half) only gets populated by whatever explicitly
-- calls Create. this is that missing call, for a static target that has nobody else calling it. a
-- real NPC spawner does the exact same two calls - parent under Alive, then CombatantRegistry.Create
-- - this file's just doing it generically for whatever's already sitting there when the server boots
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local CombatantRegistry = require(script.Parent.CombatantRegistry)
local CharacterLifecycle = require(script.Parent.CharacterLifecycle)

local ALIVE_FOLDER_NAME = "Alive"
local DUMMY_MAX_HEALTH = 200

local cfg: ConfigModule.Config = ConfigModule

local function isPlayerCharacter(model: Model): boolean
	for _, player in Players:GetPlayers() do
		if player.Character == model then
			return true
		end
	end
	return false
end

local function registerDummy(model: Model): ()
	-- Player.Character gets set before CharacterAdded even fires, so this correctly skips a player's
	-- own character even when it races the exact same ChildAdded event that CharacterLifecycle's
	-- own `character.Parent = alive` line triggers. verified this actually holds, not just assumed it
	if isPlayerCharacter(model) then
		return
	end
	if CombatantRegistry.Get(model) then
		return
	end
	local combatant = CombatantRegistry.Create(model, { MaxHealth = DUMMY_MAX_HEALTH }, nil)
	-- same opt-in rule as real players - see Config.MirrorHealthToHumanoid's comment in Config.luau
	if cfg.MirrorHealthToHumanoid then
		CharacterLifecycle.MirrorHealthToHumanoid(model, combatant)
	end
end

local DummyCombatants = {}

function DummyCombatants.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end
	local alive = workspace:WaitForChild(ALIVE_FOLDER_NAME)
	for _, child in alive:GetChildren() do
		if child:IsA("Model") then
			registerDummy(child)
		end
	end
	alive.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Model") then
			registerDummy(child)
		end
	end)
end

return DummyCombatants
