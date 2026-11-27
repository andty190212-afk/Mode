-- BuildController: client build mode with a ghost preview, grid snapping, rotation,
-- placement / move / delete. The server re-validates everything.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local BuildRules = require(Shared.BuildRules)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local State = require(Controllers.State)
local T = UI.Theme

local Build = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local mode = nil -- nil | "place" | "edit"
local kind, itemId, rotation = "furniture", nil, 0
local ignoreUid = nil
local ghost, highlight, conn
local panel, infoLabel
local lastX, lastZ, lastValid, lastErr = 0, 0, false, ""
local pointer = nil -- Vector2 screen position (touch)
local selected = nil -- model in edit mode
local selectBox

local function assetFor(k, id)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(k == "decor" and "Decor" or "Furniture")
	return folder and folder:FindFirstChild(id)
end

local function makeGhost(k, id)
	local template = assetFor(k, id)
	local def = BuildRules.catalog(k).ById[id]
	local m
	if template then
		m = template:Clone()
	else
		m = Instance.new("Model")
		local p = Instance.new("Part")
		p.Name = "Base"
		p.Size = Vector3.new(def.size[1], 2, def.size[2])
		p.Parent = m
		m.PrimaryPart = p
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Transparency = math.max(d.Transparency, 0.35)
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	if not m.PrimaryPart then
		m.PrimaryPart = m:FindFirstChild("Base") or m:FindFirstChildWhichIsA("BasePart")
	end
	-- footprint outline
	local foot = Instance.new("Part")
	foot.Name = "Footprint"
	foot.Size = Vector3.new(def.size[1], 0.1, def.size[2])
	foot.Anchored = true
	foot.CanCollide = false
	foot.CanQuery = false
	foot.Material = Enum.Material.Neon
	foot.Transparency = 0.6
	foot.CFrame = m.PrimaryPart.CFrame
	foot.Parent = m
	m.Parent = camera
	local h = Instance.new("Highlight")
	h.FillTransparency = 0.6
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = m
	h.Parent = m
	return m, h
end

local function screenPoint()
	if pointer then
		return pointer
	end
	return UserInputService:GetMouseLocation()
end

local function raycast()
	local pos = screenPoint()
	local ray = camera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	local exclude = { camera }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(exclude, npcs)
	end
	params.FilterDescendantsInstances = exclude
	params.FilterType = Enum.RaycastFilterType.Exclude
	return workspace:Raycast(ray.Origin, ray.Direction * 600, params)
end

local function setPanel(text, buttons)
	if panel then
		panel:Destroy()
	end
	local gui = UI.screen()
	panel = UI.new("Frame", {
		Name = "BuildPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -76),
		Size = UDim2.fromOffset(620, 92),
		BackgroundColor3 = T.panel,
		Parent = gui,
	})
	UI.corner(panel, 14)
	UI.stroke(panel, T.accent, 2, 0.4)
	infoLabel = UI.label(panel, text, 15, { align = Enum.TextXAlignment.Center, sizeUDim = UDim2.new(1, -20, 0, 30) })
	infoLabel.Position = UDim2.fromOffset(10, 4)
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 46), Position = UDim2.fromOffset(10, 38), Parent = panel })
	UI.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	for i, b in ipairs(buttons) do
		UI.button(row, b[1], b[2], b[3], { size = UDim2.fromOffset(b[4] or 140, 42), order = i, textSize = 14 })
	end
end

local function cleanupGhost()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
end

function Build.stop()
	cleanupGhost()
	if panel then
		panel:Destroy()
		panel = nil
	end
	if selectBox then
		selectBox:Destroy()
		selectBox = nil
	end
	mode = nil
	selected = nil
	ignoreUid = nil
	pointer = nil
end

local function frame()
	return BuildRules.frameFor(State.myIsland(), kind)
end

local function update()
	if not ghost or not State.restaurant then
		return
	end
	local hit = raycast()
	if hit then
		local f = frame()
		local lp = f:PointToObjectSpace(hit.Position)
		lastX, lastZ = math.floor(lp.X + 0.5), math.floor(lp.Z + 0.5)
	end
	ghost:PivotTo(frame() * CFrame.new(lastX, 0.1, lastZ) * CFrame.Angles(0, math.rad(rotation), 0))
	lastValid, lastErr = BuildRules.validate(State.restaurant, kind, itemId, lastX, lastZ, rotation, ignoreUid)
	local color = lastValid and T.good or T.bad
	highlight.FillColor = color
	highlight.OutlineColor = color
	local foot = ghost:FindFirstChild("Footprint")
	if foot then
		foot.Color = color
	end
	if infoLabel then
		local def = BuildRules.catalog(kind).ById[itemId]
		infoLabel.Text = (def and def.name or "") .. (ignoreUid and "" or ("  •  " .. Util.formatMoney(def and def.price or 0))) .. (lastValid and "  ✅" or ("  ❌ " .. (lastErr or "")))
	end
end

local function confirm()
	if not ghost then
		return
	end
	update()
	if not lastValid then
		UI.toast(lastErr or "Сюда нельзя", "warn")
		return
	end
	if ignoreUid then
		local res = UI.request(Net, "MoveItem", { kind = kind, uid = ignoreUid, x = lastX, z = lastZ, r = rotation })
		if res.ok then
			Build.stop()
			Build.edit(kind)
		end
	else
		UI.request(Net, "PlaceItem", { kind = kind, id = itemId, x = lastX, z = lastZ, r = rotation })
		-- остаёмся в режиме, чтобы поставить ещё
	end
end

local function rotate()
	rotation = (rotation + 90) % 360
	update()
end

function Build.place(k, id)
	if State.myIsland() == 0 or not State.restaurant then
		UI.toast("Сначала откройте ресторан", "warn")
		return
	end
	Build.stop()
	mode = "place"
	kind, itemId, rotation = k, id, 0
	ghost, highlight = makeGhost(k, id)
	conn = RunService.RenderStepped:Connect(update)
	setPanel("", {
		{ "✅ Поставить", T.good, confirm },
		{ "⟳ Повернуть (R)", T.blue, rotate },
		{ "📦 Каталог", T.purple, function()
			Build.stop()
			UI.open("build")
		end },
		{ "✕ Выход (Q)", T.bad, Build.stop, 120 },
	})
end

-- ===================== EDIT MODE =====================
local function placedModelAt()
	local hit = raycast()
	if not hit then
		return nil
	end
	local inst = hit.Instance
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:GetAttribute("Uid") and inst:GetAttribute("Kind") == kind then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

function Build.edit(k)
	if State.myIsland() == 0 then
		UI.toast("Сначала откройте ресторан", "warn")
		return
	end
	Build.stop()
	mode = "edit"
	kind = k
	setPanel("Нажмите на предмет (" .. (k == "decor" and "декор острова" or "мебель") .. "), чтобы выбрать", {
		{ "✋ Переместить", T.blue, function()
			if not selected then
				UI.toast("Сначала выберите предмет", "warn")
				return
			end
			local uid = selected:GetAttribute("Uid")
			local id = selected:GetAttribute("ItemId")
			local entry
			for _, e in ipairs(BuildRules.listOf(State.restaurant, kind)) do
				if e.uid == uid then
					entry = e
				end
			end
			Build.stop()
			mode = "place"
			kind, itemId = k, id
			rotation = entry and entry.r or 0
			ignoreUid = uid
			ghost, highlight = makeGhost(k, id)
			conn = RunService.RenderStepped:Connect(update)
			setPanel("", {
				{ "✅ Сюда", T.good, confirm },
				{ "⟳ Повернуть (R)", T.blue, rotate },
				{ "✕ Отмена", T.bad, function()
					Build.edit(k)
				end },
			})
		end },
		{ "🗑️ Продать (50%)", T.bad, function()
			if not selected then
				UI.toast("Сначала выберите предмет", "warn")
				return
			end
			local res = UI.request(Net, "RemoveItem", { kind = kind, uid = selected:GetAttribute("Uid") })
			if res.ok then
				UI.toast("Продано, возврат " .. Util.formatMoney(res.refund or 0), "success")
				selected = nil
				if selectBox then
					selectBox.Adornee = nil
				end
			end
		end },
		{ kind == "decor" and "🛋️ Интерьер" or "🌴 Остров", T.purple, function()
			Build.edit(kind == "decor" and "furniture" or "decor")
		end },
		{ "✕ Выход", T.card, Build.stop, 110 },
	})
end

local function selectAtPointer()
	local m = placedModelAt()
	if not m then
		return
	end
	selected = m
	if not selectBox then
		selectBox = Instance.new("Highlight")
		selectBox.FillTransparency = 0.7
		selectBox.FillColor = T.accent
		selectBox.OutlineColor = T.accent
		selectBox.Parent = camera
	end
	selectBox.Adornee = m
	if infoLabel then
		local def = BuildRules.catalog(kind).ById[m:GetAttribute("ItemId")]
		infoLabel.Text = "Выбрано: " .. (def and def.name or "?")
	end
end

function Build.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not mode then
			return
		end
		if input.KeyCode == Enum.KeyCode.R and not processed then
			if mode == "place" then
				rotate()
			end
		elseif (input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape) and not processed then
			Build.stop()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			pointer = nil
			if mode == "place" then
				confirm()
			else
				selectAtPointer()
			end
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
			pointer = Vector2.new(input.Position.X, input.Position.Y + 36)
			if mode == "edit" then
				selectAtPointer()
			end
		end
	end)
	UserInputService.TouchMoved:Connect(function(input, processed)
		if mode == "place" and not processed then
			pointer = Vector2.new(input.Position.X, input.Position.Y + 36)
		end
	end)
	player.CharacterRemoving:Connect(Build.stop)
end

return Build
