-- Translates every visible text on this client (UI, signs, NPC name tags, prompts)
-- when the player's language is English. Works on top of the existing Russian UI:
-- texts are swapped locally, the server and other players are not affected.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalizationService = game:GetService("LocalizationService")

local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Localizer = {}

local player = Players.LocalPlayer
local PROPS = {
	TextLabel = { "Text" },
	TextButton = { "Text" },
	TextBox = { "PlaceholderText" },
	ProximityPrompt = { "ActionText", "ObjectText" },
}

local original = setmetatable({}, { __mode = "k" }) -- [inst] = { [prop] = russian source }
local applied = setmetatable({}, { __mode = "k" }) -- [inst] = { [prop] = text we set }
local listeners = {}

local function apply(inst, prop)
	local src = original[inst][prop]
	local value = Lang.translate(src)
	applied[inst][prop] = value
	if inst[prop] ~= value then
		inst[prop] = value
	end
end

local function track(inst)
	local props = PROPS[inst.ClassName]
	if not props or original[inst] then
		return
	end
	original[inst], applied[inst] = {}, {}
	for _, prop in ipairs(props) do
		original[inst][prop] = inst[prop]
		apply(inst, prop)
		inst:GetPropertyChangedSignal(prop):Connect(function()
			local now = inst[prop]
			if now == applied[inst][prop] then
				return -- our own change
			end
			original[inst][prop] = now
			apply(inst, prop)
		end)
	end
end

local function watch(root)
	for _, d in ipairs(root:GetDescendants()) do
		track(d)
	end
	root.DescendantAdded:Connect(track)
end

function Localizer.set(lang)
	if lang == Lang.current then
		return
	end
	Lang.current = lang
	player:SetAttribute("Lang", lang)
	for inst, props in pairs(original) do
		if inst.Parent then
			for prop in pairs(props) do
				apply(inst, prop)
			end
		end
	end
	for _, fn in ipairs(listeners) do
		task.spawn(fn, lang)
	end
end

-- the player's choice is saved on the server and restored on the next join
function Localizer.choose(lang)
	Localizer.set(lang)
	task.spawn(function()
		Net.request("SetLanguage", { lang = lang })
	end)
end

function Localizer.toggle()
	Localizer.choose(Lang.current == "en" and "ru" or "en")
end

local savedApplied = false
-- called with the player state: apply a saved choice once
function Localizer.applySaved(lang)
	if savedApplied or (lang ~= "ru" and lang ~= "en") then
		return
	end
	savedApplied = true
	Localizer.set(lang)
end

function Localizer.onChanged(fn)
	table.insert(listeners, fn)
end

function Localizer.current()
	return Lang.current
end

function Localizer.init()
	local locale = ""
	pcall(function()
		locale = player.LocaleId
	end)
	if locale == "" then
		pcall(function()
			locale = LocalizationService.RobloxLocaleId
		end)
	end
	Lang.current = Lang.fromLocale(locale)
	player:SetAttribute("Lang", Lang.current)
	watch(player:WaitForChild("PlayerGui"))
	watch(workspace)
end

return Localizer
