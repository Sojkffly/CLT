local DataStoreService = game:GetService("DataStoreService")

local DataService = {}
DataService.__index = DataService

local STORE_NAME = "PlayerData_V1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local function deepCopy(t)
	local out = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			out[k] = deepCopy(v)
		else
			out[k] = v
		end
	end
	return out
end

local function mergeDefaults(defaults, loaded)
	local out = deepCopy(defaults)
	if type(loaded) ~= "table" then
		return out
	end
	for k, v in pairs(loaded) do
		-- mantém campos conhecidos + permite extensão
		if type(v) == "table" and type(out[k]) == "table" then
			out[k] = mergeDefaults(out[k], v)
		else
			out[k] = v
		end
	end
	return out
end

local function withRetry(fn, tries, baseDelay)
	tries = tries or 6
	baseDelay = baseDelay or 0.4
	local lastErr

	for i = 1, tries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		lastErr = res
		task.wait(baseDelay * i)
	end

	return false, lastErr
end

function DataService.new()
	local self = setmetatable({}, DataService)
	self._cache = {}       -- [userId] = data table
	self._dirty = {}       -- [userId] = true/false
	return self
end

function DataService:GetKey(userId)
	return ("u_%d"):format(userId)
end

function DataService:Load(userId, defaults)
	local key = self:GetKey(userId)

	local ok, loadedOrErr = withRetry(function()
		return store:GetAsync(key)
	end)

	local data
	if ok then
		data = mergeDefaults(defaults, loadedOrErr)
	else
		warn("[DataService] Load failed:", userId, loadedOrErr)
		data = deepCopy(defaults) -- fallback
	end

	self._cache[userId] = data
	self._dirty[userId] = false
	return data
end

function DataService:GetCached(userId)
	return self._cache[userId]
end

function DataService:MarkDirty(userId)
	if self._cache[userId] then
		self._dirty[userId] = true
	end
end

function DataService:Save(userId)
	local data = self._cache[userId]
	if not data then return true end
	if not self._dirty[userId] then return true end

	local key = self:GetKey(userId)

	local ok, err = withRetry(function()
		-- UpdateAsync é mais seguro que SetAsync pra evitar overwrites cegos
		return store:UpdateAsync(key, function(old)
			-- se quiser, dá pra mesclar old aqui; por enquanto substitui pelo cache atual
			return data
		end)
	end)

	if ok then
		self._dirty[userId] = false
		return true
	else
		warn("[DataService] Save failed:", userId, err)
		return false
	end
end

function DataService:Cleanup(userId)
	self._cache[userId] = nil
	self._dirty[userId] = nil
end

return DataService
