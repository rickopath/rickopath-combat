--!strict

-- CombatClient owns calling HitboxClient.Init() itself, same deal as the server entry point
local CombatClient = require(script.Combat.CombatClient)

CombatClient.Init()
