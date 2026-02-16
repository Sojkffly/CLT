local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local InventoryService = {}
InventoryService.__index = InventoryService

local SLOT_TYPES = {
	Shirt = "Shirt",
	Pants = "Pants",
	Mantle = "Mantle",
	Weapon = "Weapon",
	Accessory = "Accessory",
	Talisman = "Talisman",
	Artifact = "Artifact",
}

local function newUid()
	return "i_" .. HttpService:GenerateGUID(false)
end

local function findItem(items, uid)
	for _, it in ipairs(items) do
		if it.uid == uid then return it end
	end
	return nil
end

local function ensureArray6(arr)
	arr = arr or {}
	for i = 1, 6 do
		if arr[i] == nil then arr[i] = nil end
	end
	return arr
end

local function shallowCopy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

function InventoryService.new(reg, stats, mods, resolver)
	local self = setmetatable({}, InventoryService)
	self._reg = reg
	self._stats = stats
	self._mods = mods
	self._resolver = resolver
	self._state = {} -- [player] = { selectedUid? }
	return self
end

function InventoryService:Init()
	local re = ReplicatedStorage:WaitForChild("InventoryRE")

	re.OnServerEvent:Connect(function(player, action, payload)
		if action == "RequestState" then
			self:SendState(player)
		elseif action == "Equip" then
			self:HandleEquip(player, payload)
		elseif action == "Unequip" then
			self:HandleUnequip(player, payload)
		end
	end)
end

function InventoryService:InitPlayer(player)
	self._reg:WaitReady(player, "StatsReady")
	local data = self._stats:Get(player)
	if not data then return end

	data.Inventory = data.Inventory or { Bag = { items = {}, stacks = {} }, Pouch = { SpiritStones = 0, Capacity = 999999 } }
	data.Inventory.Bag = data.Inventory.Bag or { items = {}, stacks = {} }
	data.Inventory.Bag.items = data.Inventory.Bag.items or {}
	data.Inventory.Bag.stacks = data.Inventory.Bag.stacks or {}
	data.Inventory.Pouch = data.Inventory.Pouch or { SpiritStones = 0, Capacity = 999999 }
	data.Inventory.Pouch.SpiritStones = math.max(0, tonumber(data.Inventory.Pouch.SpiritStones) or 0)

	data.Equipped = data.Equipped or {}
	data.Equipped.Shirt = data.Equipped.Shirt or nil
	data.Equipped.Pants = data.Equipped.Pants or nil
	data.Equipped.Mantle = data.Equipped.Mantle or nil
	data.Equipped.Weapon = data.Equipped.Weapon or nil
	data.Equipped.Accessory = data.Equipped.Accessory or nil
	data.Equipped.Talismans = ensureArray6(data.Equipped.Talismans)
	data.Equipped.Artifacts = ensureArray6(data.Equipped.Artifacts)

	self._stats:MarkDirty(player)
	self._state[player] = self._state[player] or {}

	-- Reaplica mods dos equipados no join (importante)
	self:_reapplyAllEquipped(player)

	self._reg:SetReady(player, "InventoryReady")
end

function InventoryService:Cleanup(player)
	self._state[player] = nil
end

-- =========================
-- Items / Stacks helpers
-- =========================
function InventoryService:AddTestItems(player)
	-- só pra você testar sem UI complexa
	local data = self._stats:Get(player); if not data then return end
	local items = data.Inventory.Bag.items

	local function add(itType, defId, stats)
		local uid = newUid()
		table.insert(items, { uid = uid, type = itType, defId = defId, stats = stats or {} })
		return uid
	end

	-- Weapon
	add("Weapon", "iron_sword", {
		WeaponDamage_add = 15,
		WeaponAttackInterval_mult = -0.10,
		WeaponRange_add = 2,
	})

	-- Artifact
	add("Artifact", "wind_dagger", {
		ArtifactDamage_add = 10,
		ArtifactAttackInterval_mult = -0.15,
		ArtifactRange_add = 10,
		ArtifactProjectileSpeed_add = 20,
		ArtifactCurvature_add = 0.15,
	})

	-- Talisman
	add("Talisman", "qi_talisman", {
		MaxQi_add = 50,
		QiRegen_mult = 0.25,
	})

	-- Clothes
	add("Shirt", "cloth_shirt", { DEF_add = 2, MaxHP_add = 10 })
	add("Pants", "cloth_pants", { DEF_add = 2 })
	add("Mantle", "basic_mantle", { MoveSpeed_add = 2 })
	add("Accessory", "ring_1", { Crit_add = 0.03 })

	self._stats:MarkDirty(player)
end

-- =========================
-- Networking State
-- =========================
function InventoryService:SendState(player)
	local re = ReplicatedStorage:WaitForChild("InventoryRE")
	local data = self._stats:Get(player)
	if not data then return end

	-- manda um snapshot leve
	local bagItems = {}
	for _, it in ipairs(data.Inventory.Bag.items) do
		-- não manda stats completos se não quiser; por enquanto manda
		table.insert(bagItems, {
			uid = it.uid,
			type = it.type,
			defId = it.defId,
			stats = it.stats or {}, -- <<< ADICIONE ISSO
		})
	end

	re:FireClient(player, "State", {
		Equipped = shallowCopy(data.Equipped),
		BagItems = bagItems,
		Pouch = shallowCopy(data.Inventory.Pouch),
		Stacks = shallowCopy(data.Inventory.Bag.stacks),
	})
end

-- =========================
-- Equip logic
-- =========================
local function itemMatchesSlot(itemType, slot, index)
	if slot == "Shirt" or slot == "Pants" or slot == "Mantle" or slot == "Weapon" or slot == "Accessory" then
		return itemType == slot
	end
	if slot == "Talisman" then
		return itemType == "Talisman" and type(index) == "number" and index >= 1 and index <= 6
	end
	if slot == "Artifact" then
		return itemType == "Artifact" and type(index) == "number" and index >= 1 and index <= 6
	end
	return false
end

function InventoryService:HandleEquip(player, payload)
	if not self._reg:IsReady(player, "InventoryReady") then return end
	if type(payload) ~= "table" then return end

	local slot = payload.slot
	local index = payload.index
	local uid = payload.uid
	if type(slot) ~= "string" or type(uid) ~= "string" then return end

	local data = self._stats:Get(player); if not data then return end
	local item = findItem(data.Inventory.Bag.items, uid)
	if not item then return end

	if not itemMatchesSlot(item.type, slot, index) then
		return
	end

	-- Unequip anterior do slot
	self:_unequipInternal(player, slot, index)

	-- Equip novo
	if slot == "Talisman" then
		data.Equipped.Talismans[index] = uid
	elseif slot == "Artifact" then
		data.Equipped.Artifacts[index] = uid
	else
		data.Equipped[slot] = uid
	end

	self._stats:MarkDirty(player)

	-- aplica mods do item
	self:_applyItemMods(player, item)

	self._resolver:Recompute(player)
	self:SendState(player)
end

function InventoryService:HandleUnequip(player, payload)
	if not self._reg:IsReady(player, "InventoryReady") then return end
	if type(payload) ~= "table" then return end

	local slot = payload.slot
	local index = payload.index
	if type(slot) ~= "string" then return end

	self:_unequipInternal(player, slot, index)

	self._resolver:Recompute(player)
	self:SendState(player)
end

function InventoryService:_unequipInternal(player, slot, index)
	local data = self._stats:Get(player); if not data then return end

	local uid = nil
	if slot == "Talisman" and type(index) == "number" then
		uid = data.Equipped.Talismans[index]
		data.Equipped.Talismans[index] = nil
	elseif slot == "Artifact" and type(index) == "number" then
		uid = data.Equipped.Artifacts[index]
		data.Equipped.Artifacts[index] = nil
	elseif data.Equipped[slot] ~= nil then
		uid = data.Equipped[slot]
		data.Equipped[slot] = nil
	end

	if uid then
		self._mods:ClearSource(player, "Item_" .. uid)
		self._stats:MarkDirty(player)
	end
end

function InventoryService:_applyItemMods(player, item)
	local source = "Item_" .. item.uid
	local st = item.stats or {}

	-- Convenção:
	-- <Stat>_add = +X
	-- <Stat>_mult = +Y (0.2 = +20%)
	for k, v in pairs(st) do
		if type(v) == "number" then
			if k:sub(-4) == "_add" then
				local baseKey = k:sub(1, -5)
				self._mods:SetAdd(player, baseKey, source, v)
			elseif k:sub(-5) == "_mult" then
				local baseKey = k:sub(1, -6)
				self._mods:SetMult(player, baseKey, source, v)
			else
				-- fallback: trata como add
				self._mods:SetAdd(player, k, source, v)
			end
		end
	end
end

function InventoryService:_reapplyAllEquipped(player)
	local data = self._stats:Get(player); if not data then return end

	-- limpa tudo primeiro (seguro)
	-- (se você quiser, você pode só reapply; eu prefiro limpar por slot em cima)
	-- Aqui vamos reapply sem limpar geral, mas removendo duplicados pode ser feito depois.

	local function applyUid(uid)
		if not uid then return end
		local item = findItem(data.Inventory.Bag.items, uid)
		if item then
			self:_applyItemMods(player, item)
		end
	end

	applyUid(data.Equipped.Shirt)
	applyUid(data.Equipped.Pants)
	applyUid(data.Equipped.Mantle)
	applyUid(data.Equipped.Weapon)
	applyUid(data.Equipped.Accessory)

	for i = 1, 6 do
		applyUid(data.Equipped.Talismans[i])
		applyUid(data.Equipped.Artifacts[i])
	end

	self._resolver:Recompute(player)
end

return InventoryService
