-- HeliController: client-side flight model for the helicopter the local player
-- pilots (network owner), on-screen controls for touch devices, rotor animation for
-- every helicopter in the world.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Controllers = script.Parent
local UI = require(Controllers.UI)
local T = UI.Theme

local Heli = {}
local player = Players.LocalPlayer

local piloting = nil -- model
local throttle, yawInput, liftInput = 0, 0, 0
local velocity = Vector3.zero
local yaw = 0
local touchState = { fwd = 0, back = 0, left = 0, right = 0, up = 0, down = 0 }
local touchGui
local engineSound
local rotorAngle = 0

local function keyDown(k)
	return UserInputService:IsKeyDown(k)
end

local function readInput()
	local f = (keyDown(Enum.KeyCode.W) and 1 or 0) - (keyDown(Enum.KeyCode.S) and 1 or 0) + touchState.fwd - touchState.back
	local y = (keyDown(Enum.KeyCode.A) and 1 or 0) - (keyDown(Enum.KeyCode.D) and 1 or 0) + touchState.left - touchState.right
	local l = (keyDown(Enum.KeyCode.Space) and 1 or 0) + (keyDown(Enum.KeyCode.E) and 1 or 0)
		- (keyDown(Enum.KeyCode.LeftShift) and 1 or 0) - (keyDown(Enum.KeyCode.LeftControl) and 1 or 0) - (keyDown(Enum.KeyCode.Q) and 1 or 0)
		+ touchState.up - touchState.down
	-- gamepad
	for _, s in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if s.KeyCode == Enum.KeyCode.Thumbstick1 and s.Position.Magnitude > 0.15 then
			f += s.Position.Y
			y -= s.Position.X
		elseif s.KeyCode == Enum.KeyCode.ButtonR2 then
			l += s.Position.Z
		elseif s.KeyCode == Enum.KeyCode.ButtonL2 then
			l -= s.Position.Z
		end
	end
	return math.clamp(f, -1, 1), math.clamp(y, -1, 1), math.clamp(l, -1, 1)
end

local function buildTouch()
	if touchGui or not UserInputService.TouchEnabled then
		return
	end
	local gui = UI.screen()
	touchGui = UI.new("Frame", { Name = "HeliTouch", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local function pad(text, key, pos)
		local b = UI.new("TextButton", {
			Text = text,
			TextSize = 28,
			Font = UI.Font,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = T.panel,
			BackgroundTransparency = 0.25,
			Size = UDim2.fromOffset(76, 76),
			Position = pos,
			Parent = touchGui,
		})
		UI.corner(b, 38)
		b.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
				touchState[key] = 1
			end
		end)
		b.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
				touchState[key] = 0
			end
		end)
	end
	pad("▲", "fwd", UDim2.new(0, 110, 1, -270))
	pad("▼", "back", UDim2.new(0, 110, 1, -110))
	pad("◀", "left", UDim2.new(0, 30, 1, -190))
	pad("▶", "right", UDim2.new(0, 190, 1, -190))
	pad("⤒", "up", UDim2.new(1, -120, 1, -270))
	pad("⤓", "down", UDim2.new(1, -120, 1, -170))
end

local function destroyTouch()
	if touchGui then
		touchGui:Destroy()
		touchGui = nil
	end
	for k in pairs(touchState) do
		touchState[k] = 0
	end
end

local function startPiloting(model)
	piloting = model
	local root = model.PrimaryPart
	local lift = root:FindFirstChild("Lift")
	local gyro = root:FindFirstChild("Gyro")
	if lift then
		lift.MaxForce = 1e7
	end
	if gyro then
		gyro.MaxTorque = 1e7
	end
	local _, ry = root.CFrame:ToEulerAnglesYXZ()
	yaw = ry
	velocity = root.AssemblyLinearVelocity
	buildTouch()
	if Config.Sounds.Helicopter ~= "" then
		engineSound = Instance.new("Sound")
		engineSound.SoundId = Config.Sounds.Helicopter
		engineSound.Looped = true
		engineSound.Volume = 0.5
		engineSound.Parent = root
		engineSound:Play()
	end
	if model:GetAttribute("Vehicle") == "Boat" then
		UI.toast("🚤 W/S — вперёд/назад, A/D — поворот. Прыжок — выйти.", "info")
	else
		UI.toast("🚁 W/S — вперёд/назад, A/D — поворот, Пробел/E — вверх, Shift/Q — вниз. Прыжок — выйти.", "info")
	end
end

local function stopPiloting()
	if piloting and piloting.PrimaryPart then
		local root = piloting.PrimaryPart
		local lift = root:FindFirstChild("Lift")
		local gyro = root:FindFirstChild("Gyro")
		if piloting:GetAttribute("Vehicle") == "Boat" then
			-- лодка: остановиться на воде (сервер поставит её на якорь)
			if lift then
				lift.VectorVelocity = Vector3.zero
			end
		-- плавная посадка: держим небольшую вертикальную скорость вниз
		elseif lift then
			lift.VectorVelocity = Vector3.new(0, -6, 0)
			task.delay(3, function()
				if lift.Parent and piloting == nil then
					lift.MaxForce = 0
				end
			end)
		end
		if gyro then
			gyro.CFrame = CFrame.Angles(0, yaw, 0)
		end
	end
	if engineSound then
		engineSound:Destroy()
		engineSound = nil
	end
	piloting = nil
	destroyTouch()
end

local function step(dt)
	-- rotor animation for all helicopters
	rotorAngle = (rotorAngle + dt * 28) % (math.pi * 2)
	local folder = workspace:FindFirstChild("Helicopters")
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			local root = model.PrimaryPart
			if root then
				local seat = model:FindFirstChild("PilotSeat", true)
				local running = seat and seat.Occupant ~= nil
				local speed = running and 1 or 0.15
				for _, part in ipairs(model:GetChildren()) do
					local spin = part:IsA("BasePart") and part:GetAttribute("Spin")
					if spin then
						local offset = part:GetAttribute("Offset")
						if typeof(offset) == "CFrame" then
							local angle = rotorAngle * speed * (spin == "tail" and 1.6 or 1)
							local rot = spin == "tail" and CFrame.Angles(angle, 0, 0) or CFrame.Angles(0, angle, 0)
							part.CFrame = root.CFrame * offset * rot
						end
					end
				end
			end
		end
	end

	if not piloting then
		return
	end
	local root = piloting.PrimaryPart
	if not root or not piloting.Parent then
		stopPiloting()
		return
	end
	local lift = root:FindFirstChild("Lift")
	local gyro = root:FindFirstChild("Gyro")
	local maxSpeed = piloting:GetAttribute("Speed") or 70
	local climb = piloting:GetAttribute("Climb") or 28
	local turn = piloting:GetAttribute("Turn") or 1.2
	local accel = piloting:GetAttribute("Accel") or 0.8
	throttle, yawInput, liftInput = readInput()
	if piloting:GetAttribute("Vehicle") == "Boat" then
		-- лодка: только по воде, держим высоту поверхности
		yaw += yawInput * turn * dt * math.clamp(math.abs(throttle) + 0.35, 0, 1)
		local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		local floatY = piloting:GetAttribute("FloatY") or 0.2
		local p = root.Position
		local tgt = fwd * throttle * maxSpeed * (throttle < 0 and 0.4 or 1)
		local fl = Vector3.new(p.X, 0, p.Z)
		if fl.Magnitude > Config.WorldRadius then
			tgt = -fl.Unit * maxSpeed * 0.5
		end
		velocity = velocity:Lerp(tgt, math.clamp(dt * 1.5, 0, 1))
		if lift then
			lift.VectorVelocity = Vector3.new(velocity.X, (floatY - p.Y) * 4, velocity.Z)
		end
		if gyro then
			local roll = -yawInput * math.rad(8) * math.clamp(velocity.Magnitude / maxSpeed, 0, 1)
			local pitch = math.rad(4) * math.clamp(velocity.Magnitude / maxSpeed, 0, 1)
			gyro.CFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
		end
		return
	end
	yaw += yawInput * turn * dt
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local target = forward * throttle * maxSpeed + Vector3.new(0, liftInput * climb, 0)
	-- высотный потолок и граница мира
	local pos = root.Position
	if pos.Y > Config.MaxFlightHeight and target.Y > 0 then
		target = Vector3.new(target.X, 0, target.Z)
	end
	local flat = Vector3.new(pos.X, 0, pos.Z)
	if flat.Magnitude > Config.WorldRadius then
		local inward = -flat.Unit
		target = Vector3.new(inward.X * maxSpeed * 0.6, target.Y, inward.Z * maxSpeed * 0.6)
	end
	velocity = velocity:Lerp(target, math.clamp(dt * 2.2 * accel, 0, 1))
	if lift then
		lift.VectorVelocity = velocity
	end
	if gyro then
		local localVel = CFrame.Angles(0, yaw, 0):VectorToObjectSpace(velocity)
		local pitch = math.clamp(localVel.Z / maxSpeed, -1, 1) * math.rad(14)
		local roll = yawInput * math.rad(12) * math.clamp(math.abs(throttle) + 0.3, 0, 1)
		gyro.CFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
	end
	if engineSound then
		engineSound.PlaybackSpeed = 0.9 + velocity.Magnitude / maxSpeed * 0.3
	end
end

function Heli.init()
	RunService.RenderStepped:Connect(step)
	local function hookCharacter(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then
			return
		end
		hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seat = hum.SeatPart
			if seat and (seat.Name == "PilotSeat" or seat.Name == "BoatSeat") then
				local model = seat:FindFirstAncestorOfClass("Model")
				while model and not (model:GetAttribute("Helicopter") or model:GetAttribute("Vehicle")) do
					model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
				end
				if model then
					startPiloting(model)
				end
			elseif piloting then
				stopPiloting()
			end
		end)
	end
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(c)
		stopPiloting()
		hookCharacter(c)
	end)
end

return Heli
