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
	{ id = "table_wood_2", x = -8, z = 0, r = 0 },
	{ id = "table_wood_2", x = 0, z = 0, r = 0 },
	{ id = "table_wood_4", x = 8, z = 0, r = 0 },
	{ id = "plant_small", x = -12, z = 5, r = 0 },
}

return Furniture
