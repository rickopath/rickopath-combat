--!strict
-- Movement skill example.
-- 
-- The server validates the final position.
-- The client is responsible for the visual interpolation.
-- Snap to the server's authoritative CFrame when the movement result is returned.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SkillModule = require(ReplicatedStorage.Shared.Combat.Skill)
local SkillRegistry = require(ReplicatedStorage.Shared.Combat.SkillRegistry)

type SkillContext = SkillModule.SkillContext

local ID = "Dash"
local DASH_DISTANCE = 16
-- content-owned tuning, not a framework config knob - ClientMovement has no opinion on how long a
-- traversal should take, this number belongs entirely to this file
local TRAVEL_DURATION_SECONDS = 0.15

local Dash = SkillModule.extend("Dash")

-- Luau strict-mode class assignment.
;(Dash :: any).Activate = function(self: SkillModule.Skill): boolean
	local movement = self.Context.Movement
	if movement then -- client only
		local character = self.Context.Owner
		local from = character:GetPivot()
		local to = from + from.LookVector * DASH_DISTANCE

		-- predicted traversal - purely local, purely cosmetic until the server confirms it. a
		-- fresh RBXScriptConnection per activation is intentional and cheap here, same posture
		-- DebugDraw's task.delay-per-shape takes: this is a several-hundred-ms visual effect, not a
		-- hot path worth pooling
		local startTime = os.clock()
		local tweenConn: RBXScriptConnection
		tweenConn = RunService.Heartbeat:Connect(function()
			local alpha = math.clamp((os.clock() - startTime) / TRAVEL_DURATION_SECONDS, 0, 1)
			character:PivotTo(from:Lerp(to, alpha))
			if alpha >= 1 then
				tweenConn:Disconnect()
			end
		end)

		local sequenceId = movement.RequestMove(self.Id, to, DASH_DISTANCE * 1.5)

		-- correction is this skill's job too now - OnMovementResult fires for every in-flight
		-- movement request from any skill, filter by sequenceId to find the one that's ours
		local resultConn: RBXScriptConnection
		resultConn = movement.OnMovementResult:Connect(function(resolvedId: number, result: any)
			if resolvedId ~= sequenceId then
				return
			end
			resultConn:Disconnect()
			if not result.Accepted then
				if tweenConn.Connected then
					tweenConn:Disconnect()
				end
				character:PivotTo(result.AuthoritativeCFrame)
			end
		end)
	end
	return true
end

SkillRegistry.Register(ID, function(context: SkillContext): SkillModule.Skill
	return Dash.new({
		Id = ID,
		DisplayName = "Dash",
		Cooldown = 3,
		Costs = { { ResourceId = "Stamina", Amount = 15 } },
	}, context)
end)

return Dash
