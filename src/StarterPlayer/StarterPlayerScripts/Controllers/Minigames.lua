-- Minigames: cooking & bar mini-games. Each step returns a score 0..1; the list of
-- scores is sent to the server which validates timing and computes dish quality.
-- Steps: chop, prep, grill, boil, bake, assemble, garnish, pour, shake, brew
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Recipes = require(Shared.Data.Recipes)
local Ingredients = require(Shared.Data.Ingredients)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local T = UI.Theme

local Minigames = {}
Minigames.active = false

local rng = Random.new()

-- ===================== SHARED WIDGETS =====================
local function actionButton(parent, text)
	local b = UI.button(parent, text, T.accent, nil, { size = UDim2.fromOffset(260, 56), textSize = 20 })
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -10)
	return b
end

-- fires cb on Space / Enter / button tap; returns disconnect fn
local function onAction(button, cb, holdCb)
	local conns = {}
	table.insert(conns, button.MouseButton1Down:Connect(function()
		cb(true)
	end))
	table.insert(conns, button.MouseButton1Up:Connect(function()
		if holdCb then
			holdCb(false)
		end
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return then
			cb(true)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if holdCb and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return) then
			holdCb(false)
		end
	end))
	return function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end
end

local function bar(parent, y, height)
	local bg = UI.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(18, 20, 32),
		Size = UDim2.new(1, -60, 0, height or 34),
		Position = UDim2.new(0, 30, 0, y),
		Parent = parent,
	})
	UI.corner(bg, 10)
	return bg
end

local function zone(parent, center, width, color)
	local z = UI.new("Frame", {
		BackgroundColor3 = color or T.good,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(width, 0, 1, 0),
		Position = UDim2.new(center, 0, 0, 0),
		Parent = parent,
	})
	UI.corner(z, 8)
	return z
end

local function marker(parent)
	local m = UI.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 8, 1, 14),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 3,
		Parent = parent,
	})
	UI.corner(m, 4)
	return m
end

local function hint(parent, text)
	return UI.label(parent, text, 16, { align = Enum.TextXAlignment.Center, color = T.sub, sizeUDim = UDim2.new(1, -20, 0, 40) })
end

local function feedback(parent, score)
	local text = score >= 0.9 and "ИДЕАЛЬНО!" or (score >= 0.7 and "Отлично!" or (score >= 0.45 and "Неплохо" or "Мимо..."))
	local color = score >= 0.9 and T.gold or (score >= 0.7 and T.good or (score >= 0.45 and T.warn or T.bad))
	local l = UI.label(parent, text, 30, { font = UI.Font, color = color, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 40) })
	l.Position = UDim2.new(0, 0, 0.5, -20)
	l.ZIndex = 10
	local s = UI.new("UIScale", { Scale = 0.5, Parent = l })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- ===================== GAMES =====================
local games = {}

-- Timing bar: marker sweeps, press in the zone (hits times)
local function timingGame(area, ease, done, opts)
	hint(area, opts.hint).Position = UDim2.fromOffset(10, 6)
	local track = bar(area, 70, 40)
	local width = math.clamp(0.14 * ease, 0.1, 0.3)
	local hits, scores = 0, {}
	local zoneCenter = rng:NextNumber(0.25, 0.75)
	local z = zone(track, zoneCenter, width)
	local perfect = zone(track, zoneCenter, width * 0.3, T.gold)
	local m = marker(track)
	local counter = UI.label(area, "", 18, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 26) })
	counter.Position = UDim2.fromOffset(0, 120)
	local t = 0
	local speed = opts.speed or 1.1
	local btn = actionButton(area, opts.button or "НАЖАТЬ")
	local finished = false
	local conn = RunService.RenderStepped:Connect(function(dt)
		t += dt * speed
		local x = (math.sin(t * math.pi) + 1) / 2
		m.Position = UDim2.new(x, 0, 0.5, 0)
	end)
	counter.Text = "0 / " .. opts.hits
	local disconnect
	disconnect = onAction(btn, function()
		if finished then
			return
		end
		local x = m.Position.X.Scale
		local dist = math.abs(x - zoneCenter)
		local s = math.clamp(1 - dist / (width * 1.4), 0, 1)
		table.insert(scores, s)
		hits += 1
		counter.Text = hits .. " / " .. opts.hits
		-- flash
		m.BackgroundColor3 = s > 0.6 and T.good or T.bad
		task.delay(0.15, function()
			m.BackgroundColor3 = Color3.new(1, 1, 1)
		end)
		zoneCenter = rng:NextNumber(0.2, 0.8)
		z.Position = UDim2.new(zoneCenter, 0, 0, 0)
		perfect.Position = UDim2.new(zoneCenter, 0, 0, 0)
		if hits >= opts.hits then
			finished = true
			conn:Disconnect()
			disconnect()
			local sum = 0
			for _, v in ipairs(scores) do
				sum += v
			end
			done(sum / #scores)
		end
	end)
end

games.chop = function(area, ease, done)
	timingGame(area, ease, done, { hint = "🔪 Нарезка: жмите, когда нож над зелёной зоной (3 раза)", hits = 3, button = "РЕЗАТЬ", speed = 1.2 })
end
games.prep = function(area, ease, done)
	timingGame(area, ease, done, { hint = "🥩 Подготовка мяса: отбейте точно в цель (3 раза)", hits = 3, button = "ОТБИТЬ", speed = 1.0 })
end
games.garnish = function(area, ease, done)
	timingGame(area, ease, done, { hint = "🌿 Украшение: положите украшения точно в центр (2 раза)", hits = 2, button = "УКРАСИТЬ", speed = 0.9 })
end

-- Hold to heat: keep the needle inside the zone for a while
local function holdGame(area, ease, done, opts)
	hint(area, opts.hint).Position = UDim2.fromOffset(10, 6)
	local track = bar(area, 70, 40)
	local width = math.clamp(0.22 * ease, 0.16, 0.4)
	local center = opts.center or 0.62
	zone(track, center, width, opts.color)
	local m = marker(track)
	local level, holding, inZone, elapsed = 0.1, false, 0, 0
	local duration = opts.duration or 4
	local prog = UI.progress(area, 0, T.accent2, { size = UDim2.new(1, -60, 0, 8), position = UDim2.fromOffset(30, 126) })
	local btn = actionButton(area, opts.button or "ДЕРЖАТЬ")
	local disconnect = onAction(btn, function()
		holding = true
	end, function()
		holding = false
	end)
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if holding then
			level = math.min(1, level + dt * 0.55)
		else
			level = math.max(0, level - dt * 0.38)
		end
		-- небольшие колебания
		level = math.clamp(level + math.sin(elapsed * 7) * 0.002, 0, 1)
		m.Position = UDim2.new(level, 0, 0.5, 0)
		if math.abs(level - center) <= width / 2 then
			inZone += dt
			m.BackgroundColor3 = T.good
		else
			m.BackgroundColor3 = Color3.new(1, 1, 1)
		end
		prog.Fill.Size = UDim2.fromScale(elapsed / duration, 1)
		if elapsed >= duration then
			conn:Disconnect()
			disconnect()
			done(math.clamp(inZone / (duration * 0.8), 0, 1))
		end
	end)
end

games.grill = function(area, ease, done)
	holdGame(area, ease, done, { hint = "🔥 Жарка: удерживайте огонь в зелёной зоне (держите кнопку / пробел)", button = "ОГОНЬ", center = 0.6 })
end
games.boil = function(area, ease, done)
	-- whack-a-bubble
	hint(area, "🍲 Варка: лопайте пузырьки, пока суп не убежал!").Position = UDim2.fromOffset(10, 6)
	local field = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 60, 90), Size = UDim2.new(1, -60, 0, 170), Position = UDim2.fromOffset(30, 50), Parent = area })
	UI.corner(field, 14)
	local total = 5
	local popped, spawned = 0, 0
	local startT = os.clock()
	local timeLimit = 5.5 * math.clamp(ease, 0.8, 1.6)
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		local timeBonus = math.clamp(1 - (os.clock() - startT) / (timeLimit * 1.5), 0, 0.2)
		done(math.clamp(popped / total + timeBonus, 0, 1))
	end
	local function spawnBubble()
		if finished or spawned >= total then
			return
		end
		spawned += 1
		local b = UI.new("TextButton", {
			Text = "🫧",
			TextSize = 30,
			BackgroundColor3 = Color3.fromRGB(120, 200, 255),
			BackgroundTransparency = 0.3,
			Size = UDim2.fromOffset(54, 54),
			Position = UDim2.new(rng:NextNumber(0.05, 0.85), 0, rng:NextNumber(0.05, 0.6), 0),
			Parent = field,
		})
		UI.corner(b, 27)
		local alive = true
		b.Activated:Connect(function()
			if not alive then
				return
			end
			alive = false
			popped += 1
			UI.click()
			b:Destroy()
			if popped + (spawned - popped) >= total and spawned >= total then
				task.delay(0.2, finish)
			end
			spawnBubble()
		end)
		task.delay(1.6 * math.clamp(ease, 0.8, 1.6), function()
			if alive and b.Parent then
				alive = false
				b:Destroy()
				if spawned >= total then
					task.delay(0.2, finish)
				end
				spawnBubble()
			end
		end)
	end
	spawnBubble()
	task.delay(0.6, spawnBubble)
	task.delay(timeLimit + 2, finish)
end

-- stop the progress in the golden window
local function stopGame(area, ease, done, opts)
	hint(area, opts.hint).Position = UDim2.fromOffset(10, 6)
	local track = bar(area, 70, 40)
	local width = math.clamp(0.12 * ease, 0.08, 0.25)
	local center = rng:NextNumber(0.6, 0.85)
	zone(track, center, width, T.gold)
	local fill = UI.new("Frame", { BackgroundColor3 = opts.color or T.accent, Size = UDim2.fromScale(0, 1), Parent = track })
	UI.corner(fill, 10)
	local btn = actionButton(area, opts.button or "СТОП")
	local p = 0
	local finished = false
	local disconnect
	local conn = RunService.RenderStepped:Connect(function(dt)
		p += dt / (opts.time or 2.6)
		fill.Size = UDim2.fromScale(math.min(p, 1), 1)
		if p >= 1.15 and not finished then
			finished = true
			disconnect()
			done(0.1) -- сгорело / перелилось
		end
	end)
	disconnect = onAction(btn, function()
		if finished then
			return
		end
		finished = true
		conn:Disconnect()
		disconnect()
		local dist = math.abs(p - center)
		done(math.clamp(1 - dist / (width * 1.6), 0, 1))
	end)
	local oldDone = done
	done = function(s)
		conn:Disconnect()
		oldDone(s)
	end
end

games.bake = function(area, ease, done)
	stopGame(area, ease, done, { hint = "♨️ Выпечка: достаньте из духовки, когда корочка золотистая!", button = "ДОСТАТЬ", color = Color3.fromRGB(200, 120, 50), time = 2.8 })
end
games.pour = function(area, ease, done)
	stopGame(area, ease, done, { hint = "🥛 Налейте ровно до отметки!", button = "СТОП", color = Color3.fromRGB(110, 190, 255), time = 2.2 })
end
games.brew = function(area, ease, done)
	stopGame(area, ease, done, { hint = "☕ Заварка: снимите с огня в идеальный момент", button = "ГОТОВО", color = Color3.fromRGB(150, 90, 50), time = 2.0 })
end

-- sequence memory: click ingredients in the shown order
games.assemble = function(area, ease, done, recipe)
	local icons = {}
	for id in pairs(recipe and recipe.ing or {}) do
		local ing = Ingredients.ById[id]
		if ing then
			table.insert(icons, ing.icon)
		end
	end
	while #icons < 3 do
		table.insert(icons, "🧂")
	end
	while #icons > 5 do
		table.remove(icons)
	end
	local order = table.clone(icons)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local h = hint(area, "🍔 Сборка: запомните порядок...")
	h.Position = UDim2.fromOffset(10, 6)
	local show = UI.label(area, table.concat(order, "  ➜  "), 34, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 50) })
	show.Position = UDim2.fromOffset(0, 60)
	task.wait(1.4 * math.clamp(ease, 0.8, 1.8))
	show.Text = ""
	h.Text = "🍔 Сборка: нажмите ингредиенты в том же порядке"
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 110), Parent = area })
	UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local shuffled = table.clone(order)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local step, mistakes = 1, 0
	local finished = false
	for i, icon in ipairs(shuffled) do
		local b = UI.new("TextButton", { Text = icon, TextSize = 34, BackgroundColor3 = T.card, Size = UDim2.fromOffset(64, 64), LayoutOrder = i, Parent = row })
		UI.corner(b, 12)
		b.Activated:Connect(function()
			if finished or b:GetAttribute("Used") then
				return
			end
			if icon == order[step] then
				b:SetAttribute("Used", true)
				b.BackgroundColor3 = T.good
				show.Text ..= icon .. " "
				step += 1
				UI.click()
				if step > #order then
					finished = true
					done(math.clamp(1 - mistakes * 0.25, 0, 1))
				end
			else
				mistakes += 1
				b.BackgroundColor3 = T.bad
				task.delay(0.25, function()
					if not b:GetAttribute("Used") then
						b.BackgroundColor3 = T.card
					end
				end)
				if mistakes >= 4 then
					finished = true
					done(0)
				end
			end
		end)
	end
end

-- shake: tap rapidly
games.shake = function(area, ease, done)
	hint(area, "🍸 Шейкер: трясите! Быстро жмите кнопку / пробел").Position = UDim2.fromOffset(10, 6)
	local goal = math.floor(14 / math.clamp(ease, 0.8, 1.6))
	local count = 0
	local timeLimit = 3.6
	local shaker = UI.label(area, "🍸", 60, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, 0, 0, 80) })
	shaker.Position = UDim2.fromOffset(0, 40)
	local prog = UI.progress(area, 0, T.purple, { size = UDim2.new(1, -60, 0, 14), position = UDim2.fromOffset(30, 130) })
	local btn = actionButton(area, "ТРЯСТИ")
	local startT = os.clock()
	local finished = false
	local disconnect
	disconnect = onAction(btn, function()
		if finished then
			return
		end
		count += 1
		prog.Fill.Size = UDim2.fromScale(math.min(1, count / goal), 1)
		shaker.Rotation = (count % 2 == 0) and 15 or -15
		if count >= goal then
			finished = true
			disconnect()
			local t = os.clock() - startT
			done(math.clamp(1.1 - t / (timeLimit * 1.2), 0.5, 1))
		end
	end)
	task.delay(timeLimit, function()
		if not finished then
			finished = true
			disconnect()
			done(math.clamp(count / goal, 0, 1) * 0.8)
		end
	end)
end

-- ===================== RUNNER =====================
local overlay

function Minigames.run(data, onFinish)
	if Minigames.active then
		return
	end
	Minigames.active = true
	local recipe = Recipes.ById[data.recipeId]
	local gui = UI.screen()
	overlay = UI.new("Frame", {
		Name = "Minigame",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = gui,
	})
	local panel = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 400),
		BackgroundColor3 = T.panel,
		ZIndex = 21,
		Parent = overlay,
	})
	UI.corner(panel, 18)
	UI.stroke(panel, T.accent, 2, 0.3)
	local title = UI.label(panel, "", 22, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, -20, 0, 34) })
	title.Position = UDim2.fromOffset(10, 10)
	local stepsLabel = UI.label(panel, "", 14, { color = T.sub, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, -20, 0, 20) })
	stepsLabel.Position = UDim2.fromOffset(10, 44)
	local cancel = UI.button(panel, "✕", T.bad, nil, { size = UDim2.fromOffset(34, 34), radius = 17 })
	cancel.Position = UDim2.new(1, -44, 0, 10)
	local area = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -76), Position = UDim2.fromOffset(0, 70), Parent = panel })
	local s = UI.new("UIScale", { Scale = 0.8, Parent = panel })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	UI.sound(Config.Sounds.Cooking, 0.3)

	local cancelled = false
	cancel.Activated:Connect(function()
		if cancelled then
			return
		end
		cancelled = true
		Minigames.active = false
		overlay:Destroy()
		onFinish(nil)
	end)

	task.spawn(function()
		local scores = {}
		local names = {}
		for _, st in ipairs(data.steps) do
			table.insert(names, Recipes.StepNames[st] or st)
		end
		for i, step in ipairs(data.steps) do
			if cancelled then
				return
			end
			title.Text = (recipe and (recipe.icon .. " " .. recipe.name) or "Готовка") .. "  —  " .. (Recipes.StepNames[step] or step)
			local parts = {}
			for j, n in ipairs(names) do
				table.insert(parts, (j < i and "✅ " or (j == i and "▶ " or "")) .. n)
			end
			stepsLabel.Text = table.concat(parts, "   ")
			UI.clear(area)
			local result
			local stepFn = games[step] or games.chop
			local ok, err = pcall(stepFn, area, data.ease or 1, function(score)
				result = score
			end, recipe)
			if not ok then
				warn("[Minigames] " .. tostring(err))
				result = 0.5
			end
			while result == nil and not cancelled do
				task.wait()
			end
			if cancelled then
				return
			end
			feedback(area, result)
			table.insert(scores, result)
			task.wait(0.7)
		end
		if cancelled then
			return
		end
		Minigames.active = false
		overlay:Destroy()
		onFinish(scores)
	end)
end

function Minigames.cancel()
	if overlay and overlay.Parent then
		overlay:Destroy()
	end
	Minigames.active = false
end

return Minigames
