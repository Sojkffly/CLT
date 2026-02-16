--// ServerScriptService/Services/StatResolverService.lua
local StatResolverService = {}
StatResolverService.__index = StatResolverService

-- quais stats vamos resolver com modifiers (você pode expandir)
local RESOLVED_KEYS = {
	"MaxHP","ATK","DEF","Crit","Dodge","Precision","MoveSpeed",
	"MaxQi","QiRegen",

	-- ? ataque/velocidade de ataque (CombatService usa esse attribute)
	"AttackSpeed",

	-- Artefato
	"ArtifactDamage","ArtifactAttackInterval","ArtifactProjectileSpeed",
	"ArtifactKnockback","ArtifactTrailSize","ArtifactCurvature",

	-- Arma
	"WeaponDamage","WeaponAttackInterval","WeaponRange","WeaponKnockback",
}

local function clamp(n, a, b)
	if n < a then return a end
	if n > b then return b end
	return n
end

local function num(x, default)
	x = tonumber(x)
	if x == nil then return default end
	return x
end

-- pega attribute numérico com fallback
local function attr(player, name, default)
	return num(player:GetAttribute(name), default)
end

-- pega attribute multiplicador (default 1)
local function mul(player, name)
	local v = num(player:GetAttribute(name), 1)
	if v <= 0 then v = 1 end
	return v
end

-- pega attribute bônus aditivo (default 0)
local function add(player, name)
	return num(player:GetAttribute(name), 0)
end

function StatResolverService.new(playerRegistry, statsService, modifierService)
	local self = setmetatable({}, StatResolverService)
	self._reg = playerRegistry
	self._stats = statsService
	self._mods = modifierService
	return self
end

function StatResolverService:Recompute(player)
	self._reg:WaitReady(player, "StatsReady")

	local base = self._stats:Get(player)
	if not base then return end

	local awakened = (player:GetAttribute("Awakened") == true)

	-- =========================
	-- 1) Resolve base + modifiers
	-- =========================
	local finalByKey = {}

	for _, key in ipairs(RESOLVED_KEYS) do
		local baseValue = base[key]
		local final = self._mods:GetFinal(player, key, baseValue)

		-- clamps úteis
		if key == "Crit" or key == "Dodge" or key == "Precision" then
			final = clamp(final, 0, 0.95)
		elseif key == "MoveSpeed" then
			final = clamp(final, 0, 100)
		elseif key == "MaxHP" or key == "MaxQi" then
			final = math.max(1, math.floor(final + 0.5))
		elseif key == "ArtifactAttackInterval" or key == "WeaponAttackInterval" then
			final = math.max(0.1, final)
		elseif key == "ArtifactProjectileSpeed" then
			final = math.max(1, final)
		elseif key == "ArtifactTrailSize" then
			final = math.max(0, final)
		elseif key == "ArtifactCurvature" then
			final = clamp(final, 0, 1)
		elseif key == "WeaponRange" then
			final = math.max(1, final)
		elseif key == "AttackSpeed" then
			final = clamp(final, 0.6, 2.5)
		end

		finalByKey[key] = final
	end

	-- =========================
	-- 2) Aplica multipliers do AWAKEN (Attributes)
	-- =========================
	if awakened then
		-- Root / Foundation
		local qiGainMul      = mul(player, "QiGainMul") -- você definiu no Awaken
		local hpMul          = mul(player, "HPMul")
		local qiCapMul       = mul(player, "Foundation_QiCapacityMul")
		local qiRegenMul     = mul(player, "Foundation_QiRecoveryMul")
		local physiqueMul    = mul(player, "Foundation_PhysiqueMul")

		-- BodyType (alguns são multiplicadores, outros aditivos)
		local defMul         = mul(player, "BodyType_DefenseMul")
		local msMul          = mul(player, "BodyType_MoveSpeedMul")
		local atkSpdMul      = mul(player, "BodyType_AttackSpeedMul")
		local hpExtraMul     = mul(player, "BodyType_HPMulExtra")

		local dodgeBonus     = add(player, "BodyType_DodgeBonus")
		local critBonus      = add(player, "BodyType_CritBonus")

		-- aplica nos finais
		finalByKey.MaxHP = math.max(1, math.floor((num(finalByKey.MaxHP, 100) * hpMul * hpExtraMul * physiqueMul) + 0.5))
		finalByKey.MaxQi = math.max(1, math.floor((num(finalByKey.MaxQi, 100) * qiCapMul) + 0.5))

		-- QiRegen: “QiGainMul” e Foundation_QiRecoveryMul influenciam
		finalByKey.QiRegen = math.max(0, num(finalByKey.QiRegen, 0) * qiRegenMul * qiGainMul)

		-- PhysiqueMul ajuda ATK/DEF também (leve, mas faz diferença)
		finalByKey.ATK = math.max(0, num(finalByKey.ATK, 0) * physiqueMul)
		finalByKey.DEF = math.max(0, num(finalByKey.DEF, 0) * physiqueMul * defMul)

		finalByKey.MoveSpeed = clamp(num(finalByKey.MoveSpeed, 16) * msMul, 0, 100)

		finalByKey.Dodge = clamp(num(finalByKey.Dodge, 0) + dodgeBonus, 0, 0.95)
		finalByKey.Crit  = clamp(num(finalByKey.Crit, 0)  + critBonus,  0, 0.95)

		-- AttackSpeed (CombatService usa player:GetAttribute("AttackSpeed"))
		finalByKey.AttackSpeed = clamp(num(finalByKey.AttackSpeed, 1.0) * atkSpdMul, 0.6, 2.5)
	end

	-- =========================
	-- 3) Publica attributes finais
	-- =========================
	for _, key in ipairs(RESOLVED_KEYS) do
		player:SetAttribute(key, finalByKey[key])
	end

	-- =========================
	-- 4) Clampa HP/Qi atuais com MaxHP/MaxQi finais
	-- =========================
	local maxHP = attr(player, "MaxHP", num(base.MaxHP, 100))
	local hp = attr(player, "HP", num(base.HP, 0))
	if hp > maxHP then
		self._stats:Set(player, "HP", maxHP)
	end

	local maxQi = attr(player, "MaxQi", num(base.MaxQi, 100))
	local qi = attr(player, "Qi", num(base.Qi, 0))
	if qi > maxQi then
		self._stats:Set(player, "Qi", maxQi)
	end
end

function StatResolverService:InitPlayer(player)
	self._reg:WaitReady(player, "StatsReady")
	self:Recompute(player)
	self._reg:SetReady(player, "ResolvedStatsReady")
end

return StatResolverService
