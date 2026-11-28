-- Shows script errors on screen (in Studio and for the game's creator only) so problems
-- that never appear in automated tests can be reported with a single screenshot.
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local DevErrors = {}
local player = Players.LocalPlayer
local panel, list
local seen = {}
local count = 0

local function allowed()
	return RunService:IsStudio() or player.UserId == game.CreatorId
end

function DevErrors.show(text, source)
	if not allowed() or type(text) ~= "string" then
		return
	end
	text = string.sub(text, 1, 220)
	if seen[text] then
		return
	end
	seen[text] = true
	count += 1
	if count > 12 then
		return
	end
	if not panel then
		local gui = Instance.new("ScreenGui")
		gui.Name = "DevErrors"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 200
		gui.Parent = player:WaitForChild("PlayerGui")
		panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.AnchorPoint = Vector2.new(0, 1)
		panel.Position = UDim2.new(0, 110, 1, -20)
		panel.Size = UDim2.fromOffset(620, 40)
		panel.AutomaticSize = Enum.AutomaticSize.Y
		panel.BackgroundColor3 = Color3.fromRGB(70, 10, 10)
		panel.BackgroundTransparency = 0.1
		panel.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 2)
		layout.Parent = panel
		local title = Instance.new("TextButton")
		title.Size = UDim2.new(1, 0, 0, 22)
		title.BackgroundTransparency = 1
		title.TextColor3 = Color3.fromRGB(255, 220, 120)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.Text = "⚠️ Ошибки скриптов (видно только в Studio и создателю игры). Сделайте скриншот. [нажмите, чтобы скрыть]"
		title.Parent = panel
		title.Activated:Connect(function()
			panel.Visible = false
		end)
		list = panel
	end
	panel.Visible = true
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.Code
	l.TextSize = 13
	l.Text = (source or "client") .. ": " .. text
	l.Parent = list
end

function DevErrors.init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		remotes:WaitForChild("Fx").OnClientEvent:Connect(function(name, data)
			if name == "devError" and data then
				DevErrors.show(data.text, "server")
			end
		end)
	end)
	LogService.MessageOut:Connect(function(msg, kind)
		if kind == Enum.MessageType.MessageError then
			DevErrors.show(msg, "client")
		end
	end)
end

return DevErrors
