--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

--// Load VindUI Reborn
local VindUI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Skinny-yz/vindUI-Test/main/full.luau"
))()

VindUI:SetTheme("Dark")
VindUI:PreloadIcons({ "Lucide", "Material", "Phosphor", "SF" })
VindUI:SetScaleRange(0.75, 1.35)

-- Intro disabled by default — re-enable if you want the animation.
VindUI:ShowIntro({
	Enabled = false,
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

local Window = VindUI:CreateWindow({
	Title = "RUNAWAYS",
	Subtitle = "v" .. tostring(VindUI.Version),
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

--// Tabs
local MainGroup = Window:AddTabGroup({ Name = "RUNAWAYS" })
local ToolsGroup = Window:AddTabGroup({ Name = "TELEPORT" })

local HomeTab = MainGroup:AddTab({ Name = "Home", Icon = "Lucide:house" })
local VehicleTab = ToolsGroup:AddTab({ Name = "Vehicles", Icon = "Lucide:car" })

--// Kill All NPCs
local function killAllNPCs()
	spawn(function()
		_G.mb = true
		while _G.mb do
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

local Combat = HomeTab:AddCollapsibleSection({
	Title = "Combat",
	Icon = "Lucide:sword",
	Collapsed = false,
})

Combat:AddToggle({
	Text = "KillAll NPCs",
	Description = "Continuously damages every NPC until dead.",
	Icon = "Lucide:sword",
	Flag = "toggle",
	Default = false,
	Callback = function(state)
		_G.mb = state
		if state then
			killAllNPCs()
		end
	end,
})

--// Movement
local walkSpeed = 1

local Movement = HomeTab:AddCollapsibleSection({
	Title = "Movement",
	Icon = "Lucide:move",
	Collapsed = false,
})

Movement:AddSlider({
	Text = "Walk Speed",
	Description = "Scales horizontal movement via TranslateBy.",
	Icon = "Lucide:gauge",
	Flag = "tpwalk_speed",
	Min = 1,
	Max = 100,
	Default = 1,
	Increment = 1,
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

local noclipConnection
local lastSafeCFrame
local antiVoidBusy = false

Movement:AddToggle({
	Text = "NoClip",
	Description = "Disables collision with an anti-void fallback.",
	Icon = "Lucide:ghost",
	Flag = "noclip",
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

					for _ = 1, 20 do
						root.CFrame = root.CFrame + Vector3.new(0, 150, 0)
						task.wait()

						local hit = workspace:Raycast(root.Position, Vector3.new(0, -2000, 0), params)
						if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
							root.CFrame = CFrame.new(
								hit.Position + Vector3.new(0, 4, 0),
								root.Position + root.CFrame.LookVector
							)
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

Movement:AddButton({
	Text = "Inf Jump",
	Description = "Allows jumping mid-air.",
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

--// Teleport — FinalDoor
local Teleport = HomeTab:AddCollapsibleSection({
	Title = "Teleport",
	Icon = "Lucide:map-pin",
	Collapsed = false,
})

Teleport:AddButton({
	Text = "Goto FinalDoor",
	Description = "Teleports near the final door and fires its prompt.",
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

--// Vehicle Teleport
local vehicleNames = {}
for _, vehicle in ipairs(workspace.Vehicles:GetChildren()) do
	if vehicle:IsA("Model") or vehicle:IsA("BasePart") then
		vehicleNames[#vehicleNames + 1] = vehicle.Name
	end
end
table.sort(vehicleNames)

local selectedVehicle

local Vehicles = VehicleTab:AddCollapsibleSection({
	Title = "Vehicles",
	Icon = "Lucide:car",
	Collapsed = false,
})

Vehicles:AddDropdown({
	Text = "Choose a Vehicle",
	Description = "Populated from workspace.Vehicles.",
	Icon = "Lucide:list",
	Flag = "vehicle_list",
	Options = vehicleNames,
	Default = vehicleNames[1] or "==Select Vehicle==",
	Callback = function(name)
		selectedVehicle = name
	end,
})

Vehicles:AddButton({
	Text = "Teleport to Vehicle",
	Description = "Teleports you above the selected vehicle.",
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

local Automation = HomeTab:AddCollapsibleSection({
	Title = "Automation",
	Icon = "Lucide:star",
	Collapsed = false,
})

Automation:AddButton({
	Text = "GET 5 STARS",
	Description = "Runs the full multi-stage completion script.",
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

		-- Set while cash collection runs, so checkpoint teleports wait for it
		local busy = false

		-- Loot / sensor loop
		task.spawn(function()
			while running and character.Parent do
				task.wait(0.1)
				pcall(function()
					event:FireServer("GameManager", "Replay")
				end)

				if root and root.Parent then
					local cash = workspace:FindFirstChild("Cash")
					if cash and #cash:GetChildren() > 0 then
						busy = true
						for _, item in ipairs(cash:GetChildren()) do
							if not running then break end
							local sensor = item:FindFirstChild("TouchSensor")
							if sensor then
								character:PivotTo(sensor.CFrame)
								if typeof(firetouchinterest) == "function" then
									firetouchinterest(root, sensor, true)
									firetouchinterest(root, sensor, false)
								end
								task.wait(0.15)
							end
						end
						busy = false
					end

					local loot = workspace:FindFirstChild("Loot")
					if loot then
						for _, item in ipairs(loot:GetChildren()) do
							local sensor = item:FindFirstChild("TouchSensor")
								or (item:FindFirstChild("Cash") and item.Cash:FindFirstChild("TouchSensor"))
							if sensor and typeof(firetouchinterest) == "function" then
								firetouchinterest(root, sensor, true)
								firetouchinterest(root, sensor, false)
							end
						end
					end
				end
			end
		end)

		local function waitRespectingBusy(duration)
			local start = tick()
			while tick() - start < duration do
				while busy do task.wait(0.05) end
				task.wait(0.05)
			end
		end

		local function teleportRespectingBusy(cframe)
			while busy do task.wait(0.05) end
			character:PivotTo(cframe)
		end

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
					teleportRespectingBusy(child:GetPivot())
					clearWorld()
					waitRespectingBusy(0.8)
				end
			end
		end

		-- Determine checkpoints
		local points = { 2500, 22000, 45000, 83700, 120000 }

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
				if #found < 5 then
					found[#found + 1] = found[#found] + 25000
				end
				points = found
			end
		end

		for _, z in ipairs(points) do
			if not running then break end
			teleportRespectingBusy(CFrame.new(savedCFrame.Position.X, 2200, z))
			clearWorld()
			waitRespectingBusy(0.25)
		end

		-- Move past the final door
		local map2 = workspace:FindFirstChild("Map")
		local buildings2 = map2 and map2:FindFirstChild("Buildings")
		local customs = buildings2 and buildings2:FindFirstChild("CustomsFinal")

		if customs then
			teleportRespectingBusy(customs:GetPivot() * CFrame.new(0, 10, 1500))
		else
			teleportRespectingBusy(CFrame.new(savedCFrame.Position.X, 2200, points[#points] + 2500))
		end

		clearWorld()
		waitRespectingBusy(2)

		running = false
		get5StarsRunning = false

		if character.Parent then
			teleportRespectingBusy(savedCFrame)
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