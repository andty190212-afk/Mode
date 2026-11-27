-- Builds RestaurantIslandTycoon.rbxl / .rbxlx from src/ + procedural map & models.
-- Usage:  lune run tools/build_place.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local L = require("./build/lib")
local Models = require("./build/models")
local Tiers = require("./build/tiers")
local Map = require("./build/map")

local Instance = roblox.Instance
local Enum = roblox.Enum

local OUT_DIR = process.args[1] or "build"
local SRC = "src"

local game = Instance.new("DataModel")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
game:GetService("Lighting")
game:GetService("Teams")
game:GetService("Chat")
game:GetService("TextChatService")

local scriptCount = 0

-- ===================== SCRIPTS FROM src/ =====================
local function scriptFor(fileName, source)
	local inst
	local name
	if fileName:match("%.server%.lua$") then
		inst = Instance.new("Script")
		name = fileName:gsub("%.server%.lua$", "")
	elseif fileName:match("%.client%.lua$") then
		inst = Instance.new("LocalScript")
		name = fileName:gsub("%.client%.lua$", "")
	else
		inst = Instance.new("ModuleScript")
		name = fileName:gsub("%.lua$", "")
	end
	inst.Name = name
	inst.Source = source
	scriptCount += 1
	return inst
end

local function loadDir(dir, parent)
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in ipairs(entries) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			local existing = parent:FindFirstChild(entry)
			local folder = existing or L.new("Folder", parent, { Name = entry })
			loadDir(path, folder)
		elseif entry:match("%.lua$") then
			local inst = scriptFor(entry, fs.readFile(path))
			inst.Parent = parent
		end
	end
end

loadDir(SRC .. "/ReplicatedStorage", ReplicatedStorage)
loadDir(SRC .. "/ServerScriptService", ServerScriptService)
if fs.isDir(SRC .. "/ServerStorage") then
	loadDir(SRC .. "/ServerStorage", ServerStorage)
end
local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts") or L.new("StarterPlayerScripts", StarterPlayer, { Name = "StarterPlayerScripts" })
local scs = StarterPlayer:FindFirstChild("StarterCharacterScripts") or L.new("StarterCharacterScripts", StarterPlayer, { Name = "StarterCharacterScripts" })
loadDir(SRC .. "/StarterPlayer/StarterPlayerScripts", sps)

-- ===================== REMOTES =====================
local remotes = L.new("Folder", ReplicatedStorage, { Name = "Remotes" })
L.new("RemoteFunction", remotes, { Name = "Request" })
for _, n in ipairs({ "Action", "Push", "Toast", "Fx" }) do
	L.new("RemoteEvent", remotes, { Name = n })
end

-- ===================== ASSETS / TIERS / MAP =====================
Models.buildAssets(ReplicatedStorage)
Tiers.buildAll(ServerStorage)
Map.build(Workspace)
Map.buildLighting(game)

-- ===================== SETTINGS =====================
Workspace.StreamingEnabled = false
Players.CharacterAutoLoads = true
pcall(function()
	Players.MaxPlayers = 16
end)
StarterPlayer.CharacterWalkSpeed = 18
StarterPlayer.CharacterJumpPower = 50
SoundService.AmbientReverb = Enum.ReverbType.NoReverb

-- loading screen (removed by the client once the UI is built)
local loading = L.new("ScreenGui", StarterGui, { Name = "Loading", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 100 })
local bg = L.new("Frame", loading, {
	Name = "Background",
	Size = roblox.UDim2.fromScale(1, 1),
	BackgroundColor3 = L.rgb(20, 24, 40),
	BorderSizePixel = 0,
})
L.new("UIGradient", bg, { Color = roblox.ColorSequence.new(L.rgb(30, 60, 110), L.rgb(15, 18, 30)), Rotation = 90 })
local title = L.new("TextLabel", bg, {
	Name = "Title",
	Size = roblox.UDim2.fromScale(0.8, 0.15),
	Position = roblox.UDim2.fromScale(0.1, 0.35),
	BackgroundTransparency = 1,
	Text = "🏝️ Restaurant Island Tycoon",
	TextScaled = true,
	TextColor3 = L.rgb(255, 230, 160),
	FontFace = roblox.Font.fromEnum(Enum.Font.GothamBold),
})
L.new("TextLabel", bg, {
	Name = "Sub",
	Size = roblox.UDim2.fromScale(0.6, 0.05),
	Position = roblox.UDim2.fromScale(0.2, 0.52),
	BackgroundTransparency = 1,
	Text = "Загрузка островов...",
	TextScaled = true,
	TextColor3 = L.rgb(200, 210, 240),
	FontFace = roblox.Font.fromEnum(Enum.Font.GothamMedium),
})

-- ===================== WRITE =====================
if not fs.isDir(OUT_DIR) then
	fs.writeDir(OUT_DIR)
end
local binary = roblox.serializePlace(game)
local xml = roblox.serializePlace(game, true)
fs.writeFile(OUT_DIR .. "/RestaurantIslandTycoon.rbxl", binary)
fs.writeFile(OUT_DIR .. "/RestaurantIslandTycoon.rbxlx", xml)

-- ===================== SELF-CHECK =====================
local reloaded = roblox.deserializePlace(fs.readFile(OUT_DIR .. "/RestaurantIslandTycoon.rbxl"))
local counts = { parts = 0, scripts = 0, models = 0 }
for _, d in ipairs(reloaded:GetDescendants()) do
	if d:IsA("BasePart") then
		counts.parts += 1
	elseif d:IsA("LuaSourceContainer") then
		counts.scripts += 1
	elseif d:IsA("Model") then
		counts.models += 1
	end
end
local islands = reloaded:GetService("Workspace").Map.Islands:GetChildren()
print(("Wrote %s/RestaurantIslandTycoon.rbxl (%d KB) and .rbxlx (%d KB)"):format(OUT_DIR, #binary // 1024, #xml // 1024))
print(("Islands: %d | tiers: %d | parts: %d | models: %d | scripts: %d"):format(
	#islands,
	#reloaded:GetService("ServerStorage").RestaurantTiers:GetChildren(),
	counts.parts,
	counts.models,
	counts.scripts
))
local wsParts = 0
for _, d in ipairs(reloaded:GetService("Workspace"):GetDescendants()) do
	if d:IsA("BasePart") then
		wsParts += 1
	end
end
print("Workspace parts: " .. wsParts)
