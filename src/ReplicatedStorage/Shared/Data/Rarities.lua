-- 7 rarities shared by creatures, special dishes and weapons
local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Secret" }

Rarities.Info = {
	Common = { rank = 1, name = "Обычное", color = { 190, 196, 206 }, glow = 0 },
	Uncommon = { rank = 2, name = "Необычное", color = { 90, 210, 110 }, glow = 0.2 },
	Rare = { rank = 3, name = "Редкое", color = { 70, 150, 255 }, glow = 0.4 },
	Epic = { rank = 4, name = "Эпическое", color = { 175, 90, 255 }, glow = 0.6 },
	Legendary = { rank = 5, name = "Легендарное", color = { 255, 180, 40 }, glow = 0.8 },
	Mythical = { rank = 6, name = "Мифическое", color = { 255, 70, 120 }, glow = 1 },
	Secret = { rank = 7, name = "Секретное", color = { 30, 255, 230 }, glow = 1 },
}

function Rarities.rank(r)
	local i = Rarities.Info[r]
	return i and i.rank or 0
end

function Rarities.valid(r)
	return Rarities.Info[r] ~= nil
end

return Rarities
