-- Networking layer: a small set of remotes with named, whitelisted handlers,
-- per-player rate limiting and argument sanitising on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local IS_SERVER = RunService:IsServer()
local REMOTE_NAMES = {
	Request = "RemoteFunction", -- client -> server, returns result
	Action = "RemoteEvent", -- client -> server, fire & forget
	Push = "RemoteEvent", -- server -> client state updates
	Toast = "RemoteEvent", -- server -> client notifications
	Fx = "RemoteEvent", -- server -> client visual/sound effects
}

local folder
local function getFolder()
	if folder then
		return folder
	end
	if IS_SERVER then
		folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		for name, class in pairs(REMOTE_NAMES) do
			if not folder:FindFirstChild(name) then
				local r = Instance.new(class)
				r.Name = name
				r.Parent = folder
			end
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end
	return folder
end

function Net.remote(name)
	local f = getFolder()
	return IS_SERVER and f:FindFirstChild(name) or f:WaitForChild(name)
end

-- ===================== SERVER =====================
if IS_SERVER then
	local requestHandlers = {}
	local actionHandlers = {}
	local buckets = {} -- [player] = {[name] = {tokens, last}}

	local DEFAULT_RATE = 8 -- calls per second sustained
	local DEFAULT_BURST = 12
	local rates = {}

	function Net.setRate(name, perSecond, burst)
		rates[name] = { perSecond, burst or perSecond * 2 }
	end

	local function allow(player, name)
		local pb = buckets[player]
		if not pb then
			pb = {}
			buckets[player] = pb
		end
		local cfg = rates[name]
		local rate = cfg and cfg[1] or DEFAULT_RATE
		local burst = cfg and cfg[2] or DEFAULT_BURST
		local b = pb[name]
		local now = os.clock()
		if not b then
			b = { tokens = burst, last = now }
			pb[name] = b
		end
		b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
		b.last = now
		if b.tokens < 1 then
			return false
		end
		b.tokens -= 1
		return true
	end

	-- Only plain data may cross the boundary (no Instances except explicitly allowed)
	local function sanitize(v, depth)
		depth = depth or 0
		if depth > 4 then
			return nil
		end
		local t = typeof(v)
		if t == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				return nil
			end
			return v
		elseif t == "string" then
			if #v > 200 then
				return string.sub(v, 1, 200)
			end
			return v
		elseif t == "boolean" or t == "nil" then
			return v
		elseif t == "table" then
			local out, n = {}, 0
			for k, val in pairs(v) do
				n += 1
				if n > 64 then
					break
				end
				local kt = typeof(k)
				if kt == "string" or kt == "number" then
					out[k] = sanitize(val, depth + 1)
				end
			end
			return out
		elseif t == "Vector3" then
			return v
		end
		return nil
	end

	function Net.onRequest(name, handler)
		requestHandlers[name] = handler
	end

	function Net.onAction(name, handler)
		actionHandlers[name] = handler
	end

	function Net.push(player, channel, data)
		Net.remote("Push"):FireClient(player, channel, data)
	end

	function Net.pushAll(channel, data)
		Net.remote("Push"):FireAllClients(channel, data)
	end

	function Net.toast(player, text, kind)
		Net.remote("Toast"):FireClient(player, text, kind or "info")
	end

	function Net.fx(player, name, data)
		Net.remote("Fx"):FireClient(player, name, data)
	end

	function Net.fxAll(name, data)
		Net.remote("Fx"):FireAllClients(name, data)
	end

	function Net.init()
		getFolder()
		Net.remote("Request").OnServerInvoke = function(player, name, payload)
			if type(name) ~= "string" then
				return { ok = false, err = "bad request" }
			end
			local handler = requestHandlers[name]
			if not handler then
				return { ok = false, err = "unknown request" }
			end
			if not allow(player, name) then
				return { ok = false, err = "Слишком часто. Подождите." }
			end
			if Net.onActivity then
				Net.onActivity(player)
			end
			local ok, result = pcall(handler, player, sanitize(payload))
			if not ok then
				warn("[Net] request error", name, result)
				return { ok = false, err = "Ошибка сервера" }
			end
			if type(result) ~= "table" then
				result = { ok = result ~= false }
			end
			return result
		end
		Net.remote("Action").OnServerEvent:Connect(function(player, name, payload)
			if type(name) ~= "string" then
				return
			end
			local handler = actionHandlers[name]
			if not handler or not allow(player, name) then
				return
			end
			local ok, err = pcall(handler, player, sanitize(payload))
			if not ok then
				warn("[Net] action error", name, err)
			end
		end)
		game:GetService("Players").PlayerRemoving:Connect(function(p)
			buckets[p] = nil
		end)
	end
else
	-- ===================== CLIENT =====================
	local pushHandlers = {}

	function Net.request(name, payload)
		local ok, result = pcall(function()
			return Net.remote("Request"):InvokeServer(name, payload)
		end)
		if not ok then
			return { ok = false, err = "Нет связи с сервером" }
		end
		return result or { ok = false }
	end

	function Net.action(name, payload)
		Net.remote("Action"):FireServer(name, payload)
	end

	function Net.onPush(channel, handler)
		pushHandlers[channel] = pushHandlers[channel] or {}
		table.insert(pushHandlers[channel], handler)
	end

	function Net.init()
		Net.remote("Push").OnClientEvent:Connect(function(channel, data)
			local list = pushHandlers[channel]
			if list then
				for _, h in ipairs(list) do
					task.spawn(h, data)
				end
			end
		end)
	end
end

return Net
