-- QuestService: player statistics, daily & weekly quests, achievements (with rare
-- recipe unlocks), daily login rewards with streaks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Quests = require(Shared.Data.Quests)
local Recipes = require(Shared.Data.Recipes)

local QuestService = {}
local S

function QuestService.Init(registry)
	S = registry
end

local function profile(player)
	return S.DataService.get(player)
end

local function rollQuests(pool, count, seed)
	local rng = Random.new(seed)
	local list = table.clone(pool)
	Util.shuffle(list, rng)
	local out = {}
	for i = 1, math.min(count, #list) do
		local q = list[i]
		-- лёгкая вариативность цели
		local goal = math.floor(q.goal * rng:NextNumber(0.8, 1.25))
		table.insert(out, { id = q.id, goal = goal, progress = 0, claimed = false })
	end
	return out
end

local function ensureQuests(player)
	local p = profile(player)
	if not p then
		return
	end
	local q = p.data.quests
	local day = Util.dayNumber()
	if q.day ~= day then
		q.day = day
		q.daily = rollQuests(Quests.DailyPool, Quests.DailyCount, day * 7919 + player.UserId % 1000)
	end
	local week = Util.weekNumber()
	if q.week ~= week then
		q.week = week
		q.weekly = rollQuests(Quests.WeeklyPool, Quests.WeeklyCount, week * 104729 + player.UserId % 1000)
	end
end

local function checkAchievements(player, stat)
	local p = profile(player)
	if not p then
		return
	end
	local d = p.data
	for _, a in ipairs(Quests.Achievements) do
		if a.stat == stat and not d.achievements[a.id] and (d.stats[stat] or 0) >= a.goal then
			d.achievements[a.id] = os.time()
			S.Economy.grant(player, a.money, "Достижение")
			local text = "🏆 Достижение «" .. a.name .. "»! +$" .. a.money
			if a.recipe then
				d.restaurant.unlockedRecipes[a.recipe] = true
				local r = Recipes.ById[a.recipe]
				text ..= " и редкий рецепт «" .. (r and r.name or a.recipe) .. "»"
				local island = S.RestaurantService.islandOf(player)
				if island then
					if island.rest ~= d.restaurant then
						island.rest.unlockedRecipes[a.recipe] = true
					end
					S.RestaurantService.markDirty(island)
				end
			end
			Net.toast(player, text, "success")
			Net.fx(player, "achievement", { id = a.id })
		end
	end
end

function QuestService.add(player, stat, amount)
	local p = profile(player)
	if not p or not amount or amount == 0 then
		return
	end
	local stats = p.data.stats
	stats[stat] = (stats[stat] or 0) + amount
	ensureQuests(player)
	local q = p.data.quests
	for _, list in ipairs({ q.daily, q.weekly }) do
		for _, quest in ipairs(list) do
			local def = Quests.DailyById[quest.id]
			if def and def.stat == stat and not quest.claimed and quest.progress < quest.goal then
				quest.progress = math.min(quest.goal, quest.progress + amount)
				if quest.progress >= quest.goal then
					Net.toast(player, "✅ Задание выполнено! Заберите награду в меню «Задания»", "success")
				end
			end
		end
	end
	checkAchievements(player, stat)
	S.Economy.markPlayer(player)
end

function QuestService.set(player, stat, value)
	local p = profile(player)
	if not p then
		return
	end
	p.data.stats[stat] = value
	checkAchievements(player, stat)
	S.Economy.markPlayer(player)
end

function QuestService.questState(player)
	ensureQuests(player)
	local p = profile(player)
	if not p then
		return {}
	end
	local function map(list, weekly)
		local out = {}
		for i, quest in ipairs(list) do
			local def = Quests.DailyById[quest.id]
			if def then
				table.insert(out, {
					index = i,
					weekly = weekly,
					text = string.format(def.text, quest.goal),
					goal = quest.goal,
					progress = quest.progress,
					claimed = quest.claimed,
					money = def.money,
					xp = def.xp,
				})
			end
		end
		return out
	end
	local now = os.time()
	return {
		daily = map(p.data.quests.daily, false),
		weekly = map(p.data.quests.weekly, true),
		dailyReset = 86400 - (now % 86400),
	}
end

function QuestService.dailyState(player)
	local p = profile(player)
	if not p then
		return {}
	end
	local d = p.data.daily
	local today = Util.dayNumber()
	local streak = d.streak
	if d.lastDay < today - 1 then
		streak = 0
	end
	local nextIndex = (streak % #Quests.DailyRewards) + 1
	return {
		canClaim = d.lastDay < today,
		streak = streak,
		nextReward = Quests.DailyRewards[nextIndex],
		rewards = Quests.DailyRewards,
	}
end

function QuestService.Start()
	S.DataService.onLoaded(function(player)
		ensureQuests(player)
		S.Economy.markPlayer(player)
	end)

	Net.onRequest("ClaimDaily", function(player)
		local p = profile(player)
		if not p then
			return { ok = false }
		end
		local d = p.data.daily
		local today = Util.dayNumber()
		if d.lastDay >= today then
			return { ok = false, err = "Награда уже получена сегодня" }
		end
		if d.lastDay < today - 1 then
			d.streak = 0
		end
		local index = (d.streak % #Quests.DailyRewards) + 1
		local reward = Quests.DailyRewards[index]
		d.streak += 1
		d.lastDay = today
		S.Economy.grant(player, reward, "Ежедневная награда")
		S.Economy.addXp(player, 50 * index)
		Net.toast(player, "🎁 Ежедневная награда: $" .. reward .. " (день " .. index .. ")", "success")
		S.Economy.markPlayer(player)
		return { ok = true, reward = reward }
	end)

	Net.onRequest("ClaimQuest", function(player, payload)
		local p = profile(player)
		if not p then
			return { ok = false }
		end
		ensureQuests(player)
		local list = payload and payload.weekly == true and p.data.quests.weekly or p.data.quests.daily
		local quest = list[tonumber(payload and payload.index) or 0]
		if not quest then
			return { ok = false, err = "Задание не найдено" }
		end
		if quest.claimed then
			return { ok = false, err = "Награда уже получена" }
		end
		if quest.progress < quest.goal then
			return { ok = false, err = "Задание ещё не выполнено" }
		end
		local def = Quests.DailyById[quest.id]
		quest.claimed = true
		S.Economy.grant(player, def.money, "Задание")
		S.Economy.addXp(player, def.xp)
		Net.fx(player, "upgrade", {})
		S.Economy.markPlayer(player)
		return { ok = true }
	end)
end

return QuestService
