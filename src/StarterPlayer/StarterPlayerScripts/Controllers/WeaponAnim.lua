-- Procedural weapon animations (no animation assets needed). Every client animates every
-- character locally through the R15 Motor6D joints (C0), so all players see the swings.
--   * idle hold pose while a weapon is equipped
--   * attack animations by weapon style: fast thrust, heavy overhead slam, wide slash,
--     ranged aim + recoil, magic cast
--   * ability cast animations (spin, both arms up, dash lunge, ground slam...)
--   * swing trail in the weapon colour, glow/sparkles for Epic and rarer weapons
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = Shared.Data
local Weapons = require(Data.Weapons)
local Rarities = require(Data.Rarities)

local WeaponAnim = {}

local rad = math.rad
local function ang(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end

local IDLE = ang(35, 0, 8) -- weapon arm slightly raised and forward

local function motors(char)
	local function m(part, name)
		local p = char:FindFirstChild(part)
		return p and p:FindFirstChild(name)
	end
	return {
		rs = m("RightUpperArm", "RightShoulder"),
		ls = m("LeftUpperArm", "LeftShoulder"),
		re = m("RightLowerArm", "RightElbow"),
		waist = m("UpperTorso", "Waist"),
	}
end

local function base(motor)
	if not motor then
		return nil
	end
	local b = motor:GetAttribute("BaseC0")
	if not b then
		b = motor.C0
		motor:SetAttribute("BaseC0", b)
	end
	return b
end

-- play keyframes: list of { time, { rs = CFrame, ls = ..., re = ..., waist = ... } }
local function play(char, frames)
	local mo = motors(char)
	if not mo.rs or char:GetAttribute("Animating") then
		return
	end
	char:SetAttribute("Animating", true)
	task.spawn(function()
		for _, f in ipairs(frames) do
			local dur, pose = f[1], f[2]
			for key, motor in pairs(mo) do
				local b = base(motor)
				if b then
					local target = pose[key] or (key == "rs" and IDLE or CFrame.new())
					TweenService:Create(motor, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = b * target }):Play()
				end
			end
			task.wait(dur)
		end
		char:SetAttribute("Animating", nil)
	end)
end

-- ===================== TRAIL & AURA =====================
local function weaponModel(char)
	return char and char:FindFirstChild("EquippedWeapon")
end

local function colorOf(def)
	return Color3.fromRGB(def.color[1], def.color[2], def.color[3])
end

local function ensureTrail(model, def)
	local trail = model:FindFirstChild("SwingTrail", true)
	if trail then
		return trail
	end
	local handle = model:FindFirstChild("Handle")
	if not handle then
		return nil
	end
	-- the tip = the part farthest from the handle
	local tip, best = handle, 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local d = (p.Position - handle.Position).Magnitude
			if d > best then
				tip, best = p, d
			end
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Parent = tip
	trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.22
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(colorOf(def), Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	trail.Parent = handle
	return trail
end

local function flashTrail(char, def, dur)
	local model = weaponModel(char)
	if not model or not def then
		return
	end
	local trail = ensureTrail(model, def)
	if trail then
		trail.Enabled = true
		task.delay(dur or 0.3, function()
			if trail.Parent then
				trail.Enabled = false
			end
		end)
	end
end

local function ensureAura(model, def)
	if model:GetAttribute("Aura") then
		return
	end
	model:SetAttribute("Aura", true)
	local rank = Rarities.rank(def.rarity)
	if def.starter or rank < 4 then
		return
	end
	local handle = model:FindFirstChild("Handle")
	if not handle then
		return
	end
	local c = Rarities.Info[def.rarity].color
	local color = Color3.fromRGB(c[1], c[2], c[3])
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 6 + rank
	light.Brightness = 0.6 + (rank - 4) * 0.3
	light.Parent = handle
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "RarityAura"
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.25, 0)
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Rate = 6 + (rank - 4) * 6
	pe.Speed = NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = handle
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

local function charOf(userId)
	local p = Players:GetPlayerByUserId(userId or 0)
	return p and p.Character
end

function WeaponAnim.attack(userId, weaponId)
	local char = charOf(userId)
	local def = Weapons.ById[weaponId or ""]
	if not char or not def or char:GetAttribute("CarryingFrom") then
		return
	end
	-- every weapon swings: melee by its style, ranged/magic with a big overhand wave
	local frames = ATTACKS[STYLE_ANIM[def.style] or "slash"]
	if def.kind == "ranged" and def.style ~= "magic" then
		frames = ATTACKS.ranged
	end
	play(char, frames)
	flashTrail(char, def, 0.4)
end

function WeaponAnim.ability(userId, abilityId)
	local char = charOf(userId)
	if not char or char:GetAttribute("CarryingFrom") then
		return
	end
	local frames = ABILITY_ANIM[abilityId]
	if not frames then
		return
	end
	char:SetAttribute("Animating", nil) -- abilities interrupt a running swing
	play(char, frames)
	local model = weaponModel(char)
	local id = model and model:GetAttribute("WeaponId")
	if id then
		flashTrail(char, Weapons.ById[id], 0.6)
	end
end

-- a simple "eat" motion: hand to mouth twice
function WeaponAnim.eat(userId)
	local char = charOf(userId)
	if not char then
		return
	end
	play(char, {
		{ 0.15, { rs = ang(140, 0, -35), re = ang(-90, 0, 0) } },
		{ 0.15, { rs = ang(120, 0, -30), re = ang(-70, 0, 0) } },
		{ 0.15, { rs = ang(140, 0, -35), re = ang(-90, 0, 0) } },
		{ 0.2, {} },
	})
end

-- keep the idle hold pose on everyone who holds a weapon (and drop it when they don't)
local function idleLoop()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			local mo = motors(char)
			local model = weaponModel(char)
			local holding = model ~= nil and not char:GetAttribute("CarryingFrom")
			if mo.rs and not char:GetAttribute("Animating") then
				if holding then
					local b = base(mo.rs)
					mo.rs.C0 = b * IDLE
					local id = model:GetAttribute("WeaponId")
					local def = id and Weapons.ById[id]
					if def then
						ensureAura(model, def)
					end
				elseif mo.rs:GetAttribute("BaseC0") and not char:GetAttribute("CarryingFrom") then
					mo.rs.C0 = mo.rs:GetAttribute("BaseC0")
				end
			end
		end
	end
end

function WeaponAnim.init()
	task.spawn(function()
		while true do
			task.wait(0.3)
			pcall(idleLoop)
		end
	end)
end

return WeaponAnim
