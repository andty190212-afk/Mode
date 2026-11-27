-- LabService: island laboratories (one per restaurant), creature chests, growth, income,
-- special dishes, the mandatory 2-minute security cycle with the close plate, access
-- settings and creature theft (carry / return on hit / delivery). Everything is server-side.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local MapLayout = require(Shared.MapLayout)
local Data = Shared.Data
local Creatures = require(Data.Creatures)
local Rarities = require(Data.Rarities)
local Chests = require(Data.Chests)
local LabData = require(Data.Lab)
local Ingredients = require(Data.Ingredients)
local Equipment = require(Data.Equipment)

local LabService = {}
local S

local labs = {} -- [islandIndex] = lab runtime
local carries = {} -- [thief] = carry
local stealCooldown = {} -- [thief] = os.clock()
local chestLock = {} -- [player] = os.clock()
local rng = Random.new()

LabService.Labs = labs

function LabService.Init(registry)
	S = registry
end

-- ===================== HELPERS =====================
local function profileOf(player)
	return S.DataService.get(player)
end

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d", sec // 60, sec % 60)
end

local function hex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function rarityColor(r)
	local c = Rarities.Info[r].color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function labModel(index)
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Labs")
	return folder and folder:FindFirstChild("Lab" .. index)
end

local function ownerProfile(lab)
	return lab.island.owner and profileOf(lab.island.owner)
end

local function labSettings(lab)
	local p = ownerProfile(lab)
	return p and p.data.lab
end

local function isTeam(player, lab)
	return S.RestaurantService.isMember(player, lab.island)
end

local function isTrusted(player, lab)
	local st = labSettings(lab)
	return st ~= nil and st.trusted[tostring(player.UserId)] ~= nil
end

local function canClose(player, lab)
	if lab.island.owner == player then
		return true
	end
	local st = labSettings(lab)
	return lab.island.friend == player and st ~= nil and st.friendClose
end

local function podCount(lab)
	local st = labSettings(lab)
	local lvl = st and st.level or 1
	return LabData.Levels[lvl].pods
end

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end

local function localPos(cf, pos)
	return cf:PointToObjectSpace(pos)
end

-- creature record owned by player (uid -> record)
local function creatureOf(player, uid)
	local p = profileOf(player)
	return p and p.data.creatures[tostring(uid)], p
end

local function collectionSize(profile)
	local n = 0
	for _ in pairs(profile.data.creatures) do
		n += 1
	end
	return n
end

local function newCreature(profile, id, level)
	local d = profile.data
	d.creatureSeq += 1
	local uid = tostring(d.creatureSeq)
	d.creatures[uid] = { id = id, lvl = level or 1, grow = 0, pod = 0, dish = 0, got = os.time() }
	return uid, d.creatures[uid]
end

-- ===================== BONUSES (used by the restaurant) =====================
-- sum of an ability kind over adult creatures in the island's lab pods, capped
function LabService.bonus(island, kind)
	local lab = island and labs[island.index]
	if not lab then
		return 0
	end
	local total = 0
	for _, pod in pairs(lab.pods) do
		local rec = pod.record
		if rec and not pod.carried then
			local def = Creatures.ById[rec.id]
			if def and rec.grow >= Creatures.stats(def).grow then
				if def.ability.kind == kind then
					total += Creatures.abilityValue(def.ability, rec.lvl)
				end
				if rec.lvl >= Creatures.SecondAbilityLevel and def.ability2.kind == kind then
					total += Creatures.abilityValue(def.ability2, rec.lvl)
				end
			end
		end
	end
	return math.min(total, Creatures.Caps[kind] or total)
end

function LabService.mult(island, kind)
	return 1 + LabService.bonus(island, kind) / 100
end

-- ===================== CREATURE MODELS IN PODS =====================
local function scaleModel(model, scale)
	if scale == 1 then
		return
	end
	local ok = pcall(function()
		model:ScaleTo(scale)
	end)
	if ok then
		return
	end
	local pivot = model:GetPivot()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size = d.Size * scale
			d.CFrame = pivot * (rel - rel.Position + rel.Position * scale)
		end
	end
end

local function makeCreatureModel(id, stageIndex)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Creatures")
	local def = Creatures.ById[id]
	local model
	if stageIndex == 1 then
		local egg = folder and folder:FindFirstChild("Egg")
		model = egg and egg:Clone() or Instance.new("Model")
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "Shell" then
				p.Color = rarityColor(def.rarity)
			end
		end
	else
		local src = folder and folder:FindFirstChild(id)
		model = src and src:Clone() or Instance.new("Model")
		scaleModel(model, Creatures.Stages[stageIndex].scale)
	end
	model.Name = "Creature"
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	model:SetAttribute("Anim", stageIndex == 1 and "egg" or def.anim)
	model:SetAttribute("Rarity", def.rarity)
	model:SetAttribute("CreatureId", id)
	return model
end

local function podPart(lab, i)
	local pods = lab.model and lab.model:FindFirstChild("Pods")
	return pods and pods:FindFirstChild("Pod" .. i)
end

local function podTopCFrame(part)
	return part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.2, 0)
end

local function infoText(rec, owner)
	local def = Creatures.ById[rec.id]
	local st = Creatures.stats(def)
	local progress = math.min(1, rec.grow / st.grow)
	local _, stage = Creatures.stageOf(progress)
	local lines = {
		string.format("<b>%s</b>  <font color='#%s'>%s</font>", def.name, hex(rarityColor(def.rarity)), Rarities.Info[def.rarity].name),
		string.format("Ур. %d • %s", rec.lvl, stage.name),
	}
	if progress < 1 then
		table.insert(lines, string.format("Рост: %d%%", math.floor(progress * 100)))
	else
		table.insert(lines, string.format("💰 %d/мин • %s %d%%", Creatures.income(def, rec.lvl), def.dish.icon, math.floor(rec.dish / st.dishTime * 100)))
	end
	if owner then
		table.insert(lines, "<font color='#A5AFD2'>" .. owner.DisplayName .. "</font>")
	end
	return table.concat(lines, "\n")
end

local function refreshPodVisual(lab, i)
	local pod = lab.pods[i]
	local part = podPart(lab, i)
	if not part then
		return
	end
	local rec = pod and pod.record
	local wantStage = 0
	if rec and not pod.carried then
		local def = Creatures.ById[rec.id]
		wantStage = Creatures.stageOf(math.min(1, rec.grow / Creatures.stats(def).grow))
	end
	if pod and pod.model and (pod.shownStage ~= wantStage or pod.shownUid ~= pod.uid) then
		pod.model:Destroy()
		pod.model = nil
	end
	if pod and wantStage > 0 and not pod.model then
		local m = makeCreatureModel(rec.id, wantStage)
		m:PivotTo(podTopCFrame(part))
		local primary = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
		if primary then
			local bb = Instance.new("BillboardGui")
			bb.Name = "Info"
			bb.Size = UDim2.fromOffset(190, 70)
			bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
			bb.MaxDistance = 70
			bb.AlwaysOnTop = false
			local t = Instance.new("TextLabel")
			t.Name = "Text"
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.RichText = true
			t.TextScaled = true
			t.TextColor3 = Color3.new(1, 1, 1)
			t.TextStrokeTransparency = 0.4
			t.Parent = bb
			bb.Parent = primary
		end
		m.Parent = lab.model
		pod.model = m
		pod.shownStage = wantStage
		pod.shownUid = pod.uid
	end
	if pod and pod.model then
		local label = pod.model:FindFirstChild("Text", true)
		if label then
			label.Text = infoText(rec, pod.owner)
		end
	end
	-- prompt
	local prompt = part:FindFirstChild("StealPrompt")
	if prompt then
		local def = rec and Creatures.ById[rec.id]
		prompt.Enabled = lab.state ~= "closed" and pod ~= nil and not pod.carried and def ~= nil
		if def then
			prompt.ObjectText = def.name .. " (" .. Rarities.Info[def.rarity].name .. ")"
			prompt.HoldDuration = Creatures.stats(def).stealHold * (1 + LabService.bonus(lab.island, "guard") / 100)
		end
	end
	local glow = part:FindFirstChild("Glow")
	if glow then
		glow.Color = rec and rarityColor(Creatures.ById[rec.id].rarity) or Color3.fromRGB(80, 200, 255)
	end
end

local function placeRecord(lab, i, owner, uid, rec)
	lab.pods[i] = { owner = owner, uid = uid, record = rec }
	rec.pod = i
	refreshPodVisual(lab, i)
end

local function clearPod(lab, i)
	local pod = lab.pods[i]
	if pod and pod.model then
		pod.model:Destroy()
	end
	lab.pods[i] = nil
	refreshPodVisual(lab, i)
end

-- ===================== STATE PUSH =====================
local function markDirty(lab)
	if lab then
		lab.dirty = true
	end
end
LabService.markDirty = markDirty

function LabService.buildState(player)
	local profile = profileOf(player)
	if not profile then
		return nil
	end
	local d = profile.data
	local island = S.RestaurantService.islandOf(player)
	local lab = island and labs[island.index]
	local stars = island and island.rest and island.rest.stars or 0
	local state = {
		island = island and island.index or 0,
		isOwner = island ~= nil and island.owner == player,
		dishes = d.dishes,
		bank = math.floor(d.lab.bank),
		stats = d.pvp,
		collection = {},
		chests = {},
		maxCollection = LabData.MaxCollection,
	}
	local luck = 0
	if lab then
		local st = labSettings(lab)
		luck = LabData.Levels[st.level].luck + LabService.bonus(island, "luck")
		state.level = st.level
		state.maxLevel = math.min(stars, #LabData.Levels)
		state.pods = podCount(lab)
		state.access = st.access
		state.friendClose = st.friendClose
		state.trusted = {}
		for uid, name in pairs(st.trusted) do
			table.insert(state.trusted, { id = tonumber(uid), name = name })
		end
		state.cycle = {
			state = lab.state,
			remaining = math.ceil(lab.state == "closed" and lab.cycleRemaining or math.max(0, LabData.OpenWarnTime - lab.openElapsed)),
		}
		state.podList = {}
		for i = 1, LabData.MaxPods do
			local pod = lab.pods[i]
			if pod then
				state.podList[tostring(i)] = {
					uid = pod.uid,
					id = pod.record.id,
					lvl = pod.record.lvl,
					owner = pod.owner and pod.owner.DisplayName or "?",
					mine = pod.owner == player,
					carried = pod.carried ~= nil,
				}
			end
		end
		state.canClose = canClose(player, lab)
		state.bonuses = {}
		for kind in pairs(Creatures.Abilities) do
			local b = LabService.bonus(island, kind)
			if b > 0 then
				state.bonuses[kind] = b
			end
		end
	end
	state.luck = luck
	for _, c in ipairs(Chests.List) do
		table.insert(state.chests, { id = c.id, locked = stars < c.stars, odds = Chests.odds(c, luck) })
	end
	for uid, rec in pairs(d.creatures) do
		table.insert(state.collection, { uid = uid, id = rec.id, lvl = rec.lvl, grow = rec.grow, pod = rec.pod, dish = rec.dish, carried = rec.carriedBy ~= nil })
	end
	return state
end

function LabService.push(player)
	local st = LabService.buildState(player)
	if st then
		Net.push(player, "lab", st)
	end
end

local function pushTeam(lab)
	for _, m in ipairs(S.RestaurantService.membersOf(lab.island)) do
		LabService.push(m)
	end
end

-- ===================== WORLD VISUALS =====================
local function setShield(lab)
	local m = lab.model
	if not m then
		return
	end
	local closed = lab.state == "closed"
	local shields = m:FindFirstChild("Shields")
	if shields then
		for _, p in ipairs(shields:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = closed and 0.55 or 1
			end
		end
	end
	local siren = m:FindFirstChild("Siren")
	if siren then
		siren.Color = closed and Color3.fromRGB(60, 220, 120) or Color3.fromRGB(255, 40, 40)
		local light = siren:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Color = siren.Color
			light.Brightness = closed and 1 or 4
		end
	end
	m:SetAttribute("LabState", lab.state)
end

local function updateBoard(lab)
	local m = lab.model
	if not m then
		return
	end
	local text
	if not lab.island.owner then
		text = "🧪 ЛАБОРАТОРИЯ\nостров свободен"
		m:SetAttribute("LabState", "idle")
	elseif lab.state == "closed" then
		text = "🛡️ ЛАБОРАТОРИЯ ЗАЩИЩЕНА\nоткроется через " .. fmtTime(lab.cycleRemaining)
	elseif lab.state == "open" then
		text = "🚨 ЛАБОРАТОРИЯ ОТКРЫТА!\nДО ЗАКРЫТИЯ ОСТАЛОСЬ: " .. fmtTime(LabData.OpenWarnTime - lab.openElapsed)
	else
		text = "☠️ ОПАСНОСТЬ!\nЛАБОРАТОРИЯ ВСЁ ЕЩЁ ОТКРЫТА!"
	end
	m:SetAttribute("LabRemaining", lab.state == "closed" and math.ceil(lab.cycleRemaining) or math.ceil(math.max(0, LabData.OpenWarnTime - lab.openElapsed)))
	local board = m:FindFirstChild("Board")
	local label = board and board:FindFirstChild("Text", true)
	if label then
		label.Text = text
	end
	local plateLabel = m:FindFirstChild("PlateSign") and m.PlateSign:FindFirstChild("Text", true)
	if plateLabel then
		plateLabel.Text = lab.state == "closed" and "🛡️ ЗАЩИЩЕНО" or "⬇️ ЗАКРЫТЬ ЛАБОРАТОРИЮ ⬇️"
	end
end

-- ===================== CYCLE =====================
local function openLab(lab)
	lab.state = "open"
	lab.openElapsed = 0
	setShield(lab)
	for i in pairs(lab.pods) do
		refreshPodVisual(lab, i)
	end
	for _, m in ipairs(S.RestaurantService.membersOf(lab.island)) do
		Net.fx(m, "labAlarm", { kind = "open", island = lab.island.index, remaining = LabData.OpenWarnTime })
	end
	Net.fxAll("labWorld", { island = lab.island.index, state = "open" })
	updateBoard(lab)
	markDirty(lab)
end

local function closeLab(lab, by)
	lab.state = "closed"
	lab.cycleRemaining = LabData.ClosedTime
	lab.openElapsed = 0
	setShield(lab)
	for i in pairs(lab.pods) do
		refreshPodVisual(lab, i)
	end
	for _, m in ipairs(S.RestaurantService.membersOf(lab.island)) do
		Net.fx(m, "labAlarm", { kind = "closed", island = lab.island.index, by = by and by.DisplayName })
	end
	Net.fxAll("labWorld", { island = lab.island.index, state = "closed" })
	updateBoard(lab)
	markDirty(lab)
end

-- player physically standing on the close plate?
local function onPlate(lab, player)
	local plate = lab.model and lab.model:FindFirstChild("Plate")
	local root, hum = rootOf(player)
	if not plate or not root or not hum or hum.Health <= 0 then
		return false
	end
	local rel = localPos(plate.CFrame, root.Position)
	return math.abs(rel.X) <= plate.Size.X / 2 + 0.5 and math.abs(rel.Z) <= plate.Size.Z / 2 + 0.5 and rel.Y > -1 and rel.Y < 7
end

function LabService.tryPlate(player, lab)
	if lab.state == "closed" or not lab.island.owner then
		return false
	end
	if not canClose(player, lab) then
		return false
	end
	if not onPlate(lab, player) then
		return false
	end
	closeLab(lab, player)
	return true
end

-- ===================== THEFT =====================
local function carryBillboard(char, def)
	local head = char:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "StolenTag"
	bb.Size = UDim2.fromOffset(220, 46)
	bb.StudsOffset = Vector3.new(0, 6.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 250
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(120, 10, 10)
	t.BackgroundTransparency = 0.2
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.RichText = true
	t.Text = "🚨 ВОР! Несёт: <b>" .. def.name .. "</b>"
	t.Parent = bb
	bb.Parent = head
end

local function setArms(char, raised, store)
	for _, name in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		local arm = char:FindFirstChild(name)
		local motor = arm and arm:FindFirstChildWhichIsA("Motor6D")
		if motor then
			if raised then
				store[motor] = motor.C0
				motor.C0 = motor.C0 * CFrame.Angles(math.rad(90), 0, 0)
			elseif store[motor] then
				motor.C0 = store[motor]
			end
		end
	end
end

local function endCarryVisuals(carry)
	if carry.model then
		carry.model:Destroy()
		carry.model = nil
	end
	local char = carry.thief.Character
	if char then
		local tag = char:FindFirstChild("StolenTag", true)
		if tag then
			tag:Destroy()
		end
		setArms(char, false, carry.arms)
		char:SetAttribute("CarryingFrom", nil)
	end
	carry.thief:SetAttribute("Carrying", nil)
	if S.CombatService then
		S.CombatService.refreshSpeed(carry.thief)
	end
end

-- give the creature back to its owner (pod if still free, otherwise storage)
local function returnCreature(carry, reason, catcher)
	if carries[carry.thief] ~= carry then
		return
	end
	carries[carry.thief] = nil
	endCarryVisuals(carry)
	local rec = carry.record
	rec.carriedBy = nil
	local lab = carry.lab
	local pod = lab.pods[carry.pod]
	if lab.island.owner and pod and pod.uid == carry.uid and pod.owner == carry.owner then
		pod.carried = nil
		refreshPodVisual(lab, carry.pod)
	else
		rec.pod = 0
	end
	local def = Creatures.ById[rec.id]
	if carry.owner.Parent then
		Net.fx(carry.owner, "theft", { kind = "returned", name = def.name, rarity = def.rarity, catcher = catcher and catcher.DisplayName, reason = reason })
	end
	if carry.thief.Parent then
		Net.fx(carry.thief, "theft", { kind = reason == "caught" and "caught" or "lost", name = def.name, rarity = def.rarity })
	end
	local part = podPart(lab, carry.pod)
	if part then
		Net.fxAll("sparkle", { pos = part.Position + Vector3.new(0, 3, 0), color = def.rarity })
	end
	markDirty(lab)
end

local function deliver(carry, thiefIsland)
	if carries[carry.thief] ~= carry then
		return
	end
	local thiefProfile = profileOf(carry.thief)
	local ownerProf = profileOf(carry.owner)
	if not thiefProfile or not ownerProf or ownerProf.data.creatures[carry.uid] ~= carry.record then
		returnCreature(carry, "error")
		return
	end
	carries[carry.thief] = nil
	endCarryVisuals(carry)
	local lab = carry.lab
	local rec = carry.record
	-- move ownership atomically (no yields): remove from owner, add to thief
	ownerProf.data.creatures[carry.uid] = nil
	if lab.pods[carry.pod] and lab.pods[carry.pod].uid == carry.uid then
		clearPod(lab, carry.pod)
	end
	rec.carriedBy = nil
	local newUid, newRec = newCreature(thiefProfile, rec.id, rec.lvl)
	newRec.grow = rec.grow
	lab.immuneUntil = os.clock() + LabData.VictimImmunity
	thiefProfile.data.pvp.steals += 1
	ownerProf.data.pvp.stolenFrom += 1
	local def = Creatures.ById[rec.id]
	Net.fx(carry.thief, "theft", { kind = "success", name = def.name, rarity = def.rarity })
	if carry.owner.Parent then
		Net.fx(carry.owner, "theft", { kind = "stolen", name = def.name, rarity = def.rarity, thief = carry.thief.DisplayName })
	end
	S.Economy.markPlayer(carry.thief)
	markDirty(lab)
	if thiefIsland then
		markDirty(labs[thiefIsland.index])
	end
	-- save both right away to minimise any window for duplicates/losses
	task.spawn(S.DataService.save, ownerProf, false)
	task.spawn(S.DataService.save, thiefProfile, false)
	return newUid
end

function LabService.isCarrying(player)
	return carries[player] ~= nil
end

function LabService.carryOf(player)
	return carries[player]
end

function LabService.trySteal(thief, lab, i)
	local pod = lab.pods[i]
	if not pod or pod.carried then
		return false, "Здесь никого нет"
	end
	if lab.state == "closed" then
		return false, "Лаборатория защищена"
	end
	if isTeam(thief, lab) or isTrusted(thief, lab) then
		return false, "Нельзя красть у своей команды"
	end
	if pod.owner == thief then
		return false, "Это ваше существо"
	end
	if carries[thief] then
		return false, "Руки уже заняты"
	end
	local thiefIsland = S.RestaurantService.islandOf(thief)
	if not thiefIsland or not labs[thiefIsland.index] then
		return false, "Нужна своя лаборатория: откройте ресторан или вступите в команду"
	end
	local now = os.clock()
	if stealCooldown[thief] and now - stealCooldown[thief] < LabData.StealCooldown then
		return false, "Подождите перед следующей попыткой"
	end
	if lab.immuneUntil and now < lab.immuneUntil then
		return false, "Эту лабораторию только что ограбили. Попробуйте позже"
	end
	local tp = profileOf(thief)
	if not tp or collectionSize(tp) >= LabData.MaxCollection then
		return false, "Ваша коллекция заполнена"
	end
	local root, hum = rootOf(thief)
	local part = podPart(lab, i)
	if not root or not hum or hum.Health <= 0 or not part or (root.Position - part.Position).Magnitude > 14 then
		return false, "Подойдите ближе"
	end
	if hum.SeatPart then
		return false, "Сначала встаньте"
	end
	stealCooldown[thief] = now
	local def = Creatures.ById[pod.record.id]
	local carry = {
		thief = thief,
		owner = pod.owner,
		uid = pod.uid,
		record = pod.record,
		lab = lab,
		pod = i,
		t0 = now,
		lastPos = root.Position,
		arms = {},
	}
	pod.carried = carry
	pod.record.carriedBy = thief.UserId
	carries[thief] = carry
	-- visuals: creature in the thief's hands, raised arms, red tag
	local char = thief.Character
	local stage = Creatures.stageOf(math.min(1, pod.record.grow / Creatures.stats(def).grow))
	local m = makeCreatureModel(def.id, stage)
	scaleModel(m, 0.55)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
		end
	end
	m:PivotTo(root.CFrame * CFrame.new(0, 1.2, -2.4))
	local primary = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	if primary then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and p ~= primary then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = primary, p
				w.Parent = p
			end
		end
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = root, primary
		w.Parent = primary
	end
	m.Name = "CarriedCreature"
	m.Parent = char
	carry.model = m
	setArms(char, true, carry.arms)
	carryBillboard(char, def)
	char:SetAttribute("CarryingFrom", lab.island.index)
	thief:SetAttribute("Carrying", def.id)
	if S.CombatService then
		S.CombatService.refreshSpeed(thief)
	end
	refreshPodVisual(lab, i)
	-- alarm for the victim team
	for _, member in ipairs(S.RestaurantService.membersOf(lab.island)) do
		Net.fx(member, "theft", { kind = "alarm", name = def.name, rarity = def.rarity, thief = thief.DisplayName, thiefId = thief.UserId })
	end
	Net.fx(thief, "theft", { kind = "start", name = def.name, rarity = def.rarity })
	markDirty(lab)
	return true
end

-- the thief's carry speed (used by CombatService.refreshSpeed)
function LabService.carrySpeed(player)
	local carry = carries[player]
	if not carry then
		return nil
	end
	return LabData.CarrySpeed * (1 - LabService.bonus(carry.lab.island, "alarm") / 100)
end

-- attacker hit victim: if the victim carries a creature of the attacker's team -> it drops & returns
function LabService.onHit(attacker, victim)
	local carry = carries[victim]
	if not carry then
		return false
	end
	if carry.owner == attacker or S.RestaurantService.isMember(attacker, carry.lab.island) then
		local ap = profileOf(attacker)
		local vp = profileOf(victim)
		if ap then
			ap.data.pvp.defends += 1
		end
		if vp then
			vp.data.pvp.caught += 1
		end
		returnCreature(carry, "caught", attacker)
		return true
	end
	return false
end

function LabService.canFightThief(attacker, victim)
	local carry = carries[victim]
	if carry and (carry.owner == attacker or S.RestaurantService.isMember(attacker, carry.lab.island)) then
		return true
	end
	-- the thief may defend himself against the owner team
	local own = carries[attacker]
	if own and (own.owner == victim or S.RestaurantService.isMember(victim, own.lab.island)) then
		return true
	end
	return false
end

-- ===================== LAB SETUP =====================
local function insideInterior(lab, pos)
	local box = lab.model and lab.model:FindFirstChild("Interior")
	if not box then
		return false
	end
	local rel = localPos(box.CFrame, pos)
	return math.abs(rel.X) <= box.Size.X / 2 and math.abs(rel.Z) <= box.Size.Z / 2 and math.abs(rel.Y) <= box.Size.Y / 2
end

local function onPlatform(lab, pos)
	local floor = lab.model and lab.model:FindFirstChild("Floor")
	if not floor then
		return false
	end
	local rel = localPos(floor.CFrame, pos)
	return math.abs(rel.X) <= floor.Size.X / 2 + 2 and math.abs(rel.Z) <= floor.Size.Z / 2 + 2 and rel.Y > -2 and rel.Y < 20
end

function LabService.setupIsland(island)
	local profile = island.owner and profileOf(island.owner)
	if not profile then
		return
	end
	local st = profile.data.lab
	local lab = labs[island.index] or { island = island }
	labs[island.index] = lab
	lab.model = labModel(island.index)
	lab.pods = {}
	lab.immuneUntil = 0
	-- restore the cycle exactly as it was (rejoining does not reset the timer)
	if st.open then
		lab.state = (st.openElapsed or 0) >= LabData.OpenWarnTime and "danger" or "open"
		lab.openElapsed = st.openElapsed or 0
		lab.cycleRemaining = 0
	else
		lab.state = "closed"
		lab.cycleRemaining = Util.clamp(st.cycleRemaining or LabData.ClosedTime, 1, LabData.ClosedTime)
		lab.openElapsed = 0
	end
	if lab.model then
		lab.model:SetAttribute("LabIsland", island.index)
		lab.model:SetAttribute("LabOwner", island.owner.DisplayName)
		local sign = lab.model:FindFirstChild("Sign")
		local label = sign and sign:FindFirstChild("Text", true)
		if label then
			label.Text = "🧪 Лаборатория: " .. island.owner.DisplayName
		end
	end
	-- owner's creatures back into their pods
	local pods = podCount(lab)
	for uid, rec in pairs(profile.data.creatures) do
		rec.carriedBy = nil
		if rec.pod > 0 then
			if rec.pod <= pods and not lab.pods[rec.pod] then
				placeRecord(lab, rec.pod, island.owner, uid, rec)
			else
				rec.pod = 0
			end
		end
	end
	setShield(lab)
	updateBoard(lab)
	markDirty(lab)
end

-- a team member leaves (friend removed / owner unload): their creatures go to storage
function LabService.memberLeft(island, player)
	local lab = labs[island.index]
	if not lab then
		return
	end
	for i, pod in pairs(lab.pods) do
		if pod.owner == player then
			if pod.carried then
				returnCreature(pod.carried, "owner_left")
			end
			local rec = pod.record
			clearPod(lab, i)
			rec.pod = player == island.owner and i or 0 -- the owner keeps the layout for next time
		end
	end
	markDirty(lab)
end

function LabService.clearIsland(island)
	local lab = labs[island.index]
	if not lab then
		return
	end
	-- cancel every running theft from this lab (creatures stay with their owners)
	for _, carry in pairs(carries) do
		if carry.lab == lab then
			returnCreature(carry, "owner_left")
		end
	end
	-- the thief of this island loses the carried loot as well
	for thief, carry in pairs(carries) do
		if S.RestaurantService.islandOf(thief) == island then
			returnCreature(carry, "lost")
		end
	end
	local profile = island.owner and profileOf(island.owner)
	if profile then
		local st = profile.data.lab
		st.open = lab.state ~= "closed"
		st.openElapsed = lab.openElapsed
		st.cycleRemaining = lab.cycleRemaining
	end
	if island.friend then
		LabService.memberLeft(island, island.friend)
	end
	for i, pod in pairs(lab.pods) do
		local rec = pod.record
		clearPod(lab, i)
		rec.pod = i
	end
	labs[island.index] = nil
	lab.state = "closed"
	lab.cycleRemaining = LabData.ClosedTime
	setShield(lab)
	if lab.model then
		lab.model:SetAttribute("LabOwner", nil)
		lab.model:SetAttribute("LabState", "idle")
		local sign = lab.model:FindFirstChild("Sign")
		local label = sign and sign:FindFirstChild("Text", true)
		if label then
			label.Text = "🧪 Лаборатория"
		end
		local board = lab.model:FindFirstChild("Board")
		local bl = board and board:FindFirstChild("Text", true)
		if bl then
			bl.Text = "🧪 ЛАБОРАТОРИЯ\nостров свободен"
		end
	end
end

-- ===================== TICKS =====================
local function giveIngredients(island, amount)
	local rest = island.rest
	if not rest then
		return
	end
	local cap = Equipment.storageCapacity(rest)
	local used = S.ShopService.storageUsed(rest)
	for _ = 1, amount do
		if used >= cap then
			return
		end
		local item = Ingredients.List[rng:NextInteger(1, #Ingredients.List)]
		rest.inventory[item.id] = (rest.inventory[item.id] or 0) + 1
		used += 1
	end
	S.RestaurantService.markDirty(island)
end

local function tickCreatures(lab, dt)
	local island = lab.island
	local st = labSettings(lab)
	local growthMult = 1 + (LabData.Levels[st.level].growth + LabService.bonus(island, "growth")) / 100
	local synergy = 1 + LabService.bonus(island, "synergy") / 100
	local dishMult = 1 + LabService.bonus(island, "dishes") / 100
	lab.ingredientAcc = (lab.ingredientAcc or 0) + LabService.bonus(island, "ingredients") * dt / 60
	if lab.ingredientAcc >= 1 then
		local n = math.floor(lab.ingredientAcc)
		lab.ingredientAcc -= n
		giveIngredients(island, n)
	end
	local rep = LabService.bonus(island, "reputation")
	if rep > 0 and island.rest then
		island.rest.reputation = Util.clamp(island.rest.reputation + rep * dt / 60, 0, 100)
	end
	for _, pod in pairs(lab.pods) do
		local rec = pod.record
		local owner = pod.owner
		local prof = owner and owner.Parent and profileOf(owner)
		if prof and not pod.carried then
			local def = Creatures.ById[rec.id]
			local stats = Creatures.stats(def)
			if rec.grow < stats.grow then
				rec.grow = math.min(stats.grow, rec.grow + dt * growthMult)
			else
				-- income into the owner's lab bank
				prof.data.lab.bank += Creatures.income(def, rec.lvl) / 60 * dt * synergy
				-- special dish
				rec.dish += dt * dishMult
				if rec.dish >= stats.dishTime then
					local total = 0
					for _, n in pairs(prof.data.dishes) do
						total += n
					end
					if total < LabData.MaxDishes then
						rec.dish = 0
						prof.data.dishes[def.dish.id] = (prof.data.dishes[def.dish.id] or 0) + 1
						Net.fx(owner, "dishReady", { dish = def.dish.id, creature = def.id })
						LabService.push(owner)
					else
						rec.dish = stats.dishTime
					end
				end
			end
		end
	end
end

local function tickCycle(lab, dt)
	if lab.state == "closed" then
		lab.cycleRemaining -= dt
		if lab.cycleRemaining <= 0 then
			openLab(lab)
		end
	else
		lab.openElapsed += dt
		if lab.state == "open" and lab.openElapsed >= LabData.OpenWarnTime then
			-- time is up: the lab does NOT close by itself, it stays open
			lab.state = "danger"
			setShield(lab)
			for _, m in ipairs(S.RestaurantService.membersOf(lab.island)) do
				Net.fx(m, "labAlarm", { kind = "danger", island = lab.island.index })
			end
			markDirty(lab)
		end
	end
end

local function fastTick()
	local now = os.clock()
	-- plates & private access
	for _, lab in pairs(labs) do
		if lab.island.owner and lab.model then
			if lab.state ~= "closed" then
				for _, m in ipairs(S.RestaurantService.membersOf(lab.island)) do
					if LabService.tryPlate(m, lab) then
						break
					end
				end
			end
			local st = labSettings(lab)
			if lab.state == "closed" and st and st.access == "private" then
				local entry = lab.model:FindFirstChild("Entry")
				for _, p in ipairs(Players:GetPlayers()) do
					if not isTeam(p, lab) and not isTrusted(p, lab) then
						local root = rootOf(p)
						if root and entry and insideInterior(lab, root.Position) then
							S.RestaurantService.teleport(p, entry.CFrame * CFrame.new(0, 3, 0))
							Net.toast(p, "🛡️ Лаборатория закрыта владельцем", "warn")
						end
					end
				end
			end
		end
	end
	-- carriers
	for thief, carry in pairs(carries) do
		local root, hum = rootOf(thief)
		if not thief.Parent or not root or not hum or hum.Health <= 0 then
			returnCreature(carry, "dropped")
		elseif not carry.owner.Parent or not carry.lab.island.owner then
			returnCreature(carry, "owner_left")
		elseif hum.SeatPart then
			hum.Sit = false
			returnCreature(carry, "vehicle")
		elseif (root.Position - carry.lastPos).Magnitude > 60 then
			returnCreature(carry, "teleport")
		elseif now - carry.t0 > LabData.CarryMaxTime then
			returnCreature(carry, "timeout")
		else
			carry.lastPos = root.Position
			local home = S.RestaurantService.islandOf(thief)
			local homeLab = home and labs[home.index]
			if homeLab and homeLab ~= carry.lab and onPlatform(homeLab, root.Position) then
				deliver(carry, home)
			end
		end
	end
end

local function slowTick(dt)
	for _, lab in pairs(labs) do
		if lab.island.owner then
			tickCycle(lab, dt)
			tickCreatures(lab, dt)
			lab.visualAcc = (lab.visualAcc or 0) + dt
			if lab.visualAcc >= 2 then
				lab.visualAcc = 0
				for i in pairs(lab.pods) do
					refreshPodVisual(lab, i)
				end
			end
			updateBoard(lab)
			lab.pushAcc = (lab.pushAcc or 0) + dt
			if lab.dirty or lab.pushAcc >= 5 then
				lab.dirty = false
				lab.pushAcc = 0
				pushTeam(lab)
			end
		end
	end
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

local function myLab(player)
	local island = S.RestaurantService.islandOf(player)
	return island and labs[island.index], island
end

local function registerRemotes()
	Net.onRequest("LabState", function(player)
		return ok({ state = LabService.buildState(player) })
	end)

	Net.setRate("BuyChest", 2, 3)
	Net.onRequest("BuyChest", function(player, payload)
		local chest = type(payload) == "table" and Chests.ById[payload.chest]
		if not chest then
			return fail("Нет такого сундука")
		end
		local profile = profileOf(player)
		if not profile then
			return fail("Данные ещё загружаются")
		end
		local lab, island = myLab(player)
		if not lab then
			return fail("Сначала откройте ресторан или вступите в команду")
		end
		local now = os.clock()
		if chestLock[player] and now - chestLock[player] < LabData.ChestCooldown then
			return fail("Подождите пару секунд")
		end
		if (island.rest.stars or 1) < chest.stars then
			return fail("Нужен ресторан " .. chest.stars .. "★")
		end
		if collectionSize(profile) >= LabData.MaxCollection then
			return fail("Коллекция заполнена (" .. LabData.MaxCollection .. "). Отпустите кого-нибудь")
		end
		if not S.Economy.spend(player, chest.price, "Сундук: " .. chest.name) then
			return fail("Недостаточно денег")
		end
		chestLock[player] = now
		-- ONE purchase = ONE creature (no yields between spending and granting)
		local st = labSettings(lab)
		local luck = LabData.Levels[st.level].luck + LabService.bonus(island, "luck")
		local rarity = Chests.roll(chest, luck, rng)
		local pool = Creatures.ByRarity[rarity]
		local def = pool[rng:NextInteger(1, #pool)]
		local uid = newCreature(profile, def.id, 1)
		profile.data.pvp.chests += 1
		S.Economy.markPlayer(player)
		markDirty(lab)
		LabService.push(player)
		if Rarities.rank(rarity) >= 5 then
			Net.fxAll("announce", { text = "🎉 " .. player.DisplayName .. " получил " .. Rarities.Info[rarity].name .. " существо «" .. def.name .. "»!" })
		end
		return ok({ uid = uid, id = def.id, rarity = rarity, chest = chest.id })
	end)

	Net.onRequest("PlaceCreature", function(player, payload)
		local lab, island = myLab(player)
		if not lab then
			return fail("Сначала откройте ресторан или вступите в команду")
		end
		local uid = type(payload) == "table" and tostring(payload.uid)
		local rec = uid and creatureOf(player, uid)
		if not rec then
			return fail("Существо не найдено")
		end
		if rec.pod > 0 then
			return fail("Уже в капсуле")
		end
		local slot = tonumber(payload.pod)
		local pods = podCount(lab)
		if not slot then
			for i = 1, pods do
				if not lab.pods[i] then
					slot = i
					break
				end
			end
		end
		if not slot or slot < 1 or slot > pods or slot % 1 ~= 0 then
			return fail("Нет свободных капсул. Улучшите лабораторию")
		end
		if lab.pods[slot] then
			return fail("Капсула занята")
		end
		placeRecord(lab, slot, player, uid, rec)
		markDirty(lab)
		LabService.push(player)
		return ok()
	end)

	Net.onRequest("StoreCreature", function(player, payload)
		local lab = myLab(player)
		local uid = type(payload) == "table" and tostring(payload.uid)
		local rec = uid and creatureOf(player, uid)
		if not lab or not rec then
			return fail("Существо не найдено")
		end
		if rec.carriedBy then
			return fail("Существо сейчас украдено!")
		end
		local pod = lab.pods[rec.pod]
		if pod and pod.uid == uid and pod.owner == player then
			clearPod(lab, rec.pod)
		end
		rec.pod = 0
		markDirty(lab)
		LabService.push(player)
		return ok()
	end)

	Net.onRequest("UpgradeCreature", function(player, payload)
		local uid = type(payload) == "table" and tostring(payload.uid)
		local rec = uid and creatureOf(player, uid)
		if not rec then
			return fail("Существо не найдено")
		end
		if rec.carriedBy then
			return fail("Существо сейчас украдено!")
		end
		if rec.lvl >= Creatures.MaxLevel then
			return fail("Максимальный уровень")
		end
		local def = Creatures.ById[rec.id]
		local cost = Creatures.upgradeCost(def, rec.lvl)
		if not S.Economy.spend(player, cost, "Улучшение существа") then
			return fail("Недостаточно денег")
		end
		rec.lvl += 1
		if rec.lvl == Creatures.SecondAbilityLevel then
			Net.toast(player, "✨ " .. def.name .. ": открыта вторая способность!", "success")
		end
		Net.fx(player, "creatureLevel", { id = def.id, lvl = rec.lvl })
		local lab = myLab(player)
		if lab and rec.pod > 0 then
			refreshPodVisual(lab, rec.pod)
		end
		markDirty(lab)
		LabService.push(player)
		return ok()
	end)

	Net.onRequest("SpeedUpCreature", function(player, payload)
		local uid = type(payload) == "table" and tostring(payload.uid)
		local rec = uid and creatureOf(player, uid)
		if not rec then
			return fail("Существо не найдено")
		end
		local def = Creatures.ById[rec.id]
		local st = Creatures.stats(def)
		local left = st.grow - rec.grow
		if left <= 0 then
			return fail("Уже взрослое")
		end
		local cost = math.ceil(left * st.speedupRate)
		if not S.Economy.spend(player, cost, "Ускорение роста") then
			return fail("Недостаточно денег")
		end
		rec.grow = st.grow
		local lab = myLab(player)
		if lab and rec.pod > 0 then
			refreshPodVisual(lab, rec.pod)
		end
		Net.fx(player, "creatureLevel", { id = def.id, lvl = rec.lvl, grown = true })
		markDirty(lab)
		LabService.push(player)
		return ok()
	end)

	Net.onRequest("ReleaseCreature", function(player, payload)
		local uid = type(payload) == "table" and tostring(payload.uid)
		local rec, profile = creatureOf(player, uid or "")
		if not rec then
			return fail("Существо не найдено")
		end
		if rec.carriedBy then
			return fail("Существо сейчас украдено!")
		end
		if rec.pod > 0 then
			return fail("Сначала заберите его из капсулы")
		end
		local def = Creatures.ById[rec.id]
		profile.data.creatures[uid] = nil
		local refund = math.floor(Creatures.stats(def).upgradeBase * 0.5 * rec.lvl)
		S.Economy.grant(player, refund, "Существо отпущено")
		LabService.push(player)
		return ok({ refund = refund })
	end)

	Net.onRequest("CollectLab", function(player)
		local profile = profileOf(player)
		if not profile then
			return fail("Данные ещё загружаются")
		end
		local amount = math.floor(profile.data.lab.bank)
		if amount <= 0 then
			return fail("Пока нечего забирать")
		end
		profile.data.lab.bank -= amount
		S.Economy.earn(player, amount, "Доход существ", true)
		Net.fx(player, "money", { amount = amount, text = "Существа" })
		LabService.push(player)
		return ok({ amount = amount })
	end)

	Net.onRequest("UpgradeLab", function(player)
		local lab, island = myLab(player)
		if not lab or island.owner ~= player then
			return fail("Только владелец")
		end
		local st = labSettings(lab)
		local nextLvl = st.level + 1
		local def = LabData.Levels[nextLvl]
		if not def then
			return fail("Максимальный уровень")
		end
		if (island.rest.stars or 1) < nextLvl then
			return fail("Нужен ресторан " .. nextLvl .. "★")
		end
		if not S.Economy.budgetSpend(island, def.price, "upgrade", player.DisplayName, "Лаборатория ур. " .. nextLvl, "upgrades") then
			return fail("Недостаточно денег в бюджете ресторана")
		end
		st.level = nextLvl
		Net.fx(player, "levelup", { level = nextLvl, text = "Лаборатория ур. " .. nextLvl })
		markDirty(lab)
		return ok()
	end)

	Net.onRequest("LabSettings", function(player, payload)
		local lab, island = myLab(player)
		if not lab or island.owner ~= player or type(payload) ~= "table" then
			return fail("Только владелец")
		end
		local st = labSettings(lab)
		if payload.access == "open" or payload.access == "private" then
			st.access = payload.access
		end
		if type(payload.friendClose) == "boolean" then
			st.friendClose = payload.friendClose
		end
		markDirty(lab)
		return ok()
	end)

	Net.onRequest("LabTrust", function(player, payload)
		local lab, island = myLab(player)
		if not lab or island.owner ~= player or type(payload) ~= "table" then
			return fail("Только владелец")
		end
		local st = labSettings(lab)
		local id = tonumber(payload.userId)
		if not id then
			return fail("Игрок не найден")
		end
		if payload.allow then
			local target = Players:GetPlayerByUserId(id)
			if not target or target == player then
				return fail("Игрок не на сервере")
			end
			local n = 0
			for _ in pairs(st.trusted) do
				n += 1
			end
			if n >= 20 then
				return fail("Максимум 20 игроков в списке")
			end
			st.trusted[tostring(id)] = target.DisplayName
		else
			st.trusted[tostring(id)] = nil
		end
		markDirty(lab)
		return ok()
	end)
end

function LabService.Start()
	registerRemotes()
	-- steal prompts on every pod of every lab model
	for i = 1, MapLayout.IslandCount do
		local model = labModel(i)
		local pods = model and model:FindFirstChild("Pods")
		if pods then
			for _, part in ipairs(pods:GetChildren()) do
				local idx = tonumber(string.match(part.Name, "^Pod(%d+)$"))
				if idx then
					local prompt = part:FindFirstChild("StealPrompt") or Instance.new("ProximityPrompt")
					prompt.Name = "StealPrompt"
					prompt.ActionText = "Украсть"
					prompt.ObjectText = ""
					prompt.HoldDuration = 3
					prompt.MaxActivationDistance = 11
					prompt.RequiresLineOfSight = false
					prompt.Enabled = false
					prompt:SetAttribute("ThiefPrompt", true)
					prompt:SetAttribute("LabIsland", i)
					prompt.Parent = part
					prompt.Triggered:Connect(function(player)
						local lab = labs[i]
						if not lab then
							return
						end
						local okSteal, err = LabService.trySteal(player, lab, idx)
						if not okSteal and err then
							Net.toast(player, err, "warn")
						end
					end)
				end
			end
		end
		local plate = model and model:FindFirstChild("Plate")
		if plate then
			plate.Touched:Connect(function(hit)
				local char = hit.Parent
				local player = char and Players:GetPlayerFromCharacter(char)
				local lab = labs[i]
				if player and lab then
					LabService.tryPlate(player, lab)
				end
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		local carry = carries[p]
		if carry then
			returnCreature(carry, "dropped")
		end
		stealCooldown[p] = nil
		chestLock[p] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		local acc = 0
		while true do
			task.wait(0.25)
			local now = os.clock()
			local dt = math.min(2, now - last)
			last = now
			local ok1, e1 = pcall(fastTick)
			if not ok1 then
				warn("[LabService] fast tick: " .. tostring(e1))
			end
			acc += dt
			if acc >= 1 then
				local ok2, e2 = pcall(slowTick, acc)
				if not ok2 then
					warn("[LabService] tick: " .. tostring(e2))
				end
				acc = 0
			end
		end
	end)
end

return LabService
