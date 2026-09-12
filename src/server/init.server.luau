--!strict

-- CombatServer owns calling HitboxServer.Init() itself at the right point - don't add a second
-- Init() call here for anything under Combat/Hitbox, that's how you get a double-inited mess
local CombatServer = require(script.Combat.CombatServer)

CombatServer.Init()
