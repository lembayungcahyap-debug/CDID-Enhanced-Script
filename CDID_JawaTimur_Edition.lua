--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║        CDID Script - Jawa Timur Edition (Refactored)           ║
    ║        Based on LunraV2 by unkronnn                            ║
    ║        Refactored: East Java Optimization + Discord Webhook    ║
    ║        Version: 1.0.0 - JawaTimur Build                        ║
    ╚══════════════════════════════════════════════════════════════════╝

    STRUKTUR KODE:
    [1] CONFIG          — Semua konstanta & variabel yang bisa dikustomisasi
    [2] SETTINGS MGR    — Load/Save config ke file lokal
    [3] SERVICES        — Cache semua Roblox services
    [4] ANTI-AFK        — Sistem anti-kick idle
    [5] DISCORD WEBHOOK — Smart reporting ke Discord
    [6] FARMING ENGINE  — Logika Jawa Timur, Truck, Side Job
    [7] UNLOCK SHOPS    — Remote opener semua toko/dealer
    [8] UI BUILDER      — Semua elemen MacLib (Menu, Tab, Toggle, dsb)
    [9] INIT            — Startup & background tasks
]]

-- ═══════════════════════════════════════════════════
-- [1] CONFIG — Edit semua nilai di sini
-- ═══════════════════════════════════════════════════

local CONFIG = {
    -- ── Performa ──────────────────────────────────
    CycleDelay       = 0.2,     -- Interval tiap aksi farming (detik)
    TweenSpeed       = 49.5,    -- Kecepatan tween kendaraan
    DelayBeforeRejoin = 0.5,    -- Jeda sebelum teleport rejoin

    -- ── Target Earning ────────────────────────────
    TargetEarning    = 500000000000,  -- Uang target per sesi (0 = tidak ada batas)

    -- ── Discord Webhook ───────────────────────────
    WebhookURL       = "https://discord.com/api/webhooks/1471218410070343772/uxLYmnUbS555ZnDFFjQAS9oHYL-kZvhozKkq4518kw_jZjK5j0vuxiDFIQhagQr0BEz9",
    WebhookMinInterval = 300,   -- Min 5 menit antar pesan (detik)
    WebhookMaxInterval = 600,   -- Max 10 menit antar pesan (detik)

    -- ── Map ───────────────────────────────────────
    TargetMap        = "Jawa Timur",

    -- ── Jawa Timur Waypoints ──────────────────────
    -- Format: {x, y, z, label}
    JawaTimurRoute   = {
        { x = -50889.66, y = 1017.87, z = -86514.80, label = "Delivery Point A" },
        { x = -48200.00, y = 1020.00, z = -84000.00, label = "Checkpoint B"      },
        { x = -51500.00, y = 1015.00, z = -88000.00, label = "Delivery Point C" },
    },

    -- ── UI ───────────────────────────────────────
    ScriptTitle      = "Car Driving Indonesia",
    ScriptSubtitle   = "Jawa Timur Edition",
    Version          = "1.0.0-JT",
}

-- ═══════════════════════════════════════════════════
-- [2] SETTINGS MANAGER
-- ═══════════════════════════════════════════════════

local SettingsManager = {
    Version    = CONFIG.Version,
    BaseFolder = "LunarV2",
    SubFolder  = "settings",
    FileName   = "LunraConfig_JT",
    LastSave   = 0,
    SaveCooldown = 1,
}

getgenv().Settings = {
    OnFarming        = false,
    OnFirstTime      = true,
    PrivateCode      = nil,
    PrivateServer    = nil,
    MaclibVisibility = false,
    WaveText         = false,
    BlipText         = false,
    SpoofedName      = nil,
    SubtitleName     = nil,
    InfiniteJump     = false,
    SelectedJob      = nil,
    StopFarm         = false,
    TruckMethod      = nil,
    UIVisibility     = false,
    CountdownNotif   = false,
    DelayBeforeRejoin = CONFIG.DelayBeforeRejoin,
    SpoofToggle      = false,
    TargetEarning    = CONFIG.TargetEarning,
    WebhookURL       = CONFIG.WebhookURL,
    Version          = CONFIG.Version,
}

getgenv().Temporary = {
    onFindingSnake   = false,
    onFindingAngpao  = false,
    onStory          = false,
}

-- Session tracking
getgenv().SessionData = {
    StartMoney      = 0,
    EarnedThisSession = 0,
    FarmingStartTime  = 0,
    LastWebhookTime   = 0,
}

function SettingsManager:Init()
    self.HttpService = game:GetService("HttpService")
    self.FilePath = table.concat({self.BaseFolder, self.SubFolder, self.FileName}, "\\")
    if not isfolder(self.BaseFolder) then makefolder(self.BaseFolder) end
    if not isfolder(self.BaseFolder.."\\"..self.SubFolder) then
        makefolder(self.BaseFolder.."\\"..self.SubFolder)
    end
    if not self:Load() then self:Save(true) end
end

function SettingsManager:Save(force)
    if not writefile then return false end
    local now = os.time()
    if not force and (now - self.LastSave) < self.SaveCooldown then return false end
    local ok = pcall(function()
        local data = {
            version   = self.Version,
            settings  = getgenv().Settings,
            timestamp = now,
        }
        writefile(self.FilePath, self.HttpService:JSONEncode(data))
        self.LastSave = now
    end)
    return ok
end

function SettingsManager:Load()
    if not (readfile and isfile) then return false end
    local ok, result = pcall(function()
        if isfile(self.FilePath) then
            local decoded = self.HttpService:JSONDecode(readfile(self.FilePath))
            if type(decoded) == "table" and decoded.settings then
                for k, v in pairs(decoded.settings) do
                    if getgenv().Settings[k] ~= nil then
                        getgenv().Settings[k] = v
                    end
                end
                return true
            end
        end
        return false
    end)
    return ok and result
end

SettingsManager:Init()

-- ═══════════════════════════════════════════════════
-- [3] SERVICES CACHE
-- ═══════════════════════════════════════════════════

local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService    = game:GetService("TweenService")
local RunService      = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VIM             = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService      = game:GetService("GuiService")

local LP              = Players.LocalPlayer
local Network         = ReplicatedStorage:WaitForChild("NetworkContainer", 30)
local RemoteEvents    = Network and Network:FindFirstChild("RemoteEvents")
local RemoteFunctions = Network and Network:FindFirstChild("RemoteFunctions")

-- Helper: safe FireServer
local function FireEvent(eventName, ...)
    local ok, err = pcall(function()
        RemoteEvents[eventName]:FireServer(...)
    end)
    if not ok then warn("[FireEvent] "..eventName.." failed: "..tostring(err)) end
end

-- Helper: safe InvokeServer
local function InvokeFunction(funcName, ...)
    local ok, result = pcall(function()
        return RemoteFunctions[funcName]:InvokeServer(...)
    end)
    if ok then return result end
    warn("[InvokeFunction] "..funcName.." failed: "..tostring(result))
    return nil
end

-- Helper: Tween teleport dengan kecepatan CONFIG.TweenSpeed
local function TweenTo(target, cframeTarget, duration)
    duration = duration or (1 / CONFIG.TweenSpeed * 50)
    local ok = pcall(function()
        TweenService:Create(
            target,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            { CFrame = cframeTarget }
        ):Play()
    end)
    return ok
end

-- Dapatkan uang saat ini dari GUI
local function GetCurrentMoney()
    local ok, money = pcall(function()
        local text = LP.PlayerGui.Main.Container.Hub.CashFrame.Frame.TextLabel.Text
        return tonumber(text:gsub("[^%d]", "")) or 0
    end)
    return ok and money or 0
end

-- ═══════════════════════════════════════════════════
-- [4] ANTI-AFK SYSTEM
-- ═══════════════════════════════════════════════════

local AntiAFKConnection = nil

local function StartAntiAFK()
    if AntiAFKConnection then AntiAFKConnection:Disconnect() end
    local keys = { "W", "A", "S", "D" }
    AntiAFKConnection = LP.Idled:Connect(function()
        pcall(function()
            local k = keys[math.random(1, #keys)]
            VIM:SendKeyEvent(true,  k, false, game)
            task.wait(math.random() * 0.2 + 0.1)
            VIM:SendKeyEvent(false, k, false, game)
            VIM:SendMouseMoveEvent(math.random(-50,50), math.random(-50,50), game)
        end)
    end)
    LP.CharacterRemoving:Connect(function()
        if AntiAFKConnection then AntiAFKConnection:Disconnect() end
    end)
    print("[AntiAFK] Active ✓")
end

-- ═══════════════════════════════════════════════════
-- [5] DISCORD WEBHOOK — Smart Reporting
-- ═══════════════════════════════════════════════════

-- Buat progress bar teks ASCII
local function MakeProgressBar(current, target, width)
    width = width or 20
    if target <= 0 then return "[∞ No Limit Set]", 0 end
    local pct = math.min(current / target, 1)
    local filled = math.floor(pct * width)
    local bar = string.rep("█", filled) .. string.rep("░", width - filled)
    return string.format("[%s] %.1f%%", bar, pct * 100), pct * 100
end

local function FormatMoney(n)
    if not n then return "0" end
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

local function SendWebhook(isTargetReached)
    local webhookURL = getgenv().Settings.WebhookURL or ""
    if webhookURL == "" or webhookURL == "YOUR_DISCORD_WEBHOOK_URL_HERE" then
        warn("[Webhook] URL belum diisi di CONFIG.WebhookURL!")
        return
    end
    if not getgenv().Settings.OnFarming and not isTargetReached then return end

    local now = os.time()
    -- Debounce: minimal interval 5 menit kecuali target reached
    if not isTargetReached then
        local minI = CONFIG.WebhookMinInterval
        if (now - getgenv().SessionData.LastWebhookTime) < minI then return end
    end
    getgenv().SessionData.LastWebhookTime = now

    local earned  = GetCurrentMoney() - getgenv().SessionData.StartMoney
    if earned < 0 then earned = 0 end
    getgenv().SessionData.EarnedThisSession = earned

    local target  = getgenv().Settings.TargetEarning or 0
    local bar, pct = MakeProgressBar(earned, target)
    local status  = isTargetReached and "✅ TARGET REACHED" or "🟢 Aktif"
    local elapsed = math.floor((now - getgenv().SessionData.FarmingStartTime) / 60)

    local color   = isTargetReached and 65280 or 3447003 -- hijau / biru

    local embedPayload = {
        embeds = {
            {
                title       = isTargetReached and "✅ TARGET EARNING TERCAPAI!" or "📊 Farming Report — CDID Jawa Timur",
                color       = color,
                description = isTargetReached
                    and string.format("**%s** telah mencapai target earning!", LP.Name)
                    or  string.format("Laporan farming otomatis untuk **%s**", LP.Name),
                fields      = {
                    { name = "👤 Username",           value = LP.Name,                   inline = true  },
                    { name = "🆔 UserID",             value = tostring(LP.UserId),        inline = true  },
                    { name = "🗺️ Map",                value = CONFIG.TargetMap,          inline = true  },
                    { name = "⚡ Status",              value = status,                    inline = true  },
                    { name = "⏱️ Durasi Sesi",        value = elapsed.." menit",         inline = true  },
                    { name = "💰 Uang Saat Ini",      value = "Rp "..FormatMoney(GetCurrentMoney()), inline = true },
                    { name = "📈 Earned Sesi Ini",    value = "Rp "..FormatMoney(earned), inline = true },
                    { name = "🎯 Target",             value = target > 0 and "Rp "..FormatMoney(target) or "Tidak Ada", inline = true },
                    { name = "📊 Progress",           value = "```"..bar.."```",          inline = false },
                },
                footer      = { text = "CDID JawaTimur Edition v"..CONFIG.Version.." | "..os.date("%H:%M:%S") },
            }
        }
    }

    local ok, err = pcall(function()
        -- syn.request / http.request kompatibel
        local fn = (syn and syn.request) or (http and http.request) or request
        fn({
            Url     = webhookURL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(embedPayload),
        })
    end)
    if not ok then warn("[Webhook] Gagal kirim:", err) end
end

-- Timer webhook background
task.spawn(function()
    while task.wait(60) do
        if getgenv().Settings.OnFarming then
            -- Acak interval 5-10 menit
            local nextSend = math.random(CONFIG.WebhookMinInterval, CONFIG.WebhookMaxInterval)
            local elapsed  = os.time() - getgenv().SessionData.LastWebhookTime
            if elapsed >= nextSend then
                SendWebhook(false)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════
-- [6] FARMING ENGINE
-- ═══════════════════════════════════════════════════

-- ── 6a. Stop & Cleanup sesi farming ──────────────

local function StopAllFarming(notify)
    getgenv().Settings.OnFarming = false
    getgenv().Settings.StopFarm  = true
    SettingsManager:Save()

    -- Matikan mesin kendaraan
    pcall(function()
        local vehicles = workspace:FindFirstChild("Vehicles")
        if vehicles then
            local car = vehicles:FindFirstChild(LP.Name.."sCar")
            if car then
                local engine = car:FindFirstChild("Engine") or car:FindFirstChildWhichIsA("Script")
                -- Fire remote untuk matikan mesin jika ada
                pcall(function() FireEvent("Engine", "Off") end)
            end
        end
    end)

    if notify then
        SendWebhook(true) -- Kirim notif target reached
    end
    print("[Farming] Semua farming dihentikan.")
end

-- ── 6b. Cek apakah target earning tercapai ───────

local function CheckTargetEarning()
    local target = getgenv().Settings.TargetEarning or 0
    if target <= 0 then return false end
    local earned = GetCurrentMoney() - getgenv().SessionData.StartMoney
    if earned >= target then
        StopAllFarming(true)
        return true
    end
    return false
end

-- ── 6c. Safe Teleport kendaraan ──────────────────

local function SafeTeleportCar(car, targetCFrame)
    pcall(function()
        RunService:Set3dRenderingEnabled(false)
        task.wait(0.3)
        car:PivotTo(targetCFrame)
        task.wait(0.2)
        RunService:Set3dRenderingEnabled(true)
    end)
end

-- ── 6d. Jawa Timur Truck Farm ────────────────────
--
--  Rute optimal Jawa Timur:
--  Starter → Ambil Job Truck → Temukan waypoint → Spawn Truck →
--  Duduk → Countdown → Teleport ke Delivery Point Jawa Timur → Rejoin
--

local FarmingStatus -- forward-declare, akan diisi dari UI

local function TruckFarmJawaTimur()
    while task.wait(CONFIG.CycleDelay) do
        if not getgenv().Settings.OnFarming then break end
        if CheckTargetEarning() then break end

        pcall(function()
            -- 1. Ambil job Truck
            FireEvent("Job", "Truck")
            FarmingStatus:UpdateBody("Mengambil job Truck Jawa Timur...")
            task.wait(0.8)

            -- 2. Pastikan waypoint valid
            local waypointFolder = workspace.Etc:FindFirstChild("Waypoint")
            local waypoint = waypointFolder and waypointFolder:FindFirstChild("Waypoint")
            if not waypoint then
                for _ = 1, 10 do
                    FireEvent("Job", "Truck")
                    task.wait(0.6)
                    waypoint = waypointFolder and waypointFolder:FindFirstChild("Waypoint")
                    if waypoint then break end
                end
            end
            if not waypoint then
                warn("[TruckFarm] Waypoint tidak ditemukan, skip cycle.")
                return
            end

            -- 3. Teleport ke area spawn truck Jawa Timur
            --    Koordinat PT. Shad area (disesuaikan untuk JawaTimur)
            local spawnCF = CFrame.new(-21782.94, 1042.03, -26786.96)
            TweenTo(LP.Character.HumanoidRootPart, spawnCF, 1.0)
            FarmingStatus:UpdateBody("Menuju area spawn truck...")
            task.wait(1.2)

            -- 4. Pastikan waypoint adalah tujuan Jawa Timur
            repeat
                TweenTo(LP.Character.HumanoidRootPart, spawnCF, 0.5)
                LP.Character.HumanoidRootPart.Anchored = true
                local wLabel = waypoint:FindFirstChild("BillboardGui") and
                               waypoint.BillboardGui:FindFirstChild("TextLabel")
                local labelText = wLabel and wLabel.Text or ""

                if not labelText:find("Timur") and not labelText:find("Surabaya") and
                   not labelText:find("Malang") and not labelText:find("Jember") then
                    FireEvent("Job", "Truck")
                    pcall(fireproximityprompt, workspace.Etc.Job.Truck.Starter.Prompt)
                end
                LP.Character.HumanoidRootPart.Anchored = false
                task.wait(0.8)
            until (wLabel and (wLabel.Text:find("Timur") or wLabel.Text:find("Surabaya")
                   or wLabel.Text:find("Malang") or wLabel.Text:find("Jember")))

            LP.Character.HumanoidRootPart.Anchored = false
            FarmingStatus:UpdateBody("Waypoint Jawa Timur ditemukan! Spawn truck...")

            -- 5. Spawn Truck
            VIM:SendKeyEvent(true,  "F", false, game)
            task.wait(0.3)
            VIM:SendKeyEvent(false, "F", false, game)
            task.wait(4)

            local function GetCar()
                local v = workspace:FindFirstChild("Vehicles")
                return v and v:FindFirstChild(LP.Name.."sCar")
            end
            local car
            for _ = 1, 15 do
                car = GetCar()
                if car then break end
                VIM:SendKeyEvent(true,  "F", false, game)
                VIM:SendKeyEvent(false, "F", false, game)
                task.wait(0.8)
            end
            if not car then
                warn("[TruckFarm] Gagal spawn kendaraan.")
                return
            end

            -- 6. Duduk di DriveSeat
            if car:FindFirstChild("DriveSeat") then
                pcall(function() car.DriveSeat:Sit(LP.Character.Humanoid) end)
            end
            task.wait(1.2)

            local seat = LP.Character.Humanoid.SeatPart
            if not seat then
                for _ = 1, 10 do
                    pcall(function() car.DriveSeat:Sit(LP.Character.Humanoid) end)
                    task.wait(0.4)
                    seat = LP.Character.Humanoid.SeatPart
                    if seat then break end
                end
            end
            if not seat then warn("[TruckFarm] Gagal duduk."); return end

            -- 7. Countdown
            FarmingStatus:UpdateBody("Semua siap! Countdown teleport...")
            for i = 20, 0, -1 do
                if not getgenv().Settings.OnFarming then return end
                if getgenv().Settings.CountdownNotif then
                    -- Notify setiap 5 detik agar tidak spam
                    if i % 5 == 0 then
                        -- Window:Notify diisi setelah UI terbuat
                    end
                end
                FarmingStatus:UpdateBody("Teleport Jawa Timur dalam "..i.." detik...")
                task.wait(1)
            end

            -- 8. Teleport ke Delivery Point Jawa Timur
            local route = CONFIG.JawaTimurRoute
            local dest  = route[math.random(1, #route)] -- ambil random titik
            local destCF = CFrame.new(dest.x, dest.y, dest.z,
                0.866007268, 0, 0.500031412, 0, 1, 0, -0.500031412, 0, 0.866007268)

            FarmingStatus:UpdateBody("Teleporting ke "..dest.label.."...")
            SafeTeleportCar(car, destCF)
            task.wait(0.4)

            -- 9. Fire job & rejoin
            FireEvent("Job", "Truck")
            task.wait(getgenv().Settings.DelayBeforeRejoin or CONFIG.DelayBeforeRejoin)

            FarmingStatus:UpdateBody("Rejoin server...")
            pcall(function()
                TeleportService:Teleport(game.PlaceId, LP)
            end)
            task.wait(60)
        end)
    end
end

-- ── 6e. Side Job Farm ────────────────────────────

local function QuestOffice()
    for _ = 1, 5 do
        if getgenv().Settings.StopFarm then break end
        pcall(function()
            local frame  = LP.PlayerGui.Job.Components.Container.Office.Frame
            local quest  = frame.Question.Text
            local submit = frame.SubmitButton
            local box    = frame.TextBox

            local parts = string.split(quest, " ")
            local n1 = tonumber(parts[1])
            local op = parts[2]
            local n2 = tonumber(parts[3])
            local ans = (op == "+") and (n1 + n2) or (n1 - n2)
            local ansStr = tostring(math.floor(ans))

            box.Text = ansStr
            repeat task.wait(CONFIG.CycleDelay) until box.Text == ansStr

            if submit.Visible then
                GuiService.SelectedObject = submit
                VIM:SendKeyEvent(true,  Enum.KeyCode.Return, false, game)
                task.wait()
                VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                task.wait(CONFIG.CycleDelay)
                GuiService.SelectedObject = nil
            end
        end)
    end
end

local function SideFarm(jobName)
    if jobName == "Office Worker" then
        FireEvent("Job", "Office")
        pcall(function()
            LP.Character.HumanoidRootPart.CFrame = CFrame.new(-38581, 1039, -62763)
        end)
        task.wait(1)
        for _ = 1, 8 do
            pcall(fireproximityprompt, workspace.Etc.Job.Office.Starter.Prompt)
        end
        repeat
            task.wait(CONFIG.CycleDelay)
            QuestOffice()
        until getgenv().Settings.StopFarm
    elseif jobName == "Barista" then
        FireEvent("Job", "JanjiJiwa")
        task.spawn(function()
            while task.wait(CONFIG.CycleDelay) and not getgenv().Settings.StopFarm do
                pcall(function()
                    local starter = workspace.Etc.Job.JanjiJiwa.Starter.Prompt
                    fireproximityprompt(starter)
                    fireproximityprompt(starter)
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(-13716.35, 1052.89, -17997.70)
                    task.wait(15)
                    if LP.Backpack:FindFirstChild("Coffee") then
                        LP.Character.HumanoidRootPart.CFrame = CFrame.new(-13723.75, 1052.89, -17994.23)
                        FireEvent("JanjiJiwa", "Delivery")
                    end
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(-13716.35, 1052.89, -17997.70)
                end)
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════
-- [7] UNLOCK ALL SHOPS
-- ═══════════════════════════════════════════════════

local function UnlockAllShops()
    -- Buka semua dealer via proximity prompt
    local opened = 0
    pcall(function()
        for _, dealer in ipairs(workspace.Etc.Dealership:GetChildren()) do
            local prompt = dealer:FindFirstChild("Prompt")
            if prompt then
                fireproximityprompt(prompt)
                opened = opened + 1
                task.wait(0.3)
            end
        end
    end)

    -- Coba buka toko via RemoteEvent jika ada
    pcall(function()
        local shops = { "KiosMarket", "Minimarket", "SpeedShop", "TuningShop", "FuelStation" }
        for _, shop in ipairs(shops) do
            local ok = pcall(FireEvent, "OpenShop", shop)
            if ok then task.wait(0.2) end
        end
    end)

    return opened
end

-- ═══════════════════════════════════════════════════
-- [8] UI BUILDER
-- ═══════════════════════════════════════════════════

repeat task.wait() until game:IsLoaded() and LP and LP.Character

-- Tunggu Lives folder
local function WaitForLives()
    local checker = workspace:FindFirstChild("Lives") and workspace.Lives:FindFirstChild(LP.Name)
    if not checker then
        for _ = 1, 60 do
            checker = workspace:FindFirstChild("Lives") and workspace.Lives:FindFirstChild(LP.Name)
            if checker then break end
            task.wait(0.5)
        end
    end
    return checker
end
WaitForLives()

-- Load MacLib
local MacLib = loadstring(game:HttpGet(
    "https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"
))()

local Window = MacLib:Window({
    Title                 = CONFIG.ScriptTitle,
    Subtitle              = CONFIG.ScriptSubtitle,
    Size                  = UDim2.fromOffset(800, 430),
    DragStyle             = 2,
    DisabledWindowControls = {},
    ShowUserInfo          = true,
    Keybind               = Enum.KeyCode.RightControl,
    AcrylicBlur           = true,
})

-- Notify wrapper
local function Notify(msg, title)
    pcall(function()
        Window:Notify({ Title = title or CONFIG.ScriptTitle, Description = msg, Lifetime = 5 })
    end)
end

-- ── Global Settings ───────────────────────────────

Window:GlobalSetting({
    Name = "UI Blur", Default = Window:GetAcrylicBlurState(),
    Callback = function(b) Window:SetAcrylicBlurState(b) end
})
Window:GlobalSetting({
    Name = "Notifications", Default = Window:GetNotificationsState(),
    Callback = function(b) Window:SetNotificationsState(b) end
})
Window:GlobalSetting({
    Name = "Show User Info", Default = Window:GetUserInfoState(),
    Callback = function(b) Window:SetUserInfoState(b) end
})

-- ── Tab Groups ────────────────────────────────────

local G1 = Window:TabGroup()
local G2 = Window:TabGroup()

local tabs = {
    Home     = G1:Tab({ Name = "Home",      Image = "rbxassetid://10734942198" }),
    Main     = G1:Tab({ Name = "Main",      Image = "rbxassetid://10723407389" }),
    Farming  = G2:Tab({ Name = "Farming",   Image = "rbxassetid://10747364031" }),
    Webhook  = G2:Tab({ Name = "Webhook",   Image = "rbxassetid://10734950309" }),
    Settings = G2:Tab({ Name = "Settings",  Image = "rbxassetid://10734950309" }),
}

-- ═══════════════════════════════════════════════════
-- TAB: HOME
-- ═══════════════════════════════════════════════════

local secPlayer   = tabs.Home:Section({ Side = "Left"  })
local secSecurity = tabs.Home:Section({ Side = "Right" })

secPlayer:Header({ Name = "Local Player" })
secSecurity:Header({ Name = "Security" })

local SpoofName   = workspace.Lives[LP.Name].Head.PlayerBillboard.Frame.PlayerName
local JobLabel    = workspace.Lives[LP.Name].Head.PlayerBillboard.Frame.JobName

secPlayer:Slider({
    Name = "Walkspeed", Default = 16, Minimum = 2, Maximum = 250,
    DisplayMethod = "Percent", Precision = 0,
    Callback = function(v) LP.Character.Humanoid.WalkSpeed = v end
}, "walkspeed")

secPlayer:Slider({
    Name = "Jump Power", Default = 16, Minimum = 2, Maximum = 250,
    DisplayMethod = "Percent", Precision = 0,
    Callback = function(v) LP.Character.Humanoid.JumpHeight = v end
}, "jumpower")

secPlayer:Toggle({
    Name = "Infinite Jump", Default = false,
    Callback = function(v) getgenv().Settings.InfiniteJump = v end,
}, "infjump")

UserInputService.JumpRequest:Connect(function()
    if getgenv().Settings.InfiniteJump then
        LP.Character:FindFirstChildOfClass("Humanoid"):ChangeState("Jumping")
    end
end)

secPlayer:Toggle({
    Name = "Click TP (CTRL + Click)", Default = false,
    Callback = function(v)
        UserInputService.InputBegan:Connect(function(input)
            if v and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                and input.UserInputType == Enum.UserInputType.MouseButton1 then
                pcall(function()
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(
                        LP:GetMouse().Hit.Position + Vector3.new(0, 5, 0)
                    )
                end)
            end
        end)
    end,
}, "clicktp")

secPlayer:Toggle({
    Name = "No Clip", Default = false,
    Callback = function(v)
        RunService.Stepped:Connect(function()
            if v then
                for _, p in pairs(LP.Character:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    end,
}, "noclip")

-- Security
secSecurity:Toggle({
    Name = "Wave Text", Default = getgenv().Settings.WaveText,
    Callback = function(v) getgenv().Settings.WaveText = v; SettingsManager:Save() end,
}, "wvtext")

secSecurity:Toggle({
    Name = "Blip Subtitle", Default = false,
    Callback = function(v)
        getgenv().Settings.BlipText = v; SettingsManager:Save()
        task.spawn(function()
            while getgenv().Settings.BlipText do
                JobLabel.Visible = not JobLabel.Visible
                JobLabel.TextColor3 = Color3.fromRGB(
                    math.random(0,255), math.random(0,255), math.random(0,255))
                task.wait(0.5)
            end
            JobLabel.Visible = true
        end)
    end,
}, "bptext")

secSecurity:Toggle({
    Name = "Spoof Name", Default = getgenv().Settings.SpoofToggle,
    Callback = function(v)
        getgenv().Settings.SpoofToggle = v
        if v then
            SpoofName.Text = getgenv().Settings.SpoofedName or "SpoofedByScript"
        end
        SettingsManager:Save()
    end,
}, "spofingtog")

secSecurity:Input({
    Name = "Spoofed Name", Placeholder = "Nama palsu...", AcceptedCharacters = "All",
    Callback = function(i) SpoofName.Text = i; getgenv().Settings.SpoofedName = i end,
    onChanged = function(i) SpoofName.Text = i; getgenv().Settings.SpoofedName = i end,
}, "spoofingname")

secSecurity:Input({
    Name = "Subtitle Name", Placeholder = "Subtitle...", AcceptedCharacters = "All",
    Callback = function(i) JobLabel.Text = i; getgenv().Settings.SubtitleName = i end,
    onChanged = function(i) JobLabel.Text = i; getgenv().Settings.SubtitleName = i end,
}, "subtitlename")

-- Wave text animation
task.spawn(function()
    while task.wait() do
        if getgenv().Settings.WaveText and getgenv().Settings.SpoofedName then
            local t = getgenv().Settings.SpoofedName
            local cur = ""
            for i = 1, #t do
                cur = cur .. t:sub(i,i)
                SpoofName.Text = cur
                task.wait(0.08)
            end
            task.wait(1)
        else
            SpoofName.Text = getgenv().Settings.SpoofedName or LP.Name
            task.wait(0.5)
        end
    end
end)

-- ═══════════════════════════════════════════════════
-- TAB: MAIN (Vehicle, Side Job, Box, Dealer, Slot)
-- ═══════════════════════════════════════════════════

local secSideJob = tabs.Main:Section({ Side = "Left"  })
local secSniper  = tabs.Main:Section({ Side = "Left"  })
local secBox     = tabs.Main:Section({ Side = "Right" })
local secSlot    = tabs.Main:Section({ Side = "Left"  })
local secDealer  = tabs.Main:Section({ Side = "Right" })

-- Side Job
secSideJob:Header({ Name = "Side-Job Farming" })

secSideJob:Dropdown({
    Name = "Pilih Job", Multi = false, Required = true,
    Options = { "Office Worker", "Barista" },
    Default = getgenv().Settings.SelectedJob,
    Callback = function(v)
        getgenv().Settings.SelectedJob = v
        Notify("Job dipilih: "..v)
    end,
}, "SelectJob")

secSideJob:Toggle({
    Name = "Mulai Farming", Default = false,
    Callback = function(v)
        if v then
            if getgenv().Settings.SelectedJob then
                getgenv().Settings.StopFarm = false
                SettingsManager:Save()
                Notify("Memulai "..getgenv().Settings.SelectedJob.."...")
                task.spawn(function() SideFarm(getgenv().Settings.SelectedJob) end)
            else
                Notify("Pilih job terlebih dahulu!")
            end
        else
            getgenv().Settings.StopFarm = true
            SettingsManager:Save()
            Notify("Farming dihentikan.")
        end
    end,
}, "FarmingStatus")

-- Vehicle Sniper
secSniper:Header({ Name = "Vehicle Sniper" })
secSniper:Label({ Text = "Beta — kendaraan limited mungkin tidak terbeli tepat waktu" })

local limitedStock = ReplicatedStorage:FindFirstChild("LimitedStock")
local vehicleNames = {}
if limitedStock then
    for _, c in ipairs(limitedStock:GetChildren()) do
        table.insert(vehicleNames, c.Name)
    end
end

getgenv().SelectedVehicle = nil
secSniper:Dropdown({
    Name = "Pilih Kendaraan", Multi = false, Required = true,
    Options = vehicleNames, Default = 1,
    Callback = function(v) getgenv().SelectedVehicle = v end,
}, "vehiclesniper")

secSniper:Button({
    Name = "Beli Kendaraan",
    Callback = function()
        if not getgenv().SelectedVehicle then Notify("Pilih kendaraan dulu!"); return end
        InvokeFunction("Dealership", "Buy", getgenv().SelectedVehicle)
    end,
})
secSniper:Button({
    Name = "Beli Semua",
    Callback = function()
        if limitedStock then
            for _, c in ipairs(limitedStock:GetChildren()) do
                InvokeFunction("Dealership", "Buy", c.Name)
                task.wait(0.3)
            end
        end
    end,
})

-- Box
secBox:Header({ Name = "Box Misc" })
secBox:Label({ Text = "Batas 5/5 — kalau tidak bekerja berarti sudah mencapai limit" })
secBox:Button({ Name = "Claim Box",      Callback = function() FireEvent("Box", "Claim") end })
secBox:Button({ Name = "Gamepass Box",   Callback = function() FireEvent("Box", "Buy", "Gamepass Box") end })
secBox:Button({ Name = "Limited Box",    Callback = function() FireEvent("Box", "Buy", "Limited Box") end })

-- Car Slot
secSlot:Header({ Name = "Car Slot" })
local slotPriceLabel = LP.PlayerGui.Upgrade.Frame.Box.ScrollingFrame.CarSlot.Frame.Price
local slotParagraph = secSlot:Paragraph({
    Header = "Harga Saat Ini", Body = slotPriceLabel.Text, Flag = "SlotPrice"
})
slotPriceLabel:GetPropertyChangedSignal("Text"):Connect(function()
    pcall(function() slotParagraph:UpdateBody(slotPriceLabel.Text) end)
end)
secSlot:Button({
    Name = "Upgrade Slot",
    Callback = function() FireEvent("UpgradeStats", "CarSlot") end,
})

-- Dealer GUI
secDealer:Header({ Name = "🏪 Dealer & Toko" })

local dealerNames   = {}
local dealerPrompts = {}
getgenv().SelectedDealer = nil

pcall(function()
    for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
        table.insert(dealerNames, d.Name)
        dealerPrompts[d.Name] = d:FindFirstChild("Prompt")
    end
end)

secDealer:Dropdown({
    Name = "Pilih Dealer", Multi = false, Required = true,
    Options = dealerNames, Default = 1,
    Callback = function(v) getgenv().SelectedDealer = v end,
}, "dealerSelect")

secDealer:Button({
    Name = "Buka GUI Dealer",
    Callback = function()
        if getgenv().SelectedDealer then
            local p = dealerPrompts[getgenv().SelectedDealer]
            if p then pcall(fireproximityprompt, p)
            else Notify("Prompt dealer tidak ditemukan.") end
        else
            Notify("Pilih dealer terlebih dahulu!")
        end
    end,
})

secDealer:Button({
    Name = "🔓 Unlock Semua Toko",
    Callback = function()
        local count = UnlockAllShops()
        Notify("Berhasil membuka "..count.." toko/dealer!")
    end,
})

-- ═══════════════════════════════════════════════════
-- TAB: FARMING — Jawa Timur Truck Farm
-- ═══════════════════════════════════════════════════

local secTruckCfg    = tabs.Farming:Section({ Side = "Left"  })
local secTruckStatus = tabs.Farming:Section({ Side = "Right" })

secTruckCfg:Header({ Name = "⚙️ Konfigurasi Farming Jawa Timur" })
secTruckStatus:Header({ Name = "📊 Status Farming" })

-- Status display
FarmingStatus = secTruckStatus:Paragraph({
    Header = "Tujuan Saat Ini",
    Body   = "Farming belum dimulai.",
    Flag   = "farmingStatus"
})

local moneyDisplay = secTruckStatus:Paragraph({
    Header = "Uang Saat Ini",
    Body   = "Rp "..FormatMoney(GetCurrentMoney()),
    Flag   = "moneyDisplay"
})

-- Update money display setiap 2 detik
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            local money = GetCurrentMoney()
            local earned = money - getgenv().SessionData.StartMoney
            if earned < 0 then earned = 0 end
            local bar, pct = MakeProgressBar(earned, getgenv().Settings.TargetEarning)
            moneyDisplay:UpdateBody(
                "Rp "..FormatMoney(money)..
                "\nEarned: Rp "..FormatMoney(earned)..
                "\n"..bar
            )
        end)
    end
end)

secTruckCfg:Paragraph({
    Header = "ℹ️ Info",
    Body   = "Farming Jawa Timur dioptimalkan untuk\nmenghasilkan uang maksimal.\nCycle Delay: "..CONFIG.CycleDelay.."s | Tween Speed: "..CONFIG.TweenSpeed,
    Flag   = "info"
})

secTruckCfg:Input({
    Name        = "Delay Sebelum Rejoin (detik)",
    Placeholder = tostring(getgenv().Settings.DelayBeforeRejoin),
    AcceptedCharacters = "All",
    Callback  = function(v) getgenv().Settings.DelayBeforeRejoin = tonumber(v) or 0.5; SettingsManager:Save() end,
    onChanged = function(v) getgenv().Settings.DelayBeforeRejoin = tonumber(v) or 0.5; SettingsManager:Save() end,
}, "dlayrejoin")

secTruckCfg:Input({
    Name        = "🎯 Target Earning (Rp)",
    Placeholder = tostring(getgenv().Settings.TargetEarning),
    AcceptedCharacters = "All",
    Callback  = function(v)
        getgenv().Settings.TargetEarning = tonumber(v) or 0
        SettingsManager:Save()
        Notify("Target diubah ke Rp "..FormatMoney(getgenv().Settings.TargetEarning))
    end,
    onChanged = function(v)
        getgenv().Settings.TargetEarning = tonumber(v) or 0
        SettingsManager:Save()
    end,
}, "targetearning")

secTruckCfg:Toggle({
    Name = "Countdown Notification", Default = getgenv().Settings.CountdownNotif,
    Callback = function(v) getgenv().Settings.CountdownNotif = v; SettingsManager:Save() end,
}, "cdnotif")

secTruckCfg:Toggle({
    Name = "Sembunyikan UI Saat Farming", Default = getgenv().Settings.MaclibVisibility,
    Callback = function(v)
        getgenv().Settings.MaclibVisibility = v
        Window:SetState(not v)
        SettingsManager:Save()
    end,
}, "windowsvisibil")

secTruckCfg:Divider()

secTruckCfg:Toggle({
    Name = "🚛 Farming Truck (Jawa Timur)",
    Default = getgenv().Settings.OnFarming,
    Callback = function(v)
        getgenv().Settings.OnFarming = v
        getgenv().Settings.StopFarm  = not v
        SettingsManager:Save()

        if v then
            -- Rekam uang awal sesi
            getgenv().SessionData.StartMoney        = GetCurrentMoney()
            getgenv().SessionData.FarmingStartTime  = os.time()
            getgenv().SessionData.LastWebhookTime   = 0
            Notify("Auto-Farm Jawa Timur dimulai! Target: Rp "..FormatMoney(getgenv().Settings.TargetEarning))
            task.spawn(TruckFarmJawaTimur)
        else
            Notify("Farming dihentikan.")
            FarmingStatus:UpdateBody("Farming dihentikan oleh pengguna.")
        end
    end,
}, "ftruk")

-- ═══════════════════════════════════════════════════
-- TAB: WEBHOOK — Discord Config
-- ═══════════════════════════════════════════════════

local secWH = tabs.Webhook:Section({ Side = "Left"  })
local secWHInfo = tabs.Webhook:Section({ Side = "Right" })

secWH:Header({ Name = "🔔 Discord Webhook" })
secWHInfo:Header({ Name = "📋 Preview" })

secWH:Paragraph({
    Header = "Cara Pakai",
    Body   = "1. Buat webhook di server Discord kamu\n2. Copy URL webhook\n3. Paste di field di bawah\n4. Log dikirim setiap 5-10 menit\n   saat farming aktif",
    Flag   = "wh_info"
})

secWH:Input({
    Name        = "Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    AcceptedCharacters = "All",
    Callback  = function(v)
        getgenv().Settings.WebhookURL = v
        SettingsManager:Save()
        Notify("Webhook URL disimpan!")
    end,
    onChanged = function(v)
        getgenv().Settings.WebhookURL = v
    end,
}, "webhookurl")

secWH:Button({
    Name = "📤 Kirim Test Webhook",
    Callback = function()
        getgenv().Settings.OnFarming = true
        getgenv().SessionData.StartMoney = GetCurrentMoney() - 12345
        getgenv().SessionData.FarmingStartTime = os.time() - 600
        getgenv().SessionData.LastWebhookTime  = 0
        SendWebhook(false)
        getgenv().Settings.OnFarming = false
        Notify("Test webhook dikirim! Cek Discord kamu.")
    end,
})

secWH:Button({
    Name = "✅ Kirim Alert Target Reached",
    Callback = function()
        getgenv().SessionData.StartMoney = GetCurrentMoney() - (getgenv().Settings.TargetEarning or 500000)
        getgenv().SessionData.FarmingStartTime = os.time() - 3600
        getgenv().SessionData.LastWebhookTime  = 0
        SendWebhook(true)
        Notify("Alert Target Reached dikirim!")
    end,
})

secWHInfo:Paragraph({
    Header = "Info Konten Embed",
    Body   = "✅ Username & UserID\n✅ Status Farming\n✅ Uang Saat Ini\n✅ Earned Sesi Ini\n✅ Progress Bar % ke Target\n✅ Durasi Sesi\n✅ Alert TARGET REACHED",
    Flag   = "wh_fields"
})

secWHInfo:Paragraph({
    Header = "Interval Pengiriman",
    Body   = "Min: "..CONFIG.WebhookMinInterval/60 .." menit\nMax: "..CONFIG.WebhookMaxInterval/60 .." menit\n(Anti-spam aktif)",
    Flag   = "wh_interval"
})

-- ═══════════════════════════════════════════════════
-- TAB: SETTINGS
-- ═══════════════════════════════════════════════════

local secOtherTools = tabs.Settings:Section({ Side = "Right" })
local secPrivServer = tabs.Settings:Section({ Side = "Left"  })

secOtherTools:Header({ Name = "🔧 Developer Tools" })
secOtherTools:Button({
    Name = "Dex Explorer",
    Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/dex.lua"))()
    end,
})
secOtherTools:Button({
    Name = "Simple Spy",
    Callback = function()
        loadstring(game:HttpGet("https://github.com/exxtremestuffs/SimpleSpySource/raw/master/SimpleSpy.lua"))()
    end,
})

secPrivServer:Header({ Name = "🔐 Private Server" })
secPrivServer:Button({
    Name = "Buat Private Code",
    Callback = function()
        FireEvent("PrivateServer", "Create")
        Notify("Membuat private code...")
    end,
})
secPrivServer:Button({
    Name = "Join Private Server (Jawa Timur)",
    Callback = function()
        pcall(function()
            local codePath = LP.PlayerGui.Hub.Container.Window.PrivateServer.ServerLabel
            if codePath and codePath.ContentText ~= "None" then
                FireEvent("PrivateServer", "Join", codePath.ContentText, "JawaTimur")
                Notify("Joining PS: "..codePath.ContentText)
            else
                Notify("Private code tidak ditemukan. Buat dulu!")
            end
        end)
    end,
})

-- ═══════════════════════════════════════════════════
-- [9] INIT — Startup & Background Tasks
-- ═══════════════════════════════════════════════════

-- Anti AFK
StartAntiAFK()

-- Cek apakah di Jawa Timur
task.spawn(function()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if ok then
        local gameName = info.Name or ""
        if not gameName:find("Timur") and not gameName:find("CDID") and
           not gameName:find("Car Driving") then
            getgenv().Settings.OnFarming = false
            Notify("⚠️ Kamu tidak di Jawa Timur!\nAuto-Farm dinonaktifkan.")
        else
            Notify("✅ Terdeteksi di "..gameName.."\nScript siap digunakan!")
        end
    end
end)

-- Auto-resume farming jika config tersimpan aktif
task.spawn(function()
    task.wait(2)
    if getgenv().Settings.OnFarming then
        getgenv().SessionData.StartMoney        = GetCurrentMoney()
        getgenv().SessionData.FarmingStartTime  = os.time()
        getgenv().SessionData.LastWebhookTime   = 0
        Notify("Config ditemukan! Auto-Farm Jawa Timur dilanjutkan...")
        FarmingStatus:UpdateBody("Auto-resume dari config...")
        task.spawn(TruckFarmJawaTimur)
    end
end)

-- Finalisasi MacLib
MacLib:SetFolder("LunarV2")
tabs.Settings:InsertConfigSection("Left")
Window.onUnloaded(function()
    StopAllFarming(false)
    print("[CDID JawaTimur] Script unloaded.")
end)
tabs.Farming:Select()
MacLib:LoadAutoLoadConfig()

print("[CDID JawaTimur Edition] Loaded successfully! v"..CONFIG.Version)
