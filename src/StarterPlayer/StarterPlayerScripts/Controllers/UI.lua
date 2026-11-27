-- UI: small declarative UI toolkit (theme, windows with tabs, buttons, toasts),
-- responsive scaling for PC / tablet / phone.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = {}
local player = Players.LocalPlayer

UI.Theme = {
	bg = Color3.fromRGB(20, 24, 40),
	panel = Color3.fromRGB(30, 36, 58),
	panel2 = Color3.fromRGB(40, 48, 76),
	card = Color3.fromRGB(48, 57, 90),
	text = Color3.fromRGB(240, 243, 255),
	sub = Color3.fromRGB(165, 175, 210),
	accent = Color3.fromRGB(255, 170, 60),
	accent2 = Color3.fromRGB(60, 200, 190),
	good = Color3.fromRGB(80, 200, 120),
	bad = Color3.fromRGB(235, 85, 85),
	warn = Color3.fromRGB(245, 190, 60),
	blue = Color3.fromRGB(70, 140, 240),
	purple = Color3.fromRGB(150, 100, 235),
	gold = Color3.fromRGB(255, 205, 70),
}
local T = UI.Theme

UI.Font = Enum.Font.GothamBold
UI.FontMedium = Enum.Font.GothamMedium
UI.FontRegular = Enum.Font.Gotham

UI.isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ===================== PRIMITIVES =====================
function UI.new(class, props, children)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.corner(inst, r)
	UI.new("UICorner", { CornerRadius = UDim.new(0, r or 12), Parent = inst })
	return inst
end

function UI.stroke(inst, color, thickness, transparency)
	UI.new("UIStroke", {
		Color = color or Color3.fromRGB(255, 255, 255),
		Thickness = thickness or 1,
		Transparency = transparency or 0.85,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
	return inst
end

function UI.padding(inst, px, py)
	UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
		Parent = inst,
	})
	return inst
end

function UI.list(inst, dir, pad, align)
	UI.new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, pad or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = inst,
	})
	return inst
end

function UI.gradient(inst, c1, c2, rot)
	UI.new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rot or 90, Parent = inst })
	return inst
end

function UI.label(parent, text, size, props)
	props = props or {}
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text or "",
		TextColor3 = props.color or T.text,
		Font = props.font or UI.FontMedium,
		TextSize = size or 16,
		TextXAlignment = props.align or Enum.TextXAlignment.Left,
		TextYAlignment = props.valign or Enum.TextYAlignment.Center,
		TextWrapped = props.wrap ~= false,
		RichText = true,
		Size = props.sizeUDim or UDim2.new(1, 0, 0, (size or 16) + 8),
		AutomaticSize = props.auto and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
		LayoutOrder = props.order or 0,
		Parent = parent,
	})
	return l
end

local clickSound
function UI.click()
	if not clickSound then
		clickSound = Instance.new("Sound")
		clickSound.SoundId = Config.Sounds.Click
		clickSound.Volume = 0.4
		clickSound.Parent = SoundService
	end
	clickSound:Play()
end

function UI.sound(id, volume)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(10, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function UI.button(parent, text, color, onClick, props)
	props = props or {}
	local base = color or T.blue
	local b = UI.new("TextButton", {
		Text = text,
		TextColor3 = props.textColor or Color3.new(1, 1, 1),
		Font = UI.Font,
		TextSize = props.textSize or 16,
		BackgroundColor3 = base,
		AutoButtonColor = false,
		Size = props.size or UDim2.new(0, 140, 0, 40),
		LayoutOrder = props.order or 0,
		TextWrapped = true,
		Parent = parent,
	})
	UI.corner(b, props.radius or 10)
	UI.gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210), 90)
	if props.disabled then
		b.BackgroundColor3 = Color3.fromRGB(80, 85, 105)
		b.TextColor3 = Color3.fromRGB(170, 175, 190)
		b.AutoButtonColor = false
	end
	b.MouseEnter:Connect(function()
		if not props.disabled then
			TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.15) }):Play()
		end
	end)
	b.MouseLeave:Connect(function()
		if not props.disabled then
			TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
		end
	end)
	b.Activated:Connect(function()
		if props.disabled then
			if props.disabledText then
				UI.toast(props.disabledText, "warn")
			end
			return
		end
		UI.click()
		local s = UI.new("UIScale", { Scale = 0.92, Parent = b })
		TweenService:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(0.2, function()
			s:Destroy()
		end)
		if onClick then
			task.spawn(onClick)
		end
	end)
	return b
end

function UI.card(parent, height, props)
	props = props or {}
	local f = UI.new("Frame", {
		BackgroundColor3 = props.color or T.card,
		Size = UDim2.new(1, 0, 0, height or 60),
		AutomaticSize = props.auto and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
		LayoutOrder = props.order or 0,
		Parent = parent,
	})
	UI.corner(f, 10)
	UI.stroke(f, Color3.new(1, 1, 1), 1, 0.9)
	return f
end

function UI.progress(parent, fraction, color, props)
	props = props or {}
	local bg = UI.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 34),
		Size = props.size or UDim2.new(1, 0, 0, 10),
		Position = props.position or UDim2.new(),
		LayoutOrder = props.order or 0,
		Parent = parent,
	})
	UI.corner(bg, 6)
	local fill = UI.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = color or T.good,
		Size = UDim2.fromScale(math.clamp(fraction or 0, 0, 1), 1),
		Parent = bg,
	})
	UI.corner(fill, 6)
	return bg
end

function UI.textbox(parent, placeholder, props)
	props = props or {}
	local box = UI.new("TextBox", {
		PlaceholderText = placeholder or "",
		Text = props.text or "",
		TextColor3 = T.text,
		PlaceholderColor3 = T.sub,
		BackgroundColor3 = Color3.fromRGB(22, 26, 42),
		Font = UI.FontMedium,
		TextSize = 16,
		ClearTextOnFocus = false,
		Size = props.size or UDim2.new(0, 160, 0, 38),
		LayoutOrder = props.order or 0,
		Parent = parent,
	})
	UI.corner(box, 8)
	UI.stroke(box, T.accent2, 1, 0.6)
	return box
end

function UI.row(parent, height, order)
	local f = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or 40),
		LayoutOrder = order or 0,
		Parent = parent,
	})
	UI.list(f, Enum.FillDirection.Horizontal, 8)
	f.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	return f
end

function UI.clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UIGridLayout") then
			c:Destroy()
		end
	end
end

-- ===================== SCREEN =====================
local screen
function UI.screen()
	if screen then
		return screen
	end
	screen = UI.new("ScreenGui", {
		Name = "RestaurantUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = UI.new("UIScale", { Name = "Scale", Parent = screen })
	local function rescale()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local s = math.min(v.X / 1280, v.Y / 760)
		if UI.isMobile then
			s = math.clamp(s * 1.15, 0.55, 1)
		else
			s = math.clamp(s, 0.65, 1.2)
		end
		scale.Scale = s
		UI.scale = s
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	return screen
end

-- ===================== WINDOWS =====================
local windows = {}
local openWindow = nil
UI.windows = windows

function UI.window(id, title, icon, opts)
	opts = opts or {}
	local gui = UI.screen()
	local w, h = opts.width or 760, opts.height or 520
	local frame = UI.new("Frame", {
		Name = "Window_" .. id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = T.panel,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	UI.corner(frame, 16)
	UI.stroke(frame, Color3.new(1, 1, 1), 1.5, 0.8)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(w, h), Parent = frame })
	local header = UI.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = T.panel2,
		Parent = frame,
	})
	UI.corner(header, 16)
	UI.gradient(header, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 195, 215), 90)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), BackgroundColor3 = T.panel2, BorderSizePixel = 0, Parent = header })
	UI.label(header, (icon or "") .. "  " .. title, 22, { font = UI.Font, sizeUDim = UDim2.new(1, -70, 1, 0) }).Position = UDim2.fromOffset(18, 0)
	local close = UI.button(header, "✕", T.bad, function()
		UI.close(id)
	end, { size = UDim2.fromOffset(38, 38), radius = 19 })
	close.Position = UDim2.new(1, -46, 0.5, -19)

	local tabsBar = UI.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 58),
		Size = UDim2.new(1, -28, 0, 36),
		Visible = false,
		Parent = frame,
	})
	UI.list(tabsBar, Enum.FillDirection.Horizontal, 6)

	local content = UI.new("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 60),
		Size = UDim2.new(1, -28, 1, -72),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = T.sub,
		BorderSizePixel = 0,
		Parent = frame,
	})
	UI.list(content, Enum.FillDirection.Vertical, 8)
	UI.padding(content, 4, 4)

	local win = {
		id = id,
		frame = frame,
		content = content,
		tabsBar = tabsBar,
		tab = nil,
		render = opts.render,
	}
	function win:setTabs(list)
		self.tabsList = list
		tabsBar.Visible = true
		content.Position = UDim2.fromOffset(14, 100)
		content.Size = UDim2.new(1, -28, 1, -112)
		self.tab = self.tab or list[1].id
	end
	function win:refresh()
		if not frame.Visible or not self.render then
			return
		end
		local pos = content.CanvasPosition
		UI.clear(content)
		if self.tabsList then
			UI.clear(tabsBar)
			for i, t in ipairs(self.tabsList) do
				local selected = t.id == self.tab
				UI.button(tabsBar, t.text, selected and T.accent or T.card, function()
					self.tab = t.id
					content.CanvasPosition = Vector2.zero
					self:refresh()
				end, { size = UDim2.fromOffset(t.width or 120, 32), order = i, textSize = 14 })
			end
		end
		local ok, err = pcall(self.render, content, self)
		if not ok then
			warn("[UI] render " .. id .. ": " .. tostring(err))
		end
		task.defer(function()
			content.CanvasPosition = pos
		end)
	end
	windows[id] = win
	return win
end

function UI.open(id)
	local win = windows[id]
	if not win then
		return
	end
	if openWindow and openWindow ~= win then
		openWindow.frame.Visible = false
	end
	openWindow = win
	win.frame.Visible = true
	local s = win.frame:FindFirstChild("PopScale") or UI.new("UIScale", { Name = "PopScale", Parent = win.frame })
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	win:refresh()
end

function UI.close(id)
	local win = windows[id]
	if win then
		win.frame.Visible = false
		if openWindow == win then
			openWindow = nil
		end
	end
end

function UI.toggle(id)
	local win = windows[id]
	if win and win.frame.Visible then
		UI.close(id)
	else
		UI.open(id)
	end
end

function UI.isOpen(id)
	local win = windows[id]
	return win ~= nil and win.frame.Visible
end

function UI.refreshOpen()
	if openWindow then
		openWindow:refresh()
	end
end

-- ===================== TOASTS =====================
local toastHolder
function UI.toast(text, kind)
	local gui = UI.screen()
	if not toastHolder then
		toastHolder = UI.new("Frame", {
			Name = "Toasts",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -16, 1, -120),
			Size = UDim2.fromOffset(380, 400),
			ZIndex = 50,
			Parent = gui,
		})
		local l = UI.list(toastHolder, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
		l.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	local colors = { success = T.good, error = T.bad, warn = T.warn, info = T.blue, invite = T.purple }
	local color = colors[kind] or T.blue
	local f = UI.new("Frame", {
		BackgroundColor3 = T.panel,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 50,
		Parent = toastHolder,
	})
	UI.corner(f, 10)
	UI.stroke(f, color, 2, 0.1)
	UI.padding(f, 12, 10)
	local bar = UI.new("Frame", { BackgroundColor3 = color, Size = UDim2.new(0, 4, 1, 0), Position = UDim2.fromOffset(-8, 0), ZIndex = 51, Parent = f })
	UI.corner(bar, 2)
	local l = UI.label(f, text, 15, { auto = true, sizeUDim = UDim2.new(1, 0, 0, 0) })
	l.ZIndex = 51
	if kind == "error" or kind == "warn" then
		UI.sound(Config.Sounds.Error, 0.3)
	end
	local children = toastHolder:GetChildren()
	if #children > 7 then
		for _, c in ipairs(children) do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
	task.delay(4.5, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			f:Destroy()
		end
	end)
end

-- Run a server request and show the error toast automatically
function UI.request(Net, name, payload, successText)
	local res = Net.request(name, payload)
	if res and res.ok then
		if successText then
			UI.toast(successText, "success")
		end
	else
		UI.toast((res and res.err) or "Ошибка", "error")
	end
	return res
end

return UI
