--!strict

-- Toggleable adornment visualization. 
-- Built unconditionally to support runtime toggling via SetEnabled.
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)
local Pool = require(script.Parent.Pool)

local enabled = Config.DebugDrawForceOn or (RunService:IsStudio() and Config.DebugDrawAllowInStudio)

local DebugDraw = {}

local adornFolder: Folder? = nil

local function getFolder(): Folder
	if adornFolder then
		return adornFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "HitboxDebugDraw"
	folder.Parent = workspace
	adornFolder = folder
	return folder
end

local function newBox(): BoxHandleAdornment
	local created = Instance.new("BoxHandleAdornment")
	created.Adornee = workspace.Terrain
	created.AlwaysOnTop = true
	created.ZIndex = 1
	created.Transparency = 0.4
	created.Parent = getFolder()
	return created
end

local function resetBox(box: BoxHandleAdornment): ()
	box.Visible = false
end

local function newCylinder(): CylinderHandleAdornment
	local created = Instance.new("CylinderHandleAdornment")
	created.Adornee = workspace.Terrain
	created.AlwaysOnTop = true
	created.ZIndex = 1
	created.Transparency = 0.4
	created.Parent = getFolder()
	return created
end

local function resetCylinder(cyl: CylinderHandleAdornment): ()
	cyl.Visible = false
end

-- Built unconditionally to support SetEnabled runtime toggling.
local boxPool = Pool.new(newBox, resetBox, 4, 2, 64)
local cylinderPool = Pool.new(newCylinder, resetCylinder, 4, 2, 64)

-- Instances are pooled to avoid frame churn.
function DebugDraw.Box(cf: CFrame, halfExtents: Vector3, color: Color3?, duration: number?): ()
	if not enabled then
		return
	end

	local pool = boxPool :: Types.PoolHandle<BoxHandleAdornment>
	local box = pool:Checkout()
	box.CFrame = cf
	box.Size = halfExtents * 2
	box.Color3 = color or Color3.new(1, 0, 0)
	box.Visible = true

	task.delay(duration or 0.25, function()
		pool:Return(box)
	end)
end

function DebugDraw.Capsule(cf: CFrame, radius: number, length: number, color: Color3?, duration: number?): ()
	if not enabled then
		return
	end

	local pool = cylinderPool :: Types.PoolHandle<CylinderHandleAdornment>
	local cyl = pool:Checkout()
	cyl.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	cyl.Height = length
	cyl.Radius = radius
	cyl.Color3 = color or Color3.new(1, 0.6, 0)
	cyl.Visible = true

	task.delay(duration or 0.25, function()
		pool:Return(cyl)
	end)
end

function DebugDraw.Ray(origin: Vector3, direction: Vector3, color: Color3?, duration: number?): ()
	if not enabled then
		return
	end

	local len = direction.Magnitude
	if len < 1e-4 then
		return
	end

	local pool = cylinderPool :: Types.PoolHandle<CylinderHandleAdornment>
	local cyl = pool:Checkout()
	cyl.CFrame = CFrame.lookAt(origin + direction * 0.5, origin + direction) * CFrame.Angles(0, math.rad(90), 0)
	cyl.Height = len
	cyl.Radius = 0.05
	cyl.Color3 = color or Color3.new(0, 1, 0)
	cyl.Visible = true

	task.delay(duration or 0.25, function()
		pool:Return(cyl)
	end)
end

-- Runtime toggle. Primarily used on the client.
function DebugDraw.SetEnabled(value: boolean): ()
	enabled = value
end

function DebugDraw.IsEnabled(): boolean
	return enabled
end

return DebugDraw
