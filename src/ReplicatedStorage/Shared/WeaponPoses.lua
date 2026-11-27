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

local baseC0 = setmetatable({}, { __mode = "k" }) -- [Motor6D] = original C0 (plain table: no attributes needed)
local animating = setmetatable({}, { __mode = "k" }) -- [character] = true

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

-- ===================== ABILITIES =====================
local SPIN = {
	{ 0.12, { rs = ang(90, 0, 80), ls = ang(80, 0, -80), waist = ang(0, 120, 0) } },
	{ 0.12, { rs = ang(90, 0, 80), ls = ang(80, 0, -80), waist = ang(0, 240, 0) } },
	{ 0.12, { rs = ang(90, 0, 80), ls = ang(80, 0, -80), waist = ang(0, 359, 0) } },
	{ 0.15, {} },
}
local BOTH_UP = {
	{ 0.18, { rs = ang(170, 0, 15), ls = ang(170, 0, -15), waist = ang(-12, 0, 0) } },
	{ 0.25, { rs = ang(175, 0, 20), ls = ang(175, 0, -20), waist = ang(-15, 0, 0) } },
	{ 0.15, { rs = ang(100, 0, 0), ls = ang(30, 0, 0) } },
	{ 0.18, {} },
}
local SLAM = {
	{ 0.2, { rs = ang(170, 0, 10), ls = ang(170, 0, -10), waist = ang(-15, 0, 0) } },
	{ 0.1, { rs = ang(40, 0, 0), ls = ang(40, 0, 0), waist = ang(25, 0, 0) } },
	{ 0.25, {} },
}
local LUNGE = {
	{ 0.08, { rs = ang(40, 0, 0), re = ang(-60, 0, 0), waist = ang(0, 20, 0) } },
	{ 0.12, { rs = ang(100, 0, -10), re = ang(0, 0, 0), ls = ang(-30, 0, 0), waist = ang(10, -20, 0) } },
	{ 0.18, {} },
}
local THROW = {
	{ 0.14, { rs = ang(150, 0, 30), re = ang(-50, 0, 0), waist = ang(0, 30, 0) } },
	{ 0.1, { rs = ang(70, 0, -15), re = ang(0, 0, 0), waist = ang(0, -25, 0) } },
	{ 0.16, {} },
}
local GUARD = {
	{ 0.12, { rs = ang(90, 0, -40), ls = ang(90, 0, 40), re = ang(-60, 0, 0), waist = ang(5, 0, 0) } },
	{ 1.2, { rs = ang(90, 0, -40), ls = ang(90, 0, 40), re = ang(-60, 0, 0), waist = ang(5, 0, 0) } },
	{ 0.2, {} },
}
local BREATH = {
	{ 0.15, { rs = ang(90, 0, -10), ls = ang(90, 0, 10), waist = ang(-5, 0, 0) } },
	{ 1.7, { rs = ang(95, 0, -10), ls = ang(95, 0, 10), waist = ang(-5, 0, 0) } },
	{ 0.2, {} },
}

local ABILITY_ANIM = {
	home_run = ATTACKS.heavy,
	guard = GUARD,
	spin = SPIN,
	coconut_bomb = THROW,
	charge = LUNGE,
	bubble_trap = ATTACKS.magic,
	flame_wave = ATTACKS.slash,
	ice_field = SLAM,
	hook_pull = THROW,
	static_shock = BOTH_UP,
	tidal_wave = SLAM,
	reflect = GUARD,
	bee_swarm = BOTH_UP,
	updraft = BOTH_UP,
	meteor = BOTH_UP,
	shadow_step = LUNGE,
	thorn_traps = SLAM,
	plasma_beam = ATTACKS.ranged,
	storm_aura = SPIN,
	fire_rain = BOTH_UP,
	summon_golem = SLAM,
	rewind = BOTH_UP,
	black_hole = BOTH_UP,
	mirage = LUNGE,
	dragon_breath = BREATH,
	guardian_dome = BOTH_UP,
	starfall = BOTH_UP,
	soul_chains = THROW,
	blink_barrage = LUNGE,
	midas_shockwave = SLAM,
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
