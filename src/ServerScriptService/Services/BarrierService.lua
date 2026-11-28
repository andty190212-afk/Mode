-- BarrierService: a PERMANENT barrier around every owned island. Strangers can get onto an
-- island ONLY through its laboratory (lab -> walkway -> island). Boats, swimming, helicopters,
-- jumping or teleporting in from anywhere else -> they are sent back to the lab entrance.
-- When the owner closes the lab with the plate, strangers can't even be inside the lab, so
-- the island is sealed. The island team and players trusted in the lab may always enter.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local MapLayout = require(Shared.MapLayout)

local BarrierService = {}
local S

local PASS_WINDOW = 25 -- seconds: a stranger who was inside the open lab may walk onto the island
local lastLab = {} -- [player] = { [islandIndex] = os.clock() }
local inside = {} -- [player] = { [islandIndex] = true } (already legitimately on the island)
local lastToast = {}

function BarrierService.Init(registry)
	S = registry
end

function BarrierService.apply(island)
	if island.rest then
		island.rest.barrierOn = false -- the old on/off barrier setting no longer exists
	end
end

-- may this player enter the island right now?
function BarrierService.canEnter(player, island)
	if not island.owner then
		return true
	end
	if S.RestaurantService.isMember(player, island) or S.LabService.isTrustedOn(player, island) then
		return true
	end
	local t = lastLab[player] and lastLab[player][island.index]
	return t ~= nil and os.clock() - t <= PASS_WINDOW
end

function BarrierService.refreshAccess() end

function BarrierService.enforce() end

local function horizontalDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function sendToLab(player, island)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		hum.Sit = false
	end
	local cf = S.LabService.entryCFrame(island)
	if cf and char then
		char:PivotTo(cf)
	end
	local now = os.clock()
	if not lastToast[player] or now - lastToast[player] > 3 then
		lastToast[player] = now
		Net.toast(player, "🛡️ Барьер! На чужой остров можно пройти только через лабораторию", "warn")
	end
end

-- ===================== SOLID WALLS (collision groups) =====================
local PhysicsService = game:GetService("PhysicsService")
local groupsReady = false

local function setupGroups()
	local ok = pcall(function()
		for i = 1, MapLayout.IslandCount do
			local wallGroup, teamGroup = "Barrier_" .. i, "Team_" .. i
			pcall(function()
				PhysicsService:RegisterCollisionGroup(wallGroup)
			end)
			pcall(function()
				PhysicsService:RegisterCollisionGroup(teamGroup)
			end)
			PhysicsService:CollisionGroupSetCollidable(wallGroup, teamGroup, false)
		end
	end)
	groupsReady = ok
end

local function wallsOf(island)
	return island.model and island.model:FindFirstChild("BarrierWalls")
end

-- walls are solid only while the island has an owner
local function updateWalls(island)
	local walls = wallsOf(island)
	if not walls then
		return
	end
	local solid = island.owner ~= nil
	if walls:GetAttribute("Solid") == solid then
		return
	end
	walls:SetAttribute("Solid", solid)
	for _, p in ipairs(walls:GetChildren()) do
		if p:IsA("BasePart") then
			p.CanCollide = solid
			if groupsReady then
				pcall(function()
					p.CollisionGroup = "Barrier_" .. island.index
				end)
			end
		end
	end
end

-- team members' characters ignore their own island's walls
local function updateCharacterGroup(player)
	local char = player.Character
	if not char or not groupsReady then
		return
	end
	local island = S.RestaurantService.islandOf(player)
	local want = island and ("Team_" .. island.index) or "Default"
	if char:GetAttribute("BarrierGroup") == want then
		return
	end
	char:SetAttribute("BarrierGroup", want)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function()
				d.CollisionGroup = want
			end)
		end
	end
end

local function tick()
	local now = os.clock()
	for _, island in pairs(S.RestaurantService.Islands) do
		updateWalls(island)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		updateCharacterGroup(player)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local pos = root.Position
			lastLab[player] = lastLab[player] or {}
			inside[player] = inside[player] or {}
			for _, island in pairs(S.RestaurantService.Islands) do
				if island.owner and island.center then
					local i = island.index
					-- passing through the OPEN lab grants the right to walk onto the island
					if S.LabService.isOpen(island) and S.LabService.inLab(island, pos) then
						lastLab[player][i] = now
					end
					local inZone = horizontalDist(pos, island.center) <= MapLayout.BarrierRadius and pos.Y < 120
					if inZone then
						if not inside[player][i] then
							if BarrierService.canEnter(player, island) then
								inside[player][i] = true
							else
								sendToLab(player, island)
							end
						end
					else
						inside[player][i] = nil
					end
				end
			end
		end
	end
end

function BarrierService.Start()
	setupGroups()
	Players.PlayerRemoving:Connect(function(p)
		lastLab[p], inside[p], lastToast[p] = nil, nil, nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				warn("[BarrierService] " .. tostring(err))
			end
		end
	end)
end

return BarrierService
