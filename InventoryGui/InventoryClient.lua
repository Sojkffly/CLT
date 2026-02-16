-- InventoryClient (LocalScript dentro do ScreenGui InventoryGui)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local InventoryRE = ReplicatedStorage:WaitForChild("InventoryRE")

local gui = script.Parent
gui.ResetOnSpawn = false

-- =========================
-- UIScale (resoluções menores)
-- =========================
local uiScale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
uiScale.Parent = gui

local function updateScale()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local v = cam.ViewportSize
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
-- Drag state
-- =========================
local drag = {
	active = false,
	uid = nil,
	fromKind = nil,
	fromSlot = nil,
	fromIndex = nil,
	ghost = nil,
}

-- =========================
-- UI helpers
-- =========================
local function mk(className, props, parent)
	local o = Instance.new(className)
	for k, v in pairs(props) do
		o[k] = v
	end
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
}

local function makePanel(parent, size, pos)
	local f = mk("Frame", {
		Size = size,
		Position = pos,
		BackgroundColor3 = COLORS.panel,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, f)
	mk("UIStroke", { Thickness = 2, Color = COLORS.stroke }, f)
	return f
end

local function makeSlotButton(parent, size, labelTop, tagBottom)
	local b = mk("TextButton", {
		Size = size,
		BackgroundColor3 = COLORS.slot,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		AutoButtonColor = false,
	}, parent)

	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	mk("UIStroke", { Thickness = 2, Color = COLORS.stroke }, b)

	mk("TextLabel", {
		Name = "Top",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(4, 3),
		Text = labelTop or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text2,
	}, b)

	mk("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = COLORS.text,
	}, b)

	mk("TextLabel", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.new(0, 4, 1, -18),
		Text = tagBottom or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.text2,
	}, b)

	return b
end

-- =========================
-- Build UI
-- =========================
local main = makePanel(gui, UDim2.fromOffset(860, 500), UDim2.fromScale(0.5, 0.5))
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Visible = false
main.ClipsDescendants = true

local header = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
}, main)

local namePlate = makePanel(header, UDim2.fromOffset(260, 34), UDim2.fromOffset(16, 6))
namePlate.BackgroundColor3 = COLORS.panel2

mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	Text = player.Name,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = COLORS.text,
}, namePlate)

local closeBtn = mk("TextButton", {
	Size = UDim2.fromOffset(36, 36),
	Position = UDim2.new(1, -52, 0, 6),
	BackgroundColor3 = COLORS.close,
	Text = "X",
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
}, header)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, closeBtn)

local cultBtn = mk("TextButton", {
	Size = UDim2.fromOffset(140, 34),
	Position = UDim2.fromOffset(16 + 260 + 12, 6),
	BackgroundColor3 = COLORS.slot,
	Text = "Cultivation",
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = COLORS.text,
	AutoButtonColor = true,
}, header)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, cultBtn)
mk("UIStroke", { Thickness = 2, Color = COLORS.stroke }, cultBtn)

-- Left equipment
local leftCol = mk("Frame", {
	Size = UDim2.fromOffset(150, 380),
	Position = UDim2.fromOffset(16, 62),
	BackgroundTransparency = 1,
}, main)

local eqSlots = {}
local function addEqSlot(slotName, displayName, y)
	local b = makeSlotButton(leftCol, UDim2.fromOffset(120, 60), displayName, "")
	b.Position = UDim2.fromOffset(0, y)
	b.Name = "EQ_" .. slotName
	b:SetAttribute("SlotKind", "Equip")
	b:SetAttribute("SlotName", slotName)
	eqSlots[slotName] = b
	return b
end

addEqSlot("Shirt", "Coat", 0)
addEqSlot("Mantle", "Mantle", 70)
addEqSlot("Pants", "Pants", 140)
addEqSlot("Weapon", "Weapon", 210)
addEqSlot("Accessory", "Accessory", 280)

-- Center / Viewport
local center = makePanel(main, UDim2.fromOffset(270, 320), UDim2.fromOffset(176, 62))
center.BackgroundColor3 = COLORS.panel2

local viewport = mk("ViewportFrame", {
	Name = "CharacterViewport",
	Size = UDim2.new(1, -20, 1, -20),
	Position = UDim2.fromOffset(10, 20),
	BackgroundTransparency = 1,
}, center)

local leftArrow = mk("TextButton", {
	Name = "RotateLeft",
	Size = UDim2.fromOffset(34, 34),
	Position = UDim2.fromOffset(12, 12),
	BackgroundColor3 = COLORS.slot,
	Text = "?",
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = COLORS.text,
	AutoButtonColor = true,
}, center)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, leftArrow)
mk("UIStroke", { Thickness = 2, Color = COLORS.stroke }, leftArrow)

local rightArrow = mk("TextButton", {
	Name = "RotateRight",
	Size = UDim2.fromOffset(34, 34),
	Position = UDim2.new(1, -46, 0, 12),
	BackgroundColor3 = COLORS.slot,
	Text = "?",
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = COLORS.text,
	AutoButtonColor = true,
}, center)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, rightArrow)
mk("UIStroke", { Thickness = 2, Color = COLORS.stroke }, rightArrow)

-- Artifacts
local artPanel = mk("Frame", {
	Size = UDim2.fromOffset(170, 220),
	Position = UDim2.fromOffset(460, 62),
	BackgroundTransparency = 1,
}, main)

mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 20),
	Text = "Artifacts",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = COLORS.text,
}, artPanel)

local artSlots = {}
for i = 1, 6 do
	local col = ((i - 1) % 2)
	local row = math.floor((i - 1) / 2)
	local b = makeSlotButton(artPanel, UDim2.fromOffset(70, 60), "", "Artifact " .. i)
	b.Position = UDim2.fromOffset(col * 78, 26 + row * 66)
	b.Name = "Artifact" .. i
	b:SetAttribute("SlotKind", "Equip")
	b:SetAttribute("SlotName", "Artifact")
	b:SetAttribute("SlotIndex", i)
	artSlots[i] = b
end

-- Talismans
local talPanel = mk("Frame", {
	Size = UDim2.fromOffset(470, 98),
	Position = UDim2.fromOffset(176, 444 - 70),
	BackgroundTransparency = 1,
}, main)

mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 20),
	Text = "Talismans",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = COLORS.text,
}, talPanel)

local talSlots = {}
for i = 1, 6 do
	local b = makeSlotButton(talPanel, UDim2.fromOffset(70, 60), "", "Talisman " .. i)
	b.Position = UDim2.fromOffset((i - 1) * 78, 26)
	b.Name = "Talisman" .. i
	b:SetAttribute("SlotKind", "Equip")
	b:SetAttribute("SlotName", "Talisman")
	b:SetAttribute("SlotIndex", i)
	talSlots[i] = b
end

-- Right side
local right = mk("Frame", {
	Size = UDim2.fromOffset(210, 380),
	Position = UDim2.fromOffset(640, 62),
	BackgroundTransparency = 1,
}, main)

mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 20),
	Text = "Items & Equipment",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = COLORS.text,
}, right)

local bagGrid = mk("Frame", {
	Size = UDim2.new(1, 0, 1, -110),
	Position = UDim2.fromOffset(0, 26),
	BackgroundTransparency = 1,
}, right)
bagGrid.ClipsDescendants = true

mk("UIGridLayout", {
	CellSize = UDim2.fromOffset(48, 48),
	CellPadding = UDim2.fromOffset(6, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, bagGrid)

local BAG_SLOTS = 24
local bagButtons = {}
for i = 1, BAG_SLOTS do
	local b = makeSlotButton(bagGrid, UDim2.fromOffset(40, 40), "", "")
	b.Name = "Bag" .. i
	b:SetAttribute("SlotKind", "Bag")
	b:SetAttribute("BagIndex", i)
	bagButtons[i] = b
end

local pouch = makePanel(right, UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 1, -78))
pouch.BackgroundColor3 = COLORS.panel2

local pouchLbl = mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	Text = "Spirit Stones: 0",
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = COLORS.text,
}, pouch)

local statsBox = makePanel(right, UDim2.new(1, 0, 0, 64), UDim2.new(0, 0, 1, -30))
statsBox.BackgroundColor3 = COLORS.panel2

local statsLbl = mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -10, 1, -10),
	Position = UDim2.fromOffset(5, 5),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "Hover an item\nfor details...",
	TextScaled = true,
	Font = Enum.Font.Gotham,
	TextColor3 = COLORS.text2,
}, statsBox)

-- =========================
-- Tooltip
-- =========================
local tooltip = makePanel(gui, UDim2.fromOffset(240, 140), UDim2.fromOffset(0, 0))
tooltip.Visible = false
tooltip.BackgroundColor3 = Color3.fromRGB(30, 28, 24)
tooltip.ZIndex = 200

local tipText = mk("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -12, 1, -12),
	Position = UDim2.fromOffset(6, 6),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(245, 245, 245),
	ZIndex = 200,
}, tooltip)

local function formatStats(stats)
	if type(stats) ~= "table" then return "" end
	local lines = {}
	for k, v in pairs(stats) do
		if type(v) == "number" then
			table.insert(lines, string.format("%s: %s", k, tostring(v)))
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

-- =========================
-- Inventory State
-- =========================
local state = { Equipped = nil, BagItems = {}, Pouch = {}, ItemsByUid = {} }
local selectedUid = nil

local function rebuildIndex()
	state.ItemsByUid = {}
	for _, it in ipairs(state.BagItems or {}) do
		state.ItemsByUid[it.uid] = it
	end
end

local function setBtnUid(btn, uid)
	btn:SetAttribute("UID", uid)
	btn.Icon.Text = uid and "?" or ""
	btn.Bottom.Text = uid and uid:sub(1, 6) or ""
end

local function refresh()
	rebuildIndex()
	pouchLbl.Text = ("Spirit Stones: %d"):format(tonumber(state.Pouch.SpiritStones) or 0)

	local eq = state.Equipped or {}
	setBtnUid(eqSlots.Shirt, eq.Shirt)
	setBtnUid(eqSlots.Pants, eq.Pants)
	setBtnUid(eqSlots.Mantle, eq.Mantle)
	setBtnUid(eqSlots.Weapon, eq.Weapon)
	setBtnUid(eqSlots.Accessory, eq.Accessory)

	for i = 1, 6 do
		setBtnUid(talSlots[i], eq.Talismans and eq.Talismans[i])
		setBtnUid(artSlots[i], eq.Artifacts and eq.Artifacts[i])
	end

	for i = 1, BAG_SLOTS do
		local btn = bagButtons[i]
		local it = state.BagItems[i]
		btn:SetAttribute("UID", it and it.uid or nil)
		btn.Icon.Text = it and it.type:sub(1, 1) or ""
		btn.Top.Text = it and it.type or ""
		btn.Bottom.Text = it and it.defId or ""
		btn.BackgroundColor3 = (it and it.uid == selectedUid) and COLORS.slotHover or COLORS.slot
	end
end

local function requestState()
	InventoryRE:FireServer("RequestState")
end

InventoryRE.OnClientEvent:Connect(function(kind, payload)
	if kind ~= "State" then return end
	state.Equipped = payload.Equipped
	state.BagItems = payload.BagItems or {}
	state.Pouch = payload.Pouch or {}
	selectedUid = nil
	refresh()
end)

-- =========================
-- Tooltip hover
-- =========================
local function showTooltip(uid)
	local it = uid and state.ItemsByUid[uid]
	if not it then
		tooltip.Visible = false
		statsLbl.Text = "Hover an item\nfor details..."
		return
	end
	local statsText = formatStats(it.stats)
	local headerTxt = string.format("%s (%s)\n%s\n\n", it.defId or "Item", it.type or "?", uid:sub(1, 8))
	tipText.Text = headerTxt .. (statsText ~= "" and statsText or "No stats")
	statsLbl.Text = (it.defId or "Item") .. "\n" .. (it.type or "?")
	tooltip.Visible = true
end

local function bindHover(btn)
	btn.MouseEnter:Connect(function()
		local uid = btn:GetAttribute("UID")
		if uid then showTooltip(uid) end
	end)
	btn.MouseLeave:Connect(function()
		if not drag.active then
			tooltip.Visible = false
			statsLbl.Text = "Hover an item\nfor details..."
		end
	end)
end

-- =========================
-- Drag & Drop
-- =========================
local function beginDrag(uid, fromKind, fromSlot, fromIndex)
	if not uid then return end
	drag.active = true
	drag.uid = uid
	drag.fromKind = fromKind
	drag.fromSlot = fromSlot
	drag.fromIndex = fromIndex

	local g = makePanel(gui, UDim2.fromOffset(52, 52), UDim2.fromOffset(0, 0))
	g.BackgroundColor3 = Color3.fromRGB(60, 55, 45)
	g.Visible = true
	g.ZIndex = 210

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "?",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 210,
	}, g)

	drag.ghost = g
	showTooltip(uid)
end

local function endDrag()
	if drag.ghost then drag.ghost:Destroy() end
	drag.ghost = nil
	drag.active = false
	drag.uid = nil
	drag.fromKind = nil
	drag.fromSlot = nil
	drag.fromIndex = nil
end

local function getDropTarget()
	local mousePos = UserInputService:GetMouseLocation()
	local objs = GuiService:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	for _, o in ipairs(objs) do
		local cur = o
		for _ = 1, 7 do
			if not cur then break end
			local kind = cur:GetAttribute("SlotKind")
			if kind then return cur, kind end
			cur = cur.Parent
		end
	end
	return nil, nil
end

local function doEquipTo(targetBtn)
	local slotName = targetBtn:GetAttribute("SlotName")
	local slotIndex = targetBtn:GetAttribute("SlotIndex")
	if not slotName then return end

	if slotName == "Talisman" then
		InventoryRE:FireServer("Equip", { slot = "Talisman", index = slotIndex, uid = drag.uid })
	elseif slotName == "Artifact" then
		InventoryRE:FireServer("Equip", { slot = "Artifact", index = slotIndex, uid = drag.uid })
	else
		InventoryRE:FireServer("Equip", { slot = slotName, uid = drag.uid })
	end
end

local function doUnequipFrom(sourceSlot, sourceIndex)
	if sourceSlot == "Talisman" then
		InventoryRE:FireServer("Unequip", { slot = "Talisman", index = sourceIndex })
	elseif sourceSlot == "Artifact" then
		InventoryRE:FireServer("Unequip", { slot = "Artifact", index = sourceIndex })
	else
		InventoryRE:FireServer("Unequip", { slot = sourceSlot })
	end
end

local function bindDrag(btn, fromKind, fromSlot, fromIndexFunc)
	btn.MouseButton1Down:Connect(function()
		local uid = btn:GetAttribute("UID")
		if not uid then
			if fromKind == "Bag" then
				selectedUid = nil
				refresh()
			end
			return
		end

		if fromKind == "Bag" then
			selectedUid = uid
			refresh()
		end

		local idx = fromIndexFunc and fromIndexFunc() or nil
		beginDrag(uid, fromKind, fromSlot, idx)
	end)

	btn.MouseButton1Up:Connect(function()
		if not drag.active then return end

		local targetBtn, targetKind = getDropTarget()

		if targetKind == "Equip" and targetBtn then
			if drag.fromKind == "Equip" then
				doUnequipFrom(drag.fromSlot, drag.fromIndex)
				doEquipTo(targetBtn)
			else
				doEquipTo(targetBtn)
			end
		elseif targetKind == "Bag" and targetBtn then
			if drag.fromKind == "Equip" then
				doUnequipFrom(drag.fromSlot, drag.fromIndex)
			end
		end

		endDrag()
	end)

	bindHover(btn)
end

-- =========================
-- Viewport + Camera
-- =========================
local viewportCam = Instance.new("Camera")
viewportCam.Name = "ViewportCamera"
viewport.CurrentCamera = viewportCam
viewportCam.Parent = viewport

local viewModel
local yaw = 0

local function getModelBounds(model)
	local cf, size = model:GetBoundingBox()
	return cf, size
end

local function positionCamera()
	if not viewModel then return end

	local bbCf, size = getModelBounds(viewModel)

	local focusPart =
		viewModel:FindFirstChild("UpperTorso")
		or viewModel:FindFirstChild("HumanoidRootPart")
		or viewModel:FindFirstChild("Torso")

	local focusPos = (focusPart and focusPart:IsA("BasePart")) and focusPart.Position or bbCf.Position

	local radius = math.max(size.X, size.Y, size.Z) * 1.15
	local FOCUS_Y = size.Y * 0.18

	local OFFSET_SIDE = 0.0
	local OFFSET_UP = 1.0
	local OFFSET_FORWARD = 2.0

	focusPos = focusPos + Vector3.new(0, FOCUS_Y, 0)

	local yawRot = CFrame.Angles(0, yaw, 0)
	local camPos = focusPos - (yawRot.LookVector * radius)

	camPos += yawRot.RightVector * OFFSET_SIDE
	camPos += Vector3.new(0, OFFSET_UP, 0)
	camPos += yawRot.LookVector * OFFSET_FORWARD

	viewportCam.CFrame = CFrame.lookAt(camPos, focusPos)
end

-- =========================
-- ViewModel (clone do character) - SEM NIL
-- =========================
local function ensureCharacter()
	local char = player.Character
	if char then return char end
	return player.CharacterAdded:Wait()
end

local function ensureViewModel()
	-- já existe e está renderizando
	if viewModel and viewModel.Parent == viewport then
		return
	end

	-- já existe mas estava guardado (Parent=nil)
	if viewModel and viewModel.Parent == nil then
		viewModel.Parent = viewport
		positionCamera()
		return
	end

	local char = ensureCharacter()
	if not char then return end

	-- tenta clone com Archivable (muito comum falhar sem isso)
	local cloned
	local okClone = pcall(function()
		local old = char.Archivable
		char.Archivable = true
		cloned = char:Clone()
		char.Archivable = old
	end)

	if not okClone or not cloned then
		-- fallback confiável
		local okRig, rig = pcall(function()
			return Players:CreateHumanoidModelFromUserId(player.UserId)
		end)
		if not okRig or not rig then
			warn("ensureViewModel: falhou Clone e falhou CreateHumanoidModelFromUserId")
			return
		end
		cloned = rig
	end

	viewModel = cloned
	viewModel.Name = "ViewportCharacter"
	viewModel.Parent = viewport

	-- remove scripts/localscripts (inclui Animate)
	for _, d in ipairs(viewModel:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end

	-- sem colisão
	for _, d in ipairs(viewModel:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			-- ? NÃO ANCORE AQUI
		end
	end

	-- ? ancore SOMENTE o HumanoidRootPart pra não sair do lugar
	local hrp = viewModel:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.Anchored = true
	end

	-- centraliza 1x
	local bbCf = select(1, viewModel:GetBoundingBox())
	viewModel:PivotTo(viewModel:GetPivot() * CFrame.new(-bbCf.Position))

	positionCamera()
end

-- =========================
-- MIRRORING pelo Animator (pega ataques)
-- =========================
-- ===== Animation Mirroring (robusto) =====
local animConnHum
local animConnAnim
local animSyncConn

local viewportAnimator
local trackMap = {} -- [sourceTrack] = viewportTrack

local function safeDisconnect(c) if c then c:Disconnect() end end

local function getSourceHumanoidAndAnimator()
	local char = player.Character
	if not char then return nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil, nil end
	local anim = hum:FindFirstChildOfClass("Animator")
	return hum, anim
end

local function ensureViewportAnimator()
	if not viewModel then return nil end
	local hum = viewModel:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local anim = hum:FindFirstChildOfClass("Animator")
	if not anim then
		anim = Instance.new("Animator")
		anim.Parent = hum
	end
	return anim
end

local function getAnimIdFromTrack(tr)
	local id = ""
	pcall(function()
		if tr.Animation and tr.Animation.AnimationId then
			id = tr.Animation.AnimationId
		end
	end)
	return id
end

local function mirrorTrack(sourceTrack)
	if not viewportAnimator or not sourceTrack then return end
	if trackMap[sourceTrack] and trackMap[sourceTrack].IsPlaying then return end

	local animId = getAnimIdFromTrack(sourceTrack)
	if animId == "" then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	anim.Parent = viewportAnimator -- ? também parentear aqui ajuda

	local vTrack
	local ok = pcall(function()
		vTrack = viewportAnimator:LoadAnimation(anim)
	end)
	if not ok or not vTrack then return end

	pcall(function() vTrack.Priority = sourceTrack.Priority end)

	trackMap[sourceTrack] = vTrack
	vTrack:Play(0, 1, sourceTrack.Speed)
	pcall(function() vTrack:AdjustWeight(sourceTrack.WeightCurrent, 0) end)
	pcall(function() vTrack.TimePosition = sourceTrack.TimePosition end)

	sourceTrack.Stopped:Connect(function()
		local t = trackMap[sourceTrack]
		if t then
			pcall(function() t:Stop(0.08) end)
			trackMap[sourceTrack] = nil
		end
	end)
end

local function mirrorAllPlaying(hum, animator)
	local ok1, list1 = pcall(function() return hum:GetPlayingAnimationTracks() end)
	if ok1 and list1 then
		for _, tr in ipairs(list1) do mirrorTrack(tr) end
	end

	if animator then
		local ok2, list2 = pcall(function() return animator:GetPlayingAnimationTracks() end)
		if ok2 and list2 then
			for _, tr in ipairs(list2) do mirrorTrack(tr) end
		end
	end
end

function stopAnimationMirroring()
	safeDisconnect(animConnHum)
	safeDisconnect(animConnAnim)
	safeDisconnect(animSyncConn)
	animConnHum, animConnAnim, animSyncConn = nil, nil, nil
	trackMap = {}
	viewportAnimator = nil
end

function startAnimationMirroring()
	stopAnimationMirroring()
	if not viewModel then return end

	viewportAnimator = ensureViewportAnimator()
	if not viewportAnimator then return end

	local hum, srcAnimator = getSourceHumanoidAndAnimator()
	if not hum then return end

	mirrorAllPlaying(hum, srcAnimator)

	animConnHum = hum.AnimationPlayed:Connect(mirrorTrack)
	if srcAnimator then
		animConnAnim = srcAnimator.AnimationPlayed:Connect(mirrorTrack)
	end

	animSyncConn = RunService.RenderStepped:Connect(function()
		for src, vt in pairs(trackMap) do
			if src and vt and src.IsPlaying and vt.IsPlaying then
				pcall(function()
					vt:AdjustSpeed(src.Speed)
					vt:AdjustWeight(src.WeightCurrent, 0)
					vt.TimePosition = src.TimePosition
				end)
			end
		end
	end)
end


-- =========================
-- Rotação segurando click
-- =========================
local rotateLeftHeld = false
local rotateRightHeld = false
local ROTATE_SPEED = math.rad(120)

local function stopRotate()
	rotateLeftHeld = false
	rotateRightHeld = false
end

leftArrow.MouseButton1Down:Connect(function() rotateLeftHeld = true end)
leftArrow.MouseButton1Up:Connect(stopRotate)
leftArrow.MouseLeave:Connect(stopRotate)

rightArrow.MouseButton1Down:Connect(function() rotateRightHeld = true end)
rightArrow.MouseButton1Up:Connect(stopRotate)
rightArrow.MouseLeave:Connect(stopRotate)

-- =========================
-- Loop único: rotate + clamp tooltip/ghost
-- =========================
RunService.RenderStepped:Connect(function(dt)
	-- rotate
	if main.Visible and viewModel then
		if rotateLeftHeld then
			yaw -= ROTATE_SPEED * dt
			positionCamera()
		elseif rotateRightHeld then
			yaw += ROTATE_SPEED * dt
			positionCamera()
		end
	end

	-- clamp tooltip/ghost
	local cam = Workspace.CurrentCamera
	if not cam then return end

	local screen = cam.ViewportSize
	local mousePos = UserInputService:GetMouseLocation()

	if tooltip.Visible then
		local size = tooltip.AbsoluteSize
		local x = math.clamp(mousePos.X + 14, 0, screen.X - size.X)
		local y = math.clamp(mousePos.Y + 14, 0, screen.Y - size.Y)
		tooltip.Position = UDim2.fromOffset(x, y)
	end

	if drag.active and drag.ghost then
		local gsize = drag.ghost.AbsoluteSize
		local gx = math.clamp(mousePos.X - gsize.X / 2, 0, screen.X - gsize.X)
		local gy = math.clamp(mousePos.Y - gsize.Y / 2, 0, screen.Y - gsize.Y)
		drag.ghost.Position = UDim2.fromOffset(gx, gy)
	end
end)

-- =========================
-- Bind slots
-- =========================
bindDrag(eqSlots.Shirt, "Equip", "Shirt")
bindDrag(eqSlots.Pants, "Equip", "Pants")
bindDrag(eqSlots.Mantle, "Equip", "Mantle")
bindDrag(eqSlots.Weapon, "Equip", "Weapon")
bindDrag(eqSlots.Accessory, "Equip", "Accessory")

for i = 1, 6 do
	bindDrag(talSlots[i], "Equip", "Talisman", function() return i end)
	bindDrag(artSlots[i], "Equip", "Artifact", function() return i end)
end

for i = 1, BAG_SLOTS do
	bindDrag(bagButtons[i], "Bag", nil, function() return i end)
end

-- =========================
-- Open/Close
-- =========================
local function setOpen(on)
	main.Visible = on

	if on then
		requestState()

		ensureViewModel()
		positionCamera()

		startAnimationMirroring()
	else
		stopAnimationMirroring()

		-- opcional: guardar pra não renderizar
		if viewModel then
			viewModel.Parent = nil
		end
	end
end

local toggleEvent = gui:FindFirstChild("ToggleInventory")
if not toggleEvent then
	toggleEvent = Instance.new("BindableEvent")
	toggleEvent.Name = "ToggleInventory"
	toggleEvent.Parent = gui
end

toggleEvent.Event:Connect(function(forceState)
	if typeof(forceState) == "boolean" then
		setOpen(forceState)
	else
		setOpen(not main.Visible)
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)

-- abre cultivation e fecha inventário
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

cultBtn.MouseButton1Click:Connect(function()
	setOpen(false)
	local _, cultEv = findGuiWithEvent("ToggleCultivation")
	if cultEv then
		cultEv:Fire()
	else
		warn("Cultivation não encontrado (ToggleCultivation).")
	end
end)

-- respawn: se inventário estiver aberto, recria viewModel (char mudou)
player.CharacterAdded:Connect(function()
	if not main.Visible then return end
	task.wait(0.1)

	stopAnimationMirroring()
	if viewModel then
		viewModel:Destroy()
		viewModel = nil
	end

	ensureViewModel()
	positionCamera()
	startAnimationMirroring()
end)

-- tecla I
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == Enum.KeyCode.I then
		setOpen(not main.Visible)
	end
end)

-- initial
requestState()
