-- Daily/weekly quests, achievements and daily login rewards.
local Quests = {}

-- stat = player event key counted by QuestService
Quests.DailyPool = {
	{ id = "d_serve", stat = "guestsServed", goal = 25, money = 400, xp = 120, text = "Обслужите %d гостей" },
	{ id = "d_cook", stat = "dishesCooked", goal = 15, money = 350, xp = 110, text = "Приготовьте %d блюд" },
	{ id = "d_drinks", stat = "drinksMade", goal = 10, money = 300, xp = 90, text = "Приготовьте %d напитков" },
	{ id = "d_earn", stat = "moneyEarned", goal = 1500, money = 500, xp = 140, text = "Заработайте $%d" },
	{ id = "d_tips", stat = "tipsEarned", goal = 200, money = 300, xp = 90, text = "Получите $%d чаевых" },
	{ id = "d_clean", stat = "tablesCleaned", goal = 12, money = 250, xp = 80, text = "Уберите %d столов" },
	{ id = "d_buy", stat = "ingredientsBought", goal = 100, money = 250, xp = 70, text = "Закупите %d продуктов" },
	{ id = "d_happy", stat = "happyGuests", goal = 15, money = 450, xp = 130, text = "Порадуйте %d гостей (отзыв 4★+)" },
	{ id = "d_orders", stat = "ordersTaken", goal = 15, money = 300, xp = 90, text = "Примите %d заказов" },
}

Quests.WeeklyPool = {
	{ id = "w_serve", stat = "guestsServed", goal = 300, money = 5000, xp = 1200, text = "Обслужите %d гостей за неделю" },
	{ id = "w_cook", stat = "dishesCooked", goal = 200, money = 4500, xp = 1100, text = "Приготовьте %d блюд за неделю" },
	{ id = "w_earn", stat = "moneyEarned", goal = 25000, money = 6000, xp = 1500, text = "Заработайте $%d за неделю" },
	{ id = "w_vip", stat = "vipServed", goal = 10, money = 7000, xp = 1600, text = "Обслужите %d VIP-гостей" },
	{ id = "w_decor", stat = "itemsPlaced", goal = 20, money = 3500, xp = 900, text = "Разместите %d предметов" },
	{ id = "w_drinks", stat = "drinksMade", goal = 150, money = 4000, xp = 1000, text = "Приготовьте %d напитков" },
}

Quests.DailyCount = 3
Quests.WeeklyCount = 3

-- Ежедневная награда за вход (серия до 7 дней)
Quests.DailyRewards = { 200, 350, 500, 750, 1000, 1500, 3000 }

Quests.Achievements = {
	{ id = "first_dish", name = "Первое блюдо", stat = "dishesCooked", goal = 1, money = 100, icon = "🍳" },
	{ id = "cook_100", name = "Кухонный боец", stat = "dishesCooked", goal = 100, money = 1500, icon = "🔪" },
	{ id = "cook_1000", name = "Мастер плиты", stat = "dishesCooked", goal = 1000, money = 15000, icon = "🏅" },
	{ id = "serve_100", name = "Гостеприимство", stat = "guestsServed", goal = 100, money = 1500, icon = "🤝" },
	{ id = "serve_1000", name = "Легенда сервиса", stat = "guestsServed", goal = 1000, money = 15000, icon = "🏆" },
	{ id = "drinks_100", name = "Бармен года", stat = "drinksMade", goal = 100, money = 1500, icon = "🍹" },
	{ id = "tips_5000", name = "Щедрые гости", stat = "tipsEarned", goal = 5000, money = 3000, icon = "💰" },
	{ id = "earn_100k", name = "Сотня тысяч", stat = "moneyEarned", goal = 100000, money = 10000, icon = "💵" },
	{ id = "earn_1m", name = "Миллионер", stat = "moneyEarned", goal = 1000000, money = 50000, icon = "💎" },
	{ id = "vip_10", name = "Для избранных", stat = "vipServed", goal = 10, money = 5000, icon = "👑" },
	{ id = "critic_1", name = "Признание критиков", stat = "criticsPassed", goal = 1, money = 5000, icon = "📝", recipe = "cloud_souffle" },
	{ id = "critic_5", name = "Звезда гастрономии", stat = "criticsPassed", goal = 5, money = 25000, icon = "🌟", recipe = "island_paella" },
	{ id = "star_2", name = "Уютное кафе", stat = "maxStars", goal = 2, money = 1000, icon = "⭐" },
	{ id = "star_3", name = "Настоящий ресторан", stat = "maxStars", goal = 3, money = 5000, icon = "⭐" },
	{ id = "star_4", name = "Премиум-класс", stat = "maxStars", goal = 4, money = 20000, icon = "⭐", recipe = "phoenix_curry" },
	{ id = "star_5", name = "Элита островов", stat = "maxStars", goal = 5, money = 75000, icon = "🌟" },
	{ id = "decorator", name = "Дизайнер острова", stat = "itemsPlaced", goal = 25, money = 2500, icon = "🌴" },
	{ id = "collector", name = "Коллекционер мебели", stat = "uniqueFurniture", goal = 12, money = 8000, icon = "🛋️" },
	{ id = "team_up", name = "Вместе веселее", stat = "teamJoins", goal = 1, money = 500, icon = "👥" },
	{ id = "pilot", name = "Пилот", stat = "helicoptersOwned", goal = 1, money = 3000, icon = "🚁" },
	{ id = "contest_win", name = "Лучший ресторан сервера", stat = "contestsWon", goal = 1, money = 5000, icon = "🥇" },
}

Quests.AchievementById = {}
for _, a in ipairs(Quests.Achievements) do
	Quests.AchievementById[a.id] = a
end
Quests.DailyById = {}
for _, q in ipairs(Quests.DailyPool) do
	Quests.DailyById[q.id] = q
end
for _, q in ipairs(Quests.WeeklyPool) do
	Quests.DailyById[q.id] = q
end

return Quests
