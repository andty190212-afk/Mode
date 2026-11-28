local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local place = roblox.deserializePlace(fs.readFile("build/RestaurantIslandTycoon.rbxl"))
local folder = place:GetService("ReplicatedStorage").Assets.Creatures
local C = require("../../src/ReplicatedStorage/Shared/Data/Creatures")
local from, to = tonumber(process.args[1]), tonumber(process.args[2])
local out = {}
local idx = 0
for i = from, to do
	local def = C.List[i]
	local m = folder:FindFirstChild(def.id)
	idx += 1
	local off = roblox.CFrame.new(((idx - 1) % 5) * 8, 0, math.floor((idx - 1) / 5) * 9) * roblox.CFrame.Angles(0, math.rad(200), 0)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.95 then
			local cf = off * p.CFrame
			local x, y, z, a, b, c, d, e, f, g, h, k = cf:GetComponents()
			local shape = "Block"
			if p.ClassName == "Part" then shape = p.Shape.Name elseif p.ClassName == "WedgePart" then shape = "Wedge" end
			local mesh = p:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType.Name == "Sphere" then shape = "Ball" end
			table.insert(out, { p = { x, y, z }, r = { a, b, c, d, e, f, g, h, k }, s = { p.Size.X, p.Size.Y, p.Size.Z }, c = { p.Color.R, p.Color.G, p.Color.B }, t = p.Transparency, shape = shape, n = p.Name, neon = p.Material.Name == "Neon" })
		end
	end
end
fs.writeFile(process.args[3], serde.encode("json", out))
