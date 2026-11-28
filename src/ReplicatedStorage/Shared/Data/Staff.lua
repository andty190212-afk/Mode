-- NPC staff (hired by the Director; the NPC cook is also provided by the Chef pass)
local Staff = {}

Staff.Roles = {
	Cook = { name = "NPC-повар", icon = "👨‍🍳", hireCost = 600 },
	Waiter = { name = "NPC-официант", icon = "🧑‍💼", hireCost = 500 },
	Bartender = { name = "NPC-бармен", icon = "🍹", hireCost = 550 },
}

Staff.Levels = {
	[1] = { name = "Новичок", speed = 1.00, errorChance = 0.14, quality = 0.62, wage = 6, trainCost = 0, xpNeed = 0 },
	[2] = { name = "Работник", speed = 1.20, errorChance = 0.09, quality = 0.71, wage = 10, trainCost = 1800, xpNeed = 40 },
	[3] = { name = "Опытный", speed = 1.40, errorChance = 0.05, quality = 0.80, wage = 16, trainCost = 6500, xpNeed = 140 },
	[4] = { name = "Профессионал", speed = 1.65, errorChance = 0.03, quality = 0.89, wage = 25, trainCost = 18000, xpNeed = 380 },
	[5] = { name = "Мастер", speed = 2.00, errorChance = 0.01, quality = 0.97, wage = 38, trainCost = 45000, xpNeed = 900 },
}
Staff.MaxLevel = 5

-- Базовые времена работы NPC (секунды), делятся на speed
Staff.BaseCookTime = 18
Staff.BaseDrinkTime = 11
Staff.BaseServeTime = 3
Staff.BaseCleanTime = 4

-- Зарплата за минуту = базовая * множитель зарплаты (0.8 .. 1.5), влияет на мотивацию
Staff.WageMultMin = 0.8
Staff.WageMultMax = 1.5

function Staff.wagePerMinute(member)
	local lvl = Staff.Levels[member.level] or Staff.Levels[1]
	return lvl.wage * (member.wageMult or 1)
end

-- Мотивация: от зарплаты и своевременных выплат
function Staff.effectiveSpeed(member)
	local lvl = Staff.Levels[member.level] or Staff.Levels[1]
	local morale = member.morale or 1
	return lvl.speed * (0.75 + 0.25 * morale) * (0.9 + 0.2 * ((member.wageMult or 1) - 0.8) / 0.7)
end

Staff.Names = {
	"Пьер", "Лючия", "Хироши", "Аня", "Карлос", "Грета", "Ахмед", "Мила", "Бруно", "Сара", "Ким", "Оскар", "Юки", "Рита", "Марко",
}

return Staff
