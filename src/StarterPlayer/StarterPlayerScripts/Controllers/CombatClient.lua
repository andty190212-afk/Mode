-- Combat client: attack / ability input (PC: LMB + F, phones: on-screen buttons),
-- cooldown indicators, health & arena HUD, arena window and all combat visual effects.
-- The client only sends "attack/ability + aim"; hits are decided by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MapLayout = require(Shared.MapLayout)
local Data = Shared.Data
local Weapons = require(Data.Weapons)
local Rarities = require(Data.Rarities)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local CombatClient = {}
local player = Players.LocalPlayer
local Build -- BuildController (to ignore clicks in build mode)

local localAttackReady, localAbilityReady = 0, 0
local refs = {}

local function equipped()
	local cs = State.combat
	if not cs or cs.equipped == "" then
		return nil
	end
	for _, w in ipairs(cs.weapons) do
		if w.uid == cs.equipped then
			return Weapons.ById[w.id]
		end
	end
	return nil
end

local function rootPart()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- aim: mouse point on PC, camera direction on touch devices
local function aim()
	local root = rootPart()
	local cam = workspace.CurrentCamera
	if not root or not cam then
		return nil
	end
	local point
	if not UI.isMobile then
		local m = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(m.X, m.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
		point = hit and hit.Position or (ray.Origin + ray.Direction * 60)
	else
		point = root.Position + cam.CFrame.LookVector * 25
	end
	local dir = point - root.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		dir = root.CFrame.LookVector
	end
	return dir.Unit, point
end

local function faceDir(dir)
	local root = rootPart()
	if root and dir then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	end
end

function CombatClient.attack()
	local def = equipped()
	if not def or os.clock() < localAttackReady then
		return
	end
	if player:GetAttribute("Carrying") then
		return
	end
	localAttackReady = os.clock() + def.cooldown
	local dir = aim()
	faceDir(dir)
	Net.action("Attack", { dir = dir })
end

function CombatClient.ability()
	local def = equipped()
	if not def then
		UI.toast("Сначала возьмите оружие (🧪 → Оружие или стенд на острове)", "warn")
		return
	end
	if os.clock() < localAbilityReady then
		return
	end
	local dir, point = aim()
	faceDir(dir)
	local res = Net.request("Ability", { dir = dir, point = point })
	if res and res.ok then
		localAbilityReady = os.clock() + (res.cooldown or def.ability.cooldown)
		UI.sound(Config.Sounds.Ability, 0.45, 1.2)
	elseif res and res.err then
		UI.toast(res.err, "warn")
	end
end

-- ===================== HUD =====================
local function buildHud()
	local gui = UI.screen()
	local panel = UI.new("Frame", {
		Name = "CombatHud",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -100),
		Size = UDim2.fromOffset(250, 170),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	refs.panel = panel
	refs.weapon = UI.label(panel, "", 14, { align = Enum.TextXAlignment.Right, sizeUDim = UDim2.new(1, 0, 0, 40) })
	local attackBtn = UI.button(panel, "⚔️", T.bad, function()
		CombatClient.attack()
	end, { size = UDim2.fromOffset(92, 92) })
	attackBtn.Position = UDim2.new(1, -92, 1, -92)
	attackBtn.TextSize = 38
	UI.corner(attackBtn, 46)
	local abilityBtn = UI.button(panel, "✨", T.purple, function()
		CombatClient.ability()
	end, { size = UDim2.fromOffset(74, 74) })
	abilityBtn.Position = UDim2.new(1, -180, 1, -78)
	abilityBtn.TextSize = 30
	UI.corner(abilityBtn, 37)
	refs.abilityBtn = abilityBtn
	refs.cdShade = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 3, Parent = abilityBtn })
	UI.corner(refs.cdShade, 37)
	refs.cdText = UI.label(refs.cdShade, "", 22, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromScale(1, 1) })
	refs.cdText.ZIndex = 4
	refs.hint = UI.label(panel, UI.isMobile and "" or "ЛКМ — удар • F — способность", 12, { align = Enum.TextXAlignment.Right, color = T.sub, sizeUDim = UDim2.new(1, 0, 0, 18) })
	refs.hint.Position = UDim2.new(0, 0, 1, 2)

	-- health + arena bar (top-left under the money pills)
	local bar = UI.new("Frame", {
		Name = "PvpBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(420, 44),
		BackgroundColor3 = T.panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	})
	UI.corner(bar, 12)
	refs.bar = bar
	refs.hp = UI.progress(bar, 1, T.good, { size = UDim2.new(1, -20, 0, 12), position = UDim2.fromOffset(10, 6) })
	refs.arenaText = UI.label(bar, "", 13, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, -20, 0, 20) })
	refs.arenaText.Position = UDim2.fromOffset(10, 20)
end

local function updateHud()
	local def = equipped()
	refs.panel.Visible = def ~= nil
	if def then
		local c = Rarities.Info[def.rarity].color
		refs.weapon.Text = string.format("%s <b>%s</b>\n<font color='#%02X%02X%02X'>%s</font> • %s", def.icon, def.name, c[1], c[2], c[3], def.starter and "Бесплатное" or Rarities.Info[def.rarity].name, def.ability.name)
		local left = localAbilityReady - os.clock()
		refs.cdShade.Visible = left > 0
		refs.cdText.Text = left > 0 and tostring(math.ceil(left)) or ""
	end
	local root = rootPart()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local inArena = root and MapLayout.inArena(root.Position.X, root.Position.Y, root.Position.Z)
	local hurt = hum and hum.Health < hum.MaxHealth
	refs.bar.Visible = (inArena or hurt or player:GetAttribute("Carrying") ~= nil) and true or false
	if hum then
		local f = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
		refs.hp.Fill.Size = UDim2.fromScale(f, 1)
		refs.hp.Fill.BackgroundColor3 = f > 0.5 and T.good or (f > 0.25 and T.warn or T.bad)
	end
	local s = State.combat and State.combat.stats or {}
	local arena = State.arena or {}
	refs.arenaText.Text = string.format("%s ❤️ %d • ⚔️ побед %d • 💀 поражений %d • на арене: %d",
		inArena and "⚔️ АРЕНА" or (player:GetAttribute("Carrying") and "🦹 С ДОБЫЧЕЙ" or "🛡️ Вне арены"),
		hum and math.floor(hum.Health) or 0, s.arenaKills or 0, s.arenaDeaths or 0, arena.inside or 0)
end

-- ===================== ARENA WINDOW =====================
local function renderArena(c)
	local s = State.combat and State.combat.stats or {}
	local kd = (s.arenaKills or 0) / math.max(1, s.arenaDeaths or 0)
	UI.label(c, "⚔️ Центральная арена соединена мостами со всеми 8 островами. На арене разрешены PvP-бои, на точках появления действует защита 6 секунд. Вне арены бить можно только вора с вашим существом (и вор может защищаться).", 14, { auto = true, color = T.sub })
	UI.label(c, string.format("🏆 Победы: <b>%d</b> • 💀 Поражения: <b>%d</b> • K/D %.2f • Лучшая серия: %d", s.arenaKills or 0, s.arenaDeaths or 0, kd, s.bestStreak or 0), 16, { auto = true })
	local row = UI.row(c, 50)
	UI.button(row, "⚔️ На арену", T.bad, function()
		if UI.request(Net, "JoinArena", {}).ok then
			UI.close("arena")
		end
	end, { size = UDim2.fromOffset(200, 46) })
	UI.button(row, "👀 Смотреть бои", T.blue, function()
		if UI.request(Net, "JoinArena", { spectate = true }).ok then
			UI.close("arena")
		end
	end, { size = UDim2.fromOffset(200, 46) })
	UI.button(row, "🗡️ Моё оружие", T.card, function()
		UI.open("lab")
		UI.windows.lab.tab = "weapons"
		UI.windows.lab:refresh()
	end, { size = UDim2.fromOffset(180, 46) })
	UI.label(c, "Табло сервера", 18, { font = UI.Font, color = T.accent })
	local top = State.arena and State.arena.top or {}
	if #top == 0 then
		UI.label(c, "Пока никто не сражался.", 15, { color = T.sub })
	end
	for i, e in ipairs(top) do
		UI.label(c, string.format("%d. <b>%s</b> — ⚔️ %d / 💀 %d", i, e.name, e.kills, e.deaths), 15)
	end
end

-- ===================== VISUAL EFFECTS =====================
local function part(props)
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
	p.Parent = workspace
	return p
end

local function col(c)
	if type(c) == "table" then
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	return Color3.fromRGB(255, 200, 80)
end

local function ring(pos, radius, color, dur)
	local p = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1, 1), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = 0.2 })
	TweenService:Create(p, TweenInfo.new(dur or 0.4), { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(p, (dur or 0.4) + 0.1)
end

local function sphere(pos, radius, color, dur, keep)
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos), Color = color, Transparency = 0.3 })
	TweenService:Create(p, TweenInfo.new(dur or 0.35), { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = keep and 0.6 or 1 }):Play()
	Debris:AddItem(p, (dur or 0.35) + (keep or 0) + 0.1)
	return p
end

local function line(a, b, color, width, dur)
	local d = (b - a).Magnitude
	if d < 0.1 then
		return
	end
	local p = part({ Size = Vector3.new(width or 0.5, width or 0.5, d), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color, Transparency = 0.1 })
	TweenService:Create(p, TweenInfo.new(dur or 0.3), { Transparency = 1 }):Play()
	Debris:AddItem(p, (dur or 0.3) + 0.1)
end

local function projectile(a, b, color, size, time)
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(size or 0.8, size or 0.8, size or 0.8), CFrame = CFrame.new(a), Color = color })
	TweenService:Create(p, TweenInfo.new(time or 0.25, Enum.EasingStyle.Linear), { CFrame = CFrame.new(b) }):Play()
	Debris:AddItem(p, (time or 0.25) + 0.05)
end

local function falling(point, color, size, delay)
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = CFrame.new(point + Vector3.new(6, 50, 0)), Color = color })
	TweenService:Create(p, TweenInfo.new(delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(point) }):Play()
	Debris:AddItem(p, delay + 0.05)
	task.delay(delay, function()
		sphere(point, size * 2.5, color, 0.4)
		ring(point, size * 3, color, 0.5)
	end)
end

local function charOf(userId)
	local p = Players:GetPlayerByUserId(userId or 0)
	return p and p.Character
end

local function billboard(char, text, dur, color)
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(80, 40)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Parent = bb
	bb.Parent = head
	Debris:AddItem(bb, dur)
end

local function swingArm(char)
	local arm = char and char:FindFirstChild("RightUpperArm")
	local motor = arm and arm:FindFirstChildWhichIsA("Motor6D")
	if not motor or motor:GetAttribute("Swinging") then
		return
	end
	motor:SetAttribute("Swinging", true)
	local c0 = motor.C0
	local tw = TweenService:Create(motor, TweenInfo.new(0.09), { C0 = c0 * CFrame.Angles(math.rad(120), 0, 0) })
	tw:Play()
	task.delay(0.1, function()
		TweenService:Create(motor, TweenInfo.new(0.16), { C0 = c0 }):Play()
		task.delay(0.17, function()
			motor:SetAttribute("Swinging", nil)
		end)
	end)
end

local RINGS = { spin = 9, midas_shockwave = 18, updraft = 8, home_run = 5 }

local function abilityFx(d)
	local color = col(d.color)
	local from = d.from or Vector3.zero
	local a = d.ability
	if RINGS[a] then
		ring(from, RINGS[a], color, 0.45)
		if a == "midas_shockwave" then
			sphere(from, 6, Color3.fromRGB(255, 220, 80), 0.4)
		end
	elseif a == "coconut_bomb" or a == "meteor" or a == "fire_rain" or a == "starfall" then
		falling(d.point or from, color, a == "meteor" and 5 or 2, d.delay or 0.5)
	elseif a == "mirage_boom" then
		sphere(d.point, 8, color, 0.4)
	elseif a == "plasma_beam" or a == "static_shock" or a == "hook_pull" or a == "charge" or a == "rewind" or a == "shadow_step" then
		line(from, d.to or (from + (d.dir or Vector3.zAxis) * 20), color, a == "plasma_beam" and 1.6 or 0.5, 0.35)
	elseif a == "tidal_wave" then
		local dir = d.dir or Vector3.new(0, 0, -1)
		local w = part({ Size = Vector3.new(12, 5, 2), CFrame = CFrame.lookAt(from, from + dir), Color = Color3.fromRGB(60, 160, 255), Transparency = 0.3 })
		TweenService:Create(w, TweenInfo.new(0.5), { CFrame = CFrame.lookAt(from + dir * 30, from + dir * 31), Transparency = 1 }):Play()
		Debris:AddItem(w, 0.6)
	elseif a == "bee_swarm" or a == "bubble_trap" then
		projectile(from + Vector3.new(0, 2, 0), d.to or from, color, a == "bubble_trap" and 3 or 0.7, d.travel or 0.3)
	elseif a == "ice_field" or a == "storm_aura" or a == "guardian_dome" or a == "black_hole" then
		local p = d.point or from
		local s = sphere(p, d.radius or 10, a == "black_hole" and Color3.fromRGB(30, 0, 60) or color, 0.4, d.dur)
		if a ~= "black_hole" and a ~= "ice_field" then
			local owner = charOf(d.userId)
			local root = owner and owner:FindFirstChild("HumanoidRootPart")
			if root then
				task.spawn(function()
					local t0 = os.clock()
					while s.Parent and os.clock() - t0 < (d.dur or 3) do
						s.CFrame = root.CFrame
						task.wait()
					end
				end)
			end
		end
	elseif a == "flame_wave" or a == "dragon_breath" then
		local dir = d.dir or Vector3.new(0, 0, -1)
		for k = 1, (a == "dragon_breath" and 14 or 7) do
			task.delay(k * 0.1, function()
				local spread = CFrame.Angles(0, math.rad(math.random(-25, 25)), 0):VectorToWorldSpace(dir)
				projectile(from + Vector3.new(0, 1.5, 0), from + spread * (d.range or 16), Color3.fromRGB(255, 120 + math.random(0, 80), 30), 1.4, 0.35)
			end)
		end
	elseif a == "soul_chains" then
		for _, uid in ipairs(d.targets or {}) do
			local c = charOf(uid)
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if r then
				line(from, r.Position, color, 0.4, 1.2)
			end
		end
	elseif a == "guard" or a == "reflect" then
		local owner = charOf(d.userId)
		local root = owner and owner:FindFirstChild("HumanoidRootPart")
		if root then
			local s = sphere(root.Position, 4, a == "reflect" and Color3.fromRGB(220, 240, 255) or Color3.fromRGB(200, 200, 210), 0.2, d.dur or 2)
			task.spawn(function()
				local t0 = os.clock()
				while s.Parent and os.clock() - t0 < (d.dur or 2) do
					s.CFrame = root.CFrame
					task.wait()
				end
			end)
		end
	elseif a == "thorn_snap" then
		ring(d.point, 4, Color3.fromRGB(80, 200, 60), 0.4)
	elseif a == "summon_golem" or a == "mirage" or a == "blink_barrage" or a == "thorn_traps" then
		sphere(d.to or d.point or from, 4, color, 0.35)
	end
end

function CombatClient.init(build)
	Build = build
	buildHud()
	UI.window("arena", "Арена", "⚔️", { render = renderArena, width = 720, height = 520 })

	Net.onPush("combat", function(data)
		State.set("combat", data)
		if data.abilityReady and data.abilityReady > 0 then
			localAbilityReady = os.clock() + data.abilityReady
		end
		if UI.isOpen("lab") then
			UI.windows.lab:refresh()
		end
		if UI.isOpen("arena") then
			UI.windows.arena:refresh()
		end
	end)
	Net.onPush("arena", function(data)
		State.set("arena", data)
		if UI.isOpen("arena") then
			UI.windows.arena:refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if Build and Build.isActive() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if equipped() then
				CombatClient.attack()
			end
		elseif input.KeyCode == Enum.KeyCode.F then
			if equipped() then
				CombatClient.ability()
			end
		end
	end)

	Net.remote("Fx").OnClientEvent:Connect(function(name, d)
		d = d or {}
		if name == "swing" then
			local char = charOf(d.userId)
			swingArm(char)
			if d.kind == "ranged" and d.from and d.dir then
				projectile(d.from + Vector3.new(0, 1.5, 0), d.from + d.dir * (d.range or 30) + Vector3.new(0, 1.5, 0), col(d.color), d.projectile == "plasma" and 1 or 0.6, (d.range or 30) / 120)
			end
			local root = rootPart()
			if root and d.from and (root.Position - d.from).Magnitude < 60 then
				UI.sound(Config.Sounds.Swing, 0.35, 1 + math.random() * 0.2)
			end
		elseif name == "hit" then
			if d.pos and d.amount and d.amount > 0 then
				local p = part({ Size = Vector3.new(0.1, 0.1, 0.1), CFrame = CFrame.new(d.pos + Vector3.new(0, 3, 0)), Transparency = 1 })
				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromOffset(80, 36)
				bb.AlwaysOnTop = true
				local l = Instance.new("TextLabel")
				l.Size = UDim2.fromScale(1, 1)
				l.BackgroundTransparency = 1
				l.Text = "-" .. tostring(d.amount)
				l.TextScaled = true
				l.TextColor3 = d.victim == player.UserId and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 230, 90)
				l.TextStrokeTransparency = 0.3
				l.Parent = bb
				bb.Parent = p
				TweenService:Create(p, TweenInfo.new(0.8), { CFrame = p.CFrame + Vector3.new(0, 3, 0) }):Play()
				Debris:AddItem(p, 0.9)
				if d.victim == player.UserId or d.by == player.UserId then
					UI.sound(Config.Sounds.Hit, 0.45, 0.9 + math.random() * 0.3)
				end
			end
		elseif name == "ability" then
			abilityFx(d)
		elseif name == "cc" then
			billboard(charOf(d.userId), d.kind == "stun" and "💫" or "🌿", d.dur or 1)
		elseif name == "status" then
			billboard(charOf(d.userId), "🔥", d.dur or 2, Color3.fromRGB(255, 140, 40))
		elseif name == "knock" then
			local root = rootPart()
			if root and d.vel then
				root.AssemblyLinearVelocity = d.vel
			end
		elseif name == "eatDish" then
			local char = charOf(d.userId)
			local Creatures = require(Data.Creatures)
			local dish = Creatures.DishById[d.dish]
			billboard(char, dish and dish.icon or "🍽️", 1.6)
			swingArm(char)
		elseif name == "pvp" then
			if d.kind == "kill" then
				UI.toast("⚔️ Победа над " .. (d.name or "?") .. "! +$50", "success")
			elseif d.kind == "death" then
				UI.toast("💀 Вас победил " .. (d.name or "?"), "error")
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			pcall(updateHud)
		end
	end)
	task.spawn(function()
		task.wait(2)
		local res = Net.request("CombatState", {})
		if res and res.ok and res.state then
			State.set("combat", res.state)
		end
	end)
end

return CombatClient
