--// ============================================================
--// RUNAWAYS LOADER
--// First-run UI when no config exists. Skips straight to load
--// when getgenv().Config or the config file is present.
--//
--// Runtime override (skips UI):
--//   getgenv().Config = { Variant = "MoneyFarm" }
--//   loadstring(game:HttpGet(".../Loader.lua"))()
--// ============================================================

local HttpService = game:GetService("HttpService")

local CONFIG_FOLDER = "RUNAWAYS"
local CONFIG_PATH   = CONFIG_FOLDER .. "/config.json"
local REPO_DEFAULT  = "https://raw.githubusercontent.com/keysystem23-rgb/runaway-script/main/"

--// Variants available from the repo
--//   Available : false -> button disabled, cannot be loaded
--//   InDev     : true  -> shows "In Development" badge; still loadable,
--//                        but confirm dialog adds an extra warning
local VARIANTS = {
    {
        Name        = "Main",
        File        = "Runaway.lua",
        Description = "Full script: combat, movement, ESP, loot, weapon, automation.",
        Available   = true,
        InDev       = false,
    },
    {
        Name        = "MoneyFarm",
        File        = "MoneyFarm.lua",
        Description = "Loot-focused farming build with fuzzy whitelist.",
        Available   = true,
        InDev       = false,
    },
    {
        Name        = "Testing-Runaways",
        File        = "testing-Runaways.lua",
        Description = "Test build of Runaway (in progress).",
        Available   = true,
        InDev       = true,
    },
    {
        Name        = "Testing-MoneyFarm",
        File        = "testing-MoneyFarm.lua",
        Description = "Test build of MoneyFarm (in progress).",
        Available   = true,
        InDev       = true,
    },
}

local DEFAULT_CONFIG = {
    Variant        = "Main",
    CacheBust      = true,
    CustomRepo     = "",
    ShowUIOnStart  = false,
}

local function getVariantByName(name)
    for _, v in ipairs(VARIANTS) do
        if v.Name == name then return v end
    end
end

local function getVariantLabel(variant)
    if not variant.Available then
        return variant.Name .. "  (Unavailable)"
    end
    if variant.InDev then
        return variant.Name .. "  (In Development)"
    end
    return variant.Name
end

--// ---------- File helpers ----------
local function fileExists(path)
    if type(isfile) ~= "function" then return false end
    local ok, exists = pcall(isfile, path)
    return ok and exists
end

local function readConfigFile()
    if not fileExists(CONFIG_PATH) then return nil end
    if type(readfile) ~= "function" then return nil end
    local ok, content = pcall(readfile, CONFIG_PATH)
    if not ok or type(content) ~= "string" then return nil end
    local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if decodeOk and type(decoded) == "table" then return decoded end
    return nil
end

local function writeConfigFile(config)
    if type(makefolder) == "function" and type(isfolder) == "function" then
        if not isfolder(CONFIG_FOLDER) then pcall(makefolder, CONFIG_FOLDER) end
    end
    if type(writefile) ~= "function" then return false end
    local encodeOk, encoded = pcall(function() return HttpService:JSONEncode(config) end)
    if not encodeOk then return false end
    return pcall(writefile, CONFIG_PATH, encoded)
end

local function buildUrl(variant, config)
    local repo = config.CustomRepo
    if not repo or repo == "" then repo = REPO_DEFAULT end
    if repo:sub(-1) ~= "/" then repo = repo .. "/" end
    local url = repo .. variant.File
    if config.CacheBust then
        url = url .. "?cb=" .. tostring(os.time())
    end
    return url
end

--// ---------- Config resolution ----------
if type(getgenv) ~= "function" then getgenv = function() return _G end end

getgenv().Config = type(getgenv().Config) == "table" and getgenv().Config or {}
local runtimeConfig = getgenv().Config
local fileConfig    = readConfigFile()

local hasRuntimeConfig = next(runtimeConfig) ~= nil
local hasFileConfig    = fileConfig ~= nil

-- Merge: defaults <- file <- runtime (runtime wins)
local Config = {}
for k, v in pairs(DEFAULT_CONFIG) do Config[k] = v end
if fileConfig then
    for k, v in pairs(fileConfig) do Config[k] = v end
end
for k, v in pairs(runtimeConfig) do Config[k] = v end

-- Mirror back into getgenv() so child scripts can read it
for k, v in pairs(Config) do getgenv().Config[k] = v end

--// ---------- Load function ----------
local function loadVariant(variant, cfg)
    if not variant.Available then
        warn("[RUNAWAYS Loader] Variant " .. variant.Name .. " is not available.")
        return false, "Variant unavailable"
    end

    local url = buildUrl(variant, cfg)
    print("[RUNAWAYS Loader] Loading " .. variant.Name .. " -> " .. url)
    local ok, err = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if not ok then
        warn("[RUNAWAYS Loader] Failed: " .. tostring(err))
    end
    return ok, err
end

--// ---------- Skip-UI fast path ----------
local shouldSkipUI = (hasRuntimeConfig or hasFileConfig) and not Config.ShowUIOnStart

if shouldSkipUI then
    local variant = getVariantByName(Config.Variant) or VARIANTS[1]

    if not variant.Available then
        warn("[RUNAWAYS Loader] Saved variant \"" .. variant.Name ..
            "\" is unavailable. Falling back to Main.")
        variant = getVariantByName("Main") or VARIANTS[1]
        Config.Variant = variant.Name
    end

    print("[RUNAWAYS Loader] Existing config found (variant=" .. variant.Name .. "), loading directly.")
    loadVariant(variant, Config)
    return
end

--// ============================================================
--// FIRST-RUN UI
--// ============================================================
local VindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Skinny-yz/vindUI-Test/main/full.luau"
))()
VindUI:SetTheme("Dark")
VindUI:PreloadIcons({ "Lucide", "Material", "Phosphor", "SF" })
VindUI:SetScaleRange(0.75, 1.35)

local Window = VindUI:CreateWindow({
    Title = "RUNAWAYS",
    Subtitle = "Loader v" .. tostring(VindUI.Version),
    Icon = "Lucide:download",
    Size = UDim2.fromOffset(620, 520),
    MinSize = Vector2.new(500, 420),
    Draggable = true,
    Resizable = true,
    UseBlur = true,
    DefaultTab = "Config",
    TabWidth = 145,
    TabScrollbar = true,
    UserInfo = { Enabled = true, Avatar = "player", NameMode = "display" },
})

VindUI:Notify({
    Title = "First Run",
    Text = "No config found. Configure the loader, then pick a variant.",
    Type = "info",
    Duration = 5,
})

local MainGroup = Window:AddTabGroup({ Name = "LOADER" })
local ConfigTab = MainGroup:AddTab({ Name = "Config", Icon = "Lucide:settings" })
local AboutTab  = MainGroup:AddTab({ Name = "About",  Icon = "Lucide:info" })

--// ---------- Header ----------
ConfigTab:AddParagraph({
    Title = "Configure your loader",
    Icon = "Lucide:info",
    Text = "Pick a variant to load. A confirmation will appear before the script runs — you can cancel if you're not sure.\n\n" ..
        "The config is saved to \"" .. CONFIG_PATH .. "\".\n\n" ..
        "You can also skip this UI by setting getgenv().Config before running the loader.",
})

--// ---------- Variant buttons ----------
local VariantSection = ConfigTab:AddCollapsibleSection({
    Title = "Variant", Icon = "Lucide:layers", Collapsed = false,
})

local function showVariantWarning(variant, onConfirm)
    local extraWarning = ""
    if variant.InDev then
        extraWarning = "\n\n⚠  This variant is marked IN DEVELOPMENT.\n" ..
            "Expect bugs, incomplete features, and possible crashes."
    end

    local warningText = string.format(
        "Loading will point to \"%s\".%s\n\n" ..
        "Are you sure you want to do this?\n\n" ..
        "─────────────────────────────\n" ..
        "You can edit the config in:\n" ..
        "   %s\n\n" ..
        "Or via runtime override:\n" ..
        "   getgenv().Config = { Variant = \"%s\" }\n" ..
        "   getgenv().Config = { CustomRepo = \"https://...\" }",
        variant.Name, extraWarning, CONFIG_PATH, variant.Name
    )

    VindUI:Confirm({
        Title = "⚠  Change Load Target?",
        Text = warningText,
        Window = Window,
        ConfirmText = "Yes",
        CancelText = "No",
        Danger = true,
        Callback = function(confirmed)
            if confirmed then onConfirm() end
        end,
    })
end

for _, variant in ipairs(VARIANTS) do
    local icon = "Lucide:play"
    local description = variant.Description

    if not variant.Available then
        icon = "Lucide:lock"
        description = "Currently unavailable. " .. (variant.Description or "")
    elseif variant.InDev then
        icon = "Lucide:flask-conical"
        description = "[In Development] " .. (variant.Description or "")
    end

    VariantSection:AddButton({
        Text = getVariantLabel(variant),
        Description = description,
        Icon = icon,
        Callback = function()
            if not variant.Available then
                VindUI:Notify({
                    Title = "Unavailable",
                    Text = "\"" .. variant.Name .. "\" is not available right now.",
                    Type = "warning",
                    Duration = 3,
                })
                return
            end

            showVariantWarning(variant, function()
                Config.Variant = variant.Name
                Config.ShowUIOnStart = false
                writeConfigFile(Config)
                for k, v in pairs(Config) do getgenv().Config[k] = v end

                VindUI:Notify({
                    Title = "Loading",
                    Text = variant.Name .. "...",
                    Type = variant.InDev and "warning" or "success",
                    Duration = 2,
                })
                task.wait(0.3)
                pcall(function() VindUI:Unload() end)
                loadVariant(variant, Config)
            end)
        end,
    })
end

--// ---------- Settings ----------
local SettingsSection = ConfigTab:AddCollapsibleSection({
    Title = "Settings", Icon = "Lucide:wrench", Collapsed = false,
})

SettingsSection:AddToggle({
    Text = "Cache Bust",
    Description = "Appends ?cb=<time> to defeat GitHub CDN caching. Recommended during updates.",
    Icon = "Lucide:refresh-cw",
    Flag = "cachebust",
    Default = Config.CacheBust == true,
    Callback = function(state)
        Config.CacheBust = state
        writeConfigFile(Config)
    end,
})

SettingsSection:AddToggle({
    Text = "Always Show This UI",
    Description = "Show the loader every run instead of loading the saved variant immediately.",
    Icon = "Lucide:eye",
    Flag = "showui",
    Default = Config.ShowUIOnStart == true,
    Callback = function(state)
        Config.ShowUIOnStart = state
        writeConfigFile(Config)
    end,
})

SettingsSection:AddTextbox({
    Text = "Custom Repo URL",
    Description = "Leave empty to use the default repo.",
    Icon = "Lucide:link",
    Placeholder = REPO_DEFAULT,
    Default = Config.CustomRepo or "",
    Callback = function(text)
        Config.CustomRepo = text or ""
        writeConfigFile(Config)
    end,
})

--// ---------- Actions ----------
local FooterSection = ConfigTab:AddCollapsibleSection({
    Title = "Actions", Icon = "Lucide:settings-2", Collapsed = false,
})

FooterSection:AddButton({
    Text = "Load Current Variant",
    Description = "Loads whichever variant is currently saved in config.",
    Icon = "Lucide:play",
    Callback = function()
        local variant = getVariantByName(Config.Variant) or VARIANTS[1]

        if not variant.Available then
            VindUI:Notify({
                Title = "Unavailable",
                Text = "\"" .. variant.Name .. "\" is not available. Pick another variant.",
                Type = "warning",
                Duration = 3,
            })
            return
        end

        showVariantWarning(variant, function()
            writeConfigFile(Config)
            for k, v in pairs(Config) do getgenv().Config[k] = v end
            task.wait(0.3)
            pcall(function() VindUI:Unload() end)
            loadVariant(variant, Config)
        end)
    end,
})

FooterSection:AddButton({
    Text = "Save Config Only (No Load)",
    Description = "Writes current settings to disk without loading anything.",
    Icon = "Lucide:save",
    Callback = function()
        writeConfigFile(Config)
        VindUI:Notify({
            Title = "Saved",
            Text = "Config written to " .. CONFIG_PATH,
            Type = "success",
            Duration = 3,
        })
    end,
})

FooterSection:AddButton({
    Text = "Reset Config to Defaults",
    Description = "Deletes the saved config file. UI will show again next run.",
    Icon = "Lucide:rotate-ccw",
    Callback = function()
        VindUI:Confirm({
            Title = "Reset config?",
            Text = "This deletes the saved config file. Next launch will show this UI again.",
            Danger = true,
            Window = Window,
            ConfirmText = "Reset",
            CancelText = "Cancel",
            Callback = function(confirmed)
                if not confirmed then return end

                if type(delfile) == "function" and fileExists(CONFIG_PATH) then
                    pcall(delfile, CONFIG_PATH)
                end

                local fresh = {}
                for k, v in pairs(DEFAULT_CONFIG) do fresh[k] = v end
                Config = fresh
                for k, v in pairs(fresh) do getgenv().Config[k] = v end

                VindUI:Notify({
                    Title = "Reset",
                    Text = "Config reset to defaults.",
                    Type = "warning",
                    Duration = 3,
                })
            end,
        })
    end,
})

--// ---------- About tab ----------
AboutTab:AddParagraph({
    Title = "Config Path",
    Icon = "Lucide:folder",
    Text = CONFIG_PATH,
})

AboutTab:AddParagraph({
    Title = "Runtime Override",
    Icon = "Lucide:code",
    Text = "Set getgenv().Config before running the loader to skip this UI:\n\n" ..
        "getgenv().Config = { Variant = \"MoneyFarm\", CacheBust = true }\n" ..
        "loadstring(game:HttpGet(\".../Loader.lua\"))()",
})

AboutTab:AddParagraph({
    Title = "Available Variants",
    Icon = "Lucide:layers",
    Text = (function()
        local lines = {}
        for _, v in ipairs(VARIANTS) do
            local status
            if not v.Available then status = "  ✗ unavailable"
            elseif v.InDev then   status = "  ⚠ in development"
            else                  status = "  ✓ stable"
            end
            lines[#lines + 1] = v.Name .. status
        end
        return table.concat(lines, "\n")
    end)(),
})

AboutTab:AddParagraph({
    Title = "Default Repo",
    Icon = "Lucide:link",
    Text = REPO_DEFAULT,
})