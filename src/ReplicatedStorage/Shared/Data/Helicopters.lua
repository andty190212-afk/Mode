-- Helicopter models (bought with personal money after reaching 3 stars + helipad).
-- NOTE: no `script` references - also read by the place builder.
local Helicopters = {}

Helicopters.List = {
	{ id = "scout", name = "Скаут", price = 15000, stars = 3, speed = 70, climb = 28, turn = 1.4, accel = 0.9,
		body = { 235, 70, 60 }, trim = { 245, 245, 245 }, desc = "Лёгкий и манёвренный." },
	{ id = "cruiser", name = "Круизёр", price = 60000, stars = 4, speed = 95, climb = 34, turn = 1.15, accel = 0.8,
		body = { 40, 95, 175 }, trim = { 230, 230, 235 }, desc = "Быстрый и устойчивый." },
	{ id = "royal", name = "Роял", price = 220000, stars = 5, speed = 125, climb = 42, turn = 1.0, accel = 0.7,
		body = { 25, 25, 30 }, trim = { 212, 175, 55 }, desc = "Роскошный и самый быстрый." },
}

Helicopters.ById = {}
for i, h in ipairs(Helicopters.List) do
	h.order = i
	Helicopters.ById[h.id] = h
end

return Helicopters
