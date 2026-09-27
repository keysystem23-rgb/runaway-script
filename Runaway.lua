--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--// Load VindUI Reborn
local VindUI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Skinny-yz/vindUI-Test/main/full.luau"
))()

VindUI:SetTheme("Dark")
VindUI:PreloadIcons({ "Lucide", "Material", "Phosphor", "SF" })
VindUI:SetScaleRange(0.75, 1.35)

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
	UserInfo = { Enabled = true, Avatar = "player", NameMode = "display" },
})

VindUI:Notify({
	Title = "RUNAWAYS",
	Text = "Script loaded successfully.",
	Type = "success",
	Duration = 4,
})

--// Modules
local okData, Data = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Data"))
end)
local okFlow, flow = pcall(function()
	return require(ReplicatedStorage:WaitForChild("FlowClient"))
end)
local lootFolder = workspace:FindFirstChild("Loot")

--// Config
local Config = {
	DAMAGE = 9999,
	INSTANT_DAMAGE = 1e999,
	COOLDOWN = 0.1,
	SCAN_INTERVAL = 3,
	DIR_SPEED = 5,
	CAR_SPEED = 2,
	MAX_GAS = 100,
	BLOCKED_REMOTES = {
		"AntiCheatReport", "FlagPlayer", "ReportExploit",
		"KickPlayer", "BanPlayer", "AC_Heartbeat",
	},
}

--// State
local State = {
	killNPCs = false,
	dirSpeed = false,
	noClip = false,
	carFly = false,
	thirdPerson = false,
	infFuel = false,
	godMode = false,
	speedBoost = false,
	jumpOverride = false,
	fovOverride = false,
	gravityOverride = false,
	antiAFK = true,
	instantPrompt = false,
	lootAura = false,
	cashAura = false,
	indestructible = false,
	autoRefuel = false,
	infiniteAmmo = false,
	noCooldown = false,
	automaticFire = false,
	noRecoil = false,
	noSpread = false,
	espEnabled = false,
	espItems = true,
	espNPCs = true,
	espPlayers = true,
	espVehicles = true,
}

local lastHit = {}
local lastScan = 0
local carFlyAnchor = nil
local hookedNamecall = false
local oldNamecall = nil
local busy = false

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--// Original function references (for restore)
local originalTakeDamage = flow and flow.PlayerDamage and flow.PlayerDamage.TakeDamage
local originalAbandon = flow and flow.Passout and flow.Passout.Abandon
local originalVehicleDamage = flow and flow.DamageVehicle and flow.DamageVehicle.Damage
local originalSetAmmo = flow and flow.Ammo and flow.Ammo.setAmmo
local originalSubtractReserve = flow and flow.Ammo and flow.Ammo.substractReserve
local originalCameraRecoil = flow and flow.Camera and flow.Camera.Recoil
local originalViewmodelRecoil = flow and flow.Viewmodel and flow.Viewmodel.Recoil
local originalRadialFalloff = nil
do
	local okPkg, Packages = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Packages"))
	end)
	if okPkg and Packages.Utility and Packages.Utility.Luck then
		originalRadialFalloff = Packages.Utility.Luck.radialFalloff
	end
end

local blockedRemote = function() end

--// Character helpers
local function getChar() return LocalPlayer.Character end

local function getRoot()
	local c = getChar()
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local c = getChar()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function getVehicle()
	local hum = getHumanoid()
	local seat = hum and hum.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then return nil end
	local vehicle = seat:FindFirstAncestorOfClass("Model")
	if not vehicle or not vehicle:FindFirstChild("VehicleProperty") then return nil end
	return vehicle
end

local function getChassis(vehicle)
	local sys = vehicle and vehicle:FindFirstChild("system")
	return sys and sys:FindFirstChild("chassis")
end

--// Terrain-safe position (Directional Speed)
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Whitelist
terrainParams.FilterDescendantsInstances = { workspace.Terrain }

local function getSafePosition(pos)
	local result = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), terrainParams)
	if result and pos.Y < result.Position.Y + 2 then
		return Vector3.new(pos.X, result.Position.Y + 2, pos.Z)
	end
	return pos
end

--// Input helpers
local function getMobileInput()
	local ctrl = require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
	local mv = ctrl:GetMoveVector()
	return Vector2.new(mv.X, -mv.Z)
end

local function getInputDir()
	if isMobile then
		local mv = getMobileInput()
		return mv.X, mv.Y
	end
	local fwd   = (UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up))    and 1 or 0
	local back  = (UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down))  and 1 or 0
	local left  = (UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left))  and 1 or 0
	local right = (UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right)) and 1 or 0
	return right - left, fwd - back
end

local function isUpPressed()
	return not isMobile and UserInputService:IsKeyDown(Enum.KeyCode.Space)
end

local function isDownPressed()
	if isMobile then return false end
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C)
end

--// Tabs
local MainGroup    = Window:AddTabGroup({ Name = "RUNAWAYS" })
local ToolsGroup   = Window:AddTabGroup({ Name = "TOOLS" })
local ProtectGroup = Window:AddTabGroup({ Name = "PROTECTION" })

local HomeTab    = MainGroup:AddTab({ Name = "Home",     Icon = "Lucide:house" })
local PlayerTab  = MainGroup:AddTab({ Name = "Player",   Icon = "Lucide:user" })
local LootTab    = MainGroup:AddTab({ Name = "Loot",     Icon = "Lucide:package" })
local VehicleTab = ToolsGroup:AddTab({ Name = "Vehicles", Icon = "Lucide:car" })
local ESPTab     = ToolsGroup:AddTab({ Name = "ESP",      Icon = "Lucide:eye" })
local ProtectTab = ProtectGroup:AddTab({ Name = "Remotes", Icon = "Lucide:shield" })

--// ================== COMBAT ==================
local function fireDamage(target, dmg)
	local ok, err = pcall(function()
		ReplicatedStorage.FlowClient.ClientRunner.Event:FireServer("NPCs", "Damage", target, dmg)
	end)
	return ok
end

local Combat = HomeTab:AddCollapsibleSection({
	Title = "Combat", Icon = "Lucide:sword", Collapsed = false,
})

Combat:AddToggle({
	Text = "Kill All NPCs",
	Description = "Damages tagged NPCs, workspace.NPCs, and the helicopter pilot.",
	Icon = "Lucide:skull",
	Flag = "killnpcs",
	Default = false,
	Callback = function(state)
		State.killNPCs = state
		if not state then table.clear(lastHit) end
	end,
})

RunService.Heartbeat:Connect(function()
	if not State.killNPCs then return end
	local now = tick()

	for _, npc in ipairs(CollectionService:GetTagged("NPC")) do
		local hum = npc:FindFirstChild("Humanoid")
		if hum and hum.Health > 0 and now - (lastHit[hum] or 0) >= Config.COOLDOWN then
			lastHit[hum] = now
			fireDamage(hum, Config.DAMAGE)
		end
	end

	if now - lastScan >= Config.SCAN_INTERVAL then
		lastScan = now
		pcall(function()
			for _, d in pairs(workspace.NPCs:GetDescendants()) do
				if d.Name == "Humanoid" and d.Health > 0 then
					fireDamage(d, Config.INSTANT_DAMAGE)
				end
			end
		end)
	end

	for _, heli in ipairs({
		ReplicatedStorage:FindFirstChild("Assets")
			and ReplicatedStorage.Assets:FindFirstChild("Helicopter"),
		workspace:FindFirstChild("Helicopter"),
	}) do
		local pilot = heli and heli:FindFirstChild("Pilot")
		local hum = pilot and pilot:FindFirstChild("Humanoid")
		if hum and hum.Health > 0 then fireDamage(hum, Config.INSTANT_DAMAGE) end
	end
end)

--// ================== MOVEMENT ==================
local walkSpeed = 1

local Movement = HomeTab:AddCollapsibleSection({
	Title = "Movement", Icon = "Lucide:move", Collapsed = false,
})

Movement:AddSlider({
	Text = "Walk Speed (TP)",
	Description = "Scales horizontal movement via TranslateBy.",
	Icon = "Lucide:gauge",
	Flag = "tpwalk_speed",
	Min = 1, Max = 100, Default = 1, Increment = 1,
	Callback = function(value) walkSpeed = tonumber(value) or 1 end,
})

RunService.Heartbeat:Connect(function(dt)
	local c = getChar()
	local hum = c and c:FindFirstChildWhichIsA("Humanoid")
	if not c or not hum or not hum.Parent then return end
	if hum.MoveDirection.Magnitude > 0 then
		c:TranslateBy(hum.MoveDirection * walkSpeed * dt * 10)
	end
end)

Movement:AddToggle({
	Text = "Directional Speed",
	Description = "Camera-relative WASD movement with terrain safety.",
	Icon = "Lucide:rocket",
	Flag = "dirspeed",
	Default = false,
	Callback = function(state) State.dirSpeed = state end,
})

Movement:AddSlider({
	Text = "Directional Speed Amount",
	Icon = "Lucide:gauge",
	Flag = "dirspeed_amt",
	Min = 1, Max = 50, Default = 5, Increment = 1,
	Callback = function(value) Config.DIR_SPEED = tonumber(value) or 5 end,
})

RunService.Heartbeat:Connect(function()
	if not State.dirSpeed then return end
	local root = getRoot()
	if not root then return end
	local strafe, forward = getInputDir()
	if math.abs(strafe) < 0.01 and math.abs(forward) < 0.01 then return end
	local camCF = Camera.CFrame
	local flat  = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
	local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
	local dir = flat * forward + right * strafe
	if dir.Magnitude < 0.01 then return end
	local newPos = getSafePosition(root.Position + dir.Unit * Config.DIR_SPEED)
	root.CFrame = CFrame.new(newPos) * (root.CFrame - root.CFrame.Position)
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
			if noclipConnection then noclipConnection:Disconnect() end
			noclipConnection = RunService.Heartbeat:Connect(function()
				local c = getChar()
				if not c or antiVoidBusy then return end
				local root = c:FindFirstChild("HumanoidRootPart")
				if not root then return end
				for _, part in ipairs(c:GetDescendants()) do
					if part:IsA("BasePart") then part.CanCollide = false end
				end
				local y = root.Position.Y
				if not lastSafeCFrame or y >= lastSafeCFrame.Position.Y - 5 then
					lastSafeCFrame = root.CFrame
				elseif lastSafeCFrame.Position.Y - y >= 100 then
					antiVoidBusy = true
					root.AssemblyLinearVelocity = Vector3.zero
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { c }
					local found = false
					for _ = 1, 20 do
						root.CFrame = root.CFrame + Vector3.new(0, 150, 0)
						task.wait()
						local hit = workspace:Raycast(root.Position, Vector3.new(0, -2000, 0), params)
						if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
							root.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0),
								root.Position + root.CFrame.LookVector)
							found = true
							break
						end
					end
					if not found then root.CFrame = root.CFrame + Vector3.new(0, 150, 0) end
					root.AssemblyLinearVelocity = Vector3.zero
					lastSafeCFrame = root.CFrame
					antiVoidBusy = false
				end
			end)
		else
			if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
			lastSafeCFrame = nil
			antiVoidBusy = false
			local c = getChar()
			if c then
				for _, part in ipairs(c:GetDescendants()) do
					if part:IsA("BasePart") then part.CanCollide = true end
				end
			end
		end
	end,
})

local infJumpConnection
Movement:AddToggle({
	Text = "Inf Jump",
	Description = "Allows jumping mid-air.",
	Icon = "Lucide:arrow-up-circle",
	Flag = "infjump",
	Default = false,
	Callback = function(state)
		if state then
			if infJumpConnection then return end
			infJumpConnection = UserInputService.JumpRequest:Connect(function()
				local hum = getHumanoid()
				if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
			end)
		else
			if infJumpConnection then infJumpConnection:Disconnect(); infJumpConnection = nil end
		end
	end,
})

--// Third Person
Movement:AddToggle({
	Text = "Third Person",
	Description = "Unlocks the camera to third person.",
	Icon = "Lucide:eye",
	Flag = "thirdperson",
	Default = false,
	Callback = function(state)
		State.thirdPerson = state
		if state then
			LocalPlayer.CameraMode = Enum.CameraMode.Classic
			LocalPlayer.CameraMinZoomDistance = 5
			LocalPlayer.CameraMaxZoomDistance = 25
			UserInputService.MouseIconEnabled = true
		else
			LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
			LocalPlayer.CameraMinZoomDistance = 0
			UserInputService.MouseIconEnabled = false
		end
		Camera.CameraType = Enum.CameraType.Custom
		local h = getHumanoid()
		if h then Camera.CameraSubject = h end
	end,
})

--// ================== PLAYER (GodMode / Speed / Jump / FOV / Gravity) ==================
local PlayerSection = PlayerTab:AddCollapsibleSection({
	Title = "Player", Icon = "Lucide:user-cog", Collapsed = false,
})

local humanoidState = {}

local function saveHumanoidState(hum)
	if humanoidState[hum] then return end
	humanoidState[hum] = {
		WalkSpeed = hum.WalkSpeed,
		JumpPower = hum.JumpPower,
		JumpHeight = hum.JumpHeight,
		UseJumpPower = hum.UseJumpPower,
		BreakJointsOnDeath = hum.BreakJointsOnDeath,
		RequiresNeck = hum.RequiresNeck,
		DeadEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Dead),
	}
end

local function applyGodMode()
	if originalTakeDamage then flow.PlayerDamage.TakeDamage = blockedRemote end
	if originalAbandon then flow.Passout.Abandon = blockedRemote end
	local hum = getHumanoid()
	if hum then
		saveHumanoidState(hum)
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		hum.Health = hum.MaxHealth
	end
end

local function restoreGodMode()
	if flow and flow.PlayerDamage and flow.PlayerDamage.TakeDamage == blockedRemote then
		flow.PlayerDamage.TakeDamage = originalTakeDamage
	end
	if flow and flow.Passout and flow.Passout.Abandon == blockedRemote then
		flow.Passout.Abandon = originalAbandon
	end
	for hum, state in humanoidState do
		if hum.Parent and state.BreakJointsOnDeath ~= nil then
			hum.BreakJointsOnDeath = state.BreakJointsOnDeath
			hum.RequiresNeck = state.RequiresNeck
			hum:SetStateEnabled(Enum.HumanoidStateType.Dead, state.DeadEnabled)
		end
		state.BreakJointsOnDeath = nil
		state.RequiresNeck = nil
		state.DeadEnabled = nil
	end
end

PlayerSection:AddToggle({
	Text = "God Mode",
	Description = "Blocks damage + passout, keeps HP full.",
	Icon = "Lucide:heart-pulse",
	Flag = "godmode",
	Default = false,
	Callback = function(state)
		State.godMode = state
		if state then applyGodMode() else restoreGodMode() end
	end,
})

PlayerSection:AddToggle({
	Text = "Speed Boost",
	Description = "Overrides Humanoid.WalkSpeed.",
	Icon = "Lucide:zap",
	Flag = "speedboost",
	Default = false,
	Callback = function(state) State.speedBoost = state end,
})

PlayerSection:AddSlider({
	Text = "Walk Speed Value",
	Icon = "Lucide:gauge",
	Flag = "player_walkspeed",
	Min = 16, Max = 200, Default = 40, Increment = 1,
	Callback = function() end,
})

PlayerSection:AddToggle({
	Text = "Jump Power Override",
	Description = "Forces UseJumpPower with custom JumpPower.",
	Icon = "Lucide:arrow-up",
	Flag = "jumpoverride",
	Default = false,
	Callback = function(state) State.jumpOverride = state end,
})

PlayerSection:AddSlider({
	Text = "Jump Power Value",
	Icon = "Lucide:arrow-up",
	Flag = "player_jumppower",
	Min = 25, Max = 200, Default = 60, Increment = 1,
	Callback = function() end,
})

PlayerSection:AddToggle({
	Text = "FOV Override",
	Icon = "Lucide:camera",
	Flag = "fovoverride",
	Default = false,
	Callback = function(state) State.fovOverride = state end,
})

PlayerSection:AddSlider({
	Text = "Field of View",
	Icon = "Lucide:camera",
	Flag = "player_fov",
	Min = 30, Max = 120, Default = 70, Increment = 1,
	Callback = function() end,
})

PlayerSection:AddToggle({
	Text = "Gravity Override",
	Icon = "Lucide:moon",
	Flag = "gravityoverride",
	Default = false,
	Callback = function(state) State.gravityOverride = state end,
})

PlayerSection:AddSlider({
	Text = "Gravity",
	Icon = "Lucide:moon",
	Flag = "player_gravity",
	Min = 0, Max = 300, Default = 196, Increment = 1,
	Callback = function() end,
})

PlayerSection:AddToggle({
	Text = "Anti-AFK",
	Description = "Prevents idle kick.",
	Icon = "Lucide:clock",
	Flag = "antiafk",
	Default = true,
	Callback = function(state) State.antiAFK = state end,
})

-- Player applier
local fovRenderName = "RUNAWAYS_FOV"
local originalGravity = workspace.Gravity

RunService.PreSimulation:Connect(function()
	local hum = getHumanoid()
	if not hum or hum.Health <= 0 then return end
	saveHumanoidState(hum)

	if State.speedBoost then
		hum.WalkSpeed = VindUI.Options and 40 or 40
	else
		if humanoidState[hum] and humanoidState[hum].WalkSpeed then
			hum.WalkSpeed = humanoidState[hum].WalkSpeed
		end
	end

	if State.jumpOverride then
		hum.UseJumpPower = true
		hum.JumpPower = 60
	else
		if humanoidState[hum] and humanoidState[hum].UseJumpPower ~= nil then
			hum.UseJumpPower = humanoidState[hum].UseJumpPower
			hum.JumpPower = humanoidState[hum].JumpPower
			hum.JumpHeight = humanoidState[hum].JumpHeight
		end
	end

	if State.gravityOverride then
		workspace.Gravity = 100
	else
		workspace.Gravity = originalGravity
	end
end)

pcall(function() RunService:UnbindFromRenderStep(fovRenderName) end)
RunService:BindToRenderStep(fovRenderName, Enum.RenderPriority.Camera.Value + 2, function()
	if not State.fovOverride then return end
	if Camera then Camera.FieldOfView = 90 end
end)

--// Anti-AFK
local antiAFKConnection
task.spawn(function()
	while task.wait(1) do
		if State.antiAFK then
			if not antiAFKConnection then
				antiAFKConnection = LocalPlayer.Idled:Connect(function()
					local vu = game:GetService("VirtualUser")
					pcall(function()
						vu:CaptureController()
						vu:ClickButton2(Vector2.zero)
					end)
				end)
			end
		else
			if antiAFKConnection then
				antiAFKConnection:Disconnect()
				antiAFKConnection = nil
			end
		end
	end
end)

--// ================== TELEPORT ==================
local Teleport = HomeTab:AddCollapsibleSection({
	Title = "Teleport", Icon = "Lucide:map-pin", Collapsed = false,
})

Teleport:AddButton({
	Text = "Goto FinalDoor",
	Icon = "Lucide:door-open",
	Callback = function()
		local c = getChar()
		local root = c and c:FindFirstChild("HumanoidRootPart")
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
				if prompt then fireproximityprompt(prompt) end
			end
		end
	end,
})

Teleport:AddButton({
	Text = "Teleport to Start",
	Icon = "Lucide:home",
	Callback = function()
		local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
		local root = getRoot()
		if not spawn or not root then return end
		root.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
	end,
})

Teleport:AddButton({
	Text = "Teleport to Objective",
	Icon = "Lucide:target",
	Callback = function()
		local dest = LocalPlayer:GetAttribute("Pointy")
		local root = getRoot()
		if typeof(dest) ~= "CFrame" or not root then return end
		root.CFrame = CFrame.new(dest.Position + Vector3.new(0, 4, 0)) * dest.Rotation
	end,
})

Teleport:AddButton({
	Text = "Save Current Position",
	Icon = "Lucide:bookmark",
	Callback = function()
		local root = getRoot()
		if not root then return end
		Teleport.SavedPosition = root.CFrame
		VindUI:Notify({ Title = "Teleport", Text = "Position saved.", Type = "success", Duration = 3 })
	end,
})

Teleport:AddButton({
	Text = "Teleport to Saved",
	Icon = "Lucide:bookmark-check",
	Callback = function()
		local root = getRoot()
		if not root or not Teleport.SavedPosition then return end
		root.CFrame = Teleport.SavedPosition
	end,
})

--// ================== VEHICLE ==================
local vehicleNames = {}
for _, v in ipairs(workspace.Vehicles:GetChildren()) do
	if v:IsA("Model") or v:IsA("BasePart") then
		vehicleNames[#vehicleNames + 1] = v.Name
	end
end
table.sort(vehicleNames)

local selectedVehicle

local Vehicles = VehicleTab:AddCollapsibleSection({
	Title = "Vehicles", Icon = "Lucide:car", Collapsed = false,
})

Vehicles:AddDropdown({
	Text = "Choose a Vehicle",
	Icon = "Lucide:list",
	Flag = "vehicle_list",
	Options = vehicleNames,
	Default = vehicleNames[1] or "==Select Vehicle==",
	Callback = function(name) selectedVehicle = name end,
})

Vehicles:AddButton({
	Text = "Teleport to Vehicle",
	Icon = "Lucide:navigation",
	Callback = function()
		if not selectedVehicle then return end
		local v = workspace.Vehicles:FindFirstChild(selectedVehicle)
		local root = getRoot()
		if not v or not root then return end
		local cf = v:IsA("BasePart") and v.CFrame or v:GetPivot()
		root.CFrame = cf * CFrame.new(0, 5, 0)
	end,
})

Vehicles:AddToggle({
	Text = "Infinite Fuel",
	Description = "Keeps your current vehicle's gasLevel at maximum.",
	Icon = "Lucide:fuel",
	Flag = "inffuel",
	Default = false,
	Callback = function(state) State.infFuel = state end,
})

RunService.Heartbeat:Connect(function()
	if not State.infFuel then return end
	local v = getVehicle()
	local gas = v and v:FindFirstChild("gasLevel")
	if gas and gas:IsA("NumberValue") and gas.Value < Config.MAX_GAS then
		gas.Value = Config.MAX_GAS
	end
end)

Vehicles:AddToggle({
	Text = "Indestructible Vehicle",
	Description = "Blocks DamageVehicle.Damage for your current car.",
	Icon = "Lucide:shield",
	Flag = "indestructible",
	Default = false,
	Callback = function(state)
		State.indestructible = state
		if originalVehicleDamage then
			if state then
				flow.DamageVehicle.Damage = function(vehicle, ...)
					local mine = getVehicle()
					if mine and vehicle == mine then return end
					return originalVehicleDamage(vehicle, ...)
				end
			elseif flow.DamageVehicle.Damage ~= originalVehicleDamage then
				flow.DamageVehicle.Damage = originalVehicleDamage
			end
		end
	end,
})

Vehicles:AddButton({
	Text = "Flip Vehicle",
	Icon = "Lucide:rotate-cw",
	Callback = function()
		local v = getVehicle()
		if not v then return end
		local chassis = getChassis(v)
		local seat = v:FindFirstChildWhichIsA("VehicleSeat", true)
		if not chassis or not seat then return end
		local forward = Vector3.new(seat.CFrame.LookVector.X, 0, seat.CFrame.LookVector.Z)
		if forward.Magnitude < 0.1 then forward = Vector3.new(0, 0, -1) end
		local pos = seat.Position + Vector3.new(0, 3, 0)
		local target = CFrame.lookAt(pos, pos + forward.Unit, Vector3.yAxis)
		v:PivotTo(target * seat.CFrame:Inverse() * v:GetPivot())
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end,
})

Vehicles:AddButton({
	Text = "Stop Vehicle",
	Icon = "Lucide:hand",
	Callback = function()
		local v = getVehicle()
		local chassis = getChassis(v)
		if not chassis then return end
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end,
})

Vehicles:AddToggle({
	Text = "Car Fly",
	Description = "Fly the current vehicle with WASD + Space / Ctrl.",
	Icon = "Lucide:plane",
	Flag = "carfly",
	Default = false,
	Callback = function(state)
		State.carFly = state
		if not state then carFlyAnchor = nil end
	end,
})

Vehicles:AddSlider({
	Text = "Car Fly Speed",
	Icon = "Lucide:gauge",
	Flag = "carfly_speed",
	Min = 1, Max = 150, Default = 2, Increment = 1,
	Callback = function(value) Config.CAR_SPEED = tonumber(value) or 2 end,
})

RunService.Heartbeat:Connect(function()
	if not State.carFly then carFlyAnchor = nil; return end
	local v = getVehicle()
	if not v then carFlyAnchor = nil; return end
	for _, part in ipairs(v:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local strafe, forward = getInputDir()
	local upDown = (isUpPressed() and 1 or 0) - (isDownPressed() and 1 or 0)
	local hasInput = math.abs(strafe) > 0.01 or math.abs(forward) > 0.01 or upDown ~= 0
	local pivot = v:GetPivot()
	if not hasInput then
		if carFlyAnchor then
			v:PivotTo(CFrame.new(carFlyAnchor) * (pivot - pivot.Position))
		else
			carFlyAnchor = pivot.Position
		end
		return
	end
	local camCF = Camera.CFrame
	local dir = camCF.LookVector * forward + camCF.RightVector * strafe + Vector3.new(0, upDown, 0)
	if dir.Magnitude < 0.01 then return end
	local newPos = pivot.Position + dir.Unit * Config.CAR_SPEED
	carFlyAnchor = newPos
	v:PivotTo(CFrame.new(newPos) * (pivot - pivot.Position))
end)

--// Auto Refuel
Vehicles:AddToggle({
	Text = "Auto Refuel",
	Description = "Automatically refuels your vehicle at gas pumps.",
	Icon = "Lucide:fuel",
	Flag = "autorefuel",
	Default = false,
	Callback = function(state) State.autoRefuel = state end,
})

RunService.Heartbeat:Connect(function()
	if not State.autoRefuel or busy then return end
	local v = getVehicle()
	if not v then return end
	local gas = v:FindFirstChild("gasLevel")
	local prop = v:FindFirstChild("VehicleProperty")
	local cap = prop and prop:GetAttribute("GasCapacity")
	if not gas or type(cap) ~= "number" or gas.Value >= cap - 0.01 then return end

	local root = getRoot()
	if not root then return end

	for _, pump in ipairs(CollectionService:GetTagged("GasPump")) do
		local detector = pump:FindFirstChild("DetectCarCollider")
		if detector and detector:IsA("BasePart") and (detector.Position - root.Position).Magnitude <= 15 then
			local pay = pump:FindFirstChild("PayGas")
			local click = pay and pay:FindFirstChildWhichIsA("ClickDetector", true)
			if click then pcall(fireclickdetector, click, 0, "MouseClick") end
			pcall(function()
				if flow.GasPump and flow.GasPump.Pour then
					flow.GasPump.Pour(pump, false)
					task.wait(0.05)
					flow.GasPump.Pour(pump, true)
				end
			end)
			return
		end
	end
end)

--// ================== LOOT ==================
local function isLoot(item)
	if not lootFolder or item.Parent ~= lootFolder or not item:IsA("Model") then return false end
	local part = item.PrimaryPart
	return part and part:IsA("BasePart") and part.Parent == item
		and CollectionService:HasTag(item, "Draggable")
		and CollectionService:HasTag(item, "Equippable")
		and not CollectionService:HasTag(item, "BuyableLoot")
end

local function getLoot()
	local items = {}
	if not lootFolder then return items end
	for _, item in lootFolder:GetChildren() do
		if isLoot(item) then items[#items + 1] = item end
	end
	return items
end

local function getPickupCFrame(root, part)
	local offset = root.Position - part.Position
	local dir = Vector3.new(offset.X, 0, offset.Z)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
	local pos = part.Position + dir * 3 + Vector3.new(0, 2.5, 0)
	return CFrame.lookAt(pos, Vector3.new(part.Position.X, pos.Y, part.Position.Z))
end

local LootSection = LootTab:AddCollapsibleSection({
	Title = "Loot", Icon = "Lucide:package", Collapsed = false,
})

LootSection:AddToggle({
	Text = "Loot Aura",
	Description = "Auto-equips any loot within 8 studs.",
	Icon = "Lucide:sparkles",
	Flag = "lootaura",
	Default = false,
	Callback = function(state) State.lootAura = state end,
})

RunService.Heartbeat:Connect(function()
	if not State.lootAura or busy or not flow or not flow.Loot then return end
	local root = getRoot()
	local hum = getHumanoid()
	if not root or not hum or hum.SeatPart or hum.Health <= 0 then return end
	local nearest, nearestDist = nil, 8
	for _, item in getLoot() do
		local part = item.PrimaryPart
		if part then
			local d = (part.Position - root.Position).Magnitude
			if d <= nearestDist then nearest = item; nearestDist = d end
		end
	end
	if not nearest then return end
	busy = true
	pcall(flow.Loot.LootEquip, nearest.PrimaryPart)
	busy = false
end)

LootSection:AddToggle({
	Text = "Cash Aura",
	Description = "Auto-collects cash drops within 7 studs.",
	Icon = "Lucide:dollar-sign",
	Flag = "cashaura",
	Default = false,
	Callback = function(state) State.cashAura = state end,
})

RunService.Heartbeat:Connect(function()
	if not State.cashAura or not flow or not flow.Cash then return end
	local root = getRoot()
	if not root then return end
	for _, cash in CollectionService:GetTagged("Cash") do
		local holder = cash.Parent
		local sensor = holder and holder:FindFirstChild("TouchSensor", true)
		if sensor and sensor:IsA("BasePart") and (sensor.Position - root.Position).Magnitude <= 7 then
			pcall(flow.Cash.Collect, cash)
		end
	end
end)

LootSection:AddButton({
	Text = "Bring All Loot",
	Description = "Teleports to every loot item and equips it.",
	Icon = "Lucide:package-plus",
	Callback = function()
		if busy then return end
		if not flow or not flow.Loot or type(flow.Loot.LootEquip) ~= "function" then
			VindUI:Notify({ Title = "Loot", Text = "LootEquip unavailable.", Type = "error" })
			return
		end
		busy = true
		task.spawn(function()
			local c = getChar()
			local root = c and c:FindFirstChild("HumanoidRootPart")
			if not c or not root then busy = false; return end
			local saved = c:GetPivot()
			local brought = 0
			for _, item in getLoot() do
				if not isLoot(item) then continue end
				local part = item.PrimaryPart
				if not part then continue end
				c:PivotTo(getPickupCFrame(root, part))
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				task.wait(0.18)
				local ok = pcall(flow.Loot.LootEquip, part)
				if ok then brought += 1 end
				task.wait(0.05)
			end
			if c.Parent then c:PivotTo(saved) end
			busy = false
			VindUI:Notify({ Title = "Loot", Text = "Brought " .. brought .. " items.", Type = "success" })
		end)
	end,
})

LootSection:AddButton({
	Text = "Drop All Loot",
	Description = "Drops every droppable tool.",
	Icon = "Lucide:trash-2",
	Callback = function()
		if busy then return end
		busy = true
		task.spawn(function()
			local dropped = 0
			local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
			local c = getChar()
			local hum = getHumanoid()
			if not bp or not c or not hum then busy = false; return end
			hum:UnequipTools()
			for _, container in { bp, c } do
				for _, tool in ipairs(container:GetChildren()) do
					if tool:IsA("Tool") and not tool:HasTag("Undroppable") then
						pcall(flow.Loot.LootUnequip, tool, tool:HasTag("RemoteOnly"))
						dropped += 1
						task.wait(0.05)
					end
				end
			end
			busy = false
			VindUI:Notify({ Title = "Loot", Text = "Dropped " .. dropped .. ".", Type = "success" })
		end)
	end,
})

LootSection:AddButton({
	Text = "Sell All Loot",
	Description = "Runs to the pawn counter and sells everything.",
	Icon = "Lucide:badge-dollar-sign",
	Callback = function()
		if busy then return end
		busy = true
		task.spawn(function()
			local counter = CollectionService:GetTagged("PawnCounter")[1]
			local bell = counter and counter:FindFirstChild("CallBell", true)
			local prompt = bell and bell:FindFirstChildWhichIsA("ProximityPrompt", true)
			local root = getRoot()
			local c = getChar()
			if not prompt or not root or not c then busy = false; return end
			local saved = c:GetPivot()
			c:PivotTo(prompt.Parent.CFrame + Vector3.new(0, 3, 0))
			task.wait(0.5)
			local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
			local tools = {}
			for _, container in { bp, c } do
				for _, tool in ipairs(container:GetChildren()) do
					if tool:IsA("Tool") and not tool:HasTag("Undroppable") then
						tools[#tools + 1] = tool
					end
				end
			end
			local sold = 0
			for _, tool in tools do
				pcall(flow.Loot.LootUnequip, tool, tool:HasTag("RemoteOnly"))
				task.wait(0.1)
				pcall(fireproximityprompt, prompt)
				task.wait(0.15)
				sold += 1
			end
			if c.Parent then c:PivotTo(saved) end
			busy = false
			VindUI:Notify({ Title = "Loot", Text = "Sold " .. sold .. ".", Type = "success" })
		end)
	end,
})

-- Instant Prompt
local instantPromptActive = false
local promptHoldStates = setmetatable({}, { __mode = "k" })

local function applyInstantPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	if promptHoldStates[prompt] == nil then
		promptHoldStates[prompt] = prompt.HoldDuration
	end
	prompt.HoldDuration = 0
end

LootSection:AddToggle({
	Text = "Instant Prompt",
	Description = "Sets every ProximityPrompt HoldDuration to 0.",
	Icon = "Lucide:zap",
	Flag = "instantprompt",
	Default = false,
	Callback = function(state)
		instantPromptActive = state
		if state then
			for _, p in workspace:QueryDescendants("ProximityPrompt") do
				applyInstantPrompt(p)
			end
		else
			for prompt, dur in promptHoldStates do
				if prompt.Parent then prompt.HoldDuration = dur end
			end
			table.clear(promptHoldStates)
		end
	end,
})

workspace.DescendantAdded:Connect(function(inst)
	if instantPromptActive and inst:IsA("ProximityPrompt") then
		applyInstantPrompt(inst)
	end
end)

--// ================== ESP ==================
local Drawing = Drawing
local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

local function newDraw(kind)
	if not drawingAvailable then return nil end
	local ok, obj = pcall(Drawing.new, kind)
	if not ok or not obj then drawingAvailable = false; return nil end
	obj.Visible = false
	return obj
end

local function removeDraw(obj)
	if not obj then return end
	obj.Visible = false
	pcall(function() obj:Remove() end)
end

local espVisuals = {
	Items = {}, NPCs = {}, Players = {}, Vehicles = {},
}

local function newVisual()
	return {
		Text = newDraw("Text"),
		Box = newDraw("Square"),
		Tracer = newDraw("Line"),
	}
end

local function hideVisual(vis)
	for _, obj in vis do if obj then obj.Visible = false end end
end

local function removeVisual(vis)
	for _, obj in vis do removeDraw(obj) end
end

local function clearVisuals(reg)
	for k, vis in reg do removeVisual(vis); reg[k] = nil end
end

local function updateVisual(kind, target, vis, camera, origin)
	local part, hum
	if kind == "Items" then
		if not isLoot(target) then hideVisual(vis); return end
		part = target.PrimaryPart
	elseif kind == "NPCs" then
		hum = target:FindFirstChildOfClass("Humanoid")
		part = target:FindFirstChild("HumanoidRootPart")
		if not hum or not part or hum.Health <= 0 then hideVisual(vis); return end
	elseif kind == "Players" then
		local c = target.Character
		hum = c and c:FindFirstChildOfClass("Humanoid")
		part = c and c:FindFirstChild("HumanoidRootPart")
		if not hum or not part or hum.Health <= 0 then hideVisual(vis); return end
	elseif kind == "Vehicles" then
		local sys = target:FindFirstChild("system")
		part = target.PrimaryPart or (sys and sys:FindFirstChild("chassis"))
	end
	if not part or not part.Parent then hideVisual(vis); return end

	local dist = (part.Position - origin).Magnitude
	local maxRange = 3000
	if dist > maxRange then hideVisual(vis); return end

	local point, onScreen = camera:WorldToViewportPoint(part.Position)
	if point.Z <= 0 or not onScreen then hideVisual(vis); return end

	local color = Color3.fromRGB(255, 255, 255)
	if kind == "Items" then color = Color3.fromRGB(255, 210, 90)
	elseif kind == "NPCs" then color = Color3.fromRGB(255, 90, 90)
	elseif kind == "Players" then color = Color3.fromRGB(75, 210, 255)
	elseif kind == "Vehicles" then color = Color3.fromRGB(180, 110, 255) end

	local name = kind == "Items" and target.Name or kind == "Players" and target.Name or target.Name
	local label = string.format("%s | %dm", name, math.round(dist))

	if vis.Text then
		vis.Text.Text = label
		vis.Text.Position = Vector2.new(point.X, point.Y - 20)
		vis.Text.Size = 13
		vis.Text.Center = true
		vis.Text.Color = color
		vis.Text.Outline = true
		vis.Text.OutlineColor = Color3.new(0, 0, 0)
		vis.Text.Visible = true
	end

	if vis.Box then
		local sz = Vector2.new(50, 50)
		vis.Box.Position = Vector2.new(point.X - sz.X / 2, point.Y - sz.Y / 2)
		vis.Box.Size = sz
		vis.Box.Color = color
		vis.Box.Thickness = 1
		vis.Box.Filled = false
		vis.Box.Visible = true
	end

	if vis.Tracer then
		vis.Tracer.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
		vis.Tracer.To = Vector2.new(point.X, point.Y)
		vis.Tracer.Color = color
		vis.Tracer.Thickness = 1
		vis.Tracer.Visible = true
	end
end

local espRenderName = "RUNAWAYS_ESP"

local function updateESP()
	if not State.espEnabled or not drawingAvailable then return end
	local origin = getRoot() and getRoot().Position or Camera.CFrame.Position

	local function sync(kind, targets, enabled)
		if not enabled then
			for _, vis in espVisuals[kind] do hideVisual(vis) end
			return
		end
		local active = {}
		for _, tgt in ipairs(targets) do
			active[tgt] = true
			local vis = espVisuals[kind][tgt]
			if not vis then vis = newVisual(); espVisuals[kind][tgt] = vis end
			updateVisual(kind, tgt, vis, Camera, origin)
		end
		for tgt, vis in espVisuals[kind] do
			if not active[tgt] then removeVisual(vis); espVisuals[kind][tgt] = nil end
		end
	end

	local items, npcs, players, vehicles = {}, {}, {}, {}
	if State.espItems and lootFolder then
		for _, item in getLoot() do items[#items + 1] = item end
	end
	if State.espNPCs then
		for _, npc in CollectionService:GetTagged("NPC") do
			if npc:IsA("Model") and npc:IsDescendantOf(workspace) then npcs[#npcs + 1] = npc end
		end
	end
	if State.espPlayers then
		for _, p in Players:GetPlayers() do
			if p ~= LocalPlayer and p.Character then players[#players + 1] = p end
		end
	end
	if State.espVehicles and workspace:FindFirstChild("Vehicles") then
		for _, v in workspace.Vehicles:GetChildren() do
			if v:IsA("Model") then vehicles[#vehicles + 1] = v end
		end
	end

	sync("Items", items, State.espItems)
	sync("NPCs", npcs, State.espNPCs)
	sync("Players", players, State.espPlayers)
	sync("Vehicles", vehicles, State.espVehicles)
end

pcall(function() RunService:UnbindFromRenderStep(espRenderName) end)
RunService:BindToRenderStep(espRenderName, Enum.RenderPriority.Camera.Value + 10, updateESP)

local ESPMain = ESPTab:AddCollapsibleSection({
	Title = "ESP", Icon = "Lucide:eye", Collapsed = false,
})

ESPMain:AddToggle({
	Text = "ESP Enabled",
	Icon = "Lucide:eye",
	Flag = "esp_enabled",
	Default = false,
	Callback = function(state)
		State.espEnabled = state
		if not state then
			for kind in espVisuals do clearVisuals(espVisuals[kind]) end
		end
	end,
})

ESPMain:AddToggle({
	Text = "Items",
	Flag = "esp_items",
	Default = true,
	Callback = function(state) State.espItems = state end,
})

ESPMain:AddToggle({
	Text = "NPCs",
	Flag = "esp_npcs",
	Default = true,
	Callback = function(state) State.espNPCs = state end,
})

ESPMain:AddToggle({
	Text = "Players",
	Flag = "esp_players",
	Default = true,
	Callback = function(state) State.espPlayers = state end,
})

ESPMain:AddToggle({
	Text = "Vehicles",
	Flag = "esp_vehicles",
	Default = true,
	Callback = function(state) State.espVehicles = state end,
})

--// ================== WEAPON MODS ==================
local WeaponSection = ToolsGroup:AddTab({ Name = "Weapon", Icon = "Lucide:crosshair" })

local WeaponMain = WeaponSection:AddCollapsibleSection({
	Title = "Weapon Mods", Icon = "Lucide:crosshair", Collapsed = false,
})

local function installWeaponHooks()
	if flow.Ammo and type(originalSetAmmo) == "function" then
		flow.Ammo.setAmmo = function(tool, value, ...)
			if State.infiniteAmmo then return end
			return originalSetAmmo(tool, value, ...)
		end
	end
	if flow.Ammo and type(originalSubtractReserve) == "function" then
		flow.Ammo.substractReserve = function(...)
			if State.infiniteAmmo then return end
			return originalSubtractReserve(...)
		end
	end
	if flow.Camera and type(originalCameraRecoil) == "function" then
		flow.Camera.Recoil = function(...)
			if State.noRecoil then return end
			return originalCameraRecoil(...)
		end
	end
	if flow.Viewmodel and type(originalViewmodelRecoil) == "function" then
		flow.Viewmodel.Recoil = function(...)
			if State.noRecoil then return end
			return originalViewmodelRecoil(...)
		end
	end
	if originalRadialFalloff then
		local Packages = require(ReplicatedStorage:WaitForChild("Packages"))
		Packages.Utility.Luck.radialFalloff = function(...)
			if State.noSpread then return Vector2.zero end
			return originalRadialFalloff(...)
		end
	end
end
pcall(installWeaponHooks)

WeaponMain:AddToggle({
	Text = "Infinite Ammo",
	Icon = "Lucide:infinity",
	Flag = "infammo",
	Default = false,
	Callback = function(state) State.infiniteAmmo = state end,
})

WeaponMain:AddToggle({
	Text = "No Cooldown",
	Icon = "Lucide:zap",
	Flag = "nocooldown",
	Default = false,
	Callback = function(state) State.noCooldown = state end,
})

WeaponMain:AddToggle({
	Text = "Automatic Fire",
	Icon = "Lucide:repeat",
	Flag = "autofire",
	Default = false,
	Callback = function(state) State.automaticFire = state end,
})

WeaponMain:AddToggle({
	Text = "No Recoil",
	Icon = "Lucide:target",
	Flag = "norecoil",
	Default = false,
	Callback = function(state) State.noRecoil = state end,
})

WeaponMain:AddToggle({
	Text = "No Spread",
	Icon = "Lucide:crosshair",
	Flag = "nospread",
	Default = false,
	Callback = function(state) State.noSpread = state end,
})

--// ================== AUTOMATION ==================
local get5StarsRunning = false

local Automation = HomeTab:AddCollapsibleSection({
	Title = "Automation", Icon = "Lucide:star", Collapsed = false,
})

Automation:AddButton({
	Text = "GET 5 STARS",
	Description = "Runs the full multi-stage completion script.",
	Icon = "Lucide:star",
	Callback = function()
		if get5StarsRunning then return end
		get5StarsRunning = true

		local running = true
		local character = getChar()
		if not character then
			get5StarsRunning = false
			return
		end

		local savedCFrame = character:GetPivot()
		local root = character:FindFirstChild("HumanoidRootPart")
		local event = ReplicatedStorage:WaitForChild("FlowClient")
			:WaitForChild("ClientRunner"):WaitForChild("Event")

		local localBusy = false

		task.spawn(function()
			while running and character.Parent do
				task.wait(0.1)
				pcall(function()
					event:FireServer("GameManager", "Replay")
				end)
				if root and root.Parent then
					local cash = workspace:FindFirstChild("Cash")
					if cash and #cash:GetChildren() > 0 then
						localBusy = true
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
						localBusy = false
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

		local function waitRespectingBusy(d)
			local start = tick()
			while tick() - start < d do
				while localBusy do task.wait(0.05) end
				task.wait(0.05)
			end
		end

		local function teleportRespectingBusy(cf)
			while localBusy do task.wait(0.05) end
			character:PivotTo(cf)
		end

		local function clearWorld()
			local map = workspace:FindFirstChild("Map")
			if map then
				for _, d in ipairs(map:GetDescendants()) do
					if d.Name:find("Glass") then
						pcall(function() event:FireServer("Effects", "BreakGlass", d) end)
					end
				end
			end
			local npcs = workspace:FindFirstChild("NPCs")
			if npcs then
				for _, child in ipairs(npcs:GetChildren()) do
					local hum = child:FindFirstChild("Humanoid")
					if hum then pcall(function() event:FireServer("NPCs", "Damage", hum, 13000) end) end
				end
			end
			local buildings = map and map:FindFirstChild("Buildings")
			if buildings then
				for _, d in ipairs(buildings:GetDescendants()) do
					if d.Name == "MaxHealth" and d.Parent then
						pcall(function() event:FireServer("DamageToOpen", "Damage", d.Parent, 6000, "melee") end)
					end
				end
			end
		end

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

		local points = { 2500, 22000, 45000, 83700, 120000 }
		local hud = LocalPlayer:FindFirstChild("PlayerGui")
			and LocalPlayer.PlayerGui:FindFirstChild("HudGui")
		local progress = hud and hud:FindFirstChild("Distance")
			and hud.Distance:FindFirstChild("Progress")
		if progress then
			local found = {}
			for _, child in ipairs(progress:GetChildren()) do
				local n = child.Name:match("Border_(%d+)")
				if n then found[#found + 1] = tonumber(n) end
			end
			if #found > 0 then
				table.sort(found)
				if #found < 5 then found[#found + 1] = found[#found] + 25000 end
				points = found
			end
		end
		for _, z in ipairs(points) do
			if not running then break end
			teleportRespectingBusy(CFrame.new(savedCFrame.Position.X, 2200, z))
			clearWorld()
			waitRespectingBusy(0.25)
		end
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
		if character.Parent then teleportRespectingBusy(savedCFrame) end
		VindUI:Notify({ Title = "GET 5 STARS", Text = "Run complete.", Type = "success", Duration = 3 })
	end,
})

--// ================== PROTECTION ==================
local ProtectSection = ProtectTab:AddCollapsibleSection({
	Title = "Remote Blocker", Icon = "Lucide:shield", Collapsed = false,
})

ProtectSection:AddParagraph({
	Title = "Anti-Cheat Remote Blocker",
	Text = "Hooks game.__namecall and drops FireServer / InvokeServer calls to known anti-cheat remotes.",
})

ProtectSection:AddToggle({
	Text = "Block Anti-Cheat Remotes",
	Description = "Requires hookmetamethod / checkcaller / getnamecallmethod support.",
	Icon = "Lucide:shield-check",
	Flag = "acblock",
	Default = false,
	Callback = function(state)
		if state then
			if hookedNamecall then return end
			local ok, err = pcall(function()
				oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
					local method = getnamecallmethod()
					if not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
						local name = self.Name
						for _, blocked in ipairs(Config.BLOCKED_REMOTES) do
							if name:find(blocked) then return end
						end
					end
					return oldNamecall(self, ...)
				end)
				hookedNamecall = true
			end)
			if ok then
				VindUI:Notify({ Title = "Remote Blocker", Text = "Remotes blocked.", Type = "success" })
			else
				VindUI:Notify({ Title = "Remote Blocker", Text = "Hook failed: " .. tostring(err), Type = "error" })
			end
		else
			if hookedNamecall and oldNamecall then
				pcall(function() hookmetamethod(game, "__namecall", oldNamecall) end)
				hookedNamecall = false
				oldNamecall = nil
				VindUI:Notify({ Title = "Remote Blocker", Text = "Blocker disabled.", Type = "info" })
			end
		end
	end,
})

--// ================== CLEANUP ==================
LocalPlayer.CharacterAdded:Connect(function()
	table.clear(lastHit)
	table.clear(humanoidState)
	carFlyAnchor = nil
	State.dirSpeed = false
	State.noClip = false
	State.carFly = false
	State.thirdPerson = false
end)

--// Camera default
LocalPlayer.CameraMode = Enum.CameraMode.Classic
LocalPlayer.CameraMinZoomDistance = 0
LocalPlayer.CameraMaxZoomDistance = 100

local ch = getHumanoid()
if ch then Camera.CameraSubject = ch end