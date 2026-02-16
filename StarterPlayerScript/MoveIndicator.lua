local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local MoveRE = ReplicatedStorage:WaitForChild("MoveRE")

-- Config
local ARRIVE_DISTANCE = 3.5
local BASE_HEIGHT = 2.0        -- altura base acima do chão
local BOB_SPEED = 2.5
local BOB_AMPLITUDE = 0.8      -- sobe/desce
local PULSE_SPEED = 4.0

-- Helpers
local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function raycastFromMouse(maxDistRay)
	local origin = camera.CFrame.Position
	local dir = (mouse.Hit.Position - origin).Unit * (maxDistRay or 1000)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	return workspace:Raycast(origin, dir, params)
end

-- Visual
local folder = Instance.new("Folder")
folder.Name = "MoveArrowVisual"
folder.Parent = workspace

local anchor = Instance.new("Part")
anchor.Name = "MoveArrowAnchor"
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanTouch = false
anchor.CanQuery = false
anchor.Transparency = 1
anchor.Size = Vector3.new(0.2, 0.2, 0.2)
anchor.Parent = folder

local gui = Instance.new("BillboardGui")
gui.Name = "MoveArrowGui"
gui.AlwaysOnTop = true
gui.LightInfluence = 0
gui.Size = UDim2.fromOffset(60, 60)
gui.StudsOffset = Vector3.new(0, 0, 0)
gui.Adornee = anchor
gui.Parent = anchor

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Size = UDim2.fromScale(1, 1)
label.Text = "?"
label.TextScaled = true
label.Font = Enum.Font.GothamBlack
label.TextStrokeTransparency = 0.2
label.TextStrokeColor3 = Color3.new(0, 0, 0)
label.TextColor3 = Color3.new(1, 1, 1)
label.Parent = gui

local goalPos = nil
local visible = false

local function setVisible(on)
	visible = on
	folder.Parent = on and workspace or nil
end
setVisible(false)

local function setGoal(pos)
	goalPos = pos
	setVisible(true)

	-- coloca IMEDIATAMENTE no novo lugar (remove o flash)
	anchor.Position = pos + Vector3.new(0, BASE_HEIGHT, 0)
	label.TextTransparency = 0.05
	gui.Size = UDim2.fromOffset(60, 60)

	MoveRE:FireServer(pos)
end

-- Input
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

	local hit = raycastFromMouse(1000)
	if not hit then return end

	setGoal(hit.Position)
end)

-- Update
RunService.RenderStepped:Connect(function()
	if not visible or not goalPos then return end

	local root = getRoot()
	if not root then return end

	-- some ao chegar
	local flatRoot = Vector3.new(root.Position.X, goalPos.Y, root.Position.Z)
	if (goalPos - flatRoot).Magnitude <= ARRIVE_DISTANCE then
		goalPos = nil
		setVisible(false)
		return
	end

	local t = os.clock()
	local bob = math.sin(t * BOB_SPEED) * BOB_AMPLITUDE
	anchor.Position = goalPos + Vector3.new(0, BASE_HEIGHT + bob, 0)

	-- pulso só no texto (sem quadrado)
	local pulse = (math.sin(t * PULSE_SPEED) + 1) * 0.5
	label.TextTransparency = 0.05 + 0.25 * pulse
	gui.Size = UDim2.fromOffset(55 + 10 * pulse, 55 + 10 * pulse)
end)
