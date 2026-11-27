-- Weapons. Every weapon has its own model (Assets.Weapons[id]), basic attack and a
-- UNIQUE special ability (implemented in CombatService.Abilities[ability.id]).
-- Special dishes give a random weapon of EXACTLY the creature's rarity.
-- starter = true: free weapons from the island stands (not dropped by dishes).
local Weapons = {}

Weapons.Styles = {
	fast = "Быстрое",
	heavy = "Тяжёлое",
	ranged = "Дальнобойное",
	defense = "Защитное",
	magic = "Магическое",
	control = "Контроль",
	summon = "Призыв",
	mobility = "Перемещение",
	mass = "Массовое",
}

-- kind: "melee" hits in a cone in front, "ranged" fires a projectile along the aim
Weapons.List = {
	-- ===== FREE STARTER WEAPONS =====
	{ id = "starter_bat", name = "Бита", rarity = "Common", starter = true, style = "heavy", icon = "🏏",
		kind = "melee", damage = 8, cooldown = 0.9, range = 7, color = { 170, 120, 70 },
		ability = { id = "home_run", name = "Хоум-ран", cooldown = 8, desc = "Мощный удар отбрасывает противника далеко назад." } },
	{ id = "starter_sword", name = "Меч", rarity = "Common", starter = true, style = "defense", icon = "🗡️",
		kind = "melee", damage = 9, cooldown = 0.7, range = 7, color = { 200, 205, 215 },
		ability = { id = "guard", name = "Защитная стойка", cooldown = 10, desc = "2 секунды получаете на 40% меньше урона." } },

	-- ===== COMMON =====
	{ id = "spiky_ladle", name = "Колючий половник", rarity = "Common", style = "fast", icon = "🥄",
		kind = "melee", damage = 11, cooldown = 0.5, range = 7, color = { 150, 160, 175 },
		ability = { id = "spin", name = "Вихрь половника", cooldown = 8, desc = "Крутитесь на месте и бьёте всех вокруг (14 урона)." } },
	{ id = "coconut_sling", name = "Кокосовая праща", rarity = "Common", style = "ranged", icon = "🥥",
		kind = "ranged", damage = 9, cooldown = 0.8, range = 45, projectile = "coconut", color = { 120, 80, 50 },
		ability = { id = "coconut_bomb", name = "Кокосовая бомба", cooldown = 10, desc = "Бросает взрывной кокос в точку прицела (15 урона по области)." } },
	{ id = "rolling_pin", name = "Скалка-таран", rarity = "Common", style = "heavy", icon = "🪵",
		kind = "melee", damage = 15, cooldown = 1.1, range = 7, color = { 220, 180, 120 },
		ability = { id = "charge", name = "Таран", cooldown = 9, desc = "Рывок вперёд: первый противник получает 14 урона и отлетает." } },
	{ id = "bubble_wand", name = "Пузырчатая палочка", rarity = "Common", style = "control", icon = "🫧",
		kind = "ranged", damage = 8, cooldown = 0.7, range = 35, projectile = "bubble", color = { 120, 220, 255 },
		ability = { id = "bubble_trap", name = "Пузырь-ловушка", cooldown = 12, desc = "Запирает ближайшего противника впереди в пузырь на 1.2 с." } },

	-- ===== UNCOMMON =====
	{ id = "chili_blade", name = "Перчёный клинок", rarity = "Uncommon", style = "fast", icon = "🌶️",
		kind = "melee", damage = 13, cooldown = 0.6, range = 7, color = { 230, 50, 40 },
		ability = { id = "flame_wave", name = "Огненная волна", cooldown = 10, desc = "Конус огня: 10 урона и поджог на 3 секунды." } },
	{ id = "frost_spatula", name = "Морозная лопатка", rarity = "Uncommon", style = "control", icon = "❄️",
		kind = "melee", damage = 12, cooldown = 0.7, range = 7, color = { 150, 220, 255 },
		ability = { id = "ice_field", name = "Ледяное поле", cooldown = 13, desc = "Ледяная зона вокруг вас: враги замедлены на 50% и мёрзнут." } },
	{ id = "anchor_hook", name = "Якорь-крюк", rarity = "Uncommon", style = "control", icon = "⚓",
		kind = "melee", damage = 14, cooldown = 1.0, range = 8, color = { 90, 100, 120 },
		ability = { id = "hook_pull", name = "Цепной крюк", cooldown = 11, desc = "Цепью притягивает первого противника на линии к вам." } },
	{ id = "thunder_whisk", name = "Громовой венчик", rarity = "Uncommon", style = "magic", icon = "🌩️",
		kind = "melee", damage = 12, cooldown = 0.65, range = 7, color = { 255, 230, 80 },
		ability = { id = "static_shock", name = "Разряд", cooldown = 11, desc = "Молния бьёт ближайшего врага (16 урона) и оглушает на 0.6 с." } },

	-- ===== RARE =====
	{ id = "tide_trident", name = "Трезубец прилива", rarity = "Rare", style = "mass", icon = "🔱",
		kind = "melee", damage = 16, cooldown = 0.9, range = 10, color = { 40, 170, 200 },
		ability = { id = "tidal_wave", name = "Приливная волна", cooldown = 12, desc = "Волна сносит всех впереди (14 урона и отбрасывание)." } },
	{ id = "mirror_shield", name = "Зеркальный щит-клинок", rarity = "Rare", style = "defense", icon = "🪞",
		kind = "melee", damage = 12, cooldown = 0.8, range = 7, color = { 210, 230, 255 },
		ability = { id = "reflect", name = "Зеркало", cooldown = 15, desc = "3 с: получаете вдвое меньше урона, половина возвращается атакующему." } },
	{ id = "swarm_fork", name = "Вилка роя", rarity = "Rare", style = "summon", icon = "🐝",
		kind = "ranged", damage = 10, cooldown = 0.7, range = 40, projectile = "spark", color = { 250, 200, 40 },
		ability = { id = "bee_swarm", name = "Рой", cooldown = 11, desc = "Выпускает 3 самонаводящиеся пчелы в ближайших врагов." } },
	{ id = "gust_fan", name = "Веер урагана", rarity = "Rare", style = "mobility", icon = "🪭",
		kind = "melee", damage = 11, cooldown = 0.55, range = 8, color = { 180, 255, 220 },
		ability = { id = "updraft", name = "Восходящий поток", cooldown = 10, desc = "Подбрасывает вас вверх и вперёд, сдувает врагов, +35% скорости на 4 с." } },

	-- ===== EPIC =====
	{ id = "meteor_mace", name = "Метеоритная булава", rarity = "Epic", style = "heavy", icon = "☄️",
		kind = "melee", damage = 20, cooldown = 1.2, range = 8, color = { 255, 120, 40 },
		ability = { id = "meteor", name = "Метеорит", cooldown = 14, desc = "Через секунду в точку прицела падает метеорит (26 урона по области)." } },
	{ id = "shadow_kunai", name = "Теневые кунаи", rarity = "Epic", style = "mobility", icon = "🥷",
		kind = "ranged", damage = 9, cooldown = 0.4, range = 30, projectile = "kunai", color = { 60, 40, 90 },
		ability = { id = "shadow_step", name = "Теневой шаг", cooldown = 12, desc = "Телепорт за спину ближайшего врага и удар (20 урона)." } },
	{ id = "vine_whip", name = "Лиана-кнут", rarity = "Epic", style = "control", icon = "🌿",
		kind = "melee", damage = 13, cooldown = 0.8, range = 12, color = { 60, 170, 60 },
		ability = { id = "thorn_traps", name = "Шипастые ловушки", cooldown = 14, desc = "Ставит 3 ловушки: наступивший опутан на 1.5 с и получает 12 урона." } },
	{ id = "plasma_spoon", name = "Плазменная ложка-пушка", rarity = "Epic", style = "ranged", icon = "🔫",
		kind = "ranged", damage = 14, cooldown = 1.0, range = 55, projectile = "plasma", color = { 80, 255, 200 },
		ability = { id = "plasma_beam", name = "Плазменный луч", cooldown = 12, desc = "Луч пробивает всех на линии (22 урона, дальность 60)." } },

	-- ===== LEGENDARY =====
	{ id = "storm_halberd", name = "Алебарда бури", rarity = "Legendary", style = "mass", icon = "🌪️",
		kind = "melee", damage = 19, cooldown = 1.0, range = 10, color = { 120, 140, 255 },
		ability = { id = "storm_aura", name = "Буря", cooldown = 16, desc = "5 секунд вокруг вас бушует буря и бьёт всех врагов рядом." } },
	{ id = "phoenix_bow", name = "Лук феникса", rarity = "Legendary", style = "ranged", icon = "🏹",
		kind = "ranged", damage = 15, cooldown = 0.8, range = 60, projectile = "fire", color = { 255, 140, 30 },
		ability = { id = "fire_rain", name = "Огненный дождь", cooldown = 14, desc = "6 огненных стрел падают в область прицела и поджигают врагов." } },
	{ id = "golem_gauntlet", name = "Перчатка голема", rarity = "Legendary", style = "summon", icon = "🧱",
		kind = "melee", damage = 18, cooldown = 1.0, range = 7, color = { 140, 130, 120 },
		ability = { id = "summon_golem", name = "Каменный голем", cooldown = 20, desc = "Призывает голема-помощника на 10 с: он преследует и бьёт врагов." } },
	{ id = "chrono_cleaver", name = "Хроно-тесак", rarity = "Legendary", style = "defense", icon = "⌛",
		kind = "melee", damage = 18, cooldown = 0.85, range = 8, color = { 230, 200, 120 },
		ability = { id = "rewind", name = "Перемотка", cooldown = 18, desc = "Возвращает вас туда, где вы были 3 с назад, вместе со здоровьем." } },

	-- ===== MYTHICAL =====
	{ id = "void_scythe", name = "Коса Пустоты", rarity = "Mythical", style = "control", icon = "🌑",
		kind = "melee", damage = 21, cooldown = 1.0, range = 11, color = { 90, 30, 140 },
		ability = { id = "black_hole", name = "Чёрная дыра", cooldown = 18, desc = "3 секунды затягивает врагов в точку прицела и наносит урон." } },
	{ id = "mirage_rapier", name = "Рапира миража", rarity = "Mythical", style = "fast", icon = "🎭",
		kind = "melee", damage = 15, cooldown = 0.45, range = 8, color = { 255, 150, 230 },
		ability = { id = "mirage", name = "Мираж", cooldown = 16, desc = "Оставляет взрывающуюся копию, а вы становитесь невидимым и быстрым на 3 с." } },
	{ id = "dragon_wok", name = "Драконий вок", rarity = "Mythical", style = "mass", icon = "🐉",
		kind = "melee", damage = 16, cooldown = 0.9, range = 9, color = { 200, 40, 30 },
		ability = { id = "dragon_breath", name = "Дыхание дракона", cooldown = 15, desc = "2 секунды извергаете пламя конусом перед собой." } },
	{ id = "aegis_lantern", name = "Фонарь Эгиды", rarity = "Mythical", style = "defense", icon = "🏮",
		kind = "ranged", damage = 14, cooldown = 0.8, range = 35, projectile = "light", color = { 255, 240, 160 },
		ability = { id = "guardian_dome", name = "Купол-страж", cooldown = 20, desc = "Щит на 45 урона и лечение вам и другу рядом в течение 5 с." } },

	-- ===== SECRET =====
	{ id = "starfall_baton", name = "Жезл звездопада", rarity = "Secret", style = "magic", icon = "🌠",
		kind = "ranged", damage = 16, cooldown = 0.7, range = 50, projectile = "star", color = { 180, 220, 255 },
		ability = { id = "starfall", name = "Звездопад", cooldown = 18, desc = "10 звёзд падают в область прицела в течение 2 секунд." } },
	{ id = "abyss_glaive", name = "Глефа цепей Бездны", rarity = "Secret", style = "control", icon = "⛓️",
		kind = "melee", damage = 20, cooldown = 0.9, range = 11, color = { 40, 200, 180 },
		ability = { id = "soul_chains", name = "Цепи душ", cooldown = 18, desc = "Сковывает до 3 врагов рядом: 14 урона и опутывание на 1.2 с." } },
	{ id = "quantum_chopsticks", name = "Квантовые палочки", rarity = "Secret", style = "mobility", icon = "🥢",
		kind = "melee", damage = 14, cooldown = 0.35, range = 8, color = { 120, 255, 255 },
		ability = { id = "blink_barrage", name = "Квантовый шквал", cooldown = 16, desc = "Мгновенно бьёт до 3 врагов по очереди (15 урона) и возвращается." } },
	{ id = "royal_spatula", name = "Золотая лопатка Королей", rarity = "Secret", style = "mass", icon = "👑",
		kind = "melee", damage = 22, cooldown = 1.1, range = 9, color = { 255, 210, 60 },
		ability = { id = "midas_shockwave", name = "Ударная волна Мидаса", cooldown = 20, desc = "Золотая волна вокруг: 20 урона, отбрасывание и оглушение на 0.8 с." } },
}

Weapons.ById = {}
Weapons.ByRarity = {}
Weapons.Starter = {}
for _, w in ipairs(Weapons.List) do
	Weapons.ById[w.id] = w
	if w.starter then
		table.insert(Weapons.Starter, w)
	else
		Weapons.ByRarity[w.rarity] = Weapons.ByRarity[w.rarity] or {}
		table.insert(Weapons.ByRarity[w.rarity], w)
	end
end

Weapons.MaxInventory = 40

return Weapons
