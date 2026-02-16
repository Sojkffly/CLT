local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local MoveRE = ReplicatedStorage:WaitForChild("MoveRE")
local CombatRE = ReplicatedStorage:WaitForChild("CombatRE")

-- Camera settings
local yaw = 0
local pitch = math.rad(55)      -- ângulo pra ver o boneco inteiro
local distance = 28            -- zoom inicial
local minDist, maxDist = 12, 60

local rotating = false
local lastMousePos

local function getCharRoot()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function raycastFromMouse(maxDistRay)
	local origin = camera.CFrame.Position
	local dir = (mouse.Hit.Position - origin).Unit * (maxDistRay or 1000)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}

	return workspace:Raycast(origin, dir, params)
end

-- Input: rotate camera with ALT + MouseMove
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- Right click move
		local hit = raycastFromMouse(1000)
		if hit then
			MoveRE:FireServer(hit.Position)
		end
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Left click target
		local hit = raycastFromMouse(1000)
		if hit and hit.Instance then
			-- tenta achar um model "alvo"
			local inst = hit.Instance
			local model = inst:FindFirstAncestorOfClass("Model")
			if model then
				CombatRE:FireServer("SetTarget", model)
			end
		end
	end

	if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
		rotating = true
		lastMousePos = UserInputService:GetMouseLocation()
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
		rotating = false
	end
end)

UserInputService.InputChanged:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		distance = math.clamp(distance - input.Position.Z * 2, minDist, maxDist)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local root = getCharRoot()
	if not root then return end

	if rotating then
		local pos = UserInputService:GetMouseLocation()
		local delta = pos - lastMousePos
		lastMousePos = pos
		yaw -= delta.X * 0.003
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local focus = root.Position
	local offsetDir = CFrame.fromAxisAngle(Vector3.yAxis, yaw) * CFrame.Angles(-pitch, 0, 0)
	local camPos = (CFrame.new(focus) * offsetDir * CFrame.new(0, 0, distance)).Position

	camera.CFrame = CFrame.new(camPos, focus)
end)
