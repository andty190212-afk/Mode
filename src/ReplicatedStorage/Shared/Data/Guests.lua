-- Guest categories: budget multiplier, patience, tip rate, quality demand, unlock level.
local Guests = {}

Guests.Types = {
	{ id = "regular", name = "Посетитель", icon = "🙂", weight = 50, minStars = 1, party = { 1, 2 }, budget = 1.0, patience = 1.0,
		tip = 0.10, demand = 0.35, priceSense = 1.0, drinkChance = 0.55, rep = 1.0, colors = { "Bright blue", "Bright red", "Dark green" } },
	{ id = "student", name = "Студент", icon = "🎒", weight = 30, minStars = 1, party = { 1, 3 }, budget = 0.7, patience = 0.9,
		tip = 0.05, demand = 0.3, priceSense = 1.6, drinkChance = 0.7, rep = 0.8, colors = { "Bright yellow", "Bright orange" } },
	{ id = "family", name = "Семья", icon = "👨‍👩‍👧", weight = 22, minStars = 1, party = { 3, 4 }, budget = 1.0, patience = 1.1,
		tip = 0.10, demand = 0.4, priceSense = 1.2, drinkChance = 0.8, rep = 1.2, colors = { "Lime green", "Pastel blue" } },
	{ id = "tourist", name = "Турист", icon = "📸", weight = 25, minStars = 2, party = { 1, 3 }, budget = 1.25, patience = 1.15,
		tip = 0.12, demand = 0.45, priceSense = 0.9, drinkChance = 0.85, rep = 1.1, colors = { "Hot pink", "Cyan" } },
	{ id = "rich", name = "Состоятельный гость", icon = "💼", weight = 16, minStars = 3, party = { 1, 2 }, budget = 2.0, patience = 0.95,
		tip = 0.18, demand = 0.6, priceSense = 0.6, drinkChance = 0.7, rep = 1.4, colors = { "Really black", "Navy blue" } },
	{ id = "vip", name = "VIP-гость", icon = "👑", weight = 8, minStars = 4, party = { 1, 2 }, budget = 3.2, patience = 0.85,
		tip = 0.32, demand = 0.72, priceSense = 0.4, drinkChance = 0.9, rep = 2.5, vip = true, colors = { "Gold", "Royal purple" } },
	{ id = "critic", name = "Ресторанный критик", icon = "📝", weight = 0, minStars = 2, party = { 1, 1 }, budget = 1.6, patience = 0.9,
		tip = 0.08, demand = 0.75, priceSense = 0.8, drinkChance = 1.0, rep = 3.0, critic = true, colors = { "Black" } },
}

Guests.ById = {}
for _, g in ipairs(Guests.Types) do
	Guests.ById[g.id] = g
end

-- Базовое терпение (секунды) по стадиям
Guests.Patience = {
	order = 45, -- ждать, пока примут заказ
	food = 120, -- ждать еду после заказа
}

Guests.Names = {
	"Алекс", "Мария", "Иван", "Софья", "Макс", "Анна", "Лев", "Ева", "Тимур", "Ника", "Олег", "Лиза",
	"Даниил", "Вера", "Артём", "Полина", "Марк", "Алиса", "Кирилл", "Яна", "Сэм", "Мия", "Лука", "Зоя",
}

Guests.ReviewTexts = {
	good = {
		"Восхитительно! Обязательно вернусь.",
		"Лучшее блюдо на островах!",
		"Отличный сервис и быстрая подача.",
		"Уютная атмосфера, всё понравилось.",
		"Повар — настоящий волшебник!",
		"Красивый интерьер и вкусная еда.",
	},
	ok = {
		"Неплохо, но есть куда расти.",
		"Нормально поели, цены адекватные.",
		"Средне. Ждали немного долго.",
	},
	bad = {
		"Очень долго ждали заказ...",
		"Еда была холодной.",
		"Слишком дорого за такое качество.",
		"Грязные столы, не понравилось.",
		"Больше не приду.",
	},
}

return Guests
