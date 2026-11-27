-- Fantasy creatures grown in island laboratories.
-- Every creature has its own model (tools/build/creatures.luau, Assets.Creatures[id]),
-- rarity, passive abilities, income and a linked special dish.
-- Eating the dish ALWAYS gives one random weapon of the creature's rarity.
local Creatures = {}

-- per-rarity tuning
Creatures.RarityStats = {
	Common = { grow = 90, income = 30, dishTime = 240, upgradeBase = 600, speedupRate = 6, stealHold = 2.5 },
	Uncommon = { grow = 180, income = 55, dishTime = 300, upgradeBase = 1200, speedupRate = 8, stealHold = 3 },
	Rare = { grow = 360, income = 100, dishTime = 420, upgradeBase = 2500, speedupRate = 10, stealHold = 3.5 },
	Epic = { grow = 600, income = 180, dishTime = 600, upgradeBase = 5000, speedupRate = 14, stealHold = 4.5 },
	Legendary = { grow = 900, income = 320, dishTime = 900, upgradeBase = 10000, speedupRate = 20, stealHold = 5.5 },
	Mythical = { grow = 1200, income = 550, dishTime = 1200, upgradeBase = 20000, speedupRate = 30, stealHold = 6.5 },
	Secret = { grow = 1500, income = 900, dishTime = 1500, upgradeBase = 40000, speedupRate = 45, stealHold = 8 },
}

Creatures.MaxLevel = 10
Creatures.SecondAbilityLevel = 5
Creatures.Stages = {
	{ name = "Яйцо", from = 0, scale = 0.45 },
	{ name = "Малыш", from = 0.25, scale = 0.6 },
	{ name = "Подросток", from = 0.6, scale = 0.8 },
	{ name = "Взрослый", from = 1, scale = 1 },
}

-- Passive ability kinds. value = bonus at level 1; grows +10% per level.
Creatures.Abilities = {
	profit = { name = "Выгодная кухня", fmt = "+%s%% к выручке ресторана", unit = "%" },
	tips = { name = "Обаяние", fmt = "+%s%% к чаевым", unit = "%" },
	cook = { name = "Помощник повара", fmt = "Готовка быстрее на %s%%", unit = "%" },
	service = { name = "Быстрое обслуживание", fmt = "Гости едят быстрее на %s%%", unit = "%" },
	guests = { name = "Приманка", fmt = "+%s%% гостей", unit = "%" },
	ingredients = { name = "Добытчик", fmt = "+%s ингредиентов в минуту на склад", unit = "" },
	synergy = { name = "Резонанс", fmt = "+%s%% к доходу других существ", unit = "%" },
	growth = { name = "Питательная аура", fmt = "Другие существа растут быстрее на %s%%", unit = "%" },
	dishes = { name = "Гурман", fmt = "Особые блюда появляются быстрее на %s%%", unit = "%" },
	xp = { name = "Мудрость", fmt = "+%s%% опыта игрока", unit = "%" },
	reputation = { name = "Знаменитость", fmt = "+%s репутации ресторана в минуту", unit = "" },
	luck = { name = "Удача", fmt = "+%s%% к шансу редких существ в сундуках", unit = "%" },
	guard = { name = "Сторож", fmt = "Красть дольше на %s%%", unit = "%" },
	alarm = { name = "Сирена", fmt = "Вор с добычей медленнее на %s%%", unit = "%" },
}

-- caps for the sum of all creature bonuses of one lab (the restaurant stays the core of the game)
Creatures.Caps = {
	profit = 30, tips = 40, cook = 30, service = 25, guests = 25, ingredients = 12, synergy = 40,
	growth = 50, dishes = 50, xp = 40, reputation = 3, luck = 40, guard = 60, alarm = 10,
}

Creatures.List = {
	-- ===== COMMON =====
	{ id = "glowslug", name = "Светослизень", rarity = "Common", anim = "crawl", sound = 0.8,
		desc = "Мягкий слизень, светящийся в темноте. Оставляет сладкий след.",
		ability = { kind = "profit", value = 3 }, ability2 = { kind = "dishes", value = 6 },
		dish = { id = "glow_jelly", name = "Светящееся желе", icon = "🟢" } },
	{ id = "crumbcrab", name = "Крошкокраб", rarity = "Common", anim = "hop", sound = 1.2,
		desc = "Краб с панцирем из хрустящей булки. Обожает хлебные крошки.",
		ability = { kind = "tips", value = 4 }, ability2 = { kind = "ingredients", value = 1 },
		dish = { id = "crumb_toast", name = "Тост Крошкокраба", icon = "🍞" } },
	{ id = "puffshroom", name = "Пыхогриб", rarity = "Common", anim = "wobble", sound = 1.0,
		desc = "Ходячий гриб, который пыхает облачками ароматных спор.",
		ability = { kind = "growth", value = 5 }, ability2 = { kind = "xp", value = 4 },
		dish = { id = "spore_soup", name = "Споровый суп", icon = "🍄" } },
	{ id = "pebblemole", name = "Камнекрот", rarity = "Common", anim = "hop", sound = 0.7,
		desc = "Крот с кристаллом на спине. Выкапывает продукты из-под земли.",
		ability = { kind = "ingredients", value = 1 }, ability2 = { kind = "guard", value = 8 },
		dish = { id = "crystal_fries", name = "Кристальная картошка", icon = "🥔" } },

	-- ===== UNCOMMON =====
	{ id = "jellybell", name = "Медузвон", rarity = "Uncommon", anim = "float", sound = 1.4,
		desc = "Медуза-колокольчик. Её звон ускоряет официантов.",
		ability = { kind = "service", value = 5 }, ability2 = { kind = "tips", value = 5 },
		dish = { id = "bell_pudding", name = "Пудинг-колокольчик", icon = "🍮" } },
	{ id = "pepperimp", name = "Перчёный бесёнок", rarity = "Uncommon", anim = "hop", sound = 1.3,
		desc = "Озорной бесёнок с рожками-перчиками. Подогревает плиты.",
		ability = { kind = "cook", value = 5 }, ability2 = { kind = "profit", value = 4 },
		dish = { id = "imp_chili", name = "Адский чили", icon = "🌶️" } },
	{ id = "cloudpup", name = "Облачный щенок", rarity = "Uncommon", anim = "float", sound = 1.6,
		desc = "Пушистый щенок из облака. Гости не могут пройти мимо.",
		ability = { kind = "guests", value = 4 }, ability2 = { kind = "reputation", value = 0.3 },
		dish = { id = "cloud_cake", name = "Облачный бисквит", icon = "☁️" } },
	{ id = "clockbeetle", name = "Часовой жук", rarity = "Uncommon", anim = "crawl", sound = 0.9,
		desc = "Заводной жук с шестерёнками. Всё вокруг него тикает быстрее.",
		ability = { kind = "dishes", value = 8 }, ability2 = { kind = "growth", value = 6 },
		dish = { id = "gear_cookies", name = "Печенье-шестерёнки", icon = "⚙️" } },

	-- ===== RARE =====
	{ id = "lanternfox", name = "Фонарный лис", rarity = "Rare", anim = "hop", sound = 1.1,
		desc = "Лис с фонариком на хвосте. Приводит щедрых гостей.",
		ability = { kind = "tips", value = 8 }, ability2 = { kind = "luck", value = 4 },
		dish = { id = "lantern_ramen", name = "Рамен фонарного лиса", icon = "🍜" } },
	{ id = "coralgolem", name = "Коралловый голем", rarity = "Rare", anim = "wobble", sound = 0.6,
		desc = "Тяжёлый страж из живых кораллов. Мешает ворам.",
		ability = { kind = "guard", value = 12 }, ability2 = { kind = "ingredients", value = 2 },
		dish = { id = "coral_sushi", name = "Коралловые суши", icon = "🍣" } },
	{ id = "mushowl", name = "Грибосова", rarity = "Rare", anim = "flap", sound = 1.0,
		desc = "Мудрая сова со шляпкой гриба. Учит всех вокруг.",
		ability = { kind = "xp", value = 10 }, ability2 = { kind = "synergy", value = 6 },
		dish = { id = "owl_pie", name = "Пирог мудрости", icon = "🥧" } },
	{ id = "bubbledrake", name = "Пузырчатый дракончик", rarity = "Rare", anim = "float", sound = 1.5,
		desc = "Маленький дракон, выдыхающий мыльные пузыри.",
		ability = { kind = "service", value = 8 }, ability2 = { kind = "cook", value = 6 },
		dish = { id = "bubble_tea", name = "Драконий бабл-ти", icon = "🧋" } },

	-- ===== EPIC =====
	{ id = "magmatoad", name = "Магможаба", rarity = "Epic", anim = "hop", sound = 0.5,
		desc = "Жаба с лавой внутри. На её спине можно жарить стейки.",
		ability = { kind = "cook", value = 9 }, ability2 = { kind = "alarm", value = 10 },
		dish = { id = "lava_steak", name = "Лавовый стейк", icon = "🥩" } },
	{ id = "prismstag", name = "Призменный олень", rarity = "Epic", anim = "wobble", sound = 1.2,
		desc = "Олень с рогами из радужного стекла. Приносит удачу.",
		ability = { kind = "luck", value = 6 }, ability2 = { kind = "profit", value = 6 },
		dish = { id = "prism_parfait", name = "Радужное парфе", icon = "🌈" } },
	{ id = "nebulamoth", name = "Туманная моль", rarity = "Epic", anim = "flap", sound = 1.7,
		desc = "Мотылёк с крыльями-галактиками. Усиливает соседей.",
		ability = { kind = "synergy", value = 8 }, ability2 = { kind = "dishes", value = 10 },
		dish = { id = "nebula_macaron", name = "Галактические макаруны", icon = "🌌" } },
	{ id = "thunderhog", name = "Громоёж", rarity = "Epic", anim = "spin", sound = 0.9,
		desc = "Ёж с иголками-молниями. Бьёт током любого вора.",
		ability = { kind = "alarm", value = 15 }, ability2 = { kind = "guests", value = 6 },
		dish = { id = "thunder_pops", name = "Громовой попкорн", icon = "⚡" } },

	-- ===== LEGENDARY =====
	{ id = "sunphoenix", name = "Солнечный феникс", rarity = "Legendary", anim = "flap", sound = 1.3,
		desc = "Птица из солнечного пламени. Ресторан сияет от её света.",
		ability = { kind = "profit", value = 10 }, ability2 = { kind = "reputation", value = 0.6 },
		dish = { id = "phoenix_wings", name = "Крылышки феникса", icon = "🔥" } },
	{ id = "tidekraken", name = "Кракен прилива", rarity = "Legendary", anim = "float", sound = 0.6,
		desc = "Карликовый кракен. Щупальцами таскает продукты из океана.",
		ability = { kind = "ingredients", value = 3 }, ability2 = { kind = "tips", value = 10 },
		dish = { id = "kraken_paella", name = "Паэлья кракена", icon = "🦑" } },
	{ id = "crystalwyrm", name = "Кристальный змей", rarity = "Legendary", anim = "crawl", sound = 0.8,
		desc = "Змей из живого кристалла. Его сияние ускоряет рост.",
		ability = { kind = "growth", value = 15 }, ability2 = { kind = "luck", value = 6 },
		dish = { id = "wyrm_candy", name = "Кристальный леденец", icon = "💎" } },
	{ id = "luckycat", name = "Кот удачи Манэ", rarity = "Legendary", anim = "wobble", sound = 1.4,
		desc = "Золотой кот, машущий лапкой. Гости идут к нему толпами.",
		ability = { kind = "guests", value = 10 }, ability2 = { kind = "synergy", value = 8 },
		dish = { id = "golden_dumplings", name = "Золотые пельмени", icon = "🥟" } },

	-- ===== MYTHICAL =====
	{ id = "voidwhale", name = "Кит Пустоты", rarity = "Mythical", anim = "float", sound = 0.4,
		desc = "Парящий кит из звёздной пустоты. Его песня усиливает всех.",
		ability = { kind = "synergy", value = 14 }, ability2 = { kind = "guard", value = 20 },
		dish = { id = "void_caviar", name = "Икра Пустоты", icon = "🫧" } },
	{ id = "astroqilin", name = "Звёздный цилинь", rarity = "Mythical", anim = "hop", sound = 1.1,
		desc = "Небесный зверь с гривой из звёзд. Притягивает удачу.",
		ability = { kind = "luck", value = 10 }, ability2 = { kind = "xp", value = 15 },
		dish = { id = "star_noodles", name = "Звёздная лапша", icon = "✨" } },
	{ id = "chronoturtle", name = "Хроночерепаха", rarity = "Mythical", anim = "crawl", sound = 0.5,
		desc = "Черепаха с часами на панцире. Замедляет время для себя и ускоряет для кухни.",
		ability = { kind = "dishes", value = 20 }, ability2 = { kind = "growth", value = 15 },
		dish = { id = "time_tart", name = "Тарт вечности", icon = "⏳" } },
	{ id = "emberseraph", name = "Пламенный серафим", rarity = "Mythical", anim = "flap", sound = 1.5,
		desc = "Шестикрылый дух огня. Плиты горят ярче в его присутствии.",
		ability = { kind = "cook", value = 14 }, ability2 = { kind = "profit", value = 8 },
		dish = { id = "seraph_souffle", name = "Огненное суфле", icon = "🕯️" } },

	-- ===== SECRET =====
	{ id = "glitchling", name = "Глитчик", rarity = "Secret", anim = "spin", sound = 2.0,
		desc = "Существо-ошибка из другой реальности. Ломает шансы в вашу пользу.",
		ability = { kind = "luck", value = 14 }, ability2 = { kind = "alarm", value = 20 },
		dish = { id = "glitch_bytes", name = "Пиксельные кусочки", icon = "👾" } },
	{ id = "chefbeast", name = "Шеф-Чудище", rarity = "Secret", anim = "wobble", sound = 0.6,
		desc = "Огромное чудище в поварском колпаке. Лучший повар островов.",
		ability = { kind = "cook", value = 18 }, ability2 = { kind = "tips", value = 15 },
		dish = { id = "beast_feast", name = "Пир Чудища", icon = "🍖" } },
	{ id = "moonsquid", name = "Лунный кальмар", rarity = "Secret", anim = "float", sound = 0.7,
		desc = "Светящийся кальмар с луны. О ресторане говорят на всех островах.",
		ability = { kind = "reputation", value = 1 }, ability2 = { kind = "synergy", value = 12 },
		dish = { id = "moon_mochi", name = "Лунные моти", icon = "🌙" } },
	{ id = "hydrabloom", name = "Гидра-цветок", rarity = "Secret", anim = "wobble", sound = 1.0,
		desc = "Трёхглавый цветочный змей. Каждая голова приносит прибыль.",
		ability = { kind = "profit", value = 15 }, ability2 = { kind = "guests", value = 10 },
		dish = { id = "hydra_salad", name = "Салат трёх голов", icon = "🥗" } },
}

Creatures.ById = {}
Creatures.ByRarity = {}
Creatures.DishById = {}
for _, c in ipairs(Creatures.List) do
	Creatures.ById[c.id] = c
	Creatures.ByRarity[c.rarity] = Creatures.ByRarity[c.rarity] or {}
	table.insert(Creatures.ByRarity[c.rarity], c)
	c.dish.creature = c.id
	c.dish.rarity = c.rarity
	Creatures.DishById[c.dish.id] = c.dish
end

function Creatures.stats(c)
	return Creatures.RarityStats[c.rarity]
end

function Creatures.levelMult(level)
	return 1 + 0.25 * (math.max(1, level) - 1)
end

function Creatures.abilityValue(ab, level)
	local v = ab.value * (1 + 0.1 * (math.max(1, level) - 1))
	return math.floor(v * 10 + 0.5) / 10
end

-- coins per minute for an adult creature
function Creatures.income(c, level)
	return math.floor(Creatures.RarityStats[c.rarity].income * Creatures.levelMult(level))
end

function Creatures.upgradeCost(c, level)
	return math.floor(Creatures.RarityStats[c.rarity].upgradeBase * level ^ 1.5)
end

function Creatures.stageOf(progress)
	local idx = 1
	for i, st in ipairs(Creatures.Stages) do
		if progress >= st.from then
			idx = i
		end
	end
	return idx, Creatures.Stages[idx]
end

function Creatures.describeAbility(ab, level)
	local info = Creatures.Abilities[ab.kind]
	return info.name .. ": " .. string.format(info.fmt, tostring(Creatures.abilityValue(ab, level)))
end

return Creatures
