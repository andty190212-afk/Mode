-- Restaurant Island Tycoon - server bootstrap
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.init()

local servicesFolder = script.Parent:WaitForChild("Services")
local S = {}
local order = {
	"DataService",
	"EconomyService",
	"MonetizationService",
	"QuestService",
	"EventService",
	"RestaurantService",
	"BuildService",
	"GuestService",
	"KitchenService",
	"StaffService",
	"ShopService",
	"RatingService",
	"BarrierService",
	"HelicopterService",
	"BoatService",
	"WorldService",
	"LabService",
	"CombatService",
	"AdminService",
}

for _, name in ipairs(order) do
	S[name] = require(servicesFolder:WaitForChild(name))
end
S.Economy = S.EconomyService

for _, name in ipairs(order) do
	S[name].Init(S)
end

-- Сначала мир и острова, затем загрузка игроков
local startOrder = {
	"WorldService",
	"RestaurantService",
	"EconomyService",
	"MonetizationService",
	"QuestService",
	"EventService",
	"BuildService",
	"GuestService",
	"KitchenService",
	"StaffService",
	"ShopService",
	"RatingService",
	"BarrierService",
	"HelicopterService",
	"BoatService",
	"LabService",
	"CombatService",
	"AdminService",
	"DataService",
}
for _, name in ipairs(startOrder) do
	local ok, err = pcall(S[name].Start)
	if not ok then
		warn("[Main] failed to start " .. name .. ": " .. tostring(err))
	end
end

-- server script errors are shown on screen in Studio and to the game's creator
do
	local LogService = game:GetService("LogService")
	local RunService = game:GetService("RunService")
	local sent = {}
	LogService.MessageOut:Connect(function(msg, kind)
		if kind ~= Enum.MessageType.MessageError or sent[msg] then
			return
		end
		sent[msg] = true
		for _, p in ipairs(Players:GetPlayers()) do
			if RunService:IsStudio() or p.UserId == game.CreatorId then
				Net.fx(p, "devError", { text = string.sub(msg, 1, 220) })
			end
		end
	end)
end

Players.CharacterAutoLoads = true
print(("[Restaurant Island Tycoon] server ready (%d services)"):format(#order))
