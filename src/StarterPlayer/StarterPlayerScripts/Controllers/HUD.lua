-- HUD: top status bar (personal money, restaurant budget, level, profession level,
-- stars, guests, boost), side menu, contextual quick actions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Professions = require(Shared.Data.Professions)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local HUD = {}
local player = Players.LocalPlayer
local refs = {}

local MENU = {
	{ id = "restaurant", icon = "🍽️", text = "Ресторан", key = Enum.KeyCode.One },
	{ id = "professions", icon = "👔", text = "Профессии", key = Enum.KeyCode.Two },
	{ id = "team", icon = "✉️", text = "Команда", key = Enum.KeyCode.Three },
	{ id = "staff", icon = "🧑‍🍳", text = "Персонал", key = Enum.KeyCode.Four },
	{ id = "shop", icon = "🛒", text = "Продукты", key = Enum.KeyCode.Five },
	{ id = "upgrades", icon = "⚙️", text = "Улучшения", key = Enum.KeyCode.Six },
	{ id = "build", icon = "🔨", text = "Стройка", key = Enum.KeyCode.B },
	{ id = "island", icon = "🏝️", text = "Остров", key = Enum.KeyCode.Seven },
	{ id = "heli", icon = "🚁", text = "Вертолёт", key = Enum.KeyCode.Eight },
	{ id = "barrier", icon = "🛡️", text = "Барьер", key = Enum.KeyCode.Nine },
	{ id = "quests", icon = "📋", text = "Задания", key = Enum.KeyCode.J },
	{ id = "achievements", icon = "🏆", text = "Награды", key = Enum.KeyCode.K },
	{ id = "stats", icon = "📊", text = "Статистика", key = Enum.KeyCode.L },
	{ id = "store", icon = "💎", text = "Robux", key = Enum.KeyCode.P },
}

local function pill(parent, icon, color, width, order)
	local f = UI.new("Frame", {
		BackgroundColor3 = T.panel,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(width, 44),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(f, 22)
	UI.stroke(f, color, 2, 0.35)
	local ic = UI.new("TextLabel", {
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(4, 4),
		Text = icon,
		TextSize = 20,
		Font = UI.Font,
		Parent = f,
	})
	UI.corner(ic, 18)
	local label = UI.label(f, "", 17, { font = UI.Font, sizeUDim = UDim2.new(1, -50, 1, 0) })
	label.Position = UDim2.fromOffset(46, 0)
	return f, label
end

function HUD.build()
	local gui = UI.screen()
	-- ===== top bar =====
	local top = UI.new("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(1040, 44),
		Parent = gui,
	})
	UI.list(top, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	local _, moneyL = pill(top, "💵", T.good, 160, 1)
	local _, budgetL = pill(top, "🏦", T.accent2, 160, 2)
	local lvlF, lvlL = pill(top, "⭐", T.purple, 150, 3)
	local xpBar = UI.progress(lvlF, 0, T.purple, { size = UDim2.new(1, -60, 0, 4), position = UDim2.new(0, 48, 1, -9) })
	local _, profL = pill(top, "👔", T.blue, 170, 4)
	local _, starsL = pill(top, "🏆", T.gold, 150, 5)
	local _, guestsL = pill(top, "👥", T.accent, 110, 6)
	local boostF, boostL = pill(top, "⚡", T.warn, 120, 7)
	boostF.Visible = false
	refs.money, refs.budget, refs.level, refs.xp, refs.prof, refs.stars, refs.guests = moneyL, budgetL, lvlL, xpBar, profL, starsL, guestsL
	refs.boostF, refs.boost = boostF, boostL

	-- ===== side menu =====
	local side = UI.new("ScrollingFrame", {
		Name = "SideMenu",
		BackgroundColor3 = T.panel,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 20),
		Size = UDim2.fromOffset(84, 560),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		BorderSizePixel = 0,
		Parent = gui,
	})
	UI.corner(side, 16)
	UI.list(side, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)
	UI.padding(side, 4, 6)
	for i, m in ipairs(MENU) do
		local b = UI.new("TextButton", {
			Text = "",
			BackgroundColor3 = T.card,
			AutoButtonColor = true,
			Size = UDim2.fromOffset(72, 62),
			LayoutOrder = i,
			Parent = side,
		})
		UI.corner(b, 12)
		UI.label(b, m.icon, 24, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 34) }).Position = UDim2.fromOffset(0, 4)
		UI.label(b, m.text, 11, { align = Enum.TextXAlignment.Center, font = UI.Font, sizeUDim = UDim2.new(1, 0, 0, 18), color = T.sub }).Position = UDim2.fromOffset(0, 40)
		b.Activated:Connect(function()
			UI.click()
			if m.id == "team" and State.myIsland() == 0 then
				UI.toggle("lobby")
			else
				UI.toggle(m.id)
			end
		end)
	end

	-- ===== quick actions (bottom centre) =====
	local quick = UI.new("Frame", {
		Name = "Quick",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(640, 52),
		Parent = gui,
	})
	UI.list(quick, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	refs.quick = quick

	-- hotkeys
	-- меню открываются только кнопками (мышь / касание), горячих клавиш нет

	State.Changed:Connect(function()
		HUD.update()
	end)
	HUD.update()
end

local lastQuickKey = ""
local function rebuildQuick()
	local p = State.player
	local role = p and p.role or ""
	local inIsland = p and p.island ~= 0
	local key = role .. tostring(inIsland)
	if key == lastQuickKey then
		return
	end
	lastQuickKey = key
	UI.clear(refs.quick)
	if not inIsland then
		UI.button(refs.quick, "🏝️ Открыть ресторан", T.accent, function()
			UI.open("lobby")
		end, { size = UDim2.fromOffset(220, 46) })
		return
	end
	if role == "" then
		UI.button(refs.quick, "👔 Выбрать профессию", T.accent, function()
			UI.open("professions")
		end, { size = UDim2.fromOffset(230, 46) })
	end
	if role == "Cook" then
		UI.button(refs.quick, "🍳 Готовить заказ", T.accent, function()
			UI.request(Net, "StartCook", { kind = "dish" })
		end, { size = UDim2.fromOffset(190, 46) })
	end
	if role == "Cook" or role == "Waiter" then
		UI.button(refs.quick, "🍹 Сделать напиток", T.purple, function()
			UI.request(Net, "StartCook", { kind = "drink" })
		end, { size = UDim2.fromOffset(190, 46) })
	end
	if role == "Director" then
		UI.button(refs.quick, "🧑‍🍳 Персонал", T.blue, function()
			UI.open("staff")
		end, { size = UDim2.fromOffset(160, 46) })
		UI.button(refs.quick, "📜 Меню и цены", T.purple, function()
			local w = UI.windows.restaurant
			w.tab = "menu"
			UI.open("restaurant")
		end, { size = UDim2.fromOffset(170, 46) })
	end
	if role == "Chef" then
		UI.button(refs.quick, "👨‍🍳 Су-шеф", T.blue, function()
			UI.open("staff")
		end, { size = UDim2.fromOffset(160, 46) })
	end
	UI.button(refs.quick, "🛒 Продукты", T.good, function()
		UI.open("shop")
	end, { size = UDim2.fromOffset(150, 46) })
	UI.button(refs.quick, "🏠", T.card, function()
		UI.request(Net, "GoHome", {})
	end, { size = UDim2.fromOffset(50, 46) })
end

function HUD.update()
	local p = State.player
	local r = State.restaurant
	if not refs.money then
		return
	end
	if p then
		refs.money.Text = Util.formatMoney(p.money)
		refs.level.Text = "Ур. " .. p.level
		refs.xp.Fill.Size = UDim2.fromScale(math.clamp(p.xp / math.max(1, p.xpNeed), 0, 1), 1)
		local role = p.role
		if role ~= "" then
			local def = Professions.ById[role]
			local short = { Cook = "Повар", Waiter = "Официант", Chef = "Шеф", Director = "Директор" }
			refs.prof.Text = def.icon .. " " .. (short[role] or def.name) .. " " .. (p.prof[role] and p.prof[role].level or 1)
		else
			refs.prof.Text = "Нет профессии"
		end
		if p.boost and p.boost.remaining > 0 then
			refs.boostF.Visible = true
			refs.boost.Text = "x" .. p.boost.mult .. " " .. Util.formatTime(p.boost.remaining)
		else
			refs.boostF.Visible = false
		end
	end
	if r and p and p.island ~= 0 then
		refs.budget.Text = Util.formatMoney(r.budget)
		refs.stars.Text = string.rep("★", r.stars) .. string.rep("☆", 5 - r.stars)
		refs.guests.Text = tostring(r.live and r.live.guests or 0)
	else
		refs.budget.Text = "—"
		refs.stars.Text = "—"
		refs.guests.Text = "0"
	end
	rebuildQuick()
end

-- animate a number popping
function HUD.bumpMoney()
	if refs.money then
		local s = refs.money.Parent:FindFirstChild("Bump") or UI.new("UIScale", { Name = "Bump", Parent = refs.money.Parent })
		s.Scale = 1.12
		TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

return HUD
