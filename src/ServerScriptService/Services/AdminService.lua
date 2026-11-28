-- AdminService: in-game admin rights (not only in Studio).
-- The game creator (or the owner of the group that owns the game) is the head admin and can
-- grant/remove admin rights by username. The admin list is saved in a DataStore.
-- Admin tools: give money / restaurant budget, set restaurant stars, boost test stats,
-- give special dishes and creatures. Every request is checked on the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Data = Shared.Data
local Rarities = require(Data.Rarities)

local AdminService = {}
local S

local STORE, KEY = "RIT_Admins_v1", "admins"
local admins = {} -- [userId string] = name

function AdminService.Init(registry)
	S = registry
end

function AdminService.isHeadAdmin(player)
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank == 255
	end
	return player.UserId == game.CreatorId
end

function AdminService.isAdmin(player)
	return AdminService.isHeadAdmin(player) or admins[tostring(player.UserId)] ~= nil
end

local function save()
	pcall(function()
		DataStoreService:GetDataStore(STORE):SetAsync(KEY, admins)
	end)
end

local function load()
	local ok, data = pcall(function()
		return DataStoreService:GetDataStore(STORE):GetAsync(KEY)
	end)
	if ok and type(data) == "table" then
		admins = data
	end
end

local function ok(extra)
	local t = extra or {}
	t.ok = true
	return t
end
local function fail(err)
	return { ok = false, err = err }
end

function AdminService.state(player)
	if not AdminService.isAdmin(player) then
		return { isAdmin = false }
	end
	local list = {}
	for id, name in pairs(admins) do
		table.insert(list, { id = tonumber(id), name = name })
	end
	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(players, { id = p.UserId, name = p.DisplayName, admin = AdminService.isAdmin(p) })
	end
	return { isAdmin = true, isHead = AdminService.isHeadAdmin(player), admins = list, players = players }
end

local function guard(player)
	if not AdminService.isAdmin(player) then
		return false, fail("Только для админов")
	end
	return true
end

local function registerRemotes()
	Net.onRequest("AdminState", function(player)
		return ok({ state = AdminService.state(player) })
	end)

	Net.setRate("AdminGiveMoney", 4, 6)
	Net.onRequest("AdminGiveMoney", function(player, payload)
		local allowed, err = guard(player)
		if not allowed then
			return err
		end
		payload = type(payload) == "table" and payload or {}
		local amount = math.floor(tonumber(payload.amount) or 0)
		if amount <= 0 or amount > 100000000 then
			return fail("Сумма от 1 до 100 000 000")
		end
		local target = Players:GetPlayerByUserId(tonumber(payload.userId) or player.UserId) or player
		if payload.budget then
			local island = S.RestaurantService.islandOf(target)
			if not island or not island.rest then
				return fail("У игрока нет ресторана")
			end
			island.rest.budget += amount
			S.RestaurantService.markDirty(island)
		else
			S.Economy.grant(target, amount, "Админ")
		end
		if target ~= player then
			Net.toast(target, "🎁 Админ " .. player.DisplayName .. " выдал вам $" .. amount, "success")
		end
		return ok()
	end)

	Net.onRequest("AdminGiveCreature", function(player, payload)
		local allowed, err = guard(player)
		if not allowed then
			return err
		end
		local rarity = type(payload) == "table" and payload.rarity
		if not Rarities.valid(rarity) then
			return fail("Нет такой редкости")
		end
		local res = S.LabService.adminGiveCreature(player, rarity)
		if not res then
			return fail("Коллекция заполнена или данные ещё загружаются")
		end
		return ok(res)
	end)

	Net.onRequest("AdminAddAdmin", function(player, payload)
		if not AdminService.isHeadAdmin(player) then
			return fail("Выдавать права может только создатель игры")
		end
		local name = type(payload) == "table" and tostring(payload.name or "") or ""
		name = string.gsub(name, "^%s*(.-)%s*$", "%1")
		if name == "" then
			return fail("Введите ник игрока")
		end
		local target = Players:FindFirstChild(name)
		local id = target and target.UserId
		if not id then
			local okId, res = pcall(function()
				return Players:GetUserIdFromNameAsync(name)
			end)
			id = okId and res or nil
		end
		if not id then
			return fail("Игрок с таким ником не найден")
		end
		admins[tostring(id)] = target and target.DisplayName or name
		save()
		local online = Players:GetPlayerByUserId(id)
		if online then
			Net.toast(online, "🛡️ Вам выданы права админа", "success")
			S.Economy.markPlayer(online)
		end
		return ok()
	end)

	Net.onRequest("AdminRemoveAdmin", function(player, payload)
		if not AdminService.isHeadAdmin(player) then
			return fail("Снимать права может только создатель игры")
		end
		local id = type(payload) == "table" and tonumber(payload.userId)
		if not id or not admins[tostring(id)] then
			return fail("Такого админа нет")
		end
		admins[tostring(id)] = nil
		save()
		local online = Players:GetPlayerByUserId(id)
		if online then
			Net.toast(online, "Права админа сняты", "warn")
			S.Economy.markPlayer(online)
		end
		return ok()
	end)
end

function AdminService.Start()
	task.spawn(load)
	registerRemotes()
end

return AdminService
