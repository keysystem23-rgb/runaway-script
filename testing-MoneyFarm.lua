--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

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
    Title = "RUNAWAYS TEST",
    Subtitle = "Money farm test build",
    Icon = "Lucide:flask-conical",
    Size = UDim2.fromOffset(600, 420),
    MinSize = Vector2.new(480, 340),
    Draggable = true,
    Resizable = true,
    UseBlur = true,
    DefaultTab = "Main",
    TabWidth = 145,
    TabScrollbar = true,
    UserInfo = { Enabled = true, Avatar = "player", NameMode = "display" },
})

VindUI:Notify({
    Title = "RUNAWAYS TEST",
    Text = "Test build loaded.",
    Type = "success",
    Duration = 3,
})

--// Modules
local okFlow, flow = pcall(function()
    return require(ReplicatedStorage:WaitForChild("FlowClient"))
end)
local lootFolder = workspace:FindFirstChild("Loot")

--// Config
local Config = {
    MAX_GAS = 100,
    LOOT_RANGE = 50,
    GATHER_WAIT = 0.18,
    PROMPT_RANGE = 15,
    PROMPT_COOLDOWN = 0.15,
}

--// State
local State = {
    godMode = false,
    infFuel = false,
    bringAll = false,
    autoSell = false,
}
local busy = false

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
    local folder = workspace:FindFirstChild("Vehicles")
    if not folder then return nil end
    maxDist = maxDist or 2000
    local nearest, nearestDist = nil, maxDist
    for _, v in folder:GetChildren() do
        if v:IsA("Model") and v:FindFirstChild("VehicleProperty") then
            local d = (v:GetPivot().Position - root.Position).Magnitude
            if d < nearestDist then nearest = v; nearestDist = d end
        end
    end
    return nearest
end

--// ================== GOD MODE ==================
local originalTakeDamage = flow and flow.PlayerDamage and flow.PlayerDamage.TakeDamage
local originalAbandon = flow and flow.Passout and flow.Passout.Abandon
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

-- Keep HP topped up
RunService.Heartbeat:Connect(function()
    if not State.godMode then return end
    local hum = getHumanoid()
    if hum and hum.Health < hum.MaxHealth then
        hum.Health = hum.MaxHealth
    end
end)

--// ================== INFINITE FUEL ==================
RunService.Heartbeat:Connect(function()
    if not State.infFuel then return end
    local v = getVehicle()
    local gas = v and v:FindFirstChild("gasLevel")
    if gas and gas:IsA("NumberValue") and gas.Value < Config.MAX_GAS then
        gas.Value = Config.MAX_GAS
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

local function getAllLoot()
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

--// ================== BRING ALL (hybrid) ==================
local PULL_TIMEOUT_NEAR = 1.0    -- timeout when already near the item
local PULL_TIMEOUT_FAR = 0.4     -- short timeout for the "pull from afar" attempt
local NEAR_DISTANCE = 12         -- studs; under this, always try pull directly

local function isNetworkOwner(part)
    if type(isnetworkowner) ~= "function" then return true end
    local ok, owns = pcall(isnetworkowner, part)
    return ok and owns
end

local function requestOwnership(part, timeout)
    if not flow.Loot then return false end
    timeout = timeout or PULL_TIMEOUT_NEAR

    if type(flow.Loot.OwnNetworkRequestAsync) == "function" then
        local ok, granted = pcall(flow.Loot.OwnNetworkRequestAsync, part, true)
        if ok and granted then return true end
    end
    if type(flow.Loot.OwnNetworkRequest) == "function" then
        pcall(flow.Loot.OwnNetworkRequest, part, true)
    end

    local expires = os.clock() + timeout
    repeat
        RunService.Heartbeat:Wait()
        if isNetworkOwner(part) then return true end
    until os.clock() >= expires
    return false
end

local function releaseOwnership(part)
    if flow.Loot and type(flow.Loot.OwnNetworkRequest) == "function" then
        pcall(flow.Loot.OwnNetworkRequest, part, nil)
    end
end

local function getGridCFrame(rootCFrame, index)
    local column = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    return rootCFrame * CFrame.new((column - 1.5) * 4, 2, -7 - row * 4)
end

local function unweld(item, part)
    if CollectionService:HasTag(item, "Attachable") then
        if type(flow.Loot.WeldDetach) == "function" then
            pcall(flow.Loot.WeldDetach, part)
        end
        local weld = part:FindFirstChild("AttachableWeld")
        if weld then pcall(function() weld:Destroy() end) end
        task.wait(0.05)
    end
end

-- Returns: success, reason, method ("pull" or "tp")
local function tryEquipItem(item, character, root, baseCFrame, index)
    if not item.Parent then return false, "Item removed", nil end
    local part = item.PrimaryPart
    if not part or not part.Parent then return false, "No PrimaryPart", nil end

    unweld(item, part)

    local distance = (part.Position - root.Position).Magnitude

    -- Phase 1: try pulling from current position (only if close enough to be plausible)
    if distance <= NEAR_DISTANCE then
        if requestOwnership(part, PULL_TIMEOUT_NEAR) then
            local target = getGridCFrame(baseCFrame, index)
            pcall(function()
                item:PivotTo(target * part.CFrame:Inverse() * item:GetPivot())
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end)
            RunService.Heartbeat:Wait()
            RunService.Heartbeat:Wait()
            local ok, result = pcall(flow.Loot.LootEquip, part)
            releaseOwnership(part)
            if ok and (result == "Success" or result == "AlreadyOwned") then
                return true, nil, "pull"
            end
            return false, "LootEquip: " .. tostring(result), nil
        end
    end

    -- Phase 2: teleport to the item (fallback)
    character:PivotTo(getPickupCFrame(root, part))
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    task.wait(0.15)

    if not item.Parent or not part.Parent then
        return false, "Item removed during TP", nil
    end

    unweld(item, part)

    local owned = requestOwnership(part, PULL_TIMEOUT_NEAR)
    if not owned then
        return false, "Ownership timeout", nil
    end

    local ok, result = pcall(flow.Loot.LootEquip, part)
    releaseOwnership(part)

    if ok and (result == "Success" or result == "AlreadyOwned") then
        return true, nil, "tp"
    end
    return false, "LootEquip: " .. tostring(result), nil
end

local function bringAllLoot()
    if busy then return end
    if not flow or not flow.Loot or type(flow.Loot.LootEquip) ~= "function" then
        VindUI:Notify({ Title = "Bring All", Text = "LootEquip unavailable.", Type = "error" })
        return
    end

    busy = true
    task.spawn(function()
        local c = getChar()
        local hum = getHumanoid()
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if not c or not root or not hum or hum.Health <= 0 then
            busy = false
            return
        end

        local savedCFrame = c:GetPivot()
        local items = getAllLoot()

        local broughtPull, broughtTp, failed = 0, 0, 0
        local failureReasons = {}

        VindUI:Notify({
            Title = "Bring All",
            Text = "Processing " .. #items .. " items...",
            Type = "info",
            Duration = 2,
        })

        for i, item in ipairs(items) do
            -- Reset to saved position before each item so the grid stays consistent
            if c.Parent and root.Parent then
                c:PivotTo(savedCFrame)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end

            local ok, reason, method = tryEquipItem(item, c, root, savedCFrame, broughtPull + broughtTp + 1)
            if ok then
                if method == "tp" then broughtTp += 1 else broughtPull += 1 end
            else
                failed += 1
                reason = reason or "Unknown"
                failureReasons[reason] = (failureReasons[reason] or 0) + 1
                warn(string.format("[BringAll] Failed %q: %s", item.Name, reason))
            end
            task.wait(0.04)
        end

        if c.Parent then c:PivotTo(savedCFrame) end
        busy = false

        local summaryParts = {}
        for reason, count in pairs(failureReasons) do
            summaryParts[#summaryParts + 1] = reason .. " x" .. count
        end
        table.sort(summaryParts)

        local brought = broughtPull + broughtTp
        local summaryText = string.format(
            "Brought %d (pull %d, tp %d)",
            brought, broughtPull, broughtTp
        )
        if failed > 0 then
            summaryText = summaryText .. " | Failed " .. failed
            if #summaryParts > 0 then
                summaryText = summaryText .. "\n" .. table.concat(summaryParts, ", ")
            end
        end

        VindUI:Notify({
            Title = "Bring All",
            Text = summaryText,
            Type = brought > 0 and "success" or "warning",
            Duration = 6,
        })
    end)
end

--// ================== AUTO SELL ==================
local promptCooldowns = {}

local function firePrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    if not prompt.Enabled then return end
    local now = os.clock()
    if now - (promptCooldowns[prompt] or 0) < Config.PROMPT_COOLDOWN then return end
    promptCooldowns[prompt] = now

    if type(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt)
    else
        pcall(function()
            local dur = prompt.HoldDuration
            prompt.HoldDuration = 0
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
            prompt.HoldDuration = dur
        end)
    end
end

-- Finds prompts specifically on the PawnShop counter
local function getSellPrompts()
    local prompts = {}
    for _, counter in ipairs(CollectionService:GetTagged("PawnCounter")) do
        if counter:IsDescendantOf(workspace) then
            for _, d in ipairs(counter:GetDescendants()) do
                if d:IsA("ProximityPrompt") and d.Enabled then
                    prompts[#prompts + 1] = d
                end
            end
        end
    end
    return prompts
end

local function runAutoSell()
    if not State.autoSell then return end
    local root = getRoot()
    if not root then return end

    for _, prompt in getSellPrompts() do
        local part = prompt.Parent
        local pos
        if part:IsA("BasePart") then
            pos = part.Position
        elseif part:IsA("Attachment") then
            pos = part.WorldPosition
        end
        if pos and (pos - root.Position).Magnitude <= Config.PROMPT_RANGE then
            firePrompt(prompt)
        end
    end
end

--// ================== UI ==================
local MainGroup = Window:AddTabGroup({ Name = "RUNAWAYS TEST" })
local MainTab = MainGroup:AddTab({ Name = "Main", Icon = "Lucide:flask-conical" })

-- Vehicle
local VehicleSection = MainTab:AddCollapsibleSection({
    Title = "Vehicle", Icon = "Lucide:car", Collapsed = false,
})

VehicleSection:AddButton({
    Text = "Teleport to Car",
    Description = "Jumps to your current car, or the nearest one within 2000 studs.",
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
        root.CFrame = v:GetPivot() * CFrame.new(0, 5, 0)
        VindUI:Notify({ Title = "Vehicle", Text = "Teleported to " .. v.Name .. ".", Type = "success", Duration = 2 })
    end,
})

VehicleSection:AddToggle({
    Text = "Infinite Fuel",
    Description = "Keeps your current vehicle's gasLevel at maximum.",
    Icon = "Lucide:fuel",
    Flag = "inffuel",
    Default = false,
    Callback = function(state) State.infFuel = state end,
})

-- Player
local PlayerSection = MainTab:AddCollapsibleSection({
    Title = "Player", Icon = "Lucide:user-cog", Collapsed = false,
})

PlayerSection:AddToggle({
    Text = "God Mode",
    Description = "Blocks damage + passout, keeps HP at max.",
    Icon = "Lucide:heart-pulse",
    Flag = "godmode",
    Default = false,
    Callback = function(state)
        State.godMode = state
        if state then applyGodMode() else restoreGodMode() end
    end,
})

-- Loot
local LootSection = MainTab:AddCollapsibleSection({
    Title = "Loot", Icon = "Lucide:package", Collapsed = false,
})

LootSection:AddButton({
    Text = "Bring All Loot",
    Description = "Pulls every item in workspace.Loot to you and equips it. You stay in place.",
    Icon = "Lucide:package-plus",
    Callback = bringAllLoot,
})

LootSection:AddToggle({
    Text = "Auto Sell (PawnShop)",
    Description = "Fires the pawn counter prompt automatically when in range.",
    Icon = "Lucide:badge-dollar-sign",
    Flag = "autosell",
    Default = false,
    Callback = function(state)
        State.autoSell = state
        if not state then table.clear(promptCooldowns) end
    end,
})

LootSection:AddSlider({
    Text = "Sell Range",
    Icon = "Lucide:radar",
    Flag = "sell_range",
    Min = 5, Max = 50, Default = 15, Increment = 1,
    Callback = function(value) Config.PROMPT_RANGE = tonumber(value) or 15 end,
})

--// ================== MAIN LOOP ==================
RunService.Heartbeat:Connect(function()
    runAutoSell()
end)

-- Respawn handling
LocalPlayer.CharacterAdded:Connect(function()
    if State.godMode then
        task.wait(0.5)
        applyGodMode()
    end
end)

-- Camera default
LocalPlayer.CameraMode = Enum.CameraMode.Classic
LocalPlayer.CameraMinZoomDistance = 0
LocalPlayer.CameraMaxZoomDistance = 100
local ch = getHumanoid()
if ch then Camera.CameraSubject = ch end