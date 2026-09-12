--!strict

-- broadcasts every tracked combatant's current snapshot to all clients, unreliable channel - a
-- stale health bar for one tick isn't the end of the world, this isn't hit detection, relax.
-- broadcast-to-all is deliberate too - real proximity filtering needs spatial partitioning and
-- that's not happening in this pass
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)
local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("bytenet"))

type CombatantSnapshotEntry = Types.CombatantSnapshotEntry

local Packets = ByteNet.defineNamespace("CombatSnapshot", function()
	-- MUST be built inside this callback, not hoisted above defineNamespace - same trap as
	-- Hitbox/Net.luau, go read that comment if you need the full explanation again. short version:
	-- build it outside and the client blows up on valueFolder:FindFirstChild(nil) with zero useful
	-- context. keep these in the same relative order as the packet structs referencing them too,
	-- bytenet matches everything positionally between realms
	local ResourceType = ByteNet.struct({
		Current = ByteNet.float32,
		Max = ByteNet.float32,
	})

	local StatusEffectType = ByteNet.struct({
		Stacks = ByteNet.uint8,
		ExpiresAt = ByteNet.float64,
	})

	local EntryType = ByteNet.struct({
		Model = ByteNet.inst,
		Health = ByteNet.float32,
		MaxHealth = ByteNet.float32,
		Resources = ByteNet.map(ByteNet.string, ResourceType),
		StatusEffects = ByteNet.map(ByteNet.string, StatusEffectType),
		Team = ByteNet.optional(ByteNet.string),
		IsInvulnerable = ByteNet.bool,
	})

	return {
		Snapshots = ByteNet.definePacket({
			reliabilityType = "unreliable",
			value = ByteNet.struct({
				Entries = ByteNet.array(EntryType),
			}),
		}),
	}
end)

local Net = {}

function Net.FireSnapshots(entries: { CombatantSnapshotEntry }): ()
	Packets.Snapshots.sendToAll({ Entries = entries :: any })
end

-- per-player send, same packet, same unreliable channel - this is what makes proximity filtering
-- possible at all. SnapshotReplicator uses this when Config.SnapshotReplicationRadius is set, so
-- each player only gets entries for combatants actually near them instead of everyone in the game
function Net.FireSnapshotsTo(player: Player, entries: { CombatantSnapshotEntry }): ()
	Packets.Snapshots.sendTo({ Entries = entries :: any }, player)
end

function Net.OnSnapshots(handler: (entries: { CombatantSnapshotEntry }) -> ()): ()
	Packets.Snapshots.listen(function(data)
		handler(data.Entries :: any)
	end)
end

return Net
