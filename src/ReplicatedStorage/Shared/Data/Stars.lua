-- Restaurant star rating levels and requirements for promotion.
-- A star is NOT bought: all requirements must be met, then a promotion fee is paid.
local Stars = {}

Stars.Levels = {
	[1] = { name = "Дешёвая забегаловка", maxGuestsSeats = 12, spawnMult = 0.75, guestBudget = 1.0, staffSlots = 2,
		desc = "Маленькое помещение, простая кухня, обычные посетители." },
	[2] = { name = "Небольшое кафе", maxGuestsSeats = 18, spawnMult = 0.95, guestBudget = 1.6, staffSlots = 3,
		desc = "Красивее интерьер, новые столы и блюда, гости богаче." },
	[3] = { name = "Хороший ресторан", maxGuestsSeats = 26, spawnMult = 1.3, guestBudget = 2.6, staffSlots = 4,
		desc = "Просторный зал, профессиональная кухня, вертолёты." },
	[4] = { name = "Премиальный ресторан", maxGuestsSeats = 34, spawnMult = 1.45, guestBudget = 4.5, staffSlots = 5,
		desc = "Богатый интерьер, VIP-гости и большие чаевые." },
	[5] = { name = "Элитный ресторан", maxGuestsSeats = 44, spawnMult = 1.6, guestBudget = 8, staffSlots = 6,
		desc = "Роскошь, редкие рецепты, критики и огромная прибыль." },
}

-- Требования для перехода НА уровень (ключ = новая звезда)
Stars.Requirements = {
	[2] = { served = 40, reputation = 55, satisfaction = 0.60, menu = 5, interior = 25, equipment = 7, cleanliness = 60, staffLevel = 2, critics = 0, fee = 1000 },
	[3] = { served = 160, reputation = 63, satisfaction = 0.66, menu = 9, interior = 90, equipment = 12, cleanliness = 70, staffLevel = 5, critics = 0, fee = 10000 },
	[4] = { served = 420, reputation = 71, satisfaction = 0.72, menu = 13, interior = 260, equipment = 20, cleanliness = 78, staffLevel = 10, critics = 1, fee = 50000 },
	[5] = { served = 1000, reputation = 80, satisfaction = 0.79, menu = 17, interior = 650, equipment = 28, cleanliness = 85, staffLevel = 16, critics = 3, fee = 200000 },
}

Stars.RequirementLabels = {
	served = "Обслужено гостей",
	reputation = "Репутация",
	satisfaction = "Средняя удовлетворённость",
	menu = "Блюд и напитков в меню",
	interior = "Красота интерьера и острова",
	equipment = "Уровни оборудования (сумма)",
	cleanliness = "Чистота",
	staffLevel = "Опыт команды (уровни профессий/персонала)",
	critics = "Пройдено проверок критиков",
	fee = "Взнос за повышение",
}

Stars.Order = { "served", "reputation", "satisfaction", "menu", "interior", "equipment", "cleanliness", "staffLevel", "critics", "fee" }

-- metrics = {served, reputation, satisfaction, menu, interior, equipment, cleanliness, staffLevel, critics, budget}
function Stars.check(nextStar, metrics)
	local req = Stars.Requirements[nextStar]
	if not req then
		return false, {}
	end
	local rows, all = {}, true
	for _, key in ipairs(Stars.Order) do
		local need = req[key]
		local have = key == "fee" and metrics.budget or metrics[key] or 0
		local ok = have >= need
		if not ok then
			all = false
		end
		table.insert(rows, { key = key, label = Stars.RequirementLabels[key], need = need, have = have, ok = ok })
	end
	return all, rows
end

return Stars
