--!strict

export type MovementRequest = {
	SkillId: string,
	SequenceId: number,
	ClientTimestamp: number,
	From: CFrame,
	To: CFrame,
	MaxDistance: number,
}

export type MovementResult = {
	SequenceId: number,
	Accepted: boolean,
	AuthoritativeCFrame: CFrame,
	ServerTimestamp: number,
}

return {}
