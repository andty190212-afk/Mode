-- ShopService: ingredient purchasing (restaurant budget), storage capacity,
-- kitchen/bar equipment upgrades.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Data = Shared.Data
local Ingredients = require(Data.Ingredients)
local Equipment = require(Data.Equipment)
local Recipes = require(Data.Recipes)

local ShopService = {}
local S

function ShopService.Init(registry)
	S = registry
end

function ShopService.storageUsed(rest)
	local n = 0
	for _, c in pairs(rest.inventory) do
		n += c
	end
	return n
end

function ShopService.ingredientPrice(island, item)
	local mult = S.EventService.priceMultiplier(island)
	return item.price * mult
end

local function isAvailable(item, rest)
	if item.minStars > rest.stars then
		return false, "Откроется на " .. item.minStars .. "★"
	end
	if item.season and item.season ~= Recipes.currentSeason() then
		return false, "Сезонный продукт"
	end
	return true
end

function ShopService.Start()
	Net.onRequest("BuyIngredient", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local item = payload and type(payload.id) == "string" and Ingredients.ById[payload.id]
		local packs = math.floor(tonumber(payload and payload.packs) or 1)
		if not item or packs < 1 or packs > 20 then
			return { ok = false, err = "Некорректная покупка" }
		end
		local avail, why = isAvailable(item, island.rest)
		if not avail then
			return { ok = false, err = why }
		end
		local qty = packs * Config.IngredientPack
		local cap = Equipment.storageCapacity(island.rest)
		local used = ShopService.storageUsed(island.rest)
		if used + qty > cap then
			qty = math.floor((cap - used) / Config.IngredientPack) * Config.IngredientPack
			if qty <= 0 then
				return { ok = false, err = "Склад заполнен (" .. used .. "/" .. cap .. "). Улучшите склад." }
			end
		end
		local cost = math.ceil(ShopService.ingredientPrice(island, item) * qty)
		-- закупка продуктов — рабочая операция: доступна обоим участникам
		if not S.Economy.budgetSpend(island, cost, "ingredients", player.DisplayName, item.name .. " x" .. qty, "ingredientCost") then
			return { ok = false, err = "Недостаточно денег в бюджете ресторана ($" .. cost .. ")" }
		end
		island.rest.inventory[item.id] = (island.rest.inventory[item.id] or 0) + qty
		S.QuestService.add(player, "ingredientsBought", qty)
		S.Economy.addXp(player, 1)
		S.RestaurantService.markDirty(island)
		return { ok = true, qty = qty, cost = cost }
	end)

	-- Быстрая закупка: докупить всё, чего не хватает для включённых блюд меню
	Net.onRequest("RestockMenu", function(player)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local rest = island.rest
		local need = {}
		local ctx = { chefActive = S.RestaurantService.chefActive(island) }
		for _, r in ipairs(Recipes.List) do
			local m = rest.menu[r.id]
			if m and m.on and Recipes.isAvailable(r, rest, ctx) then
				for id, n in pairs(r.ing) do
					need[id] = math.max(need[id] or 0, n * 6)
				end
			end
		end
		local spent, bought = 0, 0
		local cap = Equipment.storageCapacity(rest)
		for id, target in pairs(need) do
			local item = Ingredients.ById[id]
			local have = rest.inventory[id] or 0
			if have < target and isAvailable(item, rest) then
				local packs = math.ceil((target - have) / Config.IngredientPack)
				local qty = packs * Config.IngredientPack
				if ShopService.storageUsed(rest) + qty > cap then
					break
				end
				local cost = math.ceil(ShopService.ingredientPrice(island, item) * qty)
				if not S.Economy.budgetSpend(island, cost, "ingredients", player.DisplayName, item.name .. " x" .. qty, "ingredientCost") then
					break
				end
				rest.inventory[id] = have + qty
				spent += cost
				bought += qty
			end
		end
		if bought == 0 then
			return { ok = false, err = "Нечего докупать или не хватает бюджета/места" }
		end
		S.QuestService.add(player, "ingredientsBought", bought)
		S.RestaurantService.markDirty(island)
		return { ok = true, qty = bought, cost = spent }
	end)

	Net.onRequest("UpgradeStorage", function(player)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local rest = island.rest
		local nextLevel = rest.storageLevel + 1
		if nextLevel > Equipment.StorageMaxLevel then
			return { ok = false, err = "Склад максимального уровня" }
		end
		local cost = Equipment.storageUpgradeCost(nextLevel)
		local okSpend, why = S.Economy.playerSpendBudget(player, island, cost, "upgrade", "Склад ур." .. nextLevel, "upgrades")
		if not okSpend then
			return { ok = false, err = why }
		end
		rest.storageLevel = nextLevel
		Net.fx(player, "upgrade", {})
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)

	Net.onRequest("UpgradeEquipment", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local id = payload and payload.id
		local def = type(id) == "string" and Equipment.ById[id]
		if not def then
			return { ok = false, err = "Нет такого оборудования" }
		end
		local rest = island.rest
		local cur = rest.equipment[id] or 0
		local nextLevel = cur + 1
		if nextLevel > Equipment.maxLevelFor(rest.stars) then
			return { ok = false, err = "Следующий уровень откроется на " .. nextLevel .. "★" }
		end
		local cost = Equipment.costFor(id, nextLevel)
		local okSpend, why = S.Economy.playerSpendBudget(player, island, cost, "equipment", def.name .. " ур." .. nextLevel, "upgrades")
		if not okSpend then
			return { ok = false, err = why }
		end
		rest.equipment[id] = nextLevel
		Net.fx(player, "upgrade", {})
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)
end

return ShopService
