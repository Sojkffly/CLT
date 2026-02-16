local StatsService = {}
StatsService.__index = StatsService

local PUBLIC_KEYS = {
	"Level","Realm","Exp","Gold",

	"HP","MaxHP","ATK","DEF","Crit","Dodge","Precision", "MoveSpeed",

	-- Cultivo
	"Qi","MaxQi","QiRegen",
	"CultExp","CultExpToNext","CanBreakthrough",
	-- Artefato (range)
	"ArtifactDamage","ArtifactAttackInterval","ArtifactProjectileSpeed",
	"ArtifactKnockback","ArtifactTrailSize","ArtifactCurvature","ArtifactRange",

	-- Arma (melee)
	"WeaponDamage","WeaponAttackInterval","WeaponRange","WeaponKnockback",
}

local function clamp(n, minv, maxv)
	if n < minv then return minv end
	if n > maxv then return maxv end
	return n
end

function StatsService.new(playerRegistry, dataService)
	local self = setmetatable({}, StatsService)
	self._reg = playerRegistry
	self._data = dataService
	self._stats = {} -- [player] = stats table (referência do data)
	return self
end

function StatsService:GetDefaults()
	return {
		Level = 1,
		Realm = 1,
		Exp = 0,
		Gold = 0,

		MaxHP = 100,
		HP = 100,
		ATK = 10,
		DEF = 5,
		Crit = 0.05,
		Dodge = 0.05,
		Precision = 0.90, -- 90% base (mortal acerta quase sempre)
		MoveSpeed = 16,

		-- Cultivo
		MaxQi = 100,
		Qi = 0,
		QiRegen = 1,           -- por segundo (ajustamos depois)
		CultExp = 0,
		CultExpToNext = 100,   -- custo pro próximo realm/nível de cultivo
		CanBreakthrough = false,
		-- Artefato (range) defaults (sem artefato equipado = fraco ou 0)
		ArtifactDamage = 5,
		ArtifactAttackInterval = 1.2,
		ArtifactProjectileSpeed = 60,
		ArtifactKnockback = 5,
		ArtifactTrailSize = 1,
		ArtifactCurvature = 0.0,
		ArtifactRange = 40,

		-- Arma (melee) defaults
		WeaponDamage = 8,
		WeaponAttackInterval = 1.0,
		WeaponRange = 4,
		WeaponKnockback = 8,
		
		Inventory = {
			Bag = {
				items = {},   -- itens únicos (arma/artefato/talismã etc.)
				stacks = {},  -- recursos gerais
			},
			Pouch = {
				SpiritStones = 0,
				Capacity = 999999, -- opcional
			},
		},

		Equipped = {
			Shirt = nil,
			Pants = nil,
			Mantle = nil,
			Weapon = nil,
			Accessory = nil,
			Talismans = { nil, nil, nil, nil, nil, nil },
			Artifacts = { nil, nil, nil, nil, nil, nil },
		},
		
		Awakening = {
			BodyApt = nil,
			MindApt = nil,
			SpiritApt = nil,

			HasDantian = false,
			DantianTier = 0,
			Element = "None",
			Path = "Mortal",
			Prep = 0,
		},
	}
end

function StatsService:InitPlayer(player)
	local defaults = self:GetDefaults()

	-- Carrega do DataStore (pode yieldar)
	local data = self._data:Load(player.UserId, defaults)

	-- Segurança/normalização
	data.MaxHP = math.max(1, tonumber(data.MaxHP) or defaults.MaxHP)
	data.HP = clamp(tonumber(data.HP) or data.MaxHP, 0, data.MaxHP)
	data.Level = math.max(1, tonumber(data.Level) or defaults.Level)
	data.Realm = math.max(1, tonumber(data.Realm) or defaults.Realm)
	data.MaxQi = math.max(1, tonumber(data.MaxQi) or defaults.MaxQi)
	data.Qi = math.clamp(tonumber(data.Qi) or 0, 0, data.MaxQi)
	data.QiRegen = math.max(0, tonumber(data.QiRegen) or defaults.QiRegen)

	data.CultExp = math.max(0, tonumber(data.CultExp) or 0)
	data.CultExpToNext = math.max(1, tonumber(data.CultExpToNext) or defaults.CultExpToNext)
	data.CanBreakthrough = (data.CanBreakthrough == true)
	
	data.Inventory = data.Inventory or defaults.Inventory
	data.Inventory.Bag = data.Inventory.Bag or defaults.Inventory.Bag
	data.Inventory.Bag.items = data.Inventory.Bag.items or {}
	data.Inventory.Bag.stacks = data.Inventory.Bag.stacks or {}
	data.Inventory.Pouch = data.Inventory.Pouch or defaults.Inventory.Pouch
	data.Inventory.Pouch.SpiritStones = math.max(0, tonumber(data.Inventory.Pouch.SpiritStones) or 0)
	data.Inventory.Pouch.Capacity = math.max(0, tonumber(data.Inventory.Pouch.Capacity) or defaults.Inventory.Pouch.Capacity)

	data.Equipped = data.Equipped or defaults.Equipped
	data.Equipped.Talismans = data.Equipped.Talismans or {nil,nil,nil,nil,nil,nil}
	data.Equipped.Artifacts = data.Equipped.Artifacts or {nil,nil,nil,nil,nil,nil}
	
	data.WeaponAttackInterval = math.max(0.1, tonumber(data.WeaponAttackInterval) or defaults.WeaponAttackInterval)
	data.ArtifactAttackInterval = math.max(0.1, tonumber(data.ArtifactAttackInterval) or defaults.ArtifactAttackInterval)


	self._stats[player] = data

	-- Replica
	for _, k in ipairs(PUBLIC_KEYS) do
		player:SetAttribute(k, data[k])
	end

	self._reg:SetReady(player, "StatsReady")
	return data
end

function StatsService:Get(player)
	return self._stats[player]
end

function StatsService:Set(player, key, value)
	local s = self._stats[player]
	if not s then return end

	-- Clamp de estado atual
	if key == "Qi" then
		local maxQi = tonumber(player:GetAttribute("MaxQi")) or tonumber(s.MaxQi) or 100
		value = math.clamp(tonumber(value) or 0, 0, maxQi)
	elseif key == "HP" then
		local maxHP = tonumber(player:GetAttribute("MaxHP")) or tonumber(s.MaxHP) or 100
		value = math.clamp(tonumber(value) or 0, 0, maxHP)
	end

	s[key] = value
	player:SetAttribute(key, value)

	self._data:MarkDirty(player.UserId)
end

function StatsService:MarkDirty(player)
	self._data:MarkDirty(player.UserId)
end

function StatsService:Add(player, key, delta)
	local s = self._stats[player]
	if not s then return end
	local v = (tonumber(s[key]) or 0) + delta
	self:Set(player, key, v)
end

function StatsService:Save(player)
	return self._data:Save(player.UserId)
end

function StatsService:Cleanup(player)
	self._stats[player] = nil
	self._data:Cleanup(player.UserId)
end

return StatsService
