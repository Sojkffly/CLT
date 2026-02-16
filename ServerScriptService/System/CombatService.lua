--// ServerScriptService/Services/CombatService.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = {}
CombatService.__index = CombatService

-- ===== CONFIG =====
local TICK = 0.1

local MAX_TARGET_DISTANCE = 120
local MAX_ATTACK_RANGE = 25

-- melee bem perto
local UNARMED_RANGE = 4.0
local UNARMED_DAMAGE = 3

local UNARMED_INTERVAL_FALLBACK = 0.9

local USE_LOS_RANGED = true
local USE_LOS_MELEE  = false

local HIT_REPLICATE_RADIUS = 80

-- rate limit HitMoment (por player)
local HITMOMENT_WINDOW_SEC = 1.0
local HITMOMENT_MAX_PER_WINDOW = 12

local ATTACK_STYLES = {
	Unarmed = {
		mode = "Melee",
		range = UNARMED_RANGE,
		damage = UNARMED_DAMAGE,
		animId = "rbxassetid://115701154437911",
		missReactAnimId = "rbxassetid://94136051115953",
		missReactLength = 0.5,
		baseHitChance = 0.92,
		animLength = 2.0,
		maxHits = 2,
		buffer = 0.15,
	},
}

local DEFAULT_STYLE = "Unarmed"

-- ===== Raycast params (LoS) =====
local rayParams = RaycastParams.new()
rayParams.IgnoreWater = true
rayParams.FilterType = Enum.RaycastFilterType.Blacklist

-- ===== Overlap params (Hitbox) =====
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Blacklist

-- ===== Helpers =====
local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(model)
	return model and model:FindFirstChildOfClass("Humanoid")
end

local function isAlive(model)
	local hum = getHumanoid(model)
	return hum and hum.Health > 0
end

local function clampRange(r)
	r = tonumber(r) or 0
	if r < 0 then r = 0 end
	if r > MAX_ATTACK_RANGE then r = MAX_ATTACK_RANGE end
	return r
end

local function hasLineOfSight(attackerChar, attackerHRP, targetChar, targetHRP)
	rayParams.FilterDescendantsInstances = { attackerChar }
	local origin = attackerHRP.Position
	local dir = (targetHRP.Position - origin)
	local hit = Workspace:Raycast(origin, dir, rayParams)
	if not hit then return true end
	return hit.Instance:IsDescendantOf(targetChar)
end

local function isInMeleeRange(attackerChar: Model, targetChar: Model, reach: number)
	local aRoot = getRoot(attackerChar)
	local tRoot = getRoot(targetChar)
	if not aRoot or not tRoot then return false end

	local aPos = aRoot.Position
	local tPos = tRoot.Position

	local dir = Vector3.new(tPos.X - aPos.X, 0, tPos.Z - aPos.Z)
	local mag = dir.Magnitude
	if mag < 0.001 then
		dir = Vector3.new(0, 0, 1)
	else
		dir = dir / mag
	end

	local center = aPos + dir * (reach * 0.55)
	local radius = reach * 0.75

	overlapParams.FilterDescendantsInstances = { attackerChar }
	local parts = Workspace:GetPartBoundsInRadius(center, radius, overlapParams)

	for _, p in ipairs(parts) do
		if p:IsDescendantOf(targetChar) then
			return true
		end
	end
	return false
end

local function ensureState(self, player)
	local st = self._state[player]
	if st then return st end

	st = {
		target = nil,
		nextAttack = 0,
		manualMoveUntil = 0,

		attackUntil = 0,

		lastStyle = DEFAULT_STYLE,
		lastRange = 0,
		lastDmg = 0,
		lastMode = "Melee",

		-- ? anti exploit / anti race
		attackToken = 0,
		hitSeq = 0,               -- último hitIndex aceito (por token)
		hitRemoteCount = 0,       -- rate limit count
		hitRemoteWindowAt = 0,    -- rate limit window start
	}
	self._state[player] = st
	return st
end

local function invalidateAttack(st)
	st.attackToken = (st.attackToken or 0) + 1
	st.hitSeq = 0
	st.attackUntil = 0
end

function CombatService:_getStyleForPlayer(player)
	return DEFAULT_STYLE
end

function CombatService:_getAttackSpeedMul(player)
	local s = tonumber(player:GetAttribute("AttackSpeed")) or 1.0
	return math.clamp(s, 0.6, 2.5)
end

function CombatService.new(playerRegistry, statsService)
	local self = setmetatable({}, CombatService)
	self._reg = playerRegistry
	self._stats = statsService
	self._state = {}
	self._running = false
	self._rng = Random.new()
	return self
end

function CombatService:Init()
	local CombatRE = ReplicatedStorage:WaitForChild("CombatRE")
	local MoveRE = ReplicatedStorage:WaitForChild("MoveRE")

	CombatRE.OnServerEvent:Connect(function(player, action, targetModel, styleFromClient, token, hitIndex)
		local st = ensureState(self, player)

		if action == "ClearTarget" then
			st.target = nil
			st.nextAttack = 0
			st.manualMoveUntil = 0

			invalidateAttack(st)
			CombatRE:FireClient(player, "StopAttack")
			return
		end

		if action == "SetTarget" then
			if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end

			local char = player.Character
			if not char then return end

			local myRoot = getRoot(char)
			local tgRoot = getRoot(targetModel)
			if not myRoot or not tgRoot then return end

			local th = getHumanoid(targetModel)
			if not th or th.Health <= 0 then return end

			local dist = (tgRoot.Position - myRoot.Position).Magnitude
			if dist > MAX_TARGET_DISTANCE then return end

			st.target = targetModel
			return
		end

		if action == "HitMoment" then
			-- helper: manda miss pro atacante (com react anim)
			local function reject(reason: string)
				local style2 = ATTACK_STYLES[st.lastStyle]
				local missAnim = (style2 and style2.missReactAnimId) or ""
				CombatRE:FireClient(player, "HitResult", "Miss", reason, st.lastStyle, missAnim)
			end

			-- ? token check
			if typeof(token) ~= "number" then
				reject("bad_token"); return
			end
			if token ~= (st.attackToken or 0) then
				reject("stale_token"); return
			end

			-- ? rate limit
			local now = os.clock()
			local windowStart = st.hitRemoteWindowAt or 0
			if (now - windowStart) > HITMOMENT_WINDOW_SEC then
				st.hitRemoteWindowAt = now
				st.hitRemoteCount = 0
			end
			st.hitRemoteCount = (st.hitRemoteCount or 0) + 1
			if st.hitRemoteCount > HITMOMENT_MAX_PER_WINDOW then
				reject("rate_limited"); return
			end

			-- valida target
			if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then
				reject("bad_target"); return
			end
			if st.target ~= targetModel then
				reject("not_current_target"); return
			end
			if now > (st.attackUntil or 0) then
				reject("window_closed"); return
			end
			if not isAlive(targetModel) then
				reject("target_dead"); return
			end

			-- valida style
			if typeof(styleFromClient) ~= "string" then
				reject("bad_style"); return
			end
			if styleFromClient ~= st.lastStyle then
				reject("style_mismatch"); return
			end

			local style = ATTACK_STYLES[st.lastStyle]
			if not style then
				reject("unknown_style"); return
			end

			-- ? hitIndex / maxHits
			local maxHits = (style.maxHits or 1)
			if hitIndex ~= nil then
				if typeof(hitIndex) ~= "number" then
					reject("bad_hit_index"); return
				end
				if hitIndex < 1 or hitIndex > maxHits then
					reject("hit_index_oob"); return
				end
				if hitIndex <= (st.hitSeq or 0) then
					reject("duplicate_hit"); return
				end
				st.hitSeq = hitIndex
			else
				st.hitSeq = (st.hitSeq or 0) + 1
				if st.hitSeq > maxHits then
					reject("too_many_hits"); return
				end
			end

			local char = player.Character
			if not char then
				reject("no_char"); return
			end

			local myRoot = getRoot(char)
			local tgRoot = getRoot(targetModel)
			local th = getHumanoid(targetModel)
			if not myRoot or not tgRoot or not th or th.Health <= 0 then
				reject("missing_parts"); return
			end

			-- LoS
			if style.mode == "Ranged" and USE_LOS_RANGED then
				if not hasLineOfSight(char, myRoot, targetModel, tgRoot) then
					reject("no_los"); return
				end
			elseif style.mode == "Melee" and USE_LOS_MELEE then
				if not hasLineOfSight(char, myRoot, targetModel, tgRoot) then
					reject("no_los"); return
				end
			end

			-- Range
			local range = clampRange(style.range or UNARMED_RANGE)
			if style.mode == "Melee" then
				if not isInMeleeRange(char, targetModel, range) then
					reject("out_of_range"); return
				end
			else
				local dist2 = (tgRoot.Position - myRoot.Position).Magnitude
				if dist2 > range then
					reject("out_of_range"); return
				end
			end

			-- ? Dodge/Precision
			local prec = tonumber(player:GetAttribute("Precision")) or 0.92

			local dodge = 0
			local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
			if targetPlayer then
				dodge = tonumber(targetPlayer:GetAttribute("Dodge")) or 0
			else
				dodge = tonumber(targetModel:GetAttribute("Dodge")) or 0
			end

			local baseHit = tonumber(style.baseHitChance) or 0.92
			local hitChance = math.clamp(baseHit + (prec - 0.92) - dodge, 0.10, 0.98)

			if self._rng:NextNumber() > hitChance then
				-- 1) pro atacante: só feedback de miss (sem missReact)
				CombatRE:FireClient(player, "HitResult", "Miss", "dodge", st.lastStyle, "")
				CombatRE:FireClient(player, "FloatingText", targetModel, "EVADE")

				-- 2) pro alvo: tocar dodge react (player ou NPC)
				local dodgeAnimId = style.missReactAnimId or "" -- (reaproveitando seu campo)
				local targetPlr = Players:GetPlayerFromCharacter(targetModel)

				if targetPlr then
					CombatRE:FireClient(targetPlr, "DodgeReact", dodgeAnimId)
					CombatRE:FireClient(targetPlr, "FloatingText", targetModel, "EVADED")
				else
					-- NPC: animação no server
					local th = getHumanoid(targetModel)
					if th and th.Health > 0 and dodgeAnimId ~= "" then
						local animator = th:FindFirstChildOfClass("Animator") or Instance.new("Animator", th)
						local anim = Instance.new("Animation")
						anim.AnimationId = dodgeAnimId

						local tr = animator:LoadAnimation(anim)
						tr.Priority = Enum.AnimationPriority.Action
						tr.Looped = false
						tr:Play(0.05, 1, 1)

						-- cleanup
						task.delay(1.2, function()
							if tr then tr:Stop(0) end
							if anim then anim:Destroy() end
						end)
					end
				end

				return
			end

			-- ? HIT
			local dmg = tonumber(style.damage) or UNARMED_DAMAGE
			th:TakeDamage(dmg)

			CombatRE:FireClient(player, "HitResult", "Hit", dmg, st.lastStyle, "")

			-- broadcast do hit (VFX/SFX no alvo pros próximos)
			if tgRoot then
				for _, plr in ipairs(Players:GetPlayers()) do
					local c = plr.Character
					local r = c and c:FindFirstChild("HumanoidRootPart")
					if r and (r.Position - tgRoot.Position).Magnitude <= HIT_REPLICATE_RADIUS then
						CombatRE:FireClient(plr, "HitConfirm", targetModel, st.lastStyle, dmg)
					end
				end
			else
				CombatRE:FireClient(player, "HitConfirm", targetModel, st.lastStyle, dmg)
			end

			return
		end
	end)

	MoveRE.OnServerEvent:Connect(function(player, pos)
		if typeof(pos) ~= "Vector3" then return end
		local char = player.Character
		local hum = getHumanoid(char)
		if not hum then return end

		local st = ensureState(self, player)
		st.manualMoveUntil = os.clock() + 0.6
		hum:MoveTo(pos)
	end)
end

function CombatService:Start()
	if self._running then return end
	self._running = true

	local CombatRE = ReplicatedStorage:WaitForChild("CombatRE")

	task.spawn(function()
		while self._running do
			task.wait(TICK)

			for _, player in ipairs(Players:GetPlayers()) do
				local st = self._state[player]
				local char = player.Character
				if not st or not st.target or not char then
					continue
				end

				if not isAlive(char) then
					st.target = nil
					st.nextAttack = 0
					invalidateAttack(st)
					CombatRE:FireClient(player, "StopAttack")
					continue
				end

				if not isAlive(st.target) then
					st.target = nil
					st.nextAttack = 0
					invalidateAttack(st)
					CombatRE:FireClient(player, "StopAttack")
					continue
				end

				local myRoot = getRoot(char)
				local tgRoot = getRoot(st.target)
				local myHum = getHumanoid(char)

				if not myRoot or not tgRoot or not myHum then
					st.target = nil
					st.nextAttack = 0
					invalidateAttack(st)
					CombatRE:FireClient(player, "StopAttack")
					continue
				end

				local now = os.clock()

				local styleName = self:_getStyleForPlayer(player)
				local style = ATTACK_STYLES[styleName] or ATTACK_STYLES[DEFAULT_STYLE]
				if not style then continue end

				local mode = style.mode or "Melee"
				local range = clampRange(style.range or UNARMED_RANGE)

				local inRange
				if mode == "Melee" then
					inRange = isInMeleeRange(char, st.target, range)
				else
					inRange = ((tgRoot.Position - myRoot.Position).Magnitude <= range)
				end

				if now >= (st.manualMoveUntil or 0) and not inRange then
					local aPos = myRoot.Position
					local tPos = tgRoot.Position

					local dir = Vector3.new(tPos.X - aPos.X, 0, tPos.Z - aPos.Z)
					local mag = dir.Magnitude
					local dirUnit = (mag > 0.001) and (dir / mag) or Vector3.new(0, 0, 1)

					local stopDist = math.max(1.4, range * 0.45)
					local goal = tgRoot.Position - dirUnit * stopDist
					myHum:MoveTo(goal)
				end

				if inRange and now >= (st.nextAttack or 0) then
					if mode == "Ranged" and USE_LOS_RANGED then
						if not hasLineOfSight(char, myRoot, st.target, tgRoot) then
							continue
						end
					end

					local speedMul = self:_getAttackSpeedMul(player)

					local animLength = tonumber(style.animLength) or UNARMED_INTERVAL_FALLBACK
					local duration = animLength / speedMul
					if duration < 0.1 then duration = 0.1 end

					st.lastStyle = styleName
					st.lastMode = mode
					st.lastRange = range
					st.lastDmg = tonumber(style.damage) or UNARMED_DAMAGE

					-- ? novo ataque: novo token + reseta hitSeq
					st.attackToken = (st.attackToken or 0) + 1
					st.hitSeq = 0
					st.hitRemoteCount = 0
					st.hitRemoteWindowAt = now

					st.attackUntil = now + duration + (style.buffer or 0.15)
					st.nextAttack = now + duration

					CombatRE:FireClient(player, "PlayAttack", styleName, style.animId, speedMul, st.attackToken)
				end
			end
		end
	end)
end

function CombatService:Cleanup(player)
	self._state[player] = nil
end

return CombatService
