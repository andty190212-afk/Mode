-- KitchenService: kitchen & bar queues, ingredient consumption, player cooking
-- sessions (mini-games, server-validated), basic auto-kitchen fallback,
-- the pass counter (ready dishes) and the order board display.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = Shared.Data
local Recipes = require(Data.Recipes)
local Equipment = require(Data.Equipment)
local Professions = require(Data.Professions)

local Kitchen = {}
local S

local MIN_STEP_TIME = 1.1 -- секунд на один шаг мини-игры (защита от мгновенного завершения)
local SESSION_TIMEOUT = 120

function Kitchen.Init(registry)
	S = registry
end

-- ===================== SETUP =====================
local function makePrompt(part, name, action, role, cb)
	if not part then
		return nil
	end
	local old = part:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = ""
	p.HoldDuration = 0.25
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p:SetAttribute("Role", role)
	p.Triggered:Connect(cb)
	p.Parent = part
	return p
end

function Kitchen.setupIsland(island)
	island.kitchen = {
		dishQueue = {},
		drinkQueue = {},
		pass = {},
		sessions = {},
		nextUid = 1,
		autoDishes = {},
		autoDrinks = {},
		visuals = {},
		boardDirty = true,
	}
	Kitchen.bindBuilding(island)
end

-- (re)bind prompts after the building is spawned/rebuilt
function Kitchen.bindBuilding(island)
	local RS = S.RestaurantService
	makePrompt(RS.buildingPart(island, "OrderBoard"), "CookPrompt", "Готовить заказ", "Cook", function(player)
		Kitchen.startSession(island, player, "dish")
	end)
	makePrompt(RS.buildingPart(island, "BarCounter"), "BarPrompt", "Приготовить напиток", "Cook,Waiter", function(player)
		Kitchen.startSession(island, player, "drink")
	end)
	makePrompt(RS.buildingPart(island, "PassCounter"), "PassPrompt", "Забрать блюда", "Waiter", function(player)
		if not RS.isMember(player, island) then
			return
		end
		if RS.roleOf(player) ~= "Waiter" then
			Net.toast(player, "Разносить блюда может только официант", "warn")
			return
		end
		S.GuestService.pickUp(island, player)
	end)
	makePrompt(RS.buildingPart(island, "Fridge"), "StoragePrompt", "Склад и закупка", "", function(player)
		if RS.isMember(player, island) then
			Net.fx(player, "openMenu", { menu = "shop" })
		end
	end)
	local host = RS.buildingPart(island, "HostStand")
	makePrompt(host, "VisitorPrompt", "Купить обед ($" .. Config.VisitorMealPrice .. ")", "Visitor", function(player)
		Kitchen.visitorMeal(island, player)
	end)
	if island.kitchen then
		island.kitchen.boardDirty = true
		Kitchen.refreshPassVisuals(island)
	end
end

function Kitchen.clearIsland(island)
	local k = island.kitchen
	if not k then
		return
	end
	for player in pairs(k.sessions) do
		Net.push(player, "cookCancel", {})
	end
	for _, v in pairs(k.visuals) do
		v:Destroy()
	end
	island.kitchen = nil
end

-- ===================== QUEUE =====================
local function consume(rest, recipe)
	for id, n in pairs(recipe.ing) do
		rest.inventory[id] = math.max(0, (rest.inventory[id] or 0) - n)
	end
	return recipe.cost -- стоимость уже учтена в расходах при закупке
end

local function refund(rest, recipe)
	for id, n in pairs(recipe.ing) do
		rest.inventory[id] = (rest.inventory[id] or 0) + n
	end
end

function Kitchen.enqueue(island, recipeId, price, partyId)
	local k = island.kitchen
	local recipe = Recipes.ById[recipeId]
	local item = {
		uid = k.nextUid,
		recipeId = recipeId,
		kind = recipe.kind,
		price = price,
		partyId = partyId,
		status = "queued",
		createdAt = os.clock(),
	}
	k.nextUid += 1
	consume(island.rest, recipe)
	if recipe.kind == "dish" then
		table.insert(k.dishQueue, item)
	else
		table.insert(k.drinkQueue, item)
	end
	k.boardDirty = true
	S.RestaurantService.markDirty(island)
	return item
end

local function removeFrom(list, item)
	local i = table.find(list, item)
	if i then
		table.remove(list, i)
	end
end

function Kitchen.cancelItem(island, item)
	local k = island.kitchen
	if not k then
		return
	end
	if item.status == "queued" then
		refund(island.rest, Recipes.ById[item.recipeId])
	end
	item.status = "cancelled"
	removeFrom(k.dishQueue, item)
	removeFrom(k.drinkQueue, item)
	removeFrom(k.pass, item)
	k.boardDirty = true
	Kitchen.refreshPassVisuals(island)
end

-- next queued item of a kind not claimed by anyone
function Kitchen.claimNext(island, kind, claimer)
	local k = island.kitchen
	if not k then
		return nil
	end
	local q = kind == "dish" and k.dishQueue or k.drinkQueue
	for _, item in ipairs(q) do
		if item.status == "queued" and not item.claimedBy then
			item.claimedBy = claimer
			item.status = "cooking"
			k.boardDirty = true
			return item
		end
	end
	return nil
end

function Kitchen.unclaim(island, item)
	if item.status == "cooking" then
		item.status = "queued"
		item.claimedBy = nil
		if island.kitchen then
			island.kitchen.boardDirty = true
		end
	end
end

-- quality: 0..1 final
function Kitchen.complete(island, item, quality, cookPlayer)
	local k = island.kitchen
	if not k or item.status ~= "cooking" then
		return false
	end
	removeFrom(k.dishQueue, item)
	removeFrom(k.drinkQueue, item)
	item.status = "ready"
	item.quality = Util.clamp(quality, 0.05, 1)
	item.baseQuality = item.quality
	item.cookedBy = cookPlayer and cookPlayer.UserId or nil
	item.readyAt = os.clock()
	table.insert(k.pass, item)
	k.boardDirty = true
	Kitchen.refreshPassVisuals(island)
	S.RestaurantService.markDirty(island)
	return true
end

function Kitchen.readyItems(island)
	return island.kitchen and table.clone(island.kitchen.pass) or {}
end

function Kitchen.removeFromPass(island, item, keepCarry)
	local k = island.kitchen
	if not k then
		return
	end
	removeFrom(k.pass, item)
	Kitchen.refreshPassVisuals(island)
end

function Kitchen.returnToPass(island, item)
	local k = island.kitchen
	if k and not table.find(k.pass, item) then
		table.insert(k.pass, item)
		Kitchen.refreshPassVisuals(island)
	end
end

-- ===================== QUALITY =====================
local function ingredientQuality(recipe)
	return recipe.baseQuality
end

function Kitchen.qualityFor(island, recipe, skill, extraBonus)
	local rest = island.rest
	local ingQ = ingredientQuality(recipe)
	local eq = Equipment.bonus(rest.equipment, "quality")
	if recipe.kind == "drink" then
		eq = Equipment.bonus(rest.equipment, "drinkQuality")
	end
	local chef = S.RestaurantService.chefActive(island) and 0.1 or 0
	local q = (0.3 + 0.7 * skill) * (0.55 + 0.45 * ingQ) + eq + chef + (extraBonus or 0)
	return Util.clamp(q, 0.05, 1)
end

function Kitchen.cookSpeedMult(island, kind)
	local rest = island.rest
	if kind == "drink" then
		return 1 + Equipment.bonus(rest.equipment, "drinkSpeed")
	end
	return 1 + Equipment.bonus(rest.equipment, "cookSpeed")
end

-- ===================== PLAYER SESSIONS =====================
local function canCook(player, island, kind)
	local RS = S.RestaurantService
	if not RS.isMember(player, island) then
		return false, "Это не ваш ресторан"
	end
	local role = RS.roleOf(player)
	if kind == "dish" then
		if role ~= "Cook" then
			if role == "Chef" then
				return false, "Шеф-повар не готовит сам: на кухне работает ваш NPC-повар"
			end
			return false, "Готовить блюда может только повар"
		end
	else
		if role ~= "Cook" and role ~= "Waiter" then
			return false, "Напитки готовят повар или официант (или NPC-бармен)"
		end
	end
	return true
end

function Kitchen.startSession(island, player, kind)
	S.RestaurantService.touch(player)
	local k = island.kitchen
	if not k then
		return
	end
	local okRole, why = canCook(player, island, kind)
	if not okRole then
		Net.toast(player, why, "warn")
		return
	end
	if k.sessions[player] then
		Net.toast(player, "Вы уже готовите", "info")
		return
	end
	local item = Kitchen.claimNext(island, kind, player)
	if not item then
		Net.toast(player, kind == "dish" and "Нет заказов на кухне" or "Нет заказов напитков", "info")
		return
	end
	local recipe = Recipes.ById[item.recipeId]
	local token = HttpService:GenerateGUID(false)
	local prof = kind == "dish" and "Cook" or S.RestaurantService.roleOf(player)
	local level = S.Economy.profLevel(player, prof)
	k.sessions[player] = {
		token = token,
		item = item,
		started = os.clock(),
		steps = recipe.steps,
		kind = kind,
	}
	Net.push(player, "cook", {
		token = token,
		recipeId = recipe.id,
		steps = recipe.steps,
		ease = Professions.cookStepTimeMult(level) * Kitchen.cookSpeedMult(island, kind),
		kind = kind,
	})
	S.RestaurantService.markDirty(island)
end

function Kitchen.finishSession(player, payload)
	local island = S.RestaurantService.islandOf(player)
	local k = island and island.kitchen
	local session = k and k.sessions[player]
	if not session then
		return { ok = false, err = "Нет активной готовки" }
	end
	if type(payload) ~= "table" or payload.token ~= session.token then
		return { ok = false, err = "Неверный сеанс" }
	end
	k.sessions[player] = nil
	local item = session.item
	if payload.cancel == true then
		Kitchen.unclaim(island, item)
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end
	if item.status ~= "cooking" then
		return { ok = false, err = "Заказ отменён" }
	end
	local scores = payload.scores
	if type(scores) ~= "table" or #scores ~= #session.steps then
		Kitchen.unclaim(island, item)
		return { ok = false, err = "Неверный результат" }
	end
	local elapsed = os.clock() - session.started
	local minTime = #session.steps * MIN_STEP_TIME
	local sum = 0
	for _, s in ipairs(scores) do
		if not Util.isFiniteNumber(s) then
			Kitchen.unclaim(island, item)
			return { ok = false, err = "Неверный результат" }
		end
		sum += Util.clamp(s, 0, 1)
	end
	local skill = sum / #scores
	if elapsed < minTime then
		-- подозрительно быстро: результат резко снижается
		skill *= 0.3
	end
	local recipe = Recipes.ById[item.recipeId]
	local prof = session.kind == "dish" and "Cook" or (S.RestaurantService.roleOf(player) or "Cook")
	local bonus = 0
	if prof == "Cook" then
		bonus = Professions.cookQualityBonus(S.Economy.profLevel(player, "Cook"))
	end
	local quality = Kitchen.qualityFor(island, recipe, skill, bonus)
	Kitchen.complete(island, item, quality, player)
	-- награды
	local xp = 6 + #recipe.steps * 3 + recipe.stars * 2
	S.Economy.addProfXp(player, prof, math.floor(xp * (0.5 + skill)))
	S.Economy.addXp(player, 2 + recipe.stars)
	if recipe.kind == "dish" then
		S.QuestService.add(player, "dishesCooked", 1)
	else
		S.QuestService.add(player, "drinksMade", 1)
	end
	return { ok = true, quality = quality }
end

function Kitchen.onRoleChanged(island, player)
	local k = island.kitchen
	if k and k.sessions[player] then
		local session = k.sessions[player]
		local okRole = canCook(player, island, session.kind)
		if not okRole then
			k.sessions[player] = nil
			Kitchen.unclaim(island, session.item)
			Net.push(player, "cookCancel", {})
		end
	end
	if S.RestaurantService.roleOf(player) ~= "Waiter" then
		S.GuestService.dropCarry(island, player)
	end
end

function Kitchen.onMemberLeft(island, player)
	local k = island.kitchen
	if k and k.sessions[player] then
		Kitchen.unclaim(island, k.sessions[player].item)
		k.sessions[player] = nil
	end
	S.GuestService.dropCarry(island, player)
end

-- ===================== VISITORS =====================
function Kitchen.visitorMeal(island, player)
	if S.RestaurantService.isMember(player, island) then
		Net.toast(player, "Это ваш ресторан — обслуживайте гостей!", "info")
		return
	end
	if not island.owner then
		return
	end
	if not S.Economy.spend(player, Config.VisitorMealPrice, "Обед в ресторане " .. island.rest.name) then
		Net.toast(player, "Недостаточно денег", "warn")
		return
	end
	S.Economy.budgetCredit(island, Config.VisitorMealPrice, "sale", player.DisplayName, "Обед гостя-игрока")
	S.Economy.addXp(player, 15)
	island.rest.reputation = Util.clamp(island.rest.reputation + 0.3, 0, 100)
	Net.toast(player, "🍽️ Вкусно! +15 опыта", "success")
	Net.toast(island.owner, "🍽️ " .. player.DisplayName .. " пообедал в вашем ресторане!", "info")
end

-- ===================== VISUALS =====================
function Kitchen.refreshPassVisuals(island)
	local k = island.kitchen
	if not k then
		return
	end
	local counter = S.RestaurantService.buildingPart(island, "PassCounter")
	if not counter then
		return
	end
	local wanted = {}
	for i, item in ipairs(k.pass) do
		if i > 10 then
			break
		end
		wanted[item.uid] = i
	end
	for uid, v in pairs(k.visuals) do
		if not wanted[uid] then
			v:Destroy()
			k.visuals[uid] = nil
		end
	end
	local n = math.min(#k.pass, 10)
	for i = 1, n do
		local item = k.pass[i]
		local v = k.visuals[item.uid]
		local x = -counter.Size.X / 2 + 1.5 + (i - 1) * math.max(1.6, (counter.Size.X - 3) / math.max(n, 1))
		x = math.min(x, counter.Size.X / 2 - 1)
		local cf = counter.CFrame * CFrame.new(x, counter.Size.Y / 2 + 0.15, 0)
		if not v then
			v = Instance.new("Part")
			v.Name = "Plate"
			v.Shape = Enum.PartType.Cylinder
			v.Size = Vector3.new(0.2, 1.5, 1.5)
			v.Color = Color3.fromRGB(245, 245, 240)
			v.Material = Enum.Material.SmoothPlastic
			v.Anchored = true
			v.CanCollide = false
			v.CanQuery = false
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(34, 34)
			gui.StudsOffset = Vector3.new(0, 0.9, 0)
			gui.MaxDistance = 45
			gui.LightInfluence = 0
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.TextScaled = true
			t.Text = Recipes.ById[item.recipeId].icon
			t.Parent = gui
			gui.Parent = v
			v.Parent = island.building
			k.visuals[item.uid] = v
		end
		v.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function updateBoard(island)
	local k = island.kitchen
	local board = S.RestaurantService.buildingPart(island, "OrderBoard")
	local label = board and board:FindFirstChild("Queue", true)
	if not label then
		return
	end
	local lines = { "🧾 ЗАКАЗЫ" }
	local function add(list, prefix)
		local count = 0
		for _, it in ipairs(list) do
			count += 1
			if count <= 6 then
				local r = Recipes.ById[it.recipeId]
				local mark = it.status == "cooking" and "🔥 " or "• "
				table.insert(lines, prefix .. mark .. r.icon .. " " .. r.name)
			end
		end
		if count > 6 then
			table.insert(lines, "   ... и ещё " .. (count - 6))
		end
	end
	add(k.dishQueue, "")
	if #k.drinkQueue > 0 then
		table.insert(lines, "🥤 НАПИТКИ: " .. #k.drinkQueue)
	end
	if #k.pass > 0 then
		table.insert(lines, "✅ НА РАЗДАЧЕ: " .. #k.pass)
	end
	if #lines == 1 then
		table.insert(lines, "Заказов нет")
	end
	label.Text = table.concat(lines, "\n")
end

-- ===================== AUTO KITCHEN =====================
local function hasCookCapacity(island)
	return S.RestaurantService.playerInRole(island, "Cook") ~= nil or S.StaffService.hasStaff(island, "Cook")
end

function Kitchen.tick(island, dt)
	local k = island.kitchen
	if not k then
		return
	end
	local now = os.clock()
	-- session timeouts
	for player, session in pairs(k.sessions) do
		if now - session.started > SESSION_TIMEOUT or not player.Parent then
			k.sessions[player] = nil
			Kitchen.unclaim(island, session.item)
			if player.Parent then
				Net.push(player, "cookCancel", {})
			end
		end
	end
	-- auto kitchen (fallback when nobody can cook: slow & basic quality, more slots on higher tiers)
	k.autoDishes = k.autoDishes or {}
	if not hasCookCapacity(island) then
		for i = #k.autoDishes, 1, -1 do
			local job = k.autoDishes[i]
			if now >= job.doneAt then
				table.remove(k.autoDishes, i)
				local recipe = Recipes.ById[job.item.recipeId]
				Kitchen.complete(island, job.item, Config.AutoCookQuality * (0.7 + 0.3 * recipe.baseQuality) + Equipment.bonus(island.rest.equipment, "quality") * 0.5, nil)
			end
		end
		local slots = Config.AutoCookSlots[island.rest.stars] or 1
		while #k.autoDishes < slots do
			local item = Kitchen.claimNext(island, "dish", "auto")
			if not item then
				break
			end
			local recipe = Recipes.ById[item.recipeId]
			table.insert(k.autoDishes, { item = item, doneAt = now + (Config.AutoCookTime + recipe.time * 0.5) / Kitchen.cookSpeedMult(island, "dish") })
		end
	elseif #k.autoDishes > 0 then
		for _, job in ipairs(k.autoDishes) do
			Kitchen.unclaim(island, job.item)
		end
		k.autoDishes = {}
	end
	-- auto drinks machine (if no NPC bartender): two dispensers working in parallel
	k.autoDrinks = k.autoDrinks or {}
	if not S.StaffService.hasStaff(island, "Bartender") then
		for i = #k.autoDrinks, 1, -1 do
			local job = k.autoDrinks[i]
			if now >= job.doneAt then
				table.remove(k.autoDrinks, i)
				Kitchen.complete(island, job.item, Config.AutoDrinkQuality + Equipment.bonus(island.rest.equipment, "drinkQuality"), nil)
			end
		end
		while #k.autoDrinks < Config.AutoDrinkSlots do
			local item = Kitchen.claimNext(island, "drink", "auto")
			if not item then
				break
			end
			table.insert(k.autoDrinks, { item = item, doneAt = now + Config.AutoDrinkTime / Kitchen.cookSpeedMult(island, "drink") })
		end
	elseif #k.autoDrinks > 0 then
		for _, job in ipairs(k.autoDrinks) do
			Kitchen.unclaim(island, job.item)
		end
		k.autoDrinks = {}
	end
	-- food on the pass cools down
	for _, item in ipairs(k.pass) do
		if item.readyAt and now - item.readyAt > 25 and item.quality then
			item.quality = math.max(item.baseQuality * 0.6, item.quality - 0.004 * dt)
		end
	end
	if k.boardDirty then
		k.boardDirty = false
		updateBoard(island)
	end
end

function Kitchen.liveState(island)
	local k = island.kitchen
	if not k then
		return {}
	end
	local queue = {}
	for i, it in ipairs(k.dishQueue) do
		if i > 8 then
			break
		end
		table.insert(queue, { r = it.recipeId, s = it.status })
	end
	local drinks = {}
	for i, it in ipairs(k.drinkQueue) do
		if i > 6 then
			break
		end
		table.insert(drinks, { r = it.recipeId, s = it.status })
	end
	return {
		dishQueue = #k.dishQueue,
		drinkQueue = #k.drinkQueue,
		pass = #k.pass,
		queue = queue,
		drinks = drinks,
		autoKitchen = not hasCookCapacity(island),
		autoBar = not S.StaffService.hasStaff(island, "Bartender"),
	}
end

function Kitchen.Start()
	Net.onRequest("FinishCook", function(player, payload)
		return Kitchen.finishSession(player, payload)
	end)
	Net.onRequest("StartCook", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island or not island.kitchen then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local kind = payload and payload.kind == "drink" and "drink" or "dish"
		local part = S.RestaurantService.buildingPart(island, kind == "dish" and "OrderBoard" or "BarCounter")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not part or not root or (root.Position - part.Position).Magnitude > 40 then
			return { ok = false, err = kind == "dish" and "Подойдите к кухне" or "Подойдите к бару" }
		end
		Kitchen.startSession(island, player, kind)
		return { ok = true }
	end)
	Net.setRate("FinishCook", 2, 4)
	Net.setRate("StartCook", 2, 4)
	Players.PlayerRemoving:Connect(function(player)
		local island = S.RestaurantService.islandOf(player)
		if island then
			Kitchen.onMemberLeft(island, player)
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.5)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.owner and island.kitchen then
					local ok, err = pcall(Kitchen.tick, island, dt)
					if not ok then
						warn("[KitchenService] tick error: " .. tostring(err))
					end
				end
			end
		end
	end)
end

return Kitchen
