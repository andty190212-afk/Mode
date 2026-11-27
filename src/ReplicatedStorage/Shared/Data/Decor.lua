-- Island (outdoor) decorations placed in build mode on the owner's island.
-- NOTE: no `script` references - also read by the place builder.
local Decor = {}

Decor.Categories = {
	{ id = "nature", name = "Природа", icon = "🌴" },
	{ id = "paths", name = "Дорожки", icon = "🧱" },
	{ id = "light", name = "Освещение", icon = "🏮" },
	{ id = "leisure", name = "Отдых", icon = "⛱️" },
	{ id = "structures", name = "Сооружения", icon = "🏛️" },
	{ id = "transport", name = "Транспорт", icon = "🚁" },
}

Decor.List = {
	{ id = "palm_tree", name = "Пальма", cat = "nature", price = 200, beauty = 3, stars = 1, size = { 4, 4 } },
	{ id = "oak_tree", name = "Лиственное дерево", cat = "nature", price = 240, beauty = 3, stars = 1, size = { 6, 6 } },
	{ id = "bush", name = "Куст", cat = "nature", price = 60, beauty = 1, stars = 1, size = { 3, 3 } },
	{ id = "flower_bed", name = "Клумба", cat = "nature", price = 120, beauty = 2, stars = 1, size = { 5, 3 } },
	{ id = "rocks", name = "Камни", cat = "nature", price = 90, beauty = 1, stars = 1, size = { 4, 4 } },
	{ id = "garden", name = "Сад с живой изгородью", cat = "nature", price = 2200, beauty = 18, stars = 2, size = { 12, 12 } },

	{ id = "path_stone", name = "Каменная плитка", cat = "paths", price = 30, beauty = 0.5, stars = 1, size = { 4, 4 }, flat = true },
	{ id = "path_wood", name = "Деревянный настил", cat = "paths", price = 45, beauty = 0.7, stars = 1, size = { 4, 4 }, flat = true },
	{ id = "path_marble", name = "Мраморная дорожка", cat = "paths", price = 160, beauty = 2, stars = 3, size = { 4, 4 }, flat = true },
	{ id = "bridge", name = "Декоративный мостик", cat = "paths", price = 1800, beauty = 12, stars = 2, size = { 6, 14 } },

	{ id = "lamp_post", name = "Фонарь", cat = "light", price = 300, beauty = 3, stars = 1, size = { 2, 2 } },
	{ id = "torch", name = "Тики-факел", cat = "light", price = 150, beauty = 2, stars = 1, size = { 1, 1 } },
	{ id = "string_lights", name = "Гирлянда", cat = "light", price = 900, beauty = 8, stars = 2, size = { 12, 2 } },

	{ id = "bench", name = "Скамейка", cat = "leisure", price = 200, beauty = 2, stars = 1, size = { 6, 2 } },
	{ id = "beach_umbrella", name = "Пляжный зонт", cat = "leisure", price = 250, beauty = 3, stars = 1, size = { 5, 5 } },
	{ id = "sun_lounger", name = "Шезлонг", cat = "leisure", price = 220, beauty = 2, stars = 1, size = { 3, 7 } },
	{ id = "pool", name = "Бассейн (можно плавать)", cat = "leisure", price = 12500, beauty = 60, stars = 3, size = { 18, 19 } },
	{ id = "terrace", name = "Терраса", cat = "leisure", price = 5200, beauty = 30, stars = 3, size = { 16, 12 } },
	{ id = "vip_lounge", name = "VIP-зона", cat = "leisure", price = 26000, beauty = 105, stars = 4, size = { 18, 14 } },

	{ id = "fountain", name = "Фонтан", cat = "structures", price = 3200, beauty = 25, stars = 2, size = { 10, 10 } },
	{ id = "gazebo", name = "Беседка", cat = "structures", price = 8200, beauty = 40, stars = 3, size = { 12, 12 } },
	{ id = "statue", name = "Статуя", cat = "structures", price = 15000, beauty = 55, stars = 4, size = { 6, 6 } },
	{ id = "lighthouse", name = "Маяк", cat = "structures", price = 45000, beauty = 140, stars = 5, size = { 10, 10 } },

	-- ===== новые украшения =====
	{ id = "flamingo", name = "Фламинго", cat = "nature", price = 150, beauty = 2, stars = 1, size = { 2, 2 } },
	{ id = "cactus", name = "Кактусы", cat = "nature", price = 180, beauty = 2, stars = 1, size = { 3, 3 } },
	{ id = "palm_cluster", name = "Группа пальм", cat = "nature", price = 700, beauty = 8, stars = 2, size = { 10, 10 } },
	{ id = "rose_garden", name = "Розовый сад", cat = "nature", price = 1500, beauty = 14, stars = 2, size = { 10, 6 } },
	{ id = "koi_pond", name = "Пруд с рыбками", cat = "nature", price = 4800, beauty = 32, stars = 3, size = { 12, 10 } },
	{ id = "campfire", name = "Костёр", cat = "leisure", price = 300, beauty = 3, stars = 1, size = { 6, 6 } },
	{ id = "picnic_table", name = "Стол для пикника", cat = "leisure", price = 350, beauty = 3, stars = 1, size = { 6, 6 } },
	{ id = "hammock", name = "Гамак", cat = "leisure", price = 500, beauty = 4, stars = 1, size = { 10, 3 } },
	{ id = "swings", name = "Качели", cat = "leisure", price = 650, beauty = 5, stars = 1, size = { 8, 4 } },
	{ id = "surf_rack", name = "Стойка с досками для серфинга", cat = "leisure", price = 450, beauty = 4, stars = 1, size = { 6, 2 } },
	{ id = "volleyball", name = "Пляжный волейбол", cat = "leisure", price = 1400, beauty = 10, stars = 2, size = { 18, 10 } },
	{ id = "tiki_bar", name = "Тики-бар", cat = "leisure", price = 3800, beauty = 24, stars = 2, size = { 10, 8 } },
	{ id = "hot_tub", name = "Джакузи", cat = "leisure", price = 9500, beauty = 45, stars = 4, size = { 8, 8 } },
	{ id = "flower_arch", name = "Цветочная арка", cat = "structures", price = 1200, beauty = 10, stars = 2, size = { 8, 3 } },
	{ id = "windmill", name = "Ветряная мельница", cat = "structures", price = 7000, beauty = 36, stars = 3, size = { 10, 10 } },
	{ id = "watch_tower", name = "Смотровая башня", cat = "structures", price = 16000, beauty = 60, stars = 4, size = { 10, 10 } },
	{ id = "ferris_wheel", name = "Колесо обозрения", cat = "structures", price = 60000, beauty = 180, stars = 5, size = { 20, 8 } },
	{ id = "parking", name = "Парковка", cat = "transport", price = 2600, beauty = 10, stars = 2, size = { 16, 12 }, flat = true },
	{ id = "helipad", name = "Вертолётная площадка", cat = "transport", price = 5000, beauty = 12, stars = 3, size = { 20, 20 }, flat = true, unique = true },
}

Decor.ById = {}
for i, d in ipairs(Decor.List) do
	d.order = i
	Decor.ById[d.id] = d
end

return Decor
