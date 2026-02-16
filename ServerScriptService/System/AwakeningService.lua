--// ServerScriptService/Services/AwakeningService.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local AwakenStore = DataStoreService:GetDataStore("AwakenV2")

local AwakeningService = {}
AwakeningService.__index = AwakeningService

function AwakeningService.new(reg, data, mods, resolver)
	local self = setmetatable({}, AwakeningService)
	self._reg = reg
	self._data = data
	self._mods = mods
	self._resolver = resolver

	self._stateByPlayer = {}
	self._lastTrainAt = {}
	self._lastSaveAt = {}

	self._rng = Random.new()

	return self
end

-- =========================
-- Remote
-- =========================
local function ensureRE(name)
	local re = ReplicatedStorage:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = ReplicatedStorage
	end
	return re
end

local AwakenRE = ensureRE("AwakenRE")

-- =========================
-- CONFIG
-- =========================
local SAVE_COOLDOWN = 8.0
local TRAIN_COOLDOWN = 0.12

local MIN_POTENTIAL_TO_AWAKEN = 250

local MIN_TRAIN_REQUIREMENTS = {
	Martial = 25,
	Strength = 25,
	Endurance = 20,
	Breathing = 30,
	Flexibility = 10,
}

local SCORE_K_SPIRIT = 600
local SCORE_K_BODY   = 600

local TRAIN_TYPES = {
	Martial = true,
	Strength = true,
	Endurance = true,
	Breathing = true,
	Flexibility = true,
}

local WEIGHTS_SPIRIT = {
	Breathing   = 1.20,
	Endurance   = 0.40,
	Flexibility = 0.20,
	Strength    = 0.10,
	Martial     = 0.10,
}

local WEIGHTS_BODY = {
	Strength    = 1.00,
	Martial     = 0.80,
	Endurance   = 0.60,
	Flexibility = 0.25,
	Breathing   = 0.10,
}

local ROOT_ELEMENTS = {"Metal","Wood","Water","Fire","Earth"}

local ROOT_TIERS = {
	{ name = "Common",    base = 0.60, qiGainMul = {1.00,1.10}, breakthrough = {0.00,0.01} },
	{ name = "Uncommon",  base = 0.25, qiGainMul = {1.10,1.20}, breakthrough = {0.01,0.02} },
	{ name = "Rare",      base = 0.10, qiGainMul = {1.20,1.35}, breakthrough = {0.02,0.04} },
	{ name = "Epic",      base = 0.04, qiGainMul = {1.35,1.55}, breakthrough = {0.04,0.06} },
	{ name = "Legendary", base = 0.01, qiGainMul = {1.55,1.85}, breakthrough = {0.06,0.10} },
}

local BODY_TIERS = {
	{ name = "Common",    base = 0.60, hpMul = {1.00,1.10}, stamMul = {1.00,1.10} },
	{ name = "Uncommon",  base = 0.25, hpMul = {1.10,1.20}, stamMul = {1.10,1.20} },
	{ name = "Rare",      base = 0.10, hpMul = {1.20,1.35}, stamMul = {1.20,1.35} },
	{ name = "Epic",      base = 0.04, hpMul = {1.35,1.55}, stamMul = {1.35,1.55} },
	{ name = "Legendary", base = 0.01, hpMul = {1.55,1.85}, stamMul = {1.55,1.85} },
}

local BODY_TYPES = {
	{
		name = "Iron Body",
		weights = {Strength=1.2, Martial=0.7, Endurance=0.2, Flexibility=0.1, Breathing=0.0},
		bonuses = {DefenseMul = {1.05, 1.18}, StaggerRes = {0.02, 0.08}},
	},
	{
		name = "Swift Body",
		weights = {Endurance=1.2, Flexibility=0.6, Martial=0.3, Strength=0.1, Breathing=0.0},
		bonuses = {MoveSpeedMul = {1.04, 1.16}, DodgeBonus = {0.01, 0.06}},
	},
	{
		name = "Titan Body",
		weights = {Strength=1.1, Endurance=0.8, Martial=0.4, Flexibility=0.1, Breathing=0.0},
		bonuses = {HPMulExtra = {1.03, 1.12}, CarryMul = {1.05, 1.20}},
	},
	{
		name = "Flow Body",
		weights = {Breathing=1.0, Flexibility=0.7, Endurance=0.3, Strength=0.0, Martial=0.0},
		bonuses = {QiControl = {0.03, 0.12}, BreakthroughExtra = {0.002, 0.010}},
	},
	{
		name = "Feral Body",
		weights = {Martial=1.1, Endurance=0.6, Strength=0.5, Flexibility=0.1, Breathing=0.0},
		bonuses = {CritBonus = {0.01, 0.06}, AttackSpeedMul = {1.02, 1.10}},
	},
}

-- =========================
-- helpers
-- =========================
local function clamp01(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end

local function scoreToRate(score, k)
	return 1 - math.exp(-(score / k))
end

local function shallowCopy(t)
	local o = {}
	for k,v in pairs(t) do o[k] = v end
	return o
end

local function ensureTrainTable(st)
	st.Train = st.Train or {}
	for k in pairs(TRAIN_TYPES) do
		st.Train[k] = tonumber(st.Train[k]) or 0
	end
end

local function calcPotential(st)
	ensureTrainTable(st)
	local t = st.Train
	local p =
		t.Martial * 0.9 +
		t.Strength * 1.0 +
		t.Endurance * 0.8 +
		t.Breathing * 1.1 +
		t.Flexibility * 0.5
	return math.floor(p + 0.5)
end

local function calcSpiritScore(st)
	ensureTrainTable(st)
	local score = 0
	for k,w in pairs(WEIGHTS_SPIRIT) do
		score += (tonumber(st.Train[k]) or 0) * w
	end
	return score
end

local function calcBodyScore(st)
	ensureTrainTable(st)
	local score = 0
	for k,w in pairs(WEIGHTS_BODY) do
		score += (tonumber(st.Train[k]) or 0) * w
	end
	return score
end

local function lerp(a,b,t) return a + (b-a)*t end

function AwakeningService:_randRange(minv, maxv)
	return lerp(minv, maxv, self._rng:NextNumber())
end

function AwakeningService:_pickWeightedTier(tiers, rate)
	local weights = {}
	local total = 0

	for i, tier in ipairs(tiers) do
		local base = tier.base
		local rarityFactor = (i-1) / (#tiers-1)

		local boostRare = 1 + rate * (2.2 * rarityFactor)
		local nerfCommon = 1 - rate * (0.7 * (1 - rarityFactor))

		local w = base * boostRare * nerfCommon
		if w < 0.0001 then w = 0.0001 end
		weights[i] = w
		total += w
	end

	local roll = self._rng:NextNumber() * total
	local acc = 0
	for i,w in ipairs(weights) do
		acc += w
		if roll <= acc then
			return tiers[i]
		end
	end
	return tiers[1]
end

function AwakeningService:_pickElement()
	return ROOT_ELEMENTS[self._rng:NextInteger(1, #ROOT_ELEMENTS)]
end

function AwakeningService:_buildFoundation(st)
	ensureTrainTable(st)
	local t = st.Train
	local total = (t.Martial + t.Strength + t.Endurance + t.Breathing + t.Flexibility)

	local rate = clamp01(1 - math.exp(-(total / 900)))
	local f = {}

	f.QiCapacityMul = math.floor((1.00 + rate * 0.18) * 100 + 0.5) / 100
	f.QiRecoveryMul = math.floor((1.00 + rate * 0.15) * 100 + 0.5) / 100
	f.PhysiqueMul   = math.floor((1.00 + rate * 0.12) * 100 + 0.5) / 100
	f.BreakthroughBase = math.floor((rate * 0.015) * 1000 + 0.5) / 1000

	return f
end

function AwakeningService:_pickBodyType(st)
	ensureTrainTable(st)

	local scores = {}
	local total = 0

	for i, bt in ipairs(BODY_TYPES) do
		local s = 0
		for k, w in pairs(bt.weights) do
			s += (tonumber(st.Train[k]) or 0) * (tonumber(w) or 0)
		end
		s = math.max(0.001, s)
		scores[i] = s
		total += s
	end

	local roll = self._rng:NextNumber() * total
	local acc = 0
	for i, s in ipairs(scores) do
		acc += s
		if roll <= acc then
			return BODY_TYPES[i]
		end
	end
	return BODY_TYPES[1]
end

function AwakeningService:_buildBodyTypeBonuses(bodyType, bodyRate)
	local out = { Name = bodyType.name, Bonuses = {} }

	for bonusName, range in pairs(bodyType.bonuses) do
		local minv, maxv = range[1], range[2]
		local t = clamp01(bodyRate * 0.85 + self._rng:NextNumber() * 0.15)
		local val = lerp(minv, maxv, t)

		if math.abs(val) >= 1 then
			val = math.floor(val * 100 + 0.5) / 100
		else
			val = math.floor(val * 1000 + 0.5) / 1000
		end

		out.Bonuses[bonusName] = val
	end

	return out
end

function AwakeningService:_buildResult(st)
	local spiritScore = calcSpiritScore(st)
	local bodyScore = calcBodyScore(st)

	local spiritRate = clamp01(scoreToRate(spiritScore, SCORE_K_SPIRIT))
	local bodyRate   = clamp01(scoreToRate(bodyScore, SCORE_K_BODY))

	local rootTier = self:_pickWeightedTier(ROOT_TIERS, spiritRate)
	local bodyTier = self:_pickWeightedTier(BODY_TIERS, bodyRate)

	local root = {
		Tier = rootTier.name,
		Element = self:_pickElement(),
		QiGainMul = self:_randRange(rootTier.qiGainMul[1], rootTier.qiGainMul[2]),
		BreakthroughBonus = self:_randRange(rootTier.breakthrough[1], rootTier.breakthrough[2]),
	}

	local body = {
		Tier = bodyTier.name,
		HPMul = self:_randRange(bodyTier.hpMul[1], bodyTier.hpMul[2]),
		StaminaMul = self:_randRange(bodyTier.stamMul[1], bodyTier.stamMul[2]),
	}

	root.QiGainMul = math.floor(root.QiGainMul * 100 + 0.5) / 100
	root.BreakthroughBonus = math.floor(root.BreakthroughBonus * 1000 + 0.5) / 1000
	body.HPMul = math.floor(body.HPMul * 100 + 0.5) / 100
	body.StaminaMul = math.floor(body.StaminaMul * 100 + 0.5) / 100

	local foundation = self:_buildFoundation(st)
	local bt = self:_pickBodyType(st)
	local bodyType = self:_buildBodyTypeBonuses(bt, bodyRate)

	return root, body, foundation, bodyType
end

local function meetsMinTrain(st)
	ensureTrainTable(st)
	for k, req in pairs(MIN_TRAIN_REQUIREMENTS) do
		local v = tonumber(st.Train[k]) or 0
		if v < req then
			return false, k, req, v
		end
	end
	return true
end

function AwakeningService:_packState(st)
	return {
		Awakened = st.Awakened == true,
		Train = shallowCopy(st.Train or {}),
		Potential = calcPotential(st),
		MinPotential = MIN_POTENTIAL_TO_AWAKEN,
		MinTrain = shallowCopy(MIN_TRAIN_REQUIREMENTS),

		Root = st.Root,
		Body = st.Body,
		Foundation = st.Foundation,
		BodyType = st.BodyType,
	}
end

function AwakeningService:_pushState(player)
	local st = self._stateByPlayer[player]
	if not st then return end
	AwakenRE:FireClient(player, "State", self:_packState(st))
end

function AwakeningService:_loadPlayer(player)
	local key = "p_" .. player.UserId
	local data
	local ok = pcall(function()
		data = AwakenStore:GetAsync(key)
	end)

	local st = {
		Awakened = false,
		Train = {},
		Root = nil,
		Body = nil,
		Foundation = nil,
		BodyType = nil,
	}

	if ok and type(data) == "table" then
		st.Awakened = data.Awakened == true
		st.Train = type(data.Train) == "table" and data.Train or {}
		st.Root = type(data.Root) == "table" and data.Root or nil
		st.Body = type(data.Body) == "table" and data.Body or nil
		st.Foundation = type(data.Foundation) == "table" and data.Foundation or nil
		st.BodyType = type(data.BodyType) == "table" and data.BodyType or nil
	end

	ensureTrainTable(st)
	self._stateByPlayer[player] = st

	-- ? se já estava awakened, republica attributes e recompute no load
	if st.Awakened and st.Root and st.Body and st.Foundation and st.BodyType then
		self:_applyAwakenAttributes(player, st)
		if self._resolver then
			self._resolver:Recompute(player)
		end
	end
end

function AwakeningService:_savePlayer(player)
	local st = self._stateByPlayer[player]
	if not st then return end

	local now = os.clock()
	local last = self._lastSaveAt[player] or 0
	if (now - last) < SAVE_COOLDOWN then return end
	self._lastSaveAt[player] = now

	local key = "p_" .. player.UserId
	local payload = {
		Awakened = st.Awakened == true,
		Train = st.Train,
		Root = st.Root,
		Body = st.Body,
		Foundation = st.Foundation,
		BodyType = st.BodyType,
	}

	pcall(function()
		AwakenStore:SetAsync(key, payload)
	end)
end

-- training
local function addTraining(st, trainType, baseAmount)
	ensureTrainTable(st)
	baseAmount = tonumber(baseAmount) or 1
	if baseAmount <= 0 then return end
	if baseAmount > 50 then baseAmount = 50 end

	local current = st.Train[trainType] or 0
	local gain = baseAmount / (1 + (current / 500))
	if gain < 0.05 then gain = 0.05 end

	st.Train[trainType] = current + gain
end

local function canAwaken(st)
	if st.Awakened then return false, "already_awakened" end
	if calcPotential(st) < MIN_POTENTIAL_TO_AWAKEN then
		return false, "not_enough_potential"
	end
	local ok, missingK, req, have = meetsMinTrain(st)
	if not ok then
		return false, ("min_train:%s:%d:%d"):format(missingK, req, math.floor(have))
	end
	return true, "ok"
end

function AwakeningService:_applyAwakenAttributes(player, st)
	local root, body, foundation, bodyType = st.Root, st.Body, st.Foundation, st.BodyType
	player:SetAttribute("Awakened", true)

	player:SetAttribute("RootTier", root.Tier)
	player:SetAttribute("RootElement", root.Element)
	player:SetAttribute("QiGainMul", root.QiGainMul)
	player:SetAttribute("BreakthroughBonus", root.BreakthroughBonus)

	player:SetAttribute("BodyTier", body.Tier)
	player:SetAttribute("HPMul", body.HPMul)
	player:SetAttribute("StaminaMul", body.StaminaMul)

	player:SetAttribute("Foundation_QiCapacityMul", foundation.QiCapacityMul)
	player:SetAttribute("Foundation_QiRecoveryMul", foundation.QiRecoveryMul)
	player:SetAttribute("Foundation_PhysiqueMul", foundation.PhysiqueMul)
	player:SetAttribute("Foundation_BreakthroughBase", foundation.BreakthroughBase)

	player:SetAttribute("BodyType", bodyType.Name)
	for bonusName, val in pairs(bodyType.Bonuses or {}) do
		player:SetAttribute("BodyType_" .. bonusName, val)
	end
end

-- =========================
-- Public API
-- =========================
function AwakeningService:Init()
	AwakenRE.OnServerEvent:Connect(function(player, action, a, b)
		local st = self._stateByPlayer[player]
		if not st then return end

		if action == "RequestState" then
			self:_pushState(player)
			return
		end

		if action == "Train" then
			local trainType = a
			local amount = b
			if typeof(trainType) ~= "string" or not TRAIN_TYPES[trainType] then return end

			local now = os.clock()
			local last = self._lastTrainAt[player] or 0
			if (now - last) < TRAIN_COOLDOWN then return end
			self._lastTrainAt[player] = now

			addTraining(st, trainType, amount)
			self:_pushState(player)
			self:_savePlayer(player)
			return
		end

		if action == "Awaken" then
			local ok, reason = canAwaken(st)
			if not ok then
				AwakenRE:FireClient(player, "AwakenResult", false, reason, self:_packState(st))
				return
			end

			local root, body, foundation, bodyType = self:_buildResult(st)

			st.Awakened = true
			st.Root = root
			st.Body = body
			st.Foundation = foundation
			st.BodyType = bodyType

			self:_applyAwakenAttributes(player, st)

			-- ? aqui é onde resolve TUDO:
			if self._resolver then
				self._resolver:Recompute(player)
			end

			self:_savePlayer(player)
			self:_pushState(player)
			AwakenRE:FireClient(player, "AwakenResult", true, "ok", self:_packState(st))
			return
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_loadPlayer(player)
		task.defer(function()
			self:_pushState(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_savePlayer(player)
		self._stateByPlayer[player] = nil
		self._lastTrainAt[player] = nil
		self._lastSaveAt[player] = nil
	end)

	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			self:_savePlayer(p)
		end
	end)
end

-- chama no bootstrap depois de stats+resolver prontos
function AwakeningService:OnPlayerLoaded(player)
	if not self._stateByPlayer[player] then
		self:_loadPlayer(player)
	end
	-- se já awakened, já aplicou no _loadPlayer; mas aqui garante sync:
	local st = self._stateByPlayer[player]
	if st and st.Awakened and st.Root then
		self:_applyAwakenAttributes(player, st)
		if self._resolver then
			self._resolver:Recompute(player)
		end
	end
	self:_pushState(player)
end

function AwakeningService:Cleanup(player)
	self._stateByPlayer[player] = nil
	self._lastTrainAt[player] = nil
	self._lastSaveAt[player] = nil
end

return AwakeningService
