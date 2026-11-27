-- Spectacular, large-scale ability effects (client only, no assets needed): Roblox explosions,
-- fire, smoke, sparkles, particle bursts, flying debris, lightning bolts, beams, tornadoes,
-- shock waves, light flashes and camera shake. Everything scales with the weapon rarity:
-- a Secret skill is about twice as big and much louder than a Common one.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Rarities"))

local AbilityFx = {}
local player = Players.LocalPlayer
local rad = math.rad
local rnd = Random.new()

-- ===================== TOOLKIT =====================
local folder
local function root()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "AbilityFx"
		folder.Parent = workspace
	end
	return folder
end

local function part(props, life)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = root()
	Debris:AddItem(p, life or 2)
	return p
end

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function col(c, fallback)
	if type(c) == "table" then
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	return fallback or Color3.fromRGB(255, 200, 80)
end

local function light(pos, color, range, brightness, life)
	local p = part({ Size = Vector3.new(0.1, 0.1, 0.1), CFrame = CFrame.new(pos), Transparency = 1 }, life + 0.1)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
	tween(l, life, { Brightness = 0 })
end

local function sphere(pos, r, color, life, opts)
	opts = opts or {}
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (opts.from or 1), CFrame = CFrame.new(pos), Color = color, Transparency = opts.t or 0.15, Material = opts.material or Enum.Material.Neon }, life + 0.1)
	tween(p, life, { Size = Vector3.one * r * 2, Transparency = opts.endT or 1 })
	return p
end

local function ring(pos, r, color, life, thick, height)
	local p = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height or 0.6, 2, 2), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, rad(90)), Color = color, Transparency = 0.1 }, life + 0.1)
	tween(p, life, { Size = Vector3.new((height or 0.6) * (thick or 1), r * 2, r * 2), Transparency = 1 })
	return p
end

local function pillar(pos, r, h, color, life)
	local p = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, r * 2, r * 2), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, rad(90)), Color = color, Transparency = 0.25 }, life + 0.1)
	tween(p, life * 0.35, { Size = Vector3.new(h, r * 2, r * 2), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, rad(90)) })
	task.delay(life * 0.35, function()
		tween(p, life * 0.65, { Size = Vector3.new(h, 0.1, 0.1), Transparency = 1 })
	end)
end

-- legacy-style emitters that need no texture assets
local function emitter(pos, kind, props, life)
	local p = part({ Size = Vector3.one * 0.2, CFrame = CFrame.new(pos), Transparency = 1 }, life + 2)
	local e = Instance.new(kind)
	for k, v in pairs(props or {}) do
		e[k] = v
	end
	e.Parent = p
	task.delay(life, function()
		e.Enabled = false
	end)
	return p, e
end

local function fire(pos, size, color, life)
	return emitter(pos, "Fire", { Size = size, Heat = size * 1.5, Color = color or Color3.fromRGB(255, 120, 30), SecondaryColor = Color3.fromRGB(255, 220, 90) }, life)
end

local function smoke(pos, size, color, life)
	return emitter(pos, "Smoke", { Size = size, Opacity = 0.35, RiseVelocity = 6, Color = color or Color3.fromRGB(120, 120, 120) }, life)
end

local function sparkles(pos, color, life)
	return emitter(pos, "Sparkles", { SparkleColor = color }, life)
end

-- particle burst (default ParticleEmitter texture is a soft sparkle)
local function burst(pos, color, count, speed, size, life)
	local p = part({ Size = Vector3.one * 0.2, CFrame = CFrame.new(pos), Transparency = 1 }, 3)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0, 1)
	pe.Lifetime = NumberRange.new(life * 0.6, life)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 2
	pe.Rate = 0
	pe.Parent = p
	pe:Emit(count)
end

-- unanchored chunks thrown into the air
local function debris(pos, n, color, size, speed, material)
	for _ = 1, n do
		local s = size * rnd:NextNumber(0.6, 1.3)
		local p = Instance.new("Part")
		p.Size = Vector3.new(s, s * 0.8, s)
		p.CFrame = CFrame.new(pos + Vector3.new(rnd:NextNumber(-1, 1), 0.5, rnd:NextNumber(-1, 1))) * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0)
		p.Color = color
		p.Material = material or Enum.Material.Slate
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = root()
		p.AssemblyLinearVelocity = Vector3.new(rnd:NextNumber(-1, 1), rnd:NextNumber(0.8, 1.6), rnd:NextNumber(-1, 1)) * speed
		p.AssemblyAngularVelocity = Vector3.new(rnd:NextNumber(-10, 10), rnd:NextNumber(-10, 10), rnd:NextNumber(-10, 10))
		Debris:AddItem(p, 2.5)
		task.delay(1.8, function()
			if p.Parent then
				tween(p, 0.6, { Transparency = 1, Size = p.Size * 0.3 })
			end
		end)
	end
end

-- the built-in Roblox explosion (visual only: no pressure, no joint breaking)
local function boom(pos, r)
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = r
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = root()
end

local function lightning(a, b, color, width, life)
	local points = { a }
	local segs = math.max(4, math.floor((b - a).Magnitude / 4))
	for i = 1, segs - 1 do
		local t = i / segs
		local jitter = Vector3.new(rnd:NextNumber(-1, 1), rnd:NextNumber(-1, 1), rnd:NextNumber(-1, 1)) * ((b - a).Magnitude / segs) * 0.6
		table.insert(points, a:Lerp(b, t) + jitter)
	end
	table.insert(points, b)
	for i = 1, #points - 1 do
		local p1, p2 = points[i], points[i + 1]
		local d = (p2 - p1).Magnitude
		local seg = part({ Size = Vector3.new(width, width, d), CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Color = color }, life + 0.1)
		tween(seg, life, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, d) })
	end
	light(b, color, 30, 6, life + 0.2)
end

local function beam(a, b, color, width, life)
	local d = (b - a).Magnitude
	local core = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(d, width * 0.5, width * 0.5), CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, rad(90), 0), Color = Color3.new(1, 1, 1) }, life + 0.1)
	local glow = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(d, width, width), CFrame = core.CFrame, Color = color, Transparency = 0.4 }, life + 0.1)
	tween(core, life, { Size = Vector3.new(d, 0.05, 0.05), Transparency = 1 })
	tween(glow, life, { Size = Vector3.new(d, width * 2, width * 2), Transparency = 1 })
end

local function projectile(a, b, color, size, time, arc, trail)
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(a), Color = color }, time + 0.2)
	if trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, size / 2, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -size / 2, 0)
		a1.Parent = p
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(color)
		tr.LightEmission = 1
		tr.Lifetime = 0.35
		tr.Transparency = NumberSequence.new(0, 1)
		tr.Parent = p
	end
	if arc and arc > 0 then
		task.spawn(function()
			local t0 = os.clock()
			while p.Parent do
				local t = math.min(1, (os.clock() - t0) / time)
				local pos = a:Lerp(b, t) + Vector3.new(0, math.sin(t * math.pi) * arc, 0)
				p.CFrame = CFrame.new(pos)
				if t >= 1 then
					break
				end
				RunService.Heartbeat:Wait()
			end
		end)
	else
		tween(p, time, { CFrame = CFrame.new(b) }, Enum.EasingStyle.Linear)
	end
	return p
end

local function shake(pos, power, dur)
	local cam = workspace.CurrentCamera
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	if not cam or not r then
		return
	end
	local d = (r.Position - pos).Magnitude
	if d > 120 then
		return
	end
	local k = power * (1 - d / 120)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur do
			local f = k * (1 - (os.clock() - t0) / dur)
			cam.CFrame = cam.CFrame * CFrame.Angles(rnd:NextNumber(-1, 1) * f * 0.01, rnd:NextNumber(-1, 1) * f * 0.01, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

local function screenFlash(color, strength, dur)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = color
	cc.Brightness = strength
	cc.Parent = Lighting
	tween(cc, dur, { Brightness = 0, TintColor = Color3.new(1, 1, 1) })
	Debris:AddItem(cc, dur + 0.1)
end

local function charOf(userId)
	local p = Players:GetPlayerByUserId(userId or 0)
	return p and p.Character
end

local function follow(p, userId, dur, offset)
	local char = charOf(userId)
	local r = char and char:FindFirstChild("HumanoidRootPart")
	if not r then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while p.Parent and os.clock() - t0 < dur do
			p.CFrame = r.CFrame * (offset or CFrame.new())
			RunService.Heartbeat:Wait()
		end
	end)
end

local function ground(pos)
	return Vector3.new(pos.X, pos.Y - 2.6, pos.Z)
end

-- one big impact used by many skills
local function impact(pos, r, color, S, opts)
	opts = opts or {}
	sphere(pos, r * 0.6, color, 0.35, { t = 0 })
	sphere(pos, r, Color3.new(1, 1, 1), 0.25, { t = 0.3 })
	ring(ground(pos), r * 1.4, color, 0.6, 0.2, 1.2)
	burst(pos, color, math.floor(25 * S), 30 * S, 1.2 * S, 0.8)
	light(pos, color, r * 4, 8, 0.6)
	if opts.boom then
		boom(pos, r)
	end
	if opts.debris then
		debris(ground(pos), math.floor(6 * S), opts.debrisColor or Color3.fromRGB(110, 100, 90), 0.9 * S, 35)
	end
	if opts.fire then
		fire(pos, r * 0.6, color, 1.2)
	end
	if opts.smoke then
		smoke(ground(pos), r * 0.5, opts.smokeColor, 1)
	end
	shake(pos, (opts.shake or 3) * S, 0.4 + S * 0.15)
end

-- ===================== THE 30 SKILLS =====================
local FX = {}

FX.home_run = function(d, c, S)
	local p = d.from + d.dir * 6
	impact(p, 4 * S, Color3.fromRGB(255, 230, 120), S, { debris = true, shake = 4 })
	for i = 1, 5 do
		local a = rad(i * 72)
		projectile(p, p + Vector3.new(math.cos(a) * 8, 4, math.sin(a) * 8) * S, Color3.fromRGB(255, 255, 160), 0.6, 0.4, 0, true)
	end
end

FX.guard = function(d, c, S)
	local s = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Color = Color3.fromRGB(180, 220, 255), Material = Enum.Material.ForceField, Transparency = 0.2 }, (d.dur or 2) + 0.2)
	follow(s, d.userId, d.dur or 2)
	sparkles(d.from, Color3.fromRGB(150, 200, 255), d.dur or 2)
end

FX.spin = function(d, c, S)
	local r = 9 * S
	for k = 1, 3 do
		task.delay(k * 0.08, function()
			ring(d.from, r, c, 0.45, 0.3, 2)
		end)
	end
	local blade = part({ Size = Vector3.new(r * 2, 0.4, 1.2), CFrame = CFrame.new(d.from), Color = c, Transparency = 0.2 }, 0.6)
	tween(blade, 0.5, { CFrame = CFrame.new(d.from) * CFrame.Angles(0, rad(720), 0), Transparency = 1 }, Enum.EasingStyle.Linear)
	smoke(ground(d.from), 4 * S, nil, 0.5)
	burst(d.from, c, math.floor(30 * S), 25, 1, 0.6)
end

FX.coconut_bomb = function(d, c, S)
	local t = 0.75
	projectile(d.from + Vector3.new(0, 2, 0), d.point, Color3.fromRGB(110, 70, 40), 1.6, t, 14, true)
	task.delay(t, function()
		impact(d.point, 8 * S, Color3.fromRGB(255, 170, 60), S, { boom = true, debris = true, debrisColor = Color3.fromRGB(120, 80, 50), smoke = true })
	end)
end

FX.charge = function(d, c, S)
	local to = d.to or (d.from + (d.dir or Vector3.zAxis) * 20)
	for i = 0, 5 do
		local pos = d.from:Lerp(to, i / 5)
		local ghost = part({ Size = Vector3.new(2, 5, 1), CFrame = CFrame.lookAt(pos, to), Color = c, Transparency = 0.4 }, 0.6)
		tween(ghost, 0.5, { Transparency = 1, Size = Vector3.new(2.5, 5.5, 0.3) })
	end
	smoke(ground(d.from), 3, nil, 0.4)
	impact(to, 4 * S, c, S, { debris = true, smoke = true, shake = 3 })
end

FX.bubble_trap = function(d, c, S)
	local to = d.to or d.from
	projectile(d.from + Vector3.new(0, 2, 0), to, Color3.fromRGB(180, 230, 255), 2, 0.35, 0, true)
	task.delay(0.35, function()
		local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(to), Color = Color3.fromRGB(170, 225, 255), Material = Enum.Material.Glass, Transparency = 0.5, Reflectance = 0.3 }, 1.6)
		tween(b, 0.25, { Size = Vector3.one * 8 * S }, Enum.EasingStyle.Back)
		follow(b, d.target, 1.2)
		task.delay(1.25, function()
			burst(b.Position, Color3.fromRGB(200, 240, 255), 40, 25, 0.8, 0.5)
			b:Destroy()
		end)
	end)
end

FX.flame_wave = function(d, c, S)
	local dir = d.dir or Vector3.new(0, 0, -1)
	for k = 1, 8 do
		task.delay(k * 0.05, function()
			for side = -1, 1 do
				local v = CFrame.Angles(0, rad(side * 22), 0):VectorToWorldSpace(dir)
				local pos = d.from + v * (k * 2 * S)
				fire(pos, 3 + k * 0.6 * S, Color3.fromRGB(255, 90, 20), 0.6)
				if k % 2 == 0 then
					burst(pos, Color3.fromRGB(255, 140, 40), 6, 10, 0.8, 0.6)
				end
			end
		end)
	end
	light(d.from + dir * 8, Color3.fromRGB(255, 120, 40), 30, 5, 0.8)
end

FX.ice_field = function(d, c, S)
	local center = ground(d.point or d.from)
	local r = 10 * S
	local disk = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1, 1), CFrame = CFrame.new(center) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(180, 230, 255), Material = Enum.Material.Ice, Transparency = 0.2 }, (d.dur or 4) + 0.5)
	tween(disk, 0.3, { Size = Vector3.new(0.3, r * 2, r * 2) })
	task.delay(d.dur or 4, function()
		tween(disk, 0.4, { Transparency = 1 })
	end)
	for k = 1, math.floor(14 * S) do
		local a, dist = rnd:NextNumber(0, 6.28), rnd:NextNumber(2, r)
		local pos = center + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
		local spike = part({ Size = Vector3.new(1, 0.2, 1), CFrame = CFrame.new(pos) * CFrame.Angles(rnd:NextNumber(-0.3, 0.3), a, rnd:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(200, 240, 255), Material = Enum.Material.Ice, Transparency = 0.1 }, (d.dur or 4) + 0.6)
		local h = rnd:NextNumber(2, 5) * S
		tween(spike, 0.25, { Size = Vector3.new(1, h, 1), CFrame = spike.CFrame * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
		task.delay(d.dur or 4, function()
			tween(spike, 0.4, { Transparency = 1 })
		end)
	end
	smoke(center, r * 0.6, Color3.fromRGB(220, 240, 255), d.dur or 4)
	light(center, Color3.fromRGB(150, 220, 255), r * 3, 4, d.dur or 4)
end

FX.hook_pull = function(d, c, S)
	local to = d.to or d.from
	local links = {}
	for i = 1, 12 do
		local l = part({ Size = Vector3.new(0.5, 0.5, 1.2), CFrame = CFrame.new(d.from), Color = Color3.fromRGB(150, 150, 165), Material = Enum.Material.Metal }, 1.2)
		links[i] = l
		tween(l, 0.25, { CFrame = CFrame.lookAt(d.from:Lerp(to, i / 12), to) })
	end
	task.delay(0.3, function()
		for _, l in ipairs(links) do
			tween(l, 0.25, { CFrame = CFrame.new(d.from), Transparency = 1 })
		end
		burst(to, Color3.fromRGB(200, 200, 220), 15, 15, 0.6, 0.4)
	end)
end

FX.static_shock = function(d, c, S)
	local to = d.to or d.from
	for k = 1, math.floor(2 + S) do
		task.delay(k * 0.06, function()
			lightning(to + Vector3.new(rnd:NextNumber(-3, 3), 45, rnd:NextNumber(-3, 3)), to, Color3.fromRGB(255, 255, 160), 0.6 * S, 0.3)
		end)
	end
	impact(to, 4 * S, Color3.fromRGB(255, 240, 120), S, { shake = 3 })
	screenFlash(Color3.fromRGB(255, 255, 200), 0.15, 0.25)
end

FX.tidal_wave = function(d, c, S)
	local dir = d.dir or Vector3.new(0, 0, -1)
	local start = ground(d.from)
	local wave = part({ Size = Vector3.new(14 * S, 1, 3), CFrame = CFrame.lookAt(start, start + dir), Color = Color3.fromRGB(40, 140, 230), Material = Enum.Material.Glass, Transparency = 0.25 }, 1.2)
	local foam = part({ Size = Vector3.new(14 * S, 1, 1.5), CFrame = wave.CFrame, Color = Color3.fromRGB(235, 250, 255), Material = Enum.Material.SmoothPlastic }, 1.2)
	tween(wave, 0.3, { Size = Vector3.new(14 * S, 8 * S, 3), CFrame = CFrame.lookAt(start + Vector3.new(0, 4 * S, 0) + dir * 8, start + Vector3.new(0, 4 * S, 0) + dir * 9) })
	tween(foam, 0.3, { CFrame = CFrame.lookAt(start + Vector3.new(0, 8 * S, 0) + dir * 8, start + Vector3.new(0, 8 * S, 0) + dir * 9) })
	task.delay(0.3, function()
		tween(wave, 0.6, { CFrame = CFrame.lookAt(start + Vector3.new(0, 3, 0) + dir * 32, start + Vector3.new(0, 3, 0) + dir * 33), Transparency = 1 })
		tween(foam, 0.6, { CFrame = CFrame.lookAt(start + Vector3.new(0, 6, 0) + dir * 32, start + Vector3.new(0, 6, 0) + dir * 33), Transparency = 1 })
		for k = 1, 6 do
			task.delay(k * 0.1, function()
				burst(start + dir * (8 + k * 4) + Vector3.new(0, 3, 0), Color3.fromRGB(200, 235, 255), 12, 18, 0.9, 0.6)
			end)
		end
	end)
	shake(d.from, 3 * S, 0.6)
end

FX.reflect = function(d, c, S)
	local dur = d.dur or 3
	for i = 1, 6 do
		local panel = part({ Size = Vector3.new(2.4, 3.2, 0.2), Color = Color3.fromRGB(220, 240, 255), Material = Enum.Material.Glass, Reflectance = 0.7, Transparency = 0.2 }, dur + 0.2)
		local char = charOf(d.userId)
		local r = char and char:FindFirstChild("HumanoidRootPart")
		task.spawn(function()
			local t0 = os.clock()
			while panel.Parent and r and os.clock() - t0 < dur do
				local a = (os.clock() - t0) * 3 + i * 1.047
				panel.CFrame = CFrame.new(r.Position + Vector3.new(math.cos(a) * 4, 0, math.sin(a) * 4)) * CFrame.Angles(0, -a, 0)
				RunService.Heartbeat:Wait()
			end
		end)
	end
	sparkles(d.from, Color3.fromRGB(230, 240, 255), dur)
end

FX.bee_swarm = function(d, c, S)
	local to = d.to or d.from
	for k = 1, math.floor(5 * S) do
		task.delay(k * 0.04, function()
			local b = projectile(d.from + Vector3.new(0, 3, 0), to + Vector3.new(rnd:NextNumber(-2, 2), rnd:NextNumber(0, 2), rnd:NextNumber(-2, 2)), Color3.fromRGB(255, 210, 30), 0.6, (d.travel or 0.4) + rnd:NextNumber(0, 0.2), rnd:NextNumber(2, 6), true)
			local stripe = Instance.new("Part")
			stripe.Size = Vector3.new(0.62, 0.15, 0.62)
			stripe.Color = Color3.new(0.1, 0.1, 0.1)
			stripe.CanCollide = false
			stripe.Anchored = false
			stripe.Massless = true
			stripe.CFrame = b.CFrame
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = b, stripe
			w.Parent = stripe
			stripe.Parent = b
		end)
	end
	task.delay((d.travel or 0.4) + 0.1, function()
		burst(to, Color3.fromRGB(255, 220, 60), 20, 12, 0.6, 0.5)
	end)
end

FX.updraft = function(d, c, S)
	local base = ground(d.from)
	for k = 1, 8 do
		local r = 1.5 + k * 0.7 * S
		local rg = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, r * 2, r * 2), CFrame = CFrame.new(base + Vector3.new(0, k * 2, 0)) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(200, 255, 230), Transparency = 0.55 }, 1.2)
		tween(rg, 1, { CFrame = rg.CFrame * CFrame.new(k * 1.5, 0, 0) * CFrame.Angles(rad(360), 0, 0), Transparency = 1 })
	end
	for _ = 1, math.floor(12 * S) do
		local leaf = part({ Size = Vector3.new(0.6, 0.1, 0.4), CFrame = CFrame.new(base + Vector3.new(rnd:NextNumber(-3, 3), 0, rnd:NextNumber(-3, 3))), Color = Color3.fromRGB(80, 200, 90), Material = Enum.Material.Grass }, 1.4)
		tween(leaf, 1.2, { CFrame = CFrame.new(leaf.Position + Vector3.new(rnd:NextNumber(-6, 6), 18, rnd:NextNumber(-6, 6))) * CFrame.Angles(4, 4, 0), Transparency = 1 })
	end
	smoke(base, 5, Color3.fromRGB(230, 240, 235), 0.6)
end

FX.meteor = function(d, c, S)
	local point = d.point or d.from
	local delay = d.delay or 1.2
	local size = 5 * S
	local start = point + Vector3.new(30, 90, 20)
	local rock = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(start), Color = Color3.fromRGB(80, 50, 40), Material = Enum.Material.Basalt }, delay + 0.2)
	local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 1.4, CFrame = CFrame.new(start), Color = Color3.fromRGB(255, 120, 30), Transparency = 0.5 }, delay + 0.2)
	local f = Instance.new("Fire")
	f.Size, f.Heat = size * 2, 25
	f.Parent = rock
	tween(rock, delay, { CFrame = CFrame.new(point) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(glow, delay, { CFrame = CFrame.new(point) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- target marker on the ground
	local mark = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 11 * S * 2, 11 * S * 2), CFrame = CFrame.new(ground(point)) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(255, 60, 30), Transparency = 0.6 }, delay + 0.1)
	tween(mark, delay, { Transparency = 0.2 })
	task.delay(delay, function()
		impact(point, 11 * S, Color3.fromRGB(255, 120, 30), S, { boom = true, debris = true, fire = true, smoke = true, shake = 9 })
		screenFlash(Color3.fromRGB(255, 200, 150), 0.25, 0.4)
	end)
end

FX.shadow_step = function(d, c, S)
	smoke(d.from, 4, Color3.fromRGB(40, 20, 60), 0.6)
	burst(d.from, Color3.fromRGB(120, 60, 200), 25, 20, 1, 0.5)
	if d.to then
		smoke(d.to, 4, Color3.fromRGB(40, 20, 60), 0.6)
		burst(d.to, Color3.fromRGB(160, 80, 255), 30, 25, 1, 0.5)
		beam(d.from, d.to, Color3.fromRGB(120, 60, 200), 0.6, 0.25)
		impact(d.to, 3 * S, Color3.fromRGB(150, 70, 255), S, { shake = 2 })
	end
end

FX.thorn_traps = function(d, c, S)
	burst(d.from + (d.dir or Vector3.zAxis) * 9, Color3.fromRGB(80, 200, 60), 25, 15, 0.8, 0.6)
	debris(ground(d.from + (d.dir or Vector3.zAxis) * 9), 6, Color3.fromRGB(70, 140, 50), 0.5, 18, Enum.Material.Grass)
end

FX.thorn_snap = function(d, c, S)
	local p = d.point
	for k = 1, 7 do
		local a = rad(k * 51)
		local spike = part({ Size = Vector3.new(0.5, 0.2, 0.5), CFrame = CFrame.new(p) * CFrame.Angles(math.cos(a) * 0.5, 0, math.sin(a) * 0.5), Color = Color3.fromRGB(70, 160, 50), Material = Enum.Material.Grass }, 1.6)
		tween(spike, 0.15, { Size = Vector3.new(0.5, 5, 0.5), CFrame = spike.CFrame * CFrame.new(0, 2.5, 0) }, Enum.EasingStyle.Back)
		task.delay(1.2, function()
			tween(spike, 0.3, { Transparency = 1 })
		end)
	end
	burst(p, Color3.fromRGB(90, 220, 70), 20, 12, 0.8, 0.5)
end

FX.plasma_beam = function(d, c, S)
	local from = d.from + Vector3.new(0, 1.5, 0)
	local to = (d.to or (d.from + (d.dir or Vector3.zAxis) * 60)) + Vector3.new(0, 1.5, 0)
	local orb = part({ Shape = Enum.PartType.Ball, Size = Vector3.one, CFrame = CFrame.new(from + (to - from).Unit * 2), Color = c }, 0.5)
	tween(orb, 0.2, { Size = Vector3.one * 3 * S })
	task.delay(0.15, function()
		beam(from, to, c, 2.5 * S, 0.6)
		for k = 1, 6 do
			burst(from:Lerp(to, k / 6), c, 10, 12, 0.7, 0.5)
		end
		impact(to, 4 * S, c, S, { shake = 3 })
		light(from, c, 40, 6, 0.6)
	end)
end

FX.storm_aura = function(d, c, S)
	local dur = d.dur or 5
	local r = 13 * S
	local cloud = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, r * 2.2, r * 2.2), Color = Color3.fromRGB(70, 75, 95), Material = Enum.Material.SmoothPlastic, Transparency = 0.35 }, dur + 0.2)
	follow(cloud, d.userId, dur, CFrame.new(0, 16, 0) * CFrame.Angles(0, 0, rad(90)))
	local swirl = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, r * 2, r * 2), Color = Color3.fromRGB(150, 170, 255), Transparency = 0.6 }, dur + 0.2)
	follow(swirl, d.userId, dur, CFrame.new(0, -2.4, 0) * CFrame.Angles(0, 0, rad(90)))
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for k = 1, math.floor(dur * 2.5 * S) do
		task.delay(k * 0.4 / S, function()
			if hrp and hrp.Parent then
				local a, dist = rnd:NextNumber(0, 6.28), rnd:NextNumber(3, r)
				local hit = hrp.Position + Vector3.new(math.cos(a) * dist, -2.5, math.sin(a) * dist)
				lightning(hit + Vector3.new(0, 16, 0), hit, Color3.fromRGB(190, 210, 255), 0.5, 0.25)
				burst(hit, Color3.fromRGB(200, 220, 255), 8, 10, 0.6, 0.4)
			end
		end)
	end
end

FX.fire_rain = function(d, c, S)
	local p = d.point or d.from
	local arrowStart = p + Vector3.new(rnd:NextNumber(-6, 6), 60, rnd:NextNumber(-6, 6))
	projectile(arrowStart, p, Color3.fromRGB(255, 150, 40), 0.8 * S, d.delay or 0.35, 0, true)
	task.delay(d.delay or 0.35, function()
		impact(p, 5 * S, Color3.fromRGB(255, 110, 20), S, { fire = true, shake = 2 })
	end)
end

FX.summon_golem = function(d, c, S)
	local p = ground(d.to or d.from)
	for k = 1, 6 do
		local a = rad(k * 60)
		local crack = part({ Size = Vector3.new(0.4, 0.2, 6 * S), CFrame = CFrame.new(p + Vector3.new(math.cos(a) * 3, 0, math.sin(a) * 3)) * CFrame.Angles(0, -a + rad(90), 0), Color = Color3.fromRGB(255, 140, 40) }, 2)
		tween(crack, 1.8, { Transparency = 1 })
	end
	debris(p, math.floor(10 * S), Color3.fromRGB(130, 120, 110), 1.1, 30)
	smoke(p, 6, Color3.fromRGB(140, 130, 120), 1)
	pillar(p, 3, 12, Color3.fromRGB(255, 160, 60), 0.8)
	shake(p, 5 * S, 0.6)
end

FX.rewind = function(d, c, S)
	local clock = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 8, 8), CFrame = CFrame.new(d.from) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(255, 230, 160), Transparency = 0.3 }, 1)
	tween(clock, 0.9, { CFrame = clock.CFrame * CFrame.Angles(rad(-720), 0, 0), Transparency = 1 })
	if d.to then
		beam(d.from, d.to, Color3.fromRGB(120, 200, 255), 1.2, 0.5)
		for i = 0, 4 do
			local ghost = part({ Size = Vector3.new(2, 5, 1), CFrame = CFrame.new(d.from:Lerp(d.to, i / 4)), Color = Color3.fromRGB(140, 210, 255), Transparency = 0.5 }, 0.8)
			tween(ghost, 0.7, { Transparency = 1 })
		end
		sparkles(d.to, Color3.fromRGB(160, 220, 255), 0.8)
	end
end

FX.black_hole = function(d, c, S)
	local p = (d.point or d.from) + Vector3.new(0, 3, 0)
	local dur = d.dur or 3
	local r = 16 * S
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(p), Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic }, dur + 0.5)
	tween(core, 0.4, { Size = Vector3.one * 5 * S }, Enum.EasingStyle.Back)
	local disk = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, r * 1.2, r * 1.2), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, rad(80)), Color = Color3.fromRGB(150, 60, 255), Transparency = 0.4 }, dur + 0.5)
	local disk2 = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, r * 0.8, r * 0.8), CFrame = CFrame.new(p) * CFrame.Angles(rad(20), 0, rad(100)), Color = Color3.fromRGB(255, 120, 255), Transparency = 0.4 }, dur + 0.5)
	tween(disk, dur, { CFrame = disk.CFrame * CFrame.Angles(rad(1440), 0, 0) }, Enum.EasingStyle.Linear)
	tween(disk2, dur, { CFrame = disk2.CFrame * CFrame.Angles(rad(-1440), 0, 0) }, Enum.EasingStyle.Linear)
	light(p, Color3.fromRGB(160, 60, 255), r * 3, 5, dur)
	for k = 1, math.floor(dur * 10) do
		task.delay(k * 0.1, function()
			local a, e = rnd:NextNumber(0, 6.28), rnd:NextNumber(-0.5, 0.8)
			local from = p + Vector3.new(math.cos(a) * r, e * r * 0.5, math.sin(a) * r)
			projectile(from, p, Color3.fromRGB(200, 140, 255), 0.4, 0.5, 0, true)
		end)
	end
	task.delay(dur, function()
		tween(core, 0.3, { Size = Vector3.one * 0.1 })
		tween(disk, 0.3, { Transparency = 1 })
		tween(disk2, 0.3, { Transparency = 1 })
		impact(p, 8 * S, Color3.fromRGB(170, 80, 255), S, { shake = 6 })
	end)
	shake(p, 3 * S, dur)
end

FX.mirage = function(d, c, S)
	smoke(d.point or d.from, 5, Color3.fromRGB(255, 160, 230), 0.8)
	sparkles(d.point or d.from, Color3.fromRGB(255, 180, 240), 3)
	burst(d.point or d.from, Color3.fromRGB(255, 150, 230), 40, 20, 1, 0.7)
end

FX.mirage_boom = function(d, c, S)
	impact(d.point, 8 * S, Color3.fromRGB(255, 120, 220), S, { boom = true, shake = 4 })
end

FX.dragon_breath = function(d, c, S)
	local dur = d.dur or 2
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for k = 1, math.floor(dur * 12) do
		task.delay(k / 12, function()
			if not hrp or not hrp.Parent then
				return
			end
			local look = hrp.CFrame.LookVector
			local v = CFrame.Angles(0, rad(rnd:NextNumber(-28, 28)), 0):VectorToWorldSpace(look)
			local from = hrp.Position + look * 2 + Vector3.new(0, 1.5, 0)
			local ball = projectile(from, from + v * (d.range or 20) * S, Color3.fromRGB(255, rnd:NextInteger(80, 180), 20), 2.2 * S, 0.45, 0, false)
			tween(ball, 0.45, { Size = Vector3.one * 5 * S, Transparency = 1 })
			if k % 3 == 0 then
				fire(from + v * 10 * S, 6 * S, Color3.fromRGB(255, 90, 20), 0.4)
			end
		end)
	end
	light(d.from, Color3.fromRGB(255, 120, 30), 40, 6, dur)
	shake(d.from, 2 * S, dur)
end

FX.guardian_dome = function(d, c, S)
	local dur = d.dur or 5
	local dome = part({ Shape = Enum.PartType.Ball, Size = Vector3.one, Color = Color3.fromRGB(255, 230, 140), Material = Enum.Material.ForceField, Transparency = 0.1 }, dur + 0.3)
	tween(dome, 0.4, { Size = Vector3.one * 12 * 2 * math.min(S, 1.6) }, Enum.EasingStyle.Back)
	follow(dome, d.userId, dur)
	for k = 1, 4 do
		local a = rad(k * 90)
		pillar(d.from + Vector3.new(math.cos(a) * 8, -2.5, math.sin(a) * 8), 1, 30, Color3.fromRGB(255, 240, 170), 1.2)
	end
	sparkles(d.from, Color3.fromRGB(255, 240, 180), dur)
	light(d.from, Color3.fromRGB(255, 230, 150), 35, 4, dur)
end

FX.starfall = function(d, c, S)
	local p = d.point or d.from
	local start = p + Vector3.new(rnd:NextNumber(-15, 15), 70, rnd:NextNumber(-15, 15))
	projectile(start, p, Color3.fromRGB(220, 240, 255), 1.5 * S, d.delay or 0.4, 0, true)
	task.delay(d.delay or 0.4, function()
		impact(p, 5 * S, Color3.fromRGB(170, 210, 255), S, { shake = 2 })
		sparkles(p, Color3.fromRGB(200, 230, 255), 0.8)
	end)
end

FX.soul_chains = function(d, c, S)
	for _, uid in ipairs(d.targets or {}) do
		local ch = charOf(uid)
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if r then
			for k = 1, 3 do
				task.delay(k * 0.05, function()
					lightning(d.from + Vector3.new(0, 1, 0), r.Position, Color3.fromRGB(60, 255, 200), 0.35, 1.2)
				end)
			end
			local cage = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 5, 5), CFrame = r.CFrame * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(40, 220, 180), Material = Enum.Material.ForceField, Transparency = 0.2 }, 1.3)
			tween(cage, 1.2, { Transparency = 1 })
			fire(r.Position - Vector3.new(0, 2, 0), 4, Color3.fromRGB(40, 255, 160), 1.2)
		end
	end
	screenFlash(Color3.fromRGB(170, 255, 230), 0.12, 0.4)
end

FX.blink_barrage = function(d, c, S)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for k = 1, (d.count or 3) * 3 do
		task.delay(k * 0.05, function()
			if hrp and hrp.Parent then
				local pos = hrp.Position
				local ghost = part({ Size = Vector3.new(2, 5, 1), CFrame = hrp.CFrame, Color = Color3.fromRGB(120, 255, 255), Transparency = 0.4 }, 0.5)
				tween(ghost, 0.4, { Transparency = 1 })
				local a = rnd:NextNumber(0, 6.28)
				local off = Vector3.new(math.cos(a), rnd:NextNumber(-0.5, 0.5), math.sin(a)) * 4
				beam(pos - off, pos + off, Color3.fromRGB(150, 255, 255), 0.4, 0.2)
			end
		end)
	end
	burst(d.from, Color3.fromRGB(120, 255, 255), 40, 30, 0.8, 0.6)
end

FX.midas_shockwave = function(d, c, S)
	local p = d.from
	local r = 18 * S
	pillar(ground(p), 4, 40, Color3.fromRGB(255, 220, 80), 1)
	for k = 1, 3 do
		task.delay((k - 1) * 0.12, function()
			ring(ground(p), r * (0.6 + k * 0.25), Color3.fromRGB(255, 210, 60), 0.7, 0.4, 2.5)
		end)
	end
	debris(ground(p), math.floor(16 * S), Color3.fromRGB(255, 210, 60), 0.6, 40, Enum.Material.Metal)
	impact(p, 8 * S, Color3.fromRGB(255, 220, 80), S, { boom = true, shake = 10 })
	screenFlash(Color3.fromRGB(255, 230, 150), 0.3, 0.5)
end

-- ===================== ENTRY =====================
function AbilityFx.play(d)
	local fn = FX[d.ability]
	if not fn then
		return false
	end
	local rank = Rarities.rank(d.rarity or "Common")
	local S = 1 + 0.18 * math.max(0, rank - 1) -- size/intensity scale by rarity
	local c = col(d.color)
	d.from = d.from or Vector3.zero
	d.dir = d.dir or Vector3.new(0, 0, -1)
	local ok, err = pcall(fn, d, c, S)
	if not ok then
		warn("[AbilityFx] " .. tostring(d.ability) .. ": " .. tostring(err))
	end
	-- extra glory for the rarest skills
	if rank >= 5 and d.ability ~= "fire_rain" and d.ability ~= "starfall" and d.ability ~= "thorn_snap" then
		pcall(function()
			pillar(ground(d.point or d.from), 2 * S, 25 * S, Color3.fromRGB(255, 255, 255):Lerp(c, 0.5), 0.9)
			sparkles(d.from, c, 1.2)
			if rank >= 6 then
				screenFlash(c, 0.12, 0.35)
			end
		end)
	end
	return true
end

return AbilityFx
