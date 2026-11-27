-- RatingService: 1..5 star progression. Promotion requires real performance
-- (served guests, reputation, satisfaction, menu, interior, equipment, cleanliness,
-- team experience, critics) plus a fee. The restaurant building is rebuilt per tier.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Data = Shared.Data
local Stars = require(Data.Stars)
local Recipes = require(Data.Recipes)
local Equipment = require(Data.Equipment)

local RatingService = {}
local S

function RatingService.Init(registry)
	S = registry
end

function RatingService.metrics(island)
	local rest = island.rest
	local ctx = { chefActive = S.RestaurantService.chefActive(island) }
	local menu = 0
	for _, r in ipairs(Recipes.List) do
		local m = rest.menu[r.id]
		if m and m.on and Recipes.isAvailable(r, rest, ctx) then
			menu += 1
		end
	end
	local staffLevel = 0
	for _, p in ipairs(S.RestaurantService.membersOf(island)) do
		local role = S.RestaurantService.roleOf(p)
		if role then
			staffLevel += S.Economy.profLevel(p, role)
		end
	end
	for _, m in ipairs(rest.staff) do
		staffLevel += m.level
	end
	if S.RestaurantService.chefActive(island) then
		staffLevel += rest.chefNpc.level
	end
	return {
		served = rest.stats.served,
		reputation = math.floor(rest.reputation),
		satisfaction = math.floor(rest.stats.satisfactionEma * 100 + 0.5) / 100,
		menu = menu,
		interior = math.floor(S.BuildService.beautyScore(island)),
		equipment = Equipment.totalLevels(rest.equipment),
		cleanliness = math.floor(rest.cleanliness),
		staffLevel = staffLevel,
		critics = rest.stats.criticsPassed,
		budget = math.floor(rest.budget),
	}
end

function RatingService.evaluate(island)
	local m = RatingService.metrics(island)
	local nextStar = island.rest.stars + 1
	if nextStar > 5 then
		return m, {}, false
	end
	local all, rows = Stars.check(nextStar, m)
	return m, rows, all
end

-- rebuild the restaurant building/kitchen/tables for the current star level
function RatingService.rebuild(island)
	S.GuestService.clearIsland(island)
	S.GuestService.setupIsland(island)
	S.RestaurantService.spawnBuilding(island)
	S.BuildService.respawnFurniture(island)
	S.KitchenService.clearIsland(island)
	S.KitchenService.setupIsland(island)
	S.StaffService.rebind(island)
	S.RestaurantService.setSign(island)
end

-- Только для Roblox Studio: сразу выбрать уровень ресторана 1..5 (без условий и взноса)
function RatingService.debugSetStars(player, stars)
	if not game:GetService("RunService"):IsStudio() then
		return { ok = false, err = "Доступно только в Roblox Studio" }
	end
	local island = S.RestaurantService.islandOf(player)
	if not island or island.owner ~= player then
		return { ok = false, err = "Нужен свой ресторан" }
	end
	stars = math.floor(tonumber(stars) or 0)
	if stars < 1 or stars > 5 then
		return { ok = false, err = "Уровень от 1 до 5" }
	end
	local rest = island.rest
	rest.stars = stars
	-- мебель, которая не помещается в меньший зал, продаётся (возврат 50%)
	local Furniture = require(game:GetService("ReplicatedStorage").Shared.Data.Furniture)
	local BuildRules = require(game:GetService("ReplicatedStorage").Shared.BuildRules)
	for i = #rest.furniture, 1, -1 do
		local e = rest.furniture[i]
		local okPlace = BuildRules.validate(rest, "furniture", e.id, e.x, e.z, e.r or 0, e.uid)
		if not okPlace then
			table.remove(rest.furniture, i)
			local def = Furniture.ById[e.id]
			if def then
				rest.budget += math.floor(def.price * 0.5)
			end
		end
	end
	-- оборудование не выше нового уровня
	for id, lvl in pairs(rest.equipment) do
		if lvl > stars then
			rest.equipment[id] = stars
		end
	end
	RatingService.rebuild(island)
	for _, m in ipairs(S.RestaurantService.membersOf(island)) do
		Net.fx(m, "starUp", { stars = stars })
	end
	S.Economy.updateLeaderstats(player)
	S.RestaurantService.markDirty(island)
	S.RestaurantService.markWorld()
	return { ok = true, stars = stars }
end

function RatingService.promote(player)
	local island = S.RestaurantService.islandOf(player)
	if not island or island.owner ~= player then
		return { ok = false, err = "Повышать рейтинг может только владелец" }
	end
	local rest = island.rest
	local nextStar = rest.stars + 1
	if nextStar > 5 then
		return { ok = false, err = "У вас уже 5 звёзд!" }
	end
	local _, rows, canPromote = RatingService.evaluate(island)
	if not canPromote then
		local missing = {}
		for _, r in ipairs(rows) do
			if not r.ok then
				table.insert(missing, r.label)
			end
		end
		return { ok = false, err = "Не выполнено: " .. table.concat(missing, ", ") }
	end
	local fee = Stars.Requirements[nextStar].fee
	if not S.Economy.budgetSpend(island, fee, "star", player.DisplayName, "Повышение до " .. nextStar .. "★", "upgrades") then
		return { ok = false, err = "Недостаточно бюджета на взнос" }
	end
	rest.stars = nextStar
	RatingService.rebuild(island)
	for _, m in ipairs(S.RestaurantService.membersOf(island)) do
		local profile = S.DataService.get(m)
		if profile and profile.data.stats.maxStars < nextStar then
			S.QuestService.set(m, "maxStars", nextStar)
		end
		Net.fx(m, "starUp", { stars = nextStar })
		S.Economy.addXp(m, 200 * nextStar)
	end
	Net.fxAll("announce", { text = "🌟 Ресторан «" .. rest.name .. "» получил " .. nextStar .. "★!" })
	S.Economy.updateLeaderstats(player)
	S.RestaurantService.markDirty(island)
	S.RestaurantService.markWorld()
	return { ok = true, stars = nextStar }
end

function RatingService.Start()
	Net.onRequest("PromoteStar", function(player)
		return RatingService.promote(player)
	end)
	Net.onRequest("DebugSetStars", function(player, payload)
		return RatingService.debugSetStars(player, payload and payload.stars)
	end)
	-- reputation drifts slowly towards satisfaction when idle
	task.spawn(function()
		while true do
			task.wait(30)
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.rest then
					local target = island.rest.stats.satisfactionEma * 100
					island.rest.reputation += (target - island.rest.reputation) * 0.01
				end
			end
		end
	end)
end

return RatingService
