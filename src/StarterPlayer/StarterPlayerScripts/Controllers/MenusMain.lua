-- Main menus: lobby, restaurant, professions, team/invites, staff, quests,
-- achievements, statistics.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = Shared.Data
local Professions = require(Data.Professions)
local Recipes = require(Data.Recipes)
local Stars = require(Data.Stars)
local Staff = require(Data.Staff)
local Quests = require(Data.Quests)
local Guests = require(Data.Guests)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local Menus = {}
local player = Players.LocalPlayer
local money = Util.formatMoney

local function stars(n)
	return string.rep("★", n) .. string.rep("☆", 5 - n)
end

local function section(parent, text, order)
	local l = UI.label(parent, text, 18, { font = UI.Font, color = T.accent, order = order })
	return l
end

local function emptyNote(parent, text)
	UI.label(parent, text, 15, { color = T.sub, auto = true })
end

-- ===================== LOBBY (no restaurant yet) =====================
local function renderLobby(c)
	local p = State.player
	local world = State.world
	UI.label(c, "Добро пожаловать в <b>Restaurant Island Tycoon</b>! Откройте свой ресторан на свободном острове или присоединитесь к другу.", 16, { auto = true, color = T.sub })
	if p and p.ownsRestaurantData then
		UI.label(c, "💾 Ваш сохранённый ресторан (" .. stars(p.savedStars or 1) .. ") будет восстановлен на выбранном острове.", 15, { auto = true, color = T.good })
	end
	local row = UI.row(c, 48)
	UI.button(row, "🏝️ Открыть ресторан (любой остров)", T.accent, function()
		if UI.request(Net, "ClaimIsland", {}).ok then
			UI.close("lobby")
		end
	end, { size = UDim2.fromOffset(330, 44) })
	if p and #p.invites > 0 then
		section(c, "✉️ Приглашения")
		for _, inv in ipairs(p.invites) do
			local card = UI.card(c, 56)
			UI.label(card, "<b>" .. inv.from .. "</b> зовёт в «" .. inv.restaurant .. "» (" .. inv.t .. " с)", 15, { sizeUDim = UDim2.new(1, -260, 1, 0) }).Position = UDim2.fromOffset(12, 0)
			local a = UI.button(card, "Принять", T.good, function()
				if UI.request(Net, "AcceptInvite", { island = inv.island }).ok then
					UI.close("lobby")
				end
			end, { size = UDim2.fromOffset(110, 36) })
			a.Position = UDim2.new(1, -240, 0.5, -18)
			local d = UI.button(card, "Отклонить", T.bad, function()
				UI.request(Net, "DeclineInvite", { island = inv.island })
			end, { size = UDim2.fromOffset(110, 36) })
			d.Position = UDim2.new(1, -122, 0.5, -18)
		end
	end
	section(c, "🗺️ Острова сервера")
	if not world then
		return
	end
	for _, isl in ipairs(world.islands) do
		local card = UI.card(c, 58)
		local text
		if isl.owned then
			text = string.format("<b>%d. %s</b>  —  «%s» (%s)  %s  👥 %d/2", isl.index, isl.theme, isl.name or "", isl.ownerName or "", stars(isl.stars or 1), isl.members or 1)
		else
			text = string.format("<b>%d. %s</b>  —  <font color='#7CE08A'>свободен</font>", isl.index, isl.theme)
		end
		UI.label(card, text, 15, { sizeUDim = UDim2.new(1, -200, 1, 0) }).Position = UDim2.fromOffset(12, 0)
		local btn
		if not isl.owned then
			btn = UI.button(card, "Занять", T.good, function()
				if UI.request(Net, "ClaimIsland", { index = isl.index }).ok then
					UI.close("lobby")
				end
			end, { size = UDim2.fromOffset(170, 38) })
		elseif isl.friendSlot then
			btn = UI.button(card, "Попросить вступить", T.purple, function()
				UI.request(Net, "RequestJoin", { island = isl.index }, "Запрос отправлен владельцу")
			end, { size = UDim2.fromOffset(170, 38), textSize = 14 })
		end
		if btn then
			btn.Position = UDim2.new(1, -182, 0.5, -19)
		end
	end
end

-- ===================== RESTAURANT =====================
local function renderRestaurant(c, win)
	local r = State.restaurant
	if not r then
		emptyNote(c, "Вы пока не в ресторане.")
		return
	end
	local isOwner = State.isOwner()
	local canManage = isOwner or State.role() == "Director"
	if win.tab == "overview" then
		local head = UI.card(c, 110)
		UI.label(head, "<b>" .. r.name .. "</b>", 24, { font = UI.Font, sizeUDim = UDim2.new(1, -20, 0, 32) }).Position = UDim2.fromOffset(14, 8)
		UI.label(head, "<font color='#FFCD46'>" .. stars(r.stars) .. "</font>  " .. Stars.Levels[r.stars].name .. "  •  " .. r.theme, 16, { sizeUDim = UDim2.new(1, -20, 0, 24) }).Position = UDim2.fromOffset(14, 42)
		UI.label(head, string.format("🏦 Бюджет: <b>%s</b>   ⭐ Репутация: <b>%d</b>   🧽 Чистота: <b>%d%%</b>", money(r.budget), math.floor(r.reputation), math.floor(r.cleanliness)), 15, { sizeUDim = UDim2.new(1, -20, 0, 24) }).Position = UDim2.fromOffset(14, 72)

		local live = r.live or {}
		local k = r.kitchen or {}
		section(c, "📡 Сейчас в ресторане")
		local liveCard = UI.card(c, 64)
		UI.label(liveCard, string.format("👥 Гостей: %d   📋 Ждут заказ: %d   ⏳ Ждут еду: %d   🍽️ Едят: %d   🧹 Грязных столов: %d\n🔥 Кухня: %d   🥤 Бар: %d   ✅ На раздаче: %d   🪑 Мест: %d%s%s",
			live.guests or 0, live.waitOrder or 0, live.waitFood or 0, live.eating or 0, live.dirtyTables or 0,
			k.dishQueue or 0, k.drinkQueue or 0, k.pass or 0, live.seats or 0,
			k.autoKitchen and "   ⚙️ автокухня" or "", k.autoBar and "   ⚙️ автобар" or ""), 14, { sizeUDim = UDim2.new(1, -20, 1, 0) }).Position = UDim2.fromOffset(12, 0)
		local evs = {}
		for id, e in pairs(r.events or {}) do
			local names = { rush = "🏃 Час пик", sale = "🏷️ Распродажа", special = "⭐ Особый заказ", festival = "🎉 Фестиваль" }
			if names[id] then
				table.insert(evs, names[id] .. (e.remaining > 0 and (" (" .. Util.formatTime(e.remaining) .. ")") or ""))
			end
		end
		if #evs > 0 then
			UI.label(c, "События: " .. table.concat(evs, "   "), 15, { color = T.warn, auto = true })
		end

		section(c, "💰 Общий счёт ресторана")
		local row = UI.row(c, 44)
		local box = UI.textbox(row, "Сумма", { size = UDim2.fromOffset(140, 38) })
		UI.button(row, "Внести", T.good, function()
			UI.request(Net, "Deposit", { amount = tonumber(box.Text) or 0 }, "Деньги внесены в бюджет")
		end, { size = UDim2.fromOffset(110, 38) })
		if isOwner then
			UI.button(row, "Вывести (−10%)", T.warn, function()
				local res = UI.request(Net, "Withdraw", { amount = tonumber(box.Text) or 0 })
				if res.ok then
					UI.toast("Получено " .. money(res.received), "success")
				end
			end, { size = UDim2.fromOffset(150, 38) })
			UI.button(row, r.friendCanSpend and "Друг: может тратить ✓" or "Друг: не может тратить", r.friendCanSpend and T.good or T.card, function()
				UI.request(Net, "SetFriendSpend", { allow = not r.friendCanSpend })
			end, { size = UDim2.fromOffset(220, 38), textSize = 14 })
		end
		if isOwner then
			section(c, "✏️ Название")
			local row2 = UI.row(c, 44)
			local nameBox = UI.textbox(row2, "Новое название", { size = UDim2.fromOffset(300, 38), text = r.name })
			UI.button(row2, "Переименовать", T.blue, function()
				UI.request(Net, "RenameRestaurant", { name = nameBox.Text }, "Название обновлено")
			end, { size = UDim2.fromOffset(160, 38) })
			UI.button(row2, "Закрыть ресторан", T.bad, function()
				UI.request(Net, "ReleaseIsland", {}, "Ресторан сохранён и закрыт")
			end, { size = UDim2.fromOffset(170, 38), textSize = 14 })
		end
		if isOwner and State.player and State.player.passes and State.player.passes.studio then
			UI.button(c, "🧪 Studio: ускорить тест (+100 гостей, +$250k, репутация)", T.purple, function()
				UI.request(Net, "DebugBoost", {}, "Тестовые показатели добавлены")
			end, { size = UDim2.fromOffset(460, 36), textSize = 13 })
		end
	elseif win.tab == "menu" then
		UI.label(c, canManage and "Включайте блюда и задавайте наценку. Высокая цена = больше прибыли, но меньше заказов и ниже удовлетворённость." or "Меню управляет владелец или директор.", 14, { color = T.sub, auto = true })
		local ctx = { chefActive = r.chefActive }
		for _, recipe in ipairs(Recipes.List) do
			local avail, why = Recipes.isAvailable(recipe, r, ctx)
			local m = r.menu[recipe.id] or { on = true, price = 1 }
			local card = UI.card(c, 50)
			local price = math.floor(recipe.price * m.price + 0.5)
			local margin = price - recipe.cost
			local inStock = Recipes.hasStock(recipe, r.inventory)
			local text = string.format("%s <b>%s</b>  <font color='#A5AFD2'>себест. %s • цена %s • маржа %s</font>%s",
				recipe.icon, recipe.name, money(recipe.cost), money(price), money(margin),
				not avail and ("  <font color='#EB5555'>" .. why .. "</font>") or (not inStock and "  <font color='#F5BE3C'>нет продуктов</font>" or ""))
			UI.label(card, text, 14, { sizeUDim = UDim2.new(1, -330, 1, 0) }).Position = UDim2.fromOffset(10, 0)
			if canManage then
				local minus = UI.button(card, "−", T.card, function()
					UI.request(Net, "SetMenu", { id = recipe.id, price = m.price - 0.1 })
				end, { size = UDim2.fromOffset(34, 34) })
				minus.Position = UDim2.new(1, -316, 0.5, -17)
				local pl = UI.label(card, string.format("x%.2f", m.price), 14, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromOffset(60, 34) })
				pl.Position = UDim2.new(1, -280, 0.5, -17)
				local plus = UI.button(card, "+", T.card, function()
					UI.request(Net, "SetMenu", { id = recipe.id, price = m.price + 0.1 })
				end, { size = UDim2.fromOffset(34, 34) })
				plus.Position = UDim2.new(1, -218, 0.5, -17)
				local tog = UI.button(card, m.on and "В меню ✓" or "Выключено", m.on and T.good or T.bad, function()
					UI.request(Net, "SetMenu", { id = recipe.id, on = not m.on })
				end, { size = UDim2.fromOffset(120, 34), textSize = 14 })
				tog.Position = UDim2.new(1, -176, 0.5, -17)
			end
		end
	elseif win.tab == "reviews" then
		local st = r.stats
		local avg = st.reviewCount > 0 and st.reviewSum / st.reviewCount or 0
		UI.label(c, string.format("Средняя оценка: <b>%.1f★</b> (%d отзывов)  •  Еда %d%%  Сервис %d%%  Скорость %d%%  Цена %d%%  Атмосфера %d%%",
			avg, st.reviewCount, st.foodEma * 100, st.serviceEma * 100, st.speedEma * 100, st.priceEma * 100, st.interiorEma * 100), 15, { auto = true })
		if #r.reviews == 0 then
			emptyNote(c, "Отзывов пока нет — обслужите первых гостей!")
		end
		for _, rv in ipairs(r.reviews) do
			local g = Guests.ById[rv.g]
			local card = UI.card(c, 62)
			UI.label(card, string.format("%s <b>%s</b> (%s)  <font color='#FFCD46'>%s</font>%s", g and g.icon or "🙂", rv.n or "Гость", g and g.name or "", stars(rv.s), rv.critic and "  📝 КРИТИК" or ""), 15, { sizeUDim = UDim2.new(1, -20, 0, 26) }).Position = UDim2.fromOffset(10, 4)
			UI.label(card, "«" .. rv.txt .. "»  <font color='#A5AFD2'>Еда " .. rv.food .. " • Сервис " .. rv.service .. " • Интерьер " .. rv.interior .. " • Скорость " .. rv.speed .. " • Цена " .. rv.price .. "</font>", 13, { sizeUDim = UDim2.new(1, -20, 0, 26) }).Position = UDim2.fromOffset(10, 32)
		end
	elseif win.tab == "finance" then
		local st = r.stats
		local card = UI.card(c, 110)
		UI.label(card, string.format("Выручка: <b>%s</b>\nРасходы: <b>%s</b> (продукты %s • зарплаты %s • улучшения %s)\nПрибыль: <b>%s</b>   Чаевые: %s\nПродано блюд: %d   напитков: %d   Обслужено гостей: %d   Ушли недовольными: %d",
			money(st.revenue), money(st.expenses), money(st.ingredientCost), money(st.wages), money(st.upgrades), money(st.revenue - st.expenses), money(st.tips),
			st.dishesSold, st.drinksSold, st.served, st.lost), 15, { sizeUDim = UDim2.new(1, -20, 1, -10) }).Position = UDim2.fromOffset(10, 5)
		section(c, "📒 История вкладов и расходов")
		local kinds = { sale = "Продажи", deposit = "Вклад", withdraw = "Вывод", ingredients = "Продукты", wages = "Зарплаты", furniture = "Мебель", decor = "Декор", equipment = "Оборудование", upgrade = "Улучшение", star = "Повышение рейтинга", event = "Событие", contest = "Конкурс", refund = "Возврат", staff = "Персонал" }
		for i, e in ipairs(r.ledger) do
			if i > 40 then
				break
			end
			local color = e.a >= 0 and "#50C878" or "#EB5555"
			UI.label(c, string.format("<font color='#A5AFD2'>%s</font>  %s  <font color='%s'><b>%s</b></font>  %s %s", os.date("%H:%M", e.t), kinds[e.k] or e.k, color, money(e.a), e.w ~= "" and ("— " .. e.w) or "", e.n ~= "" and ("(" .. e.n .. ")") or ""), 14)
		end
	end
end

-- ===================== PROFESSIONS =====================
local function promptPass(key)
	local p = State.player
	local id = p and p.passes and p.passes[key .. "Id"]
	if not id or id == 0 then
		UI.toast("Game Pass ещё не настроен разработчиком (Config.GamePasses." .. key .. ")", "warn")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, id)
end
Menus.promptPass = promptPass

local function renderProfessions(c)
	local r = State.restaurant
	local p = State.player
	if not r or not p then
		emptyNote(c, "Сначала откройте ресторан или вступите в команду.")
		return
	end
	UI.label(c, "В ресторане 4 уникальные должности. Одну должность может занимать только один игрок. Сначала выбирает владелец, затем приглашённый друг.", 14, { color = T.sub, auto = true })
	if not State.isOwner() and r.roles and r.owner and not r.roles.Cook and not r.roles.Waiter and not r.roles.Chef and not r.roles.Director then
		UI.label(c, "⏳ Владелец ещё не выбрал профессию.", 15, { color = T.warn })
	end
	for i, id in ipairs(Professions.Order) do
		local def = Professions.ById[id]
		local holder = r.roles and r.roles[id]
		local mine = p.role == id
		local owned = not def.paid or (p.passes and p.passes[def.pass])
		local card = UI.card(c, 128, { order = i })
		UI.label(card, def.icon .. "  <b>" .. def.name .. "</b>" .. (def.paid and ("  <font color='#FFCD46'>Game Pass " .. def.price .. " R$</font>") or "  <font color='#7CE08A'>бесплатно</font>"), 18, { sizeUDim = UDim2.new(1, -220, 0, 28) }).Position = UDim2.fromOffset(12, 6)
		UI.label(card, def.desc, 14, { color = T.sub, sizeUDim = UDim2.new(1, -220, 0, 40) }).Position = UDim2.fromOffset(12, 34)
		UI.label(card, "• " .. table.concat(def.perks, "  • "), 13, { color = T.accent2, sizeUDim = UDim2.new(1, -220, 0, 40) }).Position = UDim2.fromOffset(12, 78)
		local lvl = p.prof[id]
		local lvlLabel = UI.label(card, "Уровень " .. (lvl and lvl.level or 1), 14, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.fromOffset(190, 20) })
		lvlLabel.Position = UDim2.new(1, -200, 0, 10)
		if lvl then
			UI.progress(card, lvl.xp / math.max(1, lvl.need), T.accent, { size = UDim2.fromOffset(190, 8), position = UDim2.new(1, -200, 0, 34) })
		end
		local btn
		if mine then
			btn = UI.button(card, "✓ Ваша профессия", T.good, nil, { size = UDim2.fromOffset(190, 42) })
		elseif holder and holder.userId ~= player.UserId then
			btn = UI.button(card, "Занято: " .. holder.name, T.card, nil, { size = UDim2.fromOffset(190, 42), disabled = true, textSize = 14, disabledText = "Должность уже занята" })
		elseif not owned then
			btn = UI.button(card, "🔒 Купить за " .. def.price .. " R$", T.gold, function()
				promptPass(def.pass)
			end, { size = UDim2.fromOffset(190, 42), textColor = Color3.fromRGB(40, 30, 10) })
		else
			btn = UI.button(card, "Выбрать", T.blue, function()
				UI.request(Net, "ChooseRole", { role = id })
			end, { size = UDim2.fromOffset(190, 42) })
		end
		btn.Position = UDim2.new(1, -200, 1, -54)
	end
	if p.passes and p.passes.studio then
		UI.label(c, "🧪 Режим Studio: платные профессии доступны для теста (Config.StudioGrantGamePasses).", 13, { color = T.warn, auto = true })
	end
end

-- ===================== TEAM / INVITES =====================
local function renderTeam(c)
	local r = State.restaurant
	local p = State.player
	if not r then
		renderLobby(c)
		return
	end
	local isOwner = State.isOwner()
	section(c, "👥 Команда ресторана (максимум 2 игрока)")
	local ownerCard = UI.card(c, 50)
	UI.label(ownerCard, "👑 Владелец: <b>" .. (r.owner and r.owner.name or "?") .. "</b>   Профессия: " .. ((r.owner and r.roles and (function()
		for role, h in pairs(r.roles) do
			if h and h.userId == r.owner.userId then
				return Professions.ById[role].name
			end
		end
		return "не выбрана"
	end)()) or "?"), 15, { sizeUDim = UDim2.new(1, -20, 1, 0) }).Position = UDim2.fromOffset(12, 0)
	local friendCard = UI.card(c, 50)
	if r.friend then
		UI.label(friendCard, "🤝 Друг: <b>" .. r.friend.name .. "</b>   Профессия: " .. (r.friend.role ~= "" and Professions.ById[r.friend.role].name or "не выбрана"), 15, { sizeUDim = UDim2.new(1, -200, 1, 0) }).Position = UDim2.fromOffset(12, 0)
		if isOwner then
			local kick = UI.button(friendCard, "Удалить из команды", T.bad, function()
				UI.request(Net, "KickFriend", {}, "Участник удалён")
			end, { size = UDim2.fromOffset(180, 36), textSize = 14 })
			kick.Position = UDim2.new(1, -190, 0.5, -18)
		elseif r.friend.userId == player.UserId then
			local leave = UI.button(friendCard, "Покинуть ресторан", T.bad, function()
				UI.request(Net, "LeaveTeam", {})
			end, { size = UDim2.fromOffset(180, 36), textSize = 14 })
			leave.Position = UDim2.new(1, -190, 0.5, -18)
		end
	else
		UI.label(friendCard, "🤝 Место друга свободно", 15, { color = T.sub, sizeUDim = UDim2.new(1, -20, 1, 0) }).Position = UDim2.fromOffset(12, 0)
	end
	if not isOwner then
		return
	end
	if #r.joinRequests > 0 then
		section(c, "🙋 Запросы на вступление")
		for _, req in ipairs(r.joinRequests) do
			local card = UI.card(c, 50)
			UI.label(card, "<b>" .. req.name .. "</b> хочет присоединиться", 15, { sizeUDim = UDim2.new(1, -260, 1, 0) }).Position = UDim2.fromOffset(12, 0)
			local a = UI.button(card, "Принять", T.good, function()
				UI.request(Net, "AnswerJoin", { userId = req.userId, accept = true })
			end, { size = UDim2.fromOffset(110, 36) })
			a.Position = UDim2.new(1, -236, 0.5, -18)
			local d = UI.button(card, "Отклонить", T.bad, function()
				UI.request(Net, "AnswerJoin", { userId = req.userId, accept = false })
			end, { size = UDim2.fromOffset(110, 36) })
			d.Position = UDim2.new(1, -120, 0.5, -18)
		end
	end
	if #r.pendingInvites > 0 then
		section(c, "📨 Отправленные приглашения")
		for _, inv in ipairs(r.pendingInvites) do
			local card = UI.card(c, 50)
			UI.label(card, "<b>" .. inv.name .. "</b> — ожидает ответа (" .. inv.t .. " с)", 15, { sizeUDim = UDim2.new(1, -150, 1, 0) }).Position = UDim2.fromOffset(12, 0)
			local cancel = UI.button(card, "Отменить", T.bad, function()
				UI.request(Net, "CancelInvite", { userId = inv.userId })
			end, { size = UDim2.fromOffset(120, 36) })
			cancel.Position = UDim2.new(1, -130, 0.5, -18)
		end
	end
	if r.friend then
		return
	end
	section(c, "✉️ Пригласить друга")
	if p.role == "" then
		UI.label(c, "Сначала выберите свою профессию — после этого можно приглашать.", 14, { color = T.warn, auto = true })
		return
	end
	local busy = {}
	if State.world then
		for _, isl in ipairs(State.world.islands) do
			if isl.ownerId then
				busy[isl.ownerId] = true
			end
		end
	end
	local any = false
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not busy[other.UserId] then
			any = true
			local card = UI.card(c, 50)
			UI.label(card, "<b>" .. other.DisplayName .. "</b> (@" .. other.Name .. ")", 15, { sizeUDim = UDim2.new(1, -170, 1, 0) }).Position = UDim2.fromOffset(12, 0)
			local inv = UI.button(card, "Пригласить", T.purple, function()
				UI.request(Net, "Invite", { userId = other.UserId }, "Приглашение отправлено")
			end, { size = UDim2.fromOffset(140, 36) })
			inv.Position = UDim2.new(1, -150, 0.5, -18)
		end
	end
	if not any then
		emptyNote(c, "Нет игроков без ресторана. Владельцы других ресторанов не могут вступить в ваш (у каждого свой).")
	end
end

-- ===================== STAFF =====================
local function renderStaff(c)
	local r = State.restaurant
	if not r then
		emptyNote(c, "Вы не в ресторане.")
		return
	end
	local isDirector = State.role() == "Director"
	local isChef = State.role() == "Chef"
	local slots = Stars.Levels[r.stars].staffSlots
	local hired = 0
	for _, m in ipairs(r.staff) do
		if not m.isChef then
			hired += 1
		end
	end
	UI.label(c, string.format("Сотрудники: <b>%d/%d</b> (лимит растёт с рейтингом). Зарплата списывается из бюджета каждую минуту.", hired, slots), 15, { auto = true })
	if isDirector then
		local row = UI.row(c, 46)
		for _, role in ipairs({ "Cook", "Waiter", "Bartender" }) do
			local def = Staff.Roles[role]
			UI.button(row, "Нанять " .. def.icon .. " " .. def.name .. " (" .. money(def.hireCost) .. ")", T.blue, function()
				UI.request(Net, "HireStaff", { role = role })
			end, { size = UDim2.fromOffset(230, 42), textSize = 13 })
		end
	elseif isChef then
		UI.label(c, "👨‍🍳 Вы шеф-повар: ваш NPC-повар (Су-шеф) готовит заказы. Обучайте его, чтобы он работал быстрее и качественнее.", 14, { color = T.accent2, auto = true })
	else
		UI.label(c, "Нанимать и управлять персоналом может игрок с профессией «Директор ресторана».", 14, { color = T.sub, auto = true })
	end
	if #r.staff == 0 then
		emptyNote(c, "Персонала пока нет.")
	end
	local stateNames = { idle = "ожидает", cooking = "готовит", order = "принимает заказ", serve = "разносит", clean = "убирает", off = "не на смене" }
	for _, m in ipairs(r.staff) do
		local def = Staff.Roles[m.role]
		local card = UI.card(c, 92)
		UI.label(card, string.format("%s <b>%s</b> — %s%s  •  <font color='#FFCD46'>%s (ур. %d)</font>", def.icon, m.name, def.name, m.isChef and " шефа" or "", m.levelName, m.level), 16, { sizeUDim = UDim2.new(1, -330, 0, 26) }).Position = UDim2.fromOffset(12, 6)
		UI.label(card, string.format("Зарплата %s/мин (x%.1f) • Мотивация %d%% • Сейчас: %s", money(m.wage), m.wageMult or 1, math.floor((m.morale or 1) * 100), stateNames[m.state] or m.state), 13, { color = T.sub, sizeUDim = UDim2.new(1, -330, 0, 22) }).Position = UDim2.fromOffset(12, 34)
		if m.xpNeed > 0 then
			UI.label(card, string.format("Опыт: %d / %d • Обучение: %s", math.floor(m.xp), m.xpNeed, money(m.trainCost)), 13, { color = T.sub, sizeUDim = UDim2.new(1, -330, 0, 20) }).Position = UDim2.fromOffset(12, 56)
			UI.progress(card, m.xp / m.xpNeed, T.accent, { size = UDim2.new(1, -360, 0, 6), position = UDim2.fromOffset(12, 78) })
		else
			UI.label(card, "Максимальный уровень — Мастер", 13, { color = T.gold, sizeUDim = UDim2.new(1, -330, 0, 20) }).Position = UDim2.fromOffset(12, 56)
		end
		if isDirector or (isChef and m.isChef) then
			local train = UI.button(card, "🎓 Обучить", T.good, function()
				UI.request(Net, "TrainStaff", { uid = m.uid })
			end, { size = UDim2.fromOffset(110, 34), textSize = 14 })
			train.Position = UDim2.new(1, -320, 0, 10)
		end
		if isDirector and not m.isChef then
			local minus = UI.button(card, "З/П −", T.card, function()
				UI.request(Net, "SetWage", { uid = m.uid, mult = (m.wageMult or 1) - 0.1 })
			end, { size = UDim2.fromOffset(64, 34), textSize = 13 })
			minus.Position = UDim2.new(1, -202, 0, 10)
			local plus = UI.button(card, "З/П +", T.card, function()
				UI.request(Net, "SetWage", { uid = m.uid, mult = (m.wageMult or 1) + 0.1 })
			end, { size = UDim2.fromOffset(64, 34), textSize = 13 })
			plus.Position = UDim2.new(1, -132, 0, 10)
			local fire = UI.button(card, "Уволить", T.bad, function()
				UI.request(Net, "FireStaff", { uid = m.uid })
			end, { size = UDim2.fromOffset(110, 30), textSize = 13 })
			fire.Position = UDim2.new(1, -120, 0, 52)
		end
	end
end

-- ===================== QUESTS =====================
local function renderQuests(c)
	local p = State.player
	if not p then
		return
	end
	local d = p.daily
	section(c, "🎁 Ежедневная награда")
	local card = UI.card(c, 64)
	local days = {}
	local completed = (d.streak or 0) % 7
	if not d.canClaim and completed == 0 and (d.streak or 0) > 0 then
		completed = 7
	end
	for i, v in ipairs(d.rewards or {}) do
		local mark = i <= completed and "✅" or "▫️"
		table.insert(days, mark .. "Д" .. i .. ":$" .. v)
	end
	UI.label(card, table.concat(days, "  "), 13, { sizeUDim = UDim2.new(1, -200, 1, 0) }).Position = UDim2.fromOffset(10, 0)
	local claim = UI.button(card, d.canClaim and ("Забрать $" .. (d.nextReward or 0)) or "Завтра", d.canClaim and T.good or T.card, function()
		UI.request(Net, "ClaimDaily", {})
	end, { size = UDim2.fromOffset(170, 40), disabled = not d.canClaim })
	claim.Position = UDim2.new(1, -180, 0.5, -20)
	local function list(title, quests)
		section(c, title)
		for _, q in ipairs(quests) do
			local qc = UI.card(c, 60)
			UI.label(qc, (q.claimed and "✅ " or "📌 ") .. q.text .. "  <font color='#FFCD46'>+" .. money(q.money) .. " • +" .. q.xp .. " XP</font>", 15, { sizeUDim = UDim2.new(1, -200, 0, 26) }).Position = UDim2.fromOffset(10, 6)
			UI.progress(qc, q.progress / q.goal, q.progress >= q.goal and T.good or T.blue, { size = UDim2.new(1, -220, 0, 10), position = UDim2.fromOffset(10, 38) })
			UI.label(qc, q.progress .. "/" .. q.goal, 13, { sizeUDim = UDim2.fromOffset(80, 20), color = T.sub }).Position = UDim2.new(1, -290, 0, 32)
			local can = q.progress >= q.goal and not q.claimed
			local b = UI.button(qc, q.claimed and "Получено" or (can and "Забрать" or "В процессе"), can and T.good or T.card, function()
				UI.request(Net, "ClaimQuest", { index = q.index, weekly = q.weekly })
			end, { size = UDim2.fromOffset(170, 38), disabled = not can })
			b.Position = UDim2.new(1, -180, 0.5, -19)
		end
	end
	local qs = p.quests or {}
	list("📋 Ежедневные задания (обновление через " .. Util.formatTime(qs.dailyReset or 0) .. ")", qs.daily or {})
	list("🗓️ Еженедельные задания", qs.weekly or {})
end

local function renderAchievements(c)
	local p = State.player
	if not p then
		return
	end
	local done = 0
	for _ in pairs(p.achievements) do
		done += 1
	end
	UI.label(c, string.format("Получено: <b>%d / %d</b>", done, #Quests.Achievements), 16)
	for _, a in ipairs(Quests.Achievements) do
		local got = p.achievements[a.id] ~= nil
		local have = p.stats[a.stat] or 0
		local card = UI.card(c, 56, { color = got and Color3.fromRGB(40, 80, 60) or T.card })
		UI.label(card, a.icon .. "  <b>" .. a.name .. "</b>  <font color='#A5AFD2'>" .. math.min(have, a.goal) .. "/" .. a.goal .. "</font>" .. (a.recipe and "  📜 редкий рецепт" or ""), 15, { sizeUDim = UDim2.new(1, -170, 0, 28) }).Position = UDim2.fromOffset(10, 4)
		UI.progress(card, have / a.goal, got and T.good or T.blue, { size = UDim2.new(1, -190, 0, 8), position = UDim2.fromOffset(10, 38) })
		UI.label(card, got and "✅ Получено" or ("+" .. money(a.money)), 14, { color = got and T.good or T.gold, align = Enum.TextXAlignment.Right, sizeUDim = UDim2.fromOffset(150, 56) }).Position = UDim2.new(1, -160, 0, 0)
	end
end

-- ===================== STATS =====================
local function renderStats(c, win)
	local p = State.player
	if not p then
		return
	end
	if win.tab == "me" then
		local s = p.stats
		local card = UI.card(c, 180)
		UI.label(card, string.format(
			"Уровень игрока: <b>%d</b> (%d/%d XP)\nВсего заработано: <b>%s</b>   Чаевые: %s\nПриготовлено блюд: %d   Напитков: %d\nОбслужено гостей: %d   Принято заказов: %d   Убрано столов: %d\nVIP-гостей: %d   Пройдено критиков: %d\nРазмещено предметов: %d   Время в игре: %s",
			p.level, p.xp, p.xpNeed, money(s.moneyEarned), money(s.tipsEarned), s.dishesCooked, s.drinksMade, s.guestsServed, s.ordersTaken, s.tablesCleaned,
			s.vipServed, s.criticsPassed, s.itemsPlaced, Util.formatTime(s.playSeconds)), 15, { sizeUDim = UDim2.new(1, -20, 1, -10) }).Position = UDim2.fromOffset(10, 5)
		section(c, "🎖️ Уровни профессий")
		for _, id in ipairs(Professions.Order) do
			local pr = p.prof[id]
			local pc = UI.card(c, 44)
			UI.label(pc, Professions.ById[id].icon .. " " .. Professions.ById[id].name .. ": <b>ур. " .. pr.level .. "</b>", 15, { sizeUDim = UDim2.new(0.4, 0, 1, 0) }).Position = UDim2.fromOffset(10, 0)
			UI.progress(pc, pr.xp / math.max(1, pr.need), T.accent, { size = UDim2.new(0.55, 0, 0, 10), position = UDim2.new(0.42, 0, 0.5, -5) })
		end
		section(c, "💵 История доходов")
		for i, e in ipairs(p.income) do
			if i > 20 then
				break
			end
			UI.label(c, string.format("<font color='#A5AFD2'>%s</font>  %s  <font color='%s'>%s</font>", os.date("%H:%M", e.t), e.s, e.a >= 0 and "#50C878" or "#EB5555", money(e.a)), 14)
		end
	elseif win.tab == "contest" then
		local w = State.world
		local contest = w and w.contest
		if not contest then
			return
		end
		UI.label(c, string.format("🏆 Конкурс «Лучший ресторан сервера» — раунд %d, осталось <b>%s</b>. Очки = выручка за раунд + репутация + красота острова.", contest.round, Util.formatTime(contest.remaining)), 15, { auto = true })
		if contest.lastWinner then
			UI.label(c, "🥇 Прошлый победитель: «" .. contest.lastWinner.name .. "» (" .. contest.lastWinner.owner .. ")", 15, { color = T.gold })
		end
		for i, e in ipairs(contest.ranking) do
			local card = UI.card(c, 44)
			UI.label(card, string.format("%s <b>%s</b> (%s) — %d очков • выручка %s • красота %d", i == 1 and "🥇" or (i == 2 and "🥈" or (i == 3 and "🥉" or (i .. "."))), e.name, e.owner, e.score, money(e.revenue), e.beauty), 15, { sizeUDim = UDim2.new(1, -20, 1, 0) }).Position = UDim2.fromOffset(10, 0)
		end
		section(c, "🌍 Глобальный рейтинг: заработок")
		for _, e in ipairs(contest.top and contest.top.earnings or {}) do
			UI.label(c, e.rank .. ". " .. e.name .. " — " .. money(e.value), 14)
		end
		section(c, "🌍 Глобальный рейтинг: звёзды ресторанов")
		for _, e in ipairs(contest.top and contest.top.stars or {}) do
			UI.label(c, e.rank .. ". " .. e.name .. " — " .. stars(math.clamp(e.stars or 1, 1, 5)) .. " (" .. (e.served or 0) .. " гостей)", 14)
		end
	end
end

function Menus.build()
	UI.window("lobby", "Выбор острова", "🏝️", { render = renderLobby, height = 560 })
	local rw = UI.window("restaurant", "Ресторан", "🍽️", { render = renderRestaurant })
	rw:setTabs({ { id = "overview", text = "Обзор" }, { id = "menu", text = "Меню и цены", width = 140 }, { id = "reviews", text = "Отзывы" }, { id = "finance", text = "Финансы" } })
	UI.window("professions", "Профессии", "👔", { render = renderProfessions, height = 600 })
	UI.window("team", "Команда и приглашения", "✉️", { render = renderTeam })
	UI.window("staff", "Персонал", "🧑‍🍳", { render = renderStaff })
	UI.window("quests", "Задания", "📋", { render = renderQuests })
	UI.window("achievements", "Достижения", "🏆", { render = renderAchievements })
	local sw = UI.window("stats", "Статистика", "📊", { render = renderStats })
	sw:setTabs({ { id = "me", text = "Моя статистика", width = 160 }, { id = "contest", text = "Соревнования", width = 160 } })
end

return Menus
