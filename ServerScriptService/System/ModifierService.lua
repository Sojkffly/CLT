local ModifierService = {}
ModifierService.__index = ModifierService

-- Estrutura:
-- self._mods[player][statKey] = {
--    add = { [sourceId]=number },
--    mult = { [sourceId]=number }, -- exemplo: 0.10 = +10%
-- }

function ModifierService.new(playerRegistry, statsService)
	local self = setmetatable({}, ModifierService)
	self._reg = playerRegistry
	self._stats = statsService
	self._mods = {} -- [player] = ...
	return self
end

function ModifierService:_ensure(player, statKey)
	self._mods[player] = self._mods[player] or {}
	self._mods[player][statKey] = self._mods[player][statKey] or { add = {}, mult = {} }
	return self._mods[player][statKey]
end

function ModifierService:SetAdd(player, statKey, sourceId, value)
	local bucket = self:_ensure(player, statKey)
	bucket.add[sourceId] = value
end

function ModifierService:SetMult(player, statKey, sourceId, value)
	local bucket = self:_ensure(player, statKey)
	bucket.mult[sourceId] = value
end

function ModifierService:Remove(player, statKey, sourceId)
	local s = self._mods[player]
	if not s or not s[statKey] then return end
	s[statKey].add[sourceId] = nil
	s[statKey].mult[sourceId] = nil
end

function ModifierService:ClearSource(player, sourceId)
	local s = self._mods[player]
	if not s then return end
	for _, bucket in pairs(s) do
		bucket.add[sourceId] = nil
		bucket.mult[sourceId] = nil
	end
end

function ModifierService:GetFinal(player, statKey, baseValue)
	local s = self._mods[player]
	if not s or not s[statKey] then
		return baseValue
	end

	local bucket = s[statKey]
	local addSum = 0
	for _, v in pairs(bucket.add) do
		addSum += v
	end

	local multSum = 0
	for _, v in pairs(bucket.mult) do
		multSum += v
	end

	-- fórmula simples e boa:
	-- final = (base + add) * (1 + mult)
	return (baseValue + addSum) * (1 + multSum)
end

function ModifierService:Cleanup(player)
	self._mods[player] = nil
end

return ModifierService
