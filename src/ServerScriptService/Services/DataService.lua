-- DataService: DataStore persistence with session locking (UpdateAsync),
-- retries, autosave, graceful shutdown and schema reconciliation.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Data = Shared.Data
local Ingredients = require(Data.Ingredients)
local Furniture = require(Data.Furniture)
local Equipment = require(Data.Equipment)

local DataService = {}
DataService.Profiles = {} -- [player] = profile
DataService.SCHEMA = 1

local store
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function defaultRestaurant()
	local menu = {}
	return {
		name = "",
		stars = 1,
		budget = Config.StartBudget,
		reputation = 50,
		cleanliness = 100,
		inventory = Util.deepCopy(Ingredients.StartStock),
		storageLevel = 1,
		menu = menu, -- [recipeId] = {on=bool, price=mult}
		unlockedRecipes = {},
		equipment = Util.deepCopy(Equipment.Start),
		furniture = {}, -- {uid, id, x, z, r}
		decor = {}, -- {uid, id, x, z, r}
		staff = {}, -- {uid, role, name, level, xp, wageMult, morale}
		chefNpc = { level = 1, xp = 0 },
		bartenderNpc = { level = 1, xp = 0 }, -- бесплатный бармен (есть всегда)
		houseWaiterNpc = { level = 1, xp = 0 }, -- официант на замену, если нет официанта
		kitchenRobot = false, -- куплен ли кухонный робот
		nextUid = 1,
		barrierOn = false,
		whitelist = {}, -- [tostring(userId)] = name
		friendCanSpend = false,
		stats = {
			revenue = 0,
			expenses = 0,
			ingredientCost = 0,
			wages = 0,
			upgrades = 0,
			served = 0,
			lost = 0,
			dishesSold = 0,
			drinksSold = 0,
			tips = 0,
			criticsPassed = 0,
			criticsFailed = 0,
			vipServed = 0,
			satisfactionEma = 0.65,
			foodEma = 0.6,
			serviceEma = 0.6,
			speedEma = 0.6,
			priceEma = 0.7,
			interiorEma = 0.5,
			reviewCount = 0,
			reviewSum = 0,
			hourly = {}, -- последние 24 точки выручки {t, revenue}
		},
		reviews = {},
		ledger = {},
		createdAt = os.time(),
	}
end
DataService.defaultRestaurant = defaultRestaurant

local function defaultData()
	return {
		schema = DataService.SCHEMA,
		money = Config.StartMoney,
		level = 1,
		xp = 0,
		prof = {
			Cook = { level = 1, xp = 0 },
			Waiter = { level = 1, xp = 0 },
			Chef = { level = 1, xp = 0 },
			Director = { level = 1, xp = 0 },
		},
		stats = {
			moneyEarned = 0,
			tipsEarned = 0,
			dishesCooked = 0,
			drinksMade = 0,
			guestsServed = 0,
			ordersTaken = 0,
			tablesCleaned = 0,
			ingredientsBought = 0,
			happyGuests = 0,
			vipServed = 0,
			criticsPassed = 0,
			itemsPlaced = 0,
			uniqueFurniture = 0,
			teamJoins = 0,
			helicoptersOwned = 0,
			contestsWon = 0,
			maxStars = 1,
			playSeconds = 0,
			robuxSpent = 0,
		},
		income = {}, -- последние записи {t, amount, src}
		purchases = {}, -- [purchaseId] = timestamp  (защита от повторных начислений)
		purchaseOrder = {},
		boosts = { mult = 1, untilTime = 0 },
		daily = { lastDay = 0, streak = 0 },
		quests = { day = 0, daily = {}, week = 0, weekly = {} },
		achievements = {},
		helicopters = { owned = {}, equipped = "" },
		ownedPasses = {}, -- подтверждённые MarketplaceService покупки Game Pass
		ownedFurnitureTypes = {},
		lastRole = "",
		restaurant = defaultRestaurant(),
		-- ===== лаборатория, существа, оружие, PvP =====
		creatures = {}, -- [uid] = { id, lvl, grow, pod, dish, got }
		creatureSeq = 0,
		dishes = {}, -- [dishId] = count
		weapons = {}, -- [uid] = { id, got }
		weaponSeq = 0,
		equipped = "",
		starterClaimed = {},
		settings = { lang = "" }, -- "" = по языку Roblox, "ru" / "en" = выбрано игроком
		lab = {
			level = 1,
			bank = 0,
			access = "open", -- open | private (вход посторонним, пока лаборатория защищена)
			friendClose = true, -- друг может закрыть лабораторию плитой
			trusted = {}, -- [userId] = name
			open = false, -- состояние цикла сохраняется (перезаход не сбрасывает таймер)
			openElapsed = 0,
			cycleRemaining = 120,
		},
		pvp = { kills = 0, deaths = 0, arenaKills = 0, arenaDeaths = 0, bestStreak = 0, steals = 0, stolenFrom = 0, defends = 0, caught = 0, chests = 0, dishesEaten = 0 },
		firstJoin = os.time(),
		lastJoin = os.time(),
	}
end
DataService.defaultData = defaultData

local function newRestaurantLayout(rest)
	for _, f in ipairs(Furniture.StartLayout) do
		table.insert(rest.furniture, { uid = rest.nextUid, id = f.id, x = f.x, z = f.z - 10, r = f.r })
		rest.nextUid += 1
	end
end

local function migrate(data)
	Util.reconcile(data, defaultData())
	Util.reconcile(data.restaurant, defaultRestaurant())
	Util.reconcile(data.restaurant.stats, defaultRestaurant().stats)
	Util.reconcile(data.lab, defaultData().lab)
	Util.reconcile(data.pvp, defaultData().pvp)
	if #data.restaurant.furniture == 0 and (data.restaurant.stats.served or 0) == 0 then
		newRestaurantLayout(data.restaurant)
	end
	-- 3.0: creatures were replaced -> map old creature/dish ids to new ones of the same rarity
	local Creatures = require(Shared.Data.Creatures)
	for _, rec in pairs(data.creatures or {}) do
		if Creatures.Legacy[rec.id] then
			rec.id = Creatures.Legacy[rec.id]
		end
	end
	for oldId, n in pairs(table.clone(data.dishes or {})) do
		local newId = Creatures.LegacyDish[oldId]
		if newId then
			data.dishes[oldId] = nil
			data.dishes[newId] = (data.dishes[newId] or 0) + n
		end
	end
	data.schema = DataService.SCHEMA
	return data
end
DataService.migrateForTest = migrate

local function retry(fn, attempts)
	local lastErr
	for i = 1, attempts or Config.DataRetries do
		local ok, a, b = pcall(fn)
		if ok then
			return true, a, b
		end
		lastErr = a
		warn("[DataService] attempt " .. i .. " failed: " .. tostring(a))
		task.wait(math.min(2 ^ i, 10))
	end
	return false, lastErr
end

local function keyFor(userId)
	return "u_" .. tostring(userId)
end

-- Load with session lock. Returns profile or nil + error.
function DataService.load(player)
	local profile = { player = player, data = nil, canSave = false, loaded = false, lastSave = 0 }
	if not storeOk or not store then
		profile.data = migrate(defaultData())
		profile.loaded = true
		profile.temporary = true
		return profile
	end

	local key = keyFor(player.UserId)
	local jobId = game.JobId ~= "" and game.JobId or "studio"
	local lockedElsewhere = false
	local deadline = os.clock() + 25

	while true do
		lockedElsewhere = false
		local ok, result = retry(function()
			return store:UpdateAsync(key, function(old)
				old = old or { data = nil, lock = nil }
				if type(old) ~= "table" then
					old = { data = nil, lock = nil }
				end
				local lock = old.lock
				if lock and lock.job ~= jobId and os.time() - (lock.time or 0) < Config.SessionLockTimeout then
					lockedElsewhere = true
					return nil -- отмена записи
				end
				old.lock = { job = jobId, time = os.time() }
				return old
			end)
		end)
		if not ok then
			-- DataStore недоступен (например, Studio без API Services)
			warn("[DataService] DataStore unavailable for " .. player.Name .. ": " .. tostring(result))
			profile.data = migrate(defaultData())
			profile.loaded = true
			profile.temporary = true
			return profile
		end
		if not lockedElsewhere then
			local stored = result and result.data
			if type(stored) == "table" then
				profile.data = migrate(stored)
			else
				profile.data = migrate(defaultData())
			end
			profile.data.lastJoin = os.time()
			profile.loaded = true
			profile.canSave = true
			return profile
		end
		if os.clock() > deadline or not player.Parent then
			return nil, "Ваши данные ещё используются другим сервером. Перезайдите через минуту."
		end
		task.wait(5)
	end
end

-- Save; release = true removes the session lock.
function DataService.save(profile, release)
	if not profile or not profile.loaded or not profile.canSave or not store or profile.released then
		return false
	end
	if profile.saving then
		-- дождаться текущего сохранения
		local t = os.clock()
		while profile.saving and os.clock() - t < 15 do
			task.wait(0.2)
		end
	end
	profile.saving = true
	local jobId = game.JobId ~= "" and game.JobId or "studio"
	local key = keyFor(profile.player.UserId)
	local snapshot = Util.deepCopy(profile.data)
	local lostLock = false
	local ok, err = retry(function()
		return store:UpdateAsync(key, function(old)
			old = type(old) == "table" and old or {}
			if old.lock and old.lock.job ~= jobId and os.time() - (old.lock.time or 0) < Config.SessionLockTimeout then
				lostLock = true
				return nil
			end
			old.data = snapshot
			old.lock = (not release) and { job = jobId, time = os.time() } or nil
			old.savedAt = os.time()
			return old
		end)
	end)
	profile.saving = false
	if lostLock then
		warn("[DataService] session lock lost for " .. profile.player.Name .. "; save skipped")
		profile.canSave = false
		return false
	end
	if ok then
		profile.lastSave = os.clock()
		if release then
			profile.released = true
		end
		return true
	end
	warn("[DataService] save failed: " .. tostring(err))
	return false
end

function DataService.get(player)
	local p = DataService.Profiles[player]
	return p and p.loaded and p or nil
end

function DataService.waitFor(player, timeout)
	local t = os.clock()
	while player.Parent and os.clock() - t < (timeout or 30) do
		local p = DataService.get(player)
		if p then
			return p
		end
		task.wait(0.25)
	end
	return DataService.get(player)
end

function DataService.Init(S)
	DataService.S = S
end

local onLoadedCallbacks = {}
local onRemovingCallbacks = {}
function DataService.onLoaded(cb)
	table.insert(onLoadedCallbacks, cb)
end
function DataService.onRemoving(cb)
	table.insert(onRemovingCallbacks, cb)
end

local function runRemoving(player, profile)
	if profile then
		if profile.removed then
			return
		end
		profile.removed = true
	end
	for _, cb in ipairs(onRemovingCallbacks) do
		local ok, e = pcall(cb, player, profile)
		if not ok then
			warn("[DataService] removing callback error: " .. tostring(e))
		end
	end
end

function DataService.Start()
	local function onPlayer(player)
		local profile, err = DataService.load(player)
		if not player.Parent then
			if profile and profile.canSave then
				DataService.save(profile, true)
			end
			return
		end
		if not profile then
			player:Kick(err or "Не удалось загрузить данные")
			return
		end
		DataService.Profiles[player] = profile
		for _, cb in ipairs(onLoadedCallbacks) do
			task.spawn(cb, player, profile)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, p)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = DataService.Profiles[player]
		runRemoving(player, profile)
		if profile then
			DataService.save(profile, true)
			DataService.Profiles[player] = nil
		end
	end)

	-- Autosave (обновляет и время блокировки)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player, profile in pairs(DataService.Profiles) do
				if player.Parent then
					task.spawn(DataService.save, profile, false)
				end
				task.wait(0.5)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in pairs(DataService.Profiles) do
			pending += 1
			task.spawn(function()
				runRemoving(player, profile)
				DataService.save(profile, true)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
