-- Fantasy creatures grown in island laboratories.
-- Every creature has its own model (tools/build/creatures.luau, Assets.Creatures[id]),
-- rarity, passive abilities, income and a linked special dish.
-- Eating the dish ALWAYS gives one random weapon of the creature's rarity.
local Creatures = {}

-- per-rarity tuning
Creatures.RarityStats = {
	Common = { grow = 90, income = 30, dishTime = 60, upgradeBase = 600, speedupRate = 6, stealHold = 2.5 },
	Uncommon = { grow = 180, income = 55, dishTime = 75, upgradeBase = 1200, speedupRate = 8, stealHold = 3 },
	Rare = { grow = 360, income = 100, dishTime = 90, upgradeBase = 2500, speedupRate = 10, stealHold = 3.5 },
	Epic = { grow = 600, income = 180, dishTime = 120, upgradeBase = 5000, speedupRate = 14, stealHold = 4.5 },
	Legendary = { grow = 900, income = 320, dishTime = 150, upgradeBase = 10000, speedupRate = 20, stealHold = 5.5 },
	Mythical = { grow = 1200, income = 550, dishTime = 180, upgradeBase = 20000, speedupRate = 30, stealHold = 6.5 },
	Secret = { grow = 1500, income = 900, dishTime = 240, upgradeBase = 40000, speedupRate = 45, stealHold = 8 },
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

-- 30 original meme-style food creatures (absurd "Italian" names), 7 rarities
local function C(id, name, rarity, anim, sound, desc, ab, ab2, dish)
	return { id = id, name = name, rarity = rarity, anim = anim, sound = sound, desc = desc, ability = ab, ability2 = ab2, dish = dish }
end
local function A(kind, value)
	return { kind = kind, value = value }
end
local function D(id, name, icon)
	return { id = id, name = name, icon = icon }
end

Creatures.List = {
	-- ===== COMMON (6) =====
	C("burgerosauro", "Бургерозавро Гриллини", "Common", "hop", 0.8, "Динозавр из бургера. Рычит котлетой и машет листиком салата.", A("profit", 3), A("dishes", 6), D("dino_burger", "Динобургер", "🍔")),
	C("tostero", "Тостеро Кошкарини", "Common", "wobble", 1.3, "Кот-тостер. Когда радуется — из него выпрыгивают тосты.", A("tips", 4), A("xp", 4), D("cat_toast", "Кото-тост", "🍞")),
	C("pelmenino", "Пельменини Ниндзяччо", "Common", "hop", 1.4, "Пельмень-ниндзя. Бесшумно прячется в тарелке.", A("service", 4), A("guard", 8), D("ninja_dumplings", "Пельмени-сюрикены", "🥟")),
	C("sosiskino", "Сосискино Роллерини", "Common", "crawl", 1.2, "Сосиска на роликах с полосой горчицы. Самая быстрая на острове.", A("guests", 3), A("tips", 4), D("roller_hotdog", "Хот-дог на колёсах", "🌭")),
	C("kartofello", "Картофелло Ворчуни", "Common", "wobble", 0.7, "Ворчливая картошка в берете и с усами. Ворчит, но работает.", A("ingredients", 1), A("growth", 5), D("grumpy_mash", "Пюре ворчуна", "🥔")),
	C("kapustino", "Капустино Барабанни", "Common", "spin", 1.0, "Кочан-барабанщик. Стучит ритм для всей кухни.", A("growth", 5), A("reputation", 0.2), D("drum_borscht", "Барабанный борщ", "🥬")),

	-- ===== UNCOMMON (5) =====
	C("arbuzino", "Арбузино Слонелли", "Uncommon", "hop", 0.6, "Слон из арбуза. Хоботом раздаёт гостям семечки.", A("guests", 4), A("profit", 4), D("melon_sorbet", "Слоновий арбузный сорбет", "🍉")),
	C("spagettino", "Спагеттино Осьминоччи", "Uncommon", "float", 1.0, "Осьминог-тефтелька с щупальцами из спагетти. Варит восемь блюд сразу.", A("cook", 5), A("dishes", 8), D("eight_arm_pasta", "Паста восьми рук", "🍝")),
	C("chaynikus", "Чайникус Драконелло", "Uncommon", "flap", 1.2, "Дракон-чайник. Пыхтит паром и свистит, когда рядом вор.", A("service", 5), A("alarm", 4), D("dragon_tea", "Драконий чай", "🫖")),
	C("ponchikko", "Пончикко Космонавти", "Uncommon", "float", 1.5, "Пончик-космонавт в шлеме и с ракетным ранцем.", A("xp", 6), A("luck", 3), D("cosmo_donut", "Космо-пончик", "🍩")),
	C("limonchello", "Лимончелло Скейтерини", "Uncommon", "crawl", 1.6, "Лимон-скейтер в тёмных очках. Самый крутой фрукт.", A("tips", 6), A("service", 4), D("skater_lemonade", "Лимонад скейтера", "🍋")),

	-- ===== RARE (5) =====
	C("sushino", "Сушино Самурайчи", "Rare", "hop", 0.9, "Ролл-самурай в доспехах из лосося с катаной-палочкой.", A("guard", 12), A("cook", 6), D("samurai_roll", "Самурайский ролл", "🍣")),
	C("pitstsagatto", "Пиццагатто Диджеини", "Rare", "wobble", 1.1, "Кот-пицца в наушниках. Ставит музыку — гости танцуют.", A("guests", 7), A("synergy", 5), D("party_pizza", "Пицца-вечеринка", "🍕")),
	C("morozhenello", "Мороженелло Пингвини", "Rare", "hop", 1.4, "Пингвин из рожка мороженого. Никогда не тает.", A("dishes", 10), A("growth", 8), D("penguin_icecream", "Пингвиний пломбир", "🍦")),
	C("krevetto", "Креветто Боксини", "Rare", "hop", 1.0, "Креветка-боксёр в перчатках. Отправляет воров в нокаут.", A("alarm", 6), A("profit", 6), D("knockout_shrimp", "Креветки нокаут", "🍤")),
	C("kofeino", "Кофеино Совиньоли", "Rare", "flap", 1.2, "Сова-чашка кофе. Не спит никогда и учит всех вокруг.", A("xp", 10), A("service", 6), D("owl_espresso", "Совиный эспрессо", "☕")),

	-- ===== EPIC (4) =====
	C("tortello", "Тортелло Бегемотти", "Epic", "wobble", 0.5, "Бегемот-торт со свечками на спине. Каждый день — праздник.", A("profit", 9), A("reputation", 0.5), D("hippo_cake", "Бегемотский торт", "🎂")),
	C("perchello", "Перчелло Вулканини", "Epic", "spin", 0.8, "Перец-вулкан. Извергает острую лаву прямо на плиты.", A("cook", 9), A("alarm", 6), D("volcano_chili", "Вулканический чили", "🌶️")),
	C("bagettino", "Багеттино Рыцарелли", "Epic", "hop", 0.9, "Рыцарь-багет со щитом-круассаном. Защищает лабораторию.", A("guard", 18), A("tips", 8), D("knight_sandwich", "Рыцарский сэндвич", "🥖")),
	C("meduzino", "Медузино Желатини", "Epic", "float", 1.6, "Медуза из фруктового желе. Дрожит и светится.", A("synergy", 8), A("dishes", 12), D("jelly_medusa", "Желе-медуза", "🍮")),

	-- ===== LEGENDARY (4) =====
	C("lobstero", "Лобстеро Императоре", "Legendary", "crawl", 0.7, "Лобстер-император в короне и мантии. Правит всеми кухнями.", A("profit", 11), A("guests", 8), D("emperor_lobster", "Императорский лобстер", "🦞")),
	C("blinchello", "Блинчелло Башнери", "Legendary", "wobble", 0.9, "Великан из стопки блинов с короной из масла и сиропом.", A("ingredients", 3), A("growth", 14), D("pancake_tower", "Башня блинов", "🥞")),
	C("ramento", "Раменто Драконини", "Legendary", "float", 1.1, "Дракон из лапши, вылетающий из миски рамена.", A("cook", 13), A("xp", 12), D("dragon_ramen", "Драконий рамен", "🍜")),
	C("formaggio", "Формаджо Лунаре", "Legendary", "float", 1.4, "Мышь-луна из сыра. Приносит удачу по ночам.", A("luck", 7), A("synergy", 8), D("moon_cheese", "Лунный сыр", "🧀")),

	-- ===== MYTHICAL (3) =====
	C("takotitan", "Такотитан Галактико", "Mythical", "float", 0.5, "Титан-тако с начинкой из галактик и планетами вокруг.", A("synergy", 14), A("guard", 20), D("galaxy_taco", "Галактическое тако", "🌮")),
	C("fenikssone", "Фениксоне Фламбе", "Mythical", "flap", 1.3, "Феникс из пылающего крем-брюле. Возрождается из десерта.", A("profit", 13), A("reputation", 0.8), D("flambe_fire", "Огненное фламбе", "🔥")),
	C("krakenetti", "Кракенетти Карбонара", "Mythical", "float", 0.6, "Кракен из пасты карбонара. Утаскивает продукты из глубин.", A("cook", 15), A("ingredients", 4), D("abyss_carbonara", "Карбонара бездны", "🦑")),

	-- ===== SECRET (3) =====
	C("shefissimo", "Шефиссимо Супремо", "Secret", "wobble", 0.6, "Четырёхрукий золотой шеф-гигант. Лучший повар всех миров.", A("cook", 18), A("tips", 15), D("supremo_feast", "Пир Шефиссимо", "🍖")),
	C("glitchetto", "Глитчетто Пиццелли", "Secret", "spin", 2.0, "Пицца-призрак-ошибка из другого измерения. Ломает шансы.", A("luck", 14), A("alarm", 10), D("glitch_pizza", "Глитч-пицца", "👾")),
	C("lunamoti", "Лунамоти Кавайни", "Secret", "float", 1.5, "Лунный дух-моти с ушками кролика. О ресторане говорят все острова.", A("reputation", 1), A("synergy", 12), D("star_mochi", "Звёздные моти", "🍡")),
}

-- old creature ids (before 3.0) -> new ids of the same rarity (save migration)
Creatures.Legacy = {
	glowslug = "burgerosauro", crumbcrab = "tostero", puffshroom = "pelmenino", pebblemole = "kartofello",
	jellybell = "arbuzino", pepperimp = "spagettino", cloudpup = "chaynikus", clockbeetle = "ponchikko",
	lanternfox = "sushino", coralgolem = "pitstsagatto", mushowl = "morozhenello", bubbledrake = "kofeino",
	magmatoad = "tortello", prismstag = "perchello", nebulamoth = "bagettino", thunderhog = "meduzino",
	sunphoenix = "lobstero", tidekraken = "blinchello", crystalwyrm = "ramento", luckycat = "formaggio",
	voidwhale = "takotitan", astroqilin = "fenikssone", chronoturtle = "krakenetti", emberseraph = "takotitan",
	glitchling = "glitchetto", chefbeast = "shefissimo", moonsquid = "lunamoti", hydrabloom = "shefissimo",
}
Creatures.LegacyDish = {
	glow_jelly = "dino_burger", crumb_toast = "cat_toast", spore_soup = "ninja_dumplings", crystal_fries = "grumpy_mash",
	bell_pudding = "melon_sorbet", imp_chili = "eight_arm_pasta", cloud_cake = "dragon_tea", gear_cookies = "cosmo_donut",
	lantern_ramen = "samurai_roll", coral_sushi = "party_pizza", owl_pie = "penguin_icecream", bubble_tea = "owl_espresso",
	lava_steak = "hippo_cake", prism_parfait = "volcano_chili", nebula_macaron = "knight_sandwich", thunder_pops = "jelly_medusa",
	phoenix_wings = "emperor_lobster", kraken_paella = "pancake_tower", wyrm_candy = "dragon_ramen", golden_dumplings = "moon_cheese",
	void_caviar = "galaxy_taco", star_noodles = "flambe_fire", time_tart = "abyss_carbonara", seraph_souffle = "galaxy_taco",
	glitch_bytes = "glitch_pizza", beast_feast = "supremo_feast", moon_mochi = "star_mochi", hydra_salad = "supremo_feast",
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
