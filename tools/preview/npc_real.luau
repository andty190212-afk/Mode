-- Spawns NPCs through the real NPCUtil code (mock engine) and dumps their parts for rendering.
-- Usage: lune run tools/preview/npc_real.luau <out_dir>
local Mock = require("../test/mock")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local OUT = process.args[1] or "build/npc"
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
Mock.loadPlace("build/RestaurantIslandTycoon.rbxl")
local game = Mock.game
local NPCUtil = Mock.env.require(game.ServerScriptService.Services.NPCUtil)
local GuestLooks = Mock.env.require(game.ReplicatedStorage.Shared.Data.GuestLooks)
Mock.call(NPCUtil.preload)

local entries = {}
for _, look in ipairs(GuestLooks.List) do
	table.insert(entries, { name = look.name .. "  (" .. look.stars[1] .. "–" .. look.stars[2] .. "★)", kind = "Guest", opts = { look = look.id } })
end
table.insert(entries, { name = "VIP-гость", kind = "Guest", opts = { vip = true } })
table.insert(entries, { name = "Ресторанный критик", kind = "Guest", opts = { critic = true } })
table.insert(entries, { name = "NPC-повар", kind = "Staff", opts = { role = "Cook" } })
table.insert(entries, { name = "NPC-официант", kind = "Staff", opts = { role = "Waiter" } })
table.insert(entries, { name = "NPC-бармен", kind = "Staff", opts = { role = "Bartender" } })

local index = {}
for i, e in ipairs(entries) do
	e.opts.rng = Mock.env.Random.new(i * 7 + 3)
	local model = NPCUtil.spawn(e.kind, roblox.CFrame.new(0, 3, 0), e.opts)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Transparency or 0) < 0.95 and d.Name ~= "HumanoidRootPart" then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
			local shape = d.Shape and d.Shape.Name or "Block"
			local size = d.Size
			local rot = { r00, r01, r02, r10, r11, r12, r20, r21, r22 }
			if d.Name == "Head" then
				-- Roblox head: rounded cylinder + default face (render only)
				shape = "Cylinder"
				rot = { 0, -1, 0, 1, 0, 0, 0, 0, 1 }
			end
			table.insert(parts, { p = { x, y, z }, r = rot, s = { size.X, size.Y, size.Z }, c = { d.Color.R, d.Color.G, d.Color.B }, t = d.Transparency or 0, shape = shape, n = d.Name, neon = false })
			if d.Name == "Head" then
				local hz = z - size.Z / 2 - 0.02
				for _, ex in ipairs({ -0.22, 0.22 }) do
					table.insert(parts, { p = { x + ex, y + 0.12, hz }, r = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, s = { 0.14, 0.24, 0.04 }, c = { 0.08, 0.08, 0.1 }, t = 0, shape = "Block", n = "Eye", neon = false })
				end
				table.insert(parts, { p = { x, y - 0.25, hz }, r = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, s = { 0.4, 0.07, 0.04 }, c = { 0.35, 0.15, 0.15 }, t = 0, shape = "Block", n = "Mouth", neon = false })
			end
		end
	end
	fs.writeFile(OUT .. "/npc" .. i .. ".json", serde.encode("json", parts))
	table.insert(index, e.name)
	model:Destroy()
end
fs.writeFile(OUT .. "/index.json", serde.encode("json", index))
print(#index .. " NPCs exported, errors: " .. #Mock.errors)
for _, e in ipairs(Mock.errors) do
	print(e)
end
