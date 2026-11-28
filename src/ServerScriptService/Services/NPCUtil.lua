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
	part.CFrame = target.CFrame * c0
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

-- hair sits on the crown and slightly back, never over the face
local function addHair(model, head, color, style)
	local hs = head.Size
	local function cap(scaleY, y)
		local c = newPart("Hair", Vector3.new(hs.X * 1.06, hs.Y * scaleY, hs.Z * 1.06), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(c, head, CFrame.new(0, hs.Y * y, hs.Z * 0.08))
	end
	if style == 1 then
		cap(0.5, 0.38) -- короткая
	elseif style == 2 then
		cap(0.55, 0.36) -- длинная
		local back = newPart("HairBack", Vector3.new(hs.X * 1.0, hs.Y * 0.95, hs.Z * 0.3), color)
		weldTo(back, head, CFrame.new(0, -hs.Y * 0.05, hs.Z * 0.42))
	elseif style == 3 then
		cap(0.5, 0.38) -- пучок
		local bun = newPart("HairBun", Vector3.new(hs.X * 0.42, hs.X * 0.42, hs.X * 0.42), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(bun, head, CFrame.new(0, hs.Y * 0.6, hs.Z * 0.32))
	elseif style == 4 then
		cap(0.45, 0.42) -- коротко стриженные (под кепку)
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

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function addExtras(model, head, look, rng)
	local torso = model:FindFirstChild("UpperTorso")
	local lower = model:FindFirstChild("LowerTorso")
	if not torso then
		return
	end
	local hs, ts = head.Size, torso.Size
	local front = -(ts.Z / 2 + 0.03)
	local hfront = -(hs.Z / 2 + 0.03)
	local set = {}
	for _, e in ipairs(look.extras or {}) do
		set[e] = true
	end
	if set.shirtFront or set.blazer then
		local sf = newPart("ShirtFront", Vector3.new(ts.X * 0.32, ts.Y * 0.92, 0.06), c3(look.shirt or { 245, 245, 245 }))
		weldTo(sf, torso, CFrame.new(0, 0.02, front))
	end
	if set.tie then
		local col = c3(look.tie or { 150, 20, 40 })
		local knot = newPart("TieKnot", Vector3.new(0.18, 0.16, 0.08), col)
		weldTo(knot, torso, CFrame.new(0, ts.Y * 0.4, front - 0.05))
		local tie = newPart("Tie", Vector3.new(0.2, ts.Y * 0.62, 0.06), col)
		weldTo(tie, torso, CFrame.new(0, ts.Y * 0.04, front - 0.05))
	end
	if set.bow then
		for _, x in ipairs({ -0.15, 0.15 }) do
			local b = newPart("Bow", Vector3.new(0.28, 0.2, 0.08), BLACK)
			weldTo(b, torso, CFrame.new(x, ts.Y * 0.42, front - 0.05) * CFrame.Angles(0, 0, math.rad(x < 0 and 15 or -15)))
		end
	end
	if set.glasses or set.sunglasses then
		local col = set.sunglasses and Color3.fromRGB(15, 15, 20) or Color3.fromRGB(40, 40, 45)
		local bar = newPart("Glasses", Vector3.new(hs.X * 0.82, 0.06, 0.05), col)
		weldTo(bar, head, CFrame.new(0, hs.Y * 0.14, hfront - 0.02))
		for _, x in ipairs({ -0.2, 0.2 }) do
			local lens = newPart("Lens", Vector3.new(0.3, 0.22, 0.04), col)
			lens.Transparency = set.sunglasses and 0 or 0.6
			weldTo(lens, head, CFrame.new(x * hs.X / 1.2, hs.Y * 0.1, hfront - 0.03))
		end
	end
	if set.backpack then
		local bp = newPart("Backpack", Vector3.new(ts.X * 0.7, ts.Y * 0.85, 0.6), pick({ Color3.fromRGB(200, 60, 50), Color3.fromRGB(40, 90, 170), Color3.fromRGB(60, 60, 65) }, rng), Enum.Material.Fabric)
		weldTo(bp, torso, CFrame.new(0, -0.05, ts.Z / 2 + 0.3))
	end
	if set.camera then
		local cam = newPart("Camera", Vector3.new(0.55, 0.38, 0.3), Color3.fromRGB(25, 25, 25))
		weldTo(cam, torso, CFrame.new(0.3, -ts.Y * 0.2, front - 0.15))
		local lens = newPart("CameraLens", Vector3.new(0.18, 0.26, 0.26), Color3.fromRGB(90, 90, 95), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(lens, torso, CFrame.new(0.3, -ts.Y * 0.2, front - 0.36) * CFrame.Angles(0, math.rad(90), 0))
	end
	if set.flowerShirt then
		local colors = { Color3.fromRGB(250, 220, 60), Color3.fromRGB(250, 120, 150), Color3.fromRGB(255, 255, 255) }
		for i = 1, 6 do
			local dot = newPart("Flower", Vector3.new(0.22, 0.22, 0.05), colors[(i % 3) + 1], Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			weldTo(dot, torso, CFrame.new(((i % 3) - 1) * 0.55, (i > 3 and -0.35 or 0.3), front - 0.02))
		end
	end
	if set.cap then
		local col = pick({ Color3.fromRGB(200, 40, 40), Color3.fromRGB(30, 30, 35), Color3.fromRGB(40, 90, 180) }, rng)
		local capTop = newPart("Cap", Vector3.new(hs.X * 1.1, hs.Y * 0.48, hs.Z * 1.1), col, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(capTop, head, CFrame.new(0, hs.Y * 0.42, hs.Z * 0.04))
		local visor = newPart("CapVisor", Vector3.new(hs.X * 0.75, 0.08, hs.Z * 0.45), col)
		weldTo(visor, head, CFrame.new(0, hs.Y * 0.3, -hs.Z * 0.62))
	end
	if set.beanie then
		local col = pick({ Color3.fromRGB(240, 230, 200), Color3.fromRGB(180, 40, 50), Color3.fromRGB(60, 90, 140) }, rng)
		local b = newPart("Beanie", Vector3.new(hs.X * 1.12, hs.Y * 0.62, hs.Z * 1.12), col, Enum.Material.Fabric, Enum.PartType.Ball)
		weldTo(b, head, CFrame.new(0, hs.Y * 0.42, hs.Z * 0.03))
	end
	if set.headband then
		local hb = newPart("Headband", Vector3.new(0.14, hs.X * 1.06, hs.X * 1.06), Color3.fromRGB(240, 90, 130), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(hb, head, CFrame.new(0, hs.Y * 0.36, hs.Z * 0.05) * CFrame.Angles(0, 0, math.rad(90)))
	end
	if set.scarf then
		local sc = newPart("Scarf", Vector3.new(ts.X * 0.6, 0.35, ts.Z * 1.15), Color3.fromRGB(200, 50, 50), Enum.Material.Fabric)
		weldTo(sc, torso, CFrame.new(0, ts.Y * 0.47, 0))
		local tail = newPart("ScarfTail", Vector3.new(0.3, ts.Y * 0.5, 0.08), Color3.fromRGB(200, 50, 50), Enum.Material.Fabric)
		weldTo(tail, torso, CFrame.new(0.35, ts.Y * 0.15, front - 0.03))
	end
	if set.necklace then
		local nk = newPart("Necklace", Vector3.new(ts.X * 0.4, 0.08, 0.06), Color3.fromRGB(230, 195, 80), Enum.Material.Metal)
		weldTo(nk, torso, CFrame.new(0, ts.Y * 0.36, front - 0.03))
		local gem = newPart("Gem", Vector3.new(0.16, 0.16, 0.08), Color3.fromRGB(80, 200, 255), Enum.Material.Glass, Enum.PartType.Ball)
		weldTo(gem, torso, CFrame.new(0, ts.Y * 0.3, front - 0.05))
	end
	if set.watch then
		local hand = model:FindFirstChild("LeftLowerArm") or model:FindFirstChild("LeftHand")
		if hand then
			local w = newPart("Watch", Vector3.new(hand.Size.X * 1.05, 0.18, hand.Size.Z * 1.05), Color3.fromRGB(212, 175, 55), Enum.Material.Metal)
			weldTo(w, hand, CFrame.new(0, -hand.Size.Y * 0.4, 0))
		end
	end
	if set.purse and lower then
		local pc = c3(look.skirt or look.torso)
		local pu = newPart("Purse", Vector3.new(0.3, 0.6, 0.8), pc:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Fabric)
		weldTo(pu, lower, CFrame.new(1.15, -0.3, 0))
	end
	if set.skirt and lower then
		local ls = lower.Size
		local len = look.long and 2.7 or 1.5
		local sk = newPart("Skirt", Vector3.new(ls.X * 1.12, len, ls.Z * 1.3), c3(look.skirt or look.torso), Enum.Material.Fabric)
		weldTo(sk, lower, CFrame.new(0, -len / 2 + ls.Y / 2, 0))
	end
end

local GuestLooks = require(Shared.Data.GuestLooks)

local function chooseLook(opts, rng)
	local stars = opts.stars or 1
	if opts.vip then
		local formal = {}
		for _, id in ipairs({ "black_suit", "tuxedo", "evening_gown", "white_suit", "navy_suit" }) do
			table.insert(formal, GuestLooks.ById[id])
		end
		return pick(formal, rng)
	elseif opts.critic then
		return GuestLooks.ById.smart_casual
	elseif opts.look then
		return GuestLooks.ById[opts.look]
	end
	local typed, any = GuestLooks.pool(stars, opts.guestType)
	if typed ~= any and rng:NextNumber() < 0.7 then
		return pick(typed, rng)
	end
	return pick(any, rng)
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
	-- стандартное лицо Roblox (у аватара по умолчанию его может не быть)
	if not head:FindFirstChildOfClass("Decal") then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Face = Enum.NormalId.Front
		face.Texture = "rbxasset://textures/face.png"
		face.Parent = head
	end
	-- корень аватара может стоять не на высоте 3 (зависит от пропорций тела)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local groundOffset = (hum and hum.HipHeight or 2) + root.Size.Y / 2
	model:SetAttribute("GroundOffset", groundOffset)
	cf = cf * CFrame.new(0, groundOffset - 3, 0)
	local skin = pick(SKIN, rng)
	local clothing = Config.NPC and Config.NPC.Clothing or {}
	if kind == "Staff" and opts.role == "Robot" then
		local metal = Color3.fromRGB(175, 185, 200)
		setBodyColors(model, metal, Color3.fromRGB(70, 130, 200), metal, Color3.fromRGB(90, 95, 105))
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") and p ~= root then
				p.Material = Enum.Material.Metal
				p.Reflectance = 0.1
			end
		end
		for _, d in ipairs(head:GetChildren()) do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		local hs = head.Size
		local visor = newPart("Visor", Vector3.new(hs.X * 0.8, hs.Y * 0.28, 0.08), Color3.fromRGB(60, 230, 255), Enum.Material.Neon)
		weldTo(visor, head, CFrame.new(0, hs.Y * 0.08, -(hs.Z / 2 + 0.03)))
		local antenna = newPart("Antenna", Vector3.new(0.1, 0.7, 0.1), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
		weldTo(antenna, head, CFrame.new(0, hs.Y * 0.5 + 0.35, 0))
		local bulb = newPart("AntennaLight", Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(255, 80, 80), Enum.Material.Neon, Enum.PartType.Ball)
		weldTo(bulb, head, CFrame.new(0, hs.Y * 0.5 + 0.75, 0))
		addChefHat(model, head)
	elseif kind == "Staff" then
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
		local look = chooseLook(opts, rng)
		local torsoC = c3(look.torso)
		local arms = look.arms == "skin" and skin or (look.arms == "torso" and torsoC or c3(look.arms))
		local legs = look.legs == "skin" and skin or c3(look.legs)
		setBodyColors(model, skin, torsoC, arms, legs)
		model:SetAttribute("Look", look.id)
		local shirts = clothing.guestShirts or {}
		local pantsIds = clothing.guestPants or {}
		if #shirts > 0 and (opts.stars or 1) <= 2 and rng:NextNumber() < 0.5 then
			addClothing(model, pick(shirts, rng), #pantsIds > 0 and pick(pantsIds, rng) or 0)
		end
		local set = {}
		for _, e in ipairs(look.extras or {}) do
			set[e] = true
		end
		if not (set.cap or set.beanie) then
			addHair(model, head, pick(HAIR, rng), look.hair or 1)
		end
		addExtras(model, head, look, rng)
		if opts.vip then
			addTopHat(model, head, Color3.fromRGB(212, 175, 55))
		elseif opts.critic then
			addTopHat(model, head, BLACK)
			if not set.glasses then
				addExtras(model, head, { extras = { "glasses" }, torso = look.torso }, rng)
			end
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
