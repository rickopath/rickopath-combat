--!strict

-- the ONLY file allowed to touch WorldRoot query methods, full stop. keeps the Region3 ban actually
-- enforceable instead of just a rule people forget - nothing else has any business calling
-- workspace:whatever() directly, route it through here
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)
local Observers = require(ReplicatedStorage.Packages.observers)

local SpatialQuery = {}

local function toOverlapParams(filter: Types.QueryFilter): OverlapParams
	local params = OverlapParams.new()
	if filter.ExcludeInstances then
		params.ExcludeInstances = filter.ExcludeInstances
	end
	if filter.IncludeInstances then
		params.IncludeInstances = filter.IncludeInstances
	end
	if filter.MaxParts then
		params.MaxParts = filter.MaxParts
	end
	params.RespectCanCollide = if filter.RespectCanCollide ~= nil then filter.RespectCanCollide else false
	if filter.CollisionGroup then
		params.CollisionGroup = filter.CollisionGroup
	end
	return params
end

local function toRaycastParams(filter: Types.QueryFilter): RaycastParams
	local params = RaycastParams.new()
	if filter.ExcludeInstances then
		params.ExcludeInstances = filter.ExcludeInstances
	end
	if filter.IncludeInstances then
		params.IncludeInstances = filter.IncludeInstances
	end
	params.RespectCanCollide = if filter.RespectCanCollide ~= nil then filter.RespectCanCollide else false
	if filter.CollisionGroup then
		params.CollisionGroup = filter.CollisionGroup
	end
	return params
end

SpatialQuery.ToOverlapParams = toOverlapParams
SpatialQuery.ToRaycastParams = toRaycastParams

function SpatialQuery.Box(cf: CFrame, size: Vector3, filter: Types.QueryFilter): { BasePart }
	return workspace:GetPartBoundsInBox(cf, size, toOverlapParams(filter))
end

function SpatialQuery.Radius(pos: Vector3, radius: number, filter: Types.QueryFilter): { BasePart }
	return workspace:GetPartBoundsInRadius(pos, radius, toOverlapParams(filter))
end

function SpatialQuery.PartsInPart(part: BasePart, filter: Types.QueryFilter): { BasePart }
	return workspace:GetPartsInPart(part, toOverlapParams(filter))
end

function SpatialQuery.Shapecast(proxy: BasePart, disp: Vector3, filter: Types.QueryFilter): RaycastResult?
	return workspace:Shapecast(proxy, disp, toRaycastParams(filter))
end

-- box sweep with zero proxy Parts - Blockcast takes CFrame+size directly, no Instance, no pool, no
-- parenting dance. strictly better than Shapecast(pooledProxyPart, ...) for boxes, don't go back
-- to the proxy-Part approach, that was worse in every way
function SpatialQuery.Blockcast(cf: CFrame, size: Vector3, disp: Vector3, filter: Types.QueryFilter): RaycastResult?
	return workspace:Blockcast(cf, size, disp, toRaycastParams(filter))
end

function SpatialQuery.Spherecast(origin: Vector3, radius: number, disp: Vector3, filter: Types.QueryFilter): RaycastResult?
	return workspace:Spherecast(origin, radius, disp, toRaycastParams(filter))
end

-- cached via observeTag instead of FindFirstChild every call - this runs on every live hit
-- resolution, that's not a place to be doing a tree walk. the cleanup callback firing after a
-- successful start means the folder got deleted mid-game, that's a real problem, not just "not found yet"
local aliveFolder: Instance? = nil

Observers.observeTag(Config.AliveFolderTag, function(instance: Instance)
	aliveFolder = instance
	return function()
		aliveFolder = nil
		warn("Hitbox: workspace.Alive folder disappeared mid-game, hit resolution will find no targets until it's restored")
	end
end, { workspace })

-- walks up to the nearest direct child of workspace.Alive - THAT's the trackable target. not tag
-- based on the target side, Alive folder membership is the one and only source of truth for
-- "can this get hit", don't add a second competing system for this
function SpatialQuery.ResolveHittableModel(part: BasePart): Model?
	local alive = aliveFolder
	if not alive then
		return nil
	end

	local inst: Instance? = part
	while inst do
		if inst.Parent == alive then
			break
		end
		inst = inst.Parent
	end

	if inst and inst:IsA("Model") then
		return inst
	end
	return nil
end

return SpatialQuery
