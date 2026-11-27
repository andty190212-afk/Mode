-- EventService: random restaurant events (rush hour, supplier sale, critic, VIP,
-- inspection, special order, secret recipe), server festival, the 15-minute
-- "best restaurant of the server" contest and global leaderboards.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = Shared.Data
local Events = require(Data.Events)
local Recipes = require(Data.Recipes)

local EventService = {}
local S
local rng = Random.new()

local serverEvent = nil -- {id, untilTime}
local contest = { endsAt = os.time() + Events.ContestDuration, round = 1, lastWinner = nil }
local pendingLeader = {} -- [userId] = earnings delta to push to ODS

local earnStore, starStore
pcall(function()
	earnStore = DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	starStore = DataStoreService:GetOrderedDataStore(Config.LeaderboardStarsStoreName)
end)
local globalTop = { earnings = {}, stars = {} }

function EventService.Init(registry)
	S = registry
end

function EventService.setupIsland(island)
	island.events = { nextAt = os.clock() + rng:NextNumber(Events.Interval[1], Events.Interval[2]), active = {} }
end

local function active(island, id)
	local ev = island.events and island.events.active[id]
	return ev and (ev.untilTime == 0 or ev.untilTime > os.clock())
end

function EventService.guestMultiplier(island)
	local m = 1
	if active(island, "rush") then
		m *= 2
	end
	if serverEvent and serverEvent.untilTime > os.time() then
		m *= 1.25
	end
	if island.criticPenaltyUntil and island.criticPenaltyUntil > os.clock() then
		m *= 0.7
	end
	return m
end

function EventService.priceMultiplier(island)
	return active(island, "sale") and 0.7 or 1
end

function EventService.specialDish(island)
	local ev = island.events and island.events.active.special
	if ev and ev.untilTime > os.clock() then
		return ev.dish
	end
	return nil
end

local function notifyMembers(island, text, kind)
	for _, m in ipairs(S.RestaurantService.membersOf(island)) do
		Net.toast(m, text, kind or "info")
		Net.fx(m, "event", { text = text })
	end
end

function EventService.trigger(island, id)
	local def
	for _, e in ipairs(Events.Random) do
		if e.id == id then
			def = e
		end
	end
	if not def then
		return
	end
	local rest = island.rest
	local now = os.clock()
	if id == "rush" or id == "sale" then
		island.events.active[id] = { untilTime = now + def.duration }
	elseif id == "critic" then
		table.insert(island.guest.forcedQueue, "critic")
		island.guest.nextSpawn = math.min(island.guest.nextSpawn, now + 8)
	elseif id == "vip" then
		table.insert(island.guest.forcedQueue, "vip")
		island.guest.nextSpawn = math.min(island.guest.nextSpawn, now + 8)
	elseif id == "inspection" then
		if rest.cleanliness >= 70 then
			S.Economy.budgetCredit(island, 300 * rest.stars, "event", "Инспекция", "Проверка пройдена")
			rest.reputation = Util.clamp(rest.reputation + 2, 0, 100)
			notifyMembers(island, "🧽✅ Санитарная проверка пройдена! Премия $" .. (300 * rest.stars), "success")
		else
			local fine = math.min(rest.budget, 200 * rest.stars)
			S.Economy.budgetSpend(island, fine, "event", "Инспекция", "Штраф за грязь")
			rest.reputation = Util.clamp(rest.reputation - 3, 0, 100)
			notifyMembers(island, "🧽❌ Грязно! Штраф $" .. fine .. " и -3 репутации. Убирайте столы!", "error")
		end
		return
	elseif id == "special" then
		local options = {}
		local ctx = { chefActive = S.RestaurantService.chefActive(island) }
		for _, r in ipairs(Recipes.Dishes) do
			local m = rest.menu[r.id]
			if m and m.on and Recipes.isAvailable(r, rest, ctx) then
				table.insert(options, r)
			end
		end
		if #options == 0 then
			return
		end
		local r = options[rng:NextInteger(1, #options)]
		island.events.active.special = { untilTime = now + def.duration, dish = r.id }
		notifyMembers(island, "⭐ Особый заказ: гости хотят «" .. r.name .. "» по двойной цене! (4 мин)", "info")
		return
	elseif id == "secret" then
		local locked = {}
		for _, r in ipairs(Recipes.List) do
			if r.rare and not rest.unlockedRecipes[r.id] and r.stars <= rest.stars then
				table.insert(locked, r)
			end
		end
		if #locked == 0 then
			return
		end
		local r = locked[rng:NextInteger(1, #locked)]
		rest.unlockedRecipes[r.id] = true
		notifyMembers(island, "📜 Секретный рецепт открыт: «" .. r.name .. "»!", "success")
		S.RestaurantService.markDirty(island)
		return
	end
	notifyMembers(island, def.icon .. " " .. def.name .. " — " .. def.desc, "info")
	S.RestaurantService.markDirty(island)
end

local function tickIsland(island)
	local ev = island.events
	if not ev or not island.guest then
		return
	end
	local now = os.clock()
	for id, a in pairs(ev.active) do
		if a.untilTime ~= 0 and a.untilTime <= now then
			ev.active[id] = nil
			S.RestaurantService.markDirty(island)
		end
	end
	if now >= ev.nextAt then
		ev.nextAt = now + rng:NextNumber(Events.Interval[1], Events.Interval[2])
		local pool = {}
		for _, e in ipairs(Events.Random) do
			if (e.minStars or 1) <= island.rest.stars then
				table.insert(pool, e)
			end
		end
		local choice = Util.weightedChoice(pool, "weight", rng)
		if choice then
			EventService.trigger(island, choice.id)
		end
	end
end

function EventService.islandEventState(island)
	local out = {}
	if island.events then
		local now = os.clock()
		for id, a in pairs(island.events.active) do
			out[id] = { remaining = a.untilTime == 0 and 0 or math.max(0, math.floor(a.untilTime - now)), dish = a.dish }
		end
	end
	if serverEvent and serverEvent.untilTime > os.time() then
		out.festival = { remaining = serverEvent.untilTime - os.time() }
	end
	return out
end

function EventService.serverEventState()
	if serverEvent and serverEvent.untilTime > os.time() then
		local def = Events.Server[serverEvent.id]
		return { id = serverEvent.id, name = def.name, icon = def.icon, desc = def.desc, remaining = serverEvent.untilTime - os.time() }
	end
	return false
end

-- ===================== CONTEST =====================
local function contestScore(island)
	return math.floor((island.periodRevenue or 0) + island.rest.reputation * 20 + S.BuildService.beautyScore(island) * 2)
end

function EventService.contestState()
	local ranking = {}
	for _, island in pairs(S.RestaurantService.Islands) do
		if island.owner then
			table.insert(ranking, {
				index = island.index,
				name = island.rest.name,
				owner = island.owner.DisplayName,
				score = contestScore(island),
				revenue = math.floor(island.periodRevenue or 0),
				beauty = S.BuildService.beautyScore(island),
			})
		end
	end
	table.sort(ranking, function(a, b)
		return a.score > b.score
	end)
	return {
		remaining = math.max(0, contest.endsAt - os.time()),
		round = contest.round,
		ranking = ranking,
		lastWinner = contest.lastWinner or false,
		top = globalTop,
	}
end

local function finishContest()
	local state = EventService.contestState()
	for place, entry in ipairs(state.ranking) do
		local reward = Events.ContestRewards[place]
		local island = S.RestaurantService.Islands[entry.index]
		if reward and island.owner and #state.ranking >= 2 then
			S.Economy.budgetCredit(island, reward * island.rest.stars, "contest", "Конкурс", place .. " место")
			for _, m in ipairs(S.RestaurantService.membersOf(island)) do
				Net.toast(m, "🏆 Конкурс ресторанов: " .. place .. " место! +$" .. (reward * island.rest.stars) .. " в бюджет", "success")
				if place == 1 then
					S.QuestService.add(m, "contestsWon", 1)
				end
			end
		end
	end
	local winner = state.ranking[1]
	contest.lastWinner = winner and { name = winner.name, owner = winner.owner } or nil
	if winner and #state.ranking >= 2 then
		Net.fxAll("announce", { text = "🥇 Лучший ресторан сервера: «" .. winner.name .. "» (" .. winner.owner .. ")" })
	end
	for _, island in pairs(S.RestaurantService.Islands) do
		island.periodRevenue = 0
	end
	contest.round += 1
	contest.endsAt = os.time() + Events.ContestDuration
end

-- ===================== LEADERBOARD =====================
function EventService.trackLeaderEarnings(player, amount)
	pendingLeader[player.UserId] = true
end

local function flushLeaderboards()
	if not earnStore then
		return
	end
	for userId in pairs(pendingLeader) do
		pendingLeader[userId] = nil
		local player = Players:GetPlayerByUserId(userId)
		local p = player and S.DataService.get(player)
		if p and not p.temporary then
			pcall(function()
				earnStore:SetAsync("u_" .. userId, math.floor(p.data.stats.moneyEarned))
				starStore:SetAsync("u_" .. userId, math.floor(p.data.restaurant.stars * 1000000 + p.data.restaurant.stats.served))
			end)
		end
		task.wait(1)
	end
	local function read(store)
		local out = {}
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, 10)
		end)
		if ok and pages then
			for rank, entry in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(string.sub(entry.key, 3))
				local name = "?"
				pcall(function()
					name = Players:GetNameFromUserIdAsync(uid)
				end)
				table.insert(out, { rank = rank, name = name, value = entry.value })
			end
		end
		return out
	end
	globalTop.earnings = read(earnStore)
	globalTop.stars = read(starStore)
	for _, row in ipairs(globalTop.stars) do
		row.stars = math.floor(row.value / 1000000)
		row.served = row.value % 1000000
	end
end

function EventService.Start()
	task.spawn(function()
		while true do
			task.wait(2)
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.owner then
					local ok, err = pcall(tickIsland, island)
					if not ok then
						warn("[EventService] " .. tostring(err))
					end
				end
			end
			if os.time() >= contest.endsAt then
				pcall(finishContest)
				S.RestaurantService.markWorld()
			end
		end
	end)
	-- server-wide festival
	task.spawn(function()
		while true do
			task.wait(Events.ServerFestivalInterval * rng:NextNumber(0.8, 1.2))
			serverEvent = { id = "festival", untilTime = os.time() + Events.Server.festival.duration }
			Net.fxAll("announce", { text = "🎉 " .. Events.Server.festival.name .. ": " .. Events.Server.festival.desc })
			S.RestaurantService.markWorld()
		end
	end)
	task.spawn(function()
		task.wait(20)
		while true do
			pcall(flushLeaderboards)
			S.RestaurantService.markWorld()
			task.wait(300)
		end
	end)
end

return EventService
