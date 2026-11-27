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
local windows = { "restaurant", "professions", "team", "staff", "shop", "upgrades", "build", "island", "heli", "barrier", "quests", "achievements", "stats", "store", "lobby" }
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
for _, id in ipairs({ "team", "professions", "restaurant", "barrier", "staff" }) do
	UI.open(id)
	Mock.advance(0.1)
	UI.close(id)
end
check(#Mock.errors == errorsBefore, "friend view renders without errors", Mock.errors[errorsBefore + 1])

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
