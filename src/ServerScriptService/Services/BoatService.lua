-- BoatService: one drivable boat at the dock of every island.
-- Anyone may drive it (the island barrier still applies). The boat is anchored while
-- nobody drives it (cheap, floats in place); the driver's client steers it on the water.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local BoatService = {}
local S
local boats = {} -- [islandIndex] = {model, root, spot, lastOccupied}

BoatService.Speed = 42
BoatService.Turn = 1.1

function BoatService.Init(registry)
	S = registry
end

local function folder()
	local f = workspace:FindFirstChild("Boats")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Boats"
		f.Parent = workspace
	end
	return f
end

local function park(entry, cf)
	local model, root = entry.model, entry.root
	if not model.Parent then
		return
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- upright, on the water, keep heading
	local pos = cf.Position
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local target = CFrame.lookAt(Vector3.new(pos.X, entry.floatY, pos.Z), Vector3.new(pos.X, entry.floatY, pos.Z) + flat.Unit)
	model:PivotTo(target)
end

local function spawnBoat(island)
	local spot = island.model:FindFirstChild("BoatSpot")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Vehicles") and assets.Vehicles:FindFirstChild("Boat")
	if not spot or not template then
		return
	end
	local model = template:Clone()
	model.Name = "Boat_" .. island.index
	local root = model:FindFirstChild("Root")
	model.PrimaryPart = root
	Util.weldModel(model, root, true)
	root.Massless = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = d == root
		end
	end
	model:SetAttribute("Vehicle", "Boat")
	model:SetAttribute("Speed", BoatService.Speed)
	model:SetAttribute("Turn", BoatService.Turn)
	model:SetAttribute("FloatY", spot.Position.Y)
	local att = Instance.new("Attachment")
	att.Name = "FlightAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Lift"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 0
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Gyro"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 0
	ao.Responsiveness = 15
	ao.Parent = root
	model:PivotTo(spot.CFrame * CFrame.new(0, 0, 0))
	model.Parent = folder()
	local entry = { model = model, root = root, spot = spot.CFrame, floatY = spot.Position.Y, lastOccupied = 0, island = island }
	boats[island.index] = entry
	park(entry, spot.CFrame)

	local seat = model:FindFirstChild("BoatSeat", true)
	if seat then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BoatPrompt"
		prompt.ActionText = "Управлять лодкой"
		prompt.ObjectText = "Лодка"
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = seat
		prompt.Triggered:Connect(function(who)
			local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not seat.Occupant then
				seat:Sit(hum)
			end
		end)
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local hum = seat.Occupant
			if hum then
				local who = Players:GetPlayerFromCharacter(hum.Parent)
				entry.lastOccupied = os.clock()
				root.Anchored = false
				if who then
					pcall(function()
						root:SetNetworkOwner(who)
					end)
				end
			else
				entry.lastOccupied = os.clock()
				task.delay(1.5, function()
					if not seat.Occupant and model.Parent then
						park(entry, root.CFrame)
					end
				end)
			end
		end)
	end
end

function BoatService.boatOf(island)
	return boats[island.index] and boats[island.index].model
end

function BoatService.Start()
	for _, island in pairs(S.RestaurantService.Islands) do
		local ok, err = pcall(spawnBoat, island)
		if not ok then
			warn("[BoatService] " .. tostring(err))
		end
	end
	-- return abandoned / sunk / lost boats to their dock
	task.spawn(function()
		while true do
			task.wait(10)
			for _, entry in pairs(boats) do
				local seat = entry.model:FindFirstChild("BoatSeat", true)
				local occupied = seat and seat.Occupant ~= nil
				if occupied then
					entry.lastOccupied = os.clock()
				else
					local pos = entry.root.Position
					local far = (pos - entry.spot.Position).Magnitude > 25
					local lost = pos.Y < entry.floatY - 10 or pos.Y > entry.floatY + 30
					if lost or (far and os.clock() - entry.lastOccupied > 120) then
						park(entry, entry.spot)
					end
				end
			end
		end
	end)
end

return BoatService
