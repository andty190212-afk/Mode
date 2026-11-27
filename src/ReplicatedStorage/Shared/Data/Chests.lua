-- Creature chests. Odds in percent (sum = 100). The lab level and luck creatures
-- multiply the weights of Rare and better (see Chests.odds).
local Chests = {}

Chests.List = {
	{ id = "basic", name = "Обычный сундук", price = 4000, stars = 1, icon = "📦", color = { 170, 120, 70 },
		odds = { Common = 52, Uncommon = 26, Rare = 13, Epic = 6, Legendary = 2.2, Mythical = 0.6, Secret = 0.2 } },
	{ id = "golden", name = "Золотой сундук", price = 25000, stars = 3, icon = "🎁", color = { 255, 200, 60 },
		odds = { Common = 20, Uncommon = 30, Rare = 26, Epic = 15, Legendary = 6, Mythical = 2.2, Secret = 0.8 } },
	{ id = "royal", name = "Королевский сундук", price = 100000, stars = 5, icon = "👑", color = { 150, 70, 230 },
		odds = { Common = 0, Uncommon = 12, Rare = 30, Epic = 32, Legendary = 16.5, Mythical = 7, Secret = 2.5 } },
}

Chests.ById = {}
for _, c in ipairs(Chests.List) do
	Chests.ById[c.id] = c
end

-- (no require: this module is also read by the place builder)
local ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Secret" }
local Rarities = {
	Order = ORDER,
	rank = function(r)
		return table.find(ORDER, r) or 0
	end,
}

-- effective odds (percent) after luck bonus (luckPct, e.g. 15 = +15% to Rare+ weights)
function Chests.odds(chest, luckPct)
	local mult = 1 + (luckPct or 0) / 100
	local weights, total = {}, 0
	for _, r in ipairs(Rarities.Order) do
		local w = chest.odds[r] or 0
		if Rarities.rank(r) >= 3 then
			w *= mult
		end
		weights[r] = w
		total += w
	end
	local out = {}
	for _, r in ipairs(Rarities.Order) do
		out[r] = total > 0 and weights[r] / total * 100 or 0
	end
	return out
end

function Chests.roll(chest, luckPct, rng)
	local odds = Chests.odds(chest, luckPct)
	local x = (rng and rng:NextNumber() or math.random()) * 100
	local acc = 0
	local last
	for _, r in ipairs(Rarities.Order) do
		if odds[r] > 0 then
			acc += odds[r]
			last = r
			if x < acc then
				return r
			end
		end
	end
	return last
end

return Chests
