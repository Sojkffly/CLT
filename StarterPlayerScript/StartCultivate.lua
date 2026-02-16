local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local re = ReplicatedStorage:WaitForChild("MeditationRE")

print("Client Meditation script rodando")

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end

	-- Só teclado
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	print("Tecla:", input.KeyCode)

	if input.KeyCode == Enum.KeyCode.M then
		print("Apertou M")
		re:FireServer("Toggle")
	end
end)
