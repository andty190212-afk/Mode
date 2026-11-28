-- MonetizationService: Game Passes (Chef 80 R$, Director 100 R$) via
-- MarketplaceService:UserOwnsGamePassAsync, Developer Products via ProcessReceipt
-- with idempotent grants (purchase ids stored in the profile and saved BEFORE
-- returning PurchaseGranted).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Monetization = {}
local S
local passCache = {} -- [player] = {Chef=bool, Director=bool}

function Monetization.Init(registry)
	S = registry
end

local function studioGrant()
	return RunService:IsStudio() and Config.StudioGrantGamePasses
end

local function checkPass(player, key)
	local id = Config.GamePasses[key]
	if studioGrant() then
		return true
	end
	if not id or id == 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	local profile = S.DataService.get(player)
	if ok then
		if owns == true and profile then
			profile.data.ownedPasses = profile.data.ownedPasses or {}
			profile.data.ownedPasses[key] = true -- запоминаем подтверждённую покупку
		end
		return owns == true
	end
	-- API недоступен: используем ранее подтверждённую покупку из сохранения
	return profile ~= nil and profile.data.ownedPasses ~= nil and profile.data.ownedPasses[key] == true
end

function Monetization.refreshPasses(player)
	passCache[player] = {
		Chef = checkPass(player, "Chef"),
		Director = checkPass(player, "Director"),
	}
	S.Economy.markPlayer(player)
end

function Monetization.ownsPass(player, key)
	local cache = passCache[player]
	if not cache then
		Monetization.refreshPasses(player)
		cache = passCache[player]
	end
	return cache[key] == true
end

function Monetization.passState(player)
	local cache = passCache[player] or {}
	return {
		Chef = cache.Chef == true,
		Director = cache.Director == true,
		ChefId = Config.GamePasses.Chef,
		DirectorId = Config.GamePasses.Director,
		studio = studioGrant(),
	}
end

function Monetization.productList()
	local list = {}
	for _, p in ipairs(Config.Products) do
		table.insert(list, { key = p.key, id = p.id, robux = p.robux, kind = p.kind, amount = p.amount, mult = p.mult, minutes = p.minutes, title = p.title })
	end
	return list
end

local productsById = {}
for _, p in ipairs(Config.Products) do
	if p.id ~= 0 then
		productsById[p.id] = p
	end
end

local function grantProduct(player, product)
	if product.kind == "cash" then
		S.Economy.grant(player, product.amount, "Покупка: " .. product.title)
		Net.toast(player, "💰 +$" .. product.amount .. " — спасибо за покупку!", "success")
	elseif product.kind == "boost" then
		S.Economy.addBoost(player, product.mult, product.minutes)
		Net.toast(player, "⚡ Множитель x" .. product.mult .. " активирован на " .. product.minutes .. " мин!", "success")
	else
		error("unknown product kind")
	end
	Net.fx(player, "purchase", {})
end

local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = S.DataService.waitFor(player, 15)
	if not profile or profile.temporary then
		-- без надёжного сохранения не выдаём (Roblox повторит позже)
		if profile and profile.temporary and RunService:IsStudio() then
			-- Studio без доступа к DataStore: выдаём для теста
		else
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	local purchases = profile.data.purchases
	if purchases[info.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- уже выдано
	end
	local product = productsById[info.ProductId]
	if not product then
		warn("[Monetization] unknown product id " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(grantProduct, player, product)
	if not ok then
		warn("[Monetization] grant failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	purchases[info.PurchaseId] = os.time()
	table.insert(profile.data.purchaseOrder, info.PurchaseId)
	while #profile.data.purchaseOrder > 200 do
		local old = table.remove(profile.data.purchaseOrder, 1)
		purchases[old] = nil
	end
	profile.data.stats.robuxSpent += info.CurrencySpent or 0
	if profile.temporary then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not S.DataService.save(profile, false) then
		-- Данные в памяти уже содержат покупку и её id: повторная обработка не задублирует.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			Monetization.refreshPasses(player)
			local name = passId == Config.GamePasses.Chef and "Шеф-повар" or "Директор ресторана"
			Net.toast(player, "🎉 Game Pass «" .. name .. "» куплен! Профессия разблокирована навсегда.", "success")
		end
	end)

	S.DataService.onLoaded(function(player)
		Monetization.refreshPasses(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)

	-- Только в Roblox Studio: проверить выдачу товара без настоящей покупки (ID ещё не настроены)
	Net.onRequest("StudioTestProduct", function(player, payload)
		if not RunService:IsStudio() then
			return { ok = false, err = "Доступно только в Roblox Studio" }
		end
		for _, p in ipairs(Config.Products) do
			if p.key == (payload and payload.key) then
				local ok, err = pcall(grantProduct, player, p)
				return { ok = ok, err = not ok and tostring(err) or nil }
			end
		end
		return { ok = false, err = "Нет такого товара" }
	end)

	Net.onRequest("RefreshPasses", function(player)
		Monetization.refreshPasses(player)
		return { ok = true }
	end)
end

return Monetization
