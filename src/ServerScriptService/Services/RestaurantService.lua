-- RestaurantService: 8 islands/restaurants, ownership (1 per player), team of max 2
-- real players (owner + invited friend), invitations & join requests, the four
-- unique professions, menu & prices, budget deposits, state replication.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local MapLayout = require(Shared.MapLayout)
local Data = Shared.Data
local Professions = require(Data.Professions)
local Recipes = require(Data.Recipes)
local Equipment = require(Data.Equipment)

local RS = {}
local S

RS.Islands = {} -- [index] = island
local playerIsland = {} -- [player] = island (owner or friend)
local invites = {} -- [targetPlayer] = { [islandIndex] = {from=player, t=time} }
local joinRequests = {} -- [islandIndex] = { [userId] = {player=, t=} }
local dirty = {}
local worldDirty = true
local roleCooldown = {}

local INVITE_TTL = 120

function RS.Init(registry)
	S = registry
end

-- ===================== HELPERS =====================
function RS.islandOf(player)
	return playerIsland[player]
end

function RS.membersOf(island)
	local list = {}
	if island.owner and island.owner.Parent then
		table.insert(list, island.owner)
	end
	if island.friend and island.friend.Parent then
		table.insert(list, island.friend)
	end
	return list
end

function RS.isMember(player, island)
	return island ~= nil and (island.owner == player or island.friend == player)
end

function RS.roleOf(player)
	local island = playerIsland[player]
	if not island then
		return nil
	end
	for role, p in pairs(island.roles) do
		if p == player then
			return role
		end
	end
	return nil
end

function RS.playerInRole(island, role)
	local p = island.roles[role]
	if p and p.Parent and RS.isMember(p, island) then
		return p
	end
	return nil
end

function RS.chefActive(island)
	return RS.playerInRole(island, "Chef") ~= nil
end

function RS.markDirty(island)
	if island then
		dirty[island] = true
	end
end

function RS.markWorld()
	worldDirty = true
end

-- ===================== ACTIVITY (anti AFK-farm) =====================
local lastPositions = {}
function RS.touch(player)
	local island = playerIsland[player]
	if island then
		island.lastActivity = os.clock()
	end
end

function RS.isIdle(island)
	return island.lastActivity ~= nil and os.clock() - island.lastActivity > Config.IdleTimeout
end

-- Island local CFrame (centre at surface level; +Z = outward/dock)
function RS.islandCFrame(index)
	local x, y, z = MapLayout.islandCenter(index)
	local center = Vector3.new(x, y, z)
	local outward = Vector3.new(x, 0, z).Unit
	return CFrame.lookAt(center, center - outward)
end

function RS.buildingCFrame(index)
	return RS.islandCFrame(index) * CFrame.new(0, MapLayout.FloorHeight, MapLayout.BuildingOffsetZ)
end

function RS.islandAt(position)
	for _, island in pairs(RS.Islands) do
		local c = island.center
		local dx, dz = position.X - c.X, position.Z - c.Z
		if dx * dx + dz * dz <= MapLayout.BarrierRadius ^ 2 then
			return island
		end
	end
	return nil
end

function RS.spawnCFrame(island)
	local pad = island.model and island.model:FindFirstChild("SpawnPad")
	if pad then
		return pad.CFrame * CFrame.new(0, 4, 0)
	end
	return RS.islandCFrame(island.index) * CFrame.new(0, 5, 40)
end

function RS.loungeCFrame()
	local p = MapLayout.LoungePosition
	return CFrame.new(p[1] + math.random(-8, 8), p[2] + 5, p[3] + math.random(-8, 8))
end

function RS.teleport(player, cf)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		hum.Sit = false
		task.wait()
	end
	if root then
		char:PivotTo(cf)
	end
end

function RS.sendHome(player)
	local island = playerIsland[player]
	if island then
		RS.teleport(player, RS.spawnCFrame(island))
	else
		RS.teleport(player, RS.loungeCFrame())
	end
end

local function setSign(island)
	local bsign = island.building and island.building:FindFirstChild("BuildingSign", true)
	local blabel = bsign and bsign:FindFirstChild("Title", true)
	if blabel and island.rest then
		blabel.Text = island.rest.name
	end
	local sign = island.model and island.model:FindFirstChild("OwnerSign")
	local label = sign and sign:FindFirstChild("Title", true)
	if label and label:IsA("TextLabel") then
		if island.owner then
			label.Text = (island.rest.name ~= "" and island.rest.name or ("Ресторан " .. island.owner.DisplayName))
				.. "\n" .. string.rep("★", island.rest.stars) .. string.rep("☆", 5 - island.rest.stars)
		else
			label.Text = island.theme .. "\nСвободный остров"
		end
	end
end
RS.setSign = setSign

-- ===================== BUILDING =====================
function RS.spawnBuilding(island)
	if island.building then
		island.building:Destroy()
		island.building = nil
	end
	local tiers = ServerStorage:FindFirstChild("RestaurantTiers")
	local template = tiers and tiers:FindFirstChild("Tier" .. island.rest.stars)
	if not template then
		warn("[RestaurantService] missing tier template " .. island.rest.stars)
		return
	end
	local b = template:Clone()
	b.Name = "Restaurant"
	b:SetAttribute("Tier", island.rest.stars)
	b:SetAttribute("Island", island.index)
	b:PivotTo(RS.buildingCFrame(island.index))
	b.Parent = island.model
	island.building = b
	island.buildingCF = RS.buildingCFrame(island.index)
end

function RS.buildingPart(island, name)
	return island.building and island.building:FindFirstChild(name, true)
end

-- ===================== CLAIM / UNLOAD =====================
local function newIslandRuntime(island)
	island.roles = {}
	island.lastActivity = os.clock()
	island.periodRevenue = 0
	island.friendSpent = 0
	island.friendSpendDay = 0
end

local function loadIsland(island, player, profile)
	island.owner = player
	island.ownerId = player.UserId
	island.rest = profile.data.restaurant
	island.friend = nil
	newIslandRuntime(island)
	playerIsland[player] = island
	if island.rest.name == "" then
		island.rest.name = "Ресторан " .. player.DisplayName
	end
	-- defaults for menu: every available recipe on
	for _, r in ipairs(Recipes.List) do
		if island.rest.menu[r.id] == nil then
			island.rest.menu[r.id] = { on = true, price = 1 }
		end
	end
	RS.spawnBuilding(island)
	S.GuestService.setupIsland(island) -- до мебели: столы регистрируются как места для гостей
	S.BuildService.spawnAll(island)
	S.KitchenService.setupIsland(island)
	S.StaffService.setupIsland(island)
	S.BarrierService.apply(island, false)
	S.EventService.setupIsland(island)
	setSign(island)
	RS.markDirty(island)
	RS.markWorld()
end

function RS.claim(player, index)
	local profile = S.DataService.get(player)
	if not profile then
		return false, "Данные ещё загружаются"
	end
	if playerIsland[player] then
		return false, "Вы уже в ресторане"
	end
	local island
	if index then
		island = RS.Islands[index]
		if not island then
			return false, "Нет такого острова"
		end
		if island.owner then
			return false, "Этот остров уже занят"
		end
	else
		for i = 1, MapLayout.IslandCount do
			if not RS.Islands[i].owner then
				island = RS.Islands[i]
				break
			end
		end
	end
	if not island then
		return false, "Все острова заняты. Попросите владельца пригласить вас или подождите."
	end
	-- ВАЖНО: назначение владельца происходит без yield'ов между проверкой и записью,
	-- поэтому два игрока не могут получить один остров.
	island.owner = player
	invites[player] = nil
	loadIsland(island, player, profile)
	-- auto-restore last profession
	local last = profile.data.lastRole
	if last ~= "" then
		task.spawn(function()
			RS.setRole(player, last, true)
		end)
	end
	S.Economy.markPlayer(player)
	S.Economy.updateLeaderstats(player)
	RS.teleport(player, RS.spawnCFrame(island))
	Net.toast(player, "🏝️ Добро пожаловать на " .. island.theme .. "! Выберите профессию в меню «Профессии».", "success")
	return true
end

function RS.unloadIsland(island, reason)
	if not island.owner then
		return
	end
	local owner = island.owner
	local friend = island.friend
	S.HelicopterService.despawnForIsland(island)
	S.GuestService.clearIsland(island)
	S.KitchenService.clearIsland(island)
	S.StaffService.clearIsland(island)
	S.BuildService.clearIsland(island)
	S.BarrierService.apply(island, true)
	if island.building then
		island.building:Destroy()
		island.building = nil
	end
	playerIsland[owner] = nil
	if friend then
		playerIsland[friend] = nil
		if friend.Parent then
			Net.toast(friend, reason or "Владелец покинул ресторан. Вы перенесены в зал ожидания.", "warn")
			RS.teleport(friend, RS.loungeCFrame())
			S.Economy.markPlayer(friend)
		end
	end
	joinRequests[island.index] = nil
	for target, map in pairs(invites) do
		map[island.index] = nil
		S.Economy.markPlayer(target)
	end
	island.owner = nil
	island.ownerId = nil
	island.friend = nil
	island.rest = nil
	island.roles = {}
	setSign(island)
	RS.markWorld()
end

-- ===================== TEAM =====================
local function joinAsFriend(player, island)
	if playerIsland[player] then
		return false, "Вы уже состоите в ресторане"
	end
	if island.friend then
		return false, "В ресторане уже 2 игрока"
	end
	if not island.owner then
		return false, "У острова нет владельца"
	end
	island.friend = player
	playerIsland[player] = island
	invites[player] = nil
	for _, req in pairs(joinRequests) do
		req[player.UserId] = nil
	end
	S.QuestService.add(player, "teamJoins", 1)
	Net.toast(island.owner, "👥 " .. player.DisplayName .. " присоединился к вашему ресторану!", "success")
	Net.toast(player, "👥 Вы в команде ресторана «" .. island.rest.name .. "». Выберите свободную профессию.", "success")
	RS.teleport(player, RS.spawnCFrame(island))
	S.BarrierService.refreshAccess(island)
	S.Economy.markPlayer(player)
	S.Economy.markPlayer(island.owner)
	RS.markDirty(island)
	RS.markWorld()
	return true
end

local function removeFriend(island, reason)
	local friend = island.friend
	if not friend then
		return
	end
	for role, p in pairs(island.roles) do
		if p == friend then
			island.roles[role] = nil
		end
	end
	island.friend = nil
	playerIsland[friend] = nil
	S.KitchenService.onMemberLeft(island, friend)
	S.StaffService.refreshRoles(island)
	S.BarrierService.refreshAccess(island)
	if friend.Parent then
		Net.toast(friend, reason or "Вы покинули ресторан.", "info")
		RS.teleport(friend, RS.loungeCFrame())
		S.Economy.markPlayer(friend)
		local hum = friend.Character and friend.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 16
		end
	end
	if island.owner then
		S.Economy.markPlayer(island.owner)
	end
	RS.markDirty(island)
	RS.markWorld()
end

function RS.invitesFor(player)
	local out = {}
	local map = invites[player]
	if map then
		for index, inv in pairs(map) do
			if os.time() - inv.t <= INVITE_TTL and inv.from.Parent and RS.Islands[index].owner == inv.from then
				table.insert(out, { island = index, from = inv.from.DisplayName, restaurant = RS.Islands[index].rest.name, t = INVITE_TTL - (os.time() - inv.t) })
			end
		end
	end
	return out
end

-- ===================== PROFESSIONS =====================
local function applyRoleEffects(player, role)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		if role == "Waiter" then
			hum.WalkSpeed = Professions.waiterSpeed(S.Economy.profLevel(player, "Waiter"))
		else
			hum.WalkSpeed = 18
		end
	end
end
RS.applyRoleEffects = applyRoleEffects

function RS.onProfessionLevel(player, prof)
	if RS.roleOf(player) == prof then
		applyRoleEffects(player, prof)
	end
end

function RS.setRole(player, role, silent)
	local island = playerIsland[player]
	if not island then
		return false, "Сначала откройте ресторан или вступите в команду"
	end
	local def = Professions.ById[role]
	if not def then
		return false, "Нет такой профессии"
	end
	local now = os.clock()
	if roleCooldown[player] and now - roleCooldown[player] < 3 and not silent then
		return false, "Подождите пару секунд"
	end
	if island.friend == player and not RS.roleOf(island.owner) then
		return false, "Владелец ещё не выбрал профессию"
	end
	local holder = RS.playerInRole(island, role)
	if holder and holder ~= player then
		return false, "Эта должность уже занята игроком " .. holder.DisplayName
	end
	if def.paid and not S.MonetizationService.ownsPass(player, def.pass) then
		return false, "Нужен Game Pass «" .. def.name .. "» (" .. def.price .. " Robux)"
	end
	for r, p in pairs(island.roles) do
		if p == player then
			island.roles[r] = nil
		end
	end
	island.roles[role] = player
	roleCooldown[player] = now
	local profile = S.DataService.get(player)
	if profile then
		profile.data.lastRole = role
	end
	applyRoleEffects(player, role)
	S.KitchenService.onRoleChanged(island, player)
	S.StaffService.refreshRoles(island)
	if not silent then
		Net.toast(player, def.icon .. " Ваша профессия: " .. def.name, "success")
	end
	S.Economy.markPlayer(player)
	for _, m in ipairs(RS.membersOf(island)) do
		S.Economy.markPlayer(m)
	end
	RS.markDirty(island)
	return true
end

-- ===================== MENU / PRICES =====================
local function canManage(player, island)
	-- управлять меню могут владелец и игрок-директор
	return island.owner == player or RS.playerInRole(island, "Director") == player
end
RS.canManage = canManage

-- ===================== SNAPSHOT =====================
function RS.buildState(island)
	local rest = island.rest
	if not rest then
		return nil
	end
	local roles = {}
	for _, r in ipairs(Professions.Order) do
		local p = RS.playerInRole(island, r)
		roles[r] = p and { userId = p.UserId, name = p.DisplayName } or false
	end
	local wl = {}
	for id, name in pairs(rest.whitelist) do
		table.insert(wl, { userId = tonumber(id), name = name })
	end
	local requests = {}
	for uid, req in pairs(joinRequests[island.index] or {}) do
		if req.player.Parent then
			table.insert(requests, { userId = uid, name = req.player.DisplayName })
		end
	end
	local pendingInvites = {}
	for target, map in pairs(invites) do
		local inv = map[island.index]
		if inv and target.Parent and os.time() - inv.t <= INVITE_TTL then
			table.insert(pendingInvites, { userId = target.UserId, name = target.DisplayName, t = INVITE_TTL - (os.time() - inv.t) })
		end
	end
	local metrics, rows, canPromote = S.RatingService.evaluate(island)
	return {
		index = island.index,
		theme = island.theme,
		name = rest.name,
		owner = island.owner and { userId = island.owner.UserId, name = island.owner.DisplayName } or false,
		friend = island.friend and { userId = island.friend.UserId, name = island.friend.DisplayName, role = RS.roleOf(island.friend) or "" } or false,
		stars = rest.stars,
		budget = rest.budget,
		reputation = rest.reputation,
		cleanliness = rest.cleanliness,
		inventory = rest.inventory,
		storageLevel = rest.storageLevel,
		storageCap = Equipment.storageCapacity(rest),
		storageUsed = S.ShopService.storageUsed(rest),
		menu = rest.menu,
		unlockedRecipes = rest.unlockedRecipes,
		equipment = rest.equipment,
		furniture = rest.furniture,
		decor = rest.decor,
		staff = S.StaffService.staffState(island),
		chefNpc = rest.chefNpc,
		stats = rest.stats,
		reviews = rest.reviews,
		ledger = rest.ledger,
		barrierOn = rest.barrierOn,
		whitelist = wl,
		friendCanSpend = rest.friendCanSpend,
		roles = roles,
		chefActive = RS.chefActive(island),
		live = S.GuestService.liveState(island),
		kitchen = S.KitchenService.liveState(island),
		events = S.EventService.islandEventState(island),
		metrics = metrics,
		promotion = rows,
		canPromote = canPromote,
		joinRequests = requests,
		pendingInvites = pendingInvites,
		season = Recipes.currentSeason(),
		helipad = S.BuildService.hasDecor(island, "helipad"),
	}
end

function RS.buildWorldState()
	local list = {}
	for i = 1, MapLayout.IslandCount do
		local island = RS.Islands[i]
		local entry = { index = i, theme = island.theme, owned = island.owner ~= nil }
		if island.owner then
			entry.ownerName = island.owner.DisplayName
			entry.ownerId = island.owner.UserId
			entry.name = island.rest.name
			entry.stars = island.rest.stars
			entry.barrierOn = island.rest.barrierOn
			entry.members = #RS.membersOf(island)
			entry.friendSlot = island.friend == nil
			entry.reputation = math.floor(island.rest.reputation)
			entry.beauty = S.BuildService.beautyScore(island)
		end
		list[i] = entry
	end
	return { islands = list, contest = S.EventService.contestState(), serverEvent = S.EventService.serverEventState() }
end

-- ===================== REMOTES =====================
local function ok(extra)
	extra = extra or {}
	extra.ok = true
	return extra
end
local function fail(err)
	return { ok = false, err = err }
end

local function registerRemotes()
	Net.onActivity = RS.touch
	Net.onRequest("ClaimIsland", function(player, payload)
		local index = type(payload) == "table" and tonumber(payload.index) or nil
		if index and (index < 1 or index > MapLayout.IslandCount or index % 1 ~= 0) then
			return fail("Некорректный остров")
		end
		local success, err = RS.claim(player, index)
		return success and ok() or fail(err)
	end)

	Net.onRequest("ReleaseIsland", function(player)
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Вы не владелец")
		end
		local profile = S.DataService.get(player)
		RS.unloadIsland(island, "Владелец закрыл ресторан.")
		if profile then
			task.spawn(S.DataService.save, profile, false)
		end
		RS.teleport(player, RS.loungeCFrame())
		S.Economy.markPlayer(player)
		return ok()
	end)

	Net.onRequest("ChooseRole", function(player, payload)
		local role = type(payload) == "table" and payload.role
		if type(role) ~= "string" then
			return fail("Некорректная профессия")
		end
		local success, err = RS.setRole(player, role)
		return success and ok() or fail(err)
	end)

	Net.onRequest("Invite", function(player, payload)
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Приглашать может только владелец")
		end
		if not RS.roleOf(player) then
			return fail("Сначала выберите свою профессию")
		end
		if island.friend then
			return fail("Место друга уже занято")
		end
		local target = Players:GetPlayerByUserId(tonumber(payload and payload.userId) or 0)
		if not target or target == player then
			return fail("Игрок не найден")
		end
		if playerIsland[target] then
			return fail(target.DisplayName .. " уже состоит в ресторане")
		end
		invites[target] = invites[target] or {}
		invites[target][island.index] = { from = player, t = os.time() }
		Net.toast(target, "✉️ " .. player.DisplayName .. " приглашает вас в ресторан «" .. island.rest.name .. "»", "invite")
		Net.fx(target, "invite", { island = island.index })
		S.Economy.markPlayer(target)
		RS.markDirty(island)
		return ok()
	end)

	Net.onRequest("CancelInvite", function(player, payload)
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Нет прав")
		end
		local target = Players:GetPlayerByUserId(tonumber(payload and payload.userId) or 0)
		if target and invites[target] then
			invites[target][island.index] = nil
			S.Economy.markPlayer(target)
		end
		RS.markDirty(island)
		return ok()
	end)

	Net.onRequest("AcceptInvite", function(player, payload)
		local index = tonumber(payload and payload.island)
		local inv = index and invites[player] and invites[player][index]
		if not inv or os.time() - inv.t > INVITE_TTL then
			return fail("Приглашение недействительно")
		end
		local island = RS.Islands[index]
		if not island or island.owner ~= inv.from then
			return fail("Ресторан больше недоступен")
		end
		local success, err = joinAsFriend(player, island)
		return success and ok() or fail(err)
	end)

	Net.onRequest("DeclineInvite", function(player, payload)
		local index = tonumber(payload and payload.island)
		if index and invites[player] then
			local inv = invites[player][index]
			invites[player][index] = nil
			if inv and inv.from.Parent then
				Net.toast(inv.from, player.DisplayName .. " отклонил приглашение", "info")
				RS.markDirty(RS.Islands[index])
			end
		end
		S.Economy.markPlayer(player)
		return ok()
	end)

	Net.onRequest("RequestJoin", function(player, payload)
		local index = tonumber(payload and payload.island)
		local island = index and RS.Islands[index]
		if not island or not island.owner then
			return fail("Ресторан не найден")
		end
		if playerIsland[player] then
			return fail("Вы уже в ресторане")
		end
		if island.friend then
			return fail("В этом ресторане нет свободного места")
		end
		joinRequests[index] = joinRequests[index] or {}
		joinRequests[index][player.UserId] = { player = player, t = os.time() }
		Net.toast(island.owner, "🙋 " .. player.DisplayName .. " просит присоединиться к ресторану (меню «Приглашения»)", "invite")
		RS.markDirty(island)
		return ok()
	end)

	Net.onRequest("AnswerJoin", function(player, payload)
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Нет прав")
		end
		local uid = tonumber(payload and payload.userId) or 0
		local req = joinRequests[island.index] and joinRequests[island.index][uid]
		if not req then
			return fail("Запрос не найден")
		end
		joinRequests[island.index][uid] = nil
		RS.markDirty(island)
		if payload.accept == true then
			if not RS.roleOf(player) then
				return fail("Сначала выберите свою профессию")
			end
			local success, err = joinAsFriend(req.player, island)
			return success and ok() or fail(err)
		else
			if req.player.Parent then
				Net.toast(req.player, "Владелец отклонил ваш запрос", "warn")
			end
			return ok()
		end
	end)

	Net.onRequest("KickFriend", function(player)
		local island = playerIsland[player]
		if not island or island.owner ~= player or not island.friend then
			return fail("Нет участника для удаления")
		end
		removeFriend(island, "Владелец удалил вас из команды.")
		return ok()
	end)

	Net.onRequest("LeaveTeam", function(player)
		local island = playerIsland[player]
		if not island or island.friend ~= player then
			return fail("Вы не участник команды")
		end
		removeFriend(island, "Вы покинули ресторан.")
		return ok()
	end)

	Net.onRequest("SetMenu", function(player, payload)
		local island = playerIsland[player]
		if not island or not canManage(player, island) then
			return fail("Меню управляет владелец или директор")
		end
		local id = payload and payload.id
		local recipe = type(id) == "string" and Recipes.ById[id]
		if not recipe then
			return fail("Нет такого блюда")
		end
		local entry = island.rest.menu[id] or { on = true, price = 1 }
		if type(payload.on) == "boolean" then
			entry.on = payload.on
		end
		if Util.isFiniteNumber(payload.price) then
			entry.price = Util.round(Util.clamp(payload.price, Config.MinPriceMult, Config.MaxPriceMult), 0.05)
		end
		island.rest.menu[id] = entry
		RS.markDirty(island)
		return ok()
	end)

	Net.onRequest("RenameRestaurant", function(player, payload)
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Переименовать может только владелец")
		end
		local name = payload and payload.name
		if type(name) ~= "string" then
			return fail("Некорректное имя")
		end
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if #name < 3 or utf8.len(name) == nil or utf8.len(name) > 28 then
			return fail("Название: от 3 до 28 символов")
		end
		local success, filtered = pcall(function()
			local result = TextService:FilterStringAsync(name, player.UserId)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if not success then
			return fail("Фильтр текста недоступен, попробуйте позже")
		end
		island.rest.name = filtered
		setSign(island)
		RS.markDirty(island)
		RS.markWorld()
		return ok()
	end)

	Net.onRequest("Deposit", function(player, payload)
		local island = playerIsland[player]
		if not island then
			return fail("Вы не в ресторане")
		end
		local amount = math.floor(tonumber(payload and payload.amount) or 0)
		if amount <= 0 or amount > 1e9 then
			return fail("Некорректная сумма")
		end
		if not S.Economy.spend(player, amount, "Вклад в ресторан") then
			return fail("Недостаточно личных денег")
		end
		S.Economy.budgetCredit(island, amount, "deposit", player.DisplayName, "Вклад")
		return ok()
	end)

	Net.onRequest("Withdraw", function(player, payload)
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Выводить деньги может только владелец")
		end
		local amount = math.floor(tonumber(payload and payload.amount) or 0)
		if amount <= 0 or amount > island.rest.budget then
			return fail("Некорректная сумма")
		end
		if not S.Economy.budgetSpend(island, amount, "withdraw", player.DisplayName, "Вывод владельцем") then
			return fail("Недостаточно средств")
		end
		local net = math.floor(amount * (1 - Config.OwnerWithdrawFee))
		S.Economy.grant(player, net, "Вывод из ресторана")
		return ok({ received = net })
	end)

	Net.onRequest("SetFriendSpend", function(player, payload)
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Нет прав")
		end
		island.rest.friendCanSpend = payload and payload.allow == true
		RS.markDirty(island)
		return ok()
	end)

	Net.onRequest("GoHome", function(player)
		RS.sendHome(player)
		return ok()
	end)

	Net.onRequest("Visit", function(player, payload)
		local index = tonumber(payload and payload.island)
		local island = index and RS.Islands[index]
		if not island then
			return fail("Нет такого острова")
		end
		if not S.BarrierService.canEnter(player, island) then
			return fail("Владелец закрыл остров барьером")
		end
		if playerIsland[player] ~= island then
			if not S.Economy.spend(player, Config.FerryTicket, "Паром") then
				return fail("Билет на паром стоит $" .. Config.FerryTicket)
			end
		end
		RS.teleport(player, RS.spawnCFrame(island))
		return ok()
	end)

	-- Только для Roblox Studio: ускорение теста прогрессии (на живых серверах недоступно)
	Net.onRequest("DebugBoost", function(player)
		if not game:GetService("RunService"):IsStudio() then
			return fail("Недоступно")
		end
		local island = playerIsland[player]
		if not island or island.owner ~= player then
			return fail("Нужен свой ресторан")
		end
		local rest = island.rest
		rest.stats.served += 100
		rest.stats.criticsPassed += 1
		rest.stats.satisfactionEma = 0.9
		rest.reputation = math.max(rest.reputation, 85)
		rest.cleanliness = 100
		rest.budget += 250000
		RS.markDirty(island)
		return ok()
	end)

	Net.onRequest("GetWorld", function()
		return ok({ world = RS.buildWorldState() })
	end)

	Net.onRequest("Hello", function(player)
		S.Economy.markPlayer(player)
		local island = playerIsland[player]
		if island then
			RS.markDirty(island)
		end
		return ok({ world = RS.buildWorldState() })
	end)
end

-- ===================== LIFECYCLE =====================
function RS.Start()
	local map = workspace:WaitForChild("Map")
	local islandsFolder = map:WaitForChild("Islands")
	for i = 1, MapLayout.IslandCount do
		local model = islandsFolder:WaitForChild("Island" .. i)
		local x, y, z = MapLayout.islandCenter(i)
		local island = {
			index = i,
			model = model,
			theme = MapLayout.Themes[i].name,
			center = Vector3.new(x, y, z),
			cframe = RS.islandCFrame(i),
			roles = {},
		}
		RS.Islands[i] = island
		setSign(island)
	end

	registerRemotes()

	-- spawn placement
	local function onCharacter(player, char)
		task.defer(function()
			local root = char:WaitForChild("HumanoidRootPart", 10)
			if not root then
				return
			end
			task.wait(0.1)
			RS.sendHome(player)
			local role = RS.roleOf(player)
			if role then
				applyRoleEffects(player, role)
			end
		end)
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(c)
			onCharacter(player, c)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end

	S.DataService.onRemoving(function(player)
		invites[player] = nil
		for _, req in pairs(joinRequests) do
			req[player.UserId] = nil
		end
		local island = playerIsland[player]
		if island then
			if island.owner == player then
				RS.unloadIsland(island)
			elseif island.friend == player then
				removeFriend(island)
			end
		end
		roleCooldown[player] = nil
	end)

	-- state flush loop
	task.spawn(function()
		local worldTimer = 0
		while true do
			task.wait(0.5)
			for island in pairs(dirty) do
				dirty[island] = nil
				if island.owner then
					local state = RS.buildState(island)
					for _, m in ipairs(RS.membersOf(island)) do
						Net.push(m, "restaurant", state)
					end
				end
			end
			worldTimer += 0.5
			if worldDirty or worldTimer >= 5 then
				worldDirty = false
				worldTimer = 0
				Net.pushAll("world", RS.buildWorldState())
			end
		end
	end)

	-- activity tracking: a member who moves counts as active
	task.spawn(function()
		while true do
			task.wait(10)
			for player, island in pairs(playerIsland) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local last = lastPositions[player]
					if last and (root.Position - last).Magnitude > 4 then
						island.lastActivity = os.clock()
					end
					lastPositions[player] = root.Position
				end
			end
			for player in pairs(lastPositions) do
				if not player.Parent then
					lastPositions[player] = nil
				end
			end
		end
	end)

	-- invite expiry + periodic refresh of live counters
	task.spawn(function()
		while true do
			task.wait(2)
			for target, map in pairs(invites) do
				for index, inv in pairs(map) do
					if os.time() - inv.t > INVITE_TTL or not inv.from.Parent then
						map[index] = nil
						if target.Parent then
							S.Economy.markPlayer(target)
						end
						local isl = RS.Islands[index]
						RS.markDirty(isl)
					end
				end
			end
			for _, island in pairs(RS.Islands) do
				if island.owner then
					RS.markDirty(island)
				end
			end
		end
	end)
end

return RS
