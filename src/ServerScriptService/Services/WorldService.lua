-- WorldService: builds the terrain ocean, shallow lagoons around the islands and
-- distant mountains at server start, clouds, water look and a day/night cycle.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)

local WorldService = {}
local S

function WorldService.Init(registry)
	S = registry
end

local function buildTerrain()
	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(28, 140, 170)
	terrain.WaterTransparency = 0.75
	terrain.WaterReflectance = 0.35
	terrain.WaterWaveSize = 0.18
	terrain.WaterWaveSpeed = 9

	-- ocean in chunks (avoid long frame stalls)
	local half = 2400
	local chunk = 600
	for x = -half, half - chunk, chunk do
		for z = -half, half - chunk, chunk do
			terrain:FillBlock(CFrame.new(x + chunk / 2, -14, z + chunk / 2), Vector3.new(chunk, 28, chunk), Enum.Material.Water)
			-- глубокое дно
			terrain:FillBlock(CFrame.new(x + chunk / 2, -32, z + chunk / 2), Vector3.new(chunk, 8, chunk), Enum.Material.Sand)
		end
		task.wait()
	end

	-- shallow lagoons & sandbanks around every island (all terrain stays below the part-built island)
	for i = 1, MapLayout.IslandCount do
		local x, _, z = MapLayout.islandCenter(i)
		local r = MapLayout.IslandRadius + MapLayout.BeachWidth
		-- lagoon floor 4 studs under the surface
		terrain:FillCylinder(CFrame.new(x, -10, z), 12, r + 70, Enum.Material.Sand)
		-- smooth sandy slope from the beach down into the water (no steps, no gaps)
		terrain:FillCylinder(CFrame.new(x, -2.5, z), 9, r + 8, Enum.Material.Sand) -- top -> +2
		terrain:FillCylinder(CFrame.new(x, -2.5, z), 7, r + 14, Enum.Material.Sand) -- top -> +1
		terrain:FillCylinder(CFrame.new(x, -3, z), 6, r + 20, Enum.Material.Sand) -- top ->  0
		terrain:FillCylinder(CFrame.new(x, -4, z), 6, r + 26, Enum.Material.Sand) -- top -> -1
		-- a few coral rocks in the lagoon
		local rng = Random.new(i * 97)
		for _ = 1, 6 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = r + rng:NextNumber(28, 60)
			terrain:FillBall(Vector3.new(x + math.cos(a) * d, -5, z + math.sin(a) * d), rng:NextNumber(3, 6), Enum.Material.Rock)
		end
		task.wait()
	end

	-- distant mountains on the horizon
	local rng = Random.new(2024)
	local count = 22
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local d = rng:NextNumber(1950, 2250)
		local cx, cz = math.cos(a) * d, math.sin(a) * d
		local h = rng:NextNumber(220, 420)
		local w = rng:NextNumber(260, 420)
		-- layered cone: rock body, grass foot, snow cap
		local layers = 7
		for l = 0, layers - 1 do
			local t = l / layers
			local radius = w * (1 - t) * 0.5 + 18
			local y = -20 + h * t
			local mat = Enum.Material.Rock
			if t < 0.25 then
				mat = Enum.Material.Grass
			elseif t > 0.72 then
				mat = Enum.Material.Snow
			end
			terrain:FillBall(Vector3.new(cx + rng:NextNumber(-20, 20), y, cz + rng:NextNumber(-20, 20)), radius, mat)
		end
		task.wait()
	end
end

local function setupSky()
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.45
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = workspace.Terrain
end

local function ambience()
	if Config.Sounds.Ocean ~= "" then
		local s = Instance.new("Sound")
		s.Name = "Ocean"
		s.SoundId = Config.Sounds.Ocean
		s.Looped = true
		s.Volume = 0.35
		s.Parent = workspace
		s:Play()
	end
end

function WorldService.Start()
	local preview = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("OceanPreview")
	task.spawn(function()
		local ok, err = pcall(buildTerrain)
		if not ok then
			warn("[WorldService] terrain: " .. tostring(err))
		elseif preview then
			preview:Destroy()
		end
	end)
	setupSky()
	ambience()
	-- day/night: full cycle 30 min, nights are short
	task.spawn(function()
		Lighting.ClockTime = 9
		while true do
			task.wait(1)
			local t = Lighting.ClockTime
			local speed = (t > 6.5 and t < 18.5) and (24 / 1800) * 1.0 or (24 / 1800) * 2.2
			Lighting.ClockTime = (t + speed) % 24
		end
	end)
end

return WorldService
