-- In-game admin panel (game creator + players he granted admin rights). Server checks everything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rarities = require(Shared.Data.Rarities)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local AdminClient = {}
local player = Players.LocalPlayer
local admin -- last AdminState

local function rc(r)
	local c = Rarities.Info[r].color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function refreshState()
	local res = Net.request("AdminState", {})
	admin = res and res.ok and res.state or { isAdmin = false }
end

local function amountOf()
	local v = tonumber(UI.boxValues and UI.boxValues.adminAmount or "")
	return v and math.floor(v) or 0
end

local function render(c)
	if not admin or not admin.isAdmin then
		UI.label(c, "Только для админов.", 15, { color = T.sub })
		return
	end
	UI.label(c, admin.isHead and "👑 Вы создатель игры — главный админ" or "🛡️ Вы админ", 16, { font = UI.Font, color = T.gold })

	UI.label(c, "💵 Деньги", 18, { font = UI.Font, color = T.accent })
	local row = UI.row(c, 44)
	UI.textbox(row, "Сумма, например 100000", { key = "adminAmount", size = UDim2.fromOffset(230, 38) })
	UI.button(row, "Себе", T.good, function()
		UI.request(Net, "AdminGiveMoney", { amount = amountOf() }, "Деньги выданы")
	end, { size = UDim2.fromOffset(110, 38) })
	UI.button(row, "В бюджет ресторана", T.blue, function()
		UI.request(Net, "AdminGiveMoney", { amount = amountOf(), budget = true }, "Бюджет пополнен")
	end, { size = UDim2.fromOffset(200, 38) })
	for _, p in ipairs(admin.players or {}) do
		if p.id ~= player.UserId then
			local r = UI.row(c, 38)
			UI.label(r, p.name .. (p.admin and "  🛡️" or ""), 14, { sizeUDim = UDim2.fromOffset(220, 34) })
			UI.button(r, "Выдать деньги", T.good, function()
				UI.request(Net, "AdminGiveMoney", { amount = amountOf(), userId = p.id }, "Выдано игроку " .. p.name)
			end, { size = UDim2.fromOffset(160, 32), textSize = 13 })
		end
	end

	UI.label(c, "⭐ Ресторан", 18, { font = UI.Font, color = T.accent })
	local starRow = UI.row(c, 40)
	for n = 1, 5 do
		UI.button(starRow, string.rep("★", n), T.purple, function()
			UI.request(Net, "DebugSetStars", { stars = n }, "Уровень ресторана: " .. n .. "★")
		end, { size = UDim2.fromOffset(100, 34), textSize = 13 })
	end
	UI.button(c, "⚡ +100 гостей, +$250k в бюджет, репутация", T.purple, function()
		UI.request(Net, "DebugBoost", {}, "Готово")
	end, { size = UDim2.fromOffset(420, 36), textSize = 13 })

	UI.label(c, "🍽️ Особые блюда и 🧪 существа (по редкости)", 18, { font = UI.Font, color = T.accent })
	local dishRow = UI.row(c, 38)
	UI.button(dishRow, "🎁 Блюда: все 7", T.warn, function()
		UI.request(Net, "DevGiveDishes", { rarity = "all" }, "Выдано 7 блюд")
	end, { size = UDim2.fromOffset(160, 34), textSize = 13, textColor = Color3.fromRGB(40, 30, 10) })
	local creatureRow = UI.row(c, 38)
	for _, r in ipairs(Rarities.Order) do
		local b = UI.button(creatureRow, Rarities.Info[r].name, rc(r), function()
			local res = Net.request("AdminGiveCreature", { rarity = r })
			if res and res.ok then
				UI.toast("Существо выдано в коллекцию", "success")
			else
				UI.toast(res and res.err or "Ошибка", "error")
			end
		end, { size = UDim2.fromOffset(104, 34), textSize = 12 })
		b.TextColor3 = Color3.fromRGB(20, 20, 30)
	end

	if admin.isHead then
		UI.label(c, "🛡️ Админы (выдавать и снимать права может только создатель)", 18, { font = UI.Font, color = T.accent })
		local addRow = UI.row(c, 44)
		UI.textbox(addRow, "Ник игрока Roblox", { key = "adminName", size = UDim2.fromOffset(260, 38) })
		UI.button(addRow, "Выдать права админа", T.good, function()
			if UI.request(Net, "AdminAddAdmin", { name = UI.boxValues and UI.boxValues.adminName or "" }, "Права выданы").ok then
				refreshState()
				UI.windows.admin:refresh()
			end
		end, { size = UDim2.fromOffset(230, 38) })
		for _, a in ipairs(admin.admins or {}) do
			local r = UI.row(c, 38)
			UI.label(r, "🛡️ " .. a.name, 14, { sizeUDim = UDim2.fromOffset(260, 34) })
			UI.button(r, "Снять права", T.bad, function()
				if UI.request(Net, "AdminRemoveAdmin", { userId = a.id }, "Права сняты").ok then
					refreshState()
					UI.windows.admin:refresh()
				end
			end, { size = UDim2.fromOffset(150, 32), textSize = 13 })
		end
		if #(admin.admins or {}) == 0 then
			UI.label(c, "Пока нет других админов.", 14, { color = T.sub })
		end
	end
end

function AdminClient.open()
	task.spawn(function()
		refreshState()
		UI.open("admin")
		UI.windows.admin:refresh()
	end)
end

function AdminClient.init()
	UI.window("admin", "Админ-панель", "🛡️", { render = render, width = 820, height = 600 })
end

return AdminClient
