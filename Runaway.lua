--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--// Load VindUI Reborn
local VindUI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Skinny-yz/vindUI-Test/main/full.luau"
))()

VindUI:PreloadIcons({ "Lucide", "Material", "Phosphor", "SF" })
VindUI:SetScaleRange(0.75, 1.35)

--// Optional intro (set Enabled = false to skip)
VindUI:ShowIntro({
	Enabled = true,
	Title = "RUNAWAYS",
	Eyebrow = "WELCOME BACK",
	Subtitle = "Preparing your workspace...",
	Logo = "Lucide:sparkles",
	UseBlur = true,
	Transparency = 0.22,
	Shimmer = true,
	Duration = 2.6,
	Skippable = true,
	ReducedMotion = false,
}):Wait()

--// Create window
local Window = VindUI:CreateWindow({
	Title = "RUNAWAYS",
	Subtitle = "Interactive showcase",
	Icon = "Lucide:sparkles",
	Size = UDim2.fromOffset(640, 455),
	MinSize = Vector2.new(500, 360),
	Draggable = true,
	Resizable = true,
	UseBlur = true,
	DefaultTab = "Home",
	TabWidth = 145,
	TabScrollbar = true,
	UserInfo = {
		Enabled = true,
		Avatar = "player",
		NameMode = "display",
	},
})

VindUI:Notify({
	Title = "RUNAWAYS",
	Text = "Script loaded successfully.",
	Type = "success",
	Duration = 4,
})

--// Tab groups
local Main = Window:AddTabGroup({ Name = "RUNAWAYS" })
local Tools = Window:AddTabGroup({ Name = "TELEPORT" })

local HomeTab = Main:AddTab({ Name = "Home", Icon = "Lucide:house" })
local TeleportTab = Tools:AddTab({ Name = "Vehicles", Icon = "Lucide:car" })

--// Kill All NPCs
local function Mobs()
	spawn(function()
		_G.Mobs = true
		while _G.Mobs do
			wait()
			pcall(function()
				for _, descendant in pairs(workspace.NPCs:GetDescendants()) do
					if descendant.Name == "Humanoid" and descendant.Health > 0 then
						ReplicatedStorage.FlowClient.ClientRunner.Event:FireServer(
							"NPCs", "Damage", descendant, 1e999
						)
						wait(0)
					end
				end
				wait(3)
			end)
		end
	end)
end

local KillAllSection = HomeTab:AddSection("Combat", "Lucide:sword")
KillAllSection:AddToggle({
	Text = "KillAll NPCs",
	Flag = "toggle",
	Default = false,
	Callback = function(state)
		_G.Mobs = state
		if state then
			Mobs()
		end
	end,
})

--// Walk Speed (TP Walk)
local walkSpeed = 1

local MovementSection = HomeTab:AddSection("Movement", "Lucide:move")
MovementSection:AddSlider({
	Text = "Walk Speed",
	Flag = "tpwalk_speed",
	Min = 1,
	Max = 100,
	Default = 1,
	Callback = function(value)
		walkSpeed = tonumber(value) or 1
	end,
})

RunService.Heartbeat:Connect(function(dt)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")

	if not character or not humanoid or not humanoid.Parent then
		return
	end

	if humanoid.MoveDirection.Magnitude > 0 then
		character:TranslateBy(humanoid.MoveDirection * walkSpeed * dt * 10)
	end
end)

--// NoClip
local noclipConnection
local lastSafeCFrame
local antiVoidBusy = false

MovementSection:AddToggle({
	Text = "NoClip",
	Flag = "toggle",
	Default = false,
	Callback = function(enabled)
		if enabled then
			if noclipConnection then
				noclipConnection:Disconnect()
			end

			noclipConnection = RunService.Heartbeat:Connect(function()
				local character = LocalPlayer.Character
				if not character or antiVoidBusy then return end

				local root = character:FindFirstChild("HumanoidRootPart")
				if not root then return end

				for _, part in ipairs(character:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = false
					end
				end

				local y = root.Position.Y
				if not lastSafeCFrame or y >= lastSafeCFrame.Position.Y - 5 then
					lastSafeCFrame = root.CFrame
				elseif lastSafeCFrame.Position.Y - y >= 100 then
					antiVoidBusy = true
					root.AssemblyLinearVelocity = Vector3.zero

					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { character }

					local found = false
					local checkPos = root.Position

					for _ = 1, 20 do
						checkPos = checkPos + Vector3.new(0, 150, 0)
						task.wait()

						local hit = workspace:Raycast(checkPos, Vector3.new(0, -2000, 0), params)
						if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
							root.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0))
							found = true
							break
						end
					end

					if not found then
						root.CFrame = root.CFrame + Vector3.new(0, 150, 0)
					end

					root.AssemblyLinearVelocity = Vector3.zero
					lastSafeCFrame = root.CFrame
					antiVoidBusy = false
				end
			end)
		else
			if noclipConnection then
				noclipConnection:Disconnect()
				noclipConnection = nil
			end

			lastSafeCFrame = nil
			antiVoidBusy = false

			if LocalPlayer.Character then
				for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = true
					end
				end
			end
		end
	end,
})

--// Infinite Jump
MovementSection:AddButton({
	Text = "Inf Jump",
	Icon = "Lucide:arrow-up-circle",
	Callback = function()
		UserInputService.JumpRequest:Connect(function()
			local character = LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
	end,
})

--// Goto Final Door
local TeleportSection = HomeTab:AddSection("Teleport", "Lucide:map-pin")

TeleportSection:AddButton({
	Text = "Goto FinalDoor",
	Icon = "Lucide:door-open",
	Callback = function()
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		root.CFrame = CFrame.new(
			414.023376, 1684.79175, 83590.9922,
			-0.987750471, 4.99552533e-09, 0.156041607,
			4.77962647e-09, 1, -1.75880632e-09,
			-0.156041607, -9.91441151e-10, -0.987750471
		)
		task.wait(5)

		local commandButton = workspace.Map.Buildings.CustomsFinal.CustomsBuilding.FinalDoor.Command.CommandButton
		for _, child in ipairs(commandButton:GetChildren()) do
			if child.Name == "Prompt" then
				root.CFrame = child.CFrame * CFrame.new(0, 0, 5)
				task.wait(0.2)

				local prompt = child:FindFirstChildOfClass("ProximityPrompt")
					or child:FindFirstChild("ProximityPrompt")
				if prompt then
					fireproximityprompt(prompt)
				end
			end
		end
	end,
})

--// Vehicle Teleport (Teleport tab)
local vehicleNames = {}
for _, vehicle in ipairs(workspace.Vehicles:GetChildren()) do
	if vehicle:IsA("Model") or vehicle:IsA("BasePart") then
		vehicleNames[#vehicleNames + 1] = vehicle.Name
	end
end
table.sort(vehicleNames)

local selectedVehicle

local VehicleSection = TeleportTab:AddSection("Vehicles", "Lucide:car")
VehicleSection:AddDropdown({
	Text = "Choose a Vehicle",
	Flag = "vehicle_list",
	Default = "==Select Vehicle==",
	Options = vehicleNames,
	Callback = function(name)
		selectedVehicle = name
	end,
})

VehicleSection:AddButton({
	Text = "Teleport to Vehicle",
	Icon = "Lucide:navigation",
	Callback = function()
		if not selectedVehicle then return end

		local vehicle = workspace.Vehicles:FindFirstChild(selectedVehicle)
		if not vehicle then return end

		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		local vehicleCFrame = vehicle:IsA("BasePart") and vehicle.CFrame or vehicle:GetPivot()
		root.CFrame = vehicleCFrame * CFrame.new(0, 5, 0)
	end,
})

--// GET 5 STARS
local get5StarsRunning = false

HomeTab:AddButton({
	Text = "GET 5 STARS",
	Icon = "Lucide:star",
	Callback = function()
		if get5StarsRunning then return end
		get5StarsRunning = true

		local running = true
		local character = LocalPlayer.Character
		if not character then
			running = false
			get5StarsRunning = false
			return
		end

		local savedCFrame = character:GetPivot()
		local root = character:FindFirstChild("HumanoidRootPart")
		local event = ReplicatedStorage:WaitForChild("FlowClient")
			:WaitForChild("ClientRunner"):WaitForChild("Event")

		-- Loot / sensor loop
		task.spawn(function()
			while running and character.Parent do
				task.wait(0.1)
				pcall(function()
					event:FireServer("GameManager", "Replay")
				end)

				if root and root.Parent and typeof(firetouchinterest) == "function" then
					local cash = workspace:FindFirstChild("Cash")
					if cash then
						for _, child in ipairs(cash:GetChildren()) do
							local sensor = child:FindFirstChild("TouchSensor")
							if sensor then
								firetouchinterest(root, sensor, true)
								firetouchinterest(root, sensor, false)
							end
						end
					end

					local loot = workspace:FindFirstChild("Loot")
					if loot then
						for _, child in ipairs(loot:GetChildren()) do
							local sensor = child:FindFirstChild("TouchSensor")
								or (child:FindFirstChild("Cash") and child.Cash:FindFirstChild("TouchSensor"))
							if sensor then
								firetouchinterest(root, sensor, true)
								firetouchinterest(root, sensor, false)
							end
						end
					end
				end
			end
		end)

		local function clearWorld()
			local map = workspace:FindFirstChild("Map")
			if map then
				for _, descendant in ipairs(map:GetDescendants()) do
					if descendant.Name:find("Glass") then
						pcall(function()
							event:FireServer("Effects", "BreakGlass", descendant)
						end)
					end
				end
			end

			local npcs = workspace:FindFirstChild("NPCs")
			if npcs then
				for _, child in ipairs(npcs:GetChildren()) do
					local humanoid = child:FindFirstChild("Humanoid")
					if humanoid then
						pcall(function()
							event:FireServer("NPCs", "Damage", humanoid, 13000)
						end)
					end
				end
			end

			local buildings = map and map:FindFirstChild("Buildings")
			if buildings then
				for _, descendant in ipairs(buildings:GetDescendants()) do
					if descendant.Name == "MaxHealth" and descendant.Parent then
						pcall(function()
							event:FireServer("DamageToOpen", "Damage", descendant.Parent, 6000, "melee")
						end)
					end
				end
			end
		end

		-- Clear PawnShop area
		local map = workspace:FindFirstChild("Map")
		local buildings = map and map:FindFirstChild("Buildings")

		if buildings then
			for _, child in ipairs(buildings:GetChildren()) do
				if child.Name == "PawnShop" and child:IsA("Model") then
					clearWorld()
					character:PivotTo(child:GetPivot())
					clearWorld()
					task.wait(1)
				end
			end
		end

		-- Determine checkpoints
		local points = { 2500, 22000, 45000, 83700 }

		local hud = LocalPlayer:FindFirstChild("PlayerGui")
			and LocalPlayer.PlayerGui:FindFirstChild("HudGui")
		local progress = hud and hud:FindFirstChild("Distance")
			and hud.Distance:FindFirstChild("Progress")

		if progress then
			local found = {}
			for _, child in ipairs(progress:GetChildren()) do
				local n = child.Name:match("Border_(%d+)")
				if n then
					found[#found + 1] = tonumber(n)
				end
			end
			if #found > 0 then
				table.sort(found)
				points = found
			end
		end

		for _, z in ipairs(points) do
			if not running then break end
			character:PivotTo(CFrame.new(savedCFrame.Position.X, 2200, z))
			task.wait(0.1)
		end

		-- Move past the final door
		local map2 = workspace:FindFirstChild("Map")
		local buildings2 = map2 and map2:FindFirstChild("Buildings")
		local customs = buildings2 and buildings2:FindFirstChild("CustomsFinal")

		if customs then
			character:PivotTo(customs:GetPivot() * CFrame.new(0, 10, 1500))
		else
			character:PivotTo(CFrame.new(savedCFrame.Position.X, 2200, points[#points] + 1500))
		end

		task.wait(0.8)
		running = false
		get5StarsRunning = false

		if character.Parent then
			character:PivotTo(savedCFrame)
		end

		VindUI:Notify({
			Title = "GET 5 STARS",
			Text = "Run complete.",
			Type = "success",
			Duration = 3,
		})
	end,
})

--// Camera setup
local CurrentCamera = workspace.CurrentCamera
LocalPlayer.CameraMode = Enum.CameraMode.Classic
LocalPlayer.CameraMinZoomDistance = 0
LocalPlayer.CameraMaxZoomDistance = 100

local character = LocalPlayer.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
if humanoid then
	CurrentCamera.CameraSubject = humanoid
end