-- StaffService: NPC staff hired by the Director (cooks, waiters, bartenders) and the
-- NPC cook provided by the Chef pass. Five levels, wages from the restaurant budget,
-- morale, training, autonomous work loops.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = Shared.Data
local Staff = require(Data.Staff)
local Stars = require(Data.Stars)
local Recipes = require(Data.Recipes)
local NPCUtil = require(script.Parent.NPCUtil)

local StaffService = {}
local S
local rng = Random.new()

local ROLE_SHIRT = {
	Cook = Color3.fromRGB(245, 245, 245),
	Waiter = Color3.fromRGB(30, 30, 40),
	Bartender = Color3.fromRGB(120, 30, 40),
}

function StaffService.Init(registry)
	S = registry
end

-- ===================== RUNTIME =====================
-- built-in NPCs (free, always available): uid -> settings
local HOUSE = {
	bartender = { role = "Bartender", name = "Бармен Лео", store = "bartenderNpc" },
	house_waiter = { role = "Waiter", name = "Официант Мила", store = "houseWaiterNpc" },
	robot = { role = "Cook", name = "Кухонный робот", isRobot = true },
}

function StaffService.icon(member)
	if member.isRobot then
		return "🤖"
	end
	local r = Staff.Roles[member.role]
	return r and r.icon or "🙂"
end

local function spot(island, name, index)
	local RS = S.RestaurantService
	local part = RS.buildingPart(island, name .. (index or ""))
	if not part then
		part = RS.buildingPart(island, name .. "1") or RS.buildingPart(island, name)
	end
	if part then
		return part.CFrame
	end
	return island.buildingCF * CFrame.new(0, 0, -10)
end

local function spawnNpc(island, member)
	local rt = island.staff
	local idx = 1
	for _, n in pairs(rt.npcs) do
		if n.data.role == member.role then
			idx += 1
		end
	end
	local spotName = member.role == "Cook" and "CookSpot" or (member.role == "Bartender" and "BarSpot" or "WaiterSpot")
	local home = spot(island, spotName, math.min(idx, 3))
	local model = NPCUtil.spawn("Staff", home * CFrame.new(0, 3, 0), { role = member.isRobot and "Robot" or member.role, rng = rng })
	model.Name = "Staff_" .. member.role
	local hat = model:FindFirstChild("ChefHat")
	if hat then
		hat.Transparency = member.role == "Cook" and 0 or 1
	end
	local npc = { data = member, model = model, home = home, busy = false, state = "idle" }
	rt.npcs[member.uid] = npc
	NPCUtil.bubble(model, StaffService.icon(member) .. " " .. member.name, Color3.fromRGB(90, 90, 110))
	return npc
end

local function despawnNpc(island, uid)
	local rt = island.staff
	local npc = rt and rt.npcs[uid]
	if not npc then
		return
	end
	if npc.walk then
		npc.walk:Cancel()
	end
	if npc.item then
		S.KitchenService.unclaim(island, npc.item)
	end
	if npc.carry then
		for _, it in ipairs(npc.carry) do
			it.carriedBy = nil
			if it.status == "ready" then
				S.KitchenService.returnToPass(island, it)
			end
		end
	end
	if npc.party then
		npc.party.npcClaimed = nil
	end
	NPCUtil.destroy(npc.model)
	rt.npcs[uid] = nil
end

function StaffService.setupIsland(island)
	island.staff = { npcs = {}, wageTimer = 0 }
	for _, member in ipairs(island.rest.staff) do
		Util.reconcile(member, { level = 1, xp = 0, wageMult = 1, morale = 1, unpaid = 0 })
		spawnNpc(island, member)
	end
	StaffService.refreshRoles(island)
end

function StaffService.clearIsland(island)
	if not island.staff then
		return
	end
	for uid in pairs(island.staff.npcs) do
		despawnNpc(island, uid)
	end
	island.staff = nil
end

-- Respawn NPCs after the building changes (new tier)
function StaffService.rebind(island)
	if not island.staff then
		return
	end
	local list = {}
	for uid, npc in pairs(island.staff.npcs) do
		table.insert(list, npc.data)
		despawnNpc(island, uid)
	end
	for _, member in ipairs(list) do
		spawnNpc(island, member)
	end
end

-- Chef pass: NPC cook appears while a player holds the Chef job
function StaffService.refreshRoles(island)
	if not island.staff then
		return
	end
	local chefActive = S.RestaurantService.chefActive(island)
	local chefNpc = island.staff.npcs.chef
	if chefActive and not chefNpc then
		local c = island.rest.chefNpc
		local member = { uid = "chef", role = "Cook", name = "Су-шеф", level = c.level, xp = c.xp, wageMult = 0.5, morale = 1, isChef = true, unpaid = 0 }
		spawnNpc(island, member)
	elseif not chefActive and chefNpc then
		despawnNpc(island, "chef")
	end
	local rest = island.rest
	local npcs = island.staff.npcs
	-- бармен есть всегда
	-- официант на замену: если нет игрока-официанта и нанятых NPC-официантов
	local hiredWaiter = false
	for uid, n in pairs(npcs) do
		if n.data.role == "Waiter" and not HOUSE[uid] then
			hiredWaiter = true
		end
	end
	local wantHouse = {
		bartender = true,
		house_waiter = S.RestaurantService.playerInRole(island, "Waiter") == nil and not hiredWaiter,
		robot = rest.kitchenRobot == true,
	}
	for uid, want in pairs(wantHouse) do
		if want and not npcs[uid] then
			local h = HOUSE[uid]
			local saved = h.store and rest[h.store] or { level = 5, xp = 0 }
			spawnNpc(island, {
				uid = uid, role = h.role, name = h.name, level = h.isRobot and 5 or saved.level, xp = saved.xp,
				wageMult = 0, morale = 1, unpaid = 0, isHouse = true, isRobot = h.isRobot, store = h.store,
			})
		elseif not want and npcs[uid] then
			despawnNpc(island, uid)
		end
	end
	S.RestaurantService.markDirty(island)
end

function StaffService.hasStaff(island, role)
	if not island.staff then
		return false
	end
	for _, npc in pairs(island.staff.npcs) do
		if npc.data.role == role and (npc.data.morale or 1) > 0 then
			return true
		end
	end
	return false
end

local function alive(island, npc)
	return island.rest ~= nil and island.staff ~= nil and island.staff.npcs[npc.data.uid] == npc
end

local function memberXp(island, npc, amount)
	local m = npc.data
	m.xp = (m.xp or 0) + amount
	if m.isChef then
		island.rest.chefNpc.xp = m.xp
	elseif m.store and island.rest[m.store] then
		island.rest[m.store].xp = m.xp
	end
end

-- ===================== WORK LOOPS =====================
local function workCook(island, npc, kind)
	local item = S.KitchenService.claimNext(island, kind, "npc")
	if not item then
		return
	end
	local recipe = Recipes.ById[item.recipeId]
	local lvl = Staff.Levels[npc.data.level] or Staff.Levels[1]
	local speed = Staff.effectiveSpeed(npc.data) * S.KitchenService.cookSpeedMult(island, kind)
	local base = kind == "dish" and Staff.BaseCookTime * (recipe.time / 12) or Staff.BaseDrinkTime
	npc.item = item
	npc.busy = true
	npc.state = "cooking"
	NPCUtil.bubble(npc.model, (kind == "dish" and "🔥 " or "🍹 ") .. recipe.icon, Color3.fromRGB(240, 140, 40))
	local duration = base / speed
	task.delay(duration, function()
		if not alive(island, npc) then
			return
		end
		npc.item = nil
		npc.busy = false
		npc.state = "idle"
		NPCUtil.bubble(npc.model, StaffService.icon(npc.data) .. " " .. npc.data.name, Color3.fromRGB(90, 90, 110))
		if item.status ~= "cooking" then
			return
		end
		local skill = lvl.quality
		if rng:NextNumber() < lvl.errorChance then
			skill *= 0.55 -- ошибка: пересолил / подгорело
			NPCUtil.bubble(npc.model, "😬 Упс!", Color3.fromRGB(220, 80, 60))
		end
		local bonus = npc.data.isChef and 0.05 or 0
		S.KitchenService.complete(island, item, S.KitchenService.qualityFor(island, recipe, skill, bonus), nil)
		memberXp(island, npc, 1)
	end)
end

local function approachFor(rt)
	if rt.seats and rt.seats[1] then
		return (rt.seats[1] * CFrame.new(0, 0, 2.5)).Position
	end
	return rt.base.Position
end

local function walkThen(island, npc, points, cb)
	npc.busy = true
	local speed = 13 * Staff.effectiveSpeed(npc.data)
	npc.walk = NPCUtil.walk(npc.model, points, speed, function()
		npc.walk = nil
		if alive(island, npc) then
			cb()
		end
	end)
end

local function homePoint(npc)
	return npc.home.Position
end

local function workWaiter(island, npc)
	local G = S.GuestService
	local lvl = Staff.Levels[npc.data.level] or Staff.Levels[1]
	local serveWait = Staff.BaseServeTime / Staff.effectiveSpeed(npc.data)
	-- 1) take orders
	local parties = G.partiesWaitingOrder(island)
	if #parties > 0 then
		local party = parties[1]
		party.npcClaimed = true
		npc.party = party
		npc.state = "order"
		walkThen(island, npc, { approachFor(party.table) }, function()
			task.delay(serveWait * 0.6, function()
				npc.party = nil
				if not alive(island, npc) then
					return
				end
				if party.state == "order" and G.partyFor(island, party.id) == party then
					G.placeOrder(island, party, nil)
					memberXp(island, npc, 1)
				end
				party.npcClaimed = nil
				walkThen(island, npc, { homePoint(npc) }, function()
					npc.busy = false
					npc.state = "idle"
				end)
			end)
		end)
		return
	end
	-- 2) deliver ready items
	local ready = S.KitchenService.readyItems(island)
	if #ready > 0 then
		local capacity = 1 + math.floor((npc.data.level - 1) / 2)
		local carry = {}
		local target
		for _, it in ipairs(ready) do
			if not it.carriedBy and #carry < capacity then
				local party = G.partyFor(island, it.partyId)
				if party and (not target or party == target) then
					target = party
					it.carriedBy = "npc"
					S.KitchenService.removeFromPass(island, it)
					table.insert(carry, it)
				end
			end
		end
		if #carry == 0 or not target then
			return
		end
		npc.carry = carry
		npc.state = "serve"
		local pass = S.RestaurantService.buildingPart(island, "PassCounter")
		local passPoint = pass and (pass.CFrame * CFrame.new(0, 0, 3)).Position or homePoint(npc)
		walkThen(island, npc, { passPoint, approachFor(target.table) }, function()
			task.delay(serveWait * 0.4, function()
				if not alive(island, npc) then
					return
				end
				for _, it in ipairs(carry) do
					it.carriedBy = nil
					if rng:NextNumber() < lvl.errorChance * 0.5 then
						it.quality = (it.quality or 0.5) * 0.8 -- пролил немного
					end
					G.deliverItem(island, it, nil, false)
				end
				npc.carry = nil
				memberXp(island, npc, #carry)
				walkThen(island, npc, { homePoint(npc) }, function()
					npc.busy = false
					npc.state = "idle"
				end)
			end)
		end)
		return
	end
	-- 3) clean tables
	local dirty = G.dirtyTables(island)
	for _, rt in ipairs(dirty) do
		if not rt.npcCleaning then
			rt.npcCleaning = true
			npc.state = "clean"
			walkThen(island, npc, { approachFor(rt) }, function()
				task.delay(Staff.BaseCleanTime / Staff.effectiveSpeed(npc.data), function()
					rt.npcCleaning = nil
					if not alive(island, npc) then
						return
					end
					G.cleanTable(island, rt, nil)
					memberXp(island, npc, 1)
					walkThen(island, npc, { homePoint(npc) }, function()
						npc.busy = false
						npc.state = "idle"
					end)
				end)
			end)
			return
		end
	end
end

function StaffService.tick(island)
	local rt = island.staff
	if not rt then
		return
	end
	for _, npc in pairs(rt.npcs) do
		if not npc.busy and (npc.data.morale or 1) > 0 then
			if npc.data.role == "Cook" then
				workCook(island, npc, "dish")
			elseif npc.data.role == "Bartender" then
				workCook(island, npc, "drink")
			elseif npc.data.role == "Waiter" then
				workWaiter(island, npc)
			end
		elseif (npc.data.morale or 1) <= 0 and not npc.busy then
			NPCUtil.bubble(npc.model, "😤 Не платят!", Color3.fromRGB(220, 60, 60))
		end
	end
end

-- Wages every minute
function StaffService.payWages(island)
	local rt = island.staff
	if not rt then
		return
	end
	local warned = false
	for _, npc in pairs(rt.npcs) do
		local m = npc.data
		local wage = Staff.wagePerMinute(m)
		if S.Economy.budgetSpend(island, wage, "wages", "Персонал", "Зарплаты", "wages") then
			m.unpaid = 0
			m.morale = math.min(1, (m.morale or 1) + 0.2)
		else
			m.unpaid = (m.unpaid or 0) + 1
			m.morale = math.max(0, (m.morale or 1) - 0.34)
			if not warned then
				warned = true
				for _, p in ipairs(S.RestaurantService.membersOf(island)) do
					Net.toast(p, "💸 Не хватает бюджета на зарплаты персоналу! Мотивация падает.", "error")
				end
			end
		end
	end
	S.RestaurantService.markDirty(island)
end

-- ===================== STATE =====================
function StaffService.staffState(island)
	local out = {}
	local rt = island.staff
	for _, m in ipairs(island.rest.staff) do
		local npc = rt and rt.npcs[m.uid]
		local next = Staff.Levels[m.level + 1]
		table.insert(out, {
			uid = m.uid,
			role = m.role,
			name = m.name,
			level = m.level,
			levelName = Staff.Levels[m.level].name,
			xp = m.xp,
			xpNeed = next and next.xpNeed or 0,
			trainCost = next and next.trainCost or 0,
			wage = Staff.wagePerMinute(m),
			wageMult = m.wageMult,
			morale = m.morale,
			state = npc and npc.state or "off",
		})
	end
	for _, uid in ipairs({ "chef", "bartender", "house_waiter", "robot" }) do
		local npc = rt and rt.npcs[uid]
		if npc then
			local m = npc.data
			local next = not m.isRobot and Staff.Levels[m.level + 1] or nil
			local discount = uid == "chef" and 0.7 or 0.5
			table.insert(out, {
				uid = uid, role = m.role, name = m.name, level = m.level, levelName = m.isRobot and "Робот" or Staff.Levels[m.level].name,
				xp = m.xp, xpNeed = next and next.xpNeed or 0, trainCost = next and math.floor(next.trainCost * discount) or 0,
				wage = Staff.wagePerMinute(m), wageMult = m.wageMult, morale = m.morale, state = npc.state,
				isChef = uid == "chef", isHouse = m.isHouse == true, isRobot = m.isRobot == true,
			})
		end
	end
	return out
end

local function findMember(island, uid)
	if uid == "chef" or HOUSE[uid] then
		return island.staff and island.staff.npcs[uid] and island.staff.npcs[uid].data
	end
	for _, m in ipairs(island.rest.staff) do
		if m.uid == uid then
			return m
		end
	end
	return nil
end

-- ===================== REMOTES =====================
local function isDirector(player, island)
	return S.RestaurantService.playerInRole(island, "Director") == player
end

function StaffService.Start()
	Net.onRequest("HireStaff", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island or not isDirector(player, island) then
			return { ok = false, err = "Нанимать персонал может только директор ресторана" }
		end
		local role = payload and payload.role
		if role == "Bartender" then
			return { ok = false, err = "Бармен уже работает в ресторане бесплатно" }
		end
		local def = type(role) == "string" and Staff.Roles[role]
		if not def then
			return { ok = false, err = "Нет такой должности" }
		end
		local slots = Stars.Levels[island.rest.stars].staffSlots
		if #island.rest.staff >= slots then
			return { ok = false, err = "Максимум сотрудников для " .. island.rest.stars .. "★: " .. slots }
		end
		local okSpend, why = S.Economy.playerSpendBudget(player, island, def.hireCost, "staff", "Найм: " .. def.name, "wages")
		if not okSpend then
			return { ok = false, err = why }
		end
		local member = {
			uid = island.rest.nextUid,
			role = role,
			name = Staff.Names[rng:NextInteger(1, #Staff.Names)],
			level = 1,
			xp = 0,
			wageMult = 1,
			morale = 1,
			unpaid = 0,
		}
		island.rest.nextUid += 1
		table.insert(island.rest.staff, member)
		spawnNpc(island, member)
		StaffService.refreshRoles(island)
		S.Economy.addProfXp(player, "Director", 20)
		Net.toast(player, def.icon .. " Нанят сотрудник: " .. member.name, "success")
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)

	Net.onRequest("FireStaff", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island or not isDirector(player, island) then
			return { ok = false, err = "Только директор" }
		end
		local uid = payload and payload.uid
		for i, m in ipairs(island.rest.staff) do
			if m.uid == uid then
				table.remove(island.rest.staff, i)
				despawnNpc(island, uid)
				StaffService.refreshRoles(island)
				S.RestaurantService.markDirty(island)
				return { ok = true }
			end
		end
		return { ok = false, err = "Сотрудник не найден" }
	end)

	Net.onRequest("TrainStaff", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local uid = payload and payload.uid
		local member = findMember(island, uid)
		if not member then
			return { ok = false, err = "Сотрудник не найден" }
		end
		if member.isRobot then
			return { ok = false, err = "Робот уже работает на максимуме" }
		end
		local allowed = isDirector(player, island)
			or (uid == "chef" and S.RestaurantService.playerInRole(island, "Chef") == player)
			or (HOUSE[uid] ~= nil and island.owner == player)
		if not allowed then
			return { ok = false, err = "Обучать может директор (шеф-повар — своего су-шефа, владелец — бармена и официанта)" }
		end
		local next = Staff.Levels[member.level + 1]
		if not next then
			return { ok = false, err = "Максимальный уровень" }
		end
		if (member.xp or 0) < next.xpNeed then
			return { ok = false, err = "Нужно опыта: " .. next.xpNeed .. " (сейчас " .. math.floor(member.xp or 0) .. ")" }
		end
		local cost = uid == "chef" and math.floor(next.trainCost * 0.7) or (HOUSE[uid] and math.floor(next.trainCost * 0.5) or next.trainCost)
		local okSpend, why = S.Economy.playerSpendBudget(player, island, cost, "staff", "Обучение: " .. member.name, "upgrades")
		if not okSpend then
			return { ok = false, err = why }
		end
		member.level += 1
		if member.isChef then
			island.rest.chefNpc.level = member.level
		elseif member.store and island.rest[member.store] then
			island.rest[member.store].level = member.level
		end
		S.Economy.addProfXp(player, S.RestaurantService.roleOf(player) or "Director", 40)
		Net.toast(player, "🎓 " .. member.name .. " теперь " .. Staff.Levels[member.level].name, "success")
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)

	Net.onRequest("SetWage", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island or not isDirector(player, island) then
			return { ok = false, err = "Только директор" }
		end
		local member = findMember(island, payload and payload.uid)
		local mult = tonumber(payload and payload.mult)
		if not member or member.isChef or not mult or not Util.isFiniteNumber(mult) then
			return { ok = false, err = "Некорректные данные" }
		end
		member.wageMult = Util.round(Util.clamp(mult, Staff.WageMultMin, Staff.WageMultMax), 0.1)
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)

	task.spawn(function()
		while true do
			task.wait(0.75)
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.owner and island.staff then
					local ok, err = pcall(StaffService.tick, island)
					if not ok then
						warn("[StaffService] tick error: " .. tostring(err))
					end
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.owner and island.staff then
					pcall(StaffService.payWages, island)
				end
			end
		end
	end)
end

return StaffService
