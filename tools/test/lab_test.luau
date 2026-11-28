-- Multiplayer simulation of the lab / creatures / dishes / weapons / theft / arena update.
-- Usage: lune run tools/test/lab_test.luau  (after tools/build_place.luau build)
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
		print("  ✘ " .. label .. (extra ~= nil and ("  -> " .. tostring(extra)) or ""))
	end
end
local function section(name)
	print("\n== " .. name)
end

Mock.loadPlace("build/RestaurantIslandTycoon.rbxl")
local game = Mock.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

Mock.runScript(SSS.Main)
Mock.advance(3)
local Services = {}
for _, m in ipairs(SSS.Services:GetChildren()) do
	Services[m.Name] = Mock.env.require(m)
end
local Lab, Combat, Rest, DataS = Services.LabService, Services.CombatService, Services.RestaurantService, Services.DataService
local Data = RS.Shared.Data
local Creatures = Mock.env.require(Data.Creatures)
local Weapons = Mock.env.require(Data.Weapons)
local LabData = Mock.env.require(Data.Lab)
local MapLayout = Mock.env.require(RS.Shared.MapLayout)

local function fxList(p, name)
	local out = {}
	for _, m in ipairs(Mock.inbox(p)) do
		if m.remote == "Fx" and m.args[1] == name then
			table.insert(out, m.args[2])
		end
	end
	return out
end
local function lastFx(p, name, kind)
	local l = fxList(p, name)
	for i = #l, 1, -1 do
		if not kind or l[i].kind == kind then
			return l[i]
		end
	end
	return nil
end
local function count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end
local function moveTo(p, pos)
	p.Character:PivotTo(CFrame.new(pos))
end
local function prof(p)
	return DataS.get(p)
end

section("World")
local labsFolder = Workspace.Map:FindFirstChild("Labs")
check(labsFolder ~= nil and #labsFolder:GetChildren() == 8, "8 labs on the map")
check(Workspace.Map:FindFirstChild("Arena") ~= nil, "central arena exists")
check(Workspace.Map:FindFirstChild("Bridges") ~= nil and #Workspace.Map.Bridges:GetChildren() == 8, "8 bridges to the arena")
local stands = 0
for _, isl in ipairs(Workspace.Map.Islands:GetChildren()) do
	local s = isl:FindFirstChild("WeaponStand")
	if s and s:FindFirstChild("starter_bat") and s:FindFirstChild("starter_sword") then
		stands += 1
	end
end
check(stands == 8, "free bat + sword stand on every island", stands)
local podsOk = true
for _, l in ipairs(labsFolder:GetChildren()) do
	if #l.Pods:GetChildren() ~= 12 or not l:FindFirstChild("Plate") or not l.Pods.Pod1:FindFirstChild("StealPrompt") then
		podsOk = false
	end
end
check(podsOk, "every lab has 12 pods with steal prompts and a close plate")
check(#RS.Assets.Creatures:GetChildren() == #Creatures.List + 1, "a model for every creature + egg")
check(#RS.Assets.Weapons:GetChildren() == #Weapons.List, "a model for every weapon")

section("Players")
local alice = Mock.addPlayer("Alice")
local bob = Mock.addPlayer("Bob")
local carol = Mock.addPlayer("Carol")
Mock.advance(2)
check(Mock.request(alice, "ClaimIsland", { index = 1 }).ok, "Alice claims island 1")
check(Mock.request(bob, "ClaimIsland", { index = 2 }).ok, "Bob claims island 2")
Mock.advance(2)
local aliceIsland = Rest.islandOf(alice)
do
	local w1 = Workspace.Map.Islands.Island1:FindFirstChild("BarrierWalls")
	local w5 = Workspace.Map.Islands.Island5:FindFirstChild("BarrierWalls")
	local solid1 = w1 and w1:GetChildren()[1].CanCollide
	local solid5 = w5 and w5:GetChildren()[1].CanCollide
	check(w1 ~= nil and #w1:GetChildren() >= 96, "solid barrier wall around the island")
	check(solid1 == true and solid5 == false, "wall is solid on owned islands, open on free ones")
	local gap = 0
	for _, p in ipairs(w1:GetChildren()) do
		local rel = Rest.islandCFrame(1):PointToObjectSpace(p.Position)
		if rel.Z < 0 and math.abs(rel.X) < 8 then
			gap += 1
		end
	end
	check(gap == 4, "the only gap is at the lab walkway (wall below and above it)", gap)
end
check(Lab.Labs[1] == nil, "no lab below 3★")
check(labsFolder.Lab1.Pods.Pod1.Transparency == 1 and labsFolder.Lab1.Floor.Transparency < 1, "lab building hidden, platform/bridge stays")
local lockGui = labsFolder.Lab1.LockSign:FindFirstChildWhichIsA("SurfaceGui")
check(lockGui and lockGui.Enabled, "'lab appears at 3★' sign shown")
check(not Mock.request(alice, "BuyChest", { chest = "basic" }).ok, "no chests below 3★")
aliceIsland.rest.stars = 3
Rest.islandOf(bob).rest.stars = 3
Mock.advance(2)
check(Lab.Labs[1] ~= nil and Lab.Labs[2] ~= nil, "lab appears when the restaurant reaches 3★")
check(labsFolder.Lab1.Pods.Pod1.Transparency == 0, "lab building visible at 3★ (pods opaque again)")
do
	local wall, capsule
	for _, d in ipairs(labsFolder.Lab1:GetChildren()) do
		if d.Name == "Wall" then
			wall = d
		elseif d.Name == "Capsule" then
			capsule = d
		end
	end
	check(wall and wall.Transparency == 0 and wall.CanCollide, "walls restored exactly (opaque + solid)")
	check(capsule and math.abs(capsule.Transparency - 0.82) < 0.01, "glass capsules restored to their original transparency")
	-- hide/show again: originals must survive repeated toggles
	Lab.setLabVisible(1, false)
	Lab.setLabVisible(1, true)
	check(wall.Transparency == 0 and math.abs(capsule.Transparency - 0.82) < 0.01, "repeated hide/show keeps the original look")
end
local aliceLab = Lab.Labs[1]
check(aliceLab ~= nil and aliceLab.state == "closed", "Alice's lab is set up and protected")
check(labsFolder.Lab1:GetAttribute("LabOwner") == "Alice", "lab shows its owner")

section("Chest shop")
local pa = prof(alice)
pa.data.money = 3000
local r = Mock.request(alice, "BuyChest", { chest = "basic" })
check(not r.ok, "can't buy a 4000 chest with 3000", r.err)
check(pa.data.money == 3000, "money untouched after a failed purchase")
pa.data.money = 10000
r = Mock.request(alice, "BuyChest", { chest = "basic" })
check(r.ok and r.uid ~= nil, "chest bought", r.err)
check(pa.data.money == 6000, "exactly 4000 charged by the server", pa.data.money)
check(count(pa.data.creatures) == 1, "one purchase = one creature")
local r2 = Mock.request(alice, "BuyChest", { chest = "basic" })
check(not r2.ok and count(pa.data.creatures) == 1 and pa.data.money == 6000, "instant double-click gives nothing extra", r2.err)
check(not Mock.request(alice, "BuyChest", { chest = "royal" }).ok, "royal chest locked below 5★")
check(not Mock.request(carol, "BuyChest", { chest = "basic" }).ok, "players without a restaurant can't buy")
-- odds sanity: 20000 rolls
local Chests = Mock.env.require(Data.Chests)
local hist = {}
local rng = roblox.Random and nil
for _ = 1, 20000 do
	local rr = Chests.roll(Chests.ById.basic, 0)
	hist[rr] = (hist[rr] or 0) + 1
end
check(hist.Common > hist.Uncommon and hist.Uncommon > hist.Rare and hist.Rare > hist.Epic and hist.Epic > (hist.Legendary or 0), "rarer = less likely (Common " .. hist.Common .. ", Epic " .. (hist.Epic or 0) .. ")")

section("Growing")
local uid = r.uid
local rec = pa.data.creatures[uid]
check(Mock.request(alice, "PlaceCreature", { uid = uid }).ok, "creature placed into a pod")
check(rec.pod == 1 and aliceLab.pods[1] ~= nil, "pod 1 occupied")
check(labsFolder.Lab1:FindFirstChild("Creature") ~= nil, "creature model visible in the lab")
do
	local cm = labsFolder.Lab1:FindFirstChild("Creature")
	local pod = labsFolder.Lab1.Pods.Pod1
	local cp = cm:GetPivot().Position
	local flatDist = Vector3.new(cp.X - pod.Position.X, 0, cp.Z - pod.Position.Z).Magnitude
	check(flatDist < 0.5 and cp.Y > pod.Position.Y, "creature stands in the middle of its capsule (offset " .. string.format("%.2f", flatDist) .. ")")
end
check(not Mock.request(bob, "PlaceCreature", { uid = uid }).ok, "Bob can't place Alice's creature")
local def = Creatures.ById[rec.id]
Mock.advance(5)
check(rec.grow > 0 and rec.grow < Creatures.stats(def).grow, "growth timer runs", rec.grow)
pa.data.money = 1e7
check(Mock.request(alice, "SpeedUpCreature", { uid = uid }).ok, "speed-up paid")
check(rec.grow >= Creatures.stats(def).grow, "creature is adult")
local bank0 = pa.data.lab.bank
Mock.advance(12)
check(pa.data.lab.bank > bank0, "adult creature earns money into the lab bank")
local m0 = pa.data.money
check(Mock.request(alice, "CollectLab").ok and pa.data.money > m0, "income collected")
check(Mock.request(alice, "UpgradeCreature", { uid = uid }).ok and rec.lvl == 2, "creature level up")
-- special dish
rec.dish = Creatures.stats(def).dishTime - 0.5
Mock.advance(2)
check((pa.data.dishes[def.dish.id] or 0) == 1, "creature produced its special dish " .. def.dish.name)

section("Dish -> weapon of the SAME rarity")
local er = Mock.request(alice, "EatDish", { dish = def.dish.id })
check(er.ok and er.rarity == def.rarity, "eaten: got a " .. tostring(er.rarity) .. " weapon (creature " .. def.rarity .. ")", er.err)
check(pa.data.dishes[def.dish.id] == nil, "dish removed from inventory")
check(not Mock.request(alice, "EatDish", { dish = def.dish.id }).ok, "the same dish can't be eaten twice")
check(count(pa.data.weapons) == 1, "exactly one weapon granted")
local allMatch, total = true, 0
for _, c in ipairs(Creatures.List) do
	for _ = 1, 6 do
		pa.data.dishes[c.dish.id] = 1
		Mock.advance(1.3)
		local res = Mock.request(alice, "EatDish", { dish = c.dish.id })
		total += 1
		local w = res.ok and Weapons.ById[res.id]
		if not w or w.rarity ~= c.rarity or w.starter then
			allMatch = false
			print("    mismatch", c.id, c.rarity, res.id, res.err)
		end
		if count(pa.data.weapons) >= Weapons.MaxInventory - 1 then
			for wuid in pairs(pa.data.weapons) do
				pa.data.weapons[wuid] = nil
			end
		end
	end
end
check(allMatch, total .. " dishes of all 7 rarities -> always a weapon of exactly that rarity")
check(not Mock.request(alice, "EatDish", { dish = "nope" }).ok, "fake dish rejected")
do
	local before = 0
	for _, n in pairs(pa.data.dishes) do
		before += n
	end
	local g = Mock.request(alice, "DevGiveDishes", { rarity = "all" })
	local after = 0
	for _, n in pairs(pa.data.dishes) do
		after += n
	end
	check(g.ok and after == before + 7, "creator button: one dish of every rarity instantly", g.err)
	check(Mock.request(alice, "DevGiveDishes", { rarity = "Secret" }).ok, "creator button: dish of a chosen rarity")
end

section("Security cycle: opens every 2 minutes, stays open until the plate")
local plate = labsFolder.Lab1.Plate
if aliceLab.state ~= "closed" then
	-- the cycle already ran during the dish tests: close it first
	moveTo(alice, plate.Position + Vector3.new(0, 3, 0))
	Mock.advance(1)
	moveTo(alice, Vector3.new(0, 200, 0))
end
check(aliceLab.state == "closed", "lab is protected")
aliceLab.cycleRemaining = 3
Mock.advance(4)
check(aliceLab.state == "open", "lab opened automatically")
check(lastFx(alice, "labAlarm", "open") ~= nil, "owner got the alarm")
Mock.advance(LabData.OpenWarnTime + 3)
check(aliceLab.state == "danger", "time is up -> lab is STILL open (danger)")
check(lastFx(alice, "labAlarm", "danger") ~= nil, "owner warned: still open")
Mock.advance(150)
check(aliceLab.state == "danger", "a following cycle does not close it by itself")
moveTo(bob, plate.Position + Vector3.new(0, 3, 0))
Mock.advance(1)
check(aliceLab.state ~= "closed", "a stranger on the plate can't close it")
moveTo(bob, Vector3.new(0, 200, 0))
check(not Mock.request(alice, "LabSettings", { access = "private" }).ok == false, "owner may change settings")
moveTo(alice, plate.Position + Vector3.new(0, 3, 0))
Mock.advance(1)
check(aliceLab.state == "closed", "owner stepped on the plate -> lab protected")
check(lastFx(alice, "labAlarm", "closed") ~= nil, "'LAB PROTECTED' notification")
check(math.abs(aliceLab.cycleRemaining - LabData.ClosedTime) < 2, "next cycle scheduled in 2 minutes")
moveTo(alice, Vector3.new(0, 200, 0))
Mock.request(alice, "LabSettings", { access = "open" })

section("Theft")
local pod1 = labsFolder.Lab1.Pods.Pod1
local prompt = pod1.StealPrompt
check(prompt.Enabled == false, "steal prompt disabled while protected")
prompt.Triggered:Fire(bob)
check(not Lab.isCarrying(bob), "can't steal from a protected lab")
aliceLab.cycleRemaining = 1
Mock.advance(2)
check(aliceLab.state == "open" and prompt.Enabled, "lab open -> steal prompt enabled")
moveTo(bob, pod1.Position + Vector3.new(3, 2, 0))
prompt.Triggered:Fire(alice)
check(not Lab.isCarrying(alice), "owner can't steal own creature")
prompt.Triggered:Fire(bob)
check(Lab.isCarrying(bob), "Bob is carrying Alice's creature")
check(bob.Character:FindFirstChild("CarriedCreature") ~= nil, "creature is in the thief's hands")
check(bob.Character:FindFirstChild("StolenTag", true) ~= nil, "thief marker above Bob")
check(lastFx(alice, "theft", "alarm") ~= nil, "Alice: 'YOUR CREATURE IS BEING STOLEN!'")
local normalOutside = 18 * 2.5
local thiefSpeed = bob.Character.Humanoid.WalkSpeed
check(thiefSpeed < normalOutside and thiefSpeed >= normalOutside * 0.75, "thief is a bit slower than normal (" .. thiefSpeed .. " vs " .. normalOutside .. ")", thiefSpeed)
check(pa.data.creatures[uid] ~= nil, "ownership does not change while carried")

section("Barrier: through the open lab only; a closed lab is sealed")
do
	local center = aliceIsland.center
	local function dist(p)
		local pos = p.Character.HumanoidRootPart.Position
		return (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
	end
	-- Carol (stranger) jumps straight onto the island -> sent back to the lab
	moveTo(carol, center + Vector3.new(20, 4, 20))
	Mock.advance(0.6)
	check(dist(carol) > 185, "stranger landing on the island is sent back to the lab entrance")
	-- through the OPEN lab: inside the lab, then onto the island
	local wasState = aliceLab.state
	aliceLab.state = "open"
	local interior = labsFolder.Lab1.Interior
	moveTo(carol, interior.Position)
	Mock.advance(0.6)
	moveTo(carol, center + Vector3.new(0, 4, -150))
	Mock.advance(0.6)
	check(dist(carol) < 185, "stranger who walked through the open lab may enter the island")
	-- the owner closes the lab: strangers can't be inside it at all
	moveTo(carol, interior.Position)
	aliceLab.state = "closed"
	Mock.advance(0.6)
	local cpos = carol.Character.HumanoidRootPart.Position
	local rel = interior.CFrame:PointToObjectSpace(cpos)
	check(math.abs(rel.X) > interior.Size.X / 2 or math.abs(rel.Z) > interior.Size.Z / 2, "a closed lab pushes strangers out (can't even enter)")
	aliceLab.state = wasState
	moveTo(carol, Vector3.new(0, 200, 0))
	Mock.advance(0.5)
end

section("Owner hits the thief -> creature returns")
local bat = labsFolder.Parent.Islands.Island1.WeaponStand.starter_bat.TakePrompt
moveTo(alice, bob.Character.HumanoidRootPart.Position + Vector3.new(0, 0, 3))
bat.Triggered:Fire(alice)
check(pa.data.equipped ~= "", "Alice took the free bat")
local hpBefore = bob.Character.Humanoid.Health
local attackRemote = RS.Remotes.Action
local function attack(p, target)
	local dir = (target.Character.HumanoidRootPart.Position - p.Character.HumanoidRootPart.Position)
	p.Character:PivotTo(CFrame.lookAt(p.Character.HumanoidRootPart.Position, p.Character.HumanoidRootPart.Position + Vector3.new(dir.X, 0, dir.Z)))
	attackRemote.OnServerEvent:Fire(p, "Attack", { dir = dir.Unit })
end
attack(alice, bob)
Mock.advance(0.5)
check(not Lab.isCarrying(bob), "server-confirmed hit -> creature dropped")
check(bob.Character.Humanoid.Health < hpBefore, "the hit dealt damage")
check(aliceLab.pods[1] and aliceLab.pods[1].carried == nil, "creature is back in its pod")
check(pa.data.pvp.defends == 1 and prof(bob).data.pvp.caught == 1, "defence/caught stats saved")
check(lastFx(alice, "theft", "returned") ~= nil and lastFx(bob, "theft", "caught") ~= nil, "both got notifications")
-- random players can't hurt each other outside the arena
moveTo(carol, alice.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0))
local cHp = carol.Character.Humanoid.Health
Mock.advance(1.2)
attack(alice, carol)
Mock.advance(0.5)
check(carol.Character.Humanoid.Health < cHp, "PvP works outside the arena too (everywhere)")

section("Steal cooldown, thief leaves, delivery")
moveTo(bob, pod1.Position + Vector3.new(3, 2, 0))
prompt.Triggered:Fire(bob)
check(not Lab.isCarrying(bob), "steal cooldown blocks an instant retry")
Mock.advance(LabData.StealCooldown + 1)
if aliceLab.state == "closed" then
	aliceLab.cycleRemaining = 0.5
	Mock.advance(1)
end
moveTo(bob, pod1.Position + Vector3.new(3, 2, 0))
prompt.Triggered:Fire(bob)
check(Lab.isCarrying(bob), "Bob steals again")
-- teleport cheat -> creature returns
moveTo(bob, Vector3.new(0, 300, 0))
Mock.advance(0.6)
check(not Lab.isCarrying(bob) and aliceLab.pods[1] and aliceLab.pods[1].carried == nil, "teleporting with loot -> creature returns home")
Mock.advance(LabData.StealCooldown + 1)
moveTo(bob, pod1.Position + Vector3.new(3, 2, 0))
prompt.Triggered:Fire(bob)
check(Lab.isCarrying(bob), "Bob steals a third time")
-- walk (in legal steps) to his own lab platform
local x2, y2, z2 = MapLayout.labCenter(2)
local target = Vector3.new(x2, y2 + 3, z2)
local pos = bob.Character.HumanoidRootPart.Position
local steps = 0
while (target - pos).Magnitude > 20 and steps < 400 and Lab.isCarrying(bob) do
	local d = target - pos
	pos = pos + d.Unit * math.min(30, d.Magnitude)
	moveTo(bob, pos)
	Mock.advance(0.26)
	steps += 1
end
moveTo(bob, target)
Mock.advance(0.6)
local pb = prof(bob)
check(not Lab.isCarrying(bob), "delivered at his own lab")
check(pa.data.creatures[uid] == nil, "creature removed from Alice")
local bobHas = 0
for _, c in pairs(pb.data.creatures) do
	if c.id == rec.id then
		bobHas += 1
	end
end
check(bobHas == 1, "creature now belongs to Bob (exactly one copy)")
check(pb.data.pvp.steals == 1 and pa.data.pvp.stolenFrom == 1, "theft stats saved")
check(lastFx(alice, "theft", "stolen") ~= nil, "Alice notified about the loss")

section("Speed: 2.5x outside the cafe, normal inside")
moveTo(alice, Vector3.new(0, 200, 0))
Mock.advance(0.6)
check(alice.Character.Humanoid.WalkSpeed == 45, "outside the cafe: 45 (18 x 2.5)", alice.Character.Humanoid.WalkSpeed)
local door = Rest.buildingCFrame(1) * CFrame.new(0, 3, -8)
moveTo(alice, door.Position)
Mock.advance(0.6)
check(alice.Character.Humanoid.WalkSpeed == 18, "inside the cafe: normal 18", alice.Character.Humanoid.WalkSpeed)
moveTo(alice, Vector3.new(0, 200, 0))
Mock.advance(0.6)
check(alice.Character.Humanoid.WalkSpeed == 45, "back outside: fast again")

section("Thief disconnects / owner disconnects while carrying")
pa.data.money = 1e7
local r3 = Mock.request(alice, "BuyChest", { chest = "basic" })
Mock.advance(2)
Mock.request(alice, "PlaceCreature", { uid = r3.uid })
local slot = pa.data.creatures[r3.uid].pod
local p2 = labsFolder.Lab1.Pods["Pod" .. slot]
aliceLab.immuneUntil = 0
if aliceLab.state == "closed" then
	aliceLab.cycleRemaining = 0.5
	Mock.advance(1)
end
local dave = Mock.addPlayer("Dave")
Mock.advance(2)
check(Mock.request(dave, "ClaimIsland", { index = 3 }).ok, "Dave claims island 3")
Rest.islandOf(dave).rest.stars = 3
Mock.advance(2)
moveTo(dave, p2.Position + Vector3.new(3, 2, 0))
p2.StealPrompt.Triggered:Fire(dave)
check(Lab.isCarrying(dave), "Dave carries Alice's new creature")
Mock.removePlayer(dave)
Mock.advance(1)
check(pa.data.creatures[r3.uid] ~= nil and aliceLab.pods[slot] and aliceLab.pods[slot].carried == nil, "thief left the game -> creature returned to the owner")
-- owner leaves while Bob carries
Mock.advance(LabData.StealCooldown + 1)
aliceLab.immuneUntil = 0
if aliceLab.state == "closed" then
	aliceLab.cycleRemaining = 0.5
	Mock.advance(1)
end
moveTo(bob, p2.Position + Vector3.new(3, 2, 0))
p2.StealPrompt.Triggered:Fire(bob)
check(Lab.isCarrying(bob), "Bob carries again")
local savedOpen = aliceLab.state ~= "closed"
Mock.removePlayer(alice)
Mock.advance(2)
check(not Lab.isCarrying(bob), "owner left -> theft cancelled")
check(Lab.Labs[1] == nil, "Alice's lab unloaded")

section("Rejoin keeps the cycle state")
local alice2 = Mock.addPlayer("Alice")
alice2.UserId = alice.UserId
Mock.advance(3)
-- (the mock gives a new UserId; reuse the saved profile through the same key)
local ok2 = Mock.request(alice2, "ClaimIsland", { index = 1 })
Mock.advance(2)
local pa2 = prof(alice2)
if pa2 and pa2.data.creatures[r3.uid] then
	check(true, "creature still in Alice's saved data after rejoin")
	check((Lab.Labs[1].state ~= "closed") == savedOpen, "lab open/closed state restored, not reset")
else
	check(pa.data.creatures[r3.uid] ~= nil, "creature kept in Alice's profile when she left")
	check(pa.data.lab.open == savedOpen, "cycle state saved on leave (open=" .. tostring(savedOpen) .. ")")
end

section("Arena PvP")
local carolArena = Mock.request(carol, "JoinArena", {})
check(carolArena.ok, "Carol joins the arena")
check(carol.Character:FindFirstChildOfClass("ForceField") ~= nil, "spawn protection on arrival")
Mock.request(bob, "JoinArena", {})
local swordPrompt = Workspace.Map.Islands.Island2.WeaponStand.starter_sword.TakePrompt
swordPrompt.Triggered:Fire(bob)
check(pb.data.equipped ~= "", "Bob took the free sword")
do
	-- weapons are real Roblox Tools: hotbar inventory + standard tool animations
	local bp = bob:FindFirstChildOfClass("Backpack")
	local inHand = bob.Character:FindFirstChildOfClass("Tool")
	check(inHand ~= nil and inHand:GetAttribute("WeaponId") == "starter_sword", "the sword is a Tool in Bob's hand")
	check(inHand and inHand:FindFirstChild("Handle") ~= nil and inHand:FindFirstChild("Model") ~= nil, "tool has a Handle and the weapon model")
	local tools = 0
	for _, where in ipairs({ bp, bob.Character }) do
		for _, t in ipairs(where and where:GetChildren() or {}) do
			if t.ClassName == "Tool" then
				tools += 1
			end
		end
	end
	local owned = 0
	for _ in pairs(pb.data.weapons) do
		owned += 1
	end
	check(tools == owned, "inventory hotbar has one tool per owned weapon (" .. tools .. "/" .. owned .. ")")
	local gear = bob:FindFirstChild("StarterGear")
	local gearTools = 0
	for _, t in ipairs(gear and gear:GetChildren() or {}) do
		if t.ClassName == "Tool" then
			gearTools += 1
		end
	end
	check(gearTools == owned, "weapons also stored in StarterGear (survive respawns)")
	moveTo(bob, Vector3.new(0, MapLayout.BridgeY + 3, 40))
	Mock.advance(1.2)
	attack(bob, carol)
	Mock.advance(0.05)
	local anim = inHand and inHand:FindFirstChild("toolanim")
	check(anim ~= nil and (anim.Value == "Slash" or anim.Value == "Lunge"), "attack plays the standard tool animation", anim and anim.Value)
	Mock.advance(1)
end
Mock.advance(0.5)
moveTo(bob, Vector3.new(0, MapLayout.BridgeY + 3, 0))
moveTo(carol, Vector3.new(0, MapLayout.BridgeY + 3, 3))
local hp0 = carol.Character.Humanoid.Health
attack(bob, carol)
Mock.advance(0.3)
check(carol.Character.Humanoid.Health == hp0, "spawn protection blocks damage")
Mock.advance(7)
local hp1 = carol.Character.Humanoid.Health
attack(bob, carol)
Mock.advance(0.3)
check(carol.Character.Humanoid.Health < hp1, "PvP damage inside the arena", carol.Character.Humanoid.Health)
attack(bob, carol)
Mock.advance(0.05)
local hpCd = carol.Character.Humanoid.Health
attack(bob, carol)
Mock.advance(0.05)
check(carol.Character.Humanoid.Health == hpCd, "attack cooldown enforced by the server")
for _ = 1, 30 do
	Mock.advance(1)
	attack(bob, carol)
	if carol.Character.Humanoid.Health <= 0 then
		break
	end
end
Mock.advance(0.5)
check(pb.data.pvp.kills >= 1 and pb.data.pvp.arenaKills >= 1, "arena kill counted", pb.data.pvp.kills)
check(prof(carol).data.pvp.deaths >= 1, "arena death counted")
Mock.advance(4)
local board = Mock.lastPush(bob, "arena")
check(board and board.top and board.top[1] and board.top[1].name == "Bob", "arena board shows the leader")

section("Every weapon ability runs on the server")
local errs0 = #Mock.errors
local dummy = Mock.addPlayer("Dummy")
Mock.advance(2)
carol.Character.Humanoid.Health = 100
local okAll = true
for _, w in ipairs(Weapons.List) do
	pb.data.weaponSeq += 1
	local wuid = tostring(pb.data.weaponSeq)
	pb.data.weapons[wuid] = { id = w.id }
	Mock.request(bob, "EquipWeapon", { uid = wuid })
	moveTo(bob, Vector3.new(0, MapLayout.BridgeY + 3, 0))
	moveTo(dummy, Vector3.new(0, MapLayout.BridgeY + 3, -6))
	dummy.Character.Humanoid.Health = 100
	local rr = Mock.request(bob, "Ability", { dir = Vector3.new(0, 0, -1), point = Vector3.new(0, MapLayout.BridgeY, -10) })
	local again = Mock.request(bob, "Ability", { dir = Vector3.new(0, 0, -1) })
	if not rr.ok or again.ok then
		okAll = false
		print("    ability problem", w.id, rr.err, again.ok)
	end
	Mock.advance(3.5)
	Combat.resetCooldowns(bob)
	for key in pairs(prof(bob).data.weapons) do
		if key ~= wuid then
			pb.data.weapons[key] = nil
		end
	end
	-- reset the ability cooldown for the next weapon
end
check(okAll, "all " .. #Weapons.List .. " abilities activate once and respect their cooldown")
check(#Mock.errors == errs0, "no runtime errors from abilities", Mock.errors[errs0 + 1])

section("Exploits")
check(not Mock.request(carol, "UpgradeLab").ok, "non-owner can't upgrade a lab")
check(not Mock.request(carol, "LabSettings", { access = "private" }).ok, "non-owner can't change lab settings")
check(not Mock.request(bob, "ReleaseCreature", { uid = "999" }).ok, "can't release a creature you don't have")
check(not Mock.request(carol, "EquipWeapon", { uid = "1" }).ok, "can't equip a weapon you don't own")

-- states for the client UI test
do
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	pb.data.dishes = { glow_jelly = 2, phoenix_wings = 1, hydra_salad = 1 }
	local dump = { lab = Lab.buildState(bob), combat = Combat.buildState(bob), arena = Mock.lastPush(bob, "arena") }
	fs.writeFile("build/lab_states.json", serde.encode("json", dump, true))
end

print(("\nRESULT: %d passed, %d failed, %d runtime errors"):format(passed, failed, #Mock.errors))
for i, e in ipairs(Mock.errors) do
	if i > 5 then
		break
	end
	print(e)
end
if failed > 0 or #Mock.errors > 0 then
	process.exit(1)
end
