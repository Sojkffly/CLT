local Players = game:GetService("Players")

local CultivationService = {}
CultivationService.__index = CultivationService

function CultivationService.new(playerRegistry, statsService)
	local self = setmetatable({}, CultivationService)
	self._reg = playerRegistry
	self._stats = statsService
	self._running = false
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

function CultivationService:InitPlayer(player)
	self._reg:WaitReady(player, "StatsReady")
	self._reg:SetReady(player, "CultivationReady")
end

function CultivationService:Start()
	if self._running then return end
	self._running = true

	task.spawn(function()
		local last = os.clock()

		while self._running do
			task.wait(1)
			local now = os.clock()
			local dt = now - last
			last = now

			for _, player in ipairs(Players:GetPlayers()) do
				if self._reg:IsReady(player, "StatsReady") then
					local base = self._stats:Get(player)
					if base then
						local qi = tonumber(base.Qi) or 0

						-- =========================
						-- AWAKEN MULTS (via Attributes)
						-- =========================
						local qiGainMul = getMul(player, "QiGainMul", 1.0) -- do Root
						local fQiCapMul = getMul(player, "Foundation_QiCapacityMul", 1.0)
						local fQiRecMul = getMul(player, "Foundation_QiRecoveryMul", 1.0)

						-- =========================
						-- MaxQi / Regen base
						-- =========================
						local maxQiBase = tonumber(player:GetAttribute("MaxQi")) or (tonumber(base.MaxQi) or 100)
						local regenBase = tonumber(player:GetAttribute("QiRegen")) or (tonumber(base.QiRegen) or 0)

						-- ? aplica Awaken
						local maxQi = maxQiBase * fQiCapMul
						local regen = regenBase * fQiRecMul

						-- =========================
						-- 1) REGEN DE QI
						-- =========================
						if regen > 0 and qi < maxQi then
							local newQi = qi + regen * dt
							newQi = clamp(newQi, 0, maxQi)
							self._stats:Set(player, "Qi", newQi)
						end

						-- =========================
						-- 2) CULT EXP (SÓ MEDITANDO)
						-- =========================
						if player:GetAttribute("Meditating") == true then
							local cultExp = tonumber(base.CultExp) or 0
							local toNext = tonumber(base.CultExpToNext) or 100

							-- taxa baseada no regen + multipliers
							-- regen já veio com Foundation_QiRecoveryMul
							-- qiGainMul acelera o ganho de cultivo (Root)
							local rate = (regenBase * 0.5) * qiGainMul

							-- se regenBase for 0, ainda permite cultivo mínimo
							if rate <= 0 then
								rate = 0.05 * qiGainMul
							end

							cultExp += rate * dt
							self._stats:Set(player, "CultExp", cultExp)

							-- =========================
							-- 3) LIBERAR BREAKTHROUGH
							-- =========================
							local can = cultExp >= toNext
							if player:GetAttribute("CanBreakthrough") ~= can then
								self._stats:Set(player, "CanBreakthrough", can)
							end
						end
					end
				end
			end
		end
	end)
end

function CultivationService:Stop()
	self._running = false
end

return CultivationService
