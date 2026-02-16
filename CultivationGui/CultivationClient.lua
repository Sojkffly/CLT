-- StarterGui/CultivationGui/CultivationClient (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = script.Parent
gui.ResetOnSpawn = false
gui.DisplayOrder = 60

local AwakeningRF = ReplicatedStorage:WaitForChild("AwakeningRF")

-- =========================
-- UIScale (resoluções menores)
-- =========================
local uiScale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
uiScale.Parent = gui

local function updateScale()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local v = cam.ViewportSize
	-- Base 1920x1080
	local s = math.min(v.X / 1920, v.Y / 1080)
	uiScale.Scale = math.clamp(s, 0.65, 1)
end

updateScale()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(updateScale)
end)
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- =========================
-- UI helpers (mesmo estilo do inventário)
-- =========================
local function mk(className, props, parent)
	local o = Instance.new(className)
	for k,v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local COLORS = {
	panel = Color3.fromRGB(235, 225, 200),
	panel2 = Color3.fromRGB(230, 220, 195),
	slot = Color3.fromRGB(215, 205, 180),
	slotHover = Color3.fromRGB(205, 215, 205),
	stroke = Color3.fromRGB(140, 120, 90),
	text = Color3.fromRGB(70, 60, 40),
	text2 = Color3.fromRGB(95, 85, 65),
	close = Color3.fromRGB(210, 170, 150),
	ok = Color3.fromRGB(150, 190, 155),
}

local function makePanel(parent, size, pos)
	local f = mk("Frame", {
		Size = size,
		Position = pos,
		BackgroundColor3 = COLORS.panel,
	}, parent)
	mk("UICorner", {CornerRadius = UDim.new(0,10)}, f)
	mk("UIStroke", {Thickness = 2, Color = COLORS.stroke}, f)
	return f
end

local function makeBtn(parent, size, pos, text, bg)
	local b = mk("TextButton", {
		Size = size,
		Position = pos,
		BackgroundColor3 = bg or COLORS.slot,
		Text = text or "",
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = COLORS.text,
		AutoButtonColor = true,
	}, parent)
	mk("UICorner", {CornerRadius = UDim.new(0,10)}, b)
	mk("UIStroke", {Thickness = 2, Color = COLORS.stroke}, b)
	return b
end

local function makeStatLine(parent, text)
	local row = mk("Frame", {Size = UDim2.new(1,0,0,22), BackgroundTransparency = 1}, parent)
	local lbl = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1,0,1,0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text or "",
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = COLORS.text2,
	}, row)
	return lbl
end

-- =========================
-- Helpers p/ achar outras UIs por BindableEvent
-- =========================
local function findGuiWithEvent(eventName)
	local pg = player:WaitForChild("PlayerGui")
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") then
			local ev = g:FindFirstChild(eventName)
			if ev and ev:IsA("BindableEvent") then
				return g, ev
			end
		end
	end
	return nil, nil
end

-- =========================
-- Build UI
-- =========================
local main = makePanel(gui, UDim2.fromOffset(860, 500), UDim2.fromScale(0.5, 0.5))
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Visible = false

local header = mk("Frame", {Size = UDim2.new(1,0,0,46), BackgroundTransparency = 1}, main)

local invBtn = makeBtn(header, UDim2.fromOffset(140, 34), UDim2.fromOffset(16, 6), "Inventory", COLORS.slot)

local titlePlate = makePanel(header, UDim2.fromOffset(300, 34), UDim2.new(0.5, 0, 0, 6))
titlePlate.AnchorPoint = Vector2.new(0.5, 0)
titlePlate.BackgroundColor3 = COLORS.panel2
mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1,0,1,0),
	Text = "Cultivation",
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = COLORS.text,
}, titlePlate)

local closeBtn = mk("TextButton", {
	Size = UDim2.fromOffset(36,36),
	Position = UDim2.new(1,-52,0,6),
	BackgroundColor3 = COLORS.close,
	Text = "X",
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1,1,1),
}, header)
mk("UICorner", {CornerRadius = UDim.new(0,10)}, closeBtn)

-- Left card
local left = makePanel(main, UDim2.fromOffset(320, 420), UDim2.fromOffset(16, 62))
left.BackgroundColor3 = COLORS.panel2

mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1,-20,0,24),
	Position = UDim2.fromOffset(10, 10),
	Text = "Overview",
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = COLORS.text,
}, left)

local overviewList = mk("Frame", {
	Size = UDim2.new(1,-20,1,-48),
	Position = UDim2.fromOffset(10, 38),
	BackgroundTransparency = 1
}, left)

mk("UIListLayout", {Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder}, overviewList)

-- Right card
local right = makePanel(main, UDim2.fromOffset(490, 420), UDim2.fromOffset(354, 62))
right.BackgroundColor3 = COLORS.panel2

mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1,-20,0,24),
	Position = UDim2.fromOffset(10, 10),
	Text = "Stats",
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = COLORS.text,
}, right)

-- ? Layout corrigido: statsList em cima, infoBox no meio, botões embaixo (sem overlap)
local statsList = mk("Frame", {
	Size = UDim2.new(1,-20,0,220),
	Position = UDim2.fromOffset(10, 38),
	BackgroundTransparency = 1
}, right)
mk("UIListLayout", {Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder}, statsList)

local infoBox = makePanel(right, UDim2.new(1,0,0,64), UDim2.new(0,0,1,-160))
infoBox.BackgroundColor3 = COLORS.panel

local infoLbl = mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1,-10,1,-10),
	Position = UDim2.fromOffset(5,5),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "Ready.",
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextColor3 = COLORS.text2,
}, infoBox)

local buttonsArea = mk("Frame", {
	Size = UDim2.new(1,0,0,80),
	Position = UDim2.new(0,0,1,-90),
	BackgroundTransparency = 1
}, right)

local awakenBtn = makeBtn(buttonsArea, UDim2.fromOffset(220, 56), UDim2.fromOffset(10, 10), "Awaken", COLORS.ok)

local chooseFrame = mk("Frame", {
	Size = UDim2.new(1,-20,0,56),
	Position = UDim2.fromOffset(10, 10),
	BackgroundTransparency = 1
}, buttonsArea)

local qiBtn = makeBtn(chooseFrame, UDim2.new(0.5, -6, 1, 0), UDim2.fromOffset(0, 0), "Path: Qi", COLORS.slotHover)
local bodyBtn = makeBtn(chooseFrame, UDim2.new(0.5, -6, 1, 0), UDim2.new(0.5, 6, 0, 0), "Path: Body", COLORS.slotHover)

-- Labels
local L = {}
L.Level = makeStatLine(overviewList, "Level: ?")
L.Realm = makeStatLine(overviewList, "Realm: ?")
L.Exp = makeStatLine(overviewList, "Exp: ?")
L.Gold = makeStatLine(overviewList, "Gold: ?")
L.Path = makeStatLine(overviewList, "Path: ?")
L.Element = makeStatLine(overviewList, "Element: ?")
L.HasDantian = makeStatLine(overviewList, "HasDantian: ?")
L.DantianTier = makeStatLine(overviewList, "DantianTier: ?")
L.Prep = makeStatLine(overviewList, "Prep: ?")
L.BodyApt = makeStatLine(overviewList, "BodyApt: ?")
L.MindApt = makeStatLine(overviewList, "MindApt: ?")
L.SpiritApt = makeStatLine(overviewList, "SpiritApt: ?")

L.HP = makeStatLine(statsList, "HP: ? / ?")
L.Qi = makeStatLine(statsList, "Qi: ? / ?")
L.QiRegen = makeStatLine(statsList, "QiRegen: ?")
L.ATK = makeStatLine(statsList, "ATK: ?")
L.DEF = makeStatLine(statsList, "DEF: ?")
L.Crit = makeStatLine(statsList, "Crit: ?")
L.Dodge = makeStatLine(statsList, "Dodge: ?")
L.Precision = makeStatLine(statsList, "Precision: ?")
L.MoveSpeed = makeStatLine(statsList, "MoveSpeed: ?")

-- Data
local ATTRS = {
	"Level","Realm","Exp","Gold",
	"HP","MaxHP","ATK","DEF","Crit","Dodge","Precision","MoveSpeed",
	"Qi","MaxQi","QiRegen",
	"BodyApt","MindApt","SpiritApt","Prep","HasDantian","DantianTier","Element","Path",
}

local function getA(name) return player:GetAttribute(name) end
local function fmt(v)
	if v == nil then return "?" end
	if type(v) == "number" then return tostring(math.floor(v * 100) / 100) end
	return tostring(v)
end

local function applyVisibility()
	local has = (getA("HasDantian") == true)
	local path = getA("Path") or "Mortal"

	awakenBtn.Visible = (not has)
	chooseFrame.Visible = (has and path == "Mortal")

	if path ~= "Mortal" then
		chooseFrame.Visible = false
	end
end

local function refreshText()
	L.Level.Text = "Level: " .. fmt(getA("Level"))
	L.Realm.Text = "Realm: " .. fmt(getA("Realm"))
	L.Exp.Text = "Exp: " .. fmt(getA("Exp"))
	L.Gold.Text = "Gold: " .. fmt(getA("Gold"))

	local path = getA("Path") or "Mortal"
	L.Path.Text = "Path: " .. fmt(path)
	L.Element.Text = "Element: " .. fmt(getA("Element"))
	L.HasDantian.Text = "HasDantian: " .. fmt(getA("HasDantian"))
	L.DantianTier.Text = "DantianTier: " .. fmt(getA("DantianTier"))

	L.Prep.Text = "Prep: " .. fmt(getA("Prep"))
	L.BodyApt.Text = "BodyApt: " .. fmt(getA("BodyApt"))
	L.MindApt.Text = "MindApt: " .. fmt(getA("MindApt"))
	L.SpiritApt.Text = "SpiritApt: " .. fmt(getA("SpiritApt"))

	L.HP.Text = ("HP: %s / %s"):format(fmt(getA("HP")), fmt(getA("MaxHP")))
	L.Qi.Text = ("Qi: %s / %s"):format(fmt(getA("Qi")), fmt(getA("MaxQi")))
	L.QiRegen.Text = "QiRegen: " .. fmt(getA("QiRegen"))

	L.ATK.Text = "ATK: " .. fmt(getA("ATK"))
	L.DEF.Text = "DEF: " .. fmt(getA("DEF"))
	L.Crit.Text = "Crit: " .. fmt(getA("Crit"))
	L.Dodge.Text = "Dodge: " .. fmt(getA("Dodge"))
	L.Precision.Text = "Precision: " .. fmt(getA("Precision"))
	L.MoveSpeed.Text = "MoveSpeed: " .. fmt(getA("MoveSpeed"))

	applyVisibility()
end

local function pullState()
	infoLbl.Text = "Sync..."
	local ok = pcall(function()
		return AwakeningRF:InvokeServer("GetState")
	end)
	if not ok then
		infoLbl.Text = "Erro no GetState."
		return
	end
	infoLbl.Text = "Ready."
	refreshText()
end

-- Open/Close + API
local function setOpen(on)
	main.Visible = on
	if on then
		pullState()
		refreshText()
	end
end

local toggleCult = gui:FindFirstChild("ToggleCultivation")
if not toggleCult then
	toggleCult = Instance.new("BindableEvent")
	toggleCult.Name = "ToggleCultivation"
	toggleCult.Parent = gui
end

toggleCult.Event:Connect(function(forceState)
	if typeof(forceState) == "boolean" then
		setOpen(forceState)
	else
		setOpen(not main.Visible)
	end
end)

-- Buttons
closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)

invBtn.MouseButton1Click:Connect(function()
	setOpen(false)
	local _, invEv = findGuiWithEvent("ToggleInventory")
	if invEv then invEv:Fire() end
end)

awakenBtn.MouseButton1Click:Connect(function()
	infoLbl.Text = "Awakening..."
	local ok = pcall(function()
		return AwakeningRF:InvokeServer("DoAwaken", {BonusPrep = 0})
	end)
	infoLbl.Text = ok and "Done." or "Falhou."
	pullState()
end)

qiBtn.MouseButton1Click:Connect(function()
	infoLbl.Text = "Choosing Qi..."
	local ok = pcall(function()
		AwakeningRF:InvokeServer("ChoosePath", {Path = "Qi"})
	end)
	infoLbl.Text = ok and "Done." or "Falhou."
	pullState()
end)

bodyBtn.MouseButton1Click:Connect(function()
	infoLbl.Text = "Choosing Body..."
	local ok = pcall(function()
		AwakeningRF:InvokeServer("ChoosePath", {Path = "Body"})
	end)
	infoLbl.Text = ok and "Done." or "Falhou."
	pullState()
end)

for _, a in ipairs(ATTRS) do
	player:GetAttributeChangedSignal(a):Connect(function()
		if main.Visible then refreshText() end
	end)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == Enum.KeyCode.K then
		setOpen(not main.Visible)
	end
end)

pullState()
refreshText()
