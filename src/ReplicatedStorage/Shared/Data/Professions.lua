-- The four unique restaurant jobs. Only one real player per job per restaurant.
local Professions = {}

Professions.Order = { "Cook", "Waiter", "Chef", "Director" }

Professions.ById = {
	Cook = {
		id = "Cook", name = "Повар", icon = "🍳", paid = false, price = 0,
		desc = "Закупает продукты и сам готовит блюда в мини-играх. Качество зависит от вашей точности.",
		perks = { "Мини-игры: нарезка, жарка, варка, выпечка, сборка, украшение", "Сам улучшает плиту и кухню", "Плита 5 ур. → кухонный робот готовит за вас" },
	},
	Waiter = {
		id = "Waiter", name = "Официант", icon = "🧑‍💼", paid = false, price = 0,
		desc = "Принимает заказы, разносит блюда и напитки, убирает столы и получает чаевые.",
		perks = { "Скорость передвижения растёт с уровнем", "Носит до 4 заказов сразу", "Больше чаевых, VIP-клиенты" },
	},
	Chef = {
		id = "Chef", name = "Шеф-повар", icon = "👨‍🍳", paid = true, price = 80, pass = "Chef",
		desc = "На кухне работает ваш NPC-повар. Вы управляете кухней и открываете фирменные блюда.",
		perks = { "NPC-повар готовит вместо вас", "Фирменные рецепты шефа", "+10% к качеству блюд", "Прокачка NPC-повара" },
	},
	Director = {
		id = "Director", name = "Директор ресторана", icon = "🎩", paid = true, price = 100, pass = "Director",
		desc = "Нанимает NPC-поваров, официантов и барменов, назначает зарплаты, управляет меню и ценами.",
		perks = { "Найм и обучение NPC (5 уровней)", "Зарплаты и контроль расходов", "Меню, цены, статистика" },
	},
}

-- Бонусы профессии от её уровня
function Professions.waiterCarry(level)
	return math.min(4, 1 + math.floor(level / 6))
end
function Professions.waiterSpeed(level)
	return 16 + math.min(10, level * 0.3)
end
function Professions.waiterTipMult(level)
	return 1 + math.min(1.0, level * 0.025)
end
function Professions.cookQualityBonus(level)
	return math.min(0.2, level * 0.005)
end
function Professions.cookStepTimeMult(level)
	-- мини-игры становятся немного легче (шире зона попадания)
	return 1 + math.min(0.6, level * 0.015)
end

return Professions
