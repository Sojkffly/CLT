local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakthroughService = {}
BreakthroughService.__index = BreakthroughService

function BreakthroughService.new(playerRegistry, statsService, resolverService)
	local self = setmetatable({}, BreakthroughService)
	self._reg = playerRegistry
	self._stats = statsService
	self._resolver = resolverService
	return self
end

local function clamp(n, a, b)
	if n < a then return a end
	if n > b then return b end
	return n
end

local function getMul(player, attrName, default)
	local v = player:GetAttribute(attrName)
	v = tonumber(v)
	if v == nil then return default end
	return v
end

local function chanceSuccess(player, realm, cultExp, toNext)
	local ratio = cultExp / toNext
	if ratio < 1 then return 0 end

	-- base pelo excedente
	local baseChance = 0.60
	local bonusOver = (ratio - 1) * 0.35
	local c = baseChance + bonusOver

	-- ? Awaken bonuses
	local rootBonus = getMul(player, "BreakthroughBonus", 0)                 -- ex: 0.02 (2%)
	local foundationBonus = getMul(player, "Foundation_BreakthroughBase", 0) -- ex: 0.01 (1%)

	c += rootBonus
	c += foundationBonus

	-- opcional: realm mais alto mais difícil
	-- c -= math.min(0.20, (realm-1) * 0.01)

	return clamp(c, 0, 0.95)
end

function BreakthroughService:Init()
	local re = ReplicatedStorage:FindFirstChild("BreakthroughRE")
	if not re then
		error("BreakthroughRE não encontrado em ReplicatedStorage")
	end

	re.OnServerEvent:Connect(function(player)
		self:TryBreakthrough(player)
	end)
end

function BreakthroughService:InitPlayer(player)
	self._reg:WaitReady(player, "StatsReady")
end

function BreakthroughService:TryBreakthrough(player)
	if not self._reg:IsReady(player, "StatsReady") then return end

	local s = self._stats:Get(player)
	if not s then return end

	local cultExp = tonumber(s.CultExp) or 0
	local toNext = tonumber(s.CultExpToNext) or 100
	local realm = math.max(1, tonumber(s.Realm) or 1)

	if cultExp < toNext then
		return
	end

	local c = chanceSuccess(player, realm, cultExp, toNext)
	local roll = math.random()

	if roll <= c then
		-- SUCESSO
		self._stats:Set(player, "Realm", realm + 1)

		local newExp = cultExp - toNext
		self._stats:Set(player, "CultExp", newExp)

		local newToNext = math.floor(toNext * 1.35 + 0.5)
		self._stats:Set(player, "CultExpToNext", newToNext)

		self._stats:Set(player, "CanBreakthrough", newExp >= newToNext)

		self._resolver:Recompute(player)
	else
		-- FALHA: perde parte do exp
		local lost = cultExp * 0.20
		local newExp = cultExp - lost
		self._stats:Set(player, "CultExp", newExp)
		self._stats:Set(player, "CanBreakthrough", newExp >= toNext)
	end
end

return BreakthroughService
