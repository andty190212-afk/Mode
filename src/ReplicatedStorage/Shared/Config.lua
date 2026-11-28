--!nonstrict
-- Restaurant Island Tycoon - global configuration
-- ВАЖНО: после создания Game Pass / Developer Products на сайте Roblox
-- впишите их реальные ID ниже (см. docs/MONETIZATION.md).

local Config = {}

Config.GameName = "Restaurant Island Tycoon"
Config.Version = "2.5.2"

-- ===================== MONETIZATION =====================
Config.GamePasses = {
	Chef = 2101051301, -- Шеф-повар, 80 Robux
	Director = 2100247249, -- Директор ресторана, 100 Robux
}
Config.GamePassPrices = { Chef = 80, Director = 100 }

-- В Roblox Studio (и только в Studio) платные профессии можно выдать для теста.
-- На опубликованном сервере это НИКОГДА не работает (проверка RunService:IsStudio()).
Config.StudioGrantGamePasses = true

-- Developer Products. id = 0 означает "не настроено" (покупка не будет предложена).
Config.Products = {
	{ key = "cash_small", id = 3736953500, robux = 25, kind = "cash", amount = 1500, title = "Горсть монет" },
	{ key = "cash_medium", id = 3736953766, robux = 99, kind = "cash", amount = 7500, title = "Мешок монет" },
	{ key = "cash_large", id = 3736953960, robux = 399, kind = "cash", amount = 40000, title = "Сундук монет" },
	{ key = "cash_huge", id = 3736954148, robux = 999, kind = "cash", amount = 120000, title = "Сокровищница" },
	{ key = "boost_x2_30", id = 3736951389, robux = 79, kind = "boost", mult = 2, minutes = 30, title = "Заработок x2 (30 мин)" },
	{ key = "boost_x3_30", id = 3736951932, robux = 149, kind = "boost", mult = 3, minutes = 30, title = "Заработок x3 (30 мин)" },
	{ key = "boost_x2_120", id = 3736952884, robux = 249, kind = "boost", mult = 2, minutes = 120, title = "Заработок x2 (2 часа)" },
}

-- ===================== SERVER LIMITS =====================
Config.MaxRestaurants = 8
Config.MaxPlayersPerRestaurant = 2
Config.MaxServerPlayers = 16

-- ===================== DATA =====================
Config.DataStoreName = "RIT_PlayerData_v1"
Config.LeaderboardStoreName = "RIT_TopEarnings_v1"
Config.LeaderboardStarsStoreName = "RIT_TopStars_v1"
Config.AutosaveInterval = 90 -- seconds
Config.SessionLockTimeout = 300 -- seconds: lock older than this is considered stale
Config.DataRetries = 5

-- ===================== ECONOMY =====================
Config.StartMoney = 250
Config.StartBudget = 800
Config.WorkerShare = 0.15 -- доля от продажи блюда, идущая в личный баланс исполнителю
Config.SelfServeTipMult = 0.4 -- чаевые, если еду выдал не официант
Config.FriendDailySpendLimit = 5000
Config.OwnerWithdrawFee = 0.10 -- комиссия при выводе из бюджета ресторана в личный баланс
Config.MaxPriceMult = 2.0
Config.MinPriceMult = 0.5
Config.IngredientPack = 10 -- закупка упаковками
Config.FurnitureRefund = 0.5
Config.MaxFurniture = 80
Config.MaxDecor = 120
Config.VisitorMealPrice = 40
Config.KitchenRobotPrice = 120000 -- кухонный робот (нужна плита макс. уровня)
Config.FerryTicket = 60

-- ===================== GUESTS =====================
Config.GuestTickRate = 1 -- seconds per restaurant simulation tick
Config.BaseSpawnInterval = 14 -- секунд между группами гостей при репутации 50
Config.QueueMax = { 0, 2, 1, 3, 4 } -- групп в очереди у входа по звёздам (когда нет свободных столов)
Config.QueuePatience = 70 -- сколько секунд гости ждут в очереди
Config.MaxGuestsGlobal = 110 -- NPC-аватары тяжелее простых моделей
Config.OrderAutoDelay = 14 -- через сколько гость сам закажет через планшет (если нет официанта)
Config.AutoCookTime = 24 -- автокухня (если нет повара)
Config.AutoCookSlots = { 1, 1, 2, 2, 2 } -- одновременно готовящихся блюд по уровню звёзд
Config.AutoCookQuality = 0.42
Config.AutoDrinkTime = 10
Config.AutoDrinkSlots = 2
Config.AutoDrinkQuality = 0.5
Config.SelfPickupDelay = 12 -- гость сам забирает готовое блюдо (если нет официанта)
Config.TabletFallbackDelay = 32 -- даже при официанте: гость, которого игнорируют, закажет через планшет
Config.SelfPickupFallbackDelay = 30 -- даже при официанте: остывающее блюдо гость заберёт сам
Config.AutoCleanDelay = 20
Config.EatTime = 14
Config.IdleTimeout = 300 -- секунд без активности команды
Config.IdleGuestMult = 0.25

-- ===================== NPC LOOK =====================
Config.NPC = {
	-- Стандартные анимации Roblox R15 (как в скрипте Animate по умолчанию)
	Animations = {
		idle = "rbxassetid://507766388",
		walk = "rbxassetid://507777826",
		sit = "rbxassetid://2506281703",
	},
	-- Необязательно: UserId игроков Roblox, чьи аватары будут у части гостей (разнообразие).
	-- Пример: { 156, 261 }. Пусто = все гости — стандартные аватары с цветной одеждой.
	GuestAvatarUserIds = {},
	-- Необязательно: ID ШАБЛОНОВ одежды (Shirt/Pants template, не ID товара каталога).
	Clothing = {
		guestShirts = {},
		guestPants = {},
		Cook = { shirt = 0, pants = 0 },
		Waiter = { shirt = 0, pants = 0 },
		Bartender = { shirt = 0, pants = 0 },
	},
}

-- ===================== WEAPON ANIMATIONS =====================
-- Стандартные публичные анимации Roblox (такие же, как у инструментов в скрипте Animate).
-- Хотите свои уникальные: загрузите анимацию в Roblox и впишите ID в PerAbility[ид способности].
Config.WeaponAnimations = {
	R15 = {
		hold = "rbxassetid://507768375", -- toolnone: держать оружие
		slash = "rbxassetid://522635514", -- toolslash: удар
		lunge = "rbxassetid://522638767", -- toollunge: выпад
		point = "rbxassetid://507770453", -- указать
		cheer = "rbxassetid://507770677", -- руки вверх
		eat = "rbxassetid://507770239", -- взмах рукой (поедание)
	},
	R6 = {
		hold = "rbxassetid://182393478",
		slash = "rbxassetid://129967390",
		lunge = "rbxassetid://129967478",
		point = "rbxassetid://128853357",
		cheer = "rbxassetid://129423030",
		eat = "rbxassetid://128777973",
	},
	PerAbility = {}, -- [ability id] = "rbxassetid://..."
}

-- ===================== WORLD =====================
Config.OutsideSpeedMult = 2.5 -- вне кафе игроки бегают в 2.5 раза быстрее
Config.WaterLevel = 0
Config.IslandTopY = 6
Config.HelicopterUnlockStars = 3
Config.MaxFlightHeight = 420
Config.WorldRadius = 1700

-- ===================== PLAYER PROGRESSION =====================
function Config.XpForLevel(level: number): number
	return math.floor(100 * level ^ 1.45)
end
function Config.XpForProfLevel(level: number): number
	return math.floor(60 * level ^ 1.35)
end
Config.MaxPlayerLevel = 100
Config.MaxProfLevel = 50

-- ===================== SOUNDS =====================
-- Встроенные звуки движка (rbxasset://) работают всегда.
-- Для музыки/вертолёта/природы впишите ID аудио из Creator Store (см. docs/EXTERNAL_RESOURCES.md).
-- громкость и тон звуков интерфейса
Config.SoundTuning = {
	Click = { volume = 0.3, pitch = 1.25 },
	Buy = { volume = 0.4, pitch = 1.5 },
	Error = { volume = 0.35, pitch = 0.7 },
}

Config.Sounds = {
	-- мягкий щелчок (встроенный звук Roblox). Можно заменить на любой "rbxassetid://ID" из Creator Store
	Click = "rbxasset://sounds/button.wav",
	Buy = "rbxasset://sounds/button.wav",
	Error = "rbxasset://sounds/button.wav",
	Cash = "", -- кассовый аппарат
	Upgrade = "", -- улучшение
	Cooking = "", -- шипение сковороды
	Door = "", -- дверь
	Crowd = "", -- гул посетителей
	Helicopter = "", -- цикл вертолёта
	Ocean = "", -- шум океана
	Birds = "", -- птицы
	Music = "", -- фоновая музыка
	-- лаборатория и бой (встроенные звуки Roblox; можно заменить на rbxassetid://ID)
	LabAlarm = "rbxasset://sounds/button.wav",
	Theft = "rbxasset://sounds/button.wav",
	ChestOpen = "rbxasset://sounds/unsheath.wav",
	RareDrop = "rbxasset://sounds/button.wav",
	Eat = "rbxasset://sounds/button.wav",
	WeaponGet = "rbxasset://sounds/unsheath.wav",
	Swing = "rbxasset://sounds/swordslash.wav",
	Hit = "rbxasset://sounds/swordlunge.wav",
	Ability = "rbxasset://sounds/button.wav",
}

return Config
