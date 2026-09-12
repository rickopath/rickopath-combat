--!strict

--[[	
	--------------------------------------------------------------------------------
	STEP 1: TARGET REGISTRATION
	--------------------------------------------------------------------------------
	1. Spawn rig.
	2. Parent to `workspace.Alive`.

	That's it. `DummyCombatants.luau` automatically tracks any model placed in 
	that folder on server startup and wires up the `Combatant` wrapper for you.

	`Humanoid.Health` is ignored by the damage system. Turn on `MirrorHealthToHumanoid = true` 
	in `Config.luau` (ServerConfig Combat) if you need the default health bar to reflect actual internal health.
	
	NOTE: 
	The framework configuration is split across two files for security:
	1. `src/shared/Combat/Config.luau` (Shared config, safe to replicate to clients)
	2. `src/server/Combat/ServerConfig.luau` (Server overrides, authoritative tuning)

	You should tweak values like lag tolerance, tick intervals, and default movesets 
	in these files to fit your game. See `ImportantMisc.luau` for full details later.
	--------------------------------------------------------------------------------
	STEP 2: SKILL CREATION
	--------------------------------------------------------------------------------
	Copy `src/shared/Combat/Skills/Punch.luau`. Change the ID.

	local HITBOX_CONFIG = {
		Id = "MySlash",
		Kind = "Melee", 
		Shape = "Box",
		HalfExtents = Vector3.new(2, 2.5, 3), 
		AttachOffset = CFrame.new(0, 0, -3), 
		MaxTargetsPerSwing = 5,
	}

	--------------------------------------------------------------------------------
	STEP 3: MOVESET REGISTRATION
	--------------------------------------------------------------------------------
	Create `src/shared/Combat/Movesets/MyMoveset.luau`:

	local Moveset = require(script.Parent.Parent.Moveset)

	Moveset.Register({
		Id = "MyMoveset",
		SkillIds = { "MySlash", "Dash", "Fireball" }, 
	})

	Set `DefaultMovesetId = "MyMoveset"` in `src/shared/Combat/Config.luau`.

	--------------------------------------------------------------------------------
	STEP 4: PRESENTATION (VFX/SOUNDS)
	--------------------------------------------------------------------------------
	Keep visuals in the Presentation layer. Do not instance particles in combat logic.

	Place a ParticleEmitter named "Hit_Sparks" in `ReplicatedStorage.VFX`.
	Place a Sound named "SwooshSound" in `SoundService`.

	CLIENT PREDICTION:
	local presentation = self.Context.Presentation
	if presentation then
		presentation.PlayEffect("SwooshSound") 
	end
	
	Use the default Roblox `Animator` for animations.

	SERVER CONFIRMATION:
	local DAMAGE_SPEC = {
		Amount = 15,
		OnHit = function(target, attacker, helpers)
			helpers.PlayEffect("Hit_Sparks", { Target = target.Model })
		end,
	}

	For custom emit counts, pass params:
	`helpers.PlayEffect("Hit_Sparks", { Target = target.Model, EmitCount = 50 })`

	--------------------------------------------------------------------------------
	STEP 5: KNOCKBACK & STATUS EFFECTS
	--------------------------------------------------------------------------------
	Knockback: Call `Knockback.Apply(model, direction, strength)` inside `OnDamaged`.

	Status Effects: 
	local StatusEffectBuilders = require(game.ReplicatedStorage.Shared.Combat.StatusEffectBuilders)
	
	local BURNING = StatusEffectBuilders.DamageOverTime("Burning", "Fire", 3, 4, "Refresh")
	local STUNNED = StatusEffectBuilders.Stun(2.5) 
	
	local DAMAGE_SPEC = {
		Amount = 15,
		OnHit = function(target, attacker, helpers)
			target:ApplyStatusEffect(BURNING)
		end,
	}

	--------------------------------------------------------------------------------
	STEP 6: LAG SIMULATION
	--------------------------------------------------------------------------------
	Rollback does not function at 0 ping.
	To test:
	1. Studio Settings -> Network.
	2. Set `Incoming Replication Lag` to `0.2`.
	3. Test hits.

	Reference `APIReference.luau` for complete methods.
]]

return nil