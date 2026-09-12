--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementTypes = require(ReplicatedStorage.Shared.Combat.Movement.Types)
local MovementNet = require(ReplicatedStorage.Shared.Combat.Movement.Net)
local ConfigModule = require(ReplicatedStorage.Shared.Combat.Config)
local Signal = require(ReplicatedStorage.Shared.Hitbox.Signal)

type MovementResult = MovementTypes.MovementResult

local ClientMovement = {}

ClientMovement.OnMovementResult = Signal.new()

local cfg: ConfigModule.Config = ConfigModule
local sequenceCounter = 0

type PendingMove = {
	StartTime: number,
}

local pending: { [number]: PendingMove } = {}

function ClientMovement.RequestMove(skillId: string, to: CFrame, maxDistance: number): number
	local character = Players.LocalPlayer.Character
	if not character then
		return 0
	end

	local from = character:GetPivot()

	sequenceCounter += 1
	local sequenceId = sequenceCounter
	pending[sequenceId] = { StartTime = os.clock() }

	MovementNet.FireMovementRequest({
		SkillId = skillId,
		SequenceId = sequenceId,
		ClientTimestamp = workspace:GetServerTimeNow(),
		From = from,
		To = to,
		MaxDistance = maxDistance,
	})

	return sequenceId
end

local function onMovementResult(result: MovementResult): ()
	if not pending[result.SequenceId] then
		return 
	end
	pending[result.SequenceId] = nil
	ClientMovement.OnMovementResult:Fire(result.SequenceId, result)
end

function ClientMovement.Init(config: ConfigModule.Config?): ()
	if config then
		cfg = config
	end

	MovementNet.OnMovementResult(onMovementResult)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()

		for sequenceId, move in pending do
			if now - move.StartTime > cfg.MovementReconcileTimeoutSeconds then
				pending[sequenceId] = nil
				local character = Players.LocalPlayer.Character
				ClientMovement.OnMovementResult:Fire(sequenceId, {
					SequenceId = sequenceId,
					Accepted = false,
					AuthoritativeCFrame = if character then character:GetPivot() else CFrame.new(),
					ServerTimestamp = workspace:GetServerTimeNow(),
				})
			end
		end
	end)
end

return ClientMovement
