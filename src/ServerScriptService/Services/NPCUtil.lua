-- NPCUtil: NPC characters for guests and staff.
-- Looks: real Roblox R15 avatars (smooth body, head with a face) built once via
-- Players:CreateHumanoidModelFromDescription and cloned (fast), recoloured per role,
-- with hair, chef hat, apron, waiter vest/bow tie. Optional: avatars of real users
-- (Config.NPC.GuestAvatarUserIds) and catalog clothing (Config.NPC.Clothing).
-- Performance: anchored HumanoidRootPart moved by tweens, humanoid state machine off,
-- no physics / pathfinding. Fallback: simple part-based templates (Assets.NPC).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Config = require(Shared.Config)

local NPCUtil = {}

local SKIN = {
	Color3.fromRGB(255, 220, 177),
	Color3.fromRGB(234, 192, 134),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(255, 205, 148),
	Color3.fromRGB(110, 70, 40),
	Color3.fromRGB(245, 205, 165),
}
local SHIRTS = {
	Color3.fromRGB(52, 120, 220),
	Color3.fromRGB(220, 70, 70),
	Color3.fromRGB(60, 170, 90),
	Color3.fromRGB(240, 190, 50),
	Color3.fromRGB(170, 80, 200),
	Color3.fromRGB(240, 130, 50),
	Color3.fromRGB(40, 180, 190),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(230, 110, 160),
	Color3.fromRGB(110, 190, 240),
}
local PANTS = {
	Color3.fromRGB(40, 50, 80),
	Color3.fromRGB(60, 60, 60),
	Color3.fromRGB(110, 80, 50),
	Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(80, 100, 140),
	Color3.fromRGB(150, 140, 120),
}
local HAIR = {
	Color3.fromRGB(40, 25, 15),
	Color3.fromRGB(90, 60, 30),
	Color3.fromRGB(220, 190, 110),
	Color3.fromRGB(20, 20, 20),
	Color3.fromRGB(160, 60, 30),
	Color3.fromRGB(200, 200, 205),
}
local WHITE = Color3.fromRGB(248, 248, 245)
local BLACK = Color3.fromRGB(25, 25, 28)

-- uniforms: torso (vest/jacket), arms (sleeves), legs (trousers)
local UNIFORM = {
	Cook = { torso = WHITE, arms = WHITE, legs = Color3.fromRGB(45, 45, 50), hat = "chef", apron = WHITE, scarf = Color3.fromRGB(210, 40, 40) },
	Waiter = { torso = BLACK, arms = WHITE, legs = BLACK, bow = BLACK, shirtFront = WHITE },
	Bartender = { torso = Color3.fromRGB(120, 25, 40), arms = WHITE, legs = BLACK, bow = Color3.fromRGB(20, 20, 20), shirtFront = WHITE },
}

local npcFolder
local function folder()
	if not npcFolder then
		npcFolder = workspace:FindFirstChild("NPCs") or Instance.new("Folder")
		npcFolder.Name = "NPCs"
		npcFolder.Parent = workspace
	end
	return npcFolder
end

local function pick(list, rng)
	return list[rng:NextInteger(1, #list)]
end

-- ===================== AVATAR RIGS =====================
local baseRig = nil -- default R15 avatar (recoloured per NPC)
local userRigs = {} -- avatars of real users (kept as-is)
local preloadStarted = false

local function prepareRig(rig)
	rig.Name = "AvatarRig"
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		pcall(function()
			hum.EvaluateStateMachine = false -- NPC двигаются твинами: машина состояний не нужна
		end)
		if not hum:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = hum
		end
	end
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	return rig
end

local function buildRig(description)
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if ok and rig then
		return prepareRig(rig)
	end
	return nil
end

-- Called once at server start (yields while avatars load)
function NPCUtil.preload()
	if preloadStarted then
		return
	end
	preloadStarted = true
	local desc = Instance.new("HumanoidDescription")
	baseRig = buildRig(desc)
	if not baseRig then
		warn("[NPCUtil] R15 avatar unavailable, using simple NPC models")
	end
	local ids = Config.NPC and Config.NPC.GuestAvatarUserIds or {}
	for _, userId in ipairs(ids) do
		local ok, d = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if ok and d then
			local rig = buildRig(d)
			if rig then
				table.insert(userRigs, rig)
			end
		end
	end
end

local function weldTo(part, target, c0)
	local w = Instance.new("Weld")
	w.Part0 = target
	w.Part1 = part
	w.C0 = c0
	w.Parent = part
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = target.Parent
	return part
end

local function newPart(name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	return p
end

local function setBodyColors(model, skin, torso, arms, legs)
	local bc = model:FindFirstChildOfClass("BodyColors")
	if bc then
		bc.HeadColor3 = skin
		bc.TorsoColor3 = torso
		bc.LeftArmColor3 = arms
		bc.RightArmColor3 = arms
		bc.LeftLegColor3 = legs
		bc.RightLegColor3 = legs
	end
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			local n = p.Name
			if n == "Head" then
				p.Color = skin
			elseif n == "UpperTorso" then
				p.Color = torso
			elseif n == "LowerTorso" then
				p.Color = legs
			elseif n:find("Hand") then
				p.Color = skin
			elseif n:find("Arm") then
				p.Color = arms
			elseif n:find("Leg") or n:find("Foot") then
				p.Color = legs
			end
		end
	end
end

local function addClothing(model, shirtId, pantsId)
	if shirtId and shirtId ~= 0 then
		local s = Instance.new("Shirt")
		s.ShirtTemplate = "rbxassetid://" .. shirtId
		s.Parent = model
	end
	if pantsId and pantsId ~= 0 then
		local pa = Instance.new("Pants")
		pa.PantsTemplate = "rbxassetid://" .. pantsId
		pa.Parent = model
	end
end

local function addHair(model, head, color, style)
	local hs = head.Size
	if style == 1 then
		-- short rounded hair
		local cap = newPart("Hair", Vector3.new(hs.X * 1.08, hs.Y * 0.55, hs.Z * 1.1), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(cap, head, CFrame.new(0, hs.Y * 0.3, hs.Z * 0.04))
	elseif style == 2 then
		-- long hair
		local cap = newPart("Hair", Vector3.new(hs.X * 1.1, hs.Y * 0.6, hs.Z * 1.12), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(cap, head, CFrame.new(0, hs.Y * 0.28, hs.Z * 0.05))
		local back = newPart("HairBack", Vector3.new(hs.X * 1.0, hs.Y * 1.0, hs.Z * 0.35), color)
		weldTo(back, head, CFrame.new(0, -hs.Y * 0.1, hs.Z * 0.45))
	elseif style == 3 then
		-- bun
		local cap = newPart("Hair", Vector3.new(hs.X * 1.06, hs.Y * 0.5, hs.Z * 1.08), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(cap, head, CFrame.new(0, hs.Y * 0.32, hs.Z * 0.04))
		local bun = newPart("HairBun", Vector3.new(hs.X * 0.45, hs.X * 0.45, hs.X * 0.45), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(bun, head, CFrame.new(0, hs.Y * 0.55, hs.Z * 0.35))
	elseif style == 4 then
		-- cap (baseball)
		local cap = newPart("Cap", Vector3.new(hs.X * 1.08, hs.Y * 0.45, hs.Z * 1.08), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(cap, head, CFrame.new(0, hs.Y * 0.34, 0))
		local visor = newPart("CapVisor", Vector3.new(hs.X * 0.8, 0.08, hs.Z * 0.5), color)
		weldTo(visor, head, CFrame.new(0, hs.Y * 0.28, -hs.Z * 0.6))
	end
end

local function addTopHat(model, head, color)
	local hs = head.Size
	local brim = newPart("HatBrim", Vector3.new(0.12, hs.X * 1.5, hs.X * 1.5), color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	weldTo(brim, head, CFrame.new(0, hs.Y * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local top = newPart("Hat", Vector3.new(hs.Y * 0.75, hs.X * 0.95, hs.X * 0.95), color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	weldTo(top, head, CFrame.new(0, hs.Y * 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local band = newPart("HatBand", Vector3.new(0.15, hs.X * 0.97, hs.X * 0.97), Color3.fromRGB(150, 20, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	weldTo(band, head, CFrame.new(0, hs.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)))
end

local function addChefHat(model, head)
	local hs = head.Size
	local band = newPart("ChefHatBand", Vector3.new(hs.Y * 0.45, hs.X * 1.02, hs.X * 1.02), WHITE, Enum.Material.Fabric, Enum.PartType.Cylinder)
	weldTo(band, head, CFrame.new(0, hs.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local puff = newPart("ChefHat", Vector3.new(hs.X * 1.35, hs.Y * 1.05, hs.X * 1.35), WHITE, Enum.Material.Fabric, Enum.PartType.Ball)
	weldTo(puff, head, CFrame.new(0, hs.Y * 1.15, 0))
end

local function addUniformDetails(model, u)
	local torso = model:FindFirstChild("UpperTorso")
	local lower = model:FindFirstChild("LowerTorso")
	if not torso then
		return
	end
	local ts = torso.Size
	local front = -(ts.Z / 2 + 0.03)
	if u.shirtFront then
		local sf = newPart("ShirtFront", Vector3.new(ts.X * 0.3, ts.Y * 0.9, 0.06), u.shirtFront)
		weldTo(sf, torso, CFrame.new(0, 0.02, front))
		for i = 1, 3 do
			local b = newPart("Button", Vector3.new(0.12, 0.12, 0.05), Color3.fromRGB(60, 60, 60), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			weldTo(b, torso, CFrame.new(0, ts.Y * 0.25 - i * ts.Y * 0.18, front - 0.04))
		end
	end
	if u.bow then
		local l = newPart("BowL", Vector3.new(0.28, 0.2, 0.08), u.bow)
		weldTo(l, torso, CFrame.new(-0.15, ts.Y * 0.42, front - 0.05) * CFrame.Angles(0, 0, math.rad(15)))
		local r = newPart("BowR", Vector3.new(0.28, 0.2, 0.08), u.bow)
		weldTo(r, torso, CFrame.new(0.15, ts.Y * 0.42, front - 0.05) * CFrame.Angles(0, 0, math.rad(-15)))
	end
	if u.apron then
		local a = newPart("Apron", Vector3.new(ts.X * 0.8, ts.Y * 0.7, 0.06), u.apron, Enum.Material.Fabric)
		weldTo(a, torso, CFrame.new(0, -ts.Y * 0.12, front))
		if lower then
			local ls = lower.Size
			local a2 = newPart("ApronSkirt", Vector3.new(ls.X * 0.9, ls.Y + 1.1, 0.06), u.apron, Enum.Material.Fabric)
			weldTo(a2, lower, CFrame.new(0, -0.45, -(ls.Z / 2 + 0.05)))
		end
		-- double-breasted buttons
		for i = 1, 3 do
			for _, x in ipairs({ -0.25, 0.25 }) do
				local b = newPart("Button", Vector3.new(0.12, 0.12, 0.05), BLACK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
				weldTo(b, torso, CFrame.new(x, ts.Y * 0.4 - i * 0.22, front - 0.05))
			end
		end
	end
	if u.scarf then
		local sc = newPart("Neckerchief", Vector3.new(ts.X * 0.45, 0.22, ts.Z * 1.05), u.scarf, Enum.Material.Fabric)
		weldTo(sc, torso, CFrame.new(0, ts.Y * 0.47, 0))
	end
end

local function fallbackTemplate(kind)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("NPC") and assets.NPC:FindFirstChild(kind)
	if template then
		return template:Clone()
	end
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = root.CFrame * CFrame.new(0, 1.6, 0)
	head.Parent = model
	model.PrimaryPart = root
	return model
end

local function spawnFallback(kind, cf, opts, rng)
	local model = fallbackTemplate(kind)
	local root = model:FindFirstChild("Root")
	model.PrimaryPart = root
	local skin = pick(SKIN, rng)
	local u = opts.role and UNIFORM[opts.role]
	local shirt = u and u.torso or pick(SHIRTS, rng)
	local pants = u and u.legs or pick(PANTS, rng)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local tag = p:GetAttribute("Paint")
			if tag == "skin" then
				p.Color = skin
			elseif tag == "shirt" then
				p.Color = shirt
			elseif tag == "pants" then
				p.Color = pants
			elseif tag == "hair" then
				p.Color = pick(HAIR, rng)
			end
		end
	end
	if opts.vip or opts.critic then
		local hat = model:FindFirstChild("Hat")
		if hat then
			hat.Transparency = 0
			hat.Color = opts.vip and Color3.fromRGB(212, 175, 55) or Color3.fromRGB(25, 25, 25)
		end
	end
	Util.setCollision(model, false, false)
	Util.weldModel(model, root, true)
	model:PivotTo(cf)
	model.Parent = folder()
	return model
end

-- kind: "Guest" | "Staff"; opts: {role="Cook"|"Waiter"|"Bartender", vip=bool, critic=bool, rng}
function NPCUtil.spawn(kind, cf, opts)
	opts = opts or {}
	local rng = opts.rng or Random.new()
	local useUserRig = kind == "Guest" and #userRigs > 0 and not opts.vip and not opts.critic and rng:NextNumber() < 0.6
	local source = useUserRig and pick(userRigs, rng) or baseRig
	if not source then
		return spawnFallback(kind, cf, opts, rng)
	end
	local model = source:Clone()
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not root or not head then
		model:Destroy()
		return spawnFallback(kind, cf, opts, rng)
	end
	model.PrimaryPart = root
	-- корень аватара может стоять не на высоте 3 (зависит от пропорций тела)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local groundOffset = (hum and hum.HipHeight or 2) + root.Size.Y / 2
	model:SetAttribute("GroundOffset", groundOffset)
	cf = cf * CFrame.new(0, groundOffset - 3, 0)
	local skin = pick(SKIN, rng)
	local clothing = Config.NPC and Config.NPC.Clothing or {}
	if kind == "Staff" then
		local u = UNIFORM[opts.role or "Waiter"] or UNIFORM.Waiter
		setBodyColors(model, skin, u.torso, u.arms, u.legs)
		addUniformDetails(model, u)
		if u.hat == "chef" then
			addChefHat(model, head)
		else
			addHair(model, head, pick(HAIR, rng), rng:NextInteger(1, 3))
		end
		local c = clothing[opts.role or ""]
		if c then
			addClothing(model, c.shirt, c.pants)
		end
	elseif not useUserRig then
		local shirt = pick(SHIRTS, rng)
		local pants = pick(PANTS, rng)
		if opts.vip then
			shirt, pants = Color3.fromRGB(30, 30, 40), Color3.fromRGB(30, 30, 40)
		elseif opts.critic then
			shirt, pants = Color3.fromRGB(110, 110, 115), Color3.fromRGB(50, 50, 55)
		end
		setBodyColors(model, skin, shirt, rng:NextNumber() < 0.5 and shirt or skin, pants)
		local shirts = clothing.guestShirts or {}
		local pantsIds = clothing.guestPants or {}
		if #shirts > 0 and rng:NextNumber() < 0.7 then
			addClothing(model, pick(shirts, rng), #pantsIds > 0 and pick(pantsIds, rng) or 0)
		end
		if opts.vip then
			addHair(model, head, pick(HAIR, rng), 1)
			addTopHat(model, head, Color3.fromRGB(212, 175, 55))
		elseif opts.critic then
			addHair(model, head, pick(HAIR, rng), 1)
			addTopHat(model, head, BLACK)
			local glasses = newPart("Glasses", Vector3.new(head.Size.X * 0.8, 0.18, 0.06), BLACK)
			weldTo(glasses, head, CFrame.new(0, head.Size.Y * 0.1, -(head.Size.Z / 2 + 0.03)))
		else
			addHair(model, head, pick(HAIR, rng), rng:NextInteger(1, 4))
		end
	end
	-- physics off: anchored root, everything else follows through Motor6D/Weld
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Anchored = p == root
			if p ~= root then
				p.Massless = true
			end
		end
	end
	model:PivotTo(cf)
	model.Parent = folder()
	NPCUtil.playAnim(model, "idle")
	return model
end

-- ===================== ANIMATIONS =====================
local tracks = setmetatable({}, { __mode = "k" })

local function loadTracks(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local set = {}
	for name, id in pairs(Config.NPC and Config.NPC.Animations or {}) do
		if id ~= "" then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				track.Looped = true
				track.Priority = name == "sit" and Enum.AnimationPriority.Action or Enum.AnimationPriority.Movement
				set[name] = track
			end
		end
	end
	tracks[model] = set
	return set
end

-- name: "idle" | "walk" | "sit"
function NPCUtil.playAnim(model, name)
	if not model then
		return
	end
	local set = tracks[model] or loadTracks(model)
	if not set then
		return
	end
	if set.current == name then
		return
	end
	for n, t in pairs(set) do
		if type(n) == "string" and n ~= "current" and n ~= name and typeof(t) == "Instance" then
			t:Stop(0.2)
		end
	end
	local t = set[name]
	if t then
		t:Play(0.2)
	end
	set.current = name
end

-- seat a guest (sitting animation)
function NPCUtil.sit(model, cf)
	if model and model.PrimaryPart then
		model.PrimaryPart.CFrame = cf
		NPCUtil.playAnim(model, "sit")
	end
end

-- Walk along points (Vector3 list) at speed (studs/s). Returns a handle with :Cancel().
function NPCUtil.walk(model, points, speed, onDone)
	local root = model.PrimaryPart
	local handle = { cancelled = false }
	function handle:Cancel()
		self.cancelled = true
		if self.tween then
			self.tween:Cancel()
		end
	end
	task.spawn(function()
		NPCUtil.playAnim(model, "walk")
		for _, target in ipairs(points) do
			if handle.cancelled or not model.Parent then
				return
			end
			local from = root.Position
			local flatTarget = Vector3.new(target.X, target.Y + (model:GetAttribute("GroundOffset") or 3), target.Z)
			local dist = (flatTarget - from).Magnitude
			if dist > 0.2 then
				local look = Vector3.new(flatTarget.X, from.Y, flatTarget.Z)
				local cfTarget
				if (look - from).Magnitude > 0.05 then
					cfTarget = CFrame.lookAt(flatTarget, flatTarget + (look - from).Unit)
				else
					cfTarget = CFrame.new(flatTarget) * root.CFrame.Rotation
				end
				-- сначала мгновенно повернуться в сторону цели
				if (look - from).Magnitude > 0.05 then
					root.CFrame = CFrame.lookAt(from, look)
				end
				local tween = TweenService:Create(root, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), { CFrame = cfTarget })
				handle.tween = tween
				tween:Play()
				tween.Completed:Wait()
			end
		end
		if not handle.cancelled then
			NPCUtil.playAnim(model, "idle")
			if onDone then
				onDone()
			end
		end
	end)
	return handle
end

function NPCUtil.place(model, cf)
	if model and model.PrimaryPart then
		model.PrimaryPart.CFrame = cf
	end
end

-- Billboard with icon/text above the NPC
function NPCUtil.bubble(model, text, color)
	if not model or not model.Parent then
		return
	end
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	local gui = head:FindFirstChild("Bubble")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Bubble"
		gui.Size = UDim2.fromOffset(110, 46)
		gui.StudsOffset = Vector3.new(0, 2.4, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		local frame = Instance.new("Frame")
		frame.Name = "Frame"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		frame.BackgroundTransparency = 0.05
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(40, 40, 60)
		stroke.Parent = frame
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -8, 1, -12)
		label.Position = UDim2.fromOffset(4, 2)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(30, 30, 40)
		label.Parent = frame
		local barBg = Instance.new("Frame")
		barBg.Name = "BarBg"
		barBg.Size = UDim2.new(1, -16, 0, 5)
		barBg.Position = UDim2.new(0, 8, 1, -9)
		barBg.BackgroundColor3 = Color3.fromRGB(220, 220, 225)
		barBg.BorderSizePixel = 0
		barBg.Parent = frame
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.Size = UDim2.fromScale(1, 1)
		bar.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
		bar.BorderSizePixel = 0
		bar.Parent = barBg
		frame.Parent = gui
		gui.Parent = head
	end
	if text == nil then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	gui.Frame.Text.Text = text
	gui.Frame.UIStroke.Color = color or Color3.fromRGB(40, 40, 60)
end

function NPCUtil.patience(model, fraction)
	local head = model and (model:FindFirstChild("Head") or model.PrimaryPart)
	local gui = head and head:FindFirstChild("Bubble")
	if not gui then
		return
	end
	local bar = gui.Frame.BarBg.Bar
	fraction = math.clamp(fraction, 0, 1)
	bar.Size = UDim2.fromScale(fraction, 1)
	bar.BackgroundColor3 = Color3.fromRGB(230, 70, 60):Lerp(Color3.fromRGB(80, 200, 100), fraction)
	gui.Frame.BarBg.Visible = fraction < 0.999
end

function NPCUtil.destroy(model)
	if model then
		model:Destroy()
	end
end

return NPCUtil
