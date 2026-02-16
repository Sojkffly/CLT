local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TargetService = {}
TargetService.__index = TargetService

function TargetService.new(playerRegistry)
	local self = setmetatable({}, TargetService)
	self._reg = playerRegistry
	self._target = {} -- [player] = Model
	return self
end

local function getHumanoid(model)
	return model and model:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

function TargetService:Init()
	local re = ReplicatedStorage:WaitForChild("CombatRE")

	re.OnServerEvent:Connect(function(player, action, targetModel)
		if action == "ClearTarget" then
			self._target[player] = nil
			return
		end

		if action ~= "SetTarget" then return end
		if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end

		-- não pode selecionar a si mesmo
		if player.Character and targetModel == player.Character then return end

		local hum = getHumanoid(targetModel)
		if not hum or hum.Health <= 0 then return end

		-- valida distância máxima pra “lock” (anti exploit)
		local pr = getRoot(player.Character)
		local tr = getRoot(targetModel)
		if not pr or not tr then return end

		local dist = (tr.Position - pr.Position).Magnitude
		if dist > 120 then
			return -- longe demais pra selecionar
		end

		self._target[player] = targetModel
	end)
end

function TargetService:GetTarget(player)
	return self._target[player]
end

function TargetService:Cleanup(player)
	self._target[player] = nil
end

return TargetService
