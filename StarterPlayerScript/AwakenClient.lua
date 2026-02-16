--// StarterPlayerScripts/AwakenClient.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local AwakenRE = ReplicatedStorage:WaitForChild("AwakenRE")

-- =========================
-- UI (se você já tem CultivationGui, adapte aqui)
-- - Se existir ScreenGui "CultivationGui" com:
--   Button "AwakenButton"
--   TextLabel "PotentialLabel"
--   TextLabel "ResultLabel"
-- Ele usa. Se não existir, cria UI simples pra testar.
-- =========================
local function getOrCreateUI()
	local pg = player:WaitForChild("PlayerGui")

	local gui = pg:FindFirstChild("CultivationGui")
	if gui and gui:IsA("ScreenGui") then
		local awakenBtn = gui:FindFirstChild("AwakenButton", true)
		local potLbl = gui:FindFirstChild("PotentialLabel", true)
		local resLbl = gui:FindFirstChild("ResultLabel", true)
		if awakenBtn and potLbl and resLbl then
			return gui, awakenBtn, potLbl, resLbl
		end
	end

	-- fallback UI simples
	gui = Instance.new("ScreenGui")
	gui.Name = "CultivationGui"
	gui.ResetOnSpawn = false
	gui.Parent = pg

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(320, 160)
	frame.Position = UDim2.fromScale(0.5, 0.75)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	frame.Parent = gui

	local potLbl = Instance.new("TextLabel")
	potLbl.Name = "PotentialLabel"
	potLbl.BackgroundTransparency = 1
	potLbl.Size = UDim2.new(1, -16, 0, 30)
	potLbl.Position = UDim2.fromOffset(8, 8)
	potLbl.Font = Enum.Font.GothamBold
	potLbl.TextScaled = true
	potLbl.TextColor3 = Color3.fromRGB(255,255,255)
	potLbl.Text = "Potential: 0 / 0"
	potLbl.Parent = frame

	local resLbl = Instance.new("TextLabel")
	resLbl.Name = "ResultLabel"
	resLbl.BackgroundTransparency = 1
	resLbl.Size = UDim2.new(1, -16, 0, 70)
	resLbl.Position = UDim2.fromOffset(8, 40)
	resLbl.Font = Enum.Font.Gotham
	resLbl.TextScaled = true
	resLbl.TextColor3 = Color3.fromRGB(210,210,210)
	resLbl.Text = "Treine para liberar o Awaken."
	resLbl.Parent = frame

	local awakenBtn = Instance.new("TextButton")
	awakenBtn.Name = "AwakenButton"
	awakenBtn.Size = UDim2.new(1, -16, 0, 40)
	awakenBtn.Position = UDim2.new(0, 8, 1, -48)
	awakenBtn.Font = Enum.Font.GothamBlack
	awakenBtn.TextScaled = true
	awakenBtn.TextColor3 = Color3.fromRGB(255,255,255)
	awakenBtn.BackgroundColor3 = Color3.fromRGB(70, 120, 90)
	awakenBtn.Text = "AWAKEN"
	awakenBtn.Parent = frame

	return gui, awakenBtn, potLbl, resLbl
end

local gui, awakenBtn, potLbl, resLbl = getOrCreateUI()

-- =========================
-- Local state
-- =========================
local lastState = nil
local function formatResult(st)
	if not st then
		return "Carregando..."
	end

	local pot = tonumber(st.Potential) or 0
	local minPot = tonumber(st.MinPotential) or 0

	local f = st.Foundation
	local bt = st.BodyType

	local baseInfo = string.format("Potential: %d / %d\n", pot, minPot)

	-- mostra requisitos mínimos
	if st.MinTrain and st.Train then
		baseInfo ..= "Min Treinos:\n"
		for k, req in pairs(st.MinTrain) do
			local have = math.floor(tonumber(st.Train[k]) or 0)
			baseInfo ..= string.format(" - %s: %d/%d\n", k, have, req)
		end
	end

	if not st.Awakened then
		return baseInfo .. "\nTreine para liberar o Awaken."
	end

	local r = st.Root
	local b = st.Body

	local lines = {}
	table.insert(lines, baseInfo)
	table.insert(lines, string.format("Root: %s (%s)", r.Tier, r.Element))
	table.insert(lines, string.format("Qi Gain: x%.2f", tonumber(r.QiGainMul) or 1))
	table.insert(lines, string.format("Breakthrough: +%.1f%%", (tonumber(r.BreakthroughBonus) or 0) * 100))
	table.insert(lines, "")
	table.insert(lines, string.format("Body: %s", b.Tier))
	table.insert(lines, string.format("HP: x%.2f | Stamina: x%.2f", tonumber(b.HPMul) or 1, tonumber(b.StaminaMul) or 1))

	if f then
		table.insert(lines, "")
		table.insert(lines, "Foundation (garantido):")
		table.insert(lines, string.format("Qi Cap: x%.2f", tonumber(f.QiCapacityMul) or 1))
		table.insert(lines, string.format("Qi Rec: x%.2f", tonumber(f.QiRecoveryMul) or 1))
		table.insert(lines, string.format("Physique: x%.2f", tonumber(f.PhysiqueMul) or 1))
		table.insert(lines, string.format("Break Base: +%.2f%%", (tonumber(f.BreakthroughBase) or 0) * 100))
	end

	if bt and bt.Name then
		table.insert(lines, "")
		table.insert(lines, "Body Type: " .. bt.Name)
		if bt.Bonuses then
			for k, v in pairs(bt.Bonuses) do
				if tonumber(v) then
					if v >= 1 then
						table.insert(lines, string.format(" - %s: x%.2f", k, v))
					else
						table.insert(lines, string.format(" - %s: +%.2f%%", k, v * 100))
					end
				end
			end
		end
	end

	return table.concat(lines, "\n")
end


local function applyState(st)
	lastState = st
	local pot = tonumber(st.Potential) or 0
	local minPot = tonumber(st.MinPotential) or 0

	potLbl.Text = string.format("Potential: %d / %d", pot, minPot)

	if st.Awakened then
		awakenBtn.AutoButtonColor = false
		awakenBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
		awakenBtn.Text = "AWAKENED"
	else
		awakenBtn.AutoButtonColor = true
		awakenBtn.BackgroundColor3 = (pot >= minPot) and Color3.fromRGB(70, 140, 90) or Color3.fromRGB(120, 80, 60)
		awakenBtn.Text = (pot >= minPot) and "AWAKEN" or "LOCKED"
	end

	resLbl.Text = formatResult(st)
end

-- =========================
-- Public API (você chama isso quando o player treinar)
-- =========================
_G.AwakenTrain = function(trainType, amount)
	AwakenRE:FireServer("Train", trainType, amount or 1)
end

-- Exemplo de uso no seu jogo:
-- _G.AwakenTrain("Martial", 2)      -- soco/chute
-- _G.AwakenTrain("Strength", 2)     -- flexão
-- _G.AwakenTrain("Endurance", 1)    -- corrida
-- _G.AwakenTrain("Breathing", 1)    -- meditação
-- _G.AwakenTrain("Flexibility", 1)  -- alongamento

-- =========================
-- Button Awaken
-- =========================
awakenBtn.MouseButton1Click:Connect(function()
	if not lastState then return end
	if lastState.Awakened then return end
	AwakenRE:FireServer("Awaken")
end)

-- =========================
-- Remote events
-- =========================
AwakenRE.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "State" then
		applyState(a)
		return
	end

	if kind == "AwakenResult" then
		local ok = a
		local reason = b
		local st = c
		if st then applyState(st) end

		if ok then
			-- ok
		else
			if reason == "not_enough_potential" then
				resLbl.Text = "Ainda falta treino. Aumente seu Potential."
			elseif reason == "already_awakened" then
				resLbl.Text = "Você já despertou."
			else
				resLbl.Text = "Falha no Awaken: "..tostring(reason)
			end
		end
		return
	end
end)

-- =========================
-- Init
-- =========================
AwakenRE:FireServer("RequestState")
