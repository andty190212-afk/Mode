-- Packs the whole game into ONE model file (RIT_Install.rbxm) that can be imported into an
-- existing place with File -> Import Roblox Model, then installed with one command-bar line.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local place = roblox.deserializePlace(fs.readFile("build/RestaurantIslandTycoon.rbxl"))
local root = Instance.new("Folder")
root.Name = "RIT_Install"

local function pack(serviceName, source, skip)
	local f = Instance.new("Folder")
	f.Name = serviceName
	for _, child in ipairs(source:GetChildren()) do
		if not (skip and skip[child.Name]) then
			child:Clone().Parent = f
		end
	end
	f.Parent = root
end

pack("Workspace", place:GetService("Workspace"), { Camera = true, Terrain = true })
pack("ReplicatedStorage", place:GetService("ReplicatedStorage"))
pack("ReplicatedFirst", place:GetService("ReplicatedFirst"))
pack("ServerScriptService", place:GetService("ServerScriptService"))
pack("ServerStorage", place:GetService("ServerStorage"))
pack("Lighting", place:GetService("Lighting"))
pack("StarterPlayerScripts", place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"))

local readme = Instance.new("StringValue")
readme.Name = "README"
readme.Value = "Paste the install command from docs/INSTALL_INTO_EXISTING_GAME.md into the Studio command bar"
readme.Parent = root

fs.writeFile("dist/RIT_Install.rbxm", roblox.serializeModel({ root }))
print("Wrote dist/RIT_Install.rbxm (" .. #fs.readFile("dist/RIT_Install.rbxm") // 1024 .. " KB)")
