-- Ingredients: price per unit (bought in packs of Config.IngredientPack),
-- quality 0..1 (affects dish quality), minStars = availability level.
local Ingredients = {}

Ingredients.Categories = {
	{ id = "veg", name = "Овощи", icon = "🥬" },
	{ id = "fruit", name = "Фрукты", icon = "🍓" },
	{ id = "meat", name = "Мясо", icon = "🥩" },
	{ id = "fish", name = "Рыба", icon = "🐟" },
	{ id = "dairy", name = "Молочное", icon = "🧀" },
	{ id = "flour", name = "Мука и тесто", icon = "🌾" },
	{ id = "spice", name = "Специи", icon = "🧂" },
	{ id = "sauce", name = "Соусы", icon = "🥫" },
	{ id = "drink", name = "Для напитков", icon = "🧃" },
	{ id = "premium", name = "Дорогие", icon = "💎" },
	{ id = "rare", name = "Редкие", icon = "🌟" },
}

local list = {
	-- id, name, cat, price, quality, minStars, icon, [season]
	{ "tomato", "Помидоры", "veg", 2, 0.70, 1, "🍅" },
	{ "lettuce", "Салат-латук", "veg", 2, 0.70, 1, "🥬" },
	{ "potato", "Картофель", "veg", 1.5, 0.65, 1, "🥔" },
	{ "onion", "Лук", "veg", 1, 0.65, 1, "🧅" },
	{ "mushroom", "Шампиньоны", "veg", 3, 0.75, 2, "🍄" },
	{ "pepper", "Перец", "veg", 2.5, 0.72, 2, "🫑" },
	{ "pumpkin", "Тыква", "veg", 3, 0.78, 1, "🎃", "autumn" },

	{ "lemon", "Лимоны", "fruit", 1.5, 0.70, 1, "🍋" },
	{ "orange", "Апельсины", "fruit", 1.5, 0.70, 1, "🍊" },
	{ "strawberry", "Клубника", "fruit", 3, 0.75, 1, "🍓" },
	{ "banana", "Бананы", "fruit", 2, 0.70, 1, "🍌" },
	{ "mango", "Манго", "fruit", 4, 0.80, 2, "🥭" },
	{ "berries", "Лесные ягоды", "fruit", 5, 0.85, 3, "🫐" },

	{ "beef", "Говядина", "meat", 8, 0.75, 1, "🥩" },
	{ "chicken", "Курица", "meat", 5, 0.70, 1, "🍗" },
	{ "bacon", "Бекон", "meat", 4, 0.70, 1, "🥓" },
	{ "lamb", "Баранина", "meat", 14, 0.85, 3, "🍖" },

	{ "salmon", "Лосось", "fish", 10, 0.80, 2, "🐟" },
	{ "shrimp", "Креветки", "fish", 9, 0.80, 2, "🦐" },
	{ "tuna", "Тунец", "fish", 15, 0.86, 3, "🐠" },

	{ "milk", "Молоко", "dairy", 1.5, 0.70, 1, "🥛" },
	{ "cheese", "Сыр", "dairy", 3, 0.75, 1, "🧀" },
	{ "butter", "Сливочное масло", "dairy", 2, 0.72, 1, "🧈" },
	{ "eggs", "Яйца", "dairy", 1.5, 0.70, 1, "🥚" },
	{ "cream", "Сливки", "dairy", 3, 0.78, 2, "🍶" },
	{ "icecream", "Мороженое", "dairy", 4, 0.75, 1, "🍨" },

	{ "flour", "Мука", "flour", 1, 0.70, 1, "🌾" },
	{ "bun", "Булочки", "flour", 1.5, 0.70, 1, "🍞" },
	{ "pasta", "Паста", "flour", 2, 0.72, 2, "🍝" },
	{ "rice", "Рис", "flour", 1.5, 0.72, 2, "🍚" },
	{ "dough", "Тесто для пиццы", "flour", 2, 0.72, 2, "🫓" },

	{ "salt", "Соль и перец", "spice", 0.5, 0.70, 1, "🧂" },
	{ "herbs", "Свежие травы", "spice", 2, 0.80, 1, "🌿" },
	{ "cinnamon", "Корица", "spice", 3, 0.80, 2, "🟤" },
	{ "vanilla", "Ваниль", "spice", 6, 0.85, 3, "🌼" },

	{ "ketchup", "Кетчуп", "sauce", 1, 0.65, 1, "🥫" },
	{ "tomato_sauce", "Томатный соус", "sauce", 2, 0.72, 1, "🍅" },
	{ "pesto", "Песто", "sauce", 4, 0.82, 2, "🟢" },
	{ "soy", "Соевый соус", "sauce", 2, 0.75, 2, "🫙" },
	{ "chocolate", "Шоколад", "sauce", 4, 0.80, 1, "🍫" },
	{ "caramel", "Карамель", "sauce", 3, 0.78, 2, "🍯" },

	{ "coffee_beans", "Кофейные зёрна", "drink", 3, 0.78, 1, "☕" },
	{ "tea_leaves", "Чайные листья", "drink", 2, 0.75, 1, "🍵" },
	{ "soda", "Газированная вода", "drink", 1, 0.65, 1, "🫧" },
	{ "mint", "Мята", "drink", 2, 0.78, 1, "🌱" },
	{ "sugar", "Сахар", "drink", 0.5, 0.70, 1, "🍬" },
	{ "ice", "Лёд", "drink", 0.3, 0.70, 1, "🧊" },

	{ "lobster", "Омар", "premium", 40, 0.95, 4, "🦞" },
	{ "saffron", "Шафран", "premium", 25, 0.95, 4, "🌺" },
	{ "wagyu", "Мраморная говядина вагю", "premium", 45, 1.00, 5, "🥩" },

	{ "truffle", "Трюфель", "rare", 60, 1.00, 5, "🟫" },
	{ "dragonfruit", "Питахайя", "rare", 12, 0.95, 4, "🐉" },
	{ "gold_leaf", "Пищевое золото", "rare", 80, 1.00, 5, "✨" },
}

-- Цены закупки в таблице указаны в "базовых" единицах; итоговая цена = базовая * PRICE_SCALE
Ingredients.PRICE_SCALE = 0.6

Ingredients.List = {}
Ingredients.ById = {}
for order, row in ipairs(list) do
	local item = {
		id = row[1],
		name = row[2],
		category = row[3],
		price = math.floor(row[4] * Ingredients.PRICE_SCALE * 100 + 0.5) / 100,
		quality = row[5],
		minStars = row[6],
		icon = row[7],
		season = row[8],
		rare = row[3] == "rare",
		order = order,
	}
	table.insert(Ingredients.List, item)
	Ingredients.ById[item.id] = item
end

-- Стартовый склад нового ресторана
Ingredients.StartStock = {
	tomato = 30,
	lettuce = 30,
	potato = 40,
	onion = 30,
	beef = 20,
	chicken = 20,
	bun = 30,
	cheese = 30,
	flour = 30,
	eggs = 30,
	milk = 30,
	butter = 20,
	salt = 40,
	lemon = 30,
	orange = 30,
	sugar = 40,
	ice = 60,
	soda = 30,
	tea_leaves = 20,
	icecream = 20,
	strawberry = 20,
	chocolate = 20,
	ketchup = 20,
}

return Ingredients
