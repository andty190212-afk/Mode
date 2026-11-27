-- Guest appearances. 18 looks; which ones appear depends on the restaurant star rating
-- (casual at 1-2★, smart at 3★, suits & dresses at 4-5★) and on the guest type.
-- Colors are {r,g,b}. arms: "skin" (short sleeves) | "torso" (long sleeves) | {r,g,b}.
-- extras: tie, bow, glasses, sunglasses, backpack, camera, beanie, cap, skirt, necklace,
--         scarf, blazer (open jacket over shirt), shirtFront, flowerShirt, headband, watch, purse
-- NOTE: no `script` references (also used by preview tools).
local GuestLooks = {}

GuestLooks.List = {
	-- ===== повседневные (1-3★) =====
	{ id = "tee_jeans", name = "Футболка и джинсы", stars = { 1, 3 }, torso = { 52, 120, 220 }, arms = "skin", legs = { 40, 55, 95 }, hair = 1, extras = {} },
	{ id = "hoodie", name = "Худи", stars = { 1, 2 }, torso = { 120, 120, 125 }, arms = "torso", legs = { 30, 30, 35 }, hair = 4, extras = { "cap" } },
	{ id = "student", name = "Студент с рюкзаком", stars = { 1, 3 }, torso = { 240, 190, 50 }, arms = "skin", legs = { 60, 80, 130 }, hair = 1, extras = { "backpack", "glasses" }, types = { student = true } },
	{ id = "student_girl", name = "Студентка", stars = { 1, 3 }, torso = { 150, 100, 220 }, arms = "torso", legs = { 40, 45, 60 }, hair = 2, extras = { "backpack", "headband" }, types = { student = true } },
	{ id = "sporty", name = "Спортивный стиль", stars = { 1, 2 }, torso = { 220, 60, 60 }, arms = "torso", legs = { 30, 30, 40 }, hair = 4, extras = { "cap", "watch" } },
	{ id = "summer_dress", name = "Летнее платье", stars = { 1, 3 }, torso = { 250, 170, 190 }, arms = "skin", legs = "skin", hair = 2, extras = { "skirt", "sunglasses" }, skirt = { 250, 170, 190 } },
	{ id = "tourist", name = "Турист", stars = { 1, 4 }, torso = { 40, 170, 170 }, arms = "skin", legs = { 200, 180, 140 }, hair = 1, extras = { "flowerShirt", "camera", "sunglasses" }, types = { tourist = true } },
	{ id = "tourist_hat", name = "Турист в панаме", stars = { 2, 4 }, torso = { 245, 245, 240 }, arms = "skin", legs = { 90, 120, 80 }, hair = 1, extras = { "camera", "beanie" }, types = { tourist = true } },
	{ id = "family_mom", name = "Мама", stars = { 1, 3 }, torso = { 90, 170, 110 }, arms = "torso", legs = { 70, 70, 90 }, hair = 3, extras = { "purse" }, types = { family = true } },
	{ id = "family_dad", name = "Папа", stars = { 1, 3 }, torso = { 180, 60, 60 }, arms = "skin", legs = { 60, 70, 100 }, hair = 1, extras = { "watch" }, types = { family = true } },
	{ id = "winter", name = "Шарф и шапка", stars = { 1, 3 }, torso = { 70, 90, 150 }, arms = "torso", legs = { 40, 40, 45 }, hair = 2, extras = { "beanie", "scarf" } },
	-- ===== нарядные (3-4★) =====
	{ id = "smart_casual", name = "Рубашка и пиджак", stars = { 3, 5 }, torso = { 60, 80, 120 }, arms = "torso", legs = { 50, 50, 55 }, hair = 1, extras = { "blazer", "shirtFront", "watch" }, shirt = { 235, 240, 250 } },
	{ id = "cocktail_dress", name = "Коктейльное платье", stars = { 3, 5 }, torso = { 150, 20, 50 }, arms = "skin", legs = "skin", hair = 3, extras = { "skirt", "necklace", "purse" }, skirt = { 150, 20, 50 } },
	{ id = "polo_glasses", name = "Поло и очки", stars = { 2, 4 }, torso = { 245, 245, 245 }, arms = "skin", legs = { 120, 100, 70 }, hair = 1, extras = { "glasses", "watch" } },
	-- ===== костюмы и вечерние платья (4-5★) =====
	{ id = "black_suit", name = "Чёрный костюм", stars = { 4, 5 }, torso = { 25, 25, 30 }, arms = "torso", legs = { 25, 25, 30 }, hair = 1, extras = { "shirtFront", "tie", "watch" }, shirt = { 250, 250, 250 }, tie = { 150, 20, 40 } },
	{ id = "navy_suit", name = "Синий костюм", stars = { 4, 5 }, torso = { 30, 45, 90 }, arms = "torso", legs = { 30, 45, 90 }, hair = 4, extras = { "shirtFront", "tie" }, shirt = { 235, 240, 250 }, tie = { 200, 160, 50 } },
	{ id = "tuxedo", name = "Смокинг", stars = { 5, 5 }, torso = { 15, 15, 18 }, arms = "torso", legs = { 15, 15, 18 }, hair = 1, extras = { "shirtFront", "bow", "watch" }, shirt = { 255, 255, 255 } },
	{ id = "evening_gown", name = "Вечернее платье", stars = { 4, 5 }, torso = { 20, 20, 60 }, arms = "skin", legs = "skin", hair = 3, extras = { "skirt", "necklace", "purse" }, skirt = { 20, 20, 60 }, long = true },
	{ id = "white_suit", name = "Белый костюм", stars = { 5, 5 }, torso = { 240, 238, 230 }, arms = "torso", legs = { 240, 238, 230 }, hair = 2, extras = { "shirtFront", "tie", "sunglasses" }, shirt = { 30, 30, 35 }, tie = { 212, 175, 55 } },
}

GuestLooks.ById = {}
for _, l in ipairs(GuestLooks.List) do
	GuestLooks.ById[l.id] = l
end

-- Looks allowed for a restaurant star level (and preferred for a guest type)
function GuestLooks.pool(stars, guestType)
	local typed, any = {}, {}
	for _, l in ipairs(GuestLooks.List) do
		if stars >= l.stars[1] and stars <= l.stars[2] then
			table.insert(any, l)
			if l.types and l.types[guestType] then
				table.insert(typed, l)
			end
		end
	end
	if #typed > 0 then
		return typed, any
	end
	return any, any
end

return GuestLooks
