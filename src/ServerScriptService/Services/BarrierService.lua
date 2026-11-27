-- BarrierService: per-island protective dome. Server-enforced: strangers (and their
-- helicopters) cannot enter while it is on; owner, friend and whitelisted players can.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local MapLayout = require(Shared.MapLayout)

local BarrierService = {}
local S

function BarrierService.Init(registry)
	S = registry
end

local function dome(island)
	return island.model and island.model:FindFirstChild("BarrierDome")
end

function BarrierService.apply(island, forceOff)
	local d = dome(island)
	local on = not forceOff and island.rest ~= nil and island.rest.barrierOn
	if d then
		local r = MapLayout.BarrierRadius * 2
		if on then
			d.Size = Vector3.new(r * 0.2, r * 0.2, r * 0.2)
			d.Transparency = 1
			TweenService:Create(d, TweenInfo.new(1.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(r, r, r), Transparency = 0.82 }):Play()
			local ring = d:FindFirstChild("Hum")
			if ring and ring:IsA("Sound") then
				ring:Play()
			end
		else
			TweenService:Create(d, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(r * 1.15, r * 1.15, r * 1.15), Transparency = 1 }):Play()
		end
	end
	if on then
		BarrierService.enforce(island)
	end
	S.RestaurantService.markWorld()
end

function BarrierService.canEnter(player, island)
	if not island.owner or not island.rest then
		return true
	end
	if S.RestaurantService.isMember(player, island) then
		return true
	end
	if not island.rest.barrierOn then
		return true
	end
	return island.rest.whitelist[tostring(player.UserId)] ~= nil
end

function BarrierService.refreshAccess(island)
	if island.rest and island.rest.barrierOn then
		BarrierService.enforce(island)
	end
end

local function pushOut(island, position)
	local c = island.center
	local dir = Vector3.new(position.X - c.X, 0, position.Z - c.Z)
	if dir.Magnitude < 1 then
		dir = Vector3.new(1, 0, 0)
	end
	return c + dir.Unit * (MapLayout.BarrierRadius + 25) + Vector3.new(0, math.max(position.Y - c.Y, 30), 0)
end

function BarrierService.enforce(island)
	local c = island.center
	local r2 = MapLayout.BarrierRadius ^ 2
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and not BarrierService.canEnter(player, island) then
			local p = root.Position
			local dx, dz = p.X - c.X, p.Z - c.Z
			if dx * dx + dz * dz < r2 and p.Y < c.Y + 260 then
				local heli = S.HelicopterService.vehicleOf(player)
				if heli then
					S.HelicopterService.repel(heli, pushOut(island, heli.PrimaryPart.Position))
				else
					S.RestaurantService.sendHome(player)
				end
				Net.toast(player, "🛡️ Остров «" .. island.rest.name .. "» закрыт защитным барьером", "warn")
			end
		end
	end
end

function BarrierService.Start()
	Net.onRequest("SetBarrier", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island or island.owner ~= player then
			return { ok = false, err = "Барьером управляет только владелец" }
		end
		local on = payload and payload.on == true
		island.rest.barrierOn = on
		BarrierService.apply(island, false)
		Net.fx(player, "barrier", { on = on })
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)

	Net.onRequest("SetWhitelist", function(player, payload)
		local island = S.RestaurantService.islandOf(player)
		if not island or island.owner ~= player then
			return { ok = false, err = "Только владелец" }
		end
		local uid = tonumber(payload and payload.userId)
		if not uid then
			return { ok = false, err = "Некорректный игрок" }
		end
		if payload.allow == true then
			local target = Players:GetPlayerByUserId(uid)
			if not target then
				return { ok = false, err = "Игрок не на сервере" }
			end
			local count = 0
			for _ in pairs(island.rest.whitelist) do
				count += 1
			end
			if count >= 20 then
				return { ok = false, err = "Максимум 20 игроков в списке" }
			end
			island.rest.whitelist[tostring(uid)] = target.DisplayName
			Net.toast(target, "🛡️ " .. player.DisplayName .. " разрешил вам посещать свой остров", "info")
		else
			island.rest.whitelist[tostring(uid)] = nil
			BarrierService.refreshAccess(island)
		end
		S.RestaurantService.markDirty(island)
		return { ok = true }
	end)

	task.spawn(function()
		while true do
			task.wait(0.3)
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.rest and island.rest.barrierOn then
					local ok, err = pcall(BarrierService.enforce, island)
					if not ok then
						warn("[BarrierService] " .. tostring(err))
					end
				end
			end
		end
	end)
end

return BarrierService
