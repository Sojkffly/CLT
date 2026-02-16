--// StarterPlayerScripts/CombatClient.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local CombatRE = ReplicatedStorage:WaitForChild("CombatRE")

local Assets = ReplicatedStorage:WaitForChild("CombatAssets")
local SFX = Assets:WaitForChild("SFX")
local VFX = Assets:WaitForChild("VFX")

local PlayerScripts = player:WaitForChild("PlayerScripts")
local TargetChanged = PlayerScripts:WaitForChild("TargetChanged")
local AttackCancel = PlayerScripts:WaitForChild("AttackCancel")

local currentTarget: Model? = nil
local currentStyle: string = "Unarmed"

local track: AnimationTrack? = nil
local markerConn: RBXScriptConnection? = nil
local stoppedConn: RBXScriptConnection? = nil
local faceConn: RBXScriptConnection? = nil
local savedAutoRotate: boolean? = nil
local currentAnimId: string? = nil

-- ? anti race local
local currentAttackToken: number = 0
local currentHitIndex: number = 0

local function isAlive(model: Model?)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

-- ===== center do alvo =====
local function getHitPoint(model: Model): Vector3
	local upper = model:FindFirstChild("UpperTorso")
	if upper and upper:IsA("BasePart") then
		return upper.Position
	end

	local torso = model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso.Position
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local hip = (hum and hum.HipHeight) or 2
		return hrp.Position + Vector3.new(0, hip * 0.9, 0)
	end

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end

	return model:GetPivot().Position
end

local function showFloatingText(targetModel: Model, text: string)
	local hrp = targetModel:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 60)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Parent = hrp

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	if text == "EVADE" or text == "EVADED" then
		label.TextColor3 = Color3.fromRGB(180, 230, 255)
	else
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	task.spawn(function()
		local t = 0
		local dur = 0.45
		local start = gui.StudsOffset
		while t < dur do
			t += task.wait()
			local a = math.clamp(t / dur, 0, 1)
			gui.StudsOffset = start + Vector3.new(0, a * 1.2, 0)
			label.TextTransparency = a
			label.TextStrokeTransparency = 0.4 + a * 0.6
		end
		gui:Destroy()
	end)
end

-- ===== SFX/VFX utils =====
local function playSound(soundName: string, parent: Instance, volumeMul: number?)
	local template = SFX:FindFirstChild(soundName)
	if not (template and template:IsA("Sound")) then return end

	local s = template:Clone()
	s.Parent = parent
	if volumeMul then s.Volume = s.Volume * volumeMul end
	s:Play()
	Debris:AddItem(s, 4)
end

local function playSoundAtPos(soundName: string, worldPos: Vector3, volumeMul: number?)
	local template = SFX:FindFirstChild(soundName)
	if not (template and template:IsA("Sound")) then return end

	local att = Instance.new("Attachment")
	att.WorldPosition = worldPos
	att.Parent = workspace.Terrain

	local s = template:Clone()
	s.Parent = att
	if volumeMul then s.Volume = s.Volume * volumeMul end
	s:Play()

	Debris:AddItem(att, 4)
end

local function emitVFX(vfxName: string, worldPos: Vector3, burstOverride: number?)
	local template = VFX:FindFirstChild(vfxName)
	if not template then return end

	local clone = template:Clone()

	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new(worldPos))
		clone.Parent = workspace
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(worldPos)
		clone.Parent = workspace
	else
		local att = Instance.new("Attachment")
		att.WorldPosition = worldPos
		att.Parent = workspace.Terrain
		clone.Parent = att
	end

	local function emitParticle(p: Instance)
		if p:IsA("ParticleEmitter") then
			local burst = burstOverride or p:GetAttribute("Burst") or 20
			p:Emit(burst)
		end
	end

	if clone:IsA("ParticleEmitter") then
		emitParticle(clone)
	else
		for _, d in ipairs(clone:GetDescendants()) do
			emitParticle(d)
		end
	end

	Debris:AddItem(clone, 2)
end

-- ===== facing lock =====
local function stopFacing()
	if faceConn then faceConn:Disconnect() faceConn = nil end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and savedAutoRotate ~= nil then
		hum.AutoRotate = savedAutoRotate
	end
	savedAutoRotate = nil
end

local function startFacingTarget(targetModel: Model)
	local char = player.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	local tRoot = targetModel:FindFirstChild("HumanoidRootPart")
	if not tRoot then return end

	if savedAutoRotate == nil then
		savedAutoRotate = hum.AutoRotate
	end
	hum.AutoRotate = false

	if faceConn then faceConn:Disconnect() end
	faceConn = RunService.RenderStepped:Connect(function()
		if not track or not track.IsPlaying then return end
		if not currentTarget or currentTarget ~= targetModel then return end

		local pos = hrp.Position
		local targetPos = tRoot.Position
		local look = Vector3.new(targetPos.X, pos.Y, targetPos.Z)

		if (look - pos).Magnitude > 0.001 then
			hrp.CFrame = CFrame.lookAt(pos, look)
		end
	end)
end

-- ===== miss react =====
local missTrack: AnimationTrack? = nil
local missAnimId: string? = nil

local function playMissReact(animId: string)
	if typeof(animId) ~= "string" or animId == "" then return end

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)

	if (not missTrack) or (missAnimId ~= animId) then
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		missTrack = animator:LoadAnimation(anim)
		missTrack.Priority = Enum.AnimationPriority.Action
		missTrack.Looped = false
		missAnimId = animId
	end

	if missTrack.IsPlaying then
		missTrack:Stop(0)
	end
	missTrack:Play(0.03, 1, 1)
end

-- ===== animation track =====
local function buildTrack(animId: string)
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid")
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	anim.Parent = animator -- ? MUITO IMPORTANTE (evita track.Animation nil)

	track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	currentAnimId = animId

	if markerConn then markerConn:Disconnect() end
	markerConn = track:GetMarkerReachedSignal("Hit"):Connect(function()
		local char2 = player.Character
		local hrp = char2 and char2:FindFirstChild("HumanoidRootPart")
		if hrp then
			playSound(currentStyle .. "_Swing", hrp, 1)
			emitVFX(currentStyle .. "_Swing", hrp.Position)
		end

		if currentTarget and isAlive(currentTarget) then
			currentHitIndex += 1
			CombatRE:FireServer("HitMoment", currentTarget, currentStyle, currentAttackToken, currentHitIndex)
		end
	end)
end

-- ===== cancel =====
local function cancelAttack()
	stopFacing()

	-- ? invalida localmente (evita marker atrasado mandar token velho)
	currentAttackToken += 1
	currentHitIndex = 0

	if track and track.IsPlaying then
		track:Stop(0)
	end
end

AttackCancel.Event:Connect(function()
	cancelAttack()
end)

TargetChanged.Event:Connect(function(t)
	if typeof(t) == "Instance" and t:IsA("Model") and isAlive(t) then
		currentTarget = t
	else
		currentTarget = nil
		cancelAttack()
	end
end)

-- ===== Remote events =====
CombatRE.OnClientEvent:Connect(function(action, a, b, c, d)
	if action == "DodgeReact" then
		local animId = a
		if typeof(animId) == "string" and animId ~= "" then
			playMissReact(animId) -- reutiliza a função (ela já toca no seu próprio personagem)
		end
		return
	end
	if action == "FloatingText" then
		local targetModel = a
		local text = b
		if typeof(targetModel) == "Instance" and targetModel:IsA("Model") and typeof(text) == "string" then
			showFloatingText(targetModel, text)
		end
		return
	end

	if action == "StopAttack" then
		cancelAttack()
		return
	end

	-- ? Impacto confirmado (aqui toca o Hit no alvo)
	if action == "HitConfirm" then
		local targetModel = a
		local styleName = b

		if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end
		if typeof(styleName) ~= "string" then return end
		if not isAlive(targetModel) then return end

		local pos = getHitPoint(targetModel)
		playSoundAtPos(styleName .. "_Hit", pos, 1)
		emitVFX(styleName .. "_Hit", pos)

		return
	end

	-- ? Resultado (Miss -> MissReact)
	if action == "HitResult" then
		local result = a          -- "Miss" | "Hit"
		local missReactId = d     -- animId do miss

		if result == "Miss" then
			playMissReact(missReactId)
		end
		return
	end

	-- ? PlayAttack(styleName, animId, speedMul, token)
	if action ~= "PlayAttack" then return end

	local styleName = a
	local animId = b
	local speedMul = c
	local token = d

	if typeof(styleName) ~= "string" then return end
	if typeof(animId) ~= "string" or animId == "" then return end
	if typeof(token) ~= "number" then return end
	if not currentTarget or not isAlive(currentTarget) then return end

	-- não spammar
	if track and track.IsPlaying then
		return
	end

	currentStyle = styleName
	currentAttackToken = token
	currentHitIndex = 0

	if not track or currentAnimId ~= animId then
		buildTrack(animId)
	end

	startFacingTarget(currentTarget)

	track:AdjustSpeed(tonumber(speedMul) or 1)
	track:Play(0.05, 1, 1)

	if stoppedConn then stoppedConn:Disconnect() end
	stoppedConn = track.Stopped:Connect(function()
		stopFacing()
	end)
end)

player.CharacterAdded:Connect(function()
	cancelAttack()
	track = nil
	currentAnimId = nil
	if markerConn then markerConn:Disconnect() markerConn = nil end
	if stoppedConn then stoppedConn:Disconnect() stoppedConn = nil end
end)
