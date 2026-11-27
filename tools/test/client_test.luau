-- Client UI smoke test: runs ClientMain in the mock engine with real replicated
-- states (captured by server_test), opens every window/tab and plays mini-games.
-- Usage: lune run tools/test/client_test.luau
local Mock = require("./mock")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local states = serde.decode("json", fs.readFile("build/test_states.json"))

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

Mock.loadPlace("build/RestaurantIslandTycoon.rbxl")
Mock.mode = "client"
local game = Mock.game
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- local player
local me = Mock.addPlayer("Alice")
Players.LocalPlayer = me
Mock.localPlayer = me
me.UserId = states.player.userId

-- fake server answers
local requests = {}
RS.Remotes.Request.OnServerInvoke = function(player, name, payload)
	table.insert(requests, name)
	if name == "Hello" then
		return { ok = true, world = states.world }
	elseif name == "FinishCook" then
		return { ok = true, quality = 0.8 }
	end
	return { ok = true }
end
local function push(channel, data)
	RS.Remotes.Push.OnClientEvent:Fire(channel, data)
	Mock.advance(0.6)
end

print("== Client boot")
local sps = game:GetService("StarterPlayer").StarterPlayerScripts
Mock.runScript(sps.ClientMain)
Mock.advance(1)
check(#Mock.errors == 0, "client booted", Mock.errors[1])
local gui = me.PlayerGui:FindFirstChild("RestaurantUI")
check(gui ~= nil, "main ScreenGui created")

print("== Lobby (no restaurant)")
push("player", states.lobbyPlayer)
push("world", states.world)
local UI = Mock.env.require(sps.Controllers.UI)
check(UI.isOpen("lobby"), "lobby window opens for players without a restaurant")

print("== Owner state")
push("player", states.player)
push("restaurant", states.restaurant)
check(not UI.isOpen("lobby"), "lobby closes after joining a restaurant")
local errorsBefore = #Mock.errors
local windows = { "restaurant", "professions", "team", "staff", "shop", "upgrades", "build", "island", "heli", "quests", "achievements", "stats", "store", "lobby" }
for _, id in ipairs(windows) do
	local win = UI.windows[id]
	check(win ~= nil, "window '" .. id .. "' exists")
	if win then
		UI.open(id)
		Mock.advance(0.1)
		local n = #win.content:GetChildren()
		check(n > 1, "window '" .. id .. "' renders content (" .. n .. " children)")
		if win.tabsList then
			for _, tab in ipairs(win.tabsList) do
				win.tab = tab.id
				win:refresh()
				Mock.advance(0.1)
				check(#win.content:GetChildren() > 1, "  tab '" .. tab.id .. "' renders")
			end
		end
		UI.close(id)
	end
end
check(#Mock.errors == errorsBefore, "no render errors", Mock.errors[errorsBefore + 1])

if process.args[1] == "dump" then
	for _, id in ipairs({ "restaurant", "upgrades", "professions" }) do
		local win = UI.windows[id]
		if win.tabsList then
			win.tab = win.tabsList[#win.tabsList > 1 and (id == "upgrades" and 2 or 1) or 1].id
		end
		UI.open(id)
		Mock.advance(0.1)
		print("---- " .. id)
		for _, d in ipairs(win.content:GetDescendants()) do
			if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and d.Text ~= "" then
				print("   " .. d.ClassName:sub(5) .. ": " .. d.Text:gsub("\n", " | "))
			end
		end
		UI.close(id)
	end
end
print("== Friend view")
push("player", states.friendPlayer)
for _, id in ipairs({ "team", "professions", "restaurant", "staff" }) do
	UI.open(id)
	Mock.advance(0.1)
	UI.close(id)
end
check(#Mock.errors == errorsBefore, "friend view renders without errors", Mock.errors[errorsBefore + 1])

print("== Typing in a text box survives refreshes")
UI.windows.restaurant.tab = "overview"
UI.open("restaurant")
Mock.advance(0.2)
local box
for _, d in ipairs(UI.windows.restaurant.content:GetDescendants()) do
	if d.ClassName == "TextBox" and d.PlaceholderText == "Сумма" then
		box = d
	end
end
check(box ~= nil, "deposit box found")
Mock.data(box).focused = true
box.Text = "250"
push("restaurant", states.restaurant)
Mock.advance(2)
check(box.Parent ~= nil and box.Text == "250", "focused box is not destroyed by state updates")
Mock.data(box).focused = false
UI.windows.restaurant:refresh()
local box2
for _, d in ipairs(UI.windows.restaurant.content:GetDescendants()) do
	if d.ClassName == "TextBox" and d.PlaceholderText == "Сумма" then
		box2 = d
	end
end
check(box2 ~= nil and box2.Text == "250", "typed amount kept after redraw", box2 and box2.Text)
UI.close("restaurant")

print("== Buttons")
-- press every button in the restaurant window (requests go to the fake server)
push("player", states.player)
UI.open("restaurant")
Mock.advance(0.1)
local pressed = 0
for _, d in ipairs(UI.windows.restaurant.frame:GetDescendants()) do
	if d.ClassName == "TextButton" and d.Name ~= "TextButton_skip" then
		d.Activated:Fire()
		pressed += 1
	end
end
Mock.advance(1)
check(pressed > 3 and #Mock.errors == errorsBefore, "buttons fire without errors (" .. pressed .. " pressed)", Mock.errors[errorsBefore + 1])
UI.close("restaurant")

print("== Mini-games")
local Minigames = Mock.env.require(sps.Controllers.Minigames)
local Recipes = Mock.env.require(RS.Shared.Data.Recipes)
local steps = { "chop", "prep", "grill", "boil", "bake", "assemble", "garnish", "pour", "shake", "brew" }
for _, step in ipairs(steps) do
	local result
	Minigames.active = false
	Minigames.run({ token = "t", recipeId = "burger", steps = { step }, ease = 1, kind = "dish" }, function(scores)
		result = scores
	end)
	-- press the action button / bubbles / ingredient buttons repeatedly
	for _ = 1, 60 do
		Mock.advance(0.15)
		local rs = game:GetService("RunService")
		rs.RenderStepped:Fire(0.15)
		local overlay = gui:FindFirstChild("Minigame")
		if not overlay then
			break
		end
		for _, d in ipairs(overlay:GetDescendants()) do
			if d.ClassName == "TextButton" and d.Text ~= "✕" then
				d.MouseButton1Down:Fire()
				d.Activated:Fire()
				d.MouseButton1Up:Fire()
			end
		end
	end
	Mock.advance(2)
	check(result ~= nil and #result == 1 and result[1] >= 0 and result[1] <= 1, "mini-game '" .. step .. "' completes with a score", result and result[1])
end
-- full cooking flow through the push channel
local fc = 0
for _, n in ipairs(requests) do
	if n == "FinishCook" then
		fc += 1
	end
end
push("cook", { token = "tok1", recipeId = "pancakes", steps = Recipes.ById.pancakes.steps, ease = 1, kind = "dish" })
for _ = 1, 120 do
	Mock.advance(0.15)
	game:GetService("RunService").RenderStepped:Fire(0.15)
	local overlay = gui:FindFirstChild("Minigame")
	if not overlay then
		break
	end
	for _, d in ipairs(overlay:GetDescendants()) do
		if d.ClassName == "TextButton" and d.Text ~= "✕" then
			d.MouseButton1Down:Fire()
			d.Activated:Fire()
			d.MouseButton1Up:Fire()
		end
	end
end
Mock.advance(2)
local fc2 = 0
for _, n in ipairs(requests) do
	if n == "FinishCook" then
		fc2 += 1
	end
end
check(fc2 == fc + 1, "cook push -> mini-games -> FinishCook request sent")

print("== Build mode & helicopter controller")
local Build = Mock.env.require(sps.Controllers.BuildController)
Build.place("furniture", "table_wood_4")
game:GetService("RunService").RenderStepped:Fire(0.016)
Mock.advance(0.2)
Build.stop()
Build.edit("decor")
Mock.advance(0.2)
Build.stop()
game:GetService("RunService").RenderStepped:Fire(0.016)
check(#Mock.errors == errorsBefore, "build mode runs without errors", Mock.errors[errorsBefore + 1])

-- helicopter: rotor animation for all helicopters + local piloting
local heli = RS.Assets.Helicopters.scout:Clone()
heli:SetAttribute("Helicopter", true)
heli:SetAttribute("Speed", 70)
local root = heli:FindFirstChild("Root")
heli.PrimaryPart = root
local lift = Mock.Instance.new("LinearVelocity")
lift.Name = "Lift"
lift.Parent = root
local gyro = Mock.Instance.new("AlignOrientation")
gyro.Name = "Gyro"
gyro.Parent = root
heli.Parent = game.Workspace.Helicopters
local hum = me.Character:FindFirstChildOfClass("Humanoid")
hum.SeatPart = heli:FindFirstChild("PilotSeat")
Mock.advance(0.2)
for _ = 1, 10 do
	game:GetService("RunService").RenderStepped:Fire(0.016)
end
Mock.advance(0.2)
check(lift.MaxForce == 1e7, "piloting enables flight constraints")
local rotor = heli:FindFirstChild("Rotor")
check(rotor ~= nil and rotor:GetAttribute("Spin") == "main", "rotor animated on the client")
hum.SeatPart = nil
Mock.advance(4)
check(#Mock.errors == errorsBefore, "helicopter controller runs without errors", Mock.errors[errorsBefore + 1])

print("== Effects")
local Fx = RS.Remotes.Fx
for _, name in ipairs({ "money", "coins", "levelup", "starUp", "announce", "event", "sparkle", "ding", "achievement", "openMenu", "barrier", "invite" }) do
	Fx.OnClientEvent:Fire(name, { amount = 50, pos = Mock.env.Vector3.new(0, 0, 0), text = "test", level = 3, stars = 2, menu = "shop", on = true, island = 1 })
end
Mock.advance(8)
check(#Mock.errors == errorsBefore, "all effects run without errors", Mock.errors[errorsBefore + 1])
RS.Remotes.Toast.OnClientEvent:Fire("hello", "success")
Mock.advance(6)

print("== Lab, weapons and arena UI")
do
	local fsx = require("@lune/fs")
	local serdex = require("@lune/serde")
	if fsx.isFile("build/lab_states.json") then
		local ls = serdex.decode("json", fsx.readFile("build/lab_states.json"))
		push("player", states.player)
		push("lab", ls.lab)
		push("combat", ls.combat)
		if ls.arena then
			push("arena", ls.arena)
		end
		local errs = #Mock.errors
		local warns = #Mock.warnings
		local labWin = UI.windows.lab
		check(labWin ~= nil and UI.windows.arena ~= nil, "lab and arena windows exist")
		for _, tab in ipairs(labWin.tabsList) do
			labWin.tab = tab.id
			UI.open("lab")
			labWin:refresh()
			Mock.advance(0.2)
			check(#labWin.content:GetChildren() > 1, "  lab tab '" .. tab.id .. "' renders")
			UI.close("lab")
		end
		-- a dish cooked after the last combat push must still be listed (lab state is the source)
		do
			local labState = table.clone(ls.lab)
			labState.dishes = { glow_jelly = 1 }
			local combatState = table.clone(ls.combat)
			combatState.dishes = {}
			push("combat", combatState)
			push("lab", labState)
			labWin.tab = "dishes"
			UI.open("lab")
			labWin:refresh()
			Mock.advance(0.2)
			local eatBtn = false
			for _, d in ipairs(labWin.content:GetDescendants()) do
				if d.ClassName == "TextButton" and string.find(d.Text, "Съесть") then
					eatBtn = true
				end
			end
			check(eatBtn, "cooked dish appears in the Dishes menu with an Eat button")
			UI.close("lab")
		end
		UI.open("arena")
		Mock.advance(0.2)
		check(#UI.windows.arena.content:GetChildren() > 1, "arena window renders")
		UI.close("arena")
		local LabClient = Mock.env.require(sps.Controllers.LabClient)
		Mock.call(function()
			Mock.env.task.spawn(LabClient.showCreatureReveal, { id = "sunphoenix", uid = "1", rarity = "Legendary", chest = "basic" })
		end)
		Mock.advance(3)
		check(gui:FindFirstChild("RevealOverlay") ~= nil, "chest opening animation shows the creature")
		Mock.call(function()
			Mock.env.task.spawn(LabClient.showWeaponReveal, { id = "starfall_baton", uid = "2", rarity = "Secret", dish = "moon_mochi" })
		end)
		Mock.advance(3)
		check(gui:FindFirstChild("RevealOverlay") ~= nil, "eating animation reveals the weapon")
		-- lab alarm / theft alert
		RS.Remotes.Fx.OnClientEvent:Fire("labAlarm", { kind = "open", remaining = 120 })
		Mock.advance(1)
		check(gui:FindFirstChild("BigAlert") ~= nil and gui:FindFirstChild("LabTimer") ~= nil, "lab open alarm + countdown")
		RS.Remotes.Fx.OnClientEvent:Fire("theft", { kind = "alarm", name = "Крошкокраб", thief = "Bob", thiefId = 0 })
		RS.Remotes.Fx.OnClientEvent:Fire("ability", { ability = "meteor", from = Mock.env.Vector3.new(0, 0, 0), point = Mock.env.Vector3.new(0, 0, 5), color = { 255, 100, 0 }, delay = 0.5 })
		RS.Remotes.Fx.OnClientEvent:Fire("hit", { pos = Mock.env.Vector3.new(0, 0, 0), amount = 12, by = 1, victim = 2 })
		-- real joints so the animation code is exercised (R15 and R6)
		local E = Mock.env
		local function rig(char, r6)
			local function joint(partName, motorName, c0)
				local part = char:FindFirstChild(partName) or E.Instance.new("Part")
				part.Name = partName
				part.Parent = char
				local m = E.Instance.new("Motor6D")
				m.Name = motorName
				m.C0 = c0
				m.Parent = part
				return m
			end
			if r6 then
				return joint("Torso", "Right Shoulder", E.CFrame.new(1, 0.5, 0))
			end
			joint("UpperTorso", "Waist", E.CFrame.new(0, 0.2, 0))
			joint("LeftUpperArm", "LeftShoulder", E.CFrame.new(-1, 0.5, 0))
			joint("RightLowerArm", "RightElbow", E.CFrame.new(0, -0.3, 0))
			return joint("RightUpperArm", "RightShoulder", E.CFrame.new(1, 0.5, 0))
		end
		local shoulder = rig(me.Character, false)
		local base0 = shoulder.C0
		local wm = E.Instance.new("Tool")
		wm.Name = "Бита"
		wm:SetAttribute("WeaponId", "starter_bat")
		local wh = E.Instance.new("Part")
		wh.Name = "Handle"
		wh.Parent = wm
		wm.Parent = me.Character
		Mock.advance(0.7)
		RS.Remotes.Fx.OnClientEvent:Fire("swing", { userId = me.UserId, weapon = "starter_bat", kind = "melee", dir = E.Vector3.new(0, 0, -1), from = E.Vector3.new(0, 0, 0), range = 8, color = { 255, 200, 0 } })
		Mock.advance(0.18)
		check(wm:FindFirstChild("SwingTrail", true) ~= nil, "swing trail drawn on the weapon (motion itself is played by the server)")
		Mock.advance(1)
		local bot = Mock.addPlayer("R6Bot")
		local r6Shoulder = rig(bot.Character, true)
		local r6Base = r6Shoulder.C0
		RS.Remotes.Fx.OnClientEvent:Fire("swing", { userId = bot.UserId, weapon = "coconut_sling", kind = "ranged", dir = E.Vector3.new(0, 0, -1), from = E.Vector3.new(0, 0, 0), range = 30, color = { 255, 200, 0 } })
		Mock.advance(0.12)
		Mock.advance(1)
		for _, w in ipairs({ "starter_bat", "spiky_ladle", "coconut_sling", "starfall_baton" }) do
			RS.Remotes.Fx.OnClientEvent:Fire("swing", { userId = me.UserId, weapon = w, kind = "melee", dir = Mock.env.Vector3.new(0, 0, -1), from = Mock.env.Vector3.new(0, 0, 0), range = 8, color = { 255, 200, 0 } })
			Mock.advance(0.6)
		end
		do
			-- per-skill character motion is layered on Motor6D.Transform
			shoulder.Transform = Mock.env.CFrame.new()
			RS.Remotes.Fx.OnClientEvent:Fire("ability", { ability = "meteor", userId = me.UserId, rarity = "Epic", from = Mock.env.Vector3.new(0, 5, 0), point = Mock.env.Vector3.new(0, 3, -10), delay = 0.3 })
			Mock.advance(0.15)
			check(shoulder.Transform ~= Mock.env.CFrame.new(), "ability moves the character (Transform layer, no C0)")
			Mock.advance(1.5)
		end
		do
			local Weapons = Mock.env.require(RS.Shared.Data.Weapons)
			local E = Mock.env
			for _, w in ipairs(Weapons.List) do
				RS.Remotes.Fx.OnClientEvent:Fire("ability", {
					ability = w.ability.id, userId = me.UserId, rarity = w.rarity, color = w.color,
					from = E.Vector3.new(0, 5, 0), dir = E.Vector3.new(0, 0, -1), point = E.Vector3.new(0, 3, -12),
					to = E.Vector3.new(0, 5, -15), dur = 1, delay = 0.3, targets = { me.UserId }, radius = 8,
				})
				Mock.advance(0.3)
			end
			RS.Remotes.Fx.OnClientEvent:Fire("ability", { ability = "thorn_snap", point = E.Vector3.new(0, 3, 0), userId = me.UserId, rarity = "Epic" })
			RS.Remotes.Fx.OnClientEvent:Fire("ability", { ability = "mirage_boom", point = E.Vector3.new(0, 3, 0), userId = me.UserId, rarity = "Mythical", color = { 255, 150, 230 } })
			Mock.advance(3)
		end
		Mock.advance(2)
		check(gui:FindFirstChild("CombatHud", true) ~= nil, "combat HUD (attack / ability buttons) exists")
		check(#Mock.errors == errs, "lab UI runs without errors", Mock.errors[errs + 1])
		check(#Mock.warnings == warns, "lab UI renders without warnings", Mock.warnings[warns + 1])
	else
		print("  (skipped: run tools/test/lab_test.luau first)")
	end
end

print("== Language switch")
local function textsWith(pattern)
	local n = 0
	for _, d in ipairs(gui:GetDescendants()) do
		if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and string.find(d.Text, pattern) then
			n += 1
		end
	end
	return n
end
local langBtn = gui:FindFirstChild("Language", true)
check(langBtn ~= nil, "language button exists in side menu")
local wasRu = textsWith("Профессии") > 0
if langBtn then
	langBtn.Activated:Fire()
	Mock.advance(1)
end
check(wasRu and textsWith("Профессии") == 0 and textsWith("Professions") > 0, "side menu switches to English")
local cyr = 0
for _, d in ipairs(gui:GetDescendants()) do
	if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and d.Visible ~= false and string.find(d.Text, "[\208\209]") then
		cyr += 1
		if cyr <= 5 then
			print("  untranslated: " .. d.Text)
		end
	end
end
check(cyr <= 3, "almost no Russian text left in English mode (" .. cyr .. ")")
push("player", states.player)
push("restaurant", states.restaurant)
table.insert(windows, "lab")
table.insert(windows, "arena")
local leftovers, seen = {}, {}
for _, id in ipairs(windows) do
	local win = UI.windows[id]
	local tabs = win.tabsList or { { id = win.tab } }
	for _, tab in ipairs(tabs) do
		win.tab = tab.id
		UI.open(id)
		win:refresh()
		Mock.advance(0.1)
		for _, d in ipairs(win.frame and win.frame:GetDescendants() or win.content:GetDescendants()) do
			if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and string.find(d.Text, "[\208\209]") and not seen[d.Text] then
				seen[d.Text] = true
				table.insert(leftovers, id .. ": " .. d.Text:gsub("\n", " | "))
			end
		end
		UI.close(id)
	end
end
for i, t in ipairs(leftovers) do
	if i <= 40 then
		print("  untranslated: " .. t)
	end
end
if process.args[1] == "en" then
	UI.open("restaurant")
	Mock.advance(0.1)
	for _, d in ipairs(UI.windows.restaurant.content:GetDescendants()) do
		if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and d.Text ~= "" then
			print("   EN: " .. d.Text:gsub("\n", " | "))
		end
	end
	UI.close("restaurant")
end
check(#leftovers <= 5, "all windows are in English (" .. #leftovers .. " leftovers)")
if langBtn then
	langBtn.Activated:Fire()
	Mock.advance(1)
end
check(textsWith("Профессии") > 0, "switches back to Russian")
check(#Mock.errors == errorsBefore, "language switch runs without errors", Mock.errors[errorsBefore + 1])

check(#Mock.warnings == 0, "no warnings (render errors are reported as warnings)", Mock.warnings[1])
for i, w in ipairs(Mock.warnings) do
	if i > 10 then
		break
	end
	print("  warn: " .. w)
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
