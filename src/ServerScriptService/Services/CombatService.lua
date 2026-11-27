-- CombatService: weapon inventory, free starter weapons, special dishes -> weapons,
-- server-validated attacks and UNIQUE weapon abilities, statuses (stun/root/slow/shield/
-- burn) with anti-chain-CC rules, PvP rules (arena + thief/owner fights), spawn
-- protection, arena stats and leaderboard. The client only sends "I attack/aim here".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local MapLayout = require(Shared.MapLayout)
local Data = Shared.Data
local Weapons = require(Data.Weapons)
local Creatures = require(Data.Creatures)
local Rarities = require(Data.Rarities)

local CombatService = {}
local S

local state = {} -- [player] = runtime combat state
local session = {} -- [userId] = { name, kills, deaths } (arena board for this server)
local rng = Random.new()

local MAX_CC = 1.5
local CC_IMMUNITY = 2.5
local SPAWN_PROTECTION = 6
local LAG_RANGE = 3 -- extra studs allowed for latency

function CombatService.Init(registry)
	S = registry
end

-- ===================== HELPERS =====================
local function profileOf(player)
	return S.DataService.get(player)
end

local function st(player)
	local s = state[player]
	if not s then
		s = { cd = {}, speed = {}, history = {}, traps = {} }
		state[player] = s
	end
	return s
end

local function charParts(player)
	local char = player and player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return char, root, hum
end

local function alive(player)
	local _, root, hum = charParts(player)
	return root ~= nil and hum ~= nil and hum.Health > 0
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

function CombatService.inArena(player)
	local _, root = charParts(player)
	if not root then
		return false
	end
	local p = root.Position
	return MapLayout.inArena(p.X, p.Y, p.Z)
end

local function equippedDef(player)
	local p = profileOf(player)
	if not p or p.data.equipped == "" then
		return nil
	end
	local w = p.data.weapons[p.data.equipped]
	return w and Weapons.ById[w.id], w
end

-- can attacker damage victim right now?
function CombatService.canDamage(attacker, victim)
	if attacker == victim or not alive(attacker) or not alive(victim) then
		return false
	end
	local vchar = victim.Character
	if vchar:FindFirstChildOfClass("ForceField") then
		return false
	end
	if CombatService.inArena(attacker) and CombatService.inArena(victim) then
		return true
	end
	return S.LabService.canFightThief(attacker, victim)
end

-- enemies of attacker (players it may damage) within radius of a point
local function enemiesNear(attacker, pos, radius)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= attacker and CombatService.canDamage(attacker, p) then
			local _, root = charParts(p)
			local d = (root.Position - pos).Magnitude
			if d <= radius then
				table.insert(list, { player = p, root = root, dist = d })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	return list
end

local function inCone(origin, dir, pos, range, halfAngleDeg)
	local to = pos - origin
	local d = to.Magnitude
	if d > range then
		return false
	end
	if d < 2.5 then
		return true
	end
	return flat(to):Dot(flat(dir)) >= math.cos(math.rad(halfAngleDeg))
end

local function distToSegment(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (a + ab * t - p).Magnitude, t
end

-- used by the test suite (never reachable from a client)
function CombatService.resetCooldowns(player)
	st(player).cd = {}
end

-- ===================== STATUS & SPEED =====================
function CombatService.refreshSpeed(player)
	local _, _, hum = charParts(player)
	if not hum then
		return
	end
	local s = st(player)
	local now = os.clock()
	local base = player:GetAttribute("BaseSpeed") or 18
	local carry = S.LabService and S.LabService.carrySpeed(player)
	if carry then
		base = math.min(base, carry)
	end
	local mult = 1
	for key, m in pairs(s.speed) do
		if m.untilT > now then
			mult *= m.mult
		else
			s.speed[key] = nil
		end
	end
	mult = math.clamp(mult, 0.4, 1.6)
	local held = (s.stunUntil and s.stunUntil > now) or (s.rootUntil and s.rootUntil > now)
	hum.WalkSpeed = held and 0 or base * mult
	hum.JumpPower = held and 0 or 50
	player:SetAttribute("Stunned", (s.stunUntil and s.stunUntil > now) or nil)
end

local function addSpeed(player, key, mult, dur)
	st(player).speed[key] = { mult = mult, untilT = os.clock() + dur }
	CombatService.refreshSpeed(player)
end

-- crowd control with a hard cap and immunity afterwards (no infinite stun-locks)
local function cc(player, kind, dur)
	local s = st(player)
	local now = os.clock()
	if s.ccImmune and now < s.ccImmune then
		return false
	end
	dur = math.min(dur, MAX_CC)
	if kind == "stun" then
		s.stunUntil = now + dur
	else
		s.rootUntil = now + dur
	end
	s.ccImmune = now + dur + CC_IMMUNITY
	CombatService.refreshSpeed(player)
	Net.fxAll("cc", { userId = player.UserId, kind = kind, dur = dur })
	task.delay(dur + 0.05, function()
		if player.Parent then
			CombatService.refreshSpeed(player)
		end
	end)
	return true
end

local function knockback(player, from, power, up)
	local _, root = charParts(player)
	if not root then
		return
	end
	local dir = flat(root.Position - from)
	local vel = dir * power + Vector3.new(0, up or 18, 0)
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = vel
	bv.Parent = root
	Debris:AddItem(bv, 0.18)
	Net.fx(player, "knock", { vel = vel })
end

local function launchSelf(player, vel)
	local _, root = charParts(player)
	if not root then
		return
	end
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = vel
	bv.Parent = root
	Debris:AddItem(bv, 0.25)
	Net.fx(player, "knock", { vel = vel })
end

-- ===================== DAMAGE =====================
local function onKill(killer, victim)
	local kp, vp = profileOf(killer), profileOf(victim)
	local arena = CombatService.inArena(victim)
	if kp then
		kp.data.pvp.kills += 1
		if arena then
			kp.data.pvp.arenaKills += 1
		end
		local ks = st(killer)
		ks.streak = (ks.streak or 0) + 1
		if ks.streak > kp.data.pvp.bestStreak then
			kp.data.pvp.bestStreak = ks.streak
		end
		if ks.streak >= 3 then
			Net.fxAll("announce", { text = "⚔️ " .. killer.DisplayName .. ": серия из " .. ks.streak .. " побед!" })
		end
		S.Economy.earn(killer, 50, "Победа на арене", true)
	end
	if vp then
		vp.data.pvp.deaths += 1
		if arena then
			vp.data.pvp.arenaDeaths += 1
		end
	end
	st(victim).streak = 0
	local ks = session[killer.UserId] or { name = killer.DisplayName, kills = 0, deaths = 0 }
	ks.kills += 1
	session[killer.UserId] = ks
	local vs = session[victim.UserId] or { name = victim.DisplayName, kills = 0, deaths = 0 }
	vs.deaths += 1
	session[victim.UserId] = vs
	Net.fx(killer, "pvp", { kind = "kill", name = victim.DisplayName })
	Net.fx(victim, "pvp", { kind = "death", name = killer.DisplayName })
	CombatService.pushCombat(killer)
	CombatService.pushCombat(victim)
end

-- the only function that hurts players. Returns damage dealt.
function CombatService.damage(attacker, victim, amount, opts)
	opts = opts or {}
	if not CombatService.canDamage(attacker, victim) then
		return 0
	end
	local _, root, hum = charParts(victim)
	local vs = st(victim)
	local now = os.clock()
	if vs.reduceUntil and vs.reduceUntil > now then
		amount *= vs.reduceMult
	end
	if vs.reflectUntil and vs.reflectUntil > now and not opts.reflected then
		amount *= 0.5
		task.defer(CombatService.damage, victim, attacker, amount, { reflected = true })
	end
	if vs.shield and vs.shield > 0 and vs.shieldUntil > now then
		local absorbed = math.min(vs.shield, amount)
		vs.shield -= absorbed
		amount -= absorbed
	end
	amount = math.max(0, math.floor(amount + 0.5))
	-- attacking removes the attacker's own spawn protection
	local ff = attacker.Character and attacker.Character:FindFirstChildOfClass("ForceField")
	if ff then
		ff:Destroy()
	end
	local before = hum.Health
	if amount > 0 then
		hum:TakeDamage(amount)
	end
	vs.lastDamager = attacker
	vs.lastDamageT = now
	Net.fxAll("hit", { pos = root.Position, amount = amount, by = attacker.UserId, victim = victim.UserId, kind = opts.kind })
	-- the owner team hits a thief -> the creature drops and returns home
	S.LabService.onHit(attacker, victim)
	if before > 0 and hum.Health <= 0 and not vs.killCredited then
		vs.killCredited = true
		onKill(attacker, victim)
	end
	return amount
end

local function burn(attacker, victim, dps, dur)
	local vs = st(victim)
	vs.burn = { by = attacker, dps = dps, untilT = os.clock() + dur, acc = 0 }
	Net.fxAll("status", { userId = victim.UserId, kind = "burn", dur = dur })
end

-- ===================== ABILITIES =====================
-- ctx = { player, def, root, dir (flat), point (clamped aim point) }
local A = {}
CombatService.Abilities = A

local function hitAll(ctx, list, amount, extra)
	local n = 0
	for _, e in ipairs(list) do
		CombatService.damage(ctx.player, e.player, amount, { kind = ctx.def.ability.id })
		if extra then
			extra(e)
		end
		n += 1
	end
	return n
end

local function fx(ctx, name, data)
	data = data or {}
	data.ability = name
	data.from = ctx.root.Position
	data.dir = ctx.dir
	data.point = ctx.point
	data.color = ctx.def.color
	data.userId = ctx.player.UserId
	Net.fxAll("ability", data)
end

A.home_run = function(ctx)
	fx(ctx, "home_run")
	for _, e in ipairs(enemiesNear(ctx.player, ctx.root.Position, 8 + LAG_RANGE)) do
		if inCone(ctx.root.Position, ctx.dir, e.root.Position, 9, 60) then
			CombatService.damage(ctx.player, e.player, 8, { kind = "home_run" })
			knockback(e.player, ctx.root.Position, 95, 40)
			return
		end
	end
end

A.guard = function(ctx)
	local s = st(ctx.player)
	s.reduceUntil, s.reduceMult = os.clock() + 2, 0.6
	fx(ctx, "guard", { dur = 2 })
end

A.spin = function(ctx)
	fx(ctx, "spin", { radius = 9 })
	hitAll(ctx, enemiesNear(ctx.player, ctx.root.Position, 9), 14)
end

local function delayedBlast(ctx, name, point, radius, amount, delay, extra)
	fx(ctx, name, { radius = radius, delay = delay, point = point })
	task.delay(delay, function()
		if not ctx.player.Parent then
			return
		end
		for _, e in ipairs(enemiesNear(ctx.player, point, radius)) do
			CombatService.damage(ctx.player, e.player, amount, { kind = name })
			if extra then
				extra(e, point)
			end
		end
	end)
end

A.coconut_bomb = function(ctx)
	delayedBlast(ctx, "coconut_bomb", ctx.point, 8, 15, 0.8)
end

A.charge = function(ctx)
	local start = ctx.root.Position
	local finish = start + ctx.dir * 22
	local target
	for _, e in ipairs(enemiesNear(ctx.player, start, 26)) do
		local d, t = distToSegment(e.root.Position, start, finish)
		if d < 4.5 and t > 0 then
			target = e
			finish = start + ctx.dir * math.max(0, (e.root.Position - start).Magnitude - 3)
			break
		end
	end
	ctx.player.Character:PivotTo(CFrame.lookAt(finish, finish + ctx.dir))
	fx(ctx, "charge", { to = finish })
	if target then
		CombatService.damage(ctx.player, target.player, 14, { kind = "charge" })
		knockback(target.player, start, 60, 25)
	end
end

A.bubble_trap = function(ctx)
	for _, e in ipairs(enemiesNear(ctx.player, ctx.root.Position, 30)) do
		if inCone(ctx.root.Position, ctx.dir, e.root.Position, 30, 45) then
			fx(ctx, "bubble_trap", { to = e.root.Position, target = e.player.UserId })
			CombatService.damage(ctx.player, e.player, 6, { kind = "bubble_trap" })
			cc(e.player, "root", 1.2)
			return
		end
	end
	fx(ctx, "bubble_trap", { to = ctx.root.Position + ctx.dir * 30 })
end

A.flame_wave = function(ctx)
	fx(ctx, "flame_wave", { range = 16 })
	for _, e in ipairs(enemiesNear(ctx.player, ctx.root.Position, 16)) do
		if inCone(ctx.root.Position, ctx.dir, e.root.Position, 16, 50) then
			CombatService.damage(ctx.player, e.player, 10, { kind = "flame_wave" })
			burn(ctx.player, e.player, 4, 3)
		end
	end
end

A.ice_field = function(ctx)
	local center = ctx.root.Position
	fx(ctx, "ice_field", { radius = 10, dur = 4, point = center })
	for k = 1, 8 do
		task.delay(k * 0.5, function()
			if not ctx.player.Parent then
				return
			end
			for _, e in ipairs(enemiesNear(ctx.player, center, 10)) do
				addSpeed(e.player, "ice", 0.5, 0.7)
				CombatService.damage(ctx.player, e.player, 2, { kind = "ice_field" })
			end
		end)
	end
end

A.hook_pull = function(ctx)
	local start = ctx.root.Position
	local finish = start + ctx.dir * 35
	for _, e in ipairs(enemiesNear(ctx.player, start, 38)) do
		local d = distToSegment(e.root.Position, start, finish)
		if d < 4 then
			local dest = start + ctx.dir * 4
			e.player.Character:PivotTo(CFrame.lookAt(dest, start))
			fx(ctx, "hook_pull", { to = e.root.Position, target = e.player.UserId })
			CombatService.damage(ctx.player, e.player, 10, { kind = "hook_pull" })
			return
		end
	end
	fx(ctx, "hook_pull", { to = finish })
end

A.static_shock = function(ctx)
	local list = enemiesNear(ctx.player, ctx.root.Position, 28)
	local e = list[1]
	if e then
		fx(ctx, "static_shock", { to = e.root.Position, target = e.player.UserId })
		CombatService.damage(ctx.player, e.player, 16, { kind = "static_shock" })
		cc(e.player, "stun", 0.6)
	else
		fx(ctx, "static_shock", { to = ctx.root.Position + ctx.dir * 20 })
	end
end

A.tidal_wave = function(ctx)
	local start = ctx.root.Position
	local finish = start + ctx.dir * 30
	fx(ctx, "tidal_wave", { to = finish, width = 12 })
	for _, e in ipairs(enemiesNear(ctx.player, start, 33)) do
		local d, t = distToSegment(e.root.Position, start, finish)
		if d <= 6 and t > 0 then
			CombatService.damage(ctx.player, e.player, 14, { kind = "tidal_wave" })
			knockback(e.player, start, 70, 20)
		end
	end
end

A.reflect = function(ctx)
	local s = st(ctx.player)
	s.reflectUntil = os.clock() + 3
	fx(ctx, "reflect", { dur = 3 })
end

A.bee_swarm = function(ctx)
	local list = enemiesNear(ctx.player, ctx.root.Position, 40)
	for i = 1, 3 do
		local e = list[i] or list[1]
		if not e then
			fx(ctx, "bee_swarm", { to = ctx.root.Position + ctx.dir * 20 })
			return
		end
		local travel = e.dist / 55
		fx(ctx, "bee_swarm", { target = e.player.UserId, to = e.root.Position, travel = travel, index = i })
		task.delay(travel + i * 0.1, function()
			if ctx.player.Parent then
				CombatService.damage(ctx.player, e.player, 9, { kind = "bee_swarm" })
			end
		end)
	end
end

A.updraft = function(ctx)
	launchSelf(ctx.player, ctx.dir * 45 + Vector3.new(0, 70, 0))
	addSpeed(ctx.player, "updraft", 1.35, 4)
	fx(ctx, "updraft", { radius = 8 })
	for _, e in ipairs(enemiesNear(ctx.player, ctx.root.Position, 8)) do
		CombatService.damage(ctx.player, e.player, 8, { kind = "updraft" })
		knockback(e.player, ctx.root.Position, 50, 30)
	end
end

A.meteor = function(ctx)
	delayedBlast(ctx, "meteor", ctx.point, 11, 26, 1.2, function(e, point)
		knockback(e.player, point, 55, 35)
	end)
end

A.shadow_step = function(ctx)
	local e = enemiesNear(ctx.player, ctx.root.Position, 35)[1]
	if not e then
		fx(ctx, "shadow_step", {})
		return
	end
	local behind = e.root.CFrame * CFrame.new(0, 0, 3.5)
	fx(ctx, "shadow_step", { to = behind.Position })
	ctx.player.Character:PivotTo(CFrame.lookAt(behind.Position, e.root.Position))
	CombatService.damage(ctx.player, e.player, 20, { kind = "shadow_step" })
end

A.thorn_traps = function(ctx)
	local s = st(ctx.player)
	for _, t in ipairs(s.traps) do
		if t.part then
			t.part:Destroy()
		end
	end
	s.traps = {}
	for k = -1, 1 do
		local dir = CFrame.Angles(0, math.rad(k * 25), 0):VectorToWorldSpace(ctx.dir)
		local pos = ctx.root.Position + dir * 9 - Vector3.new(0, 2.6, 0)
		local part = Instance.new("Part")
		part.Name = "ThornTrap"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Size = Vector3.new(3.5, 0.4, 3.5)
		part.Color = Color3.fromRGB(70, 150, 50)
		part.Material = Enum.Material.Grass
		part.CFrame = CFrame.new(pos)
		part.Parent = workspace
		Debris:AddItem(part, 12)
		table.insert(s.traps, { part = part, untilT = os.clock() + 12 })
	end
	fx(ctx, "thorn_traps", {})
end

A.plasma_beam = function(ctx)
	local start = ctx.root.Position
	local finish = start + ctx.dir * 60
	fx(ctx, "plasma_beam", { to = finish })
	for _, e in ipairs(enemiesNear(ctx.player, start, 62)) do
		local d, t = distToSegment(e.root.Position, start, finish)
		if d <= 3.5 and t > 0 then
			CombatService.damage(ctx.player, e.player, 22, { kind = "plasma_beam" })
		end
	end
end

A.storm_aura = function(ctx)
	fx(ctx, "storm_aura", { radius = 13, dur = 5 })
	for k = 1, 10 do
		task.delay(k * 0.5, function()
			local _, root = charParts(ctx.player)
			if root and alive(ctx.player) then
				for _, e in ipairs(enemiesNear(ctx.player, root.Position, 13)) do
					CombatService.damage(ctx.player, e.player, 3, { kind = "storm_aura" })
				end
			end
		end)
	end
end

A.fire_rain = function(ctx)
	for k = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, 10)
		local p = ctx.point + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		task.delay((k - 1) * 0.25, function()
			if ctx.player.Parent then
				delayedBlast(ctx, "fire_rain", p, 5, 9, 0.35, function(e)
					burn(ctx.player, e.player, 3, 2)
				end)
			end
		end)
	end
end

A.summon_golem = function(ctx)
	local s = st(ctx.player)
	if s.golem then
		s.golem:Destroy()
	end
	local golem = Instance.new("Model")
	golem.Name = "Golem"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 5, 3)
	body.Color = Color3.fromRGB(130, 120, 110)
	body.Material = Enum.Material.Slate
	body.Anchored = true
	body.CanCollide = false
	body.Parent = golem
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2.4, 2, 2.4)
	head.Color = Color3.fromRGB(150, 140, 125)
	head.Material = Enum.Material.Slate
	head.Anchored = true
	head.CanCollide = false
	head.Parent = golem
	for _, x in ipairs({ -0.5, 0.5 }) do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.4, 0.4, 0.2)
		eye.Color = Color3.fromRGB(255, 160, 40)
		eye.Material = Enum.Material.Neon
		eye.Anchored = true
		eye.CanCollide = false
		eye:SetAttribute("Offset", x)
		eye.Parent = golem
	end
	golem.PrimaryPart = body
	local pos = ctx.root.Position + ctx.dir * 4
	local function place(p, look)
		local cf = CFrame.lookAt(p, p + flat(look))
		body.CFrame = cf
		head.CFrame = cf * CFrame.new(0, 3.5, 0)
		for _, eye in ipairs(golem:GetChildren()) do
			if eye.Name == "Eye" then
				eye.CFrame = cf * CFrame.new(eye:GetAttribute("Offset"), 3.7, -1.25)
			end
		end
	end
	place(pos, ctx.dir)
	golem.Parent = workspace
	s.golem = golem
	fx(ctx, "summon_golem", { to = pos })
	task.spawn(function()
		local t0 = os.clock()
		local lastHit = 0
		while golem.Parent and os.clock() - t0 < 10 and ctx.player.Parent do
			task.wait(0.2)
			local target = enemiesNear(ctx.player, body.Position, 40)[1]
			if target then
				local to = target.root.Position - body.Position
				local step = math.min(to.Magnitude - 3, 3.2)
				if step > 0 then
					pos = body.Position + flat(to) * step
					place(Vector3.new(pos.X, target.root.Position.Y, pos.Z), to)
				end
				if to.Magnitude < 6 and os.clock() - lastHit > 1 then
					lastHit = os.clock()
					CombatService.damage(ctx.player, target.player, 10, { kind = "golem" })
				end
			end
		end
		golem:Destroy()
		if s.golem == golem then
			s.golem = nil
		end
	end)
end

A.rewind = function(ctx)
	local s = st(ctx.player)
	local now = os.clock()
	local snap
	for _, h in ipairs(s.history) do
		if now - h.t >= 2.8 then
			snap = h
		end
	end
	snap = snap or s.history[1]
	if not snap then
		return
	end
	local _, _, hum = charParts(ctx.player)
	fx(ctx, "rewind", { to = snap.cf.Position })
	ctx.player.Character:PivotTo(snap.cf)
	if hum and snap.hp > hum.Health then
		hum.Health = math.min(hum.MaxHealth, snap.hp)
	end
end

A.black_hole = function(ctx)
	local center = ctx.point
	fx(ctx, "black_hole", { radius = 16, dur = 3, point = center })
	for k = 1, 12 do
		task.delay(k * 0.25, function()
			if not ctx.player.Parent then
				return
			end
			for _, e in ipairs(enemiesNear(ctx.player, center, 16)) do
				local to = center - e.root.Position
				if to.Magnitude > 2 then
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(4e4, 0, 4e4)
					bv.Velocity = flat(to) * 22
					bv.Parent = e.root
					Debris:AddItem(bv, 0.22)
				end
				CombatService.damage(ctx.player, e.player, 2.5, { kind = "black_hole" })
			end
		end)
	end
end

local function setInvisible(player, on)
	local char = player.Character
	if not char then
		return
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			if on then
				d:SetAttribute("VisT", d.Transparency)
				d.Transparency = 0.92
			elseif d:GetAttribute("VisT") ~= nil then
				d.Transparency = d:GetAttribute("VisT")
				d:SetAttribute("VisT", nil)
			end
		elseif d:IsA("Decal") then
			if on then
				d:SetAttribute("VisT", d.Transparency)
				d.Transparency = 1
			elseif d:GetAttribute("VisT") ~= nil then
				d.Transparency = d:GetAttribute("VisT")
				d:SetAttribute("VisT", nil)
			end
		end
	end
	player:SetAttribute("Invisible", on or nil)
end

A.mirage = function(ctx)
	local char = ctx.player.Character
	local decoyPos = ctx.root.Position
	char.Archivable = true
	local ok, decoy = pcall(function()
		return char:Clone()
	end)
	if ok and decoy then
		for _, d in ipairs(decoy:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ForceField") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		local h = decoy:FindFirstChildOfClass("Humanoid")
		if h then
			h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		decoy.Name = "Mirage"
		decoy.Parent = workspace
		Debris:AddItem(decoy, 3.2)
	end
	setInvisible(ctx.player, true)
	addSpeed(ctx.player, "mirage", 1.3, 3)
	fx(ctx, "mirage", { point = decoyPos, dur = 3 })
	task.delay(3, function()
		if ctx.player.Parent then
			setInvisible(ctx.player, false)
			for _, e in ipairs(enemiesNear(ctx.player, decoyPos, 8)) do
				CombatService.damage(ctx.player, e.player, 18, { kind = "mirage" })
			end
			Net.fxAll("ability", { ability = "mirage_boom", point = decoyPos, color = ctx.def.color, userId = ctx.player.UserId })
		end
	end)
end

A.dragon_breath = function(ctx)
	fx(ctx, "dragon_breath", { dur = 2, range = 20 })
	for k = 1, 5 do
		task.delay((k - 1) * 0.4, function()
			local _, root = charParts(ctx.player)
			if not root or not alive(ctx.player) then
				return
			end
			for _, e in ipairs(enemiesNear(ctx.player, root.Position, 20)) do
				if inCone(root.Position, root.CFrame.LookVector, e.root.Position, 20, 30) then
					CombatService.damage(ctx.player, e.player, 6, { kind = "dragon_breath" })
					burn(ctx.player, e.player, 2, 2)
				end
			end
		end)
	end
end

A.guardian_dome = function(ctx)
	local allies = { ctx.player }
	local island = S.RestaurantService.islandOf(ctx.player)
	if island then
		for _, m in ipairs(S.RestaurantService.membersOf(island)) do
			local _, r = charParts(m)
			if m ~= ctx.player and r and (r.Position - ctx.root.Position).Magnitude <= 12 then
				table.insert(allies, m)
			end
		end
	end
	fx(ctx, "guardian_dome", { radius = 12, dur = 5 })
	for _, a in ipairs(allies) do
		local s = st(a)
		s.shield, s.shieldUntil = 45, os.clock() + 5
		for k = 1, 5 do
			task.delay(k, function()
				local _, _, hum = charParts(a)
				if hum and hum.Health > 0 then
					hum.Health = math.min(hum.MaxHealth, hum.Health + 3)
				end
			end)
		end
	end
end

A.starfall = function(ctx)
	for k = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, 14)
		local p = ctx.point + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		task.delay((k - 1) * 0.2, function()
			if ctx.player.Parent then
				delayedBlast(ctx, "starfall", p, 5, 8, 0.4)
			end
		end)
	end
end

A.soul_chains = function(ctx)
	local list = enemiesNear(ctx.player, ctx.root.Position, 28)
	local targets = {}
	for i = 1, math.min(3, #list) do
		table.insert(targets, list[i].player.UserId)
	end
	fx(ctx, "soul_chains", { targets = targets })
	for i = 1, math.min(3, #list) do
		local e = list[i]
		CombatService.damage(ctx.player, e.player, 14, { kind = "soul_chains" })
		cc(e.player, "root", 1.2)
	end
end

A.blink_barrage = function(ctx)
	local start = ctx.root.CFrame
	local list = enemiesNear(ctx.player, ctx.root.Position, 30)
	local n = math.min(3, #list)
	fx(ctx, "blink_barrage", { count = n })
	task.spawn(function()
		for i = 1, n do
			local e = list[i]
			if ctx.player.Parent and alive(ctx.player) and alive(e.player) then
				local _, eroot = charParts(e.player)
				local pos = eroot.CFrame * CFrame.new(0, 0, 3)
				ctx.player.Character:PivotTo(CFrame.lookAt(pos.Position, eroot.Position))
				CombatService.damage(ctx.player, e.player, 15, { kind = "blink_barrage" })
				task.wait(0.15)
			end
		end
		if ctx.player.Parent and alive(ctx.player) then
			ctx.player.Character:PivotTo(start)
		end
	end)
end

A.midas_shockwave = function(ctx)
	fx(ctx, "midas_shockwave", { radius = 18 })
	for _, e in ipairs(enemiesNear(ctx.player, ctx.root.Position, 18)) do
		CombatService.damage(ctx.player, e.player, 20, { kind = "midas_shockwave" })
		knockback(e.player, ctx.root.Position, 65, 30)
		cc(e.player, "stun", 0.8)
	end
end

-- ===================== WEAPON MODEL =====================
local function unequipModel(player)
	local char = player.Character
	local old = char and char:FindFirstChild("EquippedWeapon")
	if old then
		old:Destroy()
	end
end

local function equipModel(player, def)
	unequipModel(player)
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local src = assets and assets:FindFirstChild("Weapons") and assets.Weapons:FindFirstChild(def.id)
	if not hand or not src then
		return
	end
	local m = src:Clone()
	m.Name = "EquippedWeapon"
	local handle = m:FindFirstChild("Handle") or m.PrimaryPart
	if not handle then
		m:Destroy()
		return
	end
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			p.CanQuery = false
			if p ~= handle then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = handle, p
				w.Parent = p
			end
		end
	end
	m:PivotTo(hand.CFrame * CFrame.new(0, -0.6, -0.2) * CFrame.Angles(math.rad(-90), 0, 0))
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = hand, handle
	w.Parent = handle
	m:SetAttribute("WeaponId", def.id)
	m.Parent = char
end

-- ===================== STATE PUSH =====================
function CombatService.buildState(player)
	local p = profileOf(player)
	if not p then
		return nil
	end
	local list = {}
	for uid, w in pairs(p.data.weapons) do
		table.insert(list, { uid = uid, id = w.id })
	end
	local s = st(player)
	local now = os.clock()
	local def = equippedDef(player)
	return {
		weapons = list,
		equipped = p.data.equipped,
		dishes = p.data.dishes,
		stats = p.data.pvp,
		attackReady = def and math.max(0, (s.cd.attack or 0) - now) or 0,
		abilityReady = def and math.max(0, (s.cd.ability or 0) - now) or 0,
		max = Weapons.MaxInventory,
	}
end

function CombatService.pushCombat(player)
	local stt = CombatService.buildState(player)
	if stt then
		Net.push(player, "combat", stt)
	end
end

local function grantWeapon(player, id)
	local p = profileOf(player)
	local d = p.data
	d.weaponSeq += 1
	local uid = tostring(d.weaponSeq)
	d.weapons[uid] = { id = id, got = os.time() }
	return uid
end

local function weaponCount(p)
	local n = 0
	for _ in pairs(p.data.weapons) do
		n += 1
	end
	return n
end

local function equip(player, uid)
	local p = profileOf(player)
	local w = p and p.data.weapons[uid]
	if not w then
		return false
	end
	p.data.equipped = uid
	equipModel(player, Weapons.ById[w.id])
	return true
end

-- ===================== REQUESTS =====================
local function ok(extra)
	local t = extra or {}
	t.ok = true
	return t
end
local function fail(err)
	return { ok = false, err = err }
end

local function aimOf(root, payload)
	local dir = typeof(payload.dir) == "Vector3" and payload.dir or root.CFrame.LookVector
	dir = flat(dir)
	-- the server keeps the character's facing as the source of truth if the aim is wild
	if dir:Dot(flat(root.CFrame.LookVector)) < -0.2 then
		dir = flat(root.CFrame.LookVector)
	end
	return dir
end

local function registerRemotes()
	Net.onRequest("CombatState", function(player)
		return ok({ state = CombatService.buildState(player) })
	end)

	Net.setRate("EatDish", 2, 3)
	Net.onRequest("EatDish", function(player, payload)
		local dish = type(payload) == "table" and Creatures.DishById[payload.dish]
		if not dish then
			return fail("Нет такого блюда")
		end
		local p = profileOf(player)
		if not p then
			return fail("Данные ещё загружаются")
		end
		local s = st(player)
		if s.eating and os.clock() - s.eating < 1.2 then
			return fail("Вы ещё едите")
		end
		if (p.data.dishes[dish.id] or 0) <= 0 then
			return fail("Этого блюда нет в инвентаре")
		end
		if weaponCount(p) >= Weapons.MaxInventory then
			return fail("Инвентарь оружия заполнен (" .. Weapons.MaxInventory .. "). Разберите лишнее")
		end
		-- atomic: remove ONE dish, give EXACTLY ONE weapon of the SAME rarity (no yields here)
		s.eating = os.clock()
		p.data.dishes[dish.id] -= 1
		if p.data.dishes[dish.id] <= 0 then
			p.data.dishes[dish.id] = nil
		end
		local pool = Weapons.ByRarity[dish.rarity]
		local def = pool[rng:NextInteger(1, #pool)]
		local uid = grantWeapon(player, def.id)
		p.data.pvp.dishesEaten += 1
		local _, root = charParts(player)
		if root then
			Net.fxAll("eatDish", { userId = player.UserId, dish = dish.id, pos = root.Position })
		end
		if Rarities.rank(def.rarity) >= 5 then
			Net.fxAll("announce", { text = "🗡️ " .. player.DisplayName .. " получил " .. Rarities.Info[def.rarity].name .. " оружие «" .. def.name .. "»!" })
		end
		CombatService.pushCombat(player)
		S.LabService.push(player)
		return ok({ uid = uid, id = def.id, rarity = def.rarity, dish = dish.id })
	end)

	Net.onRequest("EquipWeapon", function(player, payload)
		local uid = type(payload) == "table" and tostring(payload.uid or "")
		if uid == "" then
			local p = profileOf(player)
			if p then
				p.data.equipped = ""
			end
			unequipModel(player)
			CombatService.pushCombat(player)
			return ok()
		end
		if S.LabService.isCarrying(player) then
			return fail("Руки заняты добычей")
		end
		if not equip(player, uid) then
			return fail("Оружие не найдено")
		end
		CombatService.pushCombat(player)
		return ok()
	end)

	Net.onRequest("ScrapWeapon", function(player, payload)
		local uid = type(payload) == "table" and tostring(payload.uid or "")
		local p = profileOf(player)
		local w = p and p.data.weapons[uid]
		if not w then
			return fail("Оружие не найдено")
		end
		if p.data.equipped == uid then
			p.data.equipped = ""
			unequipModel(player)
		end
		local def = Weapons.ById[w.id]
		p.data.weapons[uid] = nil
		local refund = def.starter and 0 or 100 * Rarities.rank(def.rarity) ^ 2
		if refund > 0 then
			S.Economy.grant(player, refund, "Разбор оружия")
		end
		CombatService.pushCombat(player)
		return ok({ refund = refund })
	end)

	Net.setRate("Attack", 6, 8)
	Net.onAction("Attack", function(player, payload)
		payload = type(payload) == "table" and payload or {}
		local def = equippedDef(player)
		local _, root = charParts(player)
		if not def or not root or not alive(player) or S.LabService.isCarrying(player) then
			return
		end
		local s = st(player)
		local now = os.clock()
		if (s.stunUntil and now < s.stunUntil) or now < (s.cd.attack or 0) - 0.05 then
			return
		end
		s.cd.attack = now + def.cooldown
		local dir = aimOf(root, payload)
		local origin = root.Position
		Net.fxAll("swing", { userId = player.UserId, weapon = def.id, kind = def.kind, dir = dir, from = origin, range = def.range, projectile = def.projectile, color = def.color })
		if def.kind == "melee" then
			local hits = enemiesNear(player, origin, def.range + LAG_RANGE)
			local maxTargets = def.style == "mass" and 3 or (def.style == "heavy" and 2 or 1)
			local n = 0
			for _, e in ipairs(hits) do
				if inCone(origin, dir, e.root.Position, def.range + LAG_RANGE, 65) then
					CombatService.damage(player, e.player, def.damage, { kind = "melee" })
					n += 1
					if n >= maxTargets then
						break
					end
				end
			end
		else
			local finish = origin + dir * def.range
			local best
			for _, e in ipairs(enemiesNear(player, origin, def.range + LAG_RANGE)) do
				local d, t = distToSegment(e.root.Position, origin, finish)
				if d <= 3.5 and t > 0 and (not best or e.dist < best.dist) then
					best = e
				end
			end
			if best then
				local travel = best.dist / 120
				task.delay(travel, function()
					if player.Parent then
						CombatService.damage(player, best.player, def.damage, { kind = "ranged" })
					end
				end)
			end
		end
	end)

	Net.setRate("Ability", 2, 3)
	Net.onRequest("Ability", function(player, payload)
		payload = type(payload) == "table" and payload or {}
		local def = equippedDef(player)
		local _, root = charParts(player)
		if not def then
			return fail("Сначала возьмите оружие")
		end
		if not root or not alive(player) then
			return fail("Недоступно")
		end
		if S.LabService.isCarrying(player) then
			return fail("Руки заняты добычей")
		end
		local s = st(player)
		local now = os.clock()
		if s.stunUntil and now < s.stunUntil then
			return fail("Вы оглушены")
		end
		if now < (s.cd.ability or 0) then
			return fail("Способность перезаряжается", (s.cd.ability or 0) - now)
		end
		local impl = A[def.ability.id]
		if not impl then
			return fail("Способность недоступна")
		end
		s.cd.ability = now + def.ability.cooldown
		local dir = aimOf(root, payload)
		local point = typeof(payload.point) == "Vector3" and payload.point or (root.Position + dir * 25)
		local maxRange = 55
		if (point - root.Position).Magnitude > maxRange then
			point = root.Position + (point - root.Position).Unit * maxRange
		end
		local okRun, err = pcall(impl, { player = player, def = def, root = root, dir = dir, point = point })
		if not okRun then
			warn("[CombatService] ability " .. def.ability.id .. ": " .. tostring(err))
		end
		return ok({ cooldown = def.ability.cooldown })
	end)

	Net.onRequest("JoinArena", function(player, payload)
		if not alive(player) then
			return fail("Недоступно")
		end
		if S.LabService.isCarrying(player) then
			return fail("Руки заняты добычей")
		end
		local arena = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Arena")
		local spectate = type(payload) == "table" and payload.spectate
		local target
		if arena then
			if spectate then
				target = arena:FindFirstChild("Spectate")
			else
				local spawns = arena:FindFirstChild("Spawns")
				local list = spawns and spawns:GetChildren() or {}
				target = list[rng:NextInteger(1, math.max(1, #list))]
			end
		end
		if not target then
			return fail("Арена не найдена")
		end
		S.RestaurantService.teleport(player, target.CFrame * CFrame.new(rng:NextNumber(-3, 3), 4, rng:NextNumber(-3, 3)))
		if not spectate then
			local ff = Instance.new("ForceField")
			ff.Parent = player.Character
			Debris:AddItem(ff, SPAWN_PROTECTION)
		end
		return ok()
	end)
end

-- ===================== STARTER STANDS =====================
local function setupStands()
	local map = workspace:FindFirstChild("Map")
	local islands = map and map:FindFirstChild("Islands")
	if not islands then
		return
	end
	for _, island in ipairs(islands:GetChildren()) do
		local stand = island:FindFirstChild("WeaponStand")
		if stand then
			for _, w in ipairs(Weapons.Starter) do
				local spot = stand:FindFirstChild(w.id)
				if spot then
					local prompt = Instance.new("ProximityPrompt")
					prompt.Name = "TakePrompt"
					prompt.ActionText = "Взять бесплатно"
					prompt.ObjectText = w.name
					prompt.HoldDuration = 0.3
					prompt.MaxActivationDistance = 10
					prompt.RequiresLineOfSight = false
					prompt.Parent = spot
					prompt.Triggered:Connect(function(player)
						local p = profileOf(player)
						if not p then
							return
						end
						for uid, owned in pairs(p.data.weapons) do
							if owned.id == w.id then
								equip(player, uid)
								CombatService.pushCombat(player)
								Net.toast(player, "У вас уже есть: " .. w.name .. " (взято в руки)", "info")
								return
							end
						end
						if weaponCount(p) >= Weapons.MaxInventory then
							Net.toast(player, "Инвентарь оружия заполнен", "warn")
							return
						end
						local uid = grantWeapon(player, w.id)
						equip(player, uid)
						Net.fx(player, "weaponGet", { id = w.id, uid = uid, free = true })
						CombatService.pushCombat(player)
					end)
				end
			end
		end
	end
end

-- ===================== TICKS =====================
local function statusTick()
	local now = os.clock()
	for player, s in pairs(state) do
		if not player.Parent then
			state[player] = nil
		else
			local _, root, hum = charParts(player)
			if root and hum and hum.Health > 0 then
				-- position history for the Chrono Cleaver
				table.insert(s.history, { t = now, cf = root.CFrame, hp = hum.Health })
				while #s.history > 0 and now - s.history[1].t > 3.6 do
					table.remove(s.history, 1)
				end
				-- burn
				if s.burn then
					if s.burn.untilT <= now or not s.burn.by.Parent then
						s.burn = nil
					else
						s.burn.acc += s.burn.dps * 0.25
						if s.burn.acc >= 1 then
							local dmg = math.floor(s.burn.acc)
							s.burn.acc -= dmg
							CombatService.damage(s.burn.by, player, dmg, { kind = "burn" })
						end
					end
				end
				-- speed modifiers expire
				local changed = false
				for key, m in pairs(s.speed) do
					if m.untilT <= now then
						s.speed[key] = nil
						changed = true
					end
				end
				if changed then
					CombatService.refreshSpeed(player)
				end
			end
			-- traps of this player
			if #s.traps > 0 then
				local keep = {}
				for _, t in ipairs(s.traps) do
					if t.part and t.part.Parent and t.untilT > now then
						local triggered = false
						for _, e in ipairs(enemiesNear(player, t.part.Position, 3.2)) do
							CombatService.damage(player, e.player, 12, { kind = "thorn_traps" })
							cc(e.player, "root", 1.5)
							triggered = true
							break
						end
						if triggered then
							Net.fxAll("ability", { ability = "thorn_snap", point = t.part.Position, userId = player.UserId })
							t.part:Destroy()
						else
							table.insert(keep, t)
						end
					elseif t.part then
						t.part:Destroy()
					end
				end
				s.traps = keep
			end
		end
	end
end

local function boardTick()
	local list = {}
	for _, v in pairs(session) do
		table.insert(list, v)
	end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.deaths < b.deaths
	end)
	local top = {}
	for i = 1, math.min(8, #list) do
		top[i] = { name = list[i].name, kills = list[i].kills, deaths = list[i].deaths }
	end
	local inside = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if CombatService.inArena(p) then
			inside += 1
		end
	end
	Net.pushAll("arena", { top = top, inside = inside })
	local arena = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Arena")
	if arena then
		local lines = { "🏆 ТАБЛО АРЕНЫ  (победы / поражения)" }
		for i, e in ipairs(top) do
			table.insert(lines, string.format("%d. %s — %d / %d", i, e.name, e.kills, e.deaths))
		end
		if #top == 0 then
			table.insert(lines, "Пока никто не сражался")
		end
		table.insert(lines, "Сейчас на арене: " .. inside)
		local text = table.concat(lines, "\n")
		for _, b in ipairs(arena:GetDescendants()) do
			if b.Name == "BoardText" and b:IsA("TextLabel") then
				b.Text = text
			end
		end
	end
end

function CombatService.Start()
	registerRemotes()
	setupStands()
	local function onCharacter(player, char)
		local hum = char:WaitForChild("Humanoid", 10)
		local s = st(player)
		s.history = {}
		s.stunUntil, s.rootUntil, s.burn, s.shield = nil, nil, nil, nil
		s.killCredited = nil
		s.speed = {}
		if not player:GetAttribute("BaseSpeed") then
			player:SetAttribute("BaseSpeed", 18)
		end
		task.defer(function()
			local p = profileOf(player)
			if p and p.data.equipped ~= "" and p.data.weapons[p.data.equipped] then
				equipModel(player, Weapons.ById[p.data.weapons[p.data.equipped].id])
			end
			CombatService.refreshSpeed(player)
		end)
		if hum then
			hum.Died:Connect(function()
				local vs = st(player)
				local killer = vs.lastDamager
				-- deaths caused by PvP (e.g. falling after a knockback) still count
				if not vs.killCredited and killer and killer ~= player and killer.Parent and vs.lastDamageT and os.clock() - vs.lastDamageT < 8 then
					vs.killCredited = true
					onKill(killer, player)
				end
				vs.lastDamager = nil
				vs.streak = 0
			end)
		end
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		local s = state[p]
		if s then
			if s.golem then
				s.golem:Destroy()
			end
			for _, t in ipairs(s.traps) do
				if t.part then
					t.part:Destroy()
				end
			end
		end
		state[p] = nil
	end)
	S.DataService.onLoaded(function(player)
		task.wait(1)
		CombatService.pushCombat(player)
		S.LabService.push(player)
	end)
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.25)
			local ok1, e1 = pcall(statusTick)
			if not ok1 then
				warn("[CombatService] status: " .. tostring(e1))
			end
			acc += 0.25
			if acc >= 3 then
				acc = 0
				pcall(boardTick)
			end
		end
	end)
end

return CombatService
