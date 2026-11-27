-- HelicopterService: buying (personal money, unlocks at 3★ + helipad), spawning on
-- the island helipad, network ownership for smooth client flight, barrier repel,
-- despawn of abandoned helicopters.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Helicopters = require(Shared.Data.Helicopters)

local HelicopterService = {}
local S
local active = {} -- [player] = {model, island, lastOccupied}
local folder

function HelicopterService.Init(registry)
	S = registry
end

local function playerStars(player)
	local island = S.RestaurantService.islandOf(player)
	if island and island.rest then
		return island.rest.stars
	end
	local p = S.DataService.get(player)
	return p and p.data.restaurant.stars or 1
end

function HelicopterService.vehicleOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat.Name == "PilotSeat" then
		local model = seat:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("Helicopter") then
			return model
		end
	end
	return nil
end

function HelicopterService.repel(model, position)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local seat = model:FindFirstChild("PilotSeat", true)
	local pilot = seat and seat.Occupant and Players:GetPlayerFromCharacter(seat.Occupant.Parent)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	model:PivotTo(CFrame.new(position) * model:GetPivot().Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	task.delay(0.6, function()
		if pilot and model.Parent and root.Parent then
			pcall(function()
				root:SetNetworkOwner(pilot)
			end)
		end
	end)
end

local function despawn(player)
	local a = active[player]
	if a then
		if a.model then
			a.model:Destroy()
		end
		active[player] = nil
	end
end

function HelicopterService.despawnForIsland(island)
	for player, a in pairs(active) do
		if a.island == island then
			despawn(player)
		end
	end
end

local function spawnFor(player)
	local island = S.RestaurantService.islandOf(player)
	if not island then
		return false, "Вы не в ресторане"
	end
	local p = S.DataService.get(player)
	local id = p and p.data.helicopters.equipped
	local def = id and Helicopters.ById[id]
	if not def or not p.data.helicopters.owned[id] then
		return false, "Сначала купите вертолёт"
	end
	local padEntry = S.BuildService.decorEntry(island, "helipad")
	if not padEntry then
		return false, "Постройте вертолётную площадку (Строительство → Остров → Транспорт)"
	end
	despawn(player)
	local template = ReplicatedStorage.Assets.Helicopters:FindFirstChild(def.id)
	if not template then
		return false, "Модель вертолёта не найдена"
	end
	local model = template:Clone()
	local root = model:FindFirstChild("Root")
	model.PrimaryPart = root
	Util.weldModel(model, root, false)
	root.Massless = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = d.Name == "Skid" or d.Name == "Root"
		end
	end
	model:SetAttribute("Helicopter", true)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("ModelId", def.id)
	model:SetAttribute("Speed", def.speed)
	model:SetAttribute("Climb", def.climb)
	model:SetAttribute("Turn", def.turn)
	model:SetAttribute("Accel", def.accel)
	-- flight constraints (driven locally by the pilot's client)
	local att = Instance.new("Attachment")
	att.Name = "FlightAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Lift"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 0
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Gyro"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 0
	ao.Responsiveness = 18
	ao.CFrame = CFrame.new()
	ao.Parent = root
	local padCf = island.cframe * CFrame.new(padEntry.x, 0, padEntry.z) * CFrame.Angles(0, math.rad(padEntry.r or 0), 0)
	if not folder then
		folder = workspace:FindFirstChild("Helicopters") or Instance.new("Folder")
		folder.Name = "Helicopters"
		folder.Parent = workspace
	end
	model:PivotTo(padCf * CFrame.new(0, 4, 0))
	model.Parent = folder
	local seat = model:FindFirstChild("PilotSeat", true)
	active[player] = { model = model, island = island, lastOccupied = os.clock() }
	if seat then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PilotPrompt"
		prompt.ActionText = "Сесть за штурвал"
		prompt.ObjectText = def.name
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = seat
		prompt.Triggered:Connect(function(who)
			local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
			if hum and not seat.Occupant and hum.Health > 0 then
				seat:Sit(hum)
			end
		end)
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local hum = seat.Occupant
			if not hum then
				return
			end
			local who = Players:GetPlayerFromCharacter(hum.Parent)
			local allowed = who == player or (who and S.RestaurantService.islandOf(who) == island)
			if not allowed then
				task.defer(function()
					hum.Sit = false
				end)
				if who then
					Net.toast(who, "Это чужой вертолёт", "warn")
				end
				return
			end
			pcall(function()
				root:SetNetworkOwner(who)
			end)
			if active[player] then
				active[player].lastOccupied = os.clock()
			end
		end)
	end
	pcall(function()
		root:SetNetworkOwner(player)
	end)
	return true
end

function HelicopterService.Start()
	Net.onRequest("BuyHelicopter", function(player, payload)
		local def = payload and type(payload.id) == "string" and Helicopters.ById[payload.id]
		if not def then
			return { ok = false, err = "Нет такой модели" }
		end
		local p = S.DataService.get(player)
		if not p then
			return { ok = false }
		end
		if p.data.helicopters.owned[def.id] then
			p.data.helicopters.equipped = def.id
			S.Economy.markPlayer(player)
			return { ok = true }
		end
		local stars = math.max(playerStars(player), p.data.restaurant.stars)
		if stars < math.max(def.stars, Config.HelicopterUnlockStars) then
			return { ok = false, err = "Вертолёт «" .. def.name .. "» откроется на " .. def.stars .. "★" }
		end
		if not S.Economy.spend(player, def.price, "Вертолёт " .. def.name) then
			return { ok = false, err = "Нужно $" .. def.price .. " личных денег" }
		end
		p.data.helicopters.owned[def.id] = true
		p.data.helicopters.equipped = def.id
		S.QuestService.add(player, "helicoptersOwned", 1)
		Net.toast(player, "🚁 Вы купили вертолёт «" .. def.name .. "»!", "success")
		S.Economy.markPlayer(player)
		return { ok = true }
	end)

	Net.onRequest("SpawnHelicopter", function(player)
		local success, err = spawnFor(player)
		return { ok = success, err = err }
	end)

	Net.onRequest("DespawnHelicopter", function(player)
		despawn(player)
		return { ok = true }
	end)

	Players.PlayerRemoving:Connect(despawn)

	-- abandoned helicopters / out of bounds
	task.spawn(function()
		while true do
			task.wait(5)
			for player, a in pairs(active) do
				local model = a.model
				if not model or not model.Parent or not model.PrimaryPart then
					active[player] = nil
				else
					local seat = model:FindFirstChild("PilotSeat", true)
					if seat and seat.Occupant then
						a.lastOccupied = os.clock()
					end
					local pos = model.PrimaryPart.Position
					if pos.Y < -40 or Vector3.new(pos.X, 0, pos.Z).Magnitude > Config.WorldRadius + 300 then
						despawn(player)
						if player.Parent then
							Net.toast(player, "🚁 Вертолёт возвращён (вне зоны полётов)", "warn")
						end
					elseif os.clock() - a.lastOccupied > 120 then
						despawn(player)
					end
				end
			end
		end
	end)
end

return HelicopterService
