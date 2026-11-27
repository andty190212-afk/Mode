-- Unique character motion for every weapon skill, layered ON TOP of the playing animation
-- through Motor6D.Transform (C0 is read-only in newer avatars; Transform is what the Animator
-- itself writes every frame). Runs on every client for every character, so all players see it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AbilityMotion = {}
local rad = math.rad

local function ang(x, y, z)
	return Vector3.new(x or 0, y or 0, z or 0)
end

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

local JOINTS = {
	R15 = { rs = { "RightUpperArm", "RightShoulder" }, ls = { "LeftUpperArm", "LeftShoulder" }, re = { "RightLowerArm", "RightElbow" }, waist = { "UpperTorso", "Waist" } },
	R6 = { rs = { "Torso", "Right Shoulder" }, ls = { "Torso", "Left Shoulder" }, waist = { "HumanoidRootPart", "RootJoint" } },
}

local function toCF(key, v, r6)
	if not r6 then
		return CFrame.Angles(rad(v.X), rad(v.Y), rad(v.Z))
	end
	if key == "rs" then
		return CFrame.Angles(-rad(v.Z) * 0.5, 0, rad(v.X))
	elseif key == "ls" then
		return CFrame.Angles(rad(v.Z) * 0.5, 0, -rad(v.X))
	elseif key == "waist" then
		return CFrame.Angles(0, 0, rad(v.Y))
	end
	return CFrame.new()
end

local active = {} -- [character] = { frames, t0, joints, r6 }

local function jointsOf(char)
	local r6 = char:FindFirstChild("UpperTorso") == nil
	local out = {}
	for key, path in pairs(JOINTS[r6 and "R6" or "R15"]) do
		local part = char:FindFirstChild(path[1])
		local j = part and part:FindFirstChild(path[2])
		if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
			out[key] = j
		end
	end
	return out, r6
end

function AbilityMotion.play(userId, abilityId)
	local frames = ABILITY_ANIM[abilityId]
	local p = Players:GetPlayerByUserId(userId or 0)
	local char = p and p.Character
	if not frames or not char then
		return
	end
	local joints, r6 = jointsOf(char)
	if next(joints) == nil then
		return
	end
	active[char] = { frames = frames, t0 = os.clock(), joints = joints, r6 = r6 }
	char.Destroying:Connect(function()
		active[char] = nil
	end)
end

-- pose at time t: interpolate from the previous keyframe to the current one
local function poseAt(frames, t)
	local prev = {}
	local acc = 0
	for _, f in ipairs(frames) do
		local dur, pose = f[1], f[2]
		if t <= acc + dur then
			local a = math.clamp((t - acc) / dur, 0, 1)
			a = 1 - (1 - a) * (1 - a) -- ease out
			local out = {}
			for _, key in ipairs({ "rs", "ls", "re", "waist" }) do
				local from = prev[key] or Vector3.zero
				local to = pose[key] or Vector3.zero
				out[key] = from:Lerp(to, a)
			end
			return out
		end
		acc += dur
		prev = pose
	end
	return nil
end

function AbilityMotion.init()
	RunService.Stepped:Connect(function()
		for char, a in pairs(active) do
			local pose = poseAt(a.frames, os.clock() - a.t0)
			if not pose or not char.Parent then
				active[char] = nil
			else
				for key, j in pairs(a.joints) do
					local v = pose[key]
					if v and v.Magnitude > 0.01 then
						pcall(function()
							j.Transform = j.Transform * toCF(key, v, a.r6)
						end)
					end
				end
			end
		end
	end)
end

return AbilityMotion
