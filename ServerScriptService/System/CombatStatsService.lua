local CombatStatsService = {}
CombatStatsService.__index = CombatStatsService

function CombatStatsService.new(playerRegistry, statsService)
	local self = setmetatable({}, CombatStatsService)
	self._reg = playerRegistry
	self._stats = statsService
	return self
end

function CombatStatsService:InitPlayer(player)
	-- Espera a etapa anterior
	self._reg:WaitReady(player, "StatsReady")

	-- Exemplo: bonus por Realm (placeholder)
	local s = self._stats:Get(player)
	if not s then return end

	local bonusHP = (s.Realm - 1) * 20
	self._stats:Set(player, "MaxHP", 100 + bonusHP)

	-- mantém HP dentro do MaxHP
	local maxHP = player:GetAttribute("MaxHP")
	local hp = player:GetAttribute("HP")
	if hp > maxHP then
		self._stats:Set(player, "HP", maxHP)
	end

	self._reg:SetReady(player, "CombatStatsReady")
end

return CombatStatsService
