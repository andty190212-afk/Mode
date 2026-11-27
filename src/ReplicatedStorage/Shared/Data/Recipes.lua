-- Dishes and drinks. Each has ingredients, base price, cook time, steps (mini-games),
-- minStars (availability). Cost is computed from ingredient prices.
local Ingredients = require(script.Parent.Ingredients)

local Recipes = {}

-- Mini-game steps: chop, grill, boil, bake, assemble, garnish, pour, shake, brew
Recipes.StepNames = {
	chop = "Нарезка",
	grill = "Жарка",
	boil = "Варка",
	bake = "Выпечка",
	assemble = "Сборка",
	garnish = "Украшение",
	pour = "Налить",
	shake = "Шейкер",
	brew = "Заварка",
	prep = "Подготовка мяса",
}

Recipes.Categories = {
	{ id = "burger", name = "Бургеры", icon = "🍔" },
	{ id = "pizza", name = "Пицца", icon = "🍕" },
	{ id = "pasta", name = "Паста", icon = "🍝" },
	{ id = "salad", name = "Салаты", icon = "🥗" },
	{ id = "soup", name = "Супы", icon = "🍲" },
	{ id = "steak", name = "Стейки", icon = "🥩" },
	{ id = "fish", name = "Рыбные блюда", icon = "🐟" },
	{ id = "dessert", name = "Десерты", icon = "🍰" },
	{ id = "breakfast", name = "Завтраки", icon = "🍳" },
	{ id = "premium", name = "Премиальные", icon = "👑" },
	{ id = "drink", name = "Напитки", icon = "🥤" },
}

local dishes = {
	-- ★1
	{ id = "burger", name = "Классический бургер", cat = "burger", icon = "🍔", price = 18, time = 10, stars = 1,
		ing = { bun = 1, beef = 1, lettuce = 1, tomato = 1, cheese = 1 }, steps = { "prep", "grill", "assemble" } },
	{ id = "fries", name = "Картофель фри", cat = "burger", icon = "🍟", price = 8, time = 6, stars = 1,
		ing = { potato = 2, salt = 1, ketchup = 1 }, steps = { "chop", "grill" } },
	{ id = "grilled_cheese", name = "Горячий сэндвич с сыром", cat = "breakfast", icon = "🥪", price = 10, time = 6, stars = 1,
		ing = { bun = 1, cheese = 2, butter = 1 }, steps = { "assemble", "grill" } },
	{ id = "tomato_soup", name = "Томатный суп", cat = "soup", icon = "🍅", price = 12, time = 9, stars = 1,
		ing = { tomato = 3, onion = 1, salt = 1 }, steps = { "chop", "boil" } },
	{ id = "garden_salad", name = "Овощной салат", cat = "salad", icon = "🥗", price = 9, time = 5, stars = 1,
		ing = { lettuce = 2, tomato = 1, onion = 1 }, steps = { "chop", "garnish" } },
	{ id = "pancakes", name = "Блинчики", cat = "breakfast", icon = "🥞", price = 12, time = 8, stars = 1,
		ing = { flour = 1, eggs = 2, milk = 1, butter = 1 }, steps = { "assemble", "grill", "garnish" } },
	{ id = "nuggets", name = "Куриные наггетсы", cat = "burger", icon = "🍗", price = 12, time = 8, stars = 1,
		ing = { chicken = 2, flour = 1, salt = 1 }, steps = { "prep", "grill" } },
	{ id = "sundae", name = "Шоколадный сандей", cat = "dessert", icon = "🍨", price = 9, time = 4, stars = 1,
		ing = { icecream = 2, chocolate = 1 }, steps = { "assemble", "garnish" } },
	{ id = "omelette", name = "Омлет", cat = "breakfast", icon = "🍳", price = 10, time = 6, stars = 1,
		ing = { eggs = 3, milk = 1, salt = 1 }, steps = { "chop", "grill" } },
	-- ★2
	{ id = "margherita", name = "Пицца Маргарита", cat = "pizza", icon = "🍕", price = 24, time = 12, stars = 2,
		ing = { dough = 1, tomato_sauce = 1, cheese = 2, herbs = 1 }, steps = { "assemble", "bake", "garnish" } },
	{ id = "bolognese", name = "Спагетти Болоньезе", cat = "pasta", icon = "🍝", price = 26, time = 12, stars = 2,
		ing = { pasta = 1, beef = 1, tomato_sauce = 1, onion = 1 }, steps = { "chop", "boil", "grill" } },
	{ id = "mushroom_soup", name = "Грибной крем-суп", cat = "soup", icon = "🍄", price = 20, time = 10, stars = 2,
		ing = { mushroom = 3, cream = 1, onion = 1 }, steps = { "chop", "boil", "garnish" } },
	{ id = "caesar", name = "Цезарь с курицей", cat = "salad", icon = "🥗", price = 22, time = 9, stars = 2,
		ing = { chicken = 1, lettuce = 2, cheese = 1, bun = 1 }, steps = { "grill", "chop", "assemble" } },
	{ id = "bacon_breakfast", name = "Английский завтрак", cat = "breakfast", icon = "🥓", price = 18, time = 9, stars = 2,
		ing = { eggs = 2, bacon = 2, bun = 1, tomato = 1 }, steps = { "grill", "assemble" } },
	{ id = "strawberry_cake", name = "Клубничный торт", cat = "dessert", icon = "🍰", price = 22, time = 12, stars = 2,
		ing = { flour = 1, eggs = 2, strawberry = 2, cream = 1, sugar = 1 }, steps = { "assemble", "bake", "garnish" } },
	{ id = "shrimp_pasta", name = "Паста с креветками", cat = "pasta", icon = "🦐", price = 30, time = 11, stars = 2,
		ing = { pasta = 1, shrimp = 2, butter = 1, herbs = 1 }, steps = { "boil", "grill", "garnish" } },
	{ id = "fish_chips", name = "Лосось с картофелем", cat = "fish", icon = "🐟", price = 28, time = 11, stars = 2,
		ing = { salmon = 1, potato = 2, lemon = 1 }, steps = { "prep", "grill", "garnish" } },
	-- ★3
	{ id = "teriyaki", name = "Лосось терияки", cat = "fish", icon = "🍱", price = 42, time = 13, stars = 3,
		ing = { salmon = 2, rice = 1, soy = 1 }, steps = { "boil", "grill", "garnish" } },
	{ id = "ribeye", name = "Стейк рибай", cat = "steak", icon = "🥩", price = 48, time = 14, stars = 3,
		ing = { beef = 3, butter = 1, herbs = 1, potato = 1 }, steps = { "prep", "grill", "garnish" } },
	{ id = "pesto_pasta", name = "Паста песто", cat = "pasta", icon = "🌿", price = 32, time = 10, stars = 3,
		ing = { pasta = 1, pesto = 1, cheese = 1 }, steps = { "boil", "assemble", "garnish" } },
	{ id = "lamb_chops", name = "Каре ягнёнка", cat = "steak", icon = "🍖", price = 55, time = 15, stars = 3,
		ing = { lamb = 2, herbs = 1, potato = 1 }, steps = { "prep", "grill", "garnish" } },
	{ id = "sushi", name = "Суши-сет", cat = "fish", icon = "🍣", price = 58, time = 15, stars = 3,
		ing = { rice = 2, tuna = 1, salmon = 1, soy = 1 }, steps = { "boil", "chop", "assemble", "garnish" } },
	{ id = "tiramisu", name = "Тирамису", cat = "dessert", icon = "🍮", price = 30, time = 11, stars = 3,
		ing = { coffee_beans = 1, cream = 1, eggs = 1, chocolate = 1 }, steps = { "assemble", "garnish" } },
	{ id = "veggie_pizza", name = "Пицца с перцем и грибами", cat = "pizza", icon = "🍕", price = 34, time = 13, stars = 3,
		ing = { dough = 1, pepper = 1, mushroom = 1, cheese = 1, tomato_sauce = 1 }, steps = { "chop", "assemble", "bake" } },
	{ id = "berry_tart", name = "Ягодный тарт", cat = "dessert", icon = "🥧", price = 36, time = 12, stars = 3,
		ing = { flour = 1, berries = 2, cream = 1, sugar = 1 }, steps = { "assemble", "bake", "garnish" } },
	-- ★4
	{ id = "lobster_thermidor", name = "Омар Термидор", cat = "premium", icon = "🦞", price = 120, time = 18, stars = 4,
		ing = { lobster = 1, butter = 1, cream = 1, cheese = 1 }, steps = { "prep", "boil", "bake", "garnish" } },
	{ id = "tuna_tartare", name = "Тартар из тунца", cat = "fish", icon = "🐠", price = 85, time = 13, stars = 4,
		ing = { tuna = 2, lemon = 1, herbs = 1 }, steps = { "chop", "assemble", "garnish" } },
	{ id = "saffron_risotto", name = "Ризотто с шафраном", cat = "premium", icon = "🍛", price = 110, time = 17, stars = 4,
		ing = { rice = 2, saffron = 1, butter = 1, cheese = 1 }, steps = { "chop", "boil", "garnish" } },
	{ id = "mango_pavlova", name = "Павлова с манго", cat = "dessert", icon = "🥭", price = 60, time = 14, stars = 4,
		ing = { eggs = 2, sugar = 1, mango = 2, cream = 1 }, steps = { "assemble", "bake", "garnish" } },
	{ id = "creme_brulee", name = "Ванильный крем-брюле", cat = "dessert", icon = "🍮", price = 55, time = 14, stars = 4,
		ing = { cream = 2, eggs = 2, vanilla = 1, sugar = 1 }, steps = { "boil", "bake", "garnish" } },
	-- ★5
	{ id = "wagyu_steak", name = "Стейк из вагю", cat = "premium", icon = "🥩", price = 260, time = 20, stars = 5,
		ing = { wagyu = 2, butter = 1, herbs = 1 }, steps = { "prep", "grill", "garnish" } },
	{ id = "truffle_pasta", name = "Паста с трюфелем", cat = "premium", icon = "🍝", price = 220, time = 18, stars = 5,
		ing = { pasta = 1, truffle = 1, butter = 1, cheese = 1 }, steps = { "boil", "chop", "assemble", "garnish" } },
	{ id = "golden_cake", name = "Золотой шоколадный торт", cat = "dessert", icon = "🎂", price = 280, time = 20, stars = 5,
		ing = { flour = 1, eggs = 2, chocolate = 2, gold_leaf = 1, cream = 1 }, steps = { "assemble", "bake", "garnish", "garnish" } },
	{ id = "dragon_dessert", name = "Десерт «Дракон»", cat = "dessert", icon = "🐉", price = 140, time = 15, stars = 5,
		ing = { dragonfruit = 2, cream = 1, berries = 1 }, steps = { "chop", "assemble", "garnish" } },
	{ id = "surf_turf", name = "Сёрф-энд-тёрф", cat = "premium", icon = "👑", price = 400, time = 24, stars = 5,
		ing = { lobster = 1, wagyu = 1, butter = 1, herbs = 1 }, steps = { "prep", "grill", "boil", "garnish" } },
	-- Особые рецепты шеф-повара (требуют активного шеф-повара в ресторане)
	{ id = "chef_burger", name = "Фирменный бургер шефа", cat = "burger", icon = "🍔", price = 40, time = 12, stars = 2, chefOnly = true,
		ing = { bun = 1, beef = 2, cheese = 1, bacon = 1, mushroom = 1 }, steps = { "prep", "grill", "assemble", "garnish" } },
	{ id = "chef_seafood", name = "Морское ассорти шефа", cat = "fish", icon = "🦐", price = 95, time = 16, stars = 3, chefOnly = true,
		ing = { shrimp = 2, salmon = 1, tuna = 1, lemon = 1 }, steps = { "prep", "grill", "garnish" } },
	{ id = "chef_tasting", name = "Дегустационный сет шефа", cat = "premium", icon = "🍽️", price = 520, time = 26, stars = 5, chefOnly = true,
		ing = { wagyu = 1, lobster = 1, truffle = 1, saffron = 1 }, steps = { "prep", "grill", "boil", "assemble", "garnish" } },
	-- Сезонные
	{ id = "pumpkin_soup", name = "Тыквенный суп", cat = "soup", icon = "🎃", price = 26, time = 10, stars = 2, season = "autumn",
		ing = { pumpkin = 2, cream = 1, cinnamon = 1 }, steps = { "chop", "boil", "garnish" } },
	{ id = "gingerbread", name = "Имбирное печенье", cat = "dessert", icon = "🍪", price = 20, time = 9, stars = 2, season = "winter",
		ing = { flour = 1, cinnamon = 1, sugar = 1, butter = 1 }, steps = { "assemble", "bake" } },
	-- Редкие рецепты (открываются достижениями, критиками и событиями)
	{ id = "phoenix_curry", name = "Карри «Феникс»", cat = "premium", icon = "🔥", price = 150, time = 16, stars = 4, rare = true,
		ing = { chicken = 2, rice = 1, pepper = 2, saffron = 1 }, steps = { "chop", "grill", "boil", "garnish" } },
	{ id = "island_paella", name = "Островная паэлья", cat = "fish", icon = "🥘", price = 180, time = 18, stars = 4, rare = true,
		ing = { rice = 2, shrimp = 2, saffron = 1, lemon = 1 }, steps = { "chop", "boil", "grill", "garnish" } },
	{ id = "cloud_souffle", name = "Облачное суфле", cat = "dessert", icon = "☁️", price = 120, time = 14, stars = 3, rare = true,
		ing = { eggs = 3, vanilla = 1, sugar = 1, cream = 1 }, steps = { "assemble", "bake", "garnish" } },
}

local drinks = {
	{ id = "lemonade", name = "Лимонад", icon = "🍋", price = 6, time = 5, stars = 1,
		ing = { lemon = 2, sugar = 1, ice = 1, soda = 1 }, steps = { "pour", "shake" } },
	{ id = "orange_juice", name = "Апельсиновый сок", icon = "🍊", price = 6, time = 4, stars = 1,
		ing = { orange = 3 }, steps = { "chop", "pour" } },
	{ id = "iced_tea", name = "Холодный чай", icon = "🧋", price = 5, time = 5, stars = 1,
		ing = { tea_leaves = 1, lemon = 1, sugar = 1, ice = 1 }, steps = { "brew", "pour" } },
	{ id = "hot_tea", name = "Горячий чай", icon = "🍵", price = 4, time = 4, stars = 1,
		ing = { tea_leaves = 1, sugar = 1 }, steps = { "brew" } },
	{ id = "coffee", name = "Кофе", icon = "☕", price = 5, time = 4, stars = 1, needs = { coffee = 1 },
		ing = { coffee_beans = 1, sugar = 1 }, steps = { "brew" } },
	{ id = "strawberry_shake", name = "Клубничный милкшейк", icon = "🥤", price = 9, time = 6, stars = 1,
		ing = { milk = 1, icecream = 1, strawberry = 1 }, steps = { "pour", "shake" } },
	{ id = "choco_shake", name = "Шоколадный милкшейк", icon = "🥤", price = 9, time = 6, stars = 1,
		ing = { milk = 1, icecream = 1, chocolate = 1 }, steps = { "pour", "shake" } },
	{ id = "mojito", name = "Мохито (безалкогольный)", icon = "🌱", price = 12, time = 6, stars = 2,
		ing = { mint = 1, lemon = 1, soda = 1, sugar = 1, ice = 1 }, steps = { "chop", "shake", "pour" } },
	{ id = "cappuccino", name = "Капучино", icon = "☕", price = 9, time = 5, stars = 2, needs = { coffee = 2 },
		ing = { coffee_beans = 1, milk = 2 }, steps = { "brew", "pour" } },
	{ id = "mango_smoothie", name = "Манго-смузи", icon = "🥭", price = 12, time = 6, stars = 2,
		ing = { mango = 2, milk = 1, ice = 1 }, steps = { "chop", "shake" } },
	{ id = "berry_fizz", name = "Ягодный физз", icon = "🫐", price = 16, time = 6, stars = 3,
		ing = { berries = 1, soda = 1, sugar = 1, ice = 1 }, steps = { "pour", "shake", "garnish" } },
	{ id = "caramel_frappe", name = "Карамельный фраппе", icon = "🧋", price = 16, time = 7, stars = 3, needs = { coffee = 3 },
		ing = { coffee_beans = 1, milk = 1, caramel = 1, ice = 1 }, steps = { "brew", "shake", "garnish" } },
	{ id = "tropical_sunset", name = "Коктейль «Тропический закат»", icon = "🌅", price = 24, time = 8, stars = 4,
		ing = { mango = 1, orange = 1, strawberry = 1, soda = 1 }, steps = { "chop", "shake", "pour", "garnish" } },
	{ id = "golden_latte", name = "Золотой латте", icon = "✨", price = 60, time = 8, stars = 5, needs = { coffee = 4 },
		ing = { coffee_beans = 1, milk = 1, gold_leaf = 1 }, steps = { "brew", "pour", "garnish" } },
	{ id = "dragon_elixir", name = "Эликсир дракона", icon = "🐉", price = 45, time = 8, stars = 4, rare = true,
		ing = { dragonfruit = 1, berries = 1, soda = 1, mint = 1 }, steps = { "chop", "shake", "pour", "garnish" } },
	{ id = "summer_smoothie", name = "Летний смузи", icon = "🍹", price = 14, time = 6, stars = 1, season = "summer",
		ing = { banana = 1, strawberry = 1, milk = 1, ice = 1 }, steps = { "chop", "shake" } },
	{ id = "hot_cocoa", name = "Горячий какао", icon = "🍫", price = 10, time = 5, stars = 1, season = "winter",
		ing = { milk = 1, chocolate = 1, sugar = 1 }, steps = { "brew", "pour" } },
}

Recipes.List = {}
Recipes.ById = {}
Recipes.Dishes = {}
Recipes.Drinks = {}

local function costOf(ing)
	local c = 0
	for id, n in pairs(ing) do
		local item = Ingredients.ById[id]
		assert(item, "Unknown ingredient " .. id)
		c += item.price * n
	end
	return c
end

local function qualityOf(ing)
	local q, n = 0, 0
	for id, cnt in pairs(ing) do
		q += Ingredients.ById[id].quality * cnt
		n += cnt
	end
	return n > 0 and q / n or 0.7
end

-- Цены блюд в таблице — базовые; итоговая цена продажи = базовая * PRICE_SCALE
Recipes.PRICE_SCALE = 2

for i, d in ipairs(dishes) do
	d.price *= Recipes.PRICE_SCALE
	d.kind = "dish"
	d.cost = costOf(d.ing)
	d.baseQuality = qualityOf(d.ing)
	d.order = i
	table.insert(Recipes.List, d)
	table.insert(Recipes.Dishes, d)
	Recipes.ById[d.id] = d
end
for i, d in ipairs(drinks) do
	d.price *= Recipes.PRICE_SCALE
	d.kind = "drink"
	d.cat = "drink"
	d.cost = costOf(d.ing)
	d.baseQuality = qualityOf(d.ing)
	d.order = 100 + i
	table.insert(Recipes.List, d)
	table.insert(Recipes.Drinks, d)
	Recipes.ById[d.id] = d
end

-- Seasons by month (server time, UTC)
function Recipes.currentSeason(t)
	local month = tonumber(os.date("!%m", t or os.time()))
	if month == 12 or month == 1 then
		return "winter"
	elseif month >= 6 and month <= 8 then
		return "summer"
	elseif month == 10 or month == 11 then
		return "autumn"
	end
	return "none"
end

-- Блюда, доступные ресторану сейчас (без учёта запасов)
function Recipes.isAvailable(recipe, rest, ctx)
	if recipe.stars > (rest.stars or 1) then
		return false, "Нужно " .. recipe.stars .. "★"
	end
	if recipe.season and recipe.season ~= Recipes.currentSeason() then
		return false, "Сезонное блюдо"
	end
	if recipe.rare and not (rest.unlockedRecipes and rest.unlockedRecipes[recipe.id]) then
		return false, "Редкий рецепт не открыт"
	end
	if recipe.chefOnly and not (ctx and ctx.chefActive) then
		return false, "Нужен шеф-повар"
	end
	if recipe.needs then
		for eq, lvl in pairs(recipe.needs) do
			if ((rest.equipment or {})[eq] or 0) < lvl then
				return false, "Нужно оборудование"
			end
		end
	end
	return true
end

function Recipes.hasStock(recipe, inventory, mult)
	mult = mult or 1
	for id, n in pairs(recipe.ing) do
		if (inventory[id] or 0) < n * mult then
			return false
		end
	end
	return true
end

return Recipes
