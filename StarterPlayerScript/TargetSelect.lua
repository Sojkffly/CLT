local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local CombatRE = ReplicatedStorage:WaitForChild("CombatRE")

print("[TargetSelect] started", player.Name)

local PlayerScripts = player:WaitForChild("PlayerScripts")
local targetChanged = PlayerScripts:FindFirstChild("TargetChanged") or Instance.new("BindableEvent")
targetChanged.Name = "TargetChanged"
targetChanged.Parent = PlayerScripts

local MAX_LOCK_DISTANCE = 120

-- Highlight
local hl = Instance.new("Highlight")
hl.Name = "TargetHighlight"
hl.Enabled = false
hl.DepthMode = Enum.HighlightDepthMode.Occluded
hl.FillTransparency = 0.6
hl.OutlineTransparency = 0
hl.Parent = workspace

local currentTarget: Model? = nil

local function getRoot(model: Model?)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function isValidTarget(model: Instance?)
	if not model or not model:IsA("Model") then return false end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end

	local root = getRoot(model)
	if not root then return false end

	if player.Character and model == player.Character then return false end

	local myChar = player.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if myRoot then
		local dist = (root.Position - myRoot.Position).Magnitude
		if dist > MAX_LOCK_DISTANCE then
			return false
		end
	end

	return true
end

local PlayerScripts = player:WaitForChild("PlayerScripts")
local AttackCancel = PlayerScripts:FindFirstChild("AttackCancel") or Instance.new("BindableEvent")
AttackCancel.Name = "AttackCancel"
AttackCancel.Parent = PlayerScripts

local function clearTarget(reason: string?)
	print("[TargetSelect] clearTarget", reason or "")
	currentTarget = nil
	hl.Adornee = nil
	hl.Enabled = false
	targetChanged:Fire(nil)
	CombatRE:FireServer("ClearTarget")
	AttackCancel:Fire() -- ? cancela animação imediatamente
end

local function setTarget(model: Model, hitPart: Instance?)
	print("[TargetSelect] setTarget ->", model.Name, "hitPart=", hitPart and hitPart:GetFullName() or "nil")
	currentTarget = model
	hl.Adornee = model
	hl.Enabled = true
	targetChanged:Fire(model)
	CombatRE:FireServer("SetTarget", model)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local hitPart = mouse.Target
	if not hitPart then
		clearTarget("mouse.Target nil")
		return
	end

	-- tenta achar Model de forma mais robusta
	local model = hitPart:FindFirstAncestorOfClass("Model")
	if not model and hitPart.Parent and hitPart.Parent:IsA("Model") then
		model = hitPart.Parent
	end

	print("[TargetSelect] clicked part:", hitPart:GetFullName(), "model:", model and model.Name or "nil")

	if model and isValidTarget(model) then
		setTarget(model :: Model, hitPart)
	else
		clearTarget("invalid target")
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		clearTarget("esc")
	end
end)
