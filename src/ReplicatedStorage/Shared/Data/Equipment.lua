-- Kitchen & bar equipment upgrades (bought from the restaurant budget).
-- Max level of each item is limited by the restaurant star rating.
local Equipment = {}

Equipment.List = {
	{ id = "stove", name = "Плита", icon = "🔥", base = 300, desc = "Быстрее жарка и варка (+8%/ур.)", effect = { cookSpeed = 0.08 } },
	{ id = "oven", name = "Духовка", icon = "♨️", base = 400, desc = "Выпечка лучше (+4% качества/ур.)", effect = { quality = 0.04 } },
	{ id = "fridge", name = "Холодильник", icon = "🧊", base = 350, desc = "Свежие продукты (+3% качества/ур.)", effect = { quality = 0.03 } },
	{ id = "freezer", name = "Морозильник", icon = "❄️", base = 450, desc = "+80 мест на складе/ур.", effect = { storage = 80 } },
	{ id = "prep", name = "Рабочие поверхности", icon = "🔪", base = 300, desc = "Быстрее подготовка (+6%/ур.)", effect = { cookSpeed = 0.06 } },
	{ id = "coffee", name = "Кофемашина", icon = "☕", base = 500, desc = "Открывает кофейные напитки", effect = { drinkSpeed = 0.05 } },
	{ id = "bar", name = "Барное оборудование", icon = "🍹", base = 450, desc = "Напитки быстрее и лучше (+6%/ур.)", effect = { drinkSpeed = 0.06, drinkQuality = 0.03 } },
	{ id = "dishwasher", name = "Посудомоечная машина", icon = "🫧", base = 380, desc = "Быстрая уборка, чистота (+15%/ур.)", effect = { cleanSpeed = 0.15 } },
}

-- оборудование кухни, которое повар может улучшать сам
Equipment.Kitchen = { stove = true, oven = true, fridge = true, freezer = true, prep = true }

Equipment.ById = {}
for i, e in ipairs(Equipment.List) do
	e.order = i
	Equipment.ById[e.id] = e
end

Equipment.MaxLevel = 5
Equipment.Start = { stove = 1, oven = 1, fridge = 1, freezer = 0, prep = 1, coffee = 0, bar = 1, dishwasher = 0 }

function Equipment.costFor(id, nextLevel)
	local e = Equipment.ById[id]
	return math.floor(e.base * (2.6 ^ (nextLevel - 1)) / 10) * 10
end

-- Максимальный уровень: равен рейтингу ресторана (★1 -> ур.1 ... ★5 -> ур.5)
function Equipment.maxLevelFor(stars)
	return math.clamp(stars, 1, Equipment.MaxLevel)
end

function Equipment.bonus(equipmentLevels, key)
	local total = 0
	for id, lvl in pairs(equipmentLevels or {}) do
		local e = Equipment.ById[id]
		if e and e.effect[key] then
			total += e.effect[key] * lvl
		end
	end
	return total
end

function Equipment.totalLevels(equipmentLevels)
	local t = 0
	for _, lvl in pairs(equipmentLevels or {}) do
		t += lvl
	end
	return t
end

-- Склад
Equipment.StorageBase = 900
Equipment.StoragePerLevel = 300
Equipment.StorageMaxLevel = 10
function Equipment.storageUpgradeCost(nextLevel)
	return math.floor(250 * (1.9 ^ (nextLevel - 2)) / 10) * 10
end
function Equipment.storageCapacity(rest)
	return Equipment.StorageBase
		+ Equipment.StoragePerLevel * ((rest.storageLevel or 1) - 1)
		+ Equipment.bonus(rest.equipment, "storage")
end

return Equipment
