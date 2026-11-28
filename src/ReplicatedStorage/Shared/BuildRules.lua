-- Placement rules shared by the server (authoritative) and the client (ghost preview).
local Shared = script.Parent
local MapLayout = require(Shared.MapLayout)
local Furniture = require(Shared.Data.Furniture)
local Decor = require(Shared.Data.Decor)

local BuildRules = {}

function BuildRules.catalog(kind)
	return kind == "decor" and Decor or Furniture
end

function BuildRules.listOf(rest, kind)
	return kind == "decor" and rest.decor or rest.furniture
end

function BuildRules.halfExtents(def, r)
	local sx, sz = def.size[1], def.size[2]
	if r % 180 ~= 0 then
		sx, sz = sz, sx
	end
	return sx / 2, sz / 2
end

function BuildRules.rectOf(def, x, z, r)
	local hx, hz = BuildRules.halfExtents(def, r)
	return { minX = x - hx, maxX = x + hx, minZ = z - hz, maxZ = z + hz }
end

local function overlap(a, b, pad)
	pad = pad or 0
	return a.minX < b.maxX - pad and a.maxX > b.minX + pad and a.minZ < b.maxZ - pad and a.maxZ > b.minZ + pad
end
BuildRules.overlap = overlap

local function inside(inner, outer)
	return inner.minX >= outer.minX and inner.maxX <= outer.maxX and inner.minZ >= outer.minZ and inner.maxZ <= outer.maxZ
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- rest: restaurant data {stars, furniture, decor}
function BuildRules.validate(rest, kind, id, x, z, r, ignoreUid)
	local cat = BuildRules.catalog(kind)
	local def = cat.ById[id]
	if not def then
		return false, "Неизвестный предмет"
	end
	if not (finite(x) and finite(z) and finite(r)) then
		return false, "Некорректная позиция"
	end
	if r % 90 ~= 0 then
		return false, "Некорректный поворот"
	end
	local rect = BuildRules.rectOf(def, x, z, r)
	if kind == "furniture" then
		local area = MapLayout.diningRect(rest.stars)
		if not inside(rect, area) then
			return false, "Предмет должен стоять внутри зала ресторана"
		end
		if not def.flat and overlap(rect, MapLayout.EntranceAisle) then
			return false, "Нельзя загораживать вход"
		end
		local stairs = MapLayout.Tiers[rest.stars] and MapLayout.Tiers[rest.stars].stairs
		if stairs and overlap(rect, stairs) then
			return false, "Здесь лестница на второй этаж"
		end
	else
		local radius = MapLayout.IslandRadius - 6
		for _, c in ipairs({ { rect.minX, rect.minZ }, { rect.maxX, rect.minZ }, { rect.minX, rect.maxZ }, { rect.maxX, rect.maxZ } }) do
			if c[1] * c[1] + c[2] * c[2] > radius * radius then
				return false, "Только в пределах вашего острова"
			end
		end
		for _, res in ipairs(MapLayout.reservedIslandRects()) do
			if overlap(rect, res) then
				return false, "Здесь место для ресторана и дорожки к причалу"
			end
		end
	end
	for _, e in ipairs(BuildRules.listOf(rest, kind)) do
		if e.uid ~= ignoreUid then
			local other = cat.ById[e.id]
			if other and (def.flat == other.flat or (not def.flat and not other.flat)) then
				if overlap(rect, BuildRules.rectOf(other, e.x, e.z, e.r or 0), 0.05) then
					return false, "Место занято другим предметом"
				end
			end
		end
	end
	return true
end

-- Local frames (same math on server and client)
function BuildRules.islandCFrame(index)
	local x, y, z = MapLayout.islandCenter(index)
	local center = Vector3.new(x, y, z)
	local outward = Vector3.new(x, 0, z).Unit
	return CFrame.lookAt(center, center - outward)
end

function BuildRules.frameFor(index, kind)
	local cf = BuildRules.islandCFrame(index)
	if kind == "furniture" then
		return cf * CFrame.new(0, MapLayout.FloorHeight, MapLayout.BuildingOffsetZ)
	end
	return cf
end

return BuildRules
