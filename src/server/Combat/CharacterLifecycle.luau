--!strict

-- hooks every player's character lifecycle via Observers.observeCharacter (src/Packages/observers) -
-- parents the character under workspace.Alive, creates its Combatant, equips whatever moveset
-- Config.DefaultMovesetId names (if anything). there is no built-in "class" concept - a class was
-- only ever a CombatantDefinition plus a MovesetId bundled together, which you can do yourself in
-- about four lines. see server/Docs/Tutorial.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Combat.Types)
local Moveset = require(ReplicatedStorage.Shared.Combat.Moveset)
local ConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local Observers = require(ReplicatedStorage.Packages.observers)
local CombatantRegistry = require(script.Parent.CombatantRegistry)
local CombatantSkills = require(script.Parent.CombatantSkills)

local ALIVE_FOLDER_NAME = "Alive"

-- the one thing that genuinely can't be nil-by-default: a character with no health isn't a
-- character, it's a crash waiting to happen. override via Config.DefaultCombatantDefinition
-- instead of editing this - Stamina and Mana are only here because the shipped example moveset's
-- five skills (Punch/Dash cost Stamina, Fireball/Heal/Shield cost Mana) need both to exist or
-- PayCost silently rejects every activation of half of them (no resource pool = "cost" rejection,
-- not a crash, but a spawned character that can't cast half its kit is a bad first impression)
local FALLBACK_COMBATANT: Types.CombatantDefinition = {
	MaxHealth = 150,
	Resources = {
		{ Id = "Stamina", Max = 100, RegenPerSecond = 12, RegenDelayAfterSpendSeconds = 1 },
		{ Id = "Mana", Max = 100, RegenPerSecond = 8, RegenDelayAfterSpendSeconds = 1 },
	},
}

local cfg: ConfigModule.Config = ConfigModule

local function equipMoveset(model: Model, movesetId: string): ()
	local definition = Moveset.Get(movesetId)
	if not definition then
		-- typo'd id, or the Movesets folder never got scanned on this realm - either way you'd
		-- otherwise get a character with no skills and zero explanation, so say something
		warn(
			string.format(
				"Combat: Config.DefaultMovesetId is %q but no moveset is registered under that id - nothing equipped. Check Moveset.RegisterFolder actually ran on the server.",
				movesetId
			)
		)
		return
	end
	for _, skillId in definition.SkillIds do
		CombatantSkills.Equip(model, skillId)
	end
end

-- Combatant.Health is the ONE authoritative number - damage math, resistances, snapshot replication,
-- all of it reads from here. Humanoid.Health is never touched by any of that on its own, and this
-- function is NOT called automatically - see Config.MirrorHealthToHumanoid. call it yourself (or
-- flip that config flag) only if you actually want the simple built-in BIDIRECTIONAL mirror;
-- Combatant.OnDamaged/OnHealed/OnDied are the generic hook surface either way, wire your own sync
-- to Humanoid/a UI/an attribute/whatever from those instead if you want more control - see
-- server/Docs/ImportantMisc.luau for the recommended Observers.observeCharacter-based pattern
local function mirrorHealthToHumanoid(character: Model, combatant): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Roblox auto-injects a Script named "Health" into every loaded Player character that
	-- regenerates ~1% of MaxHealth/second - NEVER deleted here, or anywhere else in this
	-- framework. instead of fighting or removing it, its effect gets folded back into
	-- Combatant.Health for real (see the GetPropertyChangedSignal listener below), so the regen
	-- script and this mirror cooperate instead of one deleting the other. this is a documented
	-- Roblox engine quirk, not a framework bug - see devforum "Remove ROBLOX Default Health
	-- Regeneration" if you're wondering where the behavior comes from
	local function pushToHumanoid(newHealth: number)
		humanoid.Health = math.clamp(newHealth, 0, humanoid.MaxHealth)
	end

	humanoid.MaxHealth = combatant.Health.Max
	pushToHumanoid(combatant.Health.Current)

	-- always push the CURRENT authoritative value, not a manual +/-amount off humanoid.Health -
	-- that's what keeps this safe to call from the loopback path below too (see its comment)
	combatant.OnDamaged:Connect(function()
		pushToHumanoid(combatant.Health.Current)
	end)
	combatant.OnHealed:Connect(function()
		pushToHumanoid(combatant.Health.Current)
	end)

	-- catches anything ELSE moving Humanoid.Health on its own - chiefly the regen script above
	-- ticking it upward every second. no separate guard flag needed to stop this from reacting to
	-- OUR OWN writes: pushToHumanoid always sets humanoid.Health to exactly combatant.Health.Current,
	-- so by the time this fires for one of those writes, delta is already 0 and neither branch
	-- below runs - Roblox also doesn't refire a property-changed signal for a same-value write, so
	-- this can't ping-pong with itself either way. a genuine external change (the regen script, or
	-- anything else) is the only thing that ever produces a nonzero delta here
	humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		local delta = humanoid.Health - combatant.Health.Current
		if delta > 0 then
			-- the regen script (or whatever) raised Humanoid.Health on its own - fold that gain
			-- into the authoritative pool for real instead of letting the two numbers diverge
			combatant:Heal(delta)
		elseif delta < 0 then
			-- something dropped Humanoid.Health directly, NOT through Combatant:ApplyDamage -
			-- Combatant.Health stays the one authoritative number, so resnap Humanoid back to it
			-- instead of quietly accepting unaccounted damage from an out-of-band write
			pushToHumanoid(combatant.Health.Current)
		end
	end)
end

-- returns a cleanup function - Observers.observeCharacter calls this for us when the character
-- leaves the game hierarchy (respawn, death, player leaving), which is more correct than the old
-- PlayerRemoving-only cleanup: it also fires if a character is destroyed without the player leaving
local function onCharacter(player: Player, character: Model): () -> ()
	local alive = workspace:FindFirstChild(ALIVE_FOLDER_NAME)
	if not alive then
		error("Combat: workspace.Alive folder not found - required for hittable entity tracking")
	end

	-- must be parented under Alive BEFORE CombatantRegistry.Create - that call hard-errors if you
	-- get the order wrong, don't move this line down thinking it's just tidying up
	character.Parent = alive

	local combatant = CombatantRegistry.Create(character, cfg.DefaultCombatantDefinition or FALLBACK_COMBATANT, player)

	if cfg.MirrorHealthToHumanoid then
		mirrorHealthToHumanoid(character, combatant)
	end

	-- no default configured = spawn with health and nothing to do with it. that's a legitimate setup
	-- (you might equip skills yourself elsewhere), so it's a warn, not an error - but it's loud,
	-- because "why don't my keybinds do anything" is otherwise a miserable thing to debug
	local movesetId = cfg.DefaultMovesetId
	if movesetId then
		equipMoveset(character, movesetId)
	else
		warn(
			string.format(
				"Combat: Config.DefaultMovesetId is not set - %s spawned with no skills equipped. Set it (same id on client and server) or call CombatantSkills.Equip yourself.",
				player.Name
			)
		)
	end

	return function()
		CombatantRegistry.Destroy(character)
	end
end

local CharacterLifecycle = {}

CharacterLifecycle.MirrorHealthToHumanoid = mirrorHealthToHumanoid

function CharacterLifecycle.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end

	Observers.observeCharacter(onCharacter)
end

return CharacterLifecycle
