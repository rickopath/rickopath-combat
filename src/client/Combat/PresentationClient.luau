--!strict

-- client side of the presentation service. PlayEffect is fully local, zero latency - used for the
-- caster's own instant predicted feedback AND internally by the replicated handler below, same
-- function either way. OnEffectRequested is the actual hook point where real vfx/anim content
-- attaches - same split as HitboxClient.OnHitFeedback, don't reinvent it a third time somewhere else
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Signal = require(ReplicatedStorage.Shared.Hitbox.Signal)
local PresentationTypes = require(ReplicatedStorage.Shared.Combat.Presentation.Types)
local PresentationNet = require(ReplicatedStorage.Shared.Combat.Presentation.Net)

type EffectId = PresentationTypes.EffectId
type PresentParams = PresentationTypes.PresentParams
type WireParams = PresentationNet.WireParams

local PresentationClient = {}

-- (effectId: EffectId, params: PresentParams)
PresentationClient.OnEffectRequested = Signal.new()

function PresentationClient.PlayEffect(effectId: EffectId, params: PresentParams): ()
	PresentationClient.OnEffectRequested:Fire(effectId, params)
end

local function fromWireParams(params: WireParams): PresentParams
	return {
		CFrame = params.CFrame,
		Attachment = nil, -- resolved locally by effect id convention, never serialized
		Target = if params.Target and params.Target:IsA("Model") then params.Target else nil,
		Scale = params.Scale,
		Color = nil, -- resolved locally by effect id convention, bytenet has no public color3 dataType
		EmitCount = params.EmitCount,
		AttachToPartName = params.AttachToPartName,
	}
end

local function onPresent(effectId: EffectId, params: WireParams): ()
	PresentationClient.PlayEffect(effectId, fromWireParams(params))
end

function PresentationClient.Init(): ()
	PresentationNet.OnPresent(onPresent)
end

-- fires :Emit on the instance itself (if it's a ParticleEmitter) and on every ParticleEmitter
-- descendant - a template that's a Part/Model with three emitters bolted on all burst together,
-- you don't have to make the template itself a bare emitter for this to work. precedence, highest
-- first: the CALLER's params.EmitCount (set at PlayEffect call time, beats everything) -> that
-- particular emitter's own "EmitCount" attribute -> the template ROOT's "EmitCount" attribute -> 20.
-- the caller override exists specifically so the same template can burst differently per cast
-- (scale with a crit, a charge level, whatever) without needing a second template just for that
local function emitAll(root: Instance, callerEmitCount: number?): ()
	local function resolveCount(emitter: Instance): number
		return callerEmitCount or emitter:GetAttribute("EmitCount") or root:GetAttribute("EmitCount") or 20
	end
	if root:IsA("ParticleEmitter") then
		root:Emit(resolveCount(root))
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(resolveCount(descendant))
		end
	end
end

-- true for anything that ONLY renders when parented under a BasePart - Attachment included, since
-- an Attachment floating under nothing is just as inert as a ParticleEmitter floating under nothing
local function isAttachmentShaped(instance: Instance): boolean
	return instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") or instance:IsA("Attachment")
end

-- finds the part to ride along with on Target. precedence, highest first: the CALLER's
-- params.AttachToPartName (set at PlayEffect call time - "Head" for THIS cast's headshot spark,
-- say) -> the template's own "AttachToPart" attribute (a per-template Studio-set default) ->
-- Target.PrimaryPart -> a part literally named "HumanoidRootPart"
local function findAttachPart(template: Instance, target: Model?, callerPartName: string?): BasePart?
	if not target then
		return nil
	end
	local overrideName = callerPartName or template:GetAttribute("AttachToPart")
	if overrideName then
		local named = target:FindFirstChild(overrideName :: string)
		if named and named:IsA("BasePart") then
			return named
		end
	end
	if target.PrimaryPart then
		return target.PrimaryPart
	end
	local rootPart = target:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

local function spawnVfx(template: Instance, params: PresentParams): ()
	local vfx = template:Clone()
	-- "Lifetime" attribute overrides the default 3s cleanup delay - bump it for anything with a
	-- particle Lifetime longer than that, or it gets Destroy()'d mid-burst
	local lifetime = template:GetAttribute("Lifetime") or 3

	-- params.Attachment: the caller already has a specific BasePart/Attachment reference in hand
	-- (their own weapon's tip, say) and wants the VFX parented there directly - this SKIPS Target
	-- lookup entirely, it's the most specific thing a caller can say. local/predicted calls only,
	-- this field never crosses the network (see Presentation/Types.luau) - for a server-broadcast
	-- effect, use params.AttachToPartName instead, which does cross the network as a part NAME
	if params.Attachment then
		vfx.Parent = params.Attachment
		emitAll(vfx, params.EmitCount)
		Debris:AddItem(vfx, lifetime)
		return
	end

	-- RideTarget forces attach-to-target-part behavior even for a Model/Part template that would
	-- otherwise stand alone in workspace via PivotTo - set it true on the template in Studio if you
	-- want a Part-shaped effect to travel with the character instead of staying where it was cast
	local shouldRideTarget = isAttachmentShaped(vfx) or template:GetAttribute("RideTarget") == true

	if shouldRideTarget then
		local attachPart = findAttachPart(template, params.Target, params.AttachToPartName)
		if not attachPart then
			vfx:Destroy() -- nowhere sane to attach this - no Target, or Target has no matching part
			return
		end
		vfx.Parent = attachPart
	elseif vfx:IsA("PVInstance") then
		-- Model/BasePart template, standing alone at a fixed world position
		if params.Target then
			vfx:PivotTo(params.Target:GetPivot())
		elseif params.CFrame then
			vfx:PivotTo(params.CFrame)
		end
		vfx.Parent = workspace
	else
		-- anything else (a plain Folder, whatever) - best effort
		vfx.Parent = workspace
	end

	emitAll(vfx, params.EmitCount)
	Debris:AddItem(vfx, lifetime)
end

-- opt-in default subscriber - this is the SAME boilerplate every game hand-writes (clone a VFX
-- template by effectId, play a Sound by effectId), so it's here once instead of copy-pasted into
-- every project's own client init. NOT called by Init() automatically - a game with fully custom
-- presentation just never calls this and connects its own OnEffectRequested listener instead,
-- same as always. calling this AND your own listener both work fine, they're independent subscribers
--
-- supported VFX template shapes, all driven by what the template IS plus its attributes, no code
-- change needed per effect:
--   Model/BasePart          -> positioned via PivotTo (Target's pivot, else CFrame), stands alone
--                              in workspace. set RideTarget=true (attribute) to attach it to the
--                              target's part instead, same as the shapes below
--   ParticleEmitter/Trail/Beam/Attachment -> always attaches to the target's part (these render
--                              nothing standing alone in workspace, there's no "world position" mode)
--   anything with ParticleEmitter descendants -> every one of them gets :Emit()'d, whether the
--                              template itself is a bare emitter or a whole rig of them
-- attributes read off the TEMPLATE (set in Studio, tune-once-per-effect): AttachToPart (string,
-- part name on Target, default PrimaryPart/HumanoidRootPart), RideTarget (bool), Lifetime (number,
-- seconds before cleanup, default 3), EmitCount (number, burst size, default 20, can also be set
-- per individual ParticleEmitter descendant to override the template-wide default for just that one)
--
-- params overrides on PresentParams (set per CALL, tune-once-per-cast, crosses the network so a
-- server-fired effect can use these too): EmitCount, AttachToPartName - both beat the matching
-- attribute above when given. params.Attachment (local/predicted calls only, never networked) skips
-- Target lookup entirely and parents straight onto whatever BasePart/Attachment you hand it
function PresentationClient.UseDefaultPresentation(options: { VFXFolder: Instance?, SoundFolder: Instance? }?): ()
	local vfxFolder = (options and options.VFXFolder) or ReplicatedStorage:FindFirstChild("VFX")
	local soundFolder: Instance = (options and options.SoundFolder) or SoundService

	PresentationClient.OnEffectRequested:Connect(function(effectId: EffectId, params: PresentParams)
		local template = vfxFolder and vfxFolder:FindFirstChild(effectId)
		if template then
			spawnVfx(template, params)
		end

		local sound = soundFolder:FindFirstChild(effectId)
		if sound and sound:IsA("Sound") then
			sound:Play() -- for positional audio, clone it onto a part instead - this is the simple default
		end
	end)
end

return PresentationClient
