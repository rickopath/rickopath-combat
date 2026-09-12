--!strict

-- pure dev tool, zero styling opinion (plain ScreenGui/TextLabel) - same "strip this before
-- shipping" bucket InputBindings.luau's own header already puts itself in. F9 toggles a live
-- readout of the LOCAL player's own Combatant (resources, status effect countdowns, per-skill
-- cooldowns, team/invulnerable, unconfirmed predicted attacks); F10 toggles DebugDraw's runtime
-- hitbox/projectile visualization independently - two separate keys instead of one key cycling
-- through modes, so either can be left on/off without caring about the other's state
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientCombatant = require(script.Parent.ClientCombatant)
local ClientSkills = require(script.Parent.ClientSkills)
local HitboxClient = require(script.Parent.Parent.Hitbox.HitboxClient)
local DebugDraw = require(ReplicatedStorage.Shared.Hitbox.DebugDraw)

type ClientCombatantInstance = ClientCombatant.ClientCombatant

-- refreshed on a throttled Heartbeat, not every frame - this is a text readout a human is reading,
-- not something that needs to be frame-perfect
local REFRESH_INTERVAL_SECONDS = 0.2

local DebugOverlay = {}

local screenGui: ScreenGui? = nil
local label: TextLabel? = nil
local visible = false

local function buildUi(): (ScreenGui, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatDebugOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false

	local text = Instance.new("TextLabel")
	text.Name = "Readout"
	text.BackgroundColor3 = Color3.new(0, 0, 0)
	text.BackgroundTransparency = 0.35
	text.BorderSizePixel = 0
	text.Position = UDim2.new(0, 8, 0, 8)
	text.Size = UDim2.new(0, 360, 0, 420)
	text.Font = Enum.Font.Code
	text.TextSize = 14
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextWrapped = true
	text.Text = ""
	text.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, text
end

local function formatResources(combatant: ClientCombatantInstance): string
	local lines = {}
	for id, resource in combatant:GetAllResources() do
		table.insert(lines, string.format("    %s: %.0f / %.0f", id, resource.Current, resource.Max))
	end
	if #lines == 0 then
		return "    (none)"
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function formatStatusEffects(combatant: ClientCombatantInstance): string
	local lines = {}
	local now = workspace:GetServerTimeNow()
	for id, effect in combatant:GetStatusEffects() do
		local remaining = math.max(0, effect.ExpiresAt - now)
		table.insert(lines, string.format("    %s x%d (%.1fs left)", id, effect.Stacks, remaining))
	end
	if #lines == 0 then
		return "    (none)"
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function formatCooldowns(): string
	local lines = {}
	for id, skill in ClientSkills.GetAll() do
		if skill:IsOnCooldown() then
			table.insert(lines, string.format("    %s: %.1fs", id, skill:CooldownRemaining()))
		else
			table.insert(lines, string.format("    %s: ready", id))
		end
	end
	if #lines == 0 then
		return "    (none equipped)"
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function refresh(): ()
	local activeLabel = label
	if not visible or not activeLabel then
		return
	end

	local character = Players.LocalPlayer.Character
	if not character then
		activeLabel.Text = "F9 Debug Overlay\n\n(no character)"
		return
	end

	local combatant = ClientCombatant.Get(character)
	if not combatant then
		activeLabel.Text = "F9 Debug Overlay\n\n(no Combatant snapshot received yet)"
		return
	end

	activeLabel.Text = table.concat({
		string.format("F9 Debug Overlay   (F10 hitbox draw: %s)", if DebugDraw.IsEnabled() then "ON" else "OFF"),
		"",
		string.format("Team: %s   Invulnerable: %s", combatant.Team or "(none)", tostring(combatant.IsInvulnerable)),
		"",
		"Resources:",
		formatResources(combatant),
		"",
		"Status Effects:",
		formatStatusEffects(combatant),
		"",
		"Skill Cooldowns:",
		formatCooldowns(),
		"",
		string.format("Pending attacks (unconfirmed): %d", HitboxClient.GetPendingCount()),
	}, "\n")
end

local function setVisible(value: boolean): ()
	visible = value
	if screenGui then
		screenGui.Enabled = value
	end
	if value then
		-- don't wait up to REFRESH_INTERVAL_SECONDS to show real data the first time it opens
		refresh()
	end
end

function DebugOverlay.Init(): ()
	local gui, text = buildUi()
	screenGui = gui
	label = text

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F9 then
			setVisible(not visible)
		elseif input.KeyCode == Enum.KeyCode.F10 then
			DebugDraw.SetEnabled(not DebugDraw.IsEnabled())
		end
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum >= REFRESH_INTERVAL_SECONDS then
			accum = 0
			refresh()
		end
	end)
end

return DebugOverlay
