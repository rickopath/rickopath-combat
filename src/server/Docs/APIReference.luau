--!strict

-- API Reference.
-- See GettingStarted.luau and ImportantMisc.luau.
--
-- NOTE: The framework configuration is intentionally split into two files:
-- 1. `src/shared/Combat/Config.luau` (Safe fallback/shared data)
-- 2. `src/server/Combat/ServerConfig.luau` (Server overrides for sensitive tuning)
-- You are expected to modify these files to fit your game's needs (tick rates, lag tolerance, etc).

--------------------------------------------------------------------------------
-- COMBATANT
--------------------------------------------------------------------------------

--- @class CombatantRegistry

--- Registers a model as damageable. Model must already be parented under workspace.Alive.
--- @param model Model
--- @param definition CombatantDefinition
--- @param player Player? -- Omit for NPCs
--- @return Combatant
--[=[
    local combatant = CombatantRegistry.Create(model, {
        MaxHealth = 150,
        Resources = { { Id = "Stamina", Max = 100, RegenPerSecond = 12 } },
        Resistances = { [DamageType.Physical] = 0.8 },
    }, player)
]=]

--- @param model Model
--- @return Combatant?
--- @return nil

--- @param model Model
--- @return nil

--- @return {[Model]: Combatant}

--- @class Combatant

--- Runs DamageModifier, then Resistances. Fires OnDamaged if dealt > 0.
--- @param amount number
--- @param damageType string
--- @param sourceModel Model?
--- @return number -- The actual damage dealt

--- @param amount number
--- @param sourceModel Model?
--- @return number -- The actual amount healed

--- @param source Model?
--- @return nil

--- @param healthFraction number? -- Fraction of MaxHealth (default 1.0)
--- @return nil

--- @param id string -- "Health" is treated as just another pool
--- @return ResourcePool?

--- @return {[string]: ResourcePool}

--- @param def StatusEffectDefinition
--- @return nil

--- Cleanses a status effect and fires OnExpire.
--- @param id string
--- @return nil

--- @param id string
--- @return boolean

--- @return {[string]: {Stacks: number, ExpiresAt: number}}

--- @param damageType string
--- @param multiplier number
--- @return nil

--- @param team string?
--- @return nil

--- Skips damage and OnHit entirely while true. Visuals still play. Use for I-frames.
--- @param value boolean
--- @return nil

--- The pre-damage hook. Return 0 to fully block. Set once on creation.
--- @param fn function(amount: number, damageType: string, attackerCharacter: Model?) -> number
--- @return nil

--- Physics-authoritative root. Disabling anchors the root and rejects server-side movement.
--- @param enabled boolean
--- @return nil

--- Generic buff system: (Base + sum of Adds) * (product of Multiplies).
--- @param statId string
--- @param modifierId string
--- @param value number
--- @param mode "Add" | "Multiply"
--- @return nil

--- @param statId string
--- @param modifierId string
--- @return nil

--- @param statId string
--- @param baseValue number
--- @return number

--- ComboIndex += 1, updates LastAttackTime.
--- @return number -- newIndex

--- Sets ComboIndex to 0.
--- @return nil

-- SIGNALS
-- OnDamaged(amount: number, damageType: string, source: Model?)
-- OnHealed(amount: number, source: Model?)
-- OnDied(source: Model?)
-- OnDamageDealt(amount: number, damageType: string, target: any) -- Fires for the attacker
-- OnStatusEffectApplied(id: string, stacks: number)
-- OnStatusEffectExpired(id: string)

--------------------------------------------------------------------------------
-- SKILL
--------------------------------------------------------------------------------

--- @class SkillRegistry

--- Called at module scope by every skill file. Requiring the file IS the registration.
--- @param id string
--- @param constructor function(context: SkillContext) -> Skill
--- @return nil

--- @class Skill
--- Overridable lifecycle hooks for skills. 
--- Override OnCancel/OnDestroy, not Cancel/Destroy wrappers.

--- @param ... any
--- @return boolean -- false = activation failed, no cooldown starts

--- @param ... any
--- @return boolean, string?

--- @param reason string?
--- @return nil

--- @return nil

--- @param dt number
--- @return nil

--- Base wrapper: Runs CanActivate -> PayCost -> Activate -> StartCooldown.
--- @param ... any
--- @return boolean -- accepted
--- @return string? -- reason for failure

--- @return boolean

--- @return number

--- Base wrapper: Fires OnCancelled(reason), then calls your OnCancel(reason) override.
--- @param reason string?
--- @return nil

--- Base wrapper: Cleans up OnCancelled, then calls your OnDestroy() override.
--- @return nil

-- SIGNALS
-- OnCancelled(reason: string?)

--------------------------------------------------------------------------------
-- STATUS EFFECTS
--------------------------------------------------------------------------------

--- @class StatusEffectBuilders
--- Factories for StatusEffectDefinition. Build at module scope.

--- amountPerTick is per engine tick (default 1/10s), NOT per second.
--- @param id string
--- @param damageType string
--- @param amountPerTick number
--- @param duration number
--- @param stackRule "Refresh" | "Stack" | "Ignore"
--- @param onExpire function?
--- @return StatusEffectDefinition

--- Restores the prior resistance value upon expiration.
--- @param id string
--- @param damageType string
--- @param multiplier number
--- @param duration number
--- @param onExpire function?
--- @return StatusEffectDefinition

--- ID is strictly "Stunned". Base CanActivate automatically checks this.
--- @param duration number
--- @param onExpire function?
--- @return StatusEffectDefinition

--- ID is strictly "Rooted". One-liner wrapper over SetMovementEnabled.
--- @param duration number
--- @param onExpire function?
--- @return StatusEffectDefinition

--------------------------------------------------------------------------------
-- PRESENTATION
--------------------------------------------------------------------------------

--- Client: local, instant prediction. Server: broadcasts to all except caster.
--- @param effectId string
--- @param params PresentParams
--- @param options PlayEffectOptions?
--- @return nil

-- SIGNALS
-- PresentationClient.OnEffectRequested(effectId: string, params: PresentParams)

--------------------------------------------------------------------------------
-- MOVEMENT
--------------------------------------------------------------------------------

--- Client only. Sends a validation request; doesn't actually move the character.
--- @param skillId string
--- @param to CFrame
--- @param maxDistance number
--- @return number -- sequenceId

-- SIGNALS
-- ClientMovement.OnMovementResult(sequenceId: number, result: MovementResult)

--------------------------------------------------------------------------------
-- HITBOX
--------------------------------------------------------------------------------

--- Called once per skill construction inside SkillRegistry.Register. Do not call inside Activate.
--- @param weaponId string
--- @param hitboxConfig HitboxConfig
--- @param damageSpec DamageSpec
--- @return nil

--------------------------------------------------------------------------------
-- UTILITIES
--------------------------------------------------------------------------------

--- @class ResourcePool
--- @field Current number
--- @field Max number

--- Clamps to [0, Max].
--- @param value number
--- @return nil

--- Negative delta allowed. Clamps at 0.
--- @param delta number
--- @return number -- newCurrent

--- Atomic check-and-subtract. Use for skill costs.
--- @param amount number
--- @return boolean

-- SIGNALS
-- OnChanged(old: number, new: number)
-- OnDepleted()

--- @class Knockback
--- Server only. Overwrites horizontal velocity, preserves Y.
--- @param character Model
--- @param direction Vector3
--- @param speed number
--- @return nil

--- @class HitStop
--- Client only. Freezes WalkSpeed temporarily (0.05-0.15s).
--- @param character Model
--- @param duration number
--- @return nil

--- @class DebugDraw
--- Toggleable in-game via F10.
--- @param cf CFrame
--- @param halfExtents Vector3
--- @param color Color3?
--- @param duration number?
--- @return nil