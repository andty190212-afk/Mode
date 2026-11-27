-- Restaurant interior furniture (placed in build mode inside the dining area).
-- size = footprint {x, z} in studs (before rotation), beauty = interior score,
-- seats = guest seat offsets {x, z, yawDeg} relative to item centre (tables only).
-- NOTE: no `script` references - this module is also read by the place builder.
local Furniture = {}

Furniture.Categories = {
	{ id = "tables", name = "Столы", icon = "🍽️" },
	{ id = "sofas", name = "Диваны", icon = "🛋️" },
	{ id = "decor", name = "Декор", icon = "🖼️" },
	{ id = "light", name = "Освещение", icon = "💡" },
	{ id = "plants", name = "Растения", icon = "🪴" },
	{ id = "bar", name = "Барные", icon = "🍸" },
}

local S2 = { { 0, -2.6, 0 }, { 0, 2.6, 180 } }
local S4 = { { 0, -3.1, 0 }, { 0, 3.1, 180 }, { -3.1, 0, 90 }, { 3.1, 0, -90 } }

Furniture.List = {
	{ id = "table_wood_2", name = "Деревянный столик на 2", cat = "tables", price = 150, beauty = 2, stars = 1, size = { 5, 7 }, seats = S2, style = "wood" },
	{ id = "table_wood_4", name = "Деревянный стол на 4", cat = "tables", price = 320, beauty = 4, stars = 1, size = { 8, 8 }, seats = S4, style = "wood" },
	{ id = "table_bistro_2", name = "Столик бистро", cat = "tables", price = 650, beauty = 7, stars = 2, size = { 5, 7 }, seats = S2, style = "bistro" },
	{ id = "table_family_4", name = "Семейный стол", cat = "tables", price = 950, beauty = 9, stars = 2, size = { 8, 8 }, seats = S4, style = "family" },
	{ id = "booth_4", name = "Кабинка с диванами", cat = "sofas", price = 2600, beauty = 18, stars = 3, size = { 7, 10 },
		seats = { { -1.6, -3.4, 0 }, { 1.6, -3.4, 0 }, { -1.6, 3.4, 180 }, { 1.6, 3.4, 180 } }, style = "booth" },
	{ id = "table_marble_4", name = "Мраморный стол", cat = "tables", price = 6500, beauty = 32, stars = 4, size = { 8, 8 }, seats = S4, style = "marble" },
	{ id = "table_royal_6", name = "Королевский стол на 6", cat = "tables", price = 22000, beauty = 75, stars = 5, size = { 8, 13 },
		seats = { { -3.1, -3.5, 90 }, { -3.1, 0, 90 }, { -3.1, 3.5, 90 }, { 3.1, -3.5, -90 }, { 3.1, 0, -90 }, { 3.1, 3.5, -90 } }, style = "royal" },

	{ id = "sofa_lounge", name = "Лаунж-диван", cat = "sofas", price = 1800, beauty = 14, stars = 3, size = { 8, 4 }, style = "sofa" },
	{ id = "sofa_velvet", name = "Бархатный диван", cat = "sofas", price = 9000, beauty = 40, stars = 4, size = { 9, 4 }, style = "velvet" },

	{ id = "plant_small", name = "Комнатное растение", cat = "plants", price = 80, beauty = 2, stars = 1, size = { 2, 2 }, style = "plant" },
	{ id = "plant_palm", name = "Пальма в кадке", cat = "plants", price = 420, beauty = 5, stars = 2, size = { 3, 3 }, style = "palm" },
	{ id = "flower_vase", name = "Ваза с цветами", cat = "plants", price = 950, beauty = 9, stars = 3, size = { 2, 2 }, style = "vase" },

	{ id = "lamp_floor", name = "Торшер", cat = "light", price = 260, beauty = 3, stars = 1, size = { 2, 2 }, style = "lamp" },
	{ id = "neon_sign", name = "Неоновая вывеска", cat = "light", price = 1500, beauty = 12, stars = 3, size = { 6, 1 }, style = "neon" },
	{ id = "chandelier", name = "Хрустальная люстра", cat = "light", price = 8500, beauty = 46, stars = 4, size = { 4, 4 }, style = "chandelier" },

	{ id = "rug_red", name = "Красный ковёр", cat = "decor", price = 520, beauty = 6, stars = 2, size = { 8, 6 }, style = "rug", flat = true },
	{ id = "painting", name = "Картина на мольберте", cat = "decor", price = 1200, beauty = 10, stars = 2, size = { 3, 2 }, style = "painting" },
	{ id = "aquarium", name = "Аквариум", cat = "decor", price = 12500, beauty = 60, stars = 4, size = { 8, 3 }, style = "aquarium" },
	{ id = "fountain_indoor", name = "Комнатный фонтан", cat = "decor", price = 15500, beauty = 70, stars = 4, size = { 6, 6 }, style = "fountain" },
	{ id = "piano", name = "Рояль", cat = "decor", price = 18500, beauty = 82, stars = 5, size = { 7, 8 }, style = "piano" },
	{ id = "statue_gold", name = "Золотая статуя", cat = "decor", price = 36000, beauty = 125, stars = 5, size = { 4, 4 }, style = "statue" },

	-- ===== новые предметы =====
	{ id = "table_round_4", name = "Круглый стол на 4", cat = "tables", price = 480, beauty = 5, stars = 1, size = { 8, 8 }, seats = S4, style = "round" },
	{ id = "table_high_2", name = "Высокий столик", cat = "tables", price = 380, beauty = 4, stars = 1, size = { 5, 7 }, seats = S2, style = "high" },
	{ id = "table_garden_4", name = "Стол-веранда с зонтом", cat = "tables", price = 1600, beauty = 14, stars = 3, size = { 8, 8 }, seats = S4, style = "garden" },
	{ id = "armchair", name = "Кресло", cat = "sofas", price = 700, beauty = 6, stars = 2, size = { 4, 4 }, style = "armchair" },
	{ id = "plant_tall", name = "Фикус", cat = "plants", price = 220, beauty = 3, stars = 1, size = { 3, 3 }, style = "ficus" },
	{ id = "bamboo", name = "Бамбук в горшке", cat = "plants", price = 600, beauty = 6, stars = 2, size = { 3, 3 }, style = "bamboo" },
	{ id = "flower_wall", name = "Цветочная стена", cat = "plants", price = 4200, beauty = 26, stars = 4, size = { 8, 1 }, style = "flowerwall" },
	{ id = "candles", name = "Подсвечник", cat = "light", price = 640, beauty = 6, stars = 2, size = { 2, 2 }, style = "candles" },
	{ id = "lamp_paper", name = "Бумажный фонарь", cat = "light", price = 350, beauty = 4, stars = 1, size = { 2, 2 }, style = "paperlamp" },
	{ id = "arcade", name = "Игровой автомат", cat = "decor", price = 900, beauty = 7, stars = 1, size = { 3, 3 }, style = "arcade" },
	{ id = "jukebox", name = "Музыкальный автомат", cat = "decor", price = 1300, beauty = 10, stars = 2, size = { 3, 2 }, style = "jukebox" },
	{ id = "bookshelf", name = "Книжный шкаф", cat = "decor", price = 800, beauty = 7, stars = 2, size = { 6, 2 }, style = "bookshelf" },
	{ id = "tv_screen", name = "Телевизор на стойке", cat = "decor", price = 1100, beauty = 8, stars = 2, size = { 6, 2 }, style = "tv" },
	{ id = "dessert_case", name = "Витрина с десертами", cat = "decor", price = 2400, beauty = 16, stars = 3, size = { 6, 3 }, style = "dessertcase" },
	{ id = "fireplace", name = "Камин", cat = "decor", price = 5200, beauty = 30, stars = 3, size = { 7, 3 }, style = "fireplace" },
	{ id = "grand_clock", name = "Напольные часы", cat = "decor", price = 3600, beauty = 22, stars = 3, size = { 2, 2 }, style = "clock" },
	{ id = "trophy_case", name = "Витрина с наградами", cat = "decor", price = 9000, beauty = 45, stars = 4, size = { 6, 2 }, style = "trophies" },
	{ id = "dj_booth", name = "DJ-пульт", cat = "decor", price = 24000, beauty = 85, stars = 5, size = { 7, 4 }, style = "dj" },
	{ id = "bar_stools", name = "Барные стулья", cat = "bar", price = 400, beauty = 3, stars = 1, size = { 6, 2 }, style = "stools" },
	{ id = "drinks_shelf", name = "Витрина напитков", cat = "bar", price = 2200, beauty = 15, stars = 3, size = { 6, 2 }, style = "shelf" },
}

Furniture.ById = {}
for i, f in ipairs(Furniture.List) do
	f.order = i
	f.seatCount = f.seats and #f.seats or 0
	Furniture.ById[f.id] = f
end

-- Мебель, выдаваемая новому ресторану (локальные координаты зала)
Furniture.StartLayout = {
	-- z = -1 -> в сохранении -11 (ряд столов в глубине зала, вход свободен)
	{ id = "table_wood_2", x = -13, z = -1, r = 0 },
	{ id = "table_wood_2", x = -7, z = -1, r = 0 },
	{ id = "table_wood_2", x = -1, z = -1, r = 0 },
	{ id = "table_wood_4", x = 6, z = -1, r = 0 },
	{ id = "table_wood_2", x = 13, z = -1, r = 0 },
	{ id = "plant_small", x = -13, z = 5, r = 0 },
}

return Furniture
