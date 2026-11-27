-- Shop menus: ingredients, upgrades & star rating, build catalog, island,
-- helicopters, barrier, Robux store.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = Shared.Data
local Ingredients = require(Data.Ingredients)
local Equipment = require(Data.Equipment)
local Stars = require(Data.Stars)
local Furniture = require(Data.Furniture)
local Decor = require(Data.Decor)
local Helicopters = require(Data.Helicopters)
local Recipes = require(Data.Recipes)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local Menus = {}
local player = Players.LocalPlayer
local money = Util.formatMoney
Menus.onBuildSelect = nil -- set by BuildController
Menus.onBuildEdit = nil

local function section(parent, text)
	return UI.label(parent, text, 18, { font = UI.Font, color = T.accent })
end

local shopCategory = "veg"

-- ===================== INGREDIENTS =====================
local function renderShop(c)
	local r = State.restaurant
	if not r then
		UI.label(c, "Вы не в ресторане.", 15, { color = T.sub })
		return
	end
	local sale = r.events and r.events.sale
	UI.label(c, string.format("🏦 Бюджет ресторана: <b>%s</b>   📦 Склад: <b>%d / %d</b>%s", money(r.budget), r.storageUsed, r.storageCap, sale and "   <font color='#F5BE3C'>🏷️ Распродажа −30%!</font>" or ""), 16, { auto = true })
	UI.progress(c, r.storageUsed / math.max(1, r.storageCap), r.storageUsed > r.storageCap * 0.9 and T.bad or T.accent2)
	local quick = UI.row(c, 44)
	UI.button(quick, "⚡ Докупить всё для меню", T.good, function()
		local res = UI.request(Net, "RestockMenu", {})
		if res.ok then
			UI.toast(string.format("Закуплено %d ед. за %s", res.qty, money(res.cost)), "success")
		end
	end, { size = UDim2.fromOffset(260, 40) })
	-- categories
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = c })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(128, 34), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, cat in ipairs(Ingredients.Categories) do
		UI.button(grid, cat.icon .. " " .. cat.name, cat.id == shopCategory and T.accent or T.card, function()
			shopCategory = cat.id
			UI.refreshOpen()
		end, { order = i, textSize = 13 })
	end
	local season = Recipes.currentSeason()
	local mult = sale and 0.7 or 1
	for _, item in ipairs(Ingredients.List) do
		if item.category == shopCategory then
			local locked = item.minStars > r.stars
			local offSeason = item.season and item.season ~= season
			local card = UI.card(c, 52)
			local have = r.inventory[item.id] or 0
			local price = item.price * mult
			UI.label(card, string.format("%s <b>%s</b>  <font color='#A5AFD2'>%s/шт • качество %d%% • на складе: %d</font>%s",
				item.icon, item.name, money(math.max(1, math.ceil(price))), item.quality * 100, have,
				locked and ("  <font color='#EB5555'>🔒 " .. item.minStars .. "★</font>") or (offSeason and "  <font color='#F5BE3C'>не сезон</font>" or "")),
				14, { sizeUDim = UDim2.new(1, -250, 1, 0) }).Position = UDim2.fromOffset(10, 0)
			if not locked and not offSeason then
				local b1 = UI.button(card, "+10 (" .. money(math.ceil(price * 10)) .. ")", T.blue, function()
					UI.request(Net, "BuyIngredient", { id = item.id, packs = 1 })
				end, { size = UDim2.fromOffset(115, 36), textSize = 13 })
				b1.Position = UDim2.new(1, -240, 0.5, -18)
				local b5 = UI.button(card, "+50 (" .. money(math.ceil(price * 50)) .. ")", T.purple, function()
					UI.request(Net, "BuyIngredient", { id = item.id, packs = 5 })
				end, { size = UDim2.fromOffset(115, 36), textSize = 13 })
				b5.Position = UDim2.new(1, -120, 0.5, -18)
			end
		end
	end
end

-- ===================== UPGRADES & RATING =====================
local function renderUpgrades(c, win)
	local r = State.restaurant
	if not r then
		UI.label(c, "Вы не в ресторане.", 15, { color = T.sub })
		return
	end
	if win.tab == "equipment" then
		UI.label(c, "Бюджет: <b>" .. money(r.budget) .. "</b>. Максимальный уровень оборудования = количество звёзд ресторана.", 15, { auto = true })
		for _, e in ipairs(Equipment.List) do
			local lvl = r.equipment[e.id] or 0
			local nextLevel = lvl + 1
			local maxLvl = Equipment.maxLevelFor(r.stars)
			local card = UI.card(c, 56)
			UI.label(card, string.format("%s <b>%s</b>  ур. %d/%d  <font color='#A5AFD2'>%s</font>", e.icon, e.name, lvl, Equipment.MaxLevel, e.desc), 14, { sizeUDim = UDim2.new(1, -210, 1, 0) }).Position = UDim2.fromOffset(10, 0)
			local text, color, disabled
			if lvl >= Equipment.MaxLevel then
				text, color, disabled = "Максимум", T.card, true
			elseif nextLevel > maxLvl then
				text, color, disabled = "🔒 нужно " .. nextLevel .. "★", T.card, true
			else
				text, color = "Улучшить " .. money(Equipment.costFor(e.id, nextLevel)), T.good
			end
			local b = UI.button(card, text, color, function()
				UI.request(Net, "UpgradeEquipment", { id = e.id })
			end, { size = UDim2.fromOffset(190, 40), disabled = disabled, textSize = 14 })
			b.Position = UDim2.new(1, -200, 0.5, -20)
		end
		section(c, "🤖 Кухонный робот")
		local robotCard = UI.card(c, 70, { color = r.kitchenRobot and Color3.fromRGB(38, 70, 56) or nil })
		local stoveLvl = r.equipment.stove or 0
		UI.label(robotCard, r.kitchenRobot and "🤖 <b>Робот работает на кухне</b> и готовит заказы вместо повара (качество мастера, бесплатно)."
			or string.format("🤖 <b>Кухонный робот</b> готовит заказы вместо повара. Нужно: плита %d/%d ур. • %s", stoveLvl, Equipment.MaxLevel, money(Config.KitchenRobotPrice)), 14, { sizeUDim = UDim2.new(1, -210, 1, 0) }).Position = UDim2.fromOffset(10, 0)
		if not r.kitchenRobot then
			local ready = stoveLvl >= Equipment.MaxLevel
			local rb = UI.button(robotCard, ready and ("Купить " .. money(Config.KitchenRobotPrice)) or "🔒 Плита ур. 5", ready and T.gold or T.card, function()
				UI.request(Net, "BuyKitchenRobot", {}, "Робот уже на кухне!")
			end, { size = UDim2.fromOffset(190, 40), disabled = not ready, textSize = 14, textColor = ready and Color3.fromRGB(40, 30, 10) or nil, disabledText = "Улучшите плиту до 5 уровня (нужен ресторан ★5)" })
			rb.Position = UDim2.new(1, -200, 0.5, -20)
		end
		section(c, "📦 Склад")
		local card = UI.card(c, 56)
		UI.label(card, string.format("Уровень склада %d/%d • вместимость %d", r.storageLevel, Equipment.StorageMaxLevel, r.storageCap), 15, { sizeUDim = UDim2.new(1, -210, 1, 0) }).Position = UDim2.fromOffset(10, 0)
		local maxed = r.storageLevel >= Equipment.StorageMaxLevel
		local b = UI.button(card, maxed and "Максимум" or ("Расширить " .. money(Equipment.storageUpgradeCost(r.storageLevel + 1))), maxed and T.card or T.good, function()
			UI.request(Net, "UpgradeStorage", {})
		end, { size = UDim2.fromOffset(190, 40), disabled = maxed, textSize = 14 })
		b.Position = UDim2.new(1, -200, 0.5, -20)
	elseif win.tab == "rating" then
		local nextStar = r.stars + 1
		if nextStar > 5 then
			UI.label(c, "🌟 Ваш ресторан — элитный, 5 звёзд! Поддерживайте репутацию и украшайте остров.", 18, { auto = true, color = T.gold })
			return
		end
		local lvl = Stars.Levels[nextStar]
		UI.label(c, string.format("Следующий уровень: <font color='#FFCD46'>%s</font> <b>%s</b>\n%s", string.rep("★", nextStar), lvl.name, lvl.desc), 17, { auto = true })
		UI.label(c, "Звезду нельзя купить — нужно выполнить все условия, после чего оплатить взнос из бюджета.", 14, { color = T.sub, auto = true })
		for _, row in ipairs(r.promotion or {}) do
			local card = UI.card(c, 40, { color = row.ok and Color3.fromRGB(38, 70, 56) or T.card })
			local have = row.key == "satisfaction" and string.format("%d%%", row.have * 100) or (row.key == "fee" and money(row.have) or tostring(math.floor(row.have)))
			local need = row.key == "satisfaction" and string.format("%d%%", row.need * 100) or (row.key == "fee" and money(row.need) or tostring(row.need))
			UI.label(card, (row.ok and "✅ " or "❌ ") .. row.label .. ":  <b>" .. have .. "</b> / " .. need, 15, { sizeUDim = UDim2.new(1, -20, 1, 0) }).Position = UDim2.fromOffset(10, 0)
		end
		if State.isOwner() then
			UI.button(c, r.canPromote and ("🌟 Повысить до " .. nextStar .. "★") or "Условия не выполнены", r.canPromote and T.gold or T.card, function()
				UI.request(Net, "PromoteStar", {})
			end, { size = UDim2.fromOffset(300, 48), disabled = not r.canPromote, textColor = r.canPromote and Color3.fromRGB(40, 30, 10) or nil, disabledText = "Выполните все условия" })
		else
			UI.label(c, "Повысить рейтинг может владелец.", 14, { color = T.sub })
		end
	end
end

-- ===================== BUILD CATALOG =====================
local function renderBuild(c, win)
	local r = State.restaurant
	if not r then
		UI.label(c, "Вы не в ресторане.", 15, { color = T.sub })
		return
	end
	local kind = win.tab == "island" and "decor" or "furniture"
	local cat = kind == "decor" and Decor or Furniture
	UI.label(c, string.format("🏦 Бюджет: <b>%s</b>  •  Красота: <b>%d</b>  •  %s", money(r.budget), (r.metrics and r.metrics.interior) or 0,
		kind == "decor" and "Украшайте свой остров (только в его пределах)." or "Мебель ставится внутри зала. Столы = места для гостей."), 14, { auto = true })
	local row = UI.row(c, 44)
	UI.button(row, "✋ Переместить / удалить", T.purple, function()
		UI.close("build")
		if Menus.onBuildEdit then
			Menus.onBuildEdit(kind)
		end
	end, { size = UDim2.fromOffset(240, 40), textSize = 14 })
	UI.label(row, "ПК: R — поворот, ЛКМ — поставить, Q/Esc — выход", 13, { color = T.sub, sizeUDim = UDim2.fromOffset(380, 40) })
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = c })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 128), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, def in ipairs(cat.List) do
		local locked = def.stars > r.stars
		local cell = UI.new("Frame", { BackgroundColor3 = locked and Color3.fromRGB(36, 40, 60) or T.card, LayoutOrder = i, Parent = grid })
		UI.corner(cell, 10)
		UI.stroke(cell, Color3.new(1, 1, 1), 1, 0.9)
		local catIcon = ""
		for _, cc in ipairs(cat.Categories) do
			if cc.id == def.cat then
				catIcon = cc.icon
			end
		end
		UI.label(cell, catIcon, 30, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 36) }).Position = UDim2.fromOffset(0, 4)
		UI.label(cell, def.name, 13, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, -8, 0, 32) }).Position = UDim2.fromOffset(4, 38)
		UI.label(cell, money(def.price) .. "  ✨" .. def.beauty .. (def.seats and ("  🪑" .. #def.seats) or ""), 12, { color = T.sub, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 18) }).Position = UDim2.fromOffset(0, 70)
		local b = UI.button(cell, locked and ("🔒 " .. def.stars .. "★") or "Купить и поставить", locked and T.card or T.good, function()
			UI.close("build")
			if Menus.onBuildSelect then
				Menus.onBuildSelect(kind, def.id)
			end
		end, { size = UDim2.new(1, -16, 0, 30), disabled = locked, textSize = 12, disabledText = "Откроется на " .. def.stars .. "★" })
		b.Position = UDim2.new(0, 8, 1, -36)
	end
end

-- ===================== ISLAND =====================
local function renderIsland(c)
	local r = State.restaurant
	local w = State.world
	if r then
		section(c, "🏝️ " .. r.theme)
		UI.label(c, string.format("Декораций на острове: <b>%d</b>  •  Общая красота: <b>%d</b>  •  Вертолётная площадка: %s", #r.decor, (r.metrics and r.metrics.interior) or 0, r.helipad and "✅" or "❌"), 15, { auto = true })
		local row = UI.row(c, 44)
		UI.button(row, "🔨 Украсить остров", T.good, function()
			local win = UI.windows.build
			win.tab = "island"
			UI.open("build")
		end, { size = UDim2.fromOffset(200, 40) })
		UI.button(row, "🏠 Вернуться домой", T.blue, function()
			UI.request(Net, "GoHome", {})
		end, { size = UDim2.fromOffset(200, 40) })
	else
		UI.button(c, "🏝️ Выбрать остров", T.accent, function()
			UI.open("lobby")
		end, { size = UDim2.fromOffset(220, 40) })
	end
	section(c, "🗺️ Посетить другие острова")
	UI.label(c, "Летайте на вертолёте или воспользуйтесь паромом ($" .. Config.FerryTicket .. "). Закрытые барьером острова недоступны.", 14, { color = T.sub, auto = true })
	if not w then
		return
	end
	for _, isl in ipairs(w.islands) do
		local card = UI.card(c, 50)
		local text = isl.owned and string.format("<b>%d. %s</b> — «%s» (%s) %s %s", isl.index, isl.theme, isl.name, isl.ownerName, string.rep("★", isl.stars or 1), isl.barrierOn and "🛡️ закрыт" or "🟢 открыт")
			or string.format("<b>%d. %s</b> — свободен", isl.index, isl.theme)
		UI.label(card, text, 14, { sizeUDim = UDim2.new(1, -150, 1, 0) }).Position = UDim2.fromOffset(10, 0)
		if isl.index ~= State.myIsland() then
			local b = UI.button(card, "⛴️ Посетить", T.blue, function()
				UI.request(Net, "Visit", { island = isl.index })
			end, { size = UDim2.fromOffset(130, 36), disabled = isl.barrierOn == true, textSize = 14, disabledText = "Остров закрыт барьером" })
			b.Position = UDim2.new(1, -140, 0.5, -18)
		end
	end
end

-- ===================== HELICOPTER =====================
local function renderHeli(c)
	local p = State.player
	local r = State.restaurant
	if not p then
		return
	end
	local stars = r and r.stars or p.savedStars or 1
	UI.label(c, string.format("Вертолёты открываются на <b>%d★</b> и требуют вертолётную площадку на острове (Строительство → Остров → Транспорт). Покупка — за личные деньги (%s).", Config.HelicopterUnlockStars, money(p.money)), 14, { auto = true, color = T.sub })
	for _, h in ipairs(Helicopters.List) do
		local owned = p.helicopters.owned[h.id]
		local equipped = p.helicopters.equipped == h.id
		local locked = stars < h.stars
		local card = UI.card(c, 84)
		local swatch = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(h.body[1], h.body[2], h.body[3]), Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(12, 12), Parent = card })
		UI.corner(swatch, 30)
		UI.label(swatch, "🚁", 30, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromScale(1, 1) })
		UI.label(card, string.format("<b>%s</b>  %s\nСкорость %d • Набор высоты %d • Управляемость %.1f", h.name, h.desc, h.speed, h.climb, h.turn), 15, { sizeUDim = UDim2.new(1, -300, 1, 0) }).Position = UDim2.fromOffset(84, 0)
		local text, color, disabled
		if equipped then
			text, color, disabled = "✓ Выбран", T.good, true
		elseif owned then
			text, color = "Выбрать", T.blue
		elseif locked then
			text, color, disabled = "🔒 " .. h.stars .. "★", T.card, true
		else
			text, color = "Купить " .. money(h.price), T.gold
		end
		local b = UI.button(card, text, color, function()
			UI.request(Net, "BuyHelicopter", { id = h.id })
		end, { size = UDim2.fromOffset(190, 42), disabled = disabled, textColor = color == T.gold and Color3.fromRGB(40, 30, 10) or nil })
		b.Position = UDim2.new(1, -200, 0.5, -21)
	end
	local row = UI.row(c, 50)
	UI.button(row, "🛫 Вызвать вертолёт на площадку", T.good, function()
		if UI.request(Net, "SpawnHelicopter", {}, "Вертолёт ждёт на площадке. Сядьте в кресло пилота!").ok then
			UI.close("heli")
		end
	end, { size = UDim2.fromOffset(300, 44) })
	UI.button(row, "Убрать вертолёт", T.bad, function()
		UI.request(Net, "DespawnHelicopter", {})
	end, { size = UDim2.fromOffset(180, 44) })
	UI.label(c, "Управление: W/S — вперёд/назад, A/D — поворот, Пробел — вверх, Shift/Ctrl — вниз, прыжок — выйти. На телефоне — экранные кнопки.", 14, { color = T.sub, auto = true })
end

-- ===================== BARRIER =====================
local function renderBarrier(c)
	local r = State.restaurant
	if not r then
		UI.label(c, "Вы не в ресторане.", 15, { color = T.sub })
		return
	end
	local isOwner = State.isOwner()
	local status = UI.card(c, 90, { color = r.barrierOn and Color3.fromRGB(40, 60, 110) or T.card })
	UI.label(status, r.barrierOn and "🛡️ <b>Барьер ВКЛЮЧЁН</b>\nЧужие игроки и вертолёты не могут попасть на остров и в ресторан." or "🟢 <b>Барьер выключен</b>\nДругие игроки могут прилетать, посещать ресторан и покупать еду.", 16, { sizeUDim = UDim2.new(1, -230, 1, 0) }).Position = UDim2.fromOffset(12, 0)
	if isOwner then
		local b = UI.button(status, r.barrierOn and "Выключить" or "Включить барьер", r.barrierOn and T.bad or T.good, function()
			UI.request(Net, "SetBarrier", { on = not r.barrierOn })
		end, { size = UDim2.fromOffset(200, 46) })
		b.Position = UDim2.new(1, -212, 0.5, -23)
	else
		UI.label(c, "Барьером управляет владелец острова.", 14, { color = T.sub })
	end
	section(c, "✅ Разрешённые игроки (могут входить при включённом барьере)")
	local allowed = {}
	for _, e in ipairs(r.whitelist) do
		allowed[e.userId] = true
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not (r.friend and r.friend.userId == other.UserId) then
			local card = UI.card(c, 46)
			UI.label(card, "<b>" .. other.DisplayName .. "</b>" .. (allowed[other.UserId] and "  <font color='#7CE08A'>доступ разрешён</font>" or ""), 15, { sizeUDim = UDim2.new(1, -170, 1, 0) }).Position = UDim2.fromOffset(10, 0)
			if isOwner then
				local b = UI.button(card, allowed[other.UserId] and "Запретить" or "Разрешить", allowed[other.UserId] and T.bad or T.good, function()
					UI.request(Net, "SetWhitelist", { userId = other.UserId, allow = not allowed[other.UserId] })
				end, { size = UDim2.fromOffset(140, 34), textSize = 14 })
				b.Position = UDim2.new(1, -150, 0.5, -17)
			end
		end
	end
	for _, e in ipairs(r.whitelist) do
		if not Players:GetPlayerByUserId(e.userId) then
			local card = UI.card(c, 46)
			UI.label(card, e.name .. " <font color='#A5AFD2'>(не в сети)</font>", 15, { sizeUDim = UDim2.new(1, -170, 1, 0) }).Position = UDim2.fromOffset(10, 0)
			if isOwner then
				local b = UI.button(card, "Запретить", T.bad, function()
					UI.request(Net, "SetWhitelist", { userId = e.userId, allow = false })
				end, { size = UDim2.fromOffset(140, 34), textSize = 14 })
				b.Position = UDim2.new(1, -150, 0.5, -17)
			end
		end
	end
end

-- ===================== ROBUX STORE =====================
local function renderStore(c)
	local p = State.player
	if not p then
		return
	end
	section(c, "🎫 Game Pass (навсегда)")
	for _, key in ipairs({ "Chef", "Director" }) do
		local owned = p.passes[key]
		local title = key == "Chef" and "👨‍🍳 Шеф-повар — 80 R$" or "🎩 Директор ресторана — 100 R$"
		local desc = key == "Chef" and "NPC-повар готовит за вас, фирменные рецепты, +10% качества." or "Найм NPC-персонала, зарплаты, полный контроль ресторана."
		local card = UI.card(c, 64)
		UI.label(card, "<b>" .. title .. "</b>\n<font color='#A5AFD2'>" .. desc .. "</font>", 15, { sizeUDim = UDim2.new(1, -220, 1, 0) }).Position = UDim2.fromOffset(10, 0)
		local b = UI.button(card, owned and "✓ Куплено" or "Купить", owned and T.good or T.gold, function()
			local id = p.passes[key .. "Id"]
			if not id or id == 0 then
				UI.toast("Game Pass не настроен (Config.GamePasses." .. key .. ")", "warn")
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, id)
		end, { size = UDim2.fromOffset(190, 42), disabled = owned, textColor = not owned and Color3.fromRGB(40, 30, 10) or nil })
		b.Position = UDim2.new(1, -200, 0.5, -21)
	end
	section(c, "💰 Игровая валюта и множители")
	if p.boost and p.boost.remaining > 0 then
		UI.label(c, string.format("⚡ Активен множитель x%d — осталось %s", p.boost.mult, Util.formatTime(p.boost.remaining)), 16, { color = T.gold })
	end
	for _, prod in ipairs(p.products or {}) do
		local card = UI.card(c, 56)
		local desc = prod.kind == "cash" and ("+" .. money(prod.amount) .. " на личный баланс") or ("Множитель заработка x" .. prod.mult .. " на " .. prod.minutes .. " мин")
		UI.label(card, "<b>" .. prod.title .. "</b>  <font color='#A5AFD2'>" .. desc .. "</font>", 15, { sizeUDim = UDim2.new(1, -220, 1, 0) }).Position = UDim2.fromOffset(10, 0)
		local b = UI.button(card, "💎 " .. prod.robux .. " R$", T.gold, function()
			if prod.id == 0 then
				if p.passes and p.passes.studio then
					UI.request(Net, "StudioTestProduct", { key = prod.key }, "🧪 Studio: тестовая покупка выдана (Robux не списаны)")
				else
					UI.toast("Товар ещё не настроен: создайте Developer Product на сайте Roblox и впишите ID в Config.Products", "warn")
				end
				return
			end
			MarketplaceService:PromptProductPurchase(player, prod.id)
		end, { size = UDim2.fromOffset(190, 40), textColor = Color3.fromRGB(40, 30, 10) })
		b.Position = UDim2.new(1, -200, 0.5, -20)
	end
end

function Menus.build()
	UI.window("shop", "Магазин продуктов", "🛒", { render = renderShop, height = 580 })
	local up = UI.window("upgrades", "Улучшения и рейтинг", "⚙️", { render = renderUpgrades, height = 580 })
	up:setTabs({ { id = "equipment", text = "Оборудование", width = 150 }, { id = "rating", text = "Рейтинг ★", width = 130 } })
	local b = UI.window("build", "Строительство", "🔨", { render = renderBuild, width = 800, height = 600 })
	b:setTabs({ { id = "interior", text = "Интерьер", width = 130 }, { id = "island", text = "Остров", width = 130 } })
	UI.window("island", "Остров", "🏝️", { render = renderIsland })
	UI.window("heli", "Вертолёты", "🚁", { render = renderHeli })
	UI.window("barrier", "Защитный барьер", "🛡️", { render = renderBarrier })
	UI.window("store", "Магазин Robux", "💎", { render = renderStore })
end

return Menus
