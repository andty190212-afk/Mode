-- GuestService: NPC guest parties (arrive, pick a free table, sit, read the menu,
-- order, wait, get food, eat, pay, tip, review, leave), waiter interactions
-- (take order, pick up, serve, clean), satisfaction, reviews and reputation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local MapLayout = require(Shared.MapLayout)
local Data = Shared.Data
local Guests = require(Data.Guests)
local Recipes = require(Data.Recipes)
local Stars = require(Data.Stars)
local Professions = require(Data.Professions)
local Furniture = require(Data.Furniture)
local Equipment = require(Data.Equipment)
local NPCUtil = require(script.Parent.NPCUtil)

local GuestService = {}
local S
local rng = Random.new()
local totalGuests = 0

local COLORS = {
	order = Color3.fromRGB(60, 130, 230),
	food = Color3.fromRGB(240, 170, 40),
	eat = Color3.fromRGB(70, 190, 90),
	angry = Color3.fromRGB(220, 60, 60),
	happy = Color3.fromRGB(70, 190, 90),
}

function GuestService.Init(registry)
	S = registry
end

-- ===================== SETUP =====================
function GuestService.setupIsland(island)
	island.guest = {
		tables = {}, -- [uid] = tableRt
		parties = {},
		nextId = 1,
		nextSpawn = os.clock() + 6,
		carrying = {}, -- [player] = {items}
		forcedQueue = {}, -- {"critic", "vip"}
	}
end

function GuestService.clearIsland(island)
	local g = island.guest
	if not g then
		return
	end
	for _, party in pairs(g.parties) do
		for _, m in ipairs(party.models) do
			NPCUtil.destroy(m)
		end
		totalGuests -= party.size
	end
	for player in pairs(g.carrying) do
		GuestService.setCarryVisual(player, {})
	end
	island.guest = nil
end

local function worldPoint(island, localX, localZ)
	-- island-local point on the surface
	return (island.cframe * CFrame.new(localX, 0, localZ)).Position
end

local function buildingPoint(island, x, z)
	return (island.buildingCF * CFrame.new(x, 0, z)).Position
end

-- Table registration (called by BuildService)
function GuestService.registerTable(island, entry, model)
	local g = island.guest
	if not g then
		return
	end
	local def = Furniture.ById[entry.id]
	if not def or not def.seats then
		return
	end
	local base = island.buildingCF * CFrame.new(entry.x, 0, entry.z) * CFrame.Angles(0, math.rad(entry.r or 0), 0)
	local seats = {}
	for _, s in ipairs(def.seats) do
		-- гость сидит лицом к центру стола
		local pos = (base * CFrame.new(s[1], 0, s[2])).Position
		local center = base.Position
		local dir = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
		if dir.Magnitude < 0.01 then
			dir = base.LookVector
		end
		table.insert(seats, CFrame.lookAt(pos, pos + dir.Unit))
	end
	local rt = { uid = entry.uid, entry = entry, model = model, seats = seats, state = "free", base = base }
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TablePrompt"
	prompt.ObjectText = def.name
	prompt.ActionText = "Стол свободен"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("Role", "Waiter")
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		GuestService.onTablePrompt(island, rt, player)
	end)
	rt.prompt = prompt
	g.tables[entry.uid] = rt
end

function GuestService.unregisterTable(island, uid)
	local g = island.guest
	local rt = g and g.tables[uid]
	if not rt then
		return
	end
	if rt.party then
		GuestService.partyLeave(island, rt.party, nil, true)
	end
	g.tables[uid] = nil
end

function GuestService.tableBusy(island, uid)
	local g = island.guest
	local rt = g and g.tables[uid]
	return rt ~= nil and rt.state ~= "free"
end

local function setPrompt(rt, text)
	if not rt.prompt then
		return
	end
	if text then
		rt.prompt.ActionText = text
		rt.prompt.Enabled = true
	else
		rt.prompt.Enabled = false
	end
	rt.prompt:SetAttribute("Active", text ~= nil)
end

-- ===================== METRICS =====================
function GuestService.liveState(island)
	local g = island.guest
	if not g then
		return {}
	end
	local guests, waitOrder, waitFood, eating, dirtyTables, seats, tables, queued = 0, 0, 0, 0, 0, 0, 0, 0
	for _, rt in pairs(g.tables) do
		tables += 1
		seats += #rt.seats
		if rt.state == "dirty" then
			dirtyTables += 1
		end
	end
	for _, p in pairs(g.parties) do
		guests += p.size
		if p.state == "order" then
			waitOrder += 1
		elseif p.state == "food" then
			waitFood += 1
		elseif p.state == "eat" then
			eating += 1
		elseif p.state == "queue" then
			queued += 1
		end
	end
	local carry = {}
	for player, items in pairs(g.carrying) do
		local list = {}
		for _, it in ipairs(items) do
			table.insert(list, it.recipeId)
		end
		carry[tostring(player.UserId)] = list
	end
	return {
		guests = guests,
		waitOrder = waitOrder,
		waitFood = waitFood,
		eating = eating,
		dirtyTables = dirtyTables,
		seats = seats,
		tables = tables,
		queue = queued,
		carrying = carry,
	}
end

function GuestService.seatCap(island)
	return Stars.Levels[island.rest.stars].maxGuestsSeats
end

-- ===================== SPAWNING =====================
local function pickGuestType(island)
	local g = island.guest
	if #g.forcedQueue > 0 then
		return Guests.ById[table.remove(g.forcedQueue, 1)]
	end
	local stars = island.rest.stars
	local pool = {}
	for _, t in ipairs(Guests.Types) do
		if t.weight > 0 and t.minStars <= stars then
			local w = t.weight
			if t.id == "vip" or t.id == "rich" then
				w *= 1 + (stars - t.minStars) * 0.5
			end
			table.insert(pool, { t = t, w = w })
		end
	end
	-- редкий случайный критик
	if stars >= 2 and rng:NextNumber() < 0.012 then
		return Guests.ById.critic
	end
	local choice = Util.weightedChoice(pool, "w", rng)
	return choice and choice.t or Guests.ById.regular
end

local function findTable(island, size)
	local best, bestSeats = nil, math.huge
	for _, rt in pairs(island.guest.tables) do
		if rt.state == "free" and #rt.seats >= size and #rt.seats < bestSeats then
			best, bestSeats = rt, #rt.seats
		end
	end
	return best
end

local function menuAvailable(island)
	local ctx = { chefActive = S.RestaurantService.chefActive(island) }
	local list = {}
	for _, r in ipairs(Recipes.List) do
		local m = island.rest.menu[r.id]
		if m and m.on and Recipes.isAvailable(r, island.rest, ctx) and Recipes.hasStock(r, island.rest.inventory) then
			table.insert(list, r)
		end
	end
	return list
end
GuestService.menuAvailable = menuAvailable

function GuestService.spawnInterval(island)
	local rest = island.rest
	local lvl = Stars.Levels[rest.stars]
	local repFactor = 0.45 + rest.reputation / 90
	local mult = lvl.spawnMult * repFactor * S.EventService.guestMultiplier(island)
	if S.RestaurantService.isIdle(island) then
		mult *= Config.IdleGuestMult -- команда неактивна: гостей намного меньше
	end
	return Config.BaseSpawnInterval / math.max(0.2, mult)
end

local function seatedGuests(island)
	local n = 0
	for _, p in pairs(island.guest.parties) do
		if p.state ~= "queue" then
			n += p.size
		end
	end
	return n
end

local function queueCount(island)
	local n = 0
	for _, p in pairs(island.guest.parties) do
		if p.state == "queue" then
			n += 1
		end
	end
	return n
end
GuestService.queueCount = queueCount

-- queue spots in front of the door (building local coords)
local function queuePoint(island, slot, member)
	return buildingPoint(island, -2.2 + (member - 1) * 1.6, 5 + slot * 3.2)
end

-- send the party from where it stands to its table
local function walkToTable(island, party, rt, firstPoints)
	local g = island.guest
	party.table = rt
	rt.state = "reserved"
	rt.party = party
	party.state = "walk"
	party.spawnedAt = os.clock()
	local door = buildingPoint(island, 0, 2)
	local inside = buildingPoint(island, 0, -5)
	local arrived = 0
	for i, model in ipairs(party.models) do
		local seatCf = rt.seats[i] or rt.seats[1]
		local approach = (seatCf * CFrame.new(0, 0, 2.2)).Position
		local points = {}
		for _, pt in ipairs(firstPoints(i)) do
			table.insert(points, pt)
		end
		for _, pt in ipairs({ door, inside, approach, seatCf.Position }) do
			table.insert(points, pt)
		end
		task.delay((i - 1) * 0.5, function()
			party.walkHandle = NPCUtil.walk(model, points, 11, function()
				if g.parties[party.id] ~= party then
					return
				end
				NPCUtil.sit(model, seatCf * CFrame.new(0, 2.4, 0))
				arrived += 1
				if arrived >= #party.models then
					GuestService.seat(island, party)
				end
			end)
		end)
	end
end

function GuestService.trySpawn(island)
	local g = island.guest
	if totalGuests >= Config.MaxGuestsGlobal then
		return
	end
	if not island.building then
		return
	end
	local gtype = pickGuestType(island)
	local size = rng:NextInteger(gtype.party[1], gtype.party[2])
	local maxParty = Stars.Levels[island.rest.stars].maxParty
	if maxParty then
		size = math.min(size, maxParty) -- в маленьких заведениях компании меньше
	end
	local cap = GuestService.seatCap(island)
	local rt
	if seatedGuests(island) + size <= cap then
		rt = findTable(island, size)
	end
	if not rt and seatedGuests(island) + 1 <= cap and gtype.party[1] <= 1 and rng:NextNumber() < 0.5 then
		rt = findTable(island, 1)
		if rt then
			size = math.min(size, #rt.seats, cap - seatedGuests(island))
		end
	end
	local slot = queueCount(island) + 1
	if not rt and slot > (Config.QueueMax[island.rest.stars] or 2) then
		return -- мест нет и очередь заполнена
	end
	if #menuAvailable(island) == 0 then
		if not island.warnedNoMenu or os.clock() - island.warnedNoMenu > 60 then
			island.warnedNoMenu = os.clock()
			for _, m in ipairs(S.RestaurantService.membersOf(island)) do
				Net.toast(m, "⚠️ Гостям нечего заказать: закупите продукты или включите блюда в меню", "warn")
			end
		end
		return
	end
	local id = g.nextId
	g.nextId += 1
	local party = {
		id = id,
		type = gtype,
		size = size,
		table = nil,
		models = {},
		state = "walk",
		stateStart = os.clock(),
		items = {},
		name = Guests.Names[rng:NextInteger(1, #Guests.Names)],
		spawnedAt = os.clock(),
	}
	g.parties[id] = party
	totalGuests += size

	local dock = island.model:FindFirstChild("DockEnd")
	local start = dock and dock.Position or worldPoint(island, 0, MapLayout.IslandRadius + 20)
	local pathOut = worldPoint(island, 0, MapLayout.BuildingOffsetZ + 12)
	local offsets = {}
	for i = 1, size do
		offsets[i] = Vector3.new((i - 1) * 2.2 - (size - 1) * 1.1, 0, 0)
		local model = NPCUtil.spawn("Guest", CFrame.new(start + offsets[i] + Vector3.new(0, 3, 0)), {
			vip = gtype.vip,
			critic = gtype.critic,
			guestType = gtype.id,
			stars = island.rest.stars,
			rng = rng,
		})
		model.Name = "Guest_" .. gtype.id
		table.insert(party.models, model)
	end
	if rt then
		walkToTable(island, party, rt, function(i)
			return { start + offsets[i], pathOut + offsets[i] * 0.5 }
		end)
	else
		-- ждать в очереди у входа
		party.state = "queue"
		party.queueSlot = slot
		party.stateStart = os.clock()
		NPCUtil.bubble(party.models[1], gtype.icon .. " ⏳ Жду столик", Color3.fromRGB(150, 150, 170))
		for i, model in ipairs(party.models) do
			task.delay((i - 1) * 0.5, function()
				party.walkHandle = NPCUtil.walk(model, { start + offsets[i], queuePoint(island, slot, i) }, 11)
			end)
		end
	end
	if gtype.critic then
		for _, m in ipairs(S.RestaurantService.membersOf(island)) do
			Net.toast(m, "📝 Ресторанный критик пришёл! Обслужите его идеально.", "warn")
		end
	elseif gtype.vip then
		for _, m in ipairs(S.RestaurantService.membersOf(island)) do
			Net.toast(m, "👑 VIP-гость в ресторане! Большие чаевые за отличный сервис.", "info")
		end
	end
	S.RestaurantService.markDirty(island)
end

-- queued parties take freed tables (first come, first served) or give up
local function processQueue(island, now)
	local g = island.guest
	local queued = {}
	for _, p in pairs(g.parties) do
		if p.state == "queue" then
			table.insert(queued, p)
		end
	end
	table.sort(queued, function(a, b)
		return a.stateStart < b.stateStart
	end)
	local cap = GuestService.seatCap(island)
	for _, party in ipairs(queued) do
		if now - party.stateStart > Config.QueuePatience then
			NPCUtil.bubble(party.models[1], "😕 Долго ждать...", Color3.fromRGB(200, 120, 60))
			GuestService.partyLeave(island, party, "queue")
		elseif seatedGuests(island) + party.size <= cap then
			local rt = findTable(island, party.size)
			if rt then
				NPCUtil.bubble(party.models[1], nil)
				walkToTable(island, party, rt, function(i)
					return {}
				end)
			end
		end
	end
	-- подтянуть очередь вперёд
	local slot = 0
	for _, party in ipairs(queued) do
		if party.state == "queue" and g.parties[party.id] == party then
			slot += 1
			if party.queueSlot ~= slot then
				party.queueSlot = slot
				for i, model in ipairs(party.models) do
					if party.walkHandle then
						party.walkHandle:Cancel()
					end
					party.walkHandle = NPCUtil.walk(model, { queuePoint(island, slot, i) }, 8)
				end
			end
		end
	end
end
GuestService.processQueue = processQueue

-- ===================== PARTY STATES =====================
local function patienceFor(island, party, stage)
	local base = Guests.Patience[stage] or 60
	local interiorBonus = 1 + math.min(0.25, S.BuildService.beautyScore(island) / 2000)
	return base * party.type.patience * interiorBonus
end

local function leader(party)
	return party.models[1]
end

function GuestService.seat(island, party)
	party.state = "order"
	party.stateStart = os.clock()
	party.patience = patienceFor(island, party, "order")
	party.table.state = "occupied"
	NPCUtil.bubble(leader(party), party.type.icon .. " 📋", COLORS.order)
	setPrompt(party.table, "Принять заказ")
	-- если официантов нет совсем — гость закажет сам через планшет
	S.RestaurantService.markDirty(island)
end

local function hasWaiter(island)
	return S.RestaurantService.playerInRole(island, "Waiter") ~= nil or S.StaffService.hasStaff(island, "Waiter")
end
GuestService.hasWaiter = hasWaiter

local function choosePriceWeighted(island, party, list, budget)
	local candidates = {}
	for _, r in ipairs(list) do
		local m = island.rest.menu[r.id]
		local price = r.price * (m and m.price or 1)
		local ratio = price / budget
		if ratio <= 1.8 then
			local w = 1 / (0.35 + math.abs(ratio - 0.85))
			-- дорогие наценки отпугивают чувствительных к цене
			local mult = m and m.price or 1
			if mult > 1 then
				w *= math.max(0.05, 1 - (mult - 1) * party.type.priceSense)
			elseif mult < 1 then
				w *= 1 + (1 - mult) * 0.6
			end
			if r.stars >= island.rest.stars - 1 then
				w *= 1.3 -- новые блюда интереснее
			end
			table.insert(candidates, { r = r, w = w, price = price })
		end
	end
	local c = Util.weightedChoice(candidates, "w", rng)
	return c
end

-- Create the order for a party (waiter / NPC / tablet)
function GuestService.placeOrder(island, party, takenBy)
	if not island.rest or not island.guest or party.state ~= "order" then
		return false
	end
	local list = menuAvailable(island)
	local dishes, drinks = {}, {}
	for _, r in ipairs(list) do
		if r.kind == "dish" then
			table.insert(dishes, r)
		else
			table.insert(drinks, r)
		end
	end
	local starBudget = Stars.Levels[island.rest.stars].guestBudget
	local budget = 40 * party.type.budget * starBudget
	local items = {}
	local special = S.EventService.specialDish(island)
	local reserved = {}
	local function reserveOk(r)
		for id, n in pairs(r.ing) do
			if (island.rest.inventory[id] or 0) < (reserved[id] or 0) + n then
				return false
			end
		end
		for id, n in pairs(r.ing) do
			reserved[id] = (reserved[id] or 0) + n
		end
		return true
	end
	for i = 1, party.size do
		local choice
		if i == 1 and special and Recipes.ById[special] and table.find(dishes, Recipes.ById[special]) then
			local r = Recipes.ById[special]
			local m = island.rest.menu[r.id]
			choice = { r = r, price = r.price * (m and m.price or 1) * 2, special = true }
		else
			choice = choosePriceWeighted(island, party, dishes, budget)
		end
		if choice and reserveOk(choice.r) then
			table.insert(items, { recipeId = choice.r.id, kind = "dish", price = choice.price, special = choice.special })
		end
		if rng:NextNumber() < party.type.drinkChance then
			local d = choosePriceWeighted(island, party, drinks, budget * 0.35)
			if d and reserveOk(d.r) then
				table.insert(items, { recipeId = d.r.id, kind = "drink", price = d.price })
			end
		end
	end
	if #items == 0 then
		-- слишком дорого или нечего выбрать
		island.rest.stats.priceEma = Util.lerp(island.rest.stats.priceEma, 0.2, 0.1)
		NPCUtil.bubble(leader(party), "💸 Слишком дорого!", COLORS.angry)
		GuestService.partyLeave(island, party, "price")
		return false
	end
	party.items = {}
	for _, it in ipairs(items) do
		local item = S.KitchenService.enqueue(island, it.recipeId, it.price, party.id)
		item.special = it.special
		table.insert(party.items, item)
	end
	party.state = "food"
	party.orderWait = os.clock() - party.stateStart
	party.stateStart = os.clock()
	party.patience = patienceFor(island, party, "food")
	party.takenBy = takenBy
	local icons = {}
	for _, it in ipairs(party.items) do
		table.insert(icons, Recipes.ById[it.recipeId].icon)
	end
	NPCUtil.bubble(leader(party), table.concat(icons, ""), COLORS.food)
	setPrompt(party.table, "Подать блюда")
	S.RestaurantService.markDirty(island)
	return true
end

local function partyFor(island, id)
	return island.guest and island.guest.parties[id]
end
GuestService.partyFor = partyFor

-- An item was delivered to the party (by player waiter, NPC waiter, or self-pickup)
function GuestService.deliverItem(island, item, servedBy, selfServe)
	if not island.rest then
		return false
	end
	local party = partyFor(island, item.partyId)
	if not party or party.state ~= "food" then
		return false
	end
	item.status = "served"
	item.servedBy = servedBy
	item.selfServe = selfServe
	item.servedAt = os.clock()
	S.KitchenService.removeFromPass(island, item)
	local remaining = 0
	for _, it in ipairs(party.items) do
		if it.status ~= "served" and it.status ~= "failed" then
			remaining += 1
		end
	end
	if remaining == 0 then
		GuestService.startEating(island, party)
	else
		S.RestaurantService.markDirty(island)
	end
	return true
end

function GuestService.itemFailed(island, item)
	local party = partyFor(island, item.partyId)
	if not party then
		return
	end
	item.status = "failed"
	local remaining, served = 0, 0
	for _, it in ipairs(party.items) do
		if it.status == "served" then
			served += 1
		elseif it.status ~= "failed" then
			remaining += 1
		end
	end
	if remaining == 0 then
		if served > 0 then
			GuestService.startEating(island, party)
		else
			NPCUtil.bubble(leader(party), "😡 Нет продуктов!", COLORS.angry)
			GuestService.partyLeave(island, party, "nostock")
		end
	end
end

function GuestService.startEating(island, party)
	party.state = "eat"
	party.foodWait = os.clock() - party.stateStart
	party.stateStart = os.clock()
	NPCUtil.bubble(leader(party), "😋 🍽️", COLORS.eat)
	NPCUtil.patience(leader(party), 1)
	setPrompt(party.table, nil)
	S.RestaurantService.markDirty(island)
end

-- ===================== PAYMENT & REVIEW =====================
local function pickReview(sat)
	local pool = sat >= 0.72 and Guests.ReviewTexts.good or (sat >= 0.5 and Guests.ReviewTexts.ok or Guests.ReviewTexts.bad)
	return pool[rng:NextInteger(1, #pool)]
end

function GuestService.finishParty(island, party)
	local rest = island.rest
	local stats = rest.stats
	local served = {}
	local qualitySum, total, priceMultSum = 0, 0, 0
	local selfServed = 0
	for _, it in ipairs(party.items) do
		if it.status == "served" then
			table.insert(served, it)
			qualitySum += it.quality or 0.5
			total += it.price
			local m = rest.menu[it.recipeId]
			priceMultSum += m and m.price or 1
			if it.selfServe then
				selfServed += 1
			end
		end
	end
	if #served == 0 then
		GuestService.partyLeave(island, party, "nostock")
		return
	end
	local food = qualitySum / #served
	local failedCount = #party.items - #served
	food -= failedCount * 0.1
	local foodPatience = patienceFor(island, party, "food")
	local speed = Util.clamp(1 - math.max(0, (party.foodWait or 0) - 35) / foodPatience, 0, 1)
	local orderSpeed = Util.clamp(1 - math.max(0, (party.orderWait or 0) - 12) / patienceFor(island, party, "order"), 0, 1)
	speed = speed * 0.75 + orderSpeed * 0.25
	local avgMult = priceMultSum / #served
	local price = Util.clamp(1.15 - (avgMult - 1) * party.type.priceSense * 0.9, 0, 1)
	local beauty = S.BuildService.beautyScore(island)
	local expectedBeauty = 30 * rest.stars ^ 1.7
	local ambience = Util.clamp(beauty / expectedBeauty, 0, 1) * 0.65 + (rest.cleanliness / 100) * 0.35
	local service = selfServed == #served and 0.45 or (selfServed > 0 and 0.7 or 0.95)
	local sat = 0.36 * food + 0.22 * speed + 0.14 * price + 0.16 * ambience + 0.12 * service
	if food < party.type.demand then
		sat -= (party.type.demand - food) * 0.45
	end
	sat = Util.clamp(sat, 0, 1)

	-- money: revenue to budget minus worker shares; tips
	local shares = {}
	local budgetPart = 0
	for _, it in ipairs(served) do
		local share = it.price * Config.WorkerShare
		local cookPlayer = it.cookedBy and Players:GetPlayerByUserId(it.cookedBy)
		local waiterPlayer = it.servedBy and Players:GetPlayerByUserId(it.servedBy)
		local cut = 0
		if cookPlayer and S.RestaurantService.isMember(cookPlayer, island) then
			shares[cookPlayer] = (shares[cookPlayer] or 0) + share * 0.6
			cut += share * 0.6
		end
		if waiterPlayer and S.RestaurantService.isMember(waiterPlayer, island) then
			shares[waiterPlayer] = (shares[waiterPlayer] or 0) + share * 0.4
			cut += share * 0.4
		end
		budgetPart += it.price - cut
	end
	S.Economy.budgetIncome(island, budgetPart, "sale", "Гости", "Продажи")
	for player, amount in pairs(shares) do
		S.Economy.earn(player, amount, "Работа")
	end
	-- tips go to the player waiter who served most items
	local tipBase = total * party.type.tip * (0.3 + 1.4 * sat * sat)
	local waiterCounts = {}
	for _, it in ipairs(served) do
		if it.servedBy and not it.selfServe then
			waiterCounts[it.servedBy] = (waiterCounts[it.servedBy] or 0) + 1
		end
	end
	local bestWaiter, bestCount = nil, 0
	for uid, c in pairs(waiterCounts) do
		if c > bestCount then
			bestWaiter, bestCount = uid, c
		end
	end
	local tipPlayer = bestWaiter and Players:GetPlayerByUserId(bestWaiter)
	if selfServed == #served then
		tipBase *= Config.SelfServeTipMult
	end
	local tip = 0
	if tipPlayer and S.RestaurantService.isMember(tipPlayer, island) then
		tip = tipBase * Professions.waiterTipMult(S.Economy.profLevel(tipPlayer, "Waiter"))
		tip = S.Economy.earn(tipPlayer, tip, "Чаевые")
		S.QuestService.add(tipPlayer, "tipsEarned", tip)
		S.Economy.addProfXp(tipPlayer, "Waiter", 4 + party.size * 2)
		Net.fx(tipPlayer, "money", { amount = tip, text = "Чаевые", pos = leader(party).PrimaryPart.Position })
	elseif tipBase > 0 then
		tip = S.Economy.budgetIncome(island, tipBase, "sale", "Гости", "Чаевые")
	end
	stats.tips += tip

	-- stats & EMAs
	local a = 0.08
	stats.served += party.size
	stats.satisfactionEma = Util.lerp(stats.satisfactionEma, sat, a)
	stats.foodEma = Util.lerp(stats.foodEma, food, a)
	stats.speedEma = Util.lerp(stats.speedEma, speed, a)
	stats.priceEma = Util.lerp(stats.priceEma, price, a)
	stats.serviceEma = Util.lerp(stats.serviceEma, service, a)
	stats.interiorEma = Util.lerp(stats.interiorEma, ambience, a)
	for _, it in ipairs(served) do
		if it.kind == "dish" then
			stats.dishesSold += 1
		else
			stats.drinksSold += 1
		end
	end
	if party.type.vip then
		stats.vipServed += 1
	end

	-- review
	local starsGiven = Util.clamp(math.floor(1 + sat * 4.6), 1, 5)
	stats.reviewCount += 1
	stats.reviewSum += starsGiven
	local review = {
		t = os.time(),
		n = party.name,
		g = party.type.id,
		s = starsGiven,
		txt = pickReview(sat),
		food = math.floor(food * 50 + 0.5) / 10,
		service = math.floor(service * 50 + 0.5) / 10,
		interior = math.floor(ambience * 50 + 0.5) / 10,
		speed = math.floor(speed * 50 + 0.5) / 10,
		price = math.floor(price * 50 + 0.5) / 10,
	}
	-- reputation
	local repDelta = (sat - 0.55) * 3.2 * party.type.rep
	if party.type.critic then
		local passed = sat >= 0.74 and food >= 0.68
		review.critic = true
		if passed then
			stats.criticsPassed += 1
			repDelta = 8
			review.txt = "Профессиональный отзыв: великолепная кухня и сервис. Рекомендую!"
			S.Economy.budgetCredit(island, 600 * rest.stars, "event", "Критик", "Премия критика")
			for _, m in ipairs(S.RestaurantService.membersOf(island)) do
				Net.toast(m, "📝✅ Критик в восторге! +8 репутации и премия $" .. (600 * rest.stars), "success")
				S.QuestService.add(m, "criticsPassed", 1)
			end
		else
			stats.criticsFailed += 1
			repDelta = -6
			island.criticPenaltyUntil = os.clock() + 300
			review.txt = "Профессиональный отзыв: разочарование. Кухне и залу есть над чем работать."
			for _, m in ipairs(S.RestaurantService.membersOf(island)) do
				Net.toast(m, "📝❌ Критик недоволен. Репутация -6, гостей временно меньше.", "error")
			end
		end
	end
	rest.reputation = Util.clamp(rest.reputation + repDelta, 0, 100)
	table.insert(rest.reviews, 1, review)
	while #rest.reviews > 25 do
		table.remove(rest.reviews)
	end
	rest.cleanliness = Util.clamp(rest.cleanliness - 0.6 * party.size, 0, 100)

	-- quests / xp for the team
	for _, m in ipairs(S.RestaurantService.membersOf(island)) do
		S.QuestService.add(m, "guestsServed", party.size)
		if starsGiven >= 4 then
			S.QuestService.add(m, "happyGuests", party.size)
		end
		if party.type.vip then
			S.QuestService.add(m, "vipServed", 1)
		end
		S.Economy.addXp(m, 3 * party.size + math.floor(total / 10))
		local role = S.RestaurantService.roleOf(m)
		if role == "Director" or role == "Chef" then
			S.Economy.addProfXp(m, role, 3 + party.size)
		end
	end
	local face = starsGiven >= 4 and "😍" or (starsGiven == 3 and "🙂" or "😕")
	NPCUtil.bubble(leader(party), face .. " " .. string.rep("★", starsGiven), starsGiven >= 3 and COLORS.happy or COLORS.angry)
	Net.fxAll("coins", { pos = leader(party).PrimaryPart.Position, amount = math.floor(total + tip) })
	GuestService.partyLeave(island, party, nil, false, true)
end

-- ===================== LEAVE =====================
function GuestService.partyLeave(island, party, reason, instant, paid)
	local g = island.guest
	if not g or g.parties[party.id] ~= party then
		return
	end
	g.parties[party.id] = nil
	totalGuests -= party.size
	local rest = island.rest
	-- cancel kitchen items
	for _, it in ipairs(party.items) do
		if it.status ~= "served" then
			S.KitchenService.cancelItem(island, it)
		end
	end
	local wasQueued = party.state == "queue"
	if reason == "queue" then
		rest.reputation = Util.clamp(rest.reputation - 0.2, 0, 100) -- не дождались столика
	end
	if reason == "angry" or reason == "nostock" or reason == "price" then
		rest.stats.lost += party.size
		local penalty = (reason == "price" and 0.8 or 2.2) * party.type.rep
		rest.reputation = Util.clamp(rest.reputation - penalty, 0, 100)
		rest.stats.satisfactionEma = Util.lerp(rest.stats.satisfactionEma, 0.1, 0.06)
		if reason == "angry" then
			rest.stats.speedEma = Util.lerp(rest.stats.speedEma, 0, 0.08)
			table.insert(rest.reviews, 1, { t = os.time(), n = party.name, g = party.type.id, s = 1, txt = "Очень долго ждали, ушли голодными.", food = 0, service = 1, interior = 2.5, speed = 0, price = 2.5 })
			while #rest.reviews > 25 do
				table.remove(rest.reviews)
			end
		end
		if party.type.critic then
			rest.stats.criticsFailed += 1
			rest.reputation = Util.clamp(rest.reputation - 6, 0, 100)
			island.criticPenaltyUntil = os.clock() + 300
		end
	end
	local rt = party.table
	if rt and rt.party == party then
		rt.party = nil
		if paid then
			rt.state = "dirty"
			rt.dirtySince = os.clock()
			setPrompt(rt, "Убрать стол")
			GuestService.showDirty(rt, true)
		else
			rt.state = "free"
			setPrompt(rt, nil)
		end
	end
	if party.walkHandle then
		party.walkHandle:Cancel()
	end
	if instant or not island.building then
		for _, m in ipairs(party.models) do
			NPCUtil.destroy(m)
		end
	else
		local dock = island.model:FindFirstChild("DockEnd")
		local endPoint = dock and dock.Position or worldPoint(island, 0, MapLayout.IslandRadius + 20)
		local door = buildingPoint(island, 0, 2)
		local inside = buildingPoint(island, 0, -5)
		local pathOut = worldPoint(island, 0, MapLayout.BuildingOffsetZ + 12)
		if reason == "angry" then
			NPCUtil.bubble(party.models[1], "😡 Ухожу!", COLORS.angry)
		end
		for i, m in ipairs(party.models) do
			task.delay(1.5 + i * 0.4, function()
				if not m.Parent then
					return
				end
				local approach = (rt and rt.seats[i] and (rt.seats[i] * CFrame.new(0, 0, 2.2)).Position) or inside
				local route = { approach, inside, door, pathOut, endPoint }
				if wasQueued then
					route = { pathOut, endPoint }
				end
				NPCUtil.walk(m, route, 12, function()
					NPCUtil.destroy(m)
				end)
				task.delay(40, function()
					NPCUtil.destroy(m)
				end)
			end)
		end
	end
	S.RestaurantService.markDirty(island)
end

function GuestService.showDirty(rt, on)
	local existing = rt.model:FindFirstChild("DirtyDishes")
	if on and not existing then
		local p = Instance.new("Part")
		p.Name = "DirtyDishes"
		p.Size = Vector3.new(1.6, 0.25, 1.6)
		p.Shape = Enum.PartType.Cylinder
		p.Color = Color3.fromRGB(225, 225, 215)
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		local top = rt.model:FindFirstChild("Top")
		local y = top and (top.Position.Y + top.Size.Y / 2 + 0.15) or (rt.base.Position.Y + 3.2)
		p.CFrame = CFrame.new(rt.base.Position.X, y, rt.base.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = rt.model
		local crumbs = Instance.new("ParticleEmitter")
		crumbs.Rate = 0.6
		crumbs.Lifetime = NumberRange.new(1.5)
		crumbs.Speed = NumberRange.new(0.5)
		crumbs.Size = NumberSequence.new(0.25)
		crumbs.Color = ColorSequence.new(Color3.fromRGB(140, 120, 90))
		crumbs.Parent = p
	elseif not on and existing then
		existing:Destroy()
	end
end

function GuestService.cleanTable(island, rt, by)
	if not island.rest or rt.state ~= "dirty" then
		return false
	end
	rt.state = "free"
	rt.dirtySince = nil
	setPrompt(rt, nil)
	GuestService.showDirty(rt, false)
	local gain = 3 * (1 + Equipment.bonus(island.rest.equipment, "cleanSpeed"))
	island.rest.cleanliness = Util.clamp(island.rest.cleanliness + gain, 0, 100)
	S.RestaurantService.markDirty(island)
	return true
end

-- ===================== WAITER (PLAYER) =====================
function GuestService.setCarryVisual(player, items)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild("CarryGui")
	if #items == 0 then
		if gui then
			gui:Destroy()
		end
		local tray = char:FindFirstChild("ServingTray")
		if tray then
			tray:Destroy()
		end
		return
	end
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "CarryGui"
		gui.Size = UDim2.fromOffset(120, 32)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(255, 250, 235)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = label
		gui.Parent = head
	end
	local icons = {}
	for _, it in ipairs(items) do
		table.insert(icons, Recipes.ById[it.recipeId].icon)
	end
	gui.Label.Text = "🛎️ " .. table.concat(icons, " ")
	local tray = char:FindFirstChild("ServingTray")
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not tray and hand then
		tray = Instance.new("Part")
		tray.Name = "ServingTray"
		tray.Size = Vector3.new(0.2, 2.2, 2.2)
		tray.Shape = Enum.PartType.Cylinder
		tray.Color = Color3.fromRGB(190, 190, 200)
		tray.Material = Enum.Material.Metal
		tray.CanCollide = false
		tray.Massless = true
		tray.CanQuery = false
		local w = Instance.new("Weld")
		w.Part0 = hand
		w.Part1 = tray
		w.C0 = CFrame.new(0, -hand.Size.Y / 2, -0.6) * CFrame.Angles(0, 0, math.rad(90))
		w.Parent = tray
		tray.Parent = char
	end
end

function GuestService.carrying(island, player)
	local g = island.guest
	return g and g.carrying[player] or {}
end

function GuestService.pickUp(island, player)
	local g = island.guest
	if not g then
		return false
	end
	local carry = g.carrying[player] or {}
	local cap = Professions.waiterCarry(S.Economy.profLevel(player, "Waiter"))
	if #carry >= cap then
		Net.toast(player, "Руки заняты (макс. " .. cap .. ")", "warn")
		return false
	end
	local taken = 0
	for _, item in ipairs(S.KitchenService.readyItems(island)) do
		if #carry >= cap then
			break
		end
		if not item.carriedBy then
			item.carriedBy = player.UserId
			table.insert(carry, item)
			S.KitchenService.removeFromPass(island, item, true)
			taken += 1
		end
	end
	g.carrying[player] = carry
	GuestService.setCarryVisual(player, carry)
	if taken == 0 then
		Net.toast(player, "На раздаче нет готовых блюд", "info")
	end
	S.RestaurantService.markDirty(island)
	return taken > 0
end

function GuestService.dropCarry(island, player)
	local g = island.guest
	if not g or not g.carrying[player] then
		return
	end
	for _, item in ipairs(g.carrying[player]) do
		item.carriedBy = nil
		if item.status == "ready" then
			S.KitchenService.returnToPass(island, item)
		end
	end
	g.carrying[player] = nil
	GuestService.setCarryVisual(player, {})
end

function GuestService.onTablePrompt(island, rt, player)
	S.RestaurantService.touch(player)
	if not S.RestaurantService.isMember(player, island) then
		Net.toast(player, "Это не ваш ресторан", "warn")
		return
	end
	local role = S.RestaurantService.roleOf(player)
	if role ~= "Waiter" then
		Net.toast(player, "Обслуживать столы может только официант", "warn")
		return
	end
	local party = rt.party
	if rt.state == "dirty" then
		if GuestService.cleanTable(island, rt, player) then
			S.QuestService.add(player, "tablesCleaned", 1)
			S.Economy.addProfXp(player, "Waiter", 3)
			S.Economy.earn(player, 2 + island.rest.stars, "Уборка")
			Net.fx(player, "sparkle", { pos = rt.base.Position })
		end
		return
	end
	if not party then
		return
	end
	if party.state == "order" then
		if GuestService.placeOrder(island, party, player.UserId) then
			S.QuestService.add(player, "ordersTaken", 1)
			S.Economy.addProfXp(player, "Waiter", 5)
			S.Economy.addXp(player, 3)
			Net.fx(player, "ding", {})
		end
	elseif party.state == "food" then
		local carry = island.guest.carrying[player] or {}
		local delivered = 0
		for i = #carry, 1, -1 do
			local item = carry[i]
			if item.partyId == party.id then
				table.remove(carry, i)
				item.carriedBy = nil
				if GuestService.deliverItem(island, item, player.UserId, false) then
					delivered += 1
				end
			end
		end
		GuestService.setCarryVisual(player, carry)
		if delivered == 0 then
			Net.toast(player, "У вас нет блюд для этого стола. Заберите их на раздаче.", "info")
		else
			S.Economy.addProfXp(player, "Waiter", 3 * delivered)
			Net.fx(player, "ding", {})
		end
	end
end

-- ===================== TICK =====================
function GuestService.tick(island, dt)
	local g = island.guest
	if not g or not island.owner then
		return
	end
	local now = os.clock()
	-- spawn
	if now >= g.nextSpawn then
		g.nextSpawn = now + GuestService.spawnInterval(island) * rng:NextNumber(0.7, 1.3)
		GuestService.trySpawn(island)
	end
	processQueue(island, now)
	local waiterPresent = hasWaiter(island)
	for _, party in pairs(g.parties) do
		local elapsed = now - party.stateStart
		if party.state == "order" then
			NPCUtil.patience(leader(party), 1 - elapsed / party.patience)
			if (not waiterPresent and elapsed >= Config.OrderAutoDelay) or (elapsed >= Config.TabletFallbackDelay and not party.npcClaimed) then
				GuestService.placeOrder(island, party, nil) -- заказ через планшет
			elseif elapsed >= party.patience then
				GuestService.partyLeave(island, party, "angry")
			end
		elseif party.state == "food" then
			NPCUtil.patience(leader(party), 1 - elapsed / party.patience)
			if elapsed >= party.patience then
				GuestService.partyLeave(island, party, "angry")
			end
		elseif party.state == "eat" then
			if elapsed >= Config.EatTime then
				party.state = "pay"
				GuestService.finishParty(island, party)
			end
		elseif party.state == "walk" and party.table then
			if now - party.spawnedAt > 60 then
				-- застрял в пути
				GuestService.seat(island, party)
			end
		end
	end
	-- self pickup when nobody serves (or the food waits too long on the pass)
	local pickupDelay = waiterPresent and Config.SelfPickupFallbackDelay or Config.SelfPickupDelay
	for _, item in ipairs(S.KitchenService.readyItems(island)) do
		if not item.carriedBy and item.readyAt and now - item.readyAt >= pickupDelay then
			GuestService.deliverItem(island, item, nil, true)
		end
	end
	-- dirty tables: cleanliness decay + auto clean fallback
	for _, rt in pairs(g.tables) do
		if rt.state == "dirty" then
			island.rest.cleanliness = Util.clamp(island.rest.cleanliness - 0.04 * dt, 0, 100)
			local cleaner = waiterPresent and 9999 or Config.AutoCleanDelay
			if now - (rt.dirtySince or now) >= cleaner then
				GuestService.cleanTable(island, rt, nil)
				island.rest.cleanliness = Util.clamp(island.rest.cleanliness - 2, 0, 100)
			end
		end
	end
	-- slow natural recovery of cleanliness with dishwasher
	local dish = island.rest.equipment.dishwasher or 0
	if dish > 0 then
		island.rest.cleanliness = Util.clamp(island.rest.cleanliness + 0.01 * dish * dt, 0, 100)
	end
end

-- dirty tables list for NPC waiters
function GuestService.dirtyTables(island)
	local list = {}
	if island.guest then
		for _, rt in pairs(island.guest.tables) do
			if rt.state == "dirty" then
				table.insert(list, rt)
			end
		end
	end
	return list
end

function GuestService.partiesWaitingOrder(island)
	local list = {}
	if island.guest then
		for _, p in pairs(island.guest.parties) do
			if p.state == "order" and not p.npcClaimed then
				table.insert(list, p)
			end
		end
		table.sort(list, function(a, b)
			return a.stateStart < b.stateStart
		end)
	end
	return list
end

function GuestService.Start()
	task.spawn(NPCUtil.preload)
	Players.PlayerRemoving:Connect(function(player)
		local island = S.RestaurantService.islandOf(player)
		if island and island.guest then
			GuestService.dropCarry(island, player)
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.GuestTickRate)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.owner and island.guest then
					local ok, err = pcall(GuestService.tick, island, dt)
					if not ok then
						warn("[GuestService] tick error: " .. tostring(err))
					end
				end
			end
		end
	end)
end

return GuestService
