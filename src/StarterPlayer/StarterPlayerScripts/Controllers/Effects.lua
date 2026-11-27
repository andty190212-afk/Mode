-- Effects: server-triggered visual/sound effects, announcements, invite popups,
-- role-based ProximityPrompt filtering, background music.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local Effects = {}
local player = Players.LocalPlayer

-- ===================== WORLD POPUPS =====================
local function popup(pos, text, color)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
	part.Parent = workspace.CurrentCamera
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = text
	l.TextScaled = true
	l.Font = UI.Font
	l.TextColor3 = color or T.gold
	l.TextStrokeTransparency = 0.3
	l.Parent = gui
	TweenService:Create(part, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { CFrame = part.CFrame + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(part, 1.7)
end

local function sparkle(pos)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	part.Parent = workspace.CurrentCamera
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Rate = 0
	p.Speed = NumberRange.new(4, 8)
	p.Lifetime = NumberRange.new(0.6, 1)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Color = ColorSequence.new(T.gold)
	p.Parent = part
	p:Emit(25)
	Debris:AddItem(part, 1.5)
end

-- ===================== BANNERS =====================
local function banner(text, color, duration)
	local gui = UI.screen()
	local f = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(640, 54),
		BackgroundColor3 = T.panel,
		ZIndex = 40,
		Parent = gui,
	})
	UI.corner(f, 14)
	UI.stroke(f, color or T.gold, 2, 0.1)
	local l = UI.label(f, text, 19, { font = UI.Font, align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, -20, 1, 0) })
	l.Position = UDim2.fromOffset(10, 0)
	l.ZIndex = 41
	local s = UI.new("UIScale", { Scale = 0.6, Parent = f })
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(duration or 4, function()
		TweenService:Create(s, TweenInfo.new(0.25), { Scale = 0 }):Play()
		task.wait(0.3)
		f:Destroy()
	end)
end
Effects.banner = banner

local function confetti()
	local gui = UI.screen()
	local holder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 45, Parent = gui })
	local colors = { T.gold, T.accent, T.good, T.blue, T.purple, T.bad }
	for i = 1, 60 do
		local c = UI.new("Frame", {
			BackgroundColor3 = colors[(i % #colors) + 1],
			Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18)),
			Position = UDim2.new(math.random(), 0, -0.05, 0),
			Rotation = math.random(0, 360),
			ZIndex = 45,
			Parent = holder,
		})
		TweenService:Create(c, TweenInfo.new(math.random(18, 32) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(c.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
			Rotation = c.Rotation + math.random(-360, 360),
		}):Play()
	end
	Debris:AddItem(holder, 3.5)
end

-- ===================== INVITES =====================
local function invitePopup(index)
	local p = State.player
	local inv
	for _, i in ipairs(p and p.invites or {}) do
		if i.island == index then
			inv = i
		end
	end
	if not inv then
		task.wait(0.6)
		p = State.player
		for _, i in ipairs(p and p.invites or {}) do
			if i.island == index then
				inv = i
			end
		end
	end
	if not inv then
		return
	end
	local gui = UI.screen()
	local f = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.fromOffset(460, 150),
		BackgroundColor3 = T.panel,
		ZIndex = 30,
		Parent = gui,
	})
	UI.corner(f, 16)
	UI.stroke(f, T.purple, 2, 0.1)
	local l = UI.label(f, "✉️ <b>" .. inv.from .. "</b> приглашает вас в ресторан «" .. inv.restaurant .. "»", 17, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, -30, 0, 70) })
	l.Position = UDim2.fromOffset(15, 10)
	l.ZIndex = 31
	local a = UI.button(f, "Принять", T.good, function()
		UI.request(Net, "AcceptInvite", { island = index })
		f:Destroy()
		UI.close("lobby")
	end, { size = UDim2.fromOffset(180, 44) })
	a.Position = UDim2.new(0.5, -190, 1, -56)
	a.ZIndex = 31
	local d = UI.button(f, "Отклонить", T.bad, function()
		UI.request(Net, "DeclineInvite", { island = index })
		f:Destroy()
	end, { size = UDim2.fromOffset(180, 44) })
	d.Position = UDim2.new(0.5, 10, 1, -56)
	d.ZIndex = 31
	task.delay(60, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

-- ===================== PROMPT FILTER =====================
local function promptAllowed(prompt)
	local role = prompt:GetAttribute("Role")
	if role == nil or role == "" then
		return true
	end
	local myRole = State.role()
	if role == "Visitor" then
		-- только для гостей-игроков (не членов команды ресторана)
		local isl = prompt:FindFirstAncestorWhichIsA("Model")
		while isl and not isl.Name:match("^Island%d") do
			isl = isl.Parent and isl.Parent:FindFirstAncestorWhichIsA("Model")
		end
		local index = isl and tonumber(isl.Name:match("%d+"))
		return index ~= State.myIsland()
	end
	for r in string.gmatch(role, "[^,]+") do
		if r == myRole then
			return true
		end
	end
	return false
end

-- hide roof & ceiling locally while the player is inside any restaurant
local MapLayout = require(Shared.MapLayout)
local hiddenParts = {}
local function setRoofHidden(building, hidden)
	local roof = building:FindFirstChild("Roof")
	local list = roof and roof:GetDescendants() or {}
	local ceiling = building:FindFirstChild("Ceiling")
	if ceiling then
		table.insert(list, ceiling)
	end
	for _, p in ipairs(list) do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = hidden and 0.92 or 0
		end
	end
end
local function roofLoop()
	local current = nil
	while true do
		task.wait(0.3)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local inside = nil
		local islands = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Islands")
		if root and islands then
			for _, isl in ipairs(islands:GetChildren()) do
				local b = isl:FindFirstChild("Restaurant")
				local origin = b and b.PrimaryPart
				local tier = b and MapLayout.Tiers[b:GetAttribute("Tier") or 1]
				if origin and tier then
					local lp = origin.CFrame:PointToObjectSpace(root.Position)
					if math.abs(lp.X) < tier.width / 2 and lp.Z < 0.5 and lp.Z > -(tier.dining + tier.kitchen) and lp.Y < tier.height + 2 and lp.Y > -3 then
						inside = b
						break
					end
				end
			end
		end
		if inside ~= current then
			if current and current.Parent then
				setRoofHidden(current, false)
			end
			if inside then
				setRoofHidden(inside, true)
			end
			current = inside
		end
	end
end

function Effects.init(Minigames, HUD)
	task.spawn(roofLoop)
	Net.remote("Fx").OnClientEvent:Connect(function(name, data)
		data = data or {}
		if name == "money" then
			popup(data.pos or Vector3.zero, "+" .. Util.formatMoney(data.amount) .. (data.text and (" " .. data.text) or ""), T.gold)
			UI.sound(Config.Sounds.Cash, 0.4)
			HUD.bumpMoney()
		elseif name == "coins" then
			if data.pos and player.Character and player.Character.PrimaryPart and (player.Character.PrimaryPart.Position - data.pos).Magnitude < 120 then
				popup(data.pos, "💰 " .. Util.formatMoney(data.amount), T.good)
			end
		elseif name == "levelup" then
			if data.prof then
				banner("🎖️ Профессия повышена: уровень " .. data.level, T.blue, 3)
			else
				banner("⬆️ Новый уровень игрока: " .. data.level .. "!", T.purple, 3.5)
				confetti()
			end
			UI.sound(Config.Sounds.Upgrade, 0.5)
		elseif name == "starUp" then
			banner("🌟 Ваш ресторан получил " .. data.stars .. " ★! Новый интерьер и возможности!", T.gold, 6)
			confetti()
			UI.sound(Config.Sounds.Upgrade, 0.6)
		elseif name == "announce" then
			banner(data.text or "", T.accent, 5)
		elseif name == "event" then
			banner(data.text or "", T.warn, 4)
		elseif name == "invite" then
			task.spawn(invitePopup, data.island)
		elseif name == "sparkle" then
			if data.pos then
				sparkle(data.pos)
			end
		elseif name == "ding" or name == "place" or name == "purchase" or name == "upgrade" then
			UI.sound(Config.Sounds.Buy, 0.4)
			if name == "purchase" then
				confetti()
			end
		elseif name == "achievement" then
			confetti()
		elseif name == "openMenu" then
			UI.open(data.menu)
		elseif name == "barrier" then
			banner(data.on and "🛡️ Барьер включён — остров закрыт" or "🟢 Барьер выключен — остров открыт для гостей", T.accent2, 3)
		end
	end)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if not promptAllowed(prompt) then
			prompt.Enabled = false
			task.delay(2, function()
				-- вернуть видимость для следующей проверки (сервер мог изменить состояние)
				if prompt.Parent and not promptAllowed(prompt) then
					return
				end
				if prompt.Parent then
					prompt.Enabled = prompt.Name ~= "TablePrompt" or prompt:GetAttribute("Active") == true
				end
			end)
		end
	end)
	-- при смене профессии заново включить скрытые подсказки
	local lastRole = ""
	State.Changed:Connect(function(key)
		if key == "player" and State.role() ~= lastRole then
			lastRole = State.role()
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d:GetAttribute("Role") and d:GetAttribute("Role") ~= "" then
					if promptAllowed(d) then
						if d.Name == "TablePrompt" then
							d.Enabled = d:GetAttribute("Active") == true
						else
							d.Enabled = true
						end
					end
				end
			end
		end
	end)

	-- background music (configure Config.Sounds.Music)
	if Config.Sounds.Music ~= "" then
		local music = Instance.new("Sound")
		music.SoundId = Config.Sounds.Music
		music.Looped = true
		music.Volume = 0.18
		music.Parent = SoundService
		music:Play()
	end
	if Config.Sounds.Birds ~= "" then
		local birds = Instance.new("Sound")
		birds.SoundId = Config.Sounds.Birds
		birds.Looped = true
		birds.Volume = 0.15
		birds.Parent = SoundService
		birds:Play()
	end
end

return Effects
