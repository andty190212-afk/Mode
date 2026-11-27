-- World layout shared by the place builder, the server and the client.
-- NOTE: no `script` references - also read by the place builder (Lune).
local MapLayout = {}

MapLayout.IslandCount = 8
MapLayout.RingRadius = 800 -- расстояние от центра мира до центра острова
MapLayout.IslandRadius = 150 -- радиус верхней (травяной) части
MapLayout.BeachWidth = 22
MapLayout.TopY = 6 -- высота поверхности острова
MapLayout.BarrierRadius = 185
MapLayout.LoungePosition = { 0, 160, 0 } -- небесная площадка ожидания

MapLayout.Themes = {
	{ name = "Остров Кокосов", grass = { 96, 168, 72 }, accent = "palm" },
	{ name = "Лагуна Заката", grass = { 110, 160, 80 }, accent = "flower" },
	{ name = "Скалистый Риф", grass = { 88, 150, 78 }, accent = "rock" },
	{ name = "Цветочный Остров", grass = { 104, 176, 84 }, accent = "flower" },
	{ name = "Остров Бриза", grass = { 92, 164, 90 }, accent = "palm" },
	{ name = "Изумрудный Берег", grass = { 72, 156, 76 }, accent = "tree" },
	{ name = "Жемчужная Бухта", grass = { 100, 170, 96 }, accent = "palm" },
	{ name = "Остров Маяка", grass = { 86, 158, 70 }, accent = "rock" },
}

-- Island i (1..8) centre & angle. Local frame: +Z points away from the world centre
-- (towards the dock), building door faces +Z.
function MapLayout.islandAngle(i)
	return (i - 1) * (math.pi * 2 / MapLayout.IslandCount)
end

function MapLayout.islandCenter(i)
	local a = MapLayout.islandAngle(i)
	return MapLayout.RingRadius * math.cos(a), MapLayout.TopY, MapLayout.RingRadius * math.sin(a)
end

-- Building tiers. Origin = centre of the front wall at floor level (door at z=0),
-- building extends to -Z. Dining area: z in [-dining+4, -3]. Kitchen: behind the divider.
MapLayout.BuildingOffsetZ = 10 -- door is 10 studs in front of the island centre
MapLayout.FloorHeight = 0.8 -- building floor surface above the island surface
MapLayout.Tiers = {
	[1] = { width = 36, dining = 22, kitchen = 12, height = 12 },
	[2] = { width = 44, dining = 28, kitchen = 14, height = 13 },
	[3] = { width = 54, dining = 34, kitchen = 16, height = 15 },
	[4] = { width = 64, dining = 40, kitchen = 18, height = 17 },
	[5] = { width = 76, dining = 46, kitchen = 20, height = 20 },
}

function MapLayout.diningRect(tier)
	local t = MapLayout.Tiers[tier]
	return { minX = -t.width / 2 + 2, maxX = t.width / 2 - 2, minZ = -t.dining + 4, maxZ = -3 }
end

-- Reserved rect inside dining area (entrance aisle)
MapLayout.EntranceAisle = { minX = -3.5, maxX = 3.5, minZ = -7, maxZ = 0 }

-- Island decor area: circle of radius (IslandRadius - 8) minus reserved rects (island local coords)
function MapLayout.reservedIslandRects()
	local t = MapLayout.Tiers[5]
	local oz = MapLayout.BuildingOffsetZ
	return {
		-- максимальный размер здания + отступ
		{ minX = -t.width / 2 - 4, maxX = t.width / 2 + 4, minZ = oz - t.dining - t.kitchen - 4, maxZ = oz + 6 },
		-- дорожка от причала к двери
		{ minX = -5, maxX = 5, minZ = oz, maxZ = MapLayout.IslandRadius + 30 },
	}
end

MapLayout.DockLength = 46

return MapLayout
