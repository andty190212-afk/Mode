-- Restaurant Island Tycoon - client bootstrap
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
Net.init()

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local HUD = require(Controllers.HUD)
local MenusMain = require(Controllers.MenusMain)
local MenusShop = require(Controllers.MenusShop)
local Minigames = require(Controllers.Minigames)
local Build = require(Controllers.BuildController)
local Heli = require(Controllers.HeliController)
local Effects = require(Controllers.Effects)
local Localizer = require(Controllers.Localizer)
local LabClient = require(Controllers.LabClient)
local CombatClient = require(Controllers.CombatClient)

local player = Players.LocalPlayer

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

Localizer.init()
UI.screen()
MenusMain.build()
MenusShop.build()
HUD.build()
Build.init()
Heli.init()
Effects.init(Minigames, HUD)
LabClient.init(Effects)
CombatClient.init(Build)

MenusShop.onBuildSelect = function(kind, id)
	Build.place(kind, id)
end
MenusShop.onBuildEdit = function(kind)
	Build.edit(kind)
end

-- ===================== STATE SYNC =====================
local refreshQueued = false
local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(0.4, function()
		refreshQueued = false
		UI.refreshOpen()
	end)
end

local lobbyShown = false
Net.onPush("player", function(data)
	local prev = State.player
	State.set("player", data)
	if data.island == 0 then
		State.set("restaurant", nil)
		if not lobbyShown or (prev and prev.island ~= 0) then
			lobbyShown = true
			UI.open("lobby")
		end
	elseif prev and prev.island == 0 then
		UI.close("lobby")
	end
	queueRefresh()
end)

Net.onPush("restaurant", function(data)
	if State.player and State.player.island == data.index then
		State.set("restaurant", data)
		queueRefresh()
	end
end)

Net.onPush("world", function(data)
	State.set("world", data)
	if UI.isOpen("lobby") or UI.isOpen("island") or UI.isOpen("stats") or UI.isOpen("team") then
		queueRefresh()
	end
end)

Net.remote("Toast").OnClientEvent:Connect(function(text, kind)
	UI.toast(text, kind)
end)

-- ===================== COOKING =====================
Net.onPush("cook", function(data)
	Minigames.run(data, function(scores)
		if scores == nil then
			Net.request("FinishCook", { token = data.token, cancel = true })
			return
		end
		local res = Net.request("FinishCook", { token = data.token, scores = scores })
		if res and res.ok then
			local q = math.floor((res.quality or 0) * 100)
			UI.toast((data.kind == "drink" and "🥤 Напиток готов! " or "🍽️ Блюдо на раздаче! ") .. "Качество: " .. q .. "%", q >= 75 and "success" or "info")
		else
			UI.toast(res and res.err or "Ошибка", "error")
		end
	end)
end)

Net.onPush("cookCancel", function()
	Minigames.cancel()
end)

-- initial handshake
task.spawn(function()
	local res = Net.request("Hello", {})
	if res and res.world then
		State.set("world", res.world)
	end
end)

player.CharacterAdded:Connect(function()
	Build.stop()
end)

-- remove the loading screen from the place file
task.delay(1, function()
	local loading = player:WaitForChild("PlayerGui"):FindFirstChild("Loading")
	if loading then
		loading:Destroy()
	end
end)

print("[Restaurant Island Tycoon] client ready")
