-- Prints markdown tables of creatures, weapons and chest odds (for docs)
local Creatures = require("../src/ReplicatedStorage/Shared/Data/Creatures")
local Weapons = require("../src/ReplicatedStorage/Shared/Data/Weapons")
local Chests = require("../src/ReplicatedStorage/Shared/Data/Chests")
local R = { Common = "Обычное", Uncommon = "Необычное", Rare = "Редкое", Epic = "Эпическое", Legendary = "Легендарное", Mythical = "Мифическое", Secret = "Секретное" }
local order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Secret" }
print("### Существа (" .. #Creatures.List .. ")\n")
print("| Существо | Редкость | Доход ур.1 | Рост | Способность ур.1 | 2-я способность (ур.5) | Особое блюдо |")
print("|---|---|---|---|---|---|---|")
for _, c in ipairs(Creatures.List) do
	local st = Creatures.stats(c)
	print(string.format("| %s | %s | %d/мин | %d с | %s | %s | %s %s |", c.name, R[c.rarity], Creatures.income(c, 1), st.grow, Creatures.describeAbility(c.ability, 1), Creatures.describeAbility(c.ability2, 5), c.dish.icon, c.dish.name))
end
print("\n### Оружие (" .. #Weapons.List .. ")\n")
print("| Оружие | Редкость | Стиль | Урон | Атака, с | Дальность | Способность (перезарядка) |")
print("|---|---|---|---|---|---|---|")
for _, w in ipairs(Weapons.List) do
	print(string.format("| %s %s | %s | %s | %d | %.2f | %d | **%s** (%d с): %s |", w.icon, w.name, w.starter and "Бесплатное" or R[w.rarity], Weapons.Styles[w.style], w.damage, w.cooldown, w.range, w.ability.name, w.ability.cooldown, w.ability.desc))
end
print("\n### Шансы сундуков (без бонусов удачи)\n")
local head = "| Сундук | Цена | Нужно ★ |"
local sep = "|---|---|---|"
for _, r in ipairs(order) do
	head ..= " " .. R[r] .. " |"
	sep ..= "---|"
end
print(head)
print(sep)
for _, c in ipairs(Chests.List) do
	local row = string.format("| %s %s | %d | %d |", c.icon, c.name, c.price, c.stars)
	for _, r in ipairs(order) do
		row ..= " " .. tostring(c.odds[r] or 0) .. "% |"
	end
	print(row)
end
