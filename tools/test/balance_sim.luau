-- Economy balance simulation using the real server code.
-- Usage: lune run tools/test/balance_sim.luau [minutes]
local Mock = require("./mock")
local process = require("@lune/process")

local MINUTES = tonumber(process.args[1]) or 12

Mock.loadPlace("build/RestaurantIslandTycoon.rbxl")
local game = Mock.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
Mock.runScript(SSS.Main)
Mock.advance(3)
local S = {}
for _, m in ipairs(SSS.Services:GetChildren()) do
	S[m.Name] = Mock.env.require(m)
end
local Recipes = Mock.env.require(RS.Shared.Data.Recipes)
local Stars = Mock.env.require(RS.Shared.Data.Stars)
local Furniture = Mock.env.require(RS.Shared.Data.Furniture)
local BuildRules = Mock.env.require(RS.Shared.BuildRules)
local Ingredients = Mock.env.require(RS.Shared.Data.Ingredients)

local function fillTables(island, stars)
	local rest = island.rest
	rest.furniture = {}
	local best = { [1] = "table_wood_4", [2] = "table_family_4", [3] = "booth_4", [4] = "table_marble_4", [5] = "table_royal_6" }
	local id = best[stars]
	local seats = 0
	local cap = Stars.Levels[stars].maxGuestsSeats
	for z = -6, -60, -1 do
		for x = -40, 40, 1 do
			if seats >= cap then
				break
			end
			local ok = BuildRules.validate(rest, "furniture", id, x, z, 0)
			if ok then
				table.insert(rest.furniture, { uid = rest.nextUid, id = id, x = x, z = z, r = 0 })
				rest.nextUid += 1
				seats += Furniture.ById[id].seatCount
			end
		end
	end
	return seats
end

local function stockEverything(rest)
	for _, ing in ipairs(Ingredients.List) do
		rest.inventory[ing.id] = 400
	end
end

local results = {}
local function scenario(label, stars, mode)
	local p = Mock.addPlayer(label:gsub("%W", ""))
	Mock.advance(2)
	local res = Mock.request(p, "ClaimIsland", {})
	assert(res.ok, res.err)
	local island = S.RestaurantService.islandOf(p)
	local rest = island.rest
	rest.stars = stars
	rest.reputation = 60 + stars * 4
	rest.budget = 1e7
	for k in pairs(rest.equipment) do
		rest.equipment[k] = stars
	end
	-- decorate to the expected beauty for this tier
	rest.decor = {}
	local seats = fillTables(island, stars)
	stockEverything(rest)
	S.RestaurantService.spawnBuilding(island)
	S.GuestService.clearIsland(island)
	S.GuestService.setupIsland(island)
	S.BuildService.spawnAll(island)
	S.KitchenService.clearIsland(island)
	S.KitchenService.setupIsland(island)
	S.StaffService.rebind(island)
	if mode == "npc" then
		Mock.request(p, "ChooseRole", { role = "Director" })
		local slots = Stars.Levels[stars].staffSlots
		local plan = { "Cook", "Waiter", "Bartender", "Cook", "Waiter", "Cook" }
		for i = 1, slots do
			Mock.request(p, "HireStaff", { role = plan[i] })
		end
		for _, m in ipairs(rest.staff) do
			m.level = math.min(5, stars)
		end
	else
		Mock.request(p, "ChooseRole", { role = "Cook" }) -- but nobody cooks -> automation only for waiter/bar
		S.RestaurantService.setRole(p, "Director", true)
	end
	local st = rest.stats
	local rev0, wages0, served0, lost0 = st.revenue, st.wages, st.served, st.lost
	local sold0 = st.dishesSold + st.drinksSold
	-- track ingredient cost of what is cooked
	local inv0 = table.clone(rest.inventory)
	Mock.advance(MINUTES * 60)
	local ingCost = 0
	for id, n in pairs(inv0) do
		local used = n - (rest.inventory[id] or 0)
		if used > 0 then
			ingCost += used * Ingredients.ById[id].price
		end
	end
	local revenue = (st.revenue - rev0) / MINUTES
	local wages = (st.wages - wages0) / MINUTES
	local guests = (st.served - served0) / MINUTES
	local lost = (st.lost - lost0) / MINUTES
	local net = revenue - wages - ingCost / MINUTES
	table.insert(results, string.format("%-22s ★%d seats=%2d | guests/min %.1f lost/min %.1f | revenue/min $%6.0f ingr/min $%5.0f wages/min $%4.0f | NET/min $%6.0f | sat %.2f",
		label, stars, seats, guests, lost, revenue, ingCost / MINUTES, wages, net, st.satisfactionEma))
	Mock.removePlayer(p)
	Mock.advance(3)
end

for stars = 1, 5 do
	scenario("auto(no staff) " .. stars, stars, "auto")
	scenario("director+NPC " .. stars, stars, "npc")
end
print("\n" .. table.concat(results, "\n"))
print(("errors: %d"):format(#Mock.errors))
