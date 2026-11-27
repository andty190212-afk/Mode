-- Weapon animation poses shared by the SERVER (which plays them on the characters, so
-- every player sees them through normal replication) and the client (trails/aura).
-- Procedural: no animation assets needed. Works for R15 and R6 rigs.
local TweenService = game:GetService("TweenService")

local Poses = {}

local rad = math.rad
-- poses are stored as angles in degrees (x = raise forward, y = twist, z = sideways)
local function ang(x, y, z)
	return Vector3.new(x or 0, y or 0, z or 0)
end

local IDLE = ang(35, 0, 8) -- weapon arm slightly raised and forward

local baseC0 = {} -- [Motor6D] = original C0
local animating = {} -- [character] = true

-- strong tables (weak tables keyed by Instances are unreliable in Roblox); entries are
-- removed when the instance is destroyed
local function forget(t, inst)
	if t[inst] == nil and typeof(inst) == "Instance" then
		inst.Destroying:Connect(function()
			t[inst] = nil
		end)
	end
end


-- R15 and R6 rigs are both supported
function Poses.motors(char)
	local function m(part, name)
		local p = char:FindFirstChild(part)
		return p and p:FindFirstChild(name)
	end
	-- the weapon itself hangs on a Motor6D ("WeaponGrip") so it can flick on every swing
	local weapon = char:FindFirstChild("EquippedWeapon")
	local handle = weapon and weapon:FindFirstChild("Handle")
	local grip = handle and handle:FindFirstChild("WeaponGrip")
	if char:FindFirstChild("UpperTorso") then
		return {
			rs = m("RightUpperArm", "RightShoulder"),
			ls = m("LeftUpperArm", "LeftShoulder"),
			re = m("RightLowerArm", "RightElbow"),
			waist = m("UpperTorso", "Waist"),
			grip = grip,
		}, false
	end
	return {
		rs = m("Torso", "Right Shoulder"),
		ls = m("Torso", "Left Shoulder"),
		waist = m("HumanoidRootPart", "RootJoint"),
		grip = grip,
	}, true
end

-- convert a pose (degrees) into a C0 offset for the given joint
local function toCF(key, v, r6)
	if not r6 or key == "grip" then
		return CFrame.Angles(rad(v.X), rad(v.Y), rad(v.Z))
	end
	-- R6 joints are rotated: the shoulder swings around its local Z, the root twists around Z
	if key == "rs" then
		return CFrame.Angles(-rad(v.Z) * 0.5, 0, rad(v.X))
	elseif key == "ls" then
		return CFrame.Angles(rad(v.Z) * 0.5, 0, -rad(v.X))
	elseif key == "waist" then
		return CFrame.Angles(0, 0, rad(v.Y))
	end
	return CFrame.new()
end

local function base(motor)
	if not motor then
		return nil
	end
	local b = baseC0[motor]
	if not b then
		b = motor.C0
		forget(baseC0, motor)
		baseC0[motor] = b
	end
	return b
end

-- play keyframes: list of { time, { rs = ang, ls = ..., re = ..., waist = ... } }
function Poses.play(char, frames)
	local mo, r6 = Poses.motors(char)
	if (not mo.rs and not mo.grip) or animating[char] then
		return
	end
	forget(animating, char)
	animating[char] = true
	task.spawn(function()
		pcall(function()
			for i, f in ipairs(frames) do
				local dur, pose = f[1], f[2]
				for key, motor in pairs(mo) do
					local b = base(motor)
					if b then
						local v = pose[key] or (key == "rs" and IDLE or ang())
						if key == "grip" and not pose.grip then
							-- weapon flick: wind back on the first frame, snap forward on the second
							v = (i == 1 and ang(35, 0, 0)) or (i == 2 and ang(-55, 0, 0)) or ang()
						end
						TweenService:Create(motor, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = b * toCF(key, v, r6) }):Play()
					end
				end
				task.wait(dur)
			end
		end)
		animating[char] = nil
	end)
end

-- ===================== ATTACKS BY STYLE =====================
local ATTACKS = {
	-- quick thrust (rapier, kunai, ladle, chopsticks, chili blade)
	fast = {
		{ 0.07, { rs = ang(120, 0, 40), re = ang(-55, 0, 0), waist = ang(0, 20, 0) } },
		{ 0.07, { rs = ang(85, 0, -35), re = ang(0, 0, 0), waist = ang(0, -22, 0) } },
		{ 0.07, { rs = ang(110, 0, 25), re = ang(-20, 0, 0), waist = ang(0, 10, 0) } },
		{ 0.14, {} },
	},
	-- heavy overhead slam (bat, rolling pin, meteor mace, golem gauntlet)
	heavy = {
		{ 0.16, { rs = ang(160, 0, 25), ls = ang(40, 0, -10), re = ang(-40, 0, 0), waist = ang(-8, 30, 0) } },
		{ 0.1, { rs = ang(20, 0, -10), ls = ang(10, 0, 0), re = ang(0, 0, 0), waist = ang(12, -25, 0) } },
		{ 0.22, {} },
	},
	-- wide horizontal slash (most melee)
	slash = {
		{ 0.11, { rs = ang(110, 0, 85), re = ang(-35, 0, 0), waist = ang(0, 40, 0) } },
		{ 0.1, { rs = ang(80, 0, -70), re = ang(0, 0, 0), waist = ang(5, -40, 0) } },
		{ 0.18, {} },
	},
	-- ranged: a big overhand wave (wind back over the shoulder, swing forward = shot)
	ranged = {
		{ 0.12, { rs = ang(165, 0, 35), re = ang(-45, 0, 0), ls = ang(30, 0, -15), waist = ang(-6, 28, 0) } },
		{ 0.1, { rs = ang(70, 0, -25), re = ang(0, 0, 0), ls = ang(15, 0, 0), waist = ang(8, -25, 0) } },
		{ 0.18, {} },
	},
	-- magic: raise, then point forward
	magic = {
		{ 0.12, { rs = ang(150, 0, 10), re = ang(-30, 0, 0) } },
		{ 0.1, { rs = ang(95, 0, 0), re = ang(0, 0, 0), waist = ang(0, -10, 0) } },
		{ 0.16, {} },
	},
}

local STYLE_ANIM = {
	fast = "fast",
	heavy = "heavy",
	ranged = "ranged",
	magic = "magic",
	defense = "slash",
	control = "slash",
	summon = "slash",
	mobility = "fast",
	mass = "slash",
}

-- ===================== ABILITIES: a unique animation for every weapon skill =====================
local function F(t, pose)
	return { t, pose }
end
local REST = F(0.2, {})

local ABILITY_ANIM = {
	-- Бита «Хоум-ран»: долгий замах двумя руками и мощный удар
	home_run = { F(0.25, { rs = ang(150, 0, 60), ls = ang(120, 0, 40), waist = ang(0, 60, 0), grip = ang(60, 0, 0) }), F(0.12, { rs = ang(80, 0, -80), ls = ang(70, 0, -40), waist = ang(5, -70, 0), grip = ang(-70, 0, 0) }), F(0.2, { rs = ang(60, 0, -90), waist = ang(0, -80, 0) }), REST },
	-- Меч «Защитная стойка»: клинок поперёк груди, вторая рука упирается
	guard = { F(0.12, { rs = ang(95, 0, -50), ls = ang(85, 0, 45), re = ang(-70, 0, 0), grip = ang(0, 0, 90) }), F(1.6, { rs = ang(95, 0, -50), ls = ang(85, 0, 45), re = ang(-70, 0, 0), waist = ang(8, 0, 0), grip = ang(0, 0, 90) }), REST },
	-- Половник «Вихрь»: руки в стороны, полный оборот корпусом
	spin = { F(0.1, { rs = ang(90, 0, 85), ls = ang(85, 0, -85), waist = ang(0, 120, 0) }), F(0.1, { rs = ang(90, 0, 85), ls = ang(85, 0, -85), waist = ang(0, 240, 0) }), F(0.1, { rs = ang(90, 0, 85), ls = ang(85, 0, -85), waist = ang(0, 359, 0) }), REST },
	-- Праща «Кокосовая бомба»: раскрутка над головой и бросок
	coconut_bomb = { F(0.12, { rs = ang(175, 0, 30), grip = ang(0, 120, 0) }), F(0.12, { rs = ang(175, 0, -30), grip = ang(0, 240, 0) }), F(0.1, { rs = ang(60, 0, -20), waist = ang(10, -25, 0), grip = ang(-60, 0, 0) }), REST },
	-- Скалка «Таран»: присед, скалка вперёд двумя руками
	charge = { F(0.12, { rs = ang(70, 0, -10), ls = ang(70, 0, 10), waist = ang(-15, 0, 0) }), F(0.25, { rs = ang(90, 0, -15), ls = ang(90, 0, 15), waist = ang(25, 0, 0), grip = ang(-90, 0, 0) }), REST },
	-- Палочка «Пузырь-ловушка»: круг палочкой и выстрел
	bubble_trap = { F(0.1, { rs = ang(110, 0, 30), grip = ang(0, 0, 40) }), F(0.1, { rs = ang(130, 0, -10), grip = ang(0, 0, -40) }), F(0.1, { rs = ang(100, 0, 20) }), F(0.1, { rs = ang(95, 0, 0), re = ang(0, 0, 0), grip = ang(-40, 0, 0) }), REST },
	-- Перчёный клинок «Огненная волна»: широкий взмах снизу вверх
	flame_wave = { F(0.12, { rs = ang(20, 0, 70), waist = ang(0, 40, 0) }), F(0.14, { rs = ang(150, 0, -60), waist = ang(-10, -45, 0), grip = ang(-60, 0, 0) }), REST },
	-- Морозная лопатка «Ледяное поле»: удар лопаткой в землю
	ice_field = { F(0.2, { rs = ang(170, 0, 10), ls = ang(60, 0, 0), waist = ang(-10, 0, 0) }), F(0.1, { rs = ang(10, 0, 0), waist = ang(30, 0, 0), grip = ang(-80, 0, 0) }), F(0.35, { rs = ang(10, 0, 0), waist = ang(30, 0, 0) }), REST },
	-- Якорь «Цепной крюк»: бросок крюка и рывок на себя
	hook_pull = { F(0.12, { rs = ang(160, 0, 40), waist = ang(0, 35, 0) }), F(0.1, { rs = ang(90, 0, -10), waist = ang(0, -20, 0), grip = ang(-50, 0, 0) }), F(0.15, { rs = ang(40, 0, 30), ls = ang(40, 0, -20), waist = ang(-15, 30, 0), grip = ang(40, 0, 0) }), REST },
	-- Венчик «Разряд»: венчик к небу, затем указать на врага
	static_shock = { F(0.15, { rs = ang(178, 0, 0), grip = ang(0, 360, 0) }), F(0.1, { rs = ang(178, 0, 5) }), F(0.1, { rs = ang(95, 0, 0), grip = ang(-30, 0, 0) }), REST },
	-- Трезубец «Приливная волна»: трезубец над головой двумя руками и бросок вперёд
	tidal_wave = { F(0.2, { rs = ang(175, 0, 10), ls = ang(175, 0, -10), waist = ang(-12, 0, 0) }), F(0.12, { rs = ang(80, 0, 0), ls = ang(80, 0, 0), waist = ang(20, 0, 0), grip = ang(-60, 0, 0) }), REST },
	-- Зеркальный щит «Зеркало»: щит перед лицом
	reflect = { F(0.1, { rs = ang(110, 0, -70), re = ang(-80, 0, 0), ls = ang(30, 0, 20), grip = ang(0, 90, 0) }), F(2.8, { rs = ang(110, 0, -70), re = ang(-80, 0, 0), ls = ang(30, 0, 20), grip = ang(0, 90, 0) }), REST },
	-- Вилка роя «Рой»: дирижирует вилкой, выпуская пчёл
	bee_swarm = { F(0.1, { rs = ang(120, 0, 40) }), F(0.1, { rs = ang(140, 0, -20) }), F(0.1, { rs = ang(120, 0, 40) }), F(0.1, { rs = ang(100, 0, 0), grip = ang(-40, 0, 0) }), REST },
	-- Веер «Восходящий поток»: мах веером вниз, руки вверх
	updraft = { F(0.1, { rs = ang(150, 0, 30), ls = ang(150, 0, -30) }), F(0.12, { rs = ang(20, 0, 20), ls = ang(20, 0, -20), waist = ang(10, 0, 0), grip = ang(-80, 0, 0) }), F(0.3, { rs = ang(175, 0, 40), ls = ang(175, 0, -40) }), REST },
	-- Булава «Метеорит»: призыв двумя руками вверх и указание
	meteor = { F(0.25, { rs = ang(175, 0, 25), ls = ang(175, 0, -25), waist = ang(-15, 0, 0) }), F(0.25, { rs = ang(178, 0, 30), ls = ang(178, 0, -30), waist = ang(-18, 0, 0) }), F(0.15, { rs = ang(100, 0, -5), waist = ang(10, 0, 0), grip = ang(-50, 0, 0) }), REST },
	-- Кунаи «Теневой шаг»: низкая стойка и удар в спину
	shadow_step = { F(0.08, { rs = ang(20, 0, 30), ls = ang(20, 0, -30), waist = ang(20, 0, 0) }), F(0.1, { rs = ang(120, 0, -40), waist = ang(10, -30, 0), grip = ang(-90, 0, 0) }), REST },
	-- Лиана «Шипастые ловушки»: хлещет лианой по земле трижды
	thorn_traps = { F(0.1, { rs = ang(140, 0, 30) }), F(0.08, { rs = ang(30, 0, 30), waist = ang(15, 15, 0), grip = ang(-60, 0, 0) }), F(0.1, { rs = ang(140, 0, 0) }), F(0.08, { rs = ang(30, 0, 0), waist = ang(15, 0, 0), grip = ang(-60, 0, 0) }), F(0.1, { rs = ang(140, 0, -30) }), F(0.08, { rs = ang(30, 0, -30), waist = ang(15, -15, 0), grip = ang(-60, 0, 0) }), REST },
	-- Ложка-пушка «Плазменный луч»: упор двумя руками и отдача
	plasma_beam = { F(0.15, { rs = ang(92, 0, 0), ls = ang(85, 0, 30), waist = ang(5, 0, 0) }), F(0.08, { rs = ang(110, 0, 0), ls = ang(100, 0, 30), waist = ang(-12, 0, 0), grip = ang(20, 0, 0) }), F(0.3, { rs = ang(92, 0, 0), ls = ang(85, 0, 30) }), REST },
	-- Алебарда «Буря»: два оборота с алебардой над головой
	storm_aura = { F(0.12, { rs = ang(170, 0, 30), ls = ang(170, 0, -30), waist = ang(0, 180, 0) }), F(0.12, { rs = ang(170, 0, 30), ls = ang(170, 0, -30), waist = ang(0, 359, 0) }), F(0.12, { rs = ang(170, 0, 30), ls = ang(170, 0, -30), waist = ang(0, 180, 0) }), F(0.12, { rs = ang(170, 0, 30), ls = ang(170, 0, -30), waist = ang(0, 359, 0) }), REST },
	-- Лук «Огненный дождь»: выстрел вверх
	fire_rain = { F(0.15, { rs = ang(160, 0, 0), ls = ang(150, 0, 30), waist = ang(-20, 0, 0) }), F(0.4, { rs = ang(165, 0, 0), ls = ang(140, 0, 40), waist = ang(-22, 0, 0), grip = ang(15, 0, 0) }), F(0.15, { rs = ang(170, 0, 0), ls = ang(120, 0, 30), waist = ang(-20, 0, 0) }), REST },
	-- Перчатка «Каменный голем»: удар кулаком в землю
	summon_golem = { F(0.2, { rs = ang(170, 0, -10), waist = ang(-10, 0, 0) }), F(0.1, { rs = ang(-10, 0, 0), waist = ang(35, 0, 0), grip = ang(-40, 0, 0) }), F(0.4, { rs = ang(-10, 0, 0), waist = ang(35, 0, 0) }), REST },
	-- Хроно-тесак «Перемотка»: тесак описывает круг циферблата
	rewind = { F(0.1, { rs = ang(170, 0, 0), grip = ang(0, 0, 90) }), F(0.1, { rs = ang(90, 0, 80), grip = ang(0, 0, 180) }), F(0.1, { rs = ang(10, 0, 0), grip = ang(0, 0, 270) }), F(0.1, { rs = ang(90, 0, -80), grip = ang(0, 0, 359) }), REST },
	-- Коса «Чёрная дыра»: коса указывает вперёд, медленно сжимается кулак
	black_hole = { F(0.2, { rs = ang(100, 0, 0), ls = ang(100, 0, 0), waist = ang(-5, 0, 0) }), F(1.2, { rs = ang(105, 0, -10), ls = ang(105, 0, 10), re = ang(-40, 0, 0), waist = ang(-8, 0, 0), grip = ang(-30, 0, 0) }), REST },
	-- Рапира «Мираж»: поклон и исчезновение
	mirage = { F(0.15, { rs = ang(40, 0, 60), ls = ang(20, 0, -20), waist = ang(30, 0, 0), grip = ang(0, 0, 60) }), F(0.15, { rs = ang(100, 0, 0), waist = ang(-10, 0, 0) }), REST },
	-- Вок «Дыхание дракона»: вок двумя руками перед собой
	dragon_breath = { F(0.15, { rs = ang(95, 0, -20), ls = ang(95, 0, 20), waist = ang(-5, 0, 0) }), F(1.7, { rs = ang(100, 0, -20), ls = ang(100, 0, 20), waist = ang(-8, 0, 0) }), REST },
	-- Фонарь «Купол-страж»: фонарь высоко над головой
	guardian_dome = { F(0.2, { rs = ang(178, 0, 0), ls = ang(120, 0, -40) }), F(1.2, { rs = ang(178, 0, 0), ls = ang(120, 0, -40), waist = ang(-10, 0, 0) }), REST },
	-- Жезл «Звездопад»: жезл описывает дугу по небу
	starfall = { F(0.15, { rs = ang(150, 0, 70), waist = ang(-10, 30, 0) }), F(0.25, { rs = ang(170, 0, 0), waist = ang(-15, 0, 0) }), F(0.25, { rs = ang(150, 0, -70), waist = ang(-10, -30, 0) }), F(0.12, { rs = ang(100, 0, 0), grip = ang(-50, 0, 0) }), REST },
	-- Глефа «Цепи душ»: бросок цепей и рывок обеими руками
	soul_chains = { F(0.12, { rs = ang(130, 0, 60), ls = ang(130, 0, -60), waist = ang(-10, 0, 0) }), F(0.12, { rs = ang(80, 0, -20), ls = ang(80, 0, 20), waist = ang(15, 0, 0) }), F(0.2, { rs = ang(30, 0, 30), ls = ang(30, 0, -30), waist = ang(-15, 0, 0), grip = ang(40, 0, 0) }), REST },
	-- Квантовые палочки «Шквал»: серия молниеносных уколов
	blink_barrage = { F(0.05, { rs = ang(100, 0, 30) }), F(0.05, { rs = ang(80, 0, -30), grip = ang(-40, 0, 0) }), F(0.05, { rs = ang(110, 0, 20) }), F(0.05, { rs = ang(85, 0, -20), grip = ang(-40, 0, 0) }), F(0.05, { rs = ang(105, 0, 0) }), F(0.05, { rs = ang(90, 0, -10), grip = ang(-40, 0, 0) }), REST },
	-- Золотая лопатка «Ударная волна Мидаса»: прыжок-замах и удар в землю двумя руками
	midas_shockwave = { F(0.22, { rs = ang(178, 0, 5), ls = ang(178, 0, -5), waist = ang(-20, 0, 0) }), F(0.1, { rs = ang(30, 0, 0), ls = ang(30, 0, 0), waist = ang(40, 0, 0), grip = ang(-90, 0, 0) }), F(0.4, { rs = ang(30, 0, 0), ls = ang(30, 0, 0), waist = ang(40, 0, 0) }), REST },
}

Poses.IDLE = IDLE
Poses.ATTACKS = ATTACKS
Poses.STYLE_ANIM = STYLE_ANIM
Poses.ABILITY_ANIM = ABILITY_ANIM
Poses.toCF = toCF
Poses.base = base
Poses.baseC0 = baseC0
Poses.animating = animating

Poses.EAT = {
	{ 0.15, { rs = ang(140, 0, -35), re = ang(-90, 0, 0) } },
	{ 0.15, { rs = ang(120, 0, -30), re = ang(-70, 0, 0) } },
	{ 0.15, { rs = ang(140, 0, -35), re = ang(-90, 0, 0) } },
	{ 0.2, {} },
}

function Poses.attackFrames(def)
	local frames = ATTACKS[STYLE_ANIM[def.style] or "slash"]
	if def.kind == "ranged" and def.style ~= "magic" then
		frames = ATTACKS.ranged
	end
	return frames
end

-- hold pose while a weapon is in hand (call again after the character changes)
function Poses.setIdle(char, holding)
	local mo, r6 = Poses.motors(char)
	if not mo.rs or animating[char] then
		return
	end
	if holding then
		mo.rs.C0 = base(mo.rs) * toCF("rs", IDLE, r6)
	elseif baseC0[mo.rs] then
		mo.rs.C0 = baseC0[mo.rs]
	end
end

function Poses.interrupt(char)
	animating[char] = nil
end

return Poses
