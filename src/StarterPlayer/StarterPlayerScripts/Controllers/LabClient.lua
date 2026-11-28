-- Laboratory client: lab window (pods, collection, chests, dishes, weapons, defence, bestiary),
-- chest-opening and weapon-reveal animations, lab alarm/timer HUD, theft alerts,
-- creature idle animations in the labs and hiding steal prompts from the owner team.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = Shared.Data
local Creatures = require(Data.Creatures)
local Weapons = require(Data.Weapons)
local Rarities = require(Data.Rarities)
local Chests = require(Data.Chests)
local LabData = require(Data.Lab)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local LabClient = {}
local player = Players.LocalPlayer
local Effects -- set in init

local function money(n)
	return Util.formatMoney(n)
end

local function rc(r)
	local c = Rarities.Info[r].color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function rhex(r)
	local c = Rarities.Info[r].color
	return string.format("#%02X%02X%02X", c[1], c[2], c[3])
end

local function rname(r)
	return "<font color='" .. rhex(r) .. "'>" .. Rarities.Info[r].name .. "</font>"
end

local function section(parent, text)
	return UI.label(parent, text, 18, { font = UI.Font, color = T.accent })
end

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d", sec // 60, sec % 60)
end

-- ===================== VIEWPORT (3D preview of a model) =====================
local function viewport(parent, modelSrc, size, spin)
	local vp = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = size or UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 250, 240),
		Parent = parent,
	})
	if not modelSrc then
		return vp
	end
	pcall(function()
		local model = modelSrc:Clone()
		model.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 40
		cam.Parent = vp
		vp.CurrentCamera = cam
		local cf, ext = model:GetBoundingBox()
		local dist = math.max(ext.X, ext.Y, ext.Z) * 1.9 + 2
		local center = cf.Position
		local angle = 0
		local function place()
			local offset = Vector3.new(math.sin(angle) * dist, ext.Y * 0.25, -math.cos(angle) * dist)
			cam.CFrame = CFrame.lookAt(center + offset, center)
		end
		place()
		if spin then
			local conn
			conn = RunService.RenderStepped:Connect(function(dt)
				if not vp.Parent then
					conn:Disconnect()
					return
				end
				angle += dt * 0.9
				place()
			end)
		end
	end)
	return vp
end

local function assetModel(folder, id)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local f = assets and assets:FindFirstChild(folder)
	return f and f:FindFirstChild(id)
end

-- ===================== REVEAL OVERLAY (chest / weapon) =====================
local overlay
local function closeOverlay()
	if overlay then
		overlay:Destroy()
		overlay = nil
	end
end

local function revealFrame(rarity)
	closeOverlay()
	local gui = UI.screen()
	overlay = UI.new("Frame", {
		Name = "RevealOverlay",
		BackgroundColor3 = Color3.fromRGB(5, 6, 14),
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
		Active = true,
		Parent = gui,
	})
	local glow = UI.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(520, 520),
		BackgroundColor3 = rc(rarity or "Common"),
		BackgroundTransparency = 1,
		ZIndex = 60,
		Parent = overlay,
	})
	UI.corner(glow, 260)
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = glow
	return overlay, glow
end

local function flash(color)
	if not overlay then
		return
	end
	local f = UI.new("Frame", { BackgroundColor3 = color or Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 70, Parent = overlay })
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	task.delay(0.7, function()
		f:Destroy()
	end)
end

local function rarityFanfare(rarity, glow)
	local rank = Rarities.rank(rarity)
	UI.sound(Config.Sounds.RareDrop, 0.5, 0.8 + rank * 0.12)
	if glow then
		glow.BackgroundTransparency = 0.1
		TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(560 + rank * 40, 560 + rank * 40) }):Play()
	end
	if rank >= 5 then
		-- Legendary / Mythical / Secret: rotating rays, confetti and a big banner
		flash(rc(rarity))
		if Effects then
			Effects.confetti()
			Effects.banner("🌟 " .. Rarities.Info[rarity].name .. "! 🌟", rc(rarity), 4)
		end
		for k = 1, 8 do
			local ray = UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromOffset(14, 900),
				BackgroundColor3 = rc(rarity),
				BackgroundTransparency = 0.55,
				Rotation = k * 22.5,
				ZIndex = 60,
				Parent = overlay,
			})
			TweenService:Create(ray, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = k * 22.5 + 360 }):Play()
		end
		for _ = 1, rank - 3 do
			task.delay(0.35, function()
				UI.sound(Config.Sounds.RareDrop, 0.4, 1.6)
			end)
		end
	end
end

local function showCreatureReveal(res)
	local def = Creatures.ById[res.id]
	if not def then
		return
	end
	local ov, glow = revealFrame(def.rarity)
	local chestDef = Chests.ById[res.chest] or Chests.List[1]
	local title = UI.label(ov, chestDef.icon .. " " .. chestDef.name, 26, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 40) })
	title.Position = UDim2.fromScale(0, 0.08)
	title.ZIndex = 62
	-- 1-3: chest appears and shakes
	local holder = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(320, 320), ZIndex = 62, Parent = ov })
	local chestVp = viewport(holder, assetModel("Chests", chestDef.id), UDim2.fromScale(1, 1), false)
	chestVp.ZIndex = 62
	UI.sound(Config.Sounds.ChestOpen, 0.5, 0.9)
	local rank = Rarities.rank(def.rarity)
	local shakes = 8 + rank * 2
	for k = 1, shakes do
		if not overlay then
			return
		end
		holder.Rotation = (k % 2 == 0 and 1 or -1) * (3 + k * 0.6)
		holder.Size = UDim2.fromOffset(320 + k * 6, 320 + k * 6)
		task.wait(0.07)
	end
	holder.Rotation = 0
	-- 4: light burst
	flash(Color3.new(1, 1, 1))
	chestVp:Destroy()
	-- 5-6: the creature with name, rarity and stats
	local vp = viewport(holder, assetModel("Creatures", def.id), UDim2.fromScale(1, 1), true)
	vp.ZIndex = 63
	rarityFanfare(def.rarity, glow)
	local st = Creatures.stats(def)
	local info = UI.label(ov, string.format(
		"<b>%s</b>\n%s\n💰 %d/мин • рост %s • %s %s\n✨ %s\n🔒 ур. %d: %s",
		def.name,
		rname(def.rarity),
		Creatures.income(def, 1),
		Util.formatTime(st.grow),
		def.dish.icon,
		def.dish.name,
		Creatures.describeAbility(def.ability, 1),
		Creatures.SecondAbilityLevel,
		Creatures.describeAbility(def.ability2, Creatures.SecondAbilityLevel)
	), 18, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(0.8, 0, 0, 150) })
	info.Position = UDim2.fromScale(0.1, 0.66)
	info.ZIndex = 63
	-- 7: added to the collection (server already did it) -> quick actions
	local row = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromOffset(520, 50), ZIndex = 63, Parent = ov })
	UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local b1 = UI.button(row, "🧪 Поставить в капсулу", T.good, function()
		UI.request(Net, "PlaceCreature", { uid = res.uid }, "Существо в капсуле — оно начало расти!")
		closeOverlay()
	end, { size = UDim2.fromOffset(250, 46) })
	b1.ZIndex = 64
	local b2 = UI.button(row, "Отлично!", T.card, closeOverlay, { size = UDim2.fromOffset(170, 46) })
	b2.ZIndex = 64
end

local function showWeaponReveal(res)
	local def = Weapons.ById[res.id]
	if not def then
		return
	end
	local dish = Creatures.DishById[res.dish]
	local ov, glow = revealFrame(def.rarity)
	-- 1-2: eating
	local icon = UI.label(ov, dish and dish.icon or "🍽️", 120, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromOffset(240, 240) })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.42)
	icon.ZIndex = 62
	local cap = UI.label(ov, "😋 Ням-ням... " .. (dish and dish.name or ""), 24, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 40) })
	cap.Position = UDim2.fromScale(0, 0.1)
	cap.ZIndex = 62
	for k = 1, 3 do
		UI.sound(Config.Sounds.Eat, 0.4, 0.8 + k * 0.15)
		TweenService:Create(icon, TweenInfo.new(0.25), { TextSize = 120 - k * 30 }):Play()
		task.wait(0.35)
		if not overlay then
			return
		end
	end
	icon:Destroy()
	-- 3-5: reward effect and the weapon chosen by the server
	flash(rc(def.rarity))
	cap.Text = "🎁 Блюдо подарило оружие!"
	local holder = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(320, 320), ZIndex = 62, Parent = ov })
	local vp = viewport(holder, assetModel("Weapons", def.id), UDim2.fromScale(1, 1), true)
	vp.ZIndex = 63
	UI.sound(Config.Sounds.WeaponGet, 0.6, 1)
	rarityFanfare(def.rarity, glow)
	-- 6: name, icon, rarity, ability
	local info = UI.label(ov, string.format(
		"%s <b>%s</b>\n%s • %s\n⚔️ урон %d • скорость %.2f с • дальность %d\n✨ <b>%s</b> (%d с): %s",
		def.icon,
		def.name,
		rname(def.rarity),
		Weapons.Styles[def.style],
		def.damage,
		def.cooldown,
		def.range,
		def.ability.name,
		def.ability.cooldown,
		def.ability.desc
	), 18, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(0.8, 0, 0, 150) })
	info.Position = UDim2.fromScale(0.1, 0.66)
	info.ZIndex = 63
	-- 7: added to the inventory (server) -> equip
	local row = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromOffset(520, 50), ZIndex = 63, Parent = ov })
	UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local b1 = UI.button(row, "🗡️ Взять в руки", T.good, function()
		UI.request(Net, "EquipWeapon", { uid = res.uid })
		closeOverlay()
	end, { size = UDim2.fromOffset(220, 46) })
	b1.ZIndex = 64
	local b2 = UI.button(row, "В инвентарь", T.card, closeOverlay, { size = UDim2.fromOffset(170, 46) })
	b2.ZIndex = 64
end

LabClient.showCreatureReveal = showCreatureReveal
LabClient.showWeaponReveal = showWeaponReveal

-- ===================== LAB WINDOW =====================
local function creatureCard(c, rec, inPod)
	local def = Creatures.ById[rec.id]
	if not def then
		return
	end
	local st = Creatures.stats(def)
	local progress = math.min(1, rec.grow / st.grow)
	local _, stage = Creatures.stageOf(progress)
	local card = UI.card(c, 150)
	local swatch = UI.new("Frame", { BackgroundColor3 = rc(def.rarity), BackgroundTransparency = 0.6, Size = UDim2.fromOffset(110, 110), Position = UDim2.fromOffset(10, 20), Parent = card })
	UI.corner(swatch, 14)
	viewport(swatch, assetModel("Creatures", def.id), UDim2.fromScale(1, 1), false)
	local abilities = Creatures.describeAbility(def.ability, rec.lvl)
	if rec.lvl >= Creatures.SecondAbilityLevel then
		abilities ..= "\n" .. Creatures.describeAbility(def.ability2, rec.lvl)
	else
		abilities ..= "\n<font color='#7F89A8'>🔒 ур. " .. Creatures.SecondAbilityLevel .. ": " .. Creatures.Abilities[def.ability2.kind].name .. "</font>"
	end
	local text = string.format("<b>%s</b>  %s  • Ур. %d/%d • %s%s\n%s\n%s",
		def.name, rname(def.rarity), rec.lvl, Creatures.MaxLevel, stage.name,
		rec.carried and "  <font color='#FF5555'><b>🚨 УКРАДЕНО!</b></font>" or "",
		progress < 1 and string.format("🌱 Рост: %d%% (ещё %s)", math.floor(progress * 100), Util.formatTime(st.grow - rec.grow))
			or string.format("💰 %d/мин • %s %s: %d%%", Creatures.income(def, rec.lvl), def.dish.icon, def.dish.name, math.floor(math.min(1, rec.dish / st.dishTime) * 100)),
		abilities)
	UI.label(card, text, 13, { sizeUDim = UDim2.new(1, -330, 1, -10), valign = Enum.TextYAlignment.Top }).Position = UDim2.fromOffset(132, 6)
	UI.progress(card, progress < 1 and progress or math.min(1, rec.dish / st.dishTime), progress < 1 and T.good or T.warn, { size = UDim2.new(1, -330, 0, 8), position = UDim2.new(0, 132, 1, -14) })
	local col = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(180, 140), Position = UDim2.new(1, -190, 0, 5), Parent = card })
	UI.list(col, Enum.FillDirection.Vertical, 6)
	if rec.lvl < Creatures.MaxLevel then
		UI.button(col, "⬆️ Улучшить " .. money(Creatures.upgradeCost(def, rec.lvl)), T.blue, function()
			UI.request(Net, "UpgradeCreature", { uid = rec.uid })
		end, { size = UDim2.fromOffset(180, 36) })
	end
	if progress < 1 then
		UI.button(col, "⚡ Вырастить " .. money(math.ceil((st.grow - rec.grow) * st.speedupRate)), T.purple, function()
			UI.request(Net, "SpeedUpCreature", { uid = rec.uid })
		end, { size = UDim2.fromOffset(180, 36) })
	end
	if inPod then
		UI.button(col, "📦 В коллекцию", T.card, function()
			UI.request(Net, "StoreCreature", { uid = rec.uid })
		end, { size = UDim2.fromOffset(180, 36), disabled = rec.carried })
	else
		UI.button(col, "🧪 В капсулу", T.good, function()
			UI.request(Net, "PlaceCreature", { uid = rec.uid }, "Существо в капсуле!")
		end, { size = UDim2.fromOffset(180, 36) })
		UI.button(col, "👋 Отпустить", T.bad, function()
			UI.request(Net, "ReleaseCreature", { uid = rec.uid }, "Существо отпущено")
		end, { size = UDim2.fromOffset(180, 30) })
	end
end

local function noLab(c, lab)
	if lab and lab.locked then
		UI.label(c, "🔒 Лаборатория появится на вашем острове, когда ресторан получит " .. (lab.unlockStars or 3) .. "★. Развивайте ресторан: «Улучшения → Рейтинг ★».", 15, { auto = true, color = T.warn })
		return true
	end
	if not lab or lab.island == 0 then
		UI.label(c, "🧪 Лаборатория есть у каждого ресторана. Откройте ресторан на свободном острове или вступите в команду друга.", 15, { auto = true, color = T.sub })
		return true
	end
	return false
end

local function renderPods(c)
	local lab = State.lab
	if noLab(c, lab) then
		return
	end
	local used = 0
	for _ in pairs(lab.podList or {}) do
		used += 1
	end
	local cy = lab.cycle or {}
	local status = cy.state == "closed" and ("🛡️ Защищена • откроется через " .. fmtTime(cy.remaining or 0))
		or (cy.state == "open" and ("🚨 ОТКРЫТА! До закрытия: " .. fmtTime(cy.remaining or 0)) or "☠️ ОПАСНОСТЬ! Всё ещё открыта — бегите к плите!")
	UI.label(c, string.format("🧪 Лаборатория ур. <b>%d</b> • капсул: %d/%d • %s", lab.level or 1, used, lab.pods or 4, status), 15, { auto = true })
	local row = UI.row(c, 46)
	UI.button(row, "💰 Забрать доход " .. money(lab.bank or 0), T.gold, function()
		UI.request(Net, "CollectLab", {})
	end, { size = UDim2.fromOffset(250, 42), textColor = Color3.fromRGB(40, 30, 10), disabled = (lab.bank or 0) <= 0 })
	if lab.isOwner and (lab.level or 1) < #LabData.Levels then
		local nxt = LabData.Levels[(lab.level or 1) + 1]
		local locked = (lab.maxLevel or 1) < (lab.level or 1) + 1
		UI.button(row, locked and ("🔒 Ур. " .. (lab.level + 1) .. " — нужен ресторан " .. (lab.level + 1) .. "★") or ("⬆️ Лаборатория ур. " .. (lab.level + 1) .. " • " .. money(nxt.price) .. " из бюджета"), locked and T.card or T.blue, function()
			UI.request(Net, "UpgradeLab", {}, "Лаборатория улучшена!")
		end, { size = UDim2.fromOffset(360, 42), disabled = locked })
	end
	if lab.bonuses and next(lab.bonuses) then
		local parts = {}
		for kind, v in pairs(lab.bonuses) do
			table.insert(parts, Creatures.Abilities[kind].name .. " " .. (Creatures.Abilities[kind].unit == "%" and ("+" .. v .. "%") or ("+" .. v)))
		end
		table.sort(parts)
		UI.label(c, "✨ Бонусы ресторану: " .. table.concat(parts, " • "), 13, { auto = true, color = T.good })
	end
	section(c, "Капсулы")
	local byUid = {}
	for _, rec in ipairs(lab.collection or {}) do
		byUid[rec.uid] = rec
	end
	for i = 1, lab.pods or 4 do
		local pod = lab.podList and lab.podList[tostring(i)]
		if pod and pod.mine and byUid[pod.uid] then
			creatureCard(c, byUid[pod.uid], true)
		elseif pod then
			local def = Creatures.ById[pod.id]
			UI.label(c, string.format("Капсула %d: %s (%s) — существо игрока %s%s", i, def and def.name or "?", def and rname(def.rarity) or "", pod.owner, pod.carried and " • 🚨 украдено!" or ""), 14, { auto = true, color = T.sub })
		else
			UI.label(c, "Капсула " .. i .. ": <font color='#7F89A8'>пусто — поставьте существо из коллекции</font>", 14, { color = T.sub })
		end
	end
end

local function renderCollection(c)
	local lab = State.lab
	if noLab(c, lab) then
		return
	end
	local list = {}
	for _, rec in ipairs(lab.collection or {}) do
		if rec.pod == 0 then
			table.insert(list, rec)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Rarities.rank(Creatures.ById[a.id].rarity), Rarities.rank(Creatures.ById[b.id].rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.lvl > b.lvl
	end)
	UI.label(c, string.format("📦 Коллекция: %d/%d существ. Существа в коллекции в безопасности, но не растут и не приносят доход. В капсулах они работают, но их можно украсть, пока лаборатория открыта.", #(lab.collection or {}), lab.maxCollection or 60), 14, { auto = true, color = T.sub })
	if #list == 0 then
		UI.label(c, "Пусто. Купите сундук во вкладке «Сундуки».", 15, { color = T.sub })
	end
	for _, rec in ipairs(list) do
		creatureCard(c, rec, false)
	end
end

local buying = false
local function renderChests(c)
	local lab = State.lab
	if noLab(c, lab) then
		return
	end
	UI.label(c, string.format("Один сундук = одно случайное существо. Шансы зависят от сундука, уровня лаборатории и существ-удачников (сейчас удача +%s%%). Деньги — с личного баланса (%s).", tostring(lab.luck or 0), money(State.player and State.player.money or 0)), 14, { auto = true, color = T.sub })
	for _, ch in ipairs(lab.chests or {}) do
		local def = Chests.ById[ch.id]
		local card = UI.card(c, 150)
		local box = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(120, 120), Position = UDim2.fromOffset(10, 15), Parent = card })
		viewport(box, assetModel("Chests", def.id), UDim2.fromScale(1, 1), false)
		local odds = {}
		for _, r in ipairs(Rarities.Order) do
			local v = ch.odds[r] or 0
			if v > 0 then
				table.insert(odds, string.format("%s %s%%", rname(r), v >= 1 and string.format("%.1f", v) or string.format("%.2f", v)))
			end
		end
		UI.label(card, string.format("<b>%s %s</b> — %s\n%s", def.icon, def.name, money(def.price), table.concat(odds, " • ")), 14, { sizeUDim = UDim2.new(1, -350, 1, -10), valign = Enum.TextYAlignment.Top }).Position = UDim2.fromOffset(140, 6)
		local b = UI.button(card, ch.locked and ("🔒 Нужен ресторан " .. def.stars .. "★") or ("Купить " .. money(def.price)), ch.locked and T.card or T.gold, function()
			if buying then
				return
			end
			buying = true -- one click = one request (the server also protects against duplicates)
			local res = Net.request("BuyChest", { chest = def.id })
			buying = false
			if res and res.ok then
				task.spawn(showCreatureReveal, res)
			else
				UI.toast(res and res.err or "Ошибка", "error")
			end
		end, { size = UDim2.fromOffset(190, 44), disabled = ch.locked, textColor = not ch.locked and Color3.fromRGB(40, 30, 10) or nil })
		b.Position = UDim2.new(1, -200, 0.5, -22)
	end
end

local eating = false
local function renderDishes(c)
	local lab = State.lab
	-- the lab state is pushed the moment a dish is cooked: it is the source of truth
	local dishes = (lab and lab.dishes) or (State.combat and State.combat.dishes) or {}
	UI.label(c, "🍽️ Взрослые существа в капсулах готовят особые блюда. Съешьте блюдо — и получите случайное оружие <b>той же редкости</b>, что и существо.", 14, { auto = true, color = T.sub })
	-- creator / Studio tools (the server checks it again)
	local RunService = game:GetService("RunService")
	if RunService:IsStudio() or player.UserId == game.CreatorId then
		UI.label(c, "🛠️ Для создателя: выдать блюда моментально (обычные игроки этого не видят)", 14, { font = UI.Font, color = T.warn })
		local row = UI.row(c, 40)
		UI.button(row, "🎁 Все 7 редкостей", T.warn, function()
			UI.request(Net, "DevGiveDishes", { rarity = "all" }, "Выдано 7 блюд — по одному каждой редкости")
		end, { size = UDim2.fromOffset(190, 36), textColor = Color3.fromRGB(40, 30, 10) })
		local row2 = UI.row(c, 40)
		for _, r in ipairs(Rarities.Order) do
			local b = UI.button(row2, Rarities.Info[r].name, rc(r), function()
				UI.request(Net, "DevGiveDishes", { rarity = r }, "Блюдо выдано: " .. Rarities.Info[r].name)
			end, { size = UDim2.fromOffset(104, 34), textSize = 12 })
			b.TextColor3 = Color3.fromRGB(20, 20, 30)
		end
	end
	local any = false
	for _, def in ipairs(Creatures.List) do
		local n = dishes[def.dish.id] or 0
		if n > 0 then
			any = true
			local card = UI.card(c, 70)
			UI.label(card, def.dish.icon, 38, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromOffset(60, 60) }).Position = UDim2.fromOffset(6, 5)
			UI.label(card, string.format("<b>%s</b> ×%d  %s\nот существа «%s» → %s оружие", def.dish.name, n, rname(def.rarity), def.name, rname(def.rarity)), 14, { sizeUDim = UDim2.new(1, -280, 1, 0) }).Position = UDim2.fromOffset(72, 0)
			local b = UI.button(card, "😋 Съесть", T.good, function()
				if eating then
					return
				end
				eating = true
				local res = Net.request("EatDish", { dish = def.dish.id })
				if res and res.ok then
					showWeaponReveal(res)
				else
					UI.toast(res and res.err or "Ошибка", "error")
				end
				eating = false
			end, { size = UDim2.fromOffset(180, 42) })
			b.Position = UDim2.new(1, -190, 0.5, -21)
		end
	end
	if not any then
		UI.label(c, "Блюд пока нет. Вырастите существо и подождите — блюдо появится автоматически.", 15, { color = T.sub })
	end
end

local function renderWeapons(c)
	local cs = State.combat
	if not cs then
		UI.label(c, "Загрузка...", 15)
		return
	end
	UI.label(c, string.format("🗡️ Оружие: %d/%d. Бесплатные бита и меч — на стенде у моста на каждом острове. ПК: ЛКМ — удар, F — способность. Телефон: кнопки справа.", #cs.weapons, cs.max or 40), 14, { auto = true, color = T.sub })
	local list = table.clone(cs.weapons)
	table.sort(list, function(a, b)
		local wa, wb = Weapons.ById[a.id], Weapons.ById[b.id]
		local ra, rb = Rarities.rank(wa.rarity) + (wa.starter and -1 or 0), Rarities.rank(wb.rarity) + (wb.starter and -1 or 0)
		if ra ~= rb then
			return ra > rb
		end
		return a.uid < b.uid
	end)
	if cs.equipped ~= "" then
		UI.button(c, "✋ Убрать оружие из рук", T.card, function()
			UI.request(Net, "EquipWeapon", { uid = "" })
		end, { size = UDim2.fromOffset(240, 36) })
	end
	for _, w in ipairs(list) do
		local def = Weapons.ById[w.id]
		if def then
			local card = UI.card(c, 96)
			local box = UI.new("Frame", { BackgroundColor3 = rc(def.rarity), BackgroundTransparency = 0.7, Size = UDim2.fromOffset(80, 80), Position = UDim2.fromOffset(8, 8), Parent = card })
			UI.corner(box, 12)
			viewport(box, assetModel("Weapons", def.id), UDim2.fromScale(1, 1), false)
			UI.label(card, string.format("%s <b>%s</b>  %s%s • %s\n⚔️ %d урона • %.2f с • %d м\n✨ <b>%s</b> (%d с): %s",
				def.icon, def.name, def.starter and "<font color='#A5AFD2'>Бесплатное</font>" or rname(def.rarity), "", Weapons.Styles[def.style],
				def.damage, def.cooldown, def.range, def.ability.name, def.ability.cooldown, def.ability.desc), 13, { sizeUDim = UDim2.new(1, -300, 1, -6), valign = Enum.TextYAlignment.Top }).Position = UDim2.fromOffset(96, 4)
			local equipped = cs.equipped == w.uid
			local col = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(180, 86), Position = UDim2.new(1, -190, 0, 5), Parent = card })
			UI.list(col, Enum.FillDirection.Vertical, 6)
			UI.button(col, equipped and "✓ В руках" or "🗡️ Взять", equipped and T.good or T.blue, function()
				UI.request(Net, "EquipWeapon", { uid = w.uid })
			end, { size = UDim2.fromOffset(180, 38), disabled = equipped })
			UI.button(col, "♻️ Разобрать", T.bad, function()
				UI.request(Net, "ScrapWeapon", { uid = w.uid })
			end, { size = UDim2.fromOffset(180, 32) })
		end
	end
end

local function renderDefense(c)
	local lab = State.lab
	if noLab(c, lab) then
		return
	end
	local cy = lab.cycle or {}
	UI.label(c, "🚨 Каждые 2 минуты лаборатория автоматически открывается. Добегите до плиты «ЗАКРЫТЬ ЛАБОРАТОРИЮ» и наступите на неё. Если не успеть, лаборатория НЕ закроется сама: она останется открытой, пока вы не наступите на плиту.", 14, { auto = true, color = T.sub })
	UI.label(c, cy.state == "closed" and ("🛡️ Сейчас защищена. Следующее открытие через " .. fmtTime(cy.remaining or 0))
		or (cy.state == "open" and ("🚨 ОТКРЫТА! До конца таймера " .. fmtTime(cy.remaining or 0)) or "☠️ ОПАСНОСТЬ! Лаборатория всё ещё открыта!"), 17, { font = UI.Font, color = cy.state == "closed" and T.good or T.bad })
	local s = lab.stats or {}
	UI.label(c, string.format("🦹 Украдено вами: %d • 😢 Украли у вас: %d • 🛡️ Вы вернули: %d • 🚔 Вас поймали: %d", s.steals or 0, s.stolenFrom or 0, s.defends or 0, s.caught or 0), 14, { auto = true })
	if not lab.isOwner then
		UI.label(c, lab.canClose and "Владелец разрешил вам закрывать лабораторию плитой." or "Закрывать лабораторию может только владелец (или друг с разрешения).", 14, { auto = true, color = T.sub })
		return
	end
	section(c, "Доступ")
	local row = UI.row(c, 44)
	UI.button(row, lab.access == "open" and "✓ Открытый доступ" or "Открытый доступ", lab.access == "open" and T.good or T.card, function()
		UI.request(Net, "LabSettings", { access = "open" })
	end, { size = UDim2.fromOffset(220, 40) })
	UI.button(row, lab.access == "private" and "✓ Только свои" or "Только свои", lab.access == "private" and T.good or T.card, function()
		UI.request(Net, "LabSettings", { access = "private" })
	end, { size = UDim2.fromOffset(220, 40) })
	UI.label(c, "🛡️ Закрытая плитой лаборатория запечатана: посторонние не могут войти внутрь, а значит, не могут попасть и на ваш остров (вокруг него постоянный барьер, путь только через лабораторию). Когда она открывается по таймеру, войти могут все: это главная механика и её нельзя отключить.", 13, { auto = true, color = T.sub })
	UI.button(c, lab.friendClose and "✓ Друг может закрывать плитой" or "Друг не может закрывать плитой", lab.friendClose and T.good or T.card, function()
		UI.request(Net, "LabSettings", { friendClose = not lab.friendClose })
	end, { size = UDim2.fromOffset(320, 40) })
	section(c, "Доверенные игроки (входят всегда и не могут красть)")
	local trusted = {}
	for _, t in ipairs(lab.trusted or {}) do
		trusted[t.id] = true
		local r = UI.row(c, 40)
		UI.label(r, "✅ " .. t.name, 15, { sizeUDim = UDim2.fromOffset(300, 36) })
		UI.button(r, "Убрать", T.bad, function()
			UI.request(Net, "LabTrust", { userId = t.id, allow = false })
		end, { size = UDim2.fromOffset(120, 34) })
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and not trusted[p.UserId] then
			local r = UI.row(c, 40)
			UI.label(r, p.DisplayName, 15, { sizeUDim = UDim2.fromOffset(300, 36), color = T.sub })
			UI.button(r, "Доверять", T.blue, function()
				UI.request(Net, "LabTrust", { userId = p.UserId, allow = true })
			end, { size = UDim2.fromOffset(120, 34) })
		end
	end
end

local function renderBestiary(c)
	local owned = {}
	for _, rec in ipairs(State.lab and State.lab.collection or {}) do
		owned[rec.id] = true
	end
	UI.label(c, "📖 Все существа островов. Чем выше редкость, тем реже они выпадают и тем сильнее их способности.", 14, { auto = true, color = T.sub })
	for _, r in ipairs(Rarities.Order) do
		section(c, Rarities.Info[r].name)
		for _, def in ipairs(Creatures.ByRarity[r] or {}) do
			local card = UI.card(c, 74)
			local box = UI.new("Frame", { BackgroundColor3 = rc(r), BackgroundTransparency = 0.7, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(5, 5), Parent = card })
			UI.corner(box, 10)
			viewport(box, assetModel("Creatures", def.id), UDim2.fromScale(1, 1), false)
			UI.label(card, string.format("<b>%s</b>%s — %s\n%s • %s %s", def.name, owned[def.id] and "  ✅" or "", def.desc, Creatures.describeAbility(def.ability, 1), def.dish.icon, def.dish.name), 13, { sizeUDim = UDim2.new(1, -80, 1, -4) }).Position = UDim2.fromOffset(76, 2)
		end
	end
end

local function renderLab(c, win)
	local tab = win.tab
	if tab == "pods" then
		renderPods(c)
	elseif tab == "collection" then
		renderCollection(c)
	elseif tab == "chests" then
		renderChests(c)
	elseif tab == "dishes" then
		renderDishes(c)
	elseif tab == "weapons" then
		renderWeapons(c)
	elseif tab == "defense" then
		renderDefense(c)
	else
		renderBestiary(c)
	end
end

-- ===================== LAB ALARM / TIMER HUD =====================
local hud = {}
local cycleState, cycleRemaining, cycleStamp = nil, 0, 0

local function ensureHud()
	if hud.frame then
		return
	end
	local gui = UI.screen()
	hud.frame = UI.new("Frame", {
		Name = "LabTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(560, 40),
		BackgroundColor3 = T.good,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	UI.corner(hud.frame, 12)
	hud.label = UI.label(hud.frame, "", 18, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromScale(1, 1) })
	hud.label.ZIndex = 21
end

local beam
local function setWaypoint(on)
	if beam then
		beam:Destroy()
		beam = nil
	end
	if not on then
		return
	end
	local my = State.myIsland()
	local lab = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Labs") and workspace.Map.Labs:FindFirstChild("Lab" .. my)
	local plate = lab and lab:FindFirstChild("Plate")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not plate or not root then
		return
	end
	beam = Instance.new("Folder")
	beam.Name = "PlateWaypoint"
	local a0 = Instance.new("Attachment")
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 2, 0)
	a1.Parent = plate
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Color = ColorSequence.new(Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 255, 140))
	b.Width0, b.Width1 = 0.6, 1.2
	b.FaceCamera = true
	b.LightEmission = 1
	b.Parent = beam
	beam.Parent = workspace
	beam.Destroying:Connect(function()
		a0:Destroy()
		a1:Destroy()
	end)
end

local function updateHud()
	ensureHud()
	local lab = State.lab
	if not lab or lab.island == 0 or not cycleState then
		hud.frame.Visible = false
		setWaypoint(false)
		return
	end
	local left = math.max(0, cycleRemaining - (os.clock() - cycleStamp))
	hud.frame.Visible = true
	if cycleState == "closed" then
		hud.frame.BackgroundColor3 = T.good
		hud.frame.Size = UDim2.fromOffset(520, 34)
		hud.label.TextSize = 15
		hud.label.Text = "🛡️ ЛАБОРАТОРИЯ ЗАЩИЩЕНА • откроется через " .. fmtTime(left)
	elseif cycleState == "open" then
		hud.frame.BackgroundColor3 = T.bad
		hud.frame.Size = UDim2.fromOffset(620, 46)
		hud.label.TextSize = 19
		hud.label.Text = "🚨 ЛАБОРАТОРИЯ ОТКРЫТА! ДО ЗАКРЫТИЯ ОСТАЛОСЬ: " .. fmtTime(left)
	else
		local blink = math.floor(os.clock() * 2) % 2 == 0
		hud.frame.BackgroundColor3 = blink and Color3.fromRGB(150, 0, 0) or T.bad
		hud.frame.Size = UDim2.fromOffset(660, 46)
		hud.label.TextSize = 19
		hud.label.Text = "☠️ ОПАСНОСТЬ! ЛАБОРАТОРИЯ ВСЁ ЕЩЁ ОТКРЫТА! Наступите на плиту!"
	end
	local needWaypoint = cycleState ~= "closed" and (lab.canClose == true)
	if needWaypoint and not beam then
		setWaypoint(true)
	elseif not needWaypoint and beam then
		setWaypoint(false)
	end
end

local alarmPlaying = false
local function alarm(times, pitch)
	if alarmPlaying then
		return
	end
	alarmPlaying = true
	task.spawn(function()
		for _ = 1, times do
			UI.sound(Config.Sounds.LabAlarm, 0.55, pitch or 0.6)
			task.wait(0.35)
		end
		alarmPlaying = false
	end)
end

local function bigAlert(text, color, duration)
	local gui = UI.screen()
	local f = UI.new("Frame", {
		Name = "BigAlert",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(760, 90),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		ZIndex = 55,
		Parent = gui,
	})
	UI.corner(f, 16)
	UI.stroke(f, Color3.new(1, 1, 1), 3, 0.2)
	local l = UI.label(f, text, 28, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromScale(1, 1) })
	l.ZIndex = 56
	task.spawn(function()
		local t0 = os.clock()
		while f.Parent and os.clock() - t0 < (duration or 4) do
			f.Size = UDim2.fromOffset(760 + math.sin((os.clock() - t0) * 12) * 18, 90)
			task.wait(0.03)
		end
		f:Destroy()
	end)
end
LabClient.bigAlert = bigAlert

-- ===================== THIEF HIGHLIGHTS =====================
local highlights = {}
local function highlightThief(userId)
	local p = Players:GetPlayerByUserId(userId)
	local char = p and p.Character
	if not char then
		return
	end
	if highlights[userId] then
		highlights[userId]:Destroy()
	end
	local h = Instance.new("Highlight")
	h.FillColor = Color3.fromRGB(255, 40, 40)
	h.OutlineColor = Color3.fromRGB(255, 255, 255)
	h.FillTransparency = 0.4
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = char
	h.Parent = char
	highlights[userId] = h
	task.spawn(function()
		while h.Parent and char.Parent and char:GetAttribute("CarryingFrom") ~= nil do
			task.wait(0.5)
		end
		h:Destroy()
	end)
end

-- ===================== WORLD: creature idle animations =====================
local baseCF = {} -- [creature model] = resting CFrame (strong table, cleaned on Destroying)
local function animateCreatures()
	local t = os.clock()
	local cam = workspace.CurrentCamera
	local labs = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Labs")
	if not labs or not cam then
		return
	end
	for _, lab in ipairs(labs:GetChildren()) do
		if (lab:GetPivot().Position - cam.CFrame.Position).Magnitude < 260 then
			for _, m in ipairs(lab:GetChildren()) do
				if m.Name == "Creature" and m:IsA("Model") then
					-- always animate around the server's resting point (never accumulate offsets)
					local base = baseCF[m]
					if not base then
						local hp, yaw = m:GetAttribute("HomePos"), m:GetAttribute("HomeYaw")
						if typeof(hp) == "Vector3" then
							base = CFrame.new(hp) * CFrame.Angles(0, yaw or 0, 0)
						else
							base = m:GetPivot()
						end
						baseCF[m] = base
						m.Destroying:Connect(function()
							baseCF[m] = nil
						end)
					end
					local anim = m:GetAttribute("Anim")
					local phase = (m:GetAttribute("Phase") or (#m.Name + base.Position.X)) % 6.28
					local off
					if anim == "float" then
						off = CFrame.new(0, 1.2 + math.sin(t * 1.6 + phase) * 0.6, 0) * CFrame.Angles(0, math.sin(t * 0.5 + phase) * 0.4, 0)
					elseif anim == "hop" then
						off = CFrame.new(0, math.abs(math.sin(t * 3 + phase)) * 1.1, 0)
					elseif anim == "spin" then
						off = CFrame.Angles(0, t * 1.5 + phase, 0)
					elseif anim == "flap" then
						off = CFrame.new(0, 0.6 + math.sin(t * 5 + phase) * 0.25, 0) * CFrame.Angles(0, math.sin(t * 0.7) * 0.6, 0)
					elseif anim == "crawl" then
						off = CFrame.new(math.sin(t * 0.8 + phase) * 0.6, 0, 0) * CFrame.Angles(0, math.sin(t * 0.8 + phase) * 0.5, 0)
					elseif anim == "egg" then
						off = CFrame.Angles(0, 0, math.sin(t * 6 + phase) * 0.08 * (math.sin(t * 0.7 + phase) > 0.6 and 1 or 0))
					else
						off = CFrame.Angles(0, 0, math.sin(t * 2 + phase) * 0.12) * CFrame.new(0, math.abs(math.sin(t * 2 + phase)) * 0.3, 0)
					end
					m:PivotTo(base * off)
				end
			end
			-- blinking siren while open
			local siren = lab:FindFirstChild("Siren")
			local state = lab:GetAttribute("LabState")
			if siren and (state == "open" or state == "danger") then
				local on = math.floor(t * (state == "danger" and 5 or 3)) % 2 == 0
				siren.Transparency = on and 0 or 0.6
			elseif siren then
				siren.Transparency = 0
			end
		end
	end
end

-- ===================== INIT =====================
function LabClient.init(effects)
	Effects = effects
	local win = UI.window("lab", "Лаборатория", "🧪", { render = renderLab, width = 860, height = 620 })
	win:setTabs({
		{ id = "pods", text = "Капсулы", width = 110 },
		{ id = "collection", text = "Коллекция", width = 120 },
		{ id = "chests", text = "Сундуки", width = 100 },
		{ id = "dishes", text = "Блюда", width = 90 },
		{ id = "weapons", text = "Оружие", width = 100 },
		{ id = "defense", text = "Защита", width = 100 },
		{ id = "bestiary", text = "Бестиарий", width = 120 },
	})

	Net.onPush("lab", function(data)
		State.set("lab", data)
		if data.cycle then
			cycleState = data.cycle.state
			cycleRemaining = data.cycle.remaining or 0
			cycleStamp = os.clock()
		else
			cycleState = nil
		end
		if UI.isOpen("lab") then
			UI.windows.lab:refresh()
		end
	end)

	Net.remote("Fx").OnClientEvent:Connect(function(name, data)
		data = data or {}
		if name == "labAlarm" then
			if data.kind == "open" then
				cycleState, cycleRemaining, cycleStamp = "open", data.remaining or LabData.OpenWarnTime, os.clock()
				bigAlert("🚨 ВНИМАНИЕ! ЛАБОРАТОРИЯ ОТКРЫТА! ЗАКРОЙ ЕЁ!", T.bad, 4)
				alarm(6, 0.6)
			elseif data.kind == "danger" then
				cycleState = "danger"
				bigAlert("☠️ ОПАСНОСТЬ! ЛАБОРАТОРИЯ ВСЁ ЕЩЁ ОТКРЫТА!", Color3.fromRGB(150, 0, 0), 4)
				alarm(8, 0.45)
			elseif data.kind == "closed" then
				cycleState, cycleRemaining, cycleStamp = "closed", LabData.ClosedTime, os.clock()
				bigAlert("🛡️ ЛАБОРАТОРИЯ ЗАЩИЩЕНА!", T.good, 3)
				UI.sound(Config.Sounds.Buy, 0.5, 1.2)
				if Effects then
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root then
						Effects.sparkle(root.Position)
					end
				end
			end
			updateHud()
		elseif name == "theft" then
			local kind = data.kind
			if kind == "alarm" then
				bigAlert("🚨 ВНИМАНИЕ! ТВОЁ СУЩЕСТВО КРАДУТ! (" .. (data.name or "") .. ")", Color3.fromRGB(200, 0, 0), 5)
				alarm(10, 0.4)
				UI.toast("🦹 " .. (data.thief or "?") .. " уносит «" .. (data.name or "") .. "». Догоните и ударьте его оружием!", "error")
				if data.thiefId then
					highlightThief(data.thiefId)
				end
			elseif kind == "start" then
				UI.toast("🦹 Вы схватили «" .. (data.name or "") .. "»! Бегите в свою лабораторию. Если владелец ударит вас — добыча выпадет.", "warn")
				UI.sound(Config.Sounds.Theft, 0.5, 1.4)
			elseif kind == "returned" then
				bigAlert("🛡️ СУЩЕСТВО ВОЗВРАЩЕНО: " .. (data.name or ""), T.good, 3)
				UI.sound(Config.Sounds.Buy, 0.5, 1.3)
			elseif kind == "caught" then
				bigAlert("🚔 ТЕБЯ ПОЙМАЛИ! Добыча выпала", T.bad, 3)
			elseif kind == "lost" then
				UI.toast("Добыча вернулась к владельцу", "warn")
			elseif kind == "success" then
				bigAlert("🦹 КРАЖА УДАЛАСЬ! " .. (data.name or "") .. " теперь ваше", T.purple, 4)
				if Effects then
					Effects.confetti()
				end
			elseif kind == "stolen" then
				bigAlert("😢 " .. (data.thief or "Вор") .. " украл «" .. (data.name or "") .. "»", T.bad, 4)
			end
		elseif name == "dishReady" then
			local d = Creatures.DishById[data.dish]
			if d then
				UI.toast(d.icon .. " Готово особое блюдо «" .. d.name .. "»! Откройте 🧪 → Блюда", "success")
				UI.sound(Config.Sounds.Eat, 0.4, 1.4)
			end
		elseif name == "creatureLevel" then
			UI.sound(Config.Sounds.Buy, 0.5, data.grown and 1.6 or 1.3)
		elseif name == "weaponGet" then
			local def = Weapons.ById[data.id]
			if def then
				UI.toast(def.icon .. " Получено: " .. def.name .. (data.free and " (бесплатно)" or ""), "success")
				UI.sound(Config.Sounds.WeaponGet, 0.5, 1.1)
			end
		end
	end)

	-- hide "Steal" prompts from the owner team (the server checks it anyway)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt:GetAttribute("ThiefPrompt") and prompt:GetAttribute("LabIsland") == State.myIsland() then
			prompt.Enabled = false
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(updateHud)
		end
	end)
	RunService.RenderStepped:Connect(function()
		pcall(animateCreatures)
	end)
	task.spawn(function()
		task.wait(2)
		local res = Net.request("LabState", {})
		if res and res.ok and res.state then
			State.set("lab", res.state)
		end
	end)
end

return LabClient
