-- Shared helper functions (server + client)
local Util = {}

function Util.deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local r = {}
	for k, v in pairs(t) do
		r[k] = Util.deepCopy(v)
	end
	return r
end

-- Заполняет отсутствующие ключи значениями по умолчанию (миграция сохранений)
function Util.reconcile(target, template)
	for k, v in pairs(template) do
		if target[k] == nil then
			target[k] = Util.deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil and #v == 0 then
			Util.reconcile(target[k], v)
		end
	end
	return target
end

function Util.clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

function Util.round(x, step)
	step = step or 1
	return math.floor(x / step + 0.5) * step
end

function Util.formatMoney(n)
	n = math.floor(tonumber(n) or 0)
	local neg = n < 0
	n = math.abs(n)
	local s
	if n >= 1e9 then
		s = string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		s = string.format("%.2fM", n / 1e6)
	elseif n >= 1e5 then
		s = string.format("%.1fK", n / 1e3)
	else
		s = tostring(n):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	end
	return (neg and "-$" or "$") .. s
end

function Util.formatTime(sec)
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

function Util.weightedChoice(list, weightKey, rng)
	local total = 0
	for _, item in ipairs(list) do
		total += item[weightKey] or 1
	end
	if total <= 0 then
		return nil
	end
	local r = (rng and rng:NextNumber() or math.random()) * total
	for _, item in ipairs(list) do
		r -= item[weightKey] or 1
		if r <= 0 then
			return item
		end
	end
	return list[#list]
end

function Util.shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng and rng:NextInteger(1, i) or math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Util.count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function Util.dayNumber(t)
	return math.floor((t or os.time()) / 86400)
end

function Util.weekNumber(t)
	-- недели начинаются с понедельника (1 января 1970 - четверг)
	return math.floor(((t or os.time()) / 86400 + 3) / 7)
end

-- Сваривает все BasePart модели с корневой деталью (для анимированных NPC/вертолётов)
function Util.weldModel(model, root, anchoredRoot)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root and d:GetAttribute("Spin") then
			-- вращающиеся детали (винты) анимирует клиент
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
			d.Anchored = false
			d.Massless = true
		end
	end
	root.Anchored = anchoredRoot == true
end

function Util.setCollision(model, canCollide, canQuery)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = canCollide
			if canQuery ~= nil then
				d.CanQuery = canQuery
			end
			d.CanTouch = false
		end
	end
end

function Util.typeOk(v, t)
	return typeof(v) == t
end

function Util.isFiniteNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

return Util
