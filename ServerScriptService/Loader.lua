local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function ensureRE(name)
	local re = ReplicatedStorage:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = ReplicatedStorage
	end
	return re
end

ensureRE("BreakthroughRE")
ensureRE("MoveRE")
ensureRE("CombatRE")
ensureRE("MeditationRE")

local PlayerRegistry = require(script.Parent.Services.PlayerRegistry)
local DataService = require(script.Parent.Services.DataService)
local StatsService = require(script.Parent.Services.StatsService)
local CombatStatsService = require(script.Parent.Services.CombatStatsService)
local ModifierService = require(script.Parent.Services.ModifierService)
local StatResolverService = require(script.Parent.Services.StatResolverService)
local CultivationService = require(script.Parent.Services.CultivationService)
local MeditationService = require(script.Parent.Services.MeditationService)
local BreakthroughService = require(script.Parent.Services.BreakthroughService)
local CombatService = require(script.Parent.Services.CombatService)
local TargetService = require(script.Parent.Services.TargetService)
local InventoryService = require(script.Parent.Services.InventoryService)
local AwakeningService = require(script.Parent.Services.AwakeningService)


-- ========= Instances =========
local reg = PlayerRegistry.new()
local data = DataService.new()
local stats = StatsService.new(reg, data)

local mods = ModifierService.new(reg, stats)
local resolver = StatResolverService.new(reg, stats, mods)

local combatStats = CombatStatsService.new(reg, stats)

local cultivation = CultivationService.new(reg, stats)
cultivation:Start()

local meditation = MeditationService.new(reg, stats, mods, resolver)
meditation:Init()

local breakthrough = BreakthroughService.new(reg, stats, resolver)
breakthrough:Init()

-- ? aqui era o erro: passa instâncias (reg, stats), não módulos
local combat = CombatService.new(reg, stats)
combat:Init()
combat:Start()

local targetService = TargetService.new(reg)
targetService:Init()

local inventory = InventoryService.new(reg, stats, mods, resolver)
inventory:Init()

-- ? instanciar o awakening e inicializar
local awakening = AwakeningService.new(reg, data, mods, resolver)
awakening:Init()


-- autosave
task.spawn(function()
	while true do
		task.wait(60)
		for _, p in ipairs(Players:GetPlayers()) do
			stats:Save(p)
		end
	end
end)

local function onPlayerAdded(player)
	-- 1) carrega cache (DataService:Load acontece aqui dentro)
	stats:InitPlayer(player)

	-- 2) inicializa sistemas que dependem dos stats já carregados
	resolver:InitPlayer(player)
	cultivation:InitPlayer(player)
	meditation:InitPlayer(player)
	combatStats:InitPlayer(player)
	breakthrough:InitPlayer(player)
	inventory:InitPlayer(player)

	-- 3) agora sim: awakening (usa data cache + aplica mods + publica attributes)
	awakening:OnPlayerLoaded(player)
end

local function onPlayerRemoving(player)
	stats:Save(player)

	meditation:Cleanup(player)
	mods:Cleanup(player)

	inventory:Cleanup(player)
	combat:Cleanup(player)
	targetService:Cleanup(player)
	awakening:Cleanup(player)

	stats:Cleanup(player)
	reg:Cleanup(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do
		stats:Save(p)
	end
end)
