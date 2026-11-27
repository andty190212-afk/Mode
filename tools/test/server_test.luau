-- End-to-end server simulation on top of the mock engine.
-- Usage: lune run tools/test/server_test.luau
local Mock = require("./mock")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local passed, failed = 0, 0
local function check(cond, label, extra)
	if cond then
		passed += 1
		print("  ✔ " .. label)
	else
		failed += 1
		print("  ✘ " .. label .. (extra and ("  -> " .. tostring(extra)) or ""))
	end
end
local function section(name)
	print("\n== " .. name)
end

Mock.loadPlace("build/RestaurantIslandTycoon.rbxl")
local game = Mock.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

-- configure a developer product before the server starts (ids are 0 in the shipped config)
local Config = Mock.env.require(RS.Shared.Config)
Config.Products[1].id = 111111
Config.Products[5].id = 555555

section("Boot")
Mock.runScript(SSS.Main)
Mock.advance(3)
check(#Mock.errors == 0, "server booted without errors", Mock.errors[1])
local Services = {}
for _, m in ipairs(SSS.Services:GetChildren()) do
	Services[m.Name] = Mock.env.require(m)
end
local R = Services.RestaurantService
check(#R.Islands == 8, "8 islands registered", #R.Islands)

section("Join & claim")
local alice = Mock.addPlayer("Alice")
Mock.advance(2)
local res = Mock.request(alice, "ClaimIsland", {})
check(res.ok, "Alice claims an island", res.err)
local island = R.islandOf(alice)
check(island ~= nil and island.owner == alice, "Alice owns island " .. tostring(island and island.index))
check(island.building ~= nil and island.building.Name == "Restaurant", "tier-1 building spawned")
check(island.building:FindFirstChild("PassCounter", true) ~= nil, "building has PassCounter")
local res2 = Mock.request(alice, "ClaimIsland", {})
check(not res2.ok, "cannot own a second restaurant")
Mock.advance(1)
local state = Mock.lastPush(alice, "restaurant")
check(state ~= nil and state.stars == 1, "restaurant state replicated to owner")
check(Mock.lastPush(alice, "player") ~= nil, "player state replicated")
local tables = 0
for _ in pairs(island.guest.tables) do
	tables += 1
end
check(tables == 5, "starter tables registered as guest seats", tables)

section("Professions & invites")
local bob = Mock.addPlayer("Bob")
Mock.advance(2)
local inv = Mock.request(alice, "Invite", { userId = bob.UserId })
check(not inv.ok, "owner must choose a profession before inviting", inv.err)
check(Mock.request(alice, "ChooseRole", { role = "Cook" }).ok, "Alice chooses Cook")
inv = Mock.request(alice, "Invite", { userId = bob.UserId })
check(inv.ok, "Alice invites Bob", inv.err)
check(#R.invitesFor(bob) == 1, "Bob sees the invitation")
check(Mock.request(bob, "AcceptInvite", { island = island.index }).ok, "Bob accepts")
check(island.friend == bob, "Bob is the friend of the restaurant")
local carl = Mock.addPlayer("Carl")
Mock.advance(2)
check(not Mock.request(alice, "Invite", { userId = carl.UserId }).ok, "no third real player in a restaurant")
local r1 = Mock.request(bob, "ChooseRole", { role = "Cook" })
check(not r1.ok, "Bob cannot take the Cook job held by Alice", r1.err)
check(Mock.request(bob, "ChooseRole", { role = "Waiter" }).ok, "Bob becomes Waiter")
check(R.roleOf(bob) == "Waiter" and R.roleOf(alice) == "Cook", "roles assigned uniquely")
-- paid jobs without a pass (outside Studio)
Mock.isStudio = false
Services.MonetizationService.refreshPasses(carl)
local carlClaim = Mock.request(carl, "ClaimIsland", {})
check(carlClaim.ok, "Carl claims his own island")
local paid = Mock.request(carl, "ChooseRole", { role = "Director" })
check(not paid.ok, "Director locked without Game Pass (live server)", paid.err)
Mock.isStudio = true
Services.MonetizationService.refreshPasses(carl)

section("Guests, kitchen, waiter")
local wallet0 = Services.DataService.get(alice).data.money
local budget0 = island.rest.budget
Mock.advance(40)
local parties = 0
for _ in pairs(island.guest.parties) do
	parties += 1
end
check(parties > 0, "guests arrived", parties)
-- seat time
Mock.advance(10)
-- Bob takes orders on every waiting table
local function tablePrompts()
	local list = {}
	for _, rt in pairs(island.guest.tables) do
		table.insert(list, rt)
	end
	return list
end
local ordered = 0
for _, rt in ipairs(tablePrompts()) do
	if rt.party and rt.party.state == "order" then
		Mock.call(function()
			rt.prompt.Triggered:Fire(bob)
		end)
		Mock.advance(0.2)
		if rt.party and rt.party.state == "food" then
			ordered += 1
		end
	end
end
check(ordered > 0, "waiter took orders", ordered)
check(#island.kitchen.dishQueue > 0, "dishes queued in the kitchen", #island.kitchen.dishQueue)
-- Alice cooks everything in the queue via mini-games
local cooked = 0
for _ = 1, 8 do
	if #island.kitchen.dishQueue == 0 then
		break
	end
	local before = #Mock.inbox(alice)
	Mock.call(function()
		Services.KitchenService.startSession(island, alice, "dish")
	end)
	local push = Mock.lastPush(alice, "cook")
	if push and #Mock.inbox(alice) > before then
		Mock.advance(#push.steps * 1.5)
		local scores = {}
		for i = 1, #push.steps do
			scores[i] = 0.95
		end
		local fin = Mock.request(alice, "FinishCook", { token = push.token, scores = scores })
		if fin.ok then
			cooked += 1
		end
	end
end
check(cooked > 0, "cook finished dishes via mini-game results", cooked)
-- cheating: instant finish gives poor quality
if #island.kitchen.dishQueue > 0 then
	Mock.call(function()
		Services.KitchenService.startSession(island, alice, "dish")
	end)
	local push = Mock.lastPush(alice, "cook")
	local scores = {}
	for i = 1, #push.steps do
		scores[i] = 1
	end
	local fin = Mock.request(alice, "FinishCook", { token = push.token, scores = scores })
	check(fin.ok and fin.quality < 0.6, "instant (too fast) mini-game result is penalised", fin.quality)
end
local bad = Mock.request(alice, "FinishCook", { token = "forged", scores = { 1 } })
check(not bad.ok, "forged cooking token rejected")
Mock.advance(20) -- drinks from auto bar
-- Bob picks up and serves
local served = 0
for _ = 1, 10 do
	local pass = island.building:FindFirstChild("PassCounter", true)
	Mock.call(function()
		pass.PassPrompt.Triggered:Fire(bob)
	end)
	Mock.advance(0.2)
	for _, rt in ipairs(tablePrompts()) do
		if rt.party and rt.party.state == "food" then
			Mock.call(function()
				rt.prompt.Triggered:Fire(bob)
			end)
			Mock.advance(0.2)
		end
	end
	Mock.advance(3)
end
for _, rt in ipairs(tablePrompts()) do
	if rt.party and (rt.party.state == "eat" or rt.party.state == "pay") then
		served += 1
	end
end
Mock.advance(25)
local st = island.rest.stats
check(st.served > 0, "guests paid and left (served=" .. st.served .. ")", st.served)
check(island.rest.budget > budget0 - 1, "restaurant budget received sales", island.rest.budget - budget0)
check(#island.rest.reviews > 0, "guests left reviews", #island.rest.reviews)
local walletA = Services.DataService.get(alice).data.money
check(walletA > wallet0, "cook earned personal money", walletA - wallet0)
check(Services.DataService.get(bob).data.stats.tipsEarned > 0, "waiter earned tips", Services.DataService.get(bob).data.stats.tipsEarned)
-- clean dirty tables
local dirtyBefore = #Services.GuestService.dirtyTables(island)
for _, rt in ipairs(Services.GuestService.dirtyTables(island)) do
	Mock.call(function()
		rt.prompt.Triggered:Fire(bob)
	end)
end
Mock.advance(0.5)
check(dirtyBefore == 0 or #Services.GuestService.dirtyTables(island) < dirtyBefore, "waiter cleans tables", dirtyBefore)

print(("  [info] served=%d lost=%d revenue=%d tips=%d rep=%.1f sat=%.2f clean=%d reviews=%d aliceMoney=%d"):format(st.served, st.lost, st.revenue, st.tips, island.rest.reputation, st.satisfactionEma, island.rest.cleanliness, #island.rest.reviews, walletA))
for i = 1, math.min(3, #island.rest.reviews) do
	local rv = island.rest.reviews[i]
	print("  [review] " .. rv.s .. "★ " .. rv.txt .. " food=" .. rv.food .. " speed=" .. rv.speed)
end
section("Economy & shop")
local b0 = island.rest.budget
local buy = Mock.request(alice, "BuyIngredient", { id = "tomato", packs = 1 })
check(buy.ok and island.rest.budget < b0, "buy ingredients from the budget", buy.err)
check(not Mock.request(alice, "BuyIngredient", { id = "wagyu", packs = 1 }).ok, "premium ingredient locked at 1 star")
check(not Mock.request(alice, "BuyIngredient", { id = "tomato", packs = 999 }).ok, "invalid pack count rejected")
local dep = Mock.request(bob, "Deposit", { amount = 50 })
check(dep.ok, "friend can deposit", dep.err)
check(not Mock.request(bob, "Withdraw", { amount = 10 }).ok, "friend cannot withdraw (no stealing)")
local spendFriend = Mock.request(bob, "PlaceItem", { kind = "furniture", id = "plant_small", x = 14, z = -5, r = 0 })
check(not spendFriend.ok, "friend cannot spend budget without permission", spendFriend.err)
check(Mock.request(alice, "SetFriendSpend", { allow = true }).ok, "owner grants spending permission")
spendFriend = Mock.request(bob, "PlaceItem", { kind = "furniture", id = "plant_small", x = 14, z = -5, r = 0 })
check(spendFriend.ok, "friend can now buy furniture", spendFriend.err)
check(Mock.request(alice, "UpgradeEquipment", { id = "stove" }).ok == false, "equipment level capped by stars (stove already 1)")
check(Mock.request(alice, "UpgradeEquipment", { id = "coffee" }).ok, "buy coffee machine level 1")
check(not Mock.request(alice, "Deposit", { amount = -50 }).ok, "negative deposit rejected")
check(not Mock.request(alice, "SetMenu", { id = "burger", price = 99 }).ok == false, "set menu price (clamped)")
check(island.rest.menu.burger.price <= 2, "price multiplier clamped", island.rest.menu.burger.price)
Mock.request(alice, "SetMenu", { id = "burger", price = 1 })

section("Build mode")
island.rest.budget += 5000
local place = Mock.request(alice, "PlaceItem", { kind = "furniture", id = "lamp_floor", x = -10, z = -5, r = 0 })
check(place.ok, "place a floor lamp inside the dining room", place.err)
local outside = Mock.request(alice, "PlaceItem", { kind = "furniture", id = "table_wood_4", x = 0, z = 40, r = 0 })
check(not outside.ok, "cannot place furniture outside the restaurant", outside.err)
local overlap = Mock.request(alice, "PlaceItem", { kind = "furniture", id = "table_wood_4", x = -7, z = -12, r = 0 })
check(not overlap.ok, "cannot overlap furniture", overlap.err)
local door = Mock.request(alice, "PlaceItem", { kind = "furniture", id = "plant_small", x = 0, z = -4, r = 0 })
check(not door.ok, "cannot block the entrance", door.err)
local deco = Mock.request(alice, "PlaceItem", { kind = "decor", id = "palm_tree", x = 60, z = 60, r = 0 })
check(deco.ok, "place a palm on the island", deco.err)
local decoOut = Mock.request(alice, "PlaceItem", { kind = "decor", id = "palm_tree", x = 200, z = 0, r = 0 })
check(not decoOut.ok, "cannot place decor outside the island", decoOut.err)
local mv = Mock.request(alice, "MoveItem", { kind = "decor", uid = deco.uid, x = 62, z = 58, r = 90 })
check(mv.ok, "move decor", mv.err)
local rm = Mock.request(alice, "RemoveItem", { kind = "decor", uid = deco.uid })
check(rm.ok and rm.refund == 100, "remove decor with 50% refund", rm.refund)
local tcount = 0
for _ in pairs(island.guest.tables) do
	tcount += 1
end
check(tcount == 5, "tables registered for guests", tcount)

section("Star rating")
local promo = Mock.request(alice, "PromoteStar", {})
check(not promo.ok, "cannot buy a star without meeting requirements", promo.err)
-- simulate a well-run restaurant
local rest = island.rest
rest.stats.served = 60
rest.reputation = 70
rest.stats.satisfactionEma = 0.8
rest.cleanliness = 95
rest.budget = 20000
for _, id in ipairs({ "prep", "oven", "fridge", "bar", "stove" }) do
	rest.equipment[id] = 1
end
rest.equipment.freezer = 1
rest.equipment.dishwasher = 1
rest.equipment.coffee = 1
for i = 1, 6 do
	Mock.request(alice, "PlaceItem", { kind = "decor", id = "lamp_post", x = -60 + i * 4, z = 40, r = 0 })
end
local _, rows, can = Services.RatingService.evaluate(island)
local missing = {}
for _, row in ipairs(rows) do
	if not row.ok then
		table.insert(missing, row.key .. "=" .. tostring(row.have) .. "/" .. tostring(row.need))
	end
end
check(can, "requirements for 2 stars met", table.concat(missing, ", "))
promo = Mock.request(alice, "PromoteStar", {})
check(promo.ok and rest.stars == 2, "promoted to 2 stars", promo.err)
check(island.building:FindFirstChild("BuildingSign", true) ~= nil, "tier-2 building spawned")
tcount = 0
for _ in pairs(island.guest.tables) do
	tcount += 1
end
check(tcount == 5, "furniture re-registered after rebuild", tcount)
check(island.building:FindFirstChild("PassPrompt", true) ~= nil, "kitchen prompts rebound after rebuild")

local ds = Mock.request(alice, "DebugSetStars", { stars = 5 })
check(ds.ok and rest.stars == 5 and island.building:GetAttribute("Tier") == 5, "Studio: set restaurant to 5 stars instantly", ds.err)
ds = Mock.request(alice, "DebugSetStars", { stars = 2 })
check(ds.ok and rest.stars == 2 and island.building:GetAttribute("Tier") == 2, "Studio: back to 2 stars", ds.err)
Mock.isStudio = false
check(not Mock.request(alice, "DebugSetStars", { stars = 5 }).ok, "star selector disabled on live servers")
Mock.isStudio = true

section("Director & NPC staff")
check(Mock.request(alice, "ChooseRole", { role = "Director" }).ok, "Alice switches to Director (Studio pass grant)")
local hire = Mock.request(alice, "HireStaff", { role = "Cook" })
check(hire.ok, "hire NPC cook", hire.err)
check(Mock.request(alice, "HireStaff", { role = "Bartender" }).ok, "hire NPC bartender")
check(Mock.request(alice, "HireStaff", { role = "Waiter" }).ok, "hire NPC waiter (3 slots at 2 stars)")
check(not Mock.request(alice, "HireStaff", { role = "Waiter" }).ok, "staff limit by stars")
check(not Mock.request(bob, "HireStaff", { role = "Cook" }).ok, "only the director hires")
Mock.request(bob, "ChooseRole", { role = "Chef" })
check(R.roleOf(bob) == "Chef", "Bob becomes Chef (NPC sous-chef appears)")
check(island.staff.npcs.chef ~= nil, "chef NPC spawned")
local servedBefore = rest.stats.served
local npcDishes = rest.stats.dishesSold
rest.budget = 20000
Mock.advance(240)
print(("  [info] after 240s with NPCs: served +%d, dishes +%d, wages=%d, budget=%d, lost=%d"):format(rest.stats.served - servedBefore, rest.stats.dishesSold - npcDishes, rest.stats.wages, rest.budget, rest.stats.lost))
check(rest.stats.served > servedBefore, "NPC staff serve guests on their own", rest.stats.served - servedBefore)
check(rest.stats.dishesSold > npcDishes, "NPC cooks prepare dishes", rest.stats.dishesSold - npcDishes)
check(rest.stats.wages > 0, "staff receive wages from the budget", rest.stats.wages)
local avatarGuests, chefHats, bows, sitting = 0, 0, 0, 0
for _, m in ipairs(game.Workspace.NPCs:GetChildren()) do
	if m:FindFirstChild("HumanoidRootPart") and m:FindFirstChild("UpperTorso") then
		avatarGuests += 1
	end
	if m:FindFirstChild("ChefHat") then
		chefHats += 1
	end
	if m:FindFirstChild("BowL") then
		bows += 1
	end
end
check(avatarGuests > 0, "NPCs are R15 avatars (" .. avatarGuests .. ")")
check(chefHats >= 1, "NPC cooks wear a chef hat", chefHats)
check(bows >= 1, "NPC waiter/bartender wear a bow tie", bows)
local staffList = Services.StaffService.staffState(island)
check(#staffList >= 4, "staff state lists NPCs", #staffList)
local cookNpc = rest.staff[1]
cookNpc.xp = 100
rest.budget += 5000
local train = Mock.request(alice, "TrainStaff", { uid = cookNpc.uid })
check(train.ok and cookNpc.level == 2, "train NPC to level 2", train.err)
check(Mock.request(alice, "SetWage", { uid = cookNpc.uid, mult = 1.3 }).ok and cookNpc.wageMult == 1.3, "set wage")

section("Barrier & visiting")
check(Mock.request(alice, "SetBarrier", { on = true }).ok, "owner turns the barrier on")
check(not Mock.request(bob, "SetBarrier", { on = false }).ok, "friend cannot toggle the barrier")
local dave = Mock.addPlayer("Dave")
Mock.advance(2)
dave.Character.HumanoidRootPart.CFrame = CFrame.new(island.center + Vector3.new(10, 3, 10))
Mock.advance(1)
local dpos = dave.Character.HumanoidRootPart.Position
check((Vector3.new(dpos.X, 0, dpos.Z) - Vector3.new(island.center.X, 0, island.center.Z)).Magnitude > 150, "stranger pushed out by the barrier")
check(not Mock.request(dave, "Visit", { island = island.index }).ok, "cannot ferry to a closed island")
check(Mock.request(alice, "SetWhitelist", { userId = dave.UserId, allow = true }).ok, "owner allows Dave")
Services.DataService.get(dave).data.money = 500
check(Mock.request(dave, "Visit", { island = island.index }).ok, "whitelisted player can visit")
Mock.request(alice, "SetBarrier", { on = false })

section("Helicopters")
rest.stars = 3
Services.DataService.get(alice).data.money = 100000
check(not Mock.request(alice, "SpawnHelicopter", {}).ok, "no helicopter before buying")
check(Mock.request(alice, "BuyHelicopter", { id = "scout" }).ok, "buy Scout helicopter")
check(not Mock.request(alice, "BuyHelicopter", { id = "royal" }).ok, "Royal locked until 5 stars")
check(not Mock.request(alice, "SpawnHelicopter", {}).ok, "helipad required")
rest.budget += 10000
local pad = Mock.request(alice, "PlaceItem", { kind = "decor", id = "helipad", x = 70, z = -40, r = 0 })
check(pad.ok, "build a helipad", pad.err)
check(not Mock.request(alice, "PlaceItem", { kind = "decor", id = "helipad", x = -70, z = -40, r = 0 }).ok, "only one helipad")
local spawnHeli = Mock.request(alice, "SpawnHelicopter", {})
check(spawnHeli.ok, "spawn helicopter on the helipad", spawnHeli.err)
check(#game.Workspace.Helicopters:GetChildren() == 1, "helicopter model in the world")
rest.stars = 2

-- dump real replicated states for the client UI test
do
	local serde = require("@lune/serde")
	local fs = require("@lune/fs")
	Mock.advance(1)
	local dump = {
		player = Mock.lastPush(alice, "player"),
		restaurant = Mock.lastPush(alice, "restaurant"),
		world = Mock.lastPush(alice, "world"),
		friendPlayer = Mock.lastPush(bob, "player"),
		lobbyPlayer = Mock.lastPush(dave, "player"),
	}
	fs.writeFile("build/test_states.json", serde.encode("json", dump, true))
end

section("Robux purchases (ProcessReceipt)")
local MS = game:GetService("MarketplaceService")
local process_ = MS.ProcessReceipt
local m0 = Services.DataService.get(alice).data.money
local d1 = Mock.call(process_, { PlayerId = alice.UserId, ProductId = 111111, PurchaseId = "P-1", CurrencySpent = 25 })
local d2 = Mock.call(process_, { PlayerId = alice.UserId, ProductId = 111111, PurchaseId = "P-1", CurrencySpent = 25 })
local m1 = Services.DataService.get(alice).data.money
check(d1 == roblox.Enum.ProductPurchaseDecision.PurchaseGranted, "cash pack granted")
check(d2 == roblox.Enum.ProductPurchaseDecision.PurchaseGranted and m1 - m0 == Config.Products[1].amount, "duplicate receipt not granted twice", m1 - m0)
local d3 = Mock.call(process_, { PlayerId = alice.UserId, ProductId = 555555, PurchaseId = "P-2", CurrencySpent = 79 })
check(d3 == roblox.Enum.ProductPurchaseDecision.PurchaseGranted and Services.EconomyService.boostMult(alice) == 2, "x2 boost active")
local d4 = Mock.call(process_, { PlayerId = 999999, ProductId = 111111, PurchaseId = "P-3", CurrencySpent = 25 })
check(d4 == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "offline buyer -> NotProcessedYet")

section("Quests & rewards")
local daily = Mock.request(alice, "ClaimDaily", {})
check(daily.ok, "claim daily reward", daily.err)
check(not Mock.request(alice, "ClaimDaily", {}).ok, "daily reward only once per day")
local qs = Services.QuestService.questState(alice)
check(#qs.daily == 3 and #qs.weekly == 3, "3 daily + 3 weekly quests generated")
local pdata = Services.DataService.get(alice).data
pdata.quests.daily[1].progress = pdata.quests.daily[1].goal
check(Mock.request(alice, "ClaimQuest", { index = 1, weekly = false }).ok, "claim a completed quest")
check(pdata.achievements.first_dish ~= nil, "achievement 'first dish' unlocked")

section("Events, contest, leaderboard")
local E = Services.EventService
for _, id in ipairs({ "rush", "sale", "critic", "vip", "inspection", "special", "secret" }) do
	local okEv, errEv = pcall(E.trigger, island, id)
	check(okEv, "event '" .. id .. "' triggers", errEv)
end
check(E.guestMultiplier(island) >= 2, "rush hour doubles guests")
check(E.priceMultiplier(island) == 0.7, "supplier sale -30%")
Mock.advance(60)
check(#Mock.errors == 0, "events run without runtime errors", Mock.errors[1])
local budgetBefore = island.rest.budget
Mock.advance(900)
local contest = E.contestState()
check(contest.round >= 2, "contest round finished and restarted", contest.round)
check(contest.lastWinner ~= false, "contest winner recorded")
check(#contest.top.earnings > 0, "global earnings leaderboard populated", #contest.top.earnings)
check(#Mock.errors == 0, "15 minutes of full simulation without runtime errors", Mock.errors[1])

section("Leaving, saving, restoring")
local bobProfile = Services.DataService.get(bob)
Mock.removePlayer(bob)
Mock.advance(3)
check(island.friend == nil and R.roleOf(bob) == nil, "friend slot and job freed when friend leaves")
check(island.staff.npcs.chef == nil, "chef NPC removed with the Chef player")
local savedStars = rest.stars
local furnitureCount = #rest.furniture
Mock.removePlayer(alice)
Mock.advance(3)
check(island.owner == nil and island.building == nil, "island unloaded when owner leaves")
local stored = Mock.stores["RIT_PlayerData_v1"]["u_" .. alice.UserId]
check(stored and stored.data and stored.lock == nil, "data saved and session lock released")
check(stored.data.restaurant.stars == savedStars, "restaurant stars persisted", stored.data.restaurant.stars)
check(#stored.data.restaurant.furniture == furnitureCount, "furniture persisted")
check(stored.data.purchases["P-1"] ~= nil, "purchase ids persisted (anti-duplication)")
-- rejoin
local alice2 = Mock.addPlayer("Alice2")
Mock.stores["RIT_PlayerData_v1"]["u_" .. alice2.UserId] = stored
Mock.removePlayer(alice2)
Mock.advance(2)
-- simulate the same user id rejoining: copy the save to the new user id before join
local alice3
do
	local saveCopy = stored
	local nextId = alice2.UserId + 1
	Mock.stores["RIT_PlayerData_v1"]["u_" .. nextId] = saveCopy
	alice3 = Mock.addPlayer("Alice3")
end
Mock.advance(3)
local re = Mock.request(alice3, "ClaimIsland", {})
check(re.ok, "returning owner re-opens a restaurant", re.err)
local isl3 = R.islandOf(alice3)
check(isl3 and isl3.rest.stars == savedStars, "progress restored (stars)")
check(isl3 and #isl3.rest.furniture == furnitureCount, "progress restored (furniture)")
check(isl3 and isl3.building ~= nil, "restored building spawned")

section("Session lock")
local eve
do
	local nextId = alice3.UserId + 1
	Mock.stores["RIT_PlayerData_v1"]["u_" .. nextId] = { data = nil, lock = { job = "other-server", time = Mock.env.os.time() } }
	eve = Mock.addPlayer("Eve")
end
Mock.advance(40)
check(Mock.data(eve).kicked ~= nil, "player with data locked by another server is kicked safely")

section("Shutdown")
Mock.shutdown()
Mock.advance(5)
local s3 = Mock.stores["RIT_PlayerData_v1"]["u_" .. alice3.UserId]
check(s3 and s3.lock == nil, "BindToClose saved & released all profiles")

print(("\nRESULT: %d passed, %d failed, %d runtime errors, %d warnings"):format(passed, failed, #Mock.errors, #Mock.warnings))
for i, w in ipairs(Mock.warnings) do
	if i > 15 then
		break
	end
	print("  warn: " .. w)
end
if failed > 0 or #Mock.errors > 0 then
	process.exit(1)
end
