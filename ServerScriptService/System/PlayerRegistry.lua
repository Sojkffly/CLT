local Signal = require(script.Parent.Signal)

local PlayerRegistry = {}
PlayerRegistry.__index = PlayerRegistry

function PlayerRegistry.new()
	local self = setmetatable({}, PlayerRegistry)
	self._data = {} -- [player] = { flags = {}, signals = {} }
	return self
end

function PlayerRegistry:_ensure(player)
	if self._data[player] then return self._data[player] end
	self._data[player] = {
		flags = {},        -- flags["StatsReady"]=true ...
		signals = {},      -- signals["StatsReady"]=Signal
	}
	return self._data[player]
end

function PlayerRegistry:SetReady(player, key)
	local slot = self:_ensure(player)
	slot.flags[key] = true
	local sig = slot.signals[key]
	if sig then sig:Fire() end
end

function PlayerRegistry:IsReady(player, key)
	local slot = self._data[player]
	return slot and slot.flags[key] == true
end

function PlayerRegistry:WaitReady(player, key)
	local slot = self:_ensure(player)
	if slot.flags[key] then return true end

	if not slot.signals[key] then
		slot.signals[key] = Signal.new()
	end

	slot.signals[key]:Once(function() end)
	-- Yield até ficar pronto
	slot.signals[key]._bindable.Event:Wait()
	return true
end

function PlayerRegistry:Cleanup(player)
	local slot = self._data[player]
	if not slot then return end
	for _, sig in pairs(slot.signals) do
		if sig.Destroy then sig:Destroy() end
	end
	self._data[player] = nil
end

return PlayerRegistry
