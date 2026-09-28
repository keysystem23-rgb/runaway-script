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
local okFlow, flow = pcall(function() return require(ReplicatedStorage:WaitForChild("FlowClient")) end)
local lootFolder = workspace:FindFirstChild("Loot")

--// Config
local Config = {
    DAMAGE = 9999,
    INSTANT_DAMAGE = 1e999,
    COOLDOWN = 0.1,
    SCAN_INTERVAL = 3,
    CAR_SPEED = 2,
    MAX_GAS = 100,
    LOOT_RANGE = 50,
    CASH_RANGE = 50,
    MATCH_THRESHOLD = 0.6,
}

--// State
local State = {
    killNPCs = false,
    carFly = false,
    infFuel = false,
    godMode = false,
    vehicleGod = false,
    thirdPerson = false,
    espEnabled = false,
    espItems = true,
    lootAura = false,
    cashAura = false,
}

local lastHit = {}
local lastScan = 0
local carFlyAnchor = nil
local busy = false
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--// ================== ITEM WHITELIST / KEEP LIST ==================
local PICK_WHITELIST = {
    -- TIER 1: HIGH-VALUE HEAVY ITEMS (WELD TO TRUCK)
    "Gramophone", "Cat Statue", "Electric Guitar", "Turret", "Statue Thinker",
    -- TIER 2: POCKET VALUABLES (PUT IN BACKPACK)
    "King Crown", "Diamond Ring", "Diamond", "Gold Tiara", "Gold Diamond Necklace",
    "Penguin Plushy", "Gold Bar", "Ruby", "Diamond Watch", "Gold Ruby Necklace",
    "Ruby Ring", "Silver Sapphire Necklace", "Sapphire", "Silver Bar",
    -- BACKPACK
    "Large Backpack",
}

local KEEP_ON_DROP = {
    "Mace", "Crowbar", "Large Backpack",
}

--// ================== FUZZY NAME MATCHING ==================
local function levenshtein(a, b)
    a, b = a:lower():gsub("%s+", ""), b:lower():gsub("%s+", "")
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local curr = { [0] = i }
        for j = 1, lb do
            local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
            curr[j] = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = curr
    end
    return prev[lb]
end

local function similarity(a, b)
    if a:lower() == b:lower() then return 1 end

    -- Levenshtein similarity (handles typos, single-char edits)
    local lev = levenshtein(a, b)
    local levScore = 1 - lev / math.max(#a, #b)

    -- Token overlap (handles word reordering: "Large Backpack" vs "Backpack Large")
    local ta, tb = {}, {}
    local total, shared = 0, 0
    for w in a:gmatch("%a+") do ta[w:lower()] = true end
    for w in b:gmatch("%a+") do tb[w:lower()] = true end
    for w in pairs(ta) do
        total = total + 1
        if tb[w] then shared = shared + 1 end
    end
    for w in pairs(tb) do
        if not ta[w] then total = total + 1 end
    end
    local tokenScore = total > 0 and shared / total or 0

    return math.max(levScore, tokenScore)
end

-- Memoized so per-heartbeat loops stay cheap
local matchCache = {}
local function nameMatches(itemName, list, cachePrefix)
    if not itemName or itemName == "" then return false end
    local key = cachePrefix .. "|" .. itemName
    local cached = matchCache[key]
    if cached ~= nil then return cached end

    local matched = false
    for _, entry in ipairs(list) do
        if similarity(itemName, entry) >= Config.MATCH_THRESHOLD then
            matched = true
            break
        end
    end
    matchCache[key] = matched
    return matched
end

local function shouldPick(itemName)
    return nameMatches(itemName, PICK_WHITELIST, "pick")
end

local function shouldKeepOnDrop(itemName)
    return nameMatches(itemName, KEEP_ON_DROP, "keep")
end

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

local function findNearestVehicle(maxDist)
    local root = getRoot()
    if not root then return nil end
    local vehiclesFolder = workspace:FindFirstChild("Vehicles")
    if not vehiclesFolder then return nil end
    maxDist = maxDist or 500
    local nearest, nearestDist = nil, maxDist
    for _, v in vehiclesFolder:GetChildren() do
        if v:IsA("Model") and v:FindFirstChild("VehicleProperty") then
            local pivot = v:GetPivot().Position
            local d = (pivot - root.Position).Magnitude
            if d < nearestDist then nearest = v; nearestDist = d end
        end
    end
    return nearest
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
    local fwd = (UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)) and 1 or 0
    local back = (UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down)) and 1 or 0
    local left = (UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left)) and 1 or 0
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
local MainGroup = Window:AddTabGroup({ Name = "RUNAWAYS" })
local HomeTab = MainGroup:AddTab({ Name = "Home", Icon = "Lucide:house" })
local CombatTab = MainGroup:AddTab({ Name = "Combat", Icon = "Lucide:sword" })
local VehicleTab = MainGroup:AddTab({ Name = "Vehicle", Icon = "Lucide:car" })
local LootTab = MainGroup:AddTab({ Name = "Loot", Icon = "Lucide:package" })
local ESPTab = MainGroup:AddTab({ Name = "ESP", Icon = "Lucide:eye" })

--// ================== COMBAT: KILL NPCs ==================
local function fireDamage(target, dmg)
    local ok, err = pcall(function()
        ReplicatedStorage.FlowClient.ClientRunner.Event:FireServer("NPCs", "Damage", target, dmg)
    end)
    return ok
end

local Combat = CombatTab:AddCollapsibleSection({
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

--// ================== INFINITE HEALTH ==================
local originalTakeDamage = flow and flow.PlayerDamage and flow.PlayerDamage.TakeDamage
local originalAbandon = flow and flow.Passout and flow.Passout.Abandon
local originalVehicleDamage = flow and flow.DamageVehicle and flow.DamageVehicle.Damage
local blockedRemote = function() end

local function applyGodMode()
    if originalTakeDamage then flow.PlayerDamage.TakeDamage = blockedRemote end
    if originalAbandon then flow.Passout.Abandon = blockedRemote end
    local hum = getHumanoid()
    if hum then
        hum.BreakJointsOnDeath = false
        hum.RequiresNeck = false
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
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
end

local PlayerSection = HomeTab:AddCollapsibleSection({
    Title = "Player", Icon = "Lucide:user-cog", Collapsed = false,
})

PlayerSection:AddToggle({
    Text = "Infinite Health",
    Description = "Blocks damage + passout, keeps HP at max.",
    Icon = "Lucide:heart-pulse",
    Flag = "godmode",
    Default = false,
    Callback = function(state)
        State.godMode = state
        if state then applyGodMode() else restoreGodMode() end
    end,
})

PlayerSection:AddToggle({
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

-- Keep HP topped up
RunService.Heartbeat:Connect(function()
    if not State.godMode then return end
    local hum = getHumanoid()
    if hum and hum.Health < hum.MaxHealth then
        hum.Health = hum.MaxHealth
    end
end)

-- ================== VEHICLE ==================
local Vehicles = VehicleTab:AddCollapsibleSection({
    Title = "Vehicle", Icon = "Lucide:car", Collapsed = false,
})

Vehicles:AddButton({
    Text = "Teleport to Car",
    Description = "Teleports you to your current car, or the nearest one if you're not in a vehicle.",
    Icon = "Lucide:navigation",
    Callback = function()
        local root = getRoot()
        if not root then
            VindUI:Notify({ Title = "Vehicle", Text = "No character.", Type = "error" })
            return
        end
        local v = getVehicle() or findNearestVehicle(2000)
        if not v then
            VindUI:Notify({ Title = "Vehicle", Text = "No vehicle found nearby.", Type = "error" })
            return
        end
        local pivot = v:GetPivot()
        root.CFrame = pivot * CFrame.new(0, 5, 0)
        VindUI:Notify({ Title = "Vehicle", Text = "Teleported to " .. v.Name .. ".", Type = "success", Duration = 2 })
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

Vehicles:AddToggle({
    Text = "Infinite Fuel",
    Description = "Keeps your current vehicle's gasLevel at maximum.",
    Icon = "Lucide:fuel",
    Flag = "inffuel",
    Default = false,
    Callback = function(state) State.infFuel = state end,
})

Vehicles:AddToggle({
    Text = "Vehicle God Mode",
    Description = "Blocks DamageVehicle.Damage for your current car.",
    Icon = "Lucide:shield",
    Flag = "vehiclegod",
    Default = false,
    Callback = function(state)
        State.vehicleGod = state
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

-- Infinite fuel loop
RunService.Heartbeat:Connect(function()
    if not State.infFuel then return end
    local v = getVehicle()
    local gas = v and v:FindFirstChild("gasLevel")
    if gas and gas:IsA("NumberValue") and gas.Value < Config.MAX_GAS then
        gas.Value = Config.MAX_GAS
    end
end)

-- Car fly loop
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

-- ================== LOOT ==================
local function isLoot(item)
    if not lootFolder or item.Parent ~= lootFolder or not item:IsA("Model") then return false end
    local part = item.PrimaryPart
    return part and part:IsA("BasePart") and part.Parent == item
        and CollectionService:HasTag(item, "Draggable")
        and CollectionService:HasTag(item, "Equippable")
        and not CollectionService:HasTag(item, "BuyableLoot")
end

local function isWhitelistedLoot(item)
    return isLoot(item) and shouldPick(item.Name)
end

local function getWhitelistedLoot()
    local items = {}
    if not lootFolder then return items end
    for _, item in lootFolder:GetChildren() do
        if isWhitelistedLoot(item) then items[#items + 1] = item end
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
    Text = "Loot Aura (Whitelist Only)",
    Description = "Auto-equips whitelisted high-value items within " .. Config.LOOT_RANGE .. " studs.",
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
    local nearest, nearestDist = nil, Config.LOOT_RANGE
    for _, item in getWhitelistedLoot() do
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

-- ================== AUTO PICKUP MONEY ==================
LootSection:AddToggle({
    Text = "Auto Pickup Money",
    Description = "Auto-collects cash drops within " .. Config.CASH_RANGE .. " studs.",
    Icon = "Lucide:dollar-sign",
    Flag = "cashaura",
    Default = false,
    Callback = function(state)
        State.cashAura = state
        if not state then table.clear(cashCooldowns) end
    end,
})

-- Small per-drop cooldown so we don't spam Collect on the same cash
local cashCooldowns = {}
local CASH_RETRY_COOLDOWN = 0.75

RunService.Heartbeat:Connect(function()
    if not State.cashAura or not flow or not flow.Cash then return end
    if type(flow.Cash.Collect) ~= "function" then return end

    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum or hum.Health <= 0 then return end

    local now = os.clock()

    for _, cash in CollectionService:GetTagged("Cash") do
        if cash:IsDescendantOf(workspace) then
            local holder = cash.Parent
            local sensor = holder and holder:FindFirstChild("TouchSensor", true)
            if sensor and sensor:IsA("BasePart") then
                local d = (sensor.Position - root.Position).Magnitude
                local last = cashCooldowns[cash] or 0
                if d <= Config.CASH_RANGE and now - last >= CASH_RETRY_COOLDOWN then
                    cashCooldowns[cash] = now
                    pcall(flow.Cash.Collect, cash)
                end
            end
        end
    end

    -- Prune stale entries so the table doesn't grow forever
    if #CollectionService:GetTagged("Cash") < 5 then
        for k in pairs(cashCooldowns) do
            if not k.Parent then cashCooldowns[k] = nil end
        end
    end
end)

LootSection:AddButton({
    Text = "Pick All (Whitelist Only)",
    Description = "Teleports to every whitelisted item and equips it.",
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
            for _, item in getWhitelistedLoot() do
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
            VindUI:Notify({ Title = "Loot", Text = "Picked " .. brought .. " items.", Type = "success" })
        end)
    end,
})

LootSection:AddButton({
    Text = "Drop All (Keep Mace/Crowbar/Large Backpack)",
    Description = "Drops every droppable tool except Mace, Crowbar, and Large Backpack.",
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
                        if not shouldKeepOnDrop(tool.Name) then
                            pcall(flow.Loot.LootUnequip, tool, tool:HasTag("RemoteOnly"))
                            dropped += 1
                            task.wait(0.05)
                        end
                    end
                end
            end
            busy = false
            VindUI:Notify({ Title = "Loot", Text = "Dropped " .. dropped .. " items.", Type = "success" })
        end)
    end,
})

-- ================== ESP ==================
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

local espVisuals = { Items = {} }

local function newVisual()
    return { Text = newDraw("Text"), Box = newDraw("Square"), Tracer = newDraw("Line") }
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

local function updateItemVisual(target, vis, camera, origin)
    if not isWhitelistedLoot(target) then hideVisual(vis); return end
    local part = target.PrimaryPart
    if not part or not part.Parent then hideVisual(vis); return end
    local dist = (part.Position - origin).Magnitude
    if dist > 3000 then hideVisual(vis); return end
    local point, onScreen = camera:WorldToViewportPoint(part.Position)
    if point.Z <= 0 or not onScreen then hideVisual(vis); return end
    local color = Color3.fromRGB(255, 210, 90)
    local label = string.format("%s | %dm", target.Name, math.round(dist))
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
    if not State.espItems then
        for _, vis in espVisuals.Items do hideVisual(vis) end
        return
    end
    local origin = getRoot() and getRoot().Position or Camera.CFrame.Position
    local active = {}
    for _, item in getWhitelistedLoot() do
        active[item] = true
        local vis = espVisuals.Items[item]
        if not vis then vis = newVisual(); espVisuals.Items[item] = vis end
        updateItemVisual(item, vis, Camera, origin)
    end
    for tgt, vis in espVisuals.Items do
        if not active[tgt] then removeVisual(vis); espVisuals.Items[tgt] = nil end
    end
end
pcall(function() RunService:UnbindFromRenderStep(espRenderName) end)
RunService:BindToRenderStep(espRenderName, Enum.RenderPriority.Camera.Value + 10, updateESP)

local ESPMain = ESPTab:AddCollapsibleSection({
    Title = "ESP", Icon = "Lucide:eye", Collapsed = false,
})
ESPMain:AddToggle({
    Text = "ESP Enabled (Whitelisted Items Only)", Icon = "Lucide:eye", Flag = "esp_enabled", Default = false,
    Callback = function(state)
        State.espEnabled = state
        if not state then
            clearVisuals(espVisuals.Items)
        end
    end,
})

-- ================== GET 5 STARS ==================
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

-- ================== CLEANUP / RESPAWN ==================
LocalPlayer.CharacterAdded:Connect(function()
    table.clear(lastHit)
    carFlyAnchor = nil
    State.carFly = false
    if State.godMode then
        task.wait(0.5)
        applyGodMode()
    end
    if State.thirdPerson then
        task.wait(0.3)
        LocalPlayer.CameraMode = Enum.CameraMode.Classic
        LocalPlayer.CameraMinZoomDistance = 5
        LocalPlayer.CameraMaxZoomDistance = 25
        UserInputService.MouseIconEnabled = true
        Camera.CameraType = Enum.CameraType.Custom
        local h = getHumanoid()
        if h then Camera.CameraSubject = h end
    end
end)

LocalPlayer.CameraMode = Enum.CameraMode.Classic
LocalPlayer.CameraMinZoomDistance = 0
LocalPlayer.CameraMaxZoomDistance = 100
local ch = getHumanoid()
if ch then Camera.CameraSubject = ch end