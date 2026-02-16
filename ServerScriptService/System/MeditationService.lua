local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeditationService = {}
MeditationService.__index = MeditationService

local SOURCE_ID = "Meditation" -- id fixo do modifier

function MeditationService.new(playerRegistry, statsService, modifierService, resolverService)
	local self = setmetatable({}, MeditationService)
	self._reg = playerRegistry
	self._stats = statsService
	self._mods = modifierService
	self._resolver = resolverService
	self._isMeditating = {} -- [player] = true/false
	return self
end

function MeditationService:Init()
	local re = ReplicatedStorage:FindFirstChild("MeditationRE")
	if not re then
		error("MeditationRE não encontrado em ReplicatedStorage")
	end
	print("MeditationService Init ok, RE:", re:GetFullName())

	re.OnServerEvent:Connect(function(player, action)
		print("Servidor recebeu:", player.Name, action)
		if action == "Start" then
			self:StartMeditation(player)
		elseif action == "Stop" then
			self:StopMeditation(player)
		elseif action == "Toggle" then
			if self._isMeditating[player] then
				self:StopMeditation(player)
			else
				self:StartMeditation(player)
			end
		end
	end)
end

function MeditationService:InitPlayer(player)
	self._reg:WaitReady(player, "StatsReady")
	self._isMeditating[player] = false
	player:SetAttribute("Meditating", false)
	self._reg:SetReady(player, "MeditationReady")
end

function MeditationService:IsMeditating(player)
	return self._isMeditating[player] == true
end

function MeditationService:StartMeditation(player)
	if not self._reg:IsReady(player, "StatsReady") then return end
	if self._isMeditating[player] then return end

	-- Exemplo de regra: não meditar com HP 0
	local hp = tonumber(player:GetAttribute("HP")) or 0
	if hp <= 0 then return end

	self._isMeditating[player] = true
	player:SetAttribute("Meditating", true)
	print("StartMeditation", player.Name)

	-- BÔNUS: +200% regen (ou seja, final = base * (1 + 2.0) = 3x)
	self._mods:SetMult(player, "QiRegen", SOURCE_ID, 2.0)

	-- (Opcional) bônus de MaxQi enquanto medita:
	-- self._mods:SetAdd(player, "MaxQi", SOURCE_ID, 25)

	self._resolver:Recompute(player)
end

function MeditationService:StopMeditation(player)
	if not self._isMeditating[player] then return end

	self._isMeditating[player] = false
	player:SetAttribute("Meditating", false)
	print("StopMeditation", player.Name)

	self._mods:ClearSource(player, SOURCE_ID)
	self._resolver:Recompute(player)
end

function MeditationService:Cleanup(player)
	-- garante que remove bônus
	if self._isMeditating[player] then
		self:StopMeditation(player)
	end
	self._isMeditating[player] = nil
end

return MeditationService
