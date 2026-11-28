-- Random restaurant events and server-wide events/contests
local Events = {}

Events.Random = {
	{ id = "rush", name = "Час пик!", icon = "🏃", weight = 30, duration = 120, desc = "Гостей в 2 раза больше на 2 минуты." },
	{ id = "sale", name = "Распродажа у поставщика", icon = "🏷️", weight = 22, duration = 180, desc = "Продукты на 30% дешевле 3 минуты." },
	{ id = "critic", name = "Приезжает критик", icon = "📝", weight = 12, duration = 0, minStars = 2, desc = "Ресторанный критик уже в пути. Не подведите!" },
	{ id = "vip", name = "VIP-визит", icon = "👑", weight = 14, duration = 0, minStars = 3, desc = "К вам направляется важный гость." },
	{ id = "inspection", name = "Санитарная проверка", icon = "🧽", weight = 12, duration = 0, desc = "Проверка чистоты: награда или штраф." },
	{ id = "special", name = "Особый заказ", icon = "⭐", weight = 18, duration = 240, desc = "Гость хочет особое блюдо за двойную цену." },
	{ id = "secret", name = "Секретный рецепт", icon = "📜", weight = 4, duration = 0, minStars = 3, desc = "Старый моряк поделился редким рецептом!" },
}

Events.Interval = { 240, 420 } -- секунд между случайными событиями ресторана

Events.Server = {
	festival = { name = "Фестиваль островов", icon = "🎉", desc = "+25% гостей во всех ресторанах", duration = 300 },
}
Events.ServerFestivalInterval = 1500

-- Соревнование ресторанов сервера
Events.ContestDuration = 900 -- 15 минут
Events.ContestRewards = { 5000, 2500, 1000 } -- в бюджет ресторана за 1/2/3 место

return Events
