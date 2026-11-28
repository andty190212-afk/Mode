-- EconomyService: personal money, restaurant budget (separate!), XP/levels,
-- earnings multipliers, ledger/history and the personal state replication.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local Economy = {}
local S
local dirtyPlayers = {}

function Economy.Init(registry)
	S = registry
end

local function profileOf(player)
	return S.DataService.get(player)
end

function Economy.markPlayer(player)
	dirtyPlayers[player] = true
end

-- ===================== BOOSTS =====================
function Economy.boostMult(player)
	local p = profileOf(player)
	if not p then
		return 1
	end
	local b = p.data.boosts
	if b and b.untilTime > os.time() then
		return b.mult
	end
	return 1
end

function Economy.addBoost(player, mult, minutes)
	local p = profileOf(player)
	if not p then
		return false
	end
	local b = p.data.boosts
	local now = os.time()
	if b.untilTime > now and b.mult == mult then
		b.untilTime += minutes * 60
	elseif b.untilTime > now and b.mult > mult then
		-- уже действует более сильный множитель: добавляем время с пересчётом
		b.untilTime += math.floor(minutes * 60 * mult / b.mult)
	else
		local remaining = math.max(0, b.untilTime - now)
		b.mult = mult
		b.untilTime = now + minutes * 60 + math.floor(remaining * 0.5)
	end
	Economy.markPlayer(player)
	return true
end

-- ===================== PERSONAL MONEY =====================
local function pushIncome(data, amount, src)
	table.insert(data.income, 1, { t = os.time(), a = math.floor(amount), s = src })
	while #data.income > 40 do
		table.remove(data.income)
	end
end

-- Earned money (affected by boosts). Returns actual amount.
function Economy.earn(player, amount, src, noBoost)
	local p = profileOf(player)
	if not p or amount <= 0 then
		return 0
	end
	local mult = noBoost and 1 or Economy.boostMult(player)
	local total = math.floor(amount * mult + 0.5)
	p.data.money += total
	pushIncome(p.data, total, src)
	S.QuestService.add(player, "moneyEarned", total)
	Economy.markPlayer(player)
	S.EventService.trackLeaderEarnings(player, total)
	return total
end

-- Money granted (rewards, purchases) - not boosted, not counted as earnings quests
function Economy.grant(player, amount, src)
	local p = profileOf(player)
	if not p then
		return false
	end
	p.data.money += math.floor(amount)
	pushIncome(p.data, amount, src)
	Economy.markPlayer(player)
	return true
end

function Economy.canAfford(player, amount)
	local p = profileOf(player)
	return p ~= nil and amount >= 0 and p.data.money >= amount
end

function Economy.spend(player, amount, src)
	local p = profileOf(player)
	if not p or amount < 0 or not Util.isFiniteNumber(amount) then
		return false
	end
	amount = math.floor(amount)
	if p.data.money < amount then
		return false
	end
	p.data.money -= amount
	pushIncome(p.data, -amount, src)
	Economy.markPlayer(player)
	return true
end

-- ===================== XP =====================
function Economy.addXp(player, amount)
	local p = profileOf(player)
	if not p then
		return
	end
	local d = p.data
	local island = S.RestaurantService.islandOf(player)
	if island then
		amount *= S.LabService.mult(island, "xp") -- бонус существ лаборатории
	end
	d.xp += math.floor(amount)
	local leveled = false
	while d.level < Config.MaxPlayerLevel and d.xp >= Config.XpForLevel(d.level) do
		d.xp -= Config.XpForLevel(d.level)
		d.level += 1
		leveled = true
	end
	if leveled then
		Net.toast(player, "⬆️ Новый уровень игрока: " .. d.level .. "! Бонус $" .. (d.level * 50), "success")
		Economy.grant(player, d.level * 50, "Уровень")
		Net.fx(player, "levelup", { level = d.level })
		Economy.updateLeaderstats(player)
	end
	Economy.markPlayer(player)
end

function Economy.addProfXp(player, prof, amount)
	local p = profileOf(player)
	if not p or not p.data.prof[prof] then
		return
	end
	local pr = p.data.prof[prof]
	pr.xp += math.floor(amount)
	local leveled = false
	while pr.level < Config.MaxProfLevel and pr.xp >= Config.XpForProfLevel(pr.level) do
		pr.xp -= Config.XpForProfLevel(pr.level)
		pr.level += 1
		leveled = true
	end
	if leveled then
		local names = { Cook = "Повар", Waiter = "Официант", Chef = "Шеф-повар", Director = "Директор" }
		Net.toast(player, "🎖️ " .. (names[prof] or prof) .. ": уровень " .. pr.level, "success")
		Net.fx(player, "levelup", { prof = prof, level = pr.level })
		S.RestaurantService.onProfessionLevel(player, prof)
	end
	Economy.markPlayer(player)
end

function Economy.profLevel(player, prof)
	local p = profileOf(player)
	return p and p.data.prof[prof] and p.data.prof[prof].level or 1
end

-- ===================== RESTAURANT BUDGET =====================
local function ledger(rest, kind, amount, who, note)
	table.insert(rest.ledger, 1, { t = os.time(), k = kind, a = math.floor(amount), w = who or "", n = note or "" })
	while #rest.ledger > 60 do
		table.remove(rest.ledger)
	end
end
Economy.ledger = ledger

-- Income to the restaurant budget (sales). Boost of the best member applies.
function Economy.budgetIncome(island, amount, kind, who, note)
	local rest = island.rest
	if not rest or amount <= 0 then
		return 0
	end
	local mult = 1
	for _, member in ipairs(S.RestaurantService.membersOf(island)) do
		mult = math.max(mult, Economy.boostMult(member))
	end
	local total = math.floor(amount * mult + 0.5)
	rest.budget += total
	rest.stats.revenue += total
	island.periodRevenue = (island.periodRevenue or 0) + total
	if kind ~= "sale" then
		ledger(rest, kind, total, who, note)
	else
		-- продажи агрегируются, чтобы не засорять журнал
		local top = rest.ledger[1]
		if top and top.k == "sale" and os.time() - top.t < 60 then
			top.a += total
			top.t = os.time()
		else
			ledger(rest, "sale", total, "Гости", "Продажи")
		end
	end
	S.RestaurantService.markDirty(island)
	return total
end

-- Non-boosted credit (deposits, rewards)
function Economy.budgetCredit(island, amount, kind, who, note)
	local rest = island.rest
	if not rest or amount <= 0 then
		return false
	end
	rest.budget += math.floor(amount)
	ledger(rest, kind, amount, who, note)
	S.RestaurantService.markDirty(island)
	return true
end

-- category: ingredientCost | wages | upgrades
function Economy.budgetSpend(island, amount, kind, who, note, category)
	local rest = island.rest
	if not rest or amount < 0 or not Util.isFiniteNumber(amount) then
		return false
	end
	amount = math.floor(amount + 0.5)
	if rest.budget < amount then
		return false
	end
	rest.budget -= amount
	rest.stats.expenses += amount
	if category and rest.stats[category] then
		rest.stats[category] += amount
	end
	if kind == "wages" then
		local top = rest.ledger[1]
		if top and top.k == "wages" and os.time() - top.t < 120 then
			top.a -= amount
			top.t = os.time()
		else
			ledger(rest, kind, -amount, who, note)
		end
	else
		ledger(rest, kind, -amount, who, note)
	end
	S.RestaurantService.markDirty(island)
	return true
end

-- Кто может тратить бюджет: владелец; друг — только если владелец разрешил (с дневным лимитом)
function Economy.canSpendBudget(player, island, amount)
	if island.owner == player then
		return true
	end
	if island.friend == player and island.rest.friendCanSpend then
		local day = Util.dayNumber()
		if island.friendSpendDay ~= day then
			island.friendSpendDay = day
			island.friendSpent = 0
		end
		if (island.friendSpent or 0) + amount <= Config.FriendDailySpendLimit then
			return true
		end
		return false, "Дневной лимит трат друга: $" .. Config.FriendDailySpendLimit
	end
	return false, "Нет прав тратить бюджет ресторана"
end

function Economy.noteFriendSpend(player, island, amount)
	if island.friend == player then
		island.friendSpent = (island.friendSpent or 0) + amount
	end
end

-- Spend from the restaurant budget on behalf of a player (permission checked)
function Economy.playerSpendBudget(player, island, amount, kind, note, category)
	local allowed, why = Economy.canSpendBudget(player, island, amount)
	if not allowed then
		return false, why
	end
	if not Economy.budgetSpend(island, amount, kind, player.DisplayName, note, category) then
		return false, "Недостаточно денег в бюджете ресторана"
	end
	Economy.noteFriendSpend(player, island, amount)
	return true
end

-- ===================== LEADERSTATS =====================
function Economy.updateLeaderstats(player)
	local p = profileOf(player)
	if not p then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local money = Instance.new("IntValue")
		money.Name = "💵 Деньги"
		money.Parent = ls
		local stars = Instance.new("IntValue")
		stars.Name = "⭐ Звёзды"
		stars.Parent = ls
		local lvl = Instance.new("IntValue")
		lvl.Name = "Уровень"
		lvl.Parent = ls
		ls.Parent = player
	end
	ls["💵 Деньги"].Value = math.min(2 ^ 31 - 1, p.data.money)
	ls["Уровень"].Value = p.data.level
	local island = S.RestaurantService.islandOf(player)
	ls["⭐ Звёзды"].Value = island and island.rest and island.rest.stars or 0
end

-- ===================== STATE REPLICATION =====================
function Economy.buildPlayerState(player)
	local p = profileOf(player)
	if not p then
		return nil
	end
	local d = p.data
	local island = S.RestaurantService.islandOf(player)
	local profs = {}
	for k, v in pairs(d.prof) do
		profs[k] = { level = v.level, xp = v.xp, need = Config.XpForProfLevel(v.level) }
	end
	return {
		lang = d.settings and d.settings.lang or "",
		admin = S.AdminService and S.AdminService.isAdmin(player) or false,
		userId = player.UserId,
		money = d.money,
		level = d.level,
		xp = d.xp,
		xpNeed = Config.XpForLevel(d.level),
		prof = profs,
		stats = d.stats,
		income = d.income,
		boost = { mult = d.boosts.mult, remaining = math.max(0, d.boosts.untilTime - os.time()) },
		daily = S.QuestService.dailyState(player),
		quests = S.QuestService.questState(player),
		achievements = d.achievements,
		helicopters = d.helicopters,
		island = island and island.index or 0,
		isOwner = island ~= nil and island.owner == player,
		role = S.RestaurantService.roleOf(player) or "",
		passes = S.MonetizationService.passState(player),
		products = S.MonetizationService.productList(),
		invites = S.RestaurantService.invitesFor(player),
		temporaryData = p.temporary == true,
		ownsRestaurantData = (d.restaurant.stats.served or 0) > 0 or (d.restaurant.stars or 1) > 1,
		savedStars = d.restaurant.stars,
	}
end

function Economy.Start()
	S.DataService.onLoaded(function(player)
		Economy.updateLeaderstats(player)
		Economy.markPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirtyPlayers[player] = nil
	end)
	-- Flush loop
	task.spawn(function()
		while true do
			task.wait(0.35)
			for player in pairs(dirtyPlayers) do
				dirtyPlayers[player] = nil
				if player.Parent then
					local state = Economy.buildPlayerState(player)
					if state then
						Net.push(player, "player", state)
						Economy.updateLeaderstats(player)
					end
				end
			end
		end
	end)
	-- Play time + periodic refresh of boost timer
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in ipairs(Players:GetPlayers()) do
				local p = profileOf(player)
				if p then
					p.data.stats.playSeconds += 30
					Economy.markPlayer(player)
				end
			end
		end
	end)
end

return Economy
