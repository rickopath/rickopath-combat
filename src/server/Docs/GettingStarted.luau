--!strict

--[[	
	--------------------------------------------------------------------------------
	STEP 1: TARGET REGISTRATION
	--------------------------------------------------------------------------------
	1. Spawn rig.
	2. Parent to `workspace.Alive`.
	3. Register on server:

	local CombatantRegistry = require(game.ServerScriptService.Server.Combat.CombatantRegistry)
	
	dummy.Parent = workspace.Alive
	local combatant = CombatantRegistry.Create(dummy, { MaxHealth = 100 })

	`Humanoid.Health` is ignored. Turn on `MirrorHealthToHumanoid = true` in `Config.luau` 
	if you need the default health bar to update.

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