-- BuildService: server-validated build mode for restaurant furniture (inside the
-- dining area) and island decorations (on the owner's island only).
-- Buy / place / move / rotate / remove. Positions are stored in local coordinates.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local BuildRules = require(Shared.BuildRules)
local Data = Shared.Data
local Furniture = require(Data.Furniture)
local Decor = require(Data.Decor)

local BuildService = {}
local S

function BuildService.Init(registry)
	S = registry
end

local catalog = BuildRules.catalog
local listOf = BuildRules.listOf

-- ===================== MODELS =====================
local function makeFallback(def)
	local m = Instance.new("Model")
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(def.size[1], 0.2, def.size[2])
	base.Transparency = 1
	base.Anchored = true
	base.Parent = m
	local body = Instance.new("Part")
	body.Name = "Top"
	body.Size = Vector3.new(def.size[1], def.flat and 0.2 or 3, def.size[2])
	body.CFrame = CFrame.new(0, body.Size.Y / 2, 0)
	body.Anchored = true
	body.Color = Color3.fromRGB(180, 140, 100)
	body.Parent = m
	m.PrimaryPart = base
	return m
end

function BuildService.modelFor(kind, id)
	local def = catalog(kind).ById[id]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(kind == "decor" and "Decor" or "Furniture")
	local template = folder and folder:FindFirstChild(id)
	local model = template and template:Clone() or makeFallback(def)
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("Base") or model:FindFirstChildWhichIsA("BasePart")
	end
	return model
end

local function frameFor(island, kind)
	if kind == "decor" then
		return island.cframe
	end
	return island.buildingCF
end

local function placeModel(island, kind, entry)
	local model = BuildService.modelFor(kind, entry.id)
	model.Name = kind .. "_" .. entry.id .. "_" .. entry.uid
	local cf = frameFor(island, kind) * CFrame.new(entry.x, 0.1, entry.z) * CFrame.Angles(0, math.rad(entry.r or 0), 0)
	model:PivotTo(cf)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:SetAttribute("Uid", entry.uid)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("ItemId", entry.id)
	model.Parent = island.buildFolder
	island.build[kind][entry.uid] = model
	if kind == "furniture" then
		S.GuestService.registerTable(island, entry, model)
	end
	return model
end

local function removeModel(island, kind, uid)
	local model = island.build[kind][uid]
	if kind == "furniture" then
		S.GuestService.unregisterTable(island, uid)
	end
	if model then
		model:Destroy()
	end
	island.build[kind][uid] = nil
end

function BuildService.spawnAll(island)
	BuildService.clearIsland(island)
	local folder = Instance.new("Folder")
	folder.Name = "Placed"
	folder.Parent = island.model
	island.buildFolder = folder
	island.build = { furniture = {}, decor = {} }
	-- отбросить предметы, оказавшиеся вне зоны (например, после изменения карты)
	for _, kind in ipairs({ "furniture", "decor" }) do
		local list = listOf(island.rest, kind)
		for i = #list, 1, -1 do
			local e = list[i]
			if not catalog(kind).ById[e.id] then
				table.remove(list, i)
			end
		end
	end
	for _, e in ipairs(island.rest.decor) do
		placeModel(island, "decor", e)
	end
	for _, e in ipairs(island.rest.furniture) do
		placeModel(island, "furniture", e)
	end
end

-- after a tier change only the furniture must follow the new building frame
function BuildService.respawnFurniture(island)
	for uid in pairs(island.build.furniture) do
		removeModel(island, "furniture", uid)
	end
	for _, e in ipairs(island.rest.furniture) do
		placeModel(island, "furniture", e)
	end
end

function BuildService.clearIsland(island)
	if island.build then
		for uid in pairs(island.build.furniture) do
			removeModel(island, "furniture", uid)
		end
		for uid in pairs(island.build.decor) do
			removeModel(island, "decor", uid)
		end
	end
	if island.buildFolder then
		island.buildFolder:Destroy()
		island.buildFolder = nil
	end
	island.build = nil
end

function BuildService.beautyScore(island)
	local rest = island.rest
	if not rest then
		return 0
	end
	local b = 0
	for _, e in ipairs(rest.furniture) do
		local d = Furniture.ById[e.id]
		b += d and d.beauty or 0
	end
	for _, e in ipairs(rest.decor) do
		local d = Decor.ById[e.id]
		b += d and d.beauty or 0
	end
	return b
end

function BuildService.hasDecor(island, id)
	if not island.rest then
		return false
	end
	for _, e in ipairs(island.rest.decor) do
		if e.id == id then
			return true
		end
	end
	return false
end

function BuildService.decorEntry(island, id)
	for _, e in ipairs(island.rest.decor) do
		if e.id == id then
			return e
		end
	end
	return nil
end

-- ===================== VALIDATION =====================
function BuildService.validate(island, kind, id, x, z, r, ignoreUid)
	return BuildRules.validate(island.rest, kind, id, x, z, r, ignoreUid)
end

local function canBuild(player, island)
	if island.owner == player then
		return true
	end
	if island.friend == player and island.rest.friendCanSpend then
		return true
	end
	return false, "Строить может владелец (или друг с разрешением владельца)"
end

local function snap(v)
	return math.floor(v + 0.5)
end

-- ===================== REMOTES =====================
function BuildService.Start()
	Net.onRequest("PlaceItem", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local allowed, why = canBuild(player, island)
		if not allowed then
			return { ok = false, err = why }
		end
		if type(payload) ~= "table" then
			return { ok = false, err = "Некорректные данные" }
		end
		local kind = payload.kind == "decor" and "decor" or "furniture"
		local def = type(payload.id) == "string" and catalog(kind).ById[payload.id]
		if not def then
			return { ok = false, err = "Неизвестный предмет" }
		end
		if def.stars > island.rest.stars then
			return { ok = false, err = "Откроется на " .. def.stars .. "★" }
		end
		local list = listOf(island.rest, kind)
		if #list >= (kind == "decor" and Config.MaxDecor or Config.MaxFurniture) then
			return { ok = false, err = "Достигнут лимит предметов" }
		end
		if def.unique and BuildService.hasDecor(island, def.id) then
			return { ok = false, err = "Такой объект может быть только один" }
		end
		local x, z = snap(tonumber(payload.x) or 0), snap(tonumber(payload.z) or 0)
		local r = (math.floor((tonumber(payload.r) or 0) / 90 + 0.5) * 90) % 360
		local valid, err = BuildService.validate(island, kind, def.id, x, z, r)
		if not valid then
			return { ok = false, err = err }
		end
		local okSpend, spendErr = S.Economy.playerSpendBudget(player, island, def.price, kind, def.name, "upgrades")
		if not okSpend then
			return { ok = false, err = spendErr }
		end
		local entry = { uid = island.rest.nextUid, id = def.id, x = x, z = z, r = r }
		island.rest.nextUid += 1
		table.insert(list, entry)
		placeModel(island, kind, entry)
		S.QuestService.add(player, "itemsPlaced", 1)
		local profile = S.DataService.get(player)
		if profile and kind == "furniture" and not profile.data.ownedFurnitureTypes[def.id] then
			profile.data.ownedFurnitureTypes[def.id] = true
			S.QuestService.add(player, "uniqueFurniture", 1)
		end
		S.Economy.addXp(player, 5)
		Net.fx(player, "place", {})
		S.RestaurantService.markDirty(island)
		S.RestaurantService.markWorld()
		return { ok = true, uid = entry.uid }
	end)

	Net.onRequest("MoveItem", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local allowed, why = canBuild(player, island)
		if not allowed then
			return { ok = false, err = why }
		end
		local kind = payload and payload.kind == "decor" and "decor" or "furniture"
		local uid = tonumber(payload and payload.uid)
		local entry
		for _, e in ipairs(listOf(island.rest, kind)) do
			if e.uid == uid then
				entry = e
			end
		end
		if not entry then
			return { ok = false, err = "Предмет не найден" }
		end
		if kind == "furniture" and S.GuestService.tableBusy(island, uid) then
			return { ok = false, err = "За столом гости — подождите" }
		end
		local x, z = snap(tonumber(payload.x) or entry.x), snap(tonumber(payload.z) or entry.z)
		local r = (math.floor((tonumber(payload.r) or entry.r) / 90 + 0.5) * 90) % 360
		local valid, err = BuildService.validate(island, kind, entry.id, x, z, r, entry.uid)
		if not valid then
			return { ok = false, err = err }
		end
		removeModel(island, kind, entry.uid)
		entry.x, entry.z, entry.r = x, z, r
		placeModel(island, kind, entry)
		Net.fx(player, "place", {})
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)

	Net.onRequest("RemoveItem", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island then
			return { ok = false, err = "Вы не в ресторане" }
		end
		local allowed, why = canBuild(player, island)
		if not allowed then
			return { ok = false, err = why }
		end
		local kind = payload and payload.kind == "decor" and "decor" or "furniture"
		local uid = tonumber(payload and payload.uid)
		local list = listOf(island.rest, kind)
		for i, e in ipairs(list) do
			if e.uid == uid then
				if kind == "furniture" and S.GuestService.tableBusy(island, uid) then
					return { ok = false, err = "За столом гости — подождите" }
				end
				if e.id == "helipad" then
					S.HelicopterService.despawnForIsland(island)
				end
				table.remove(list, i)
				removeModel(island, kind, uid)
				local def = catalog(kind).ById[e.id]
				local refund = math.floor((def and def.price or 0) * Config.FurnitureRefund)
				if refund > 0 then
					S.Economy.budgetCredit(island, refund, "refund", player.DisplayName, "Продажа: " .. (def and def.name or ""))
				end
				S.RestaurantService.markDirty(island)
				S.RestaurantService.markWorld()
				return { ok = true, refund = refund }
			end
		end
		return { ok = false, err = "Предмет не найден" }
	end)
end

return BuildService
