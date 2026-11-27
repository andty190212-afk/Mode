-- NPCUtil: lightweight NPC characters (no Humanoid, anchored root moved by tweens)
-- so 8 restaurants with dozens of NPCs run without physics/pathfinding cost.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Util = require(ReplicatedStorage.Shared.Util)

local NPCUtil = {}

local SKIN = {
	Color3.fromRGB(255, 220, 177),
	Color3.fromRGB(234, 192, 134),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(255, 205, 148),
	Color3.fromRGB(110, 70, 40),
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
}
local PANTS = {
	Color3.fromRGB(40, 50, 80),
	Color3.fromRGB(60, 60, 60),
	Color3.fromRGB(110, 80, 50),
	Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(80, 100, 140),
}
local HAIR = {
	Color3.fromRGB(40, 25, 15),
	Color3.fromRGB(90, 60, 30),
	Color3.fromRGB(220, 190, 110),
	Color3.fromRGB(20, 20, 20),
	Color3.fromRGB(160, 60, 30),
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

-- kind: "Guest" | "Staff"; opts: {shirt=Color3, vip=bool, critic=bool, hat="chef"|"none", rng}
function NPCUtil.spawn(kind, cf, opts)
	opts = opts or {}
	local rng = opts.rng or Random.new()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("NPC") and assets.NPC:FindFirstChild(kind)
	local model
	if template then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(2, 2, 1)
		root.Transparency = 1
		root.Parent = model
		local body = Instance.new("Part")
		body.Name = "Torso"
		body.Size = Vector3.new(2, 2, 1)
		body.CFrame = root.CFrame
		body.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.CFrame = root.CFrame * CFrame.new(0, 1.6, 0)
		head.Parent = model
		model.PrimaryPart = root
	end
	local root = model:FindFirstChild("Root")
	model.PrimaryPart = root
	local skin = pick(SKIN, rng)
	local shirt = opts.shirt or pick(SHIRTS, rng)
	local pants = pick(PANTS, rng)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local tag = p:GetAttribute("Paint")
			if tag == "skin" or p.Name == "Head" or p.Name:find("Arm") then
				p.Color = skin
			elseif tag == "shirt" or p.Name == "Torso" then
				p.Color = shirt
			elseif tag == "pants" or p.Name:find("Leg") then
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
		for _, target in ipairs(points) do
			if handle.cancelled or not model.Parent then
				return
			end
			local from = root.Position
			local flatTarget = Vector3.new(target.X, target.Y + 3, target.Z)
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
		if not handle.cancelled and onDone then
			onDone()
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
