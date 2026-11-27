-- Minimal Roblox engine mock for running the game's server (and client UI) code in Lune.
-- Virtual time scheduler, signals, fake Instances, services, DataStores, players.
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local Mock = {}

local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

-- ===================== SCHEDULER =====================
local now = 0
local queue = {}
local errors = {}
Mock.errors = errors
local BASE_TIME = 1795000000 -- fixed "os.time" base for determinism

local function push(t, co, args)
	table.insert(queue, { t = t, co = co, args = args, seq = #queue + math.random() })
end

local function resume(co, ...)
	if coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local tb = debug.traceback(co, tostring(err))
		table.insert(errors, tb)
		print("[MOCK ERROR] " .. tb)
	end
end

local task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	push(now, co, table.pack(...))
	return co
end
function task.delay(t, f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	push(now + (t or 0), co, table.pack(...))
	return co
end
function task.wait(t)
	t = math.max(t or 0, 1 / 60)
	local co = coroutine.running()
	local start = now
	push(now + t, co, nil)
	coroutine.yield()
	return now - start
end
function task.cancel(co)
	for i = #queue, 1, -1 do
		if queue[i].co == co then
			table.remove(queue, i)
		end
	end
end
Mock.task = task

function Mock.advance(seconds, step)
	local target = now + seconds
	step = step or 0.05
	while true do
		local best, bestI = nil, nil
		for i, e in ipairs(queue) do
			if e.t <= target and (not best or e.t < best.t or (e.t == best.t and e.seq < best.seq)) then
				best, bestI = e, i
			end
		end
		if not best then
			break
		end
		table.remove(queue, bestI)
		if best.t > now then
			now = best.t
		end
		if best.args then
			resume(best.co, table.unpack(best.args, 1, best.args.n))
		else
			resume(best.co, now)
		end
	end
	now = target
end

function Mock.now()
	return now
end

-- run a function inside a coroutine and return its results once finished (advancing time if it yields)
function Mock.call(f, ...)
	local results
	local done = false
	local co = coroutine.create(function(...)
		results = table.pack(f(...))
		done = true
	end)
	resume(co, ...)
	local guard = 0
	while not done and guard < 2000 do
		Mock.advance(0.1)
		guard += 1
	end
	if not done then
		error("Mock.call: function did not finish")
	end
	return table.unpack(results, 1, results.n)
end

-- ===================== SIGNALS =====================
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {}, waiting = {} }, Signal)
end
function Signal:Connect(fn)
	local conn = { Connected = true }
	local entry = { fn = fn, conn = conn }
	table.insert(self.handlers, entry)
	function conn.Disconnect()
		conn.Connected = false
		for i, e in ipairs(self.handlers) do
			if e == entry then
				table.remove(self.handlers, i)
				break
			end
		end
	end
	conn.disconnect = conn.Disconnect
	return setmetatable(conn, { __index = { Disconnect = function()
		conn.Disconnect()
	end } })
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Wait()
	local co = coroutine.running()
	table.insert(self.waiting, co)
	return coroutine.yield()
end
function Signal:Fire(...)
	for _, e in ipairs(table.clone(self.handlers)) do
		task.spawn(e.fn, ...)
	end
	local w = self.waiting
	self.waiting = {}
	for _, co in ipairs(w) do
		task.spawn(co, ...)
	end
end
Mock.Signal = Signal

-- ===================== INSTANCES =====================
local DATA = setmetatable({}, { __mode = "k" })
local MT = {}
local Instance = {}
Mock.Instance = Instance

local PARENT = {
	Part = "BasePart", WedgePart = "BasePart", CornerWedgePart = "BasePart", Seat = "BasePart", VehicleSeat = "BasePart",
	SpawnLocation = "Part", MeshPart = "BasePart", TrussPart = "BasePart", Terrain = "BasePart",
	BasePart = "PVInstance", Model = "PVInstance", Workspace = "Model", PVInstance = "Instance",
	Script = "BaseScript", LocalScript = "Script", BaseScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer", LuaSourceContainer = "Instance",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light", Light = "Instance",
	TextLabel = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton", GuiButton = "GuiObject", TextBox = "GuiObject", ImageLabel = "GuiObject",
	Frame = "GuiObject", ScrollingFrame = "GuiObject", GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector", BillboardGui = "LayerCollector", SurfaceGui = "LayerCollector", LayerCollector = "GuiBase2d", GuiBase2d = "Instance",
	WeldConstraint = "Instance", Weld = "JointInstance", JointInstance = "Instance",
	LinearVelocity = "Constraint", AlignOrientation = "Constraint", Constraint = "Instance",
	Player = "Instance", Humanoid = "Instance", Folder = "Instance",
}

local function isA(class, target)
	local c = class
	while c do
		if c == target then
			return true
		end
		c = PARENT[c]
	end
	return target == "Instance"
end

local DEFAULTS = {
	BasePart = { Transparency = 0, Size = Vector3.new(4, 1, 2), CFrame = CFrame.new(), Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, Massless = false, Color = Color3.new(0.6, 0.6, 0.6), AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, LocalTransparencyModifier = 0 },
	Humanoid = { WalkSpeed = 16, Sit = false, Health = 100, JumpPower = 50 },
	GuiObject = { Visible = true, BackgroundTransparency = 0, Rotation = 0, TextTransparency = 0, Text = "", ZIndex = 1, LayoutOrder = 0, AbsoluteSize = roblox.Vector2.new(100, 30), AbsolutePosition = roblox.Vector2.new(0, 0) },
	ProximityPrompt = { Enabled = true, ActionText = "", ObjectText = "", HoldDuration = 0, MaxActivationDistance = 10 },
	LayerCollector = { Enabled = true },
	Camera = { ViewportSize = roblox.Vector2.new(1280, 720), CFrame = CFrame.new(0, 10, 0) },
	Sound = { Playing = false, Volume = 0.5, PlaybackSpeed = 1, SoundId = "" },
	Model = { PrimaryPart = nil },
	Light = { Enabled = true, Brightness = 1, Range = 8 },
}

local EVENTS = {}
for _, e in ipairs({
	"Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
	"MouseEnter", "MouseLeave", "InputBegan", "InputEnded", "InputChanged", "TouchMoved", "Changed", "ChildAdded", "ChildRemoved",
	"DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "Touched", "TouchEnded", "Completed", "OnServerEvent",
	"OnClientEvent", "Event", "PlayerAdded", "PlayerRemoving", "CharacterAdded", "CharacterRemoving", "Heartbeat", "RenderStepped",
	"Stepped", "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "Ended", "Died", "FocusLost", "Focused",
	"PlaybackEnded",
}) do
	EVENTS[e] = true
end

local function data(inst)
	return DATA[inst]
end

local function defaultFor(class, key)
	local c = class
	while c do
		local d = DEFAULTS[c]
		if d and d[key] ~= nil then
			return d[key]
		end
		c = PARENT[c]
	end
	return nil
end

local function propSignal(inst, key)
	local d = data(inst)
	d.propSignals[key] = d.propSignals[key] or Signal.new()
	return d.propSignals[key]
end

local methods = {}

function methods:IsA(class)
	return isA(data(self).class, class)
end
function methods:GetChildren()
	return table.clone(data(self).children)
end
function methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in ipairs(data(i).children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, c in ipairs(data(self).children) do
		if data(c).props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(data(self).children) do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods:WaitForChild(name, timeout)
	local c = self:FindFirstChild(name)
	if c then
		return c
	end
	local t = 0
	while t < (timeout or 5) do
		task.wait(0.1)
		t += 0.1
		c = self:FindFirstChild(name)
		if c then
			return c
		end
	end
	if not timeout then
		print("[MOCK] infinite yield possible on WaitForChild('" .. name .. "') of " .. self:GetFullName())
	end
	return nil
end
function methods:FindFirstChildOfClass(class)
	for _, c in ipairs(data(self).children) do
		if data(c).class == class then
			return c
		end
	end
	return nil
end
function methods:FindFirstChildWhichIsA(class, recursive)
	for _, c in ipairs(data(self).children) do
		if isA(data(c).class, class) then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(data(self).children) do
			local f = c:FindFirstChildWhichIsA(class, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods:FindFirstAncestor(name)
	local p = data(self).parent
	while p do
		if data(p).props.Name == name then
			return p
		end
		p = data(p).parent
	end
	return nil
end
function methods:FindFirstAncestorOfClass(class)
	local p = data(self).parent
	while p do
		if data(p).class == class then
			return p
		end
		p = data(p).parent
	end
	return nil
end
function methods:FindFirstAncestorWhichIsA(class)
	local p = data(self).parent
	while p do
		if isA(data(p).class, class) then
			return p
		end
		p = data(p).parent
	end
	return nil
end
function methods:IsDescendantOf(other)
	local p = data(self).parent
	while p do
		if p == other then
			return true
		end
		p = data(p).parent
	end
	return false
end
function methods:GetFullName()
	local parts = {}
	local i = self
	while i and data(i).class ~= "DataModel" do
		table.insert(parts, 1, data(i).props.Name)
		i = data(i).parent
	end
	return table.concat(parts, ".")
end
function methods:SetAttribute(k, v)
	data(self).attrs[k] = v
end
function methods:GetAttribute(k)
	return data(self).attrs[k]
end
function methods:GetAttributes()
	return table.clone(data(self).attrs)
end
function methods:GetPropertyChangedSignal(key)
	return propSignal(self, key)
end
function methods:GetAttributeChangedSignal(key)
	return propSignal(self, "@" .. key)
end
function methods:Destroy()
	local d = data(self)
	if d.destroyed then
		return
	end
	for _, c in ipairs(table.clone(d.children)) do
		c:Destroy()
	end
	self.Parent = nil
	d.destroyed = true
end
function methods:ClearAllChildren()
	for _, c in ipairs(table.clone(data(self).children)) do
		c:Destroy()
	end
end
function methods:Clone()
	local d = data(self)
	local map = {}
	local function copy(src)
		local sd = data(src)
		local c = Instance.new(sd.class)
		local cd = data(c)
		for k, v in pairs(sd.props) do
			if k ~= "Parent" then
				cd.props[k] = v
			end
		end
		for k, v in pairs(sd.attrs) do
			cd.attrs[k] = v
		end
		map[src] = c
		for _, ch in ipairs(sd.children) do
			local cc = copy(ch)
			cc.Parent = c
		end
		return c
	end
	local root = copy(self)
	-- remap instance references (PrimaryPart, Part0/Part1, Adornee)
	for src, dst in pairs(map) do
		for k, v in pairs(data(dst).props) do
			if type(v) == "table" and DATA[v] and map[v] then
				data(dst).props[k] = map[v]
			end
		end
	end
	return root
end
-- PVInstance
local function pivotOf(self)
	local d = data(self)
	if isA(d.class, "BasePart") then
		return self.CFrame
	end
	local pp = d.props.PrimaryPart
	if pp then
		return pp.CFrame
	end
	if d.props.WorldPivot then
		return d.props.WorldPivot
	end
	local first = self:FindFirstChildWhichIsA("BasePart", true)
	return first and first.CFrame or CFrame.new()
end
function methods:GetPivot()
	return pivotOf(self)
end
function methods:PivotTo(cf)
	local d = data(self)
	if isA(d.class, "BasePart") then
		self.CFrame = cf
		return
	end
	local delta = cf * pivotOf(self):Inverse()
	for _, p in ipairs(self:GetDescendants()) do
		if isA(data(p).class, "BasePart") then
			p.CFrame = delta * p.CFrame
		end
	end
	if d.props.WorldPivot and not d.props.PrimaryPart then
		d.props.WorldPivot = cf
	end
end
function methods:GetBoundingBox()
	return pivotOf(self), Vector3.new(10, 10, 10)
end
function methods:SetNetworkOwner() end
function methods:GetMass()
	return 1
end
function methods:ApplyImpulse() end
function methods:Emit() end
function methods:Play()
	data(self).props.Playing = true
end
function methods:Stop()
	data(self).props.Playing = false
end
function methods:MoveTo() end
function methods:Sit(hum)
	data(self).props.Occupant = hum
end
function methods:Kick(msg)
	print("[MOCK] kicked " .. tostring(data(self).props.Name) .. ": " .. tostring(msg))
	data(self).kicked = msg
end
-- Remotes
function methods:FireClient(player, ...)
	local inbox = data(player).inbox
	if inbox then
		table.insert(inbox, { remote = data(self).props.Name, args = table.pack(...) })
	end
end
function methods:FireAllClients(...)
	for _, p in ipairs(Mock.players) do
		self:FireClient(p, ...)
	end
end
function methods:FireServer(...)
	self.OnServerEvent:Fire(Mock.localPlayer, ...)
end
function methods:InvokeServer(...)
	local cb = data(self).props.OnServerInvoke
	return cb(Mock.localPlayer, ...)
end
function methods:Fire(...)
	self.Event:Fire(...)
end
-- Terrain
function methods:FillBlock() end
function methods:FillCylinder() end
function methods:FillBall() end
function methods:FillWedge() end
-- Workspace / camera
function methods:Raycast()
	return nil
end
function methods:ViewportPointToRay()
	return { Origin = Vector3.new(0, 50, 0), Direction = Vector3.new(0, -1, 0) }
end
function methods:GetServerTimeNow()
	return BASE_TIME + now
end

MT.__index = function(self, key)
	local d = DATA[self]
	local m = methods[key]
	if m then
		return m
	end
	local v = d.props[key]
	if v ~= nil then
		return v
	end
	if key == "Position" and isA(d.class, "BasePart") then
		return self.CFrame.Position
	end
	if key == "ClassName" then
		return d.class
	end
	if key == "Parent" then
		return d.parent
	end
	for _, c in ipairs(d.children) do
		if DATA[c].props.Name == key then
			return c
		end
	end
	if EVENTS[key] then
		d.props[key] = Signal.new()
		return d.props[key]
	end
	if d.special and d.special[key] ~= nil then
		return d.special[key]
	end
	local def = defaultFor(d.class, key)
	if def ~= nil then
		return def
	end
	if key == "Rotation" and isA(d.class, "BasePart") then
		return self.CFrame.Rotation
	end
	return nil
end

MT.__newindex = function(self, key, value)
	local d = DATA[self]
	if key == "Parent" then
		if d.destroyed and value ~= nil then
			error("The Parent property of " .. tostring(d.props.Name) .. " is locked")
		end
		local old = d.parent
		if old == value then
			return
		end
		if old then
			local od = DATA[old]
			for i, c in ipairs(od.children) do
				if c == self then
					table.remove(od.children, i)
					break
				end
			end
			if od.props.ChildRemoved then
				od.props.ChildRemoved:Fire(self)
			end
		end
		d.parent = value
		if value then
			table.insert(DATA[value].children, self)
			if DATA[value].props.ChildAdded then
				DATA[value].props.ChildAdded:Fire(self)
			end
		end
		return
	end
	if key == "Position" and isA(d.class, "BasePart") then
		d.props.CFrame = CFrame.new(value) * self.CFrame.Rotation
		return
	end
	local old = d.props[key]
	d.props[key] = value
	if old ~= value and d.propSignals[key] then
		d.propSignals[key]:Fire()
	end
end
MT.__tostring = function(self)
	return DATA[self].props.Name or DATA[self].class
end

function Instance.new(class, parent)
	local inst = setmetatable({}, MT)
	DATA[inst] = { class = class, props = { Name = class }, children = {}, attrs = {}, propSignals = {}, parent = nil }
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Mock.isInstance(v)
	return type(v) == "table" and DATA[v] ~= nil
end
function Mock.data(v)
	return DATA[v]
end

-- ===================== IMPORT FROM A REAL PLACE =====================
local COPY = {
	"CFrame", "Size", "Color", "Transparency", "Material", "Anchored", "CanCollide", "CanQuery", "CanTouch", "Massless",
	"Source", "Text", "Face", "Enabled", "Neutral", "Shape", "TextScaled",
}
function Mock.import(src, parent)
	local inst = Instance.new(src.ClassName)
	inst.Name = src.Name
	for _, prop in ipairs(COPY) do
		local ok, v = pcall(function()
			return src[prop]
		end)
		if ok and v ~= nil then
			DATA[inst].props[prop] = v
		end
	end
	local ok, attrs = pcall(function()
		return src:GetAttributes()
	end)
	if ok and attrs then
		for k, v in pairs(attrs) do
			DATA[inst].attrs[k] = v
		end
	end
	for _, c in ipairs(src:GetChildren()) do
		Mock.import(c, inst)
	end
	if src.ClassName == "Model" then
		local okp, pp = pcall(function()
			return src.PrimaryPart
		end)
		if okp and pp then
			DATA[inst].pendingPrimary = pp.Name
		end
	end
	inst.Parent = parent
	return inst
end
local function resolvePrimary(root)
	for _, d in ipairs(root:GetDescendants()) do
		local dd = DATA[d]
		if dd.pendingPrimary then
			dd.props.PrimaryPart = d:FindFirstChild(dd.pendingPrimary)
			dd.pendingPrimary = nil
		end
	end
end

-- ===================== SERVICES =====================
local game = Instance.new("DataModel")
game.Name = "Game"
Mock.game = game
local services = {}
local function service(name, class)
	local s = Instance.new(class or name)
	s.Name = name
	s.Parent = game
	services[name] = s
	return s
end
local Workspace = service("Workspace")
local terrain = Instance.new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = Workspace
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = Workspace
Workspace.CurrentCamera = camera
for _, n in ipairs({ "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui", "Lighting", "SoundService", "Teams", "Chat" }) do
	service(n)
end
local Players = service("Players")
Mock.players = {}
methods.GetPlayers = function(self)
	if self == Players then
		return table.clone(Mock.players)
	end
	return {}
end
methods.GetPlayerByUserId = function(self, id)
	for _, p in ipairs(Mock.players) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
methods.GetPlayerFromCharacter = function(self, char)
	for _, p in ipairs(Mock.players) do
		if p.Character == char then
			return p
		end
	end
	return nil
end
methods.GetNameFromUserIdAsync = function(self, id)
	return "User" .. tostring(id)
end

local RunService = service("RunService")
Mock.isStudio = true
methods.IsServer = function()
	return Mock.mode ~= "client"
end
methods.IsClient = function()
	return Mock.mode == "client"
end
methods.IsStudio = function()
	return Mock.isStudio
end

local TweenService = service("TweenService")
methods.Create = function(self, inst, info, goals)
	local tween = { Completed = Signal.new(), cancelled = false, PlaybackState = "Begin" }
	function tween.Play(t)
		local duration = type(info) == "table" and info.Time or 0
		task.delay(duration, function()
			if tween.cancelled then
				return
			end
			for k, v in pairs(goals) do
				inst[k] = v
			end
			tween.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tween.Cancel(t)
		if not tween.cancelled then
			tween.cancelled = true
			tween.Completed:Fire(Enum.PlaybackState.Cancelled)
		end
	end
	function tween.Pause() end
	function tween.Destroy() end
	return tween
end

-- DataStores (in memory, persistent across "servers" during a test run)
Mock.stores = {}
Mock.dataStoreFails = false
local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local r = {}
	for k, v in pairs(t) do
		r[k] = deepCopy(v)
	end
	return r
end
local DataStoreService = service("DataStoreService")
methods.GetDataStore = function(self, name)
	Mock.stores[name] = Mock.stores[name] or {}
	local mem = Mock.stores[name]
	local store = {}
	function store.UpdateAsync(_, key, fn)
		if Mock.dataStoreFails then
			error("DataStore request failed (mock)")
		end
		task.wait(0.05)
		local newValue = fn(deepCopy(mem[key]))
		if newValue ~= nil then
			mem[key] = deepCopy(newValue)
		end
		return deepCopy(mem[key])
	end
	function store.GetAsync(_, key)
		return deepCopy(mem[key])
	end
	function store.SetAsync(_, key, v)
		mem[key] = deepCopy(v)
	end
	function store.RemoveAsync(_, key)
		mem[key] = nil
	end
	function store.GetSortedAsync(_, asc, n)
		local list = {}
		for k, v in pairs(mem) do
			table.insert(list, { key = k, value = v })
		end
		table.sort(list, function(a, b)
			return asc and a.value < b.value or a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(n, #list) do
			page[i] = list[i]
		end
		return {
			GetCurrentPage = function()
				return page
			end,
		}
	end
	return store
end
methods.GetOrderedDataStore = methods.GetDataStore

local MarketplaceService = service("MarketplaceService")
Mock.ownedPasses = {}
methods.UserOwnsGamePassAsync = function(self, userId, passId)
	return Mock.ownedPasses[userId .. ":" .. passId] == true
end
methods.PromptGamePassPurchase = function() end
methods.PromptProductPurchase = function() end

local TextService = service("TextService")
methods.FilterStringAsync = function(self, text)
	return {
		GetNonChatStringForBroadcastAsync = function()
			return text
		end,
	}
end
local HttpService = service("HttpService")
local guid = 0
methods.GenerateGUID = function()
	guid += 1
	return "guid-" .. guid
end
methods.JSONEncode = function(self, v)
	return tostring(v)
end
local Debris = service("Debris")
methods.AddItem = function(self, inst, t)
	task.delay(t or 10, function()
		inst:Destroy()
	end)
end
service("ProximityPromptService")
local UserInputService = service("UserInputService")
UserInputService.TouchEnabled = false
UserInputService.KeyboardEnabled = true
methods.IsKeyDown = function()
	return false
end
methods.GetMouseLocation = function()
	return roblox.Vector2.new(640, 360)
end
methods.GetGamepadState = function()
	return {}
end
services.GuiService = service("GuiService")
methods.SetCoreGuiEnabled = function() end
methods.SetCore = function() end

Mock.bindToClose = {}
methods.BindToClose = function(self, fn)
	table.insert(Mock.bindToClose, fn)
end
methods.GetService = function(self, name)
	local s = services[name]
	if not s then
		s = service(name)
	end
	return s
end
DATA[game].props.JobId = "mock-job-1"
DATA[game].props.PlaceId = 0

-- ===================== GLOBALS / SCRIPT RUNNER =====================
local RandomMT = {}
RandomMT.__index = RandomMT
local Random = {}
function Random.new(seed)
	local state = math.floor((seed or os.clock() * 1e6) % 2147483646) + 1
	return setmetatable({ state = state }, RandomMT)
end
function RandomMT:_next()
	self.state = (self.state * 16807) % 2147483647
	return (self.state - 1) / 2147483646
end
function RandomMT:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * self:_next()
end
function RandomMT:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

local TweenInfo = {
	new = function(time, ...)
		return { Time = time or 1 }
	end,
}

local moduleCache = {}
local env

local function runSource(scriptInst, src, chunkName)
	-- Lune copies raw fields of the environment table, so build a flat table per script
	local scriptEnv = table.clone(env)
	scriptEnv.script = scriptInst
	local fn = luau.load(src, { debugName = chunkName, environment = scriptEnv })
	return fn
end

local function mockRequire(mod)
	if not Mock.isInstance(mod) then
		error("require expects a ModuleScript instance, got " .. typeof(mod))
	end
	if moduleCache[mod] ~= nil then
		return moduleCache[mod]
	end
	local fn = runSource(mod, mod.Source, mod:GetFullName())
	local result = fn()
	moduleCache[mod] = result
	return result
end

local realTypeof = typeof
local function mockTypeof(v)
	if Mock.isInstance(v) then
		return "Instance"
	end
	return realTypeof(v)
end

local realOs = os
env = {
	game = game,
	workspace = Workspace,
	Workspace = Workspace,
	script = nil,
	require = mockRequire,
	task = task,
	wait = task.wait,
	delay = task.delay,
	spawn = task.spawn,
	tick = function()
		return BASE_TIME + now
	end,
	time = function()
		return now
	end,
	os = setmetatable({
		clock = function()
			return now
		end,
		time = function()
			return BASE_TIME + math.floor(now)
		end,
		date = realOs.date,
	}, { __index = realOs }),
	print = function(...)
		if Mock.verbose then
			print(...)
		end
	end,
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		table.insert(Mock.warnings, table.concat(parts, " "))
		if Mock.verbose then
			print("[WARN] " .. table.concat(parts, " "))
		end
	end,
	typeof = mockTypeof,
	Instance = Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	BrickColor = roblox.BrickColor,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	ColorSequence = roblox.ColorSequence,
	Rect = roblox.Rect,
	Ray = roblox.Ray,
	Font = roblox.Font,
	Random = Random,
	TweenInfo = TweenInfo,
	RaycastParams = { new = function()
		return {}
	end },
	DateTime = { now = function()
		return { UnixTimestamp = BASE_TIME + math.floor(now) }
	end },
	utf8 = utf8,
	debug = debug,
}
setmetatable(env, { __index = _G })
Mock.env = env
Mock.warnings = {}

function Mock.loadPlace(path)
	local place = roblox.deserializePlace(fs.readFile(path))
	for _, svc in ipairs(place:GetChildren()) do
		local target = services[svc.Name]
		if target then
			for _, c in ipairs(svc:GetChildren()) do
				if not (svc.Name == "Workspace" and (c.Name == "Terrain" or c.Name == "Camera")) then
					Mock.import(c, target)
				end
			end
		end
	end
	resolvePrimary(game)
end

function Mock.runScript(scriptInst)
	local fn = runSource(scriptInst, scriptInst.Source, scriptInst:GetFullName())
	task.spawn(fn)
end

-- ===================== PLAYERS =====================
local nextUserId = 1000
function Mock.addPlayer(name)
	nextUserId += 1
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = nextUserId
	DATA[p].inbox = {}
	local pg = Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = p
	p.Parent = Players
	table.insert(Mock.players, p)
	-- character
	local char = Instance.new("Model")
	char.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(0, 200, 0)
	root.Parent = char
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Parent = char
	local hand = Instance.new("Part")
	hand.Name = "RightHand"
	hand.Size = Vector3.new(1, 1, 1)
	hand.Parent = char
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	char.PrimaryPart = root
	Players.PlayerAdded:Fire(p)
	char.Parent = Workspace
	p.Character = char
	p.CharacterAdded:Fire(char)
	return p
end

function Mock.removePlayer(p)
	for i, q in ipairs(Mock.players) do
		if q == p then
			table.remove(Mock.players, i)
		end
	end
	Players.PlayerRemoving:Fire(p)
	task.defer(function()
		p.Parent = nil
	end)
end

function Mock.inbox(p)
	return DATA[p].inbox
end

function Mock.request(player, name, payload)
	local remote = services.ReplicatedStorage.Remotes.Request
	local cb = DATA[remote].props.OnServerInvoke
	return Mock.call(cb, player, name, payload)
end

function Mock.toasts(player)
	local out = {}
	for _, m in ipairs(DATA[player].inbox) do
		if m.remote == "Toast" then
			table.insert(out, m.args[1])
		end
	end
	return out
end

function Mock.lastPush(player, channel)
	local inbox = DATA[player].inbox
	for i = #inbox, 1, -1 do
		local m = inbox[i]
		if m.remote == "Push" and m.args[1] == channel then
			return m.args[2]
		end
	end
	return nil
end

function Mock.shutdown()
	for _, fn in ipairs(Mock.bindToClose) do
		Mock.call(fn)
	end
end

return Mock
