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

	To use the default built-in VFX handler, add this to your `init.client.luau`:
	```lua
	local PresentationClient = require(script.Combat.PresentationClient)
	-- To change the default folders, pass a table:
	-- PresentationClient.UseDefaultPresentation({ VFXFolder = game.ReplicatedStorage.MyParticles })
	PresentationClient.UseDefaultPresentation()
	```
	
	Place a ParticleEmitter named "Hit_Sparks" in `ReplicatedStorage.VFX`.
	Place a Sound named "SwooshSound" in `SoundService`.

	You can customize templates by adding these Attributes in Studio:
	- `AttachToPart` (String): Part name to stick to (e.g., "RightHand").
	- `RideTarget` (Bool): If true, forces a Part/Model effect to move with the target.
	- `Lifetime` (Number): Seconds before the effect gets deleted (default 3).
	- `EmitCount` (Number): How many particles burst out (default 20).

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

	WANT TO WRITE YOUR OWN CUSTOM HANDLER INSTEAD?
	Don't call `UseDefaultPresentation()`. Hook the signal yourself in your client script:
	```lua
	local PresentationClient = require(script.Combat.PresentationClient)
	PresentationClient.OnEffectRequested:Connect(function(effectId, params)
		if effectId == "Blood" then
			print("Splatter at", params.CFrame)
		end
	end)
	```

	--------------------------------------------------------------------------------
	STEP 5: KNOCKBACK & STATUS EFFECTS
	--------------------------------------------------------------------------------
	Knockback: Call `Knockback.Apply(model, direction, strength)` inside `OnDamaged`.

	Status Effects: 
	The framework comes with a few built-in builders. 
	
	```lua
	local StatusEffectBuilders = require(game.ReplicatedStorage.Shared.Combat.StatusEffectBuilders)
	
	-- DamageOverTime parameters: (id, damageType, amountPerTick, durationSeconds, stackRule)
	-- NOTE: amountPerTick fires every Server Tick (10 times a second by default), NOT per second!
	local BURNING = StatusEffectBuilders.DamageOverTime("Burning", "Fire", 3, 4, "Refresh")
	
	local STUNNED = StatusEffectBuilders.Stun(2.5) 
	local SLOWED = StatusEffectBuilders.ModifyResistance("Slowed", "Physical", 0.5, 3)
	```
	
	To make a completely custom effect (like a lifesteal buff), you just construct the table yourself:
	```lua
	local LIFESTEAL = {
		Id = "Lifesteal",
		Duration = 5,
		MaxStacks = 1,
		StackRule = "Refresh",
		OnApply = function(combatant, stacks)
			-- Do custom math
		end,
		OnTick = function(combatant, dt, stacks)
			combatant:Heal(1 * stacks)
		end,
		OnExpire = function(combatant)
			-- Clean up
		end,
	}
	```

	Apply them in your damage spec:
	local DAMAGE_SPEC = {
		Amount = 15,
		OnHit = function(target, attacker, helpers)
			target:ApplyStatusEffect(BURNING)
			target:ApplyStatusEffect(LIFESTEAL)
		end,
	}

	--------------------------------------------------------------------------------
	STEP 6: PASSIVES
	--------------------------------------------------------------------------------
	Passives live in `src/shared/Combat/Passives/`. Drop a file there and
	`PassiveRegistry.RegisterFolder` picks it up automatically on server boot.

	A passive is a plain table with reaction hooks. No Activate, no Cooldown.

	```lua
	local PassiveRegistry = require(game.ReplicatedStorage.Shared.Combat.PassiveRegistry)

	PassiveRegistry.Register("Thorns", function(context)
		return {
			Id = "Thorns",
			OnEquipped = function(ctx)
				-- fires once when this passive is equipped to the combatant
			end,
			OnDamageTaken = function(ctx, amount, damageType, source)
				-- fires every time this combatant takes damage
				-- ctx.Combatant is the owner. source is the attacker's Model
				if source then
					local attacker = CombatantRegistry.Get(source)
					if attacker then
						attacker:ApplyDamage(amount * 0.2, "Physical", ctx.Owner)
					end
				end
			end,
			OnDamageDealt = function(ctx, amount, damageType, target)
				-- fires every time this combatant deals damage
				-- target is the victim's Combatant object
			end,
			OnUnequipped = function(ctx)
				-- fires when removed - clean up anything you set up in OnEquipped
			end,
		}
	end)
	```

	Equip it to a combatant on the server:
	```lua
	local CombatantPassives = require(game.ServerScriptService.Server.Combat.CombatantPassives)
	CombatantPassives.Equip(character, "Thorns")
	```

	Unequip it:
	```lua
	CombatantPassives.Unequip(character, "Thorns")
	```

	--------------------------------------------------------------------------------
	STEP 7: LAG SIMULATION
	--------------------------------------------------------------------------------
	Rollback does not function at 0 ping.
	To test:
	1. Studio Settings -> Network.
	2. Set `Incoming Replication Lag` to `0.2`.
	3. Test hits.

	Reference `APIReference.luau` for complete methods.
]]

return nil