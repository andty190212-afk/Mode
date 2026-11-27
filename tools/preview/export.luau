-- Export part geometry of a model in the built place to JSON for the preview renderer
-- Usage: lune run tools/preview/export.luau <path.in.place> <out.json>
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local place = roblox.deserializePlace(fs.readFile("build/RestaurantIslandTycoon.rbxl"))
local target = place
for seg in string.gmatch(process.args[1], "[^%.]+") do
	target = target:FindFirstChild(seg) or error("not found: " .. seg)
end
local origin = nil
if process.args[3] then
	-- optional: also place a furniture/decor layout? not needed
end
local out = {}
local function add(p)
	local cf = p.CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local shape = "Block"
	if p.ClassName == "Part" or p.ClassName == "SpawnLocation" then
		shape = p.Shape.Name
	elseif p.ClassName == "WedgePart" then
		shape = "Wedge"
	end
	table.insert(out, {
		p = { x, y, z }, r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		s = { p.Size.X, p.Size.Y, p.Size.Z }, c = { p.Color.R, p.Color.G, p.Color.B },
		t = p.Transparency, shape = shape, n = p.Name, neon = p.Material.Name == "Neon",
	})
end
-- optional: place restaurant tier N on island I (as the server does at runtime)
local tierArg, islandArg = tonumber(process.args[3]), tonumber(process.args[4])
if tierArg and islandArg then
	local MapLayout = require("../../src/ReplicatedStorage/Shared/MapLayout")
	local x, y, z = MapLayout.islandCenter(islandArg)
	local center = roblox.Vector3.new(x, y, z)
	local outward = roblox.Vector3.new(x, 0, z).Unit
	local bcf = roblox.CFrame.lookAt(center, center - outward) * roblox.CFrame.new(0, MapLayout.FloorHeight, MapLayout.BuildingOffsetZ)
	local tier = place:GetService("ServerStorage").RestaurantTiers:FindFirstChild("Tier" .. tierArg)
	for _, d in ipairs(tier:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local orig = d.CFrame
			d.CFrame = bcf * orig
			add(d)
			d.CFrame = orig
		end
	end
end
if process.args[3] == "grid" then
	-- lay out child models in a grid (asset preview)
	local i = 0
	for _, child in ipairs(target:GetChildren()) do
		local gx, gz = (i % 6) * 26, math.floor(i / 6) * 26
		local parts = child:IsA("BasePart") and { child } or child:GetDescendants()
		for _, d in ipairs(parts) do
			if d:IsA("BasePart") and d.Transparency < 0.95 then
				local orig = d.CFrame
				d.CFrame = roblox.CFrame.new(gx, 0, gz) * orig
				add(d)
				d.CFrame = orig
			end
		end
		i += 1
	end
	fs.writeFile(process.args[2], serde.encode("json", out))
	print(#out .. " parts (grid)")
	return
end
if target:IsA("BasePart") then add(target) end
for _, d in ipairs(target:GetDescendants()) do
	if d:IsA("BasePart") and d.Transparency < 0.95 then add(d) end
end
fs.writeFile(process.args[2], serde.encode("json", out))
print(#out .. " parts")
