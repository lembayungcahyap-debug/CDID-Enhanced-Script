--[[
╔══════════════════════════════════════════════════════════════════╗
║   CDID — Jawa Timur Edition  |  Rayfield UI  |  v3.0-FINAL     ║
║                                                                  ║
║   STRUKTUR                                                       ║
║   [1] CONFIG          — Semua nilai yang bisa diubah            ║
║   [2] SETTINGS MGR    — Load/Save config lokal                  ║
║   [3] SERVICES        — Cache Roblox services                   ║
║   [4] HELPERS         — Utiliti (FireEvent, Tween, Money, dll)  ║
║   [5] ANTI-AFK        — Cegah Idle Kick                         ║
║   [6] DISCORD WEBHOOK — Smart log ke Discord                    ║
║   [7] FARMING ENGINE  — Truck Farm + Side Jobs                  ║
║   [8] UNLOCK SHOPS    — Buka semua Dealer/Toko                  ║
║   [9] UI — RAYFIELD   — Semua tab & elemen UI                  ║
║   [10] INIT           — Startup tasks                           ║
╚══════════════════════════════════════════════════════════════════╝
]]

-- ================================================================
-- [1] CONFIG
-- ================================================================

local CFG = {
    -- Performa
    CycleDelay        = 0.2,
    TweenSpeed        = 49.5,
    DelayRejoin       = 0.5,
    CountdownSec      = 20,

    -- Target (0 = tidak ada batas)
    TargetEarning     = 500000,

    -- Discord Webhook
    WebhookURL        = "",      -- ← ISI URL WEBHOOK DISCORD KAMU
    WHIntervalMin     = 300,     -- 5 menit
    WHIntervalMax     = 600,     -- 10 menit

    -- Map
    MapName           = "Jawa Timur",

    -- Keyword validasi waypoint Jawa Timur
    WaypointKeywords  = {
        "Timur", "Surabaya", "Malang", "Jember",
        "Banyuwangi", "Pasuruan", "Kediri", "Mojokerto",
    },

    -- Rute delivery Jawa Timur
    -- Tambah/ubah koordinat sesuai hasil eksplorasi in-game
    Route = {
        { x = -50889.66, y = 1017.87, z = -86514.80, label = "Surabaya — Delivery A" },
        { x = -48200.00, y = 1020.00, z = -84000.00, label = "Malang — Checkpoint B"  },
        { x = -51500.00, y = 1015.00, z = -88000.00, label = "Jember — Delivery C"    },
    },

    -- Spawn area truck (near PT. Shad)
    TruckSpawnCF = CFrame.new(-21782.94, 1042.03, -26786.96),

    -- UI
    Title   = "CDID Jawa Timur",
    Sub     = "Auto-Farm Edition v3.0",
    Version = "3.0-FINAL",
}

-- ================================================================
-- [2] SETTINGS MANAGER
-- ================================================================

local SM = {
    Base = "CDID_JT3",
    File = "CDID_JT3\\cfg.json",
    LastSave = 0,
    Cooldown = 1,
}

-- State global — persistent antar cycle
getgenv().GS = getgenv().GS or {
    OnFarming    = false,
    StopFarm     = false,
    InfJump      = false,
    CdNotif      = false,
    HideUI       = false,
    TargetEarning = CFG.TargetEarning,
    WebhookURL   = CFG.WebhookURL,
    DelayRejoin  = CFG.DelayRejoin,
    SelectedJob  = "Office Worker",
}

-- Session stats (reset tiap kali farming dimulai)
getgenv().SS = getgenv().SS or {
    StartMoney      = 0,
    FarmStart       = 0,
    LastWebhook     = 0,
}

function SM:Init()
    self.HS = game:GetService("HttpService")
    pcall(function()
        if not isfolder(self.Base) then makefolder(self.Base) end
    end)
    if not self:Load() then self:Save(true) end
end

function SM:Save(force)
    if not writefile then return end
    local now = os.time()
    if not force and (now - self.LastSave) < self.Cooldown then return end
    pcall(function()
        writefile(self.File, self.HS:JSONEncode({ v = CFG.Version, s = getgenv().GS }))
        self.LastSave = now
    end)
end

function SM:Load()
    if not (readfile and isfile) then return false end
    local ok = pcall(function()
        if isfile(self.File) then
            local d = self.HS:JSONDecode(readfile(self.File))
            if d and d.s then
                for k, v in pairs(d.s) do
                    if getgenv().GS[k] ~= nil then getgenv().GS[k] = v end
                end
            end
        end
    end)
    return ok
end

SM:Init()

-- ================================================================
-- [3] SERVICES
-- ================================================================

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local TwnSvc     = game:GetService("TweenService")
local RunSvc     = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local TelSvc     = game:GetService("TeleportService")
local HttpSvc    = game:GetService("HttpService")
local MktSvc     = game:GetService("MarketplaceService")
local GuiSvc     = game:GetService("GuiService")

-- VirtualInputManager — kompatibel dengan semua executor
local VIM = game:GetService("VirtualInputManager")

local LP         = Players.LocalPlayer

-- Cache network (non-blocking, dicoba setelah game load)
local NetEvents, NetFuncs

local function CacheNetwork()
    local ok = pcall(function()
        local nc = RS:WaitForChild("NetworkContainer", 20)
        if nc then
            NetEvents = nc:FindFirstChild("RemoteEvents")
            NetFuncs  = nc:FindFirstChild("RemoteFunctions")
        end
    end)
    return ok
end

-- ================================================================
-- [4] HELPERS
-- ================================================================

-- Safe FireServer (tidak crash kalau Remote nil)
local function Fire(name, ...)
    local a = { ... }
    pcall(function()
        if not NetEvents then return end
        local ev = NetEvents:FindFirstChild(name)
        if ev then ev:FireServer(table.unpack(a)) end
    end)
end

-- Safe InvokeServer
local function Invoke(name, ...)
    local a = { ... }
    local ok, r = pcall(function()
        if not NetFuncs then return nil end
        local fn = NetFuncs:FindFirstChild(name)
        if fn then return fn:InvokeServer(table.unpack(a)) end
    end)
    return ok and r or nil
end

-- Tween karakter ke CFrame
local function TweenChar(cf, dur)
    dur = dur or (1 / CFG.TweenSpeed * 50)
    pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            TwnSvc:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = cf }):Play()
        end
    end)
end

-- Set CFrame instan (tanpa tween)
local function WarpChar(cf)
    pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = cf end
    end)
end

-- Ambil uang dari GUI (fallback 0)
local function GetMoney()
    local ok, v = pcall(function()
        local t = LP.PlayerGui.Main.Container.Hub.CashFrame.Frame.TextLabel.Text
        return tonumber(t:gsub("[^%d]", "")) or 0
    end)
    return (ok and v) or 0
end

-- Format angka: 1234567 → "1.234.567"
local function Fmt(n)
    if not n then return "0" end
    return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

-- Progress bar ASCII
local function PBar(cur, tgt, w)
    w = w or 18
    if not tgt or tgt <= 0 then return "[ ∞ No Limit ]", 0 end
    local p = math.min(cur / tgt, 1)
    local f = math.floor(p * w)
    return string.format("[%s%s] %.1f%%", string.rep("█", f), string.rep("░", w - f), p * 100), p * 100
end

-- Cek apakah pemain sedang di dalam kendaraan
local function InVehicle()
    local ok, r = pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end)
    return ok and r
end

-- Cek keyword Jawa Timur pada teks waypoint
local function IsJTWaypoint(txt)
    if not txt then return false end
    for _, kw in ipairs(CFG.WaypointKeywords) do
        if txt:find(kw) then return true end
    end
    return false
end

-- ================================================================
-- [5] ANTI-AFK
-- ================================================================

local _afkConn

local function StartAntiAFK()
    if _afkConn then pcall(function() _afkConn:Disconnect() end) end

    _afkConn = LP.Idled:Connect(function()
        pcall(function()
            local keys = { "W", "A", "S", "D" }
            local k = keys[math.random(1, #keys)]
            VIM:SendKeyEvent(true,  k, false, game)
            task.wait(math.random() * 0.2 + 0.05)
            VIM:SendKeyEvent(false, k, false, game)
            VIM:SendMouseMoveEvent(math.random(-30, 30), math.random(-30, 30), game)
        end)
    end)

    -- Reconnect setelah respawn
    LP.CharacterAdded:Once(function()
        task.wait(1)
        StartAntiAFK()
    end)
end

-- ================================================================
-- [6] DISCORD WEBHOOK
-- ================================================================

local function SendWebhook(isTargetReached)
    local url = getgenv().GS.WebhookURL or ""
    if url == "" then return end

    -- Guard: hanya kirim saat farming aktif atau target reached
    if not getgenv().GS.OnFarming and not isTargetReached then return end

    local now = os.time()

    -- Debounce (kecuali alert target reached)
    if not isTargetReached then
        local minI = CFG.WHIntervalMin
        if (now - getgenv().SS.LastWebhook) < minI then return end
    end
    getgenv().SS.LastWebhook = now

    local money  = GetMoney()
    local earned = math.max(0, money - getgenv().SS.StartMoney)
    local tgt    = getgenv().GS.TargetEarning or 0
    local bar, _ = PBar(earned, tgt)
    local elapsed = math.floor((now - getgenv().SS.FarmStart) / 60)
    local status  = isTargetReached and "✅ TARGET REACHED" or "🟢 Farming Aktif"
    local color   = isTargetReached and 5832543 or 3066993

    local payload = {
        embeds = {{
            title = isTargetReached
                and "✅ TARGET EARNING TERCAPAI!"
                or  "📊 CDID Farm Report — Jawa Timur",
            color = color,
            description = string.format("**%s** (`%d`)", LP.Name, LP.UserId),
            fields = {
                { name = "⚡ Status",         value = status,                    inline = true  },
                { name = "🗺️ Map",            value = CFG.MapName,               inline = true  },
                { name = "⏱️ Durasi Sesi",    value = elapsed .. " menit",       inline = true  },
                { name = "💰 Uang Sekarang",  value = "Rp " .. Fmt(money),       inline = true  },
                { name = "📈 Earned Sesi",    value = "Rp " .. Fmt(earned),      inline = true  },
                { name = "🎯 Target",
                  value = tgt > 0 and "Rp " .. Fmt(tgt) or "Tidak Ada",
                  inline = true },
                { name = "📊 Progress",
                  value = "```\n" .. bar .. "\n```",
                  inline = false },
            },
            footer = {
                text = "CDID v" .. CFG.Version .. " | " .. os.date("%d/%m %H:%M")
            },
        }}
    }

    pcall(function()
        local reqFn = (syn and syn.request)
                   or (http and http.request)
                   or (typeof(request) == "function" and request)
        if not reqFn then return end
        reqFn({
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpSvc:JSONEncode(payload),
        })
    end)
end

-- Timer webhook background (cek setiap 60 detik)
task.spawn(function()
    while task.wait(60) do
        if getgenv().GS.OnFarming then
            local interval = math.random(CFG.WHIntervalMin, CFG.WHIntervalMax)
            if (os.time() - getgenv().SS.LastWebhook) >= interval then
                pcall(SendWebhook, false)
            end
        end
    end
end)

-- ================================================================
-- [7] FARMING ENGINE
-- ================================================================

-- Forward-declare label updater (diisi dari UI)
local _statusUpdate = function(_) end
local _moneyUpdate  = function(_) end

local function SetStatus(txt)
    pcall(_statusUpdate, txt)
end

-- ── 7a. Stop semua farming ────────────────────────────────────

local function StopAll(sendAlert)
    getgenv().GS.OnFarming = false
    getgenv().GS.StopFarm  = true
    SM:Save()
    pcall(function() Fire("Engine", "Off") end)
    SetStatus("⏹️ Farming dihentikan.")
    if sendAlert then task.spawn(pcall, SendWebhook, true) end
end

-- ── 7b. Cek target earning ────────────────────────────────────

local function CheckTarget()
    local tgt = getgenv().GS.TargetEarning or 0
    if tgt <= 0 then return false end
    if (GetMoney() - getgenv().SS.StartMoney) >= tgt then
        StopAll(true)
        return true
    end
    return false
end

-- ── 7c. Safe teleport kendaraan (dengan validasi) ─────────────

local function TeleportCar(car, destCF)
    -- Validasi: pemain harus di dalam kendaraan
    if not InVehicle() then
        warn("[TeleportCar] Pemain tidak di kendaraan — dibatalkan.")
        return false
    end
    if not (car and car.PrimaryPart) then
        warn("[TeleportCar] Model kendaraan tidak valid.")
        return false
    end
    pcall(function()
        RunSvc:Set3dRenderingEnabled(false)
        task.wait(0.2)
        car:PivotTo(destCF)
        task.wait(0.2)
        RunSvc:Set3dRenderingEnabled(true)
    end)
    return true
end

-- ── 7d. Truck Farm — Jawa Timur ───────────────────────────────

local function TruckFarm()
    while task.wait(CFG.CycleDelay) do
        if not getgenv().GS.OnFarming then break end
        if CheckTarget() then break end

        local ok, err = pcall(function()

            -- STEP 1: Ambil job Truck
            SetStatus("📋 Mengambil job Truck...")
            Fire("Job", "Truck")
            task.wait(0.8)

            -- STEP 2: Cari & validasi waypoint
            local wpFolder = workspace.Etc and workspace.Etc:FindFirstChild("Waypoint")
            local waypoint = wpFolder and wpFolder:FindFirstChild("Waypoint")

            if not waypoint then
                for _ = 1, 15 do
                    task.wait(0.5)
                    Fire("Job", "Truck")
                    wpFolder = workspace.Etc and workspace.Etc:FindFirstChild("Waypoint")
                    waypoint = wpFolder and wpFolder:FindFirstChild("Waypoint")
                    if waypoint then break end
                end
            end

            if not waypoint then
                SetStatus("⚠️ Waypoint tidak ditemukan — skip cycle.")
                warn("[TruckFarm] Waypoint nil, skip.")
                return
            end

            -- STEP 3: Pindah ke area spawn truck
            SetStatus("🚗 Menuju area spawn...")
            TweenChar(CFG.TruckSpawnCF, 1.0)
            task.wait(1.5)

            -- STEP 4: Validasi waypoint adalah tujuan Jawa Timur
            local billboard = waypoint:FindFirstChildWhichIsA("BillboardGui", true)
            local wLabel    = billboard and billboard:FindFirstChildWhichIsA("TextLabel", true)
            local labelText = wLabel and wLabel.Text or ""

            local attempt = 0
            while not IsJTWaypoint(labelText) and getgenv().GS.OnFarming do
                attempt = attempt + 1
                if attempt > 25 then
                    SetStatus("⚠️ Waypoint JT tidak muncul — skip cycle.")
                    return
                end
                LP.Character.HumanoidRootPart.Anchored = true
                Fire("Job", "Truck")
                pcall(fireproximityprompt, workspace.Etc.Job.Truck.Starter.Prompt)
                task.wait(0.8)
                LP.Character.HumanoidRootPart.Anchored = false
                labelText = wLabel and wLabel.Text or ""
            end

            if not getgenv().GS.OnFarming then return end

            LP.Character.HumanoidRootPart.Anchored = false
            SetStatus("✅ Waypoint: " .. labelText)

            -- STEP 5: Spawn kendaraan (tekan F)
            SetStatus("🔑 Spawn kendaraan...")
            local function PressF()
                VIM:SendKeyEvent(true,  "F", false, game)
                task.wait(0.2)
                VIM:SendKeyEvent(false, "F", false, game)
            end

            PressF()
            task.wait(4)

            local function FindCar()
                local v = workspace:FindFirstChild("Vehicles")
                return v and v:FindFirstChild(LP.Name .. "sCar")
            end

            local car
            for _ = 1, 15 do
                car = FindCar()
                if car then break end
                PressF()
                task.wait(0.8)
            end

            if not car then
                SetStatus("❌ Gagal spawn kendaraan — retry cycle.")
                return
            end

            -- STEP 6: Duduk di DriveSeat
            SetStatus("🪑 Duduk di kendaraan...")
            local driveSeat = car:FindFirstChild("DriveSeat")
            if not driveSeat then
                warn("[TruckFarm] DriveSeat nil.")
                return
            end

            pcall(function() driveSeat:Sit(LP.Character.Humanoid) end)
            task.wait(1.2)

            -- Validasi duduk dengan retry
            for _ = 1, 12 do
                if InVehicle() then break end
                pcall(function() driveSeat:Sit(LP.Character.Humanoid) end)
                task.wait(0.4)
            end

            if not InVehicle() then
                SetStatus("❌ Gagal duduk — retry cycle.")
                return
            end

            -- STEP 7: Countdown
            for i = CFG.CountdownSec, 0, -1 do
                if not getgenv().GS.OnFarming then return end
                if CheckTarget() then return end
                SetStatus(string.format("⏳ Teleport Jawa Timur dalam %d detik...", i))
                task.wait(1)
            end

            -- STEP 8: Teleport kendaraan ke delivery point (random dari route)
            local dest   = CFG.Route[math.random(1, #CFG.Route)]
            local destCF = CFrame.new(
                dest.x, dest.y, dest.z,
                0.866007268, 0, 0.500031412,
                0,           1, 0,
                -0.500031412, 0, 0.866007268
            )

            SetStatus("🚀 Teleport ke " .. dest.label .. "...")
            if not TeleportCar(car, destCF) then
                SetStatus("⚠️ Teleport gagal validasi — retry cycle.")
                return
            end
            task.wait(0.4)

            -- STEP 9: Fire job & rejoin
            Fire("Job", "Truck")
            SetStatus("🔄 Rejoin...")
            task.wait(getgenv().GS.DelayRejoin or CFG.DelayRejoin)

            pcall(function() TelSvc:Teleport(game.PlaceId, LP) end)
            task.wait(90)
        end)

        if not ok then
            warn("[TruckFarm] pcall error:", err)
            SetStatus("⚠️ Error: " .. tostring(err):sub(1, 60))
            task.wait(3)
        end
    end

    SetStatus("⏹️ Truck farm loop selesai.")
end

-- ── 7e. Side Jobs ─────────────────────────────────────────────

local function QuestOffice()
    for _ = 1, 5 do
        if getgenv().GS.StopFarm then break end
        pcall(function()
            local gui = LP.PlayerGui:FindFirstChild("Job")
            if not gui then return end
            local frame  = gui.Components.Container.Office.Frame
            local quest  = frame.Question.Text
            local submit = frame.SubmitButton
            local box    = frame.TextBox

            local parts  = quest:split(" ")
            local n1, op, n2 = tonumber(parts[1]), parts[2], tonumber(parts[3])
            if not (n1 and op and n2) then return end

            local ans    = op == "+" and (n1 + n2) or (n1 - n2)
            local str    = tostring(math.floor(ans))
            box.Text     = str

            repeat task.wait(CFG.CycleDelay) until box.Text == str

            if submit.Visible then
                GuiSvc.SelectedObject = submit
                VIM:SendKeyEvent(true,  Enum.KeyCode.Return, false, game)
                task.wait()
                VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                task.wait(CFG.CycleDelay)
                GuiSvc.SelectedObject = nil
            end
        end)
    end
end

local function SideFarm(jobName)
    getgenv().GS.StopFarm = false

    if jobName == "Office Worker" then
        Fire("Job", "Office")
        pcall(function()
            LP.Character.HumanoidRootPart.CFrame = CFrame.new(-38581, 1039, -62763)
        end)
        task.wait(1)
        for _ = 1, 8 do
            pcall(fireproximityprompt, workspace.Etc.Job.Office.Starter.Prompt)
        end
        repeat
            task.wait(CFG.CycleDelay)
            QuestOffice()
        until getgenv().GS.StopFarm

    elseif jobName == "Barista" then
        Fire("Job", "JanjiJiwa")
        task.spawn(function()
            while task.wait(CFG.CycleDelay) and not getgenv().GS.StopFarm do
                pcall(function()
                    local starter = workspace.Etc.Job.JanjiJiwa.Starter.Prompt
                    fireproximityprompt(starter)
                    WarpChar(CFrame.new(-13716.35, 1052.89, -17997.70))
                    task.wait(15)
                    if LP.Backpack:FindFirstChild("Coffee") then
                        WarpChar(CFrame.new(-13723.75, 1052.89, -17994.23))
                        Fire("JanjiJiwa", "Delivery")
                    end
                    WarpChar(CFrame.new(-13716.35, 1052.89, -17997.70))
                end)
            end
        end)
    end
end

-- ================================================================
-- [8] UNLOCK SHOPS
-- ================================================================

local function UnlockShops()
    local n = 0
    -- Via proximity prompts
    pcall(function()
        for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
            local p = d:FindFirstChild("Prompt")
            if p then fireproximityprompt(p); n = n + 1; task.wait(0.2) end
        end
    end)
    -- Via RemoteEvent
    for _, s in ipairs({ "KiosMarket", "Minimarket", "SpeedShop", "TuningShop", "FuelStation" }) do
        pcall(Fire, "OpenShop", s)
        task.wait(0.15)
    end
    return n
end

-- ================================================================
-- [9] UI — RAYFIELD
-- ================================================================

-- Tunggu game & karakter benar-benar loaded
repeat task.wait(0.1)
until game:IsLoaded()
   and LP
   and LP.Character
   and LP.Character:FindFirstChild("HumanoidRootPart")

-- ── Load Rayfield ─────────────────────────────────────────────

local Rayfield

-- Coba URL utama dulu, fallback ke GitHub raw
local RF_URLS = {
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
}

for _, url in ipairs(RF_URLS) do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if ok and lib then
        Rayfield = lib
        break
    end
    warn("[CDID] Rayfield URL gagal:", url)
    task.wait(1)
end

if not Rayfield then
    -- Fallback terakhir: tampilkan pesan error via ScreenGui sederhana
    local sg = Instance.new("ScreenGui")
    sg.Name = "CDIDError"; sg.ResetOnSpawn = false
    sg.Parent = LP.PlayerGui
    local frame = Instance.new("Frame", sg)
    frame.Size = UDim2.fromOffset(400, 80)
    frame.Position = UDim2.fromScale(0.5, 0.1)
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    local lbl = Instance.new("TextLabel", frame)
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.Text = "❌ CDID: Gagal load Rayfield!\nCek koneksi internet & HTTP Request."
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.BackgroundTransparency = 1
    lbl.TextScaled = true
    error("[CDID] FATAL: Rayfield tidak dapat dimuat dari semua URL.")
end

-- Cache network setelah Rayfield berhasil dimuat
CacheNetwork()

-- ── Buat Window ───────────────────────────────────────────────

local Window = Rayfield:CreateWindow({
    Name            = CFG.Title,
    LoadingTitle    = CFG.Title,
    LoadingSubtitle = CFG.Sub,
    ConfigurationSaving = { Enabled = true, FileName = "CDID_JT3" },
    Discord         = { Enabled = false },
    KeySystem       = false,
})

-- Helper notifikasi
local function Notif(title, msg, dur, img)
    pcall(function()
        Rayfield:Notify({
            Title    = title or CFG.Title,
            Content  = msg   or "",
            Duration = dur   or 5,
            Image    = img   or "info",
        })
    end)
end

-- ╔══════════════════════════════════════╗
-- ║  TAB 1 — HOME                       ║
-- ╚══════════════════════════════════════╝

local HomeTab = Window:CreateTab("🏠 Home", "home")

HomeTab:CreateSection("Info Pemain")
HomeTab:CreateLabel("👤 " .. LP.Name .. "  |  🆔 " .. tostring(LP.UserId))
HomeTab:CreateLabel("🗺️ Map: " .. CFG.MapName .. "  |  📦 v" .. CFG.Version)

HomeTab:CreateDivider()
HomeTab:CreateSection("Karakter")

HomeTab:CreateSlider({
    Name         = "Walk Speed",
    Range        = { 2, 250 },
    Increment    = 1,
    Suffix       = " stud/s",
    CurrentValue = 16,
    Flag         = "WalkSpeed",
    Callback = function(v)
        pcall(function() LP.Character.Humanoid.WalkSpeed = v end)
    end,
})

HomeTab:CreateSlider({
    Name         = "Jump Power",
    Range        = { 2, 200 },
    Increment    = 1,
    CurrentValue = 50,
    Flag         = "JumpPower",
    Callback = function(v)
        pcall(function() LP.Character.Humanoid.JumpHeight = v end)
    end,
})

HomeTab:CreateToggle({
    Name         = "Infinite Jump",
    CurrentValue = false,
    Flag         = "InfJump",
    Callback = function(v)
        getgenv().GS.InfJump = v
    end,
})

UIS.JumpRequest:Connect(function()
    if getgenv().GS.InfJump then
        pcall(function()
            LP.Character:FindFirstChildOfClass("Humanoid"):ChangeState("Jumping")
        end)
    end
end)

HomeTab:CreateToggle({
    Name         = "No Clip",
    CurrentValue = false,
    Flag         = "NoClip",
    Callback = function(v)
        RunSvc.Stepped:Connect(function()
            if v and LP.Character then
                for _, p in pairs(LP.Character:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    end,
})

HomeTab:CreateToggle({
    Name         = "Click TP  (CTRL + Klik Kiri)",
    CurrentValue = false,
    Flag         = "ClickTP",
    Callback = function(v)
        UIS.InputBegan:Connect(function(inp)
            if not v then return end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl)
               and inp.UserInputType == Enum.UserInputType.MouseButton1 then
                pcall(function()
                    LP.Character.HumanoidRootPart.CFrame =
                        CFrame.new(LP:GetMouse().Hit.Position + Vector3.new(0, 5, 0))
                end)
            end
        end)
    end,
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 2 — FARMING                    ║
-- ╚══════════════════════════════════════╝

local FarmTab = Window:CreateTab("🚛 Farming", "truck")

FarmTab:CreateSection("📊 Status Real-Time")

-- Paragraph dinamis — diupdate via _statusUpdate / _moneyUpdate
local statusPara = FarmTab:CreateParagraph({
    Title   = "Status",
    Content = "Belum dimulai.",
})

local moneyPara = FarmTab:CreateParagraph({
    Title   = "Uang & Progress",
    Content = "Rp 0",
})

-- Assign updater functions
_statusUpdate = function(txt)
    pcall(function()
        statusPara:Set({ Title = "Status", Content = txt })
    end)
end

-- Update money setiap 2 detik
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            local money  = GetMoney()
            local earned = math.max(0, money - getgenv().SS.StartMoney)
            local bar, _ = PBar(earned, getgenv().GS.TargetEarning)
            moneyPara:Set({
                Title   = "Uang & Progress",
                Content = "💰 Rp " .. Fmt(money) ..
                          "\n📈 Earned: Rp " .. Fmt(earned) ..
                          "\n" .. bar,
            })
        end)
    end
end)

FarmTab:CreateDivider()
FarmTab:CreateSection("⚙️ Konfigurasi")

FarmTab:CreateInput({
    Name            = "🎯 Target Earning  (Rp, 0 = tidak ada batas)",
    PlaceholderText = tostring(getgenv().GS.TargetEarning),
    RemoveTextAfterFocusLost = false,
    Flag            = "TargetInput",
    Callback = function(v)
        local n = tonumber(v)
        if n then
            getgenv().GS.TargetEarning = n
            SM:Save()
            Notif("Target", "Target: Rp " .. Fmt(n), 4, "check")
        end
    end,
})

FarmTab:CreateInput({
    Name            = "⏱️ Delay Rejoin  (detik)",
    PlaceholderText = tostring(getgenv().GS.DelayRejoin),
    RemoveTextAfterFocusLost = false,
    Flag            = "DelayInput",
    Callback = function(v)
        local n = tonumber(v)
        if n then getgenv().GS.DelayRejoin = n; SM:Save() end
    end,
})

FarmTab:CreateToggle({
    Name         = "🔔 Countdown Notification",
    CurrentValue = getgenv().GS.CdNotif,
    Flag         = "CdNotif",
    Callback = function(v)
        getgenv().GS.CdNotif = v; SM:Save()
    end,
})

FarmTab:CreateDivider()
FarmTab:CreateSection("🚛 Auto-Farm Jawa Timur")

FarmTab:CreateParagraph({
    Title   = "ℹ️ Info Parameter",
    Content = "Cycle Delay : " .. CFG.CycleDelay .. " detik\n" ..
              "Tween Speed : " .. CFG.TweenSpeed .. "\n" ..
              "Countdown   : " .. CFG.CountdownSec .. " detik\n" ..
              "Route JT    : " .. #CFG.Route .. " titik delivery",
})

FarmTab:CreateToggle({
    Name         = "▶️  Mulai Truck Farm  (Jawa Timur)",
    CurrentValue = false,
    Flag         = "TruckFarmToggle",
    Callback = function(v)
        getgenv().GS.OnFarming = v
        getgenv().GS.StopFarm  = not v
        SM:Save()

        if v then
            getgenv().SS.StartMoney  = GetMoney()
            getgenv().SS.FarmStart   = os.time()
            getgenv().SS.LastWebhook = 0
            Notif("Farming", "▶️ Auto-Farm Jawa Timur dimulai!\nTarget: Rp " ..
                  Fmt(getgenv().GS.TargetEarning), 5, "play")
            task.spawn(TruckFarm)
        else
            StopAll(false)
            Notif("Farming", "⏹️ Auto-Farm dihentikan.", 4, "stop")
        end
    end,
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 3 — SIDE JOBS                  ║
-- ╚══════════════════════════════════════╝

local JobTab = Window:CreateTab("💼 Side Jobs", "briefcase")

JobTab:CreateSection("Pilih Pekerjaan")

local _selectedJob = getgenv().GS.SelectedJob or "Office Worker"

JobTab:CreateDropdown({
    Name          = "Job",
    Options       = { "Office Worker", "Barista" },
    CurrentOption = { _selectedJob },
    Flag          = "JobDropdown",
    Callback = function(opt)
        _selectedJob = opt
        getgenv().GS.SelectedJob = opt
        SM:Save()
        Notif("Job", "Dipilih: " .. opt, 3, "info")
    end,
})

JobTab:CreateToggle({
    Name         = "▶️  Mulai Side Job",
    CurrentValue = false,
    Flag         = "SideJobToggle",
    Callback = function(v)
        if v then
            getgenv().GS.StopFarm = false
            task.spawn(function() SideFarm(_selectedJob) end)
            Notif("Side Job", "Mulai: " .. _selectedJob, 4, "play")
        else
            getgenv().GS.StopFarm = true
            SM:Save()
            Notif("Side Job", "Dihentikan.", 4, "stop")
        end
    end,
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 4 — TOOLS                      ║
-- ╚══════════════════════════════════════╝

local ToolTab = Window:CreateTab("🔧 Tools", "wrench")

-- Vehicle Sniper
ToolTab:CreateSection("🎯 Vehicle Sniper")

local limitedStock = RS:FindFirstChild("LimitedStock")
local vList = {}
if limitedStock then
    for _, c in ipairs(limitedStock:GetChildren()) do
        table.insert(vList, c.Name)
    end
end
if #vList == 0 then vList = { "Tidak ada limited stock" } end

local _selVehicle = vList[1]
ToolTab:CreateDropdown({
    Name          = "Kendaraan",
    Options       = vList,
    CurrentOption = { vList[1] },
    Flag          = "VehicleDD",
    Callback = function(opt) _selVehicle = opt end,
})

ToolTab:CreateButton({
    Name     = "🛒 Beli Kendaraan Dipilih",
    Callback = function()
        Invoke("Dealership", "Buy", _selVehicle)
        Notif("Sniper", "Membeli: " .. _selVehicle, 4, "cart")
    end,
})

ToolTab:CreateButton({
    Name     = "🛒 Beli SEMUA Kendaraan",
    Callback = function()
        if limitedStock then
            for _, c in ipairs(limitedStock:GetChildren()) do
                Invoke("Dealership", "Buy", c.Name)
                task.wait(0.3)
            end
            Notif("Sniper", "Semua kendaraan dibeli!", 4, "check")
        end
    end,
})

-- Dealer & Toko
ToolTab:CreateSection("🏪 Dealer & Toko")

local dNames, dPrompts = {}, {}
pcall(function()
    for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
        table.insert(dNames, d.Name)
        dPrompts[d.Name] = d:FindFirstChild("Prompt")
    end
end)
if #dNames == 0 then dNames = { "Tidak ada dealer" } end

local _selDealer = dNames[1]
ToolTab:CreateDropdown({
    Name          = "Dealer",
    Options       = dNames,
    CurrentOption = { dNames[1] },
    Flag          = "DealerDD",
    Callback = function(opt) _selDealer = opt end,
})

ToolTab:CreateButton({
    Name     = "🚪 Buka GUI Dealer",
    Callback = function()
        local p = dPrompts[_selDealer]
        if p then
            pcall(fireproximityprompt, p)
            Notif("Dealer", "Membuka: " .. _selDealer, 3, "store")
        else
            Notif("Dealer", "Prompt tidak ditemukan.", 4, "alert")
        end
    end,
})

ToolTab:CreateButton({
    Name     = "🔓 Unlock SEMUA Toko",
    Callback = function()
        local n = UnlockShops()
        Notif("Shops", n .. " toko/dealer dibuka!", 5, "check")
    end,
})

-- Box
ToolTab:CreateSection("📦 Box")
ToolTab:CreateButton({ Name = "Claim Box",    Callback = function() Fire("Box","Claim") end })
ToolTab:CreateButton({ Name = "Gamepass Box", Callback = function() Fire("Box","Buy","Gamepass Box") end })
ToolTab:CreateButton({ Name = "Limited Box",  Callback = function() Fire("Box","Buy","Limited Box") end })

-- Car Slot
ToolTab:CreateSection("🚗 Car Slot")
ToolTab:CreateButton({
    Name     = "⬆️ Upgrade Slot",
    Callback = function() Fire("UpgradeStats", "CarSlot") end,
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 5 — WEBHOOK                    ║
-- ╚══════════════════════════════════════╝

local WHTab = Window:CreateTab("📡 Webhook", "bell")

WHTab:CreateSection("🔔 Discord Config")

WHTab:CreateParagraph({
    Title   = "Cara Setup",
    Content = "1. Buka Server Discord → Edit Channel → Integrations → Webhooks\n" ..
              "2. Buat webhook baru → Copy URL\n" ..
              "3. Paste di input di bawah → tekan Enter\n" ..
              "4. Log otomatis dikirim setiap 5–10 menit saat farming aktif",
})

WHTab:CreateInput({
    Name            = "Webhook URL",
    PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false,
    Flag            = "WebhookInput",
    Callback = function(v)
        getgenv().GS.WebhookURL = v
        SM:Save()
        Notif("Webhook", "✅ URL disimpan!", 4, "check")
    end,
})

WHTab:CreateButton({
    Name     = "📤 Test Kirim Webhook",
    Callback = function()
        local bk = getgenv().GS.OnFarming
        getgenv().GS.OnFarming  = true
        getgenv().SS.StartMoney = GetMoney() - 88888
        getgenv().SS.FarmStart  = os.time() - 300
        getgenv().SS.LastWebhook = 0
        pcall(SendWebhook, false)
        getgenv().GS.OnFarming = bk
        Notif("Webhook", "Test dikirim — cek Discord!", 5, "bell")
    end,
})

WHTab:CreateButton({
    Name     = "✅ Test Alert Target Reached",
    Callback = function()
        getgenv().SS.LastWebhook = 0
        pcall(SendWebhook, true)
        Notif("Webhook", "Alert TARGET REACHED dikirim!", 5, "check")
    end,
})

WHTab:CreateSection("📋 Data Embed")
WHTab:CreateParagraph({
    Title   = "Isi Log Discord",
    Content = "✅ Username & UserID\n" ..
              "✅ Status (Aktif / Target Reached)\n" ..
              "✅ Uang Saat Ini\n" ..
              "✅ Earned Sesi Ini\n" ..
              "✅ Progress Bar % ke Target\n" ..
              "✅ Durasi Sesi (menit)\n" ..
              "✅ Timestamp",
})
WHTab:CreateParagraph({
    Title   = "Interval Anti-Spam",
    Content = "Min: " .. CFG.WHIntervalMin/60 .. " menit\n" ..
              "Max: " .. CFG.WHIntervalMax/60 .. " menit\n" ..
              "(Acak setiap siklus — debounce aktif)",
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 6 — SETTINGS                   ║
-- ╚══════════════════════════════════════╝

local SettTab = Window:CreateTab("⚙️ Settings", "settings")

SettTab:CreateSection("🔐 Private Server")

SettTab:CreateButton({
    Name     = "📋 Buat Private Code",
    Callback = function()
        Fire("PrivateServer", "Create")
        Notif("PS", "Membuat private code...", 4, "info")
    end,
})

SettTab:CreateButton({
    Name     = "🔗 Join Private Server (Jawa Timur)",
    Callback = function()
        pcall(function()
            local lbl = LP.PlayerGui.Hub.Container.Window.PrivateServer.ServerLabel
            if lbl and lbl.ContentText ~= "None" then
                Fire("PrivateServer", "Join", lbl.ContentText, "JawaTimur")
                Notif("PS", "Joining: " .. lbl.ContentText, 5, "link")
            else
                Notif("PS", "Buat private code dulu!", 5, "alert")
            end
        end)
    end,
})

SettTab:CreateSection("🔧 Developer Tools")

SettTab:CreateButton({
    Name     = "Dex Explorer",
    Callback = function()
        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/dex.lua"))()
        end)
    end,
})

SettTab:CreateButton({
    Name     = "Simple Spy",
    Callback = function()
        pcall(function()
            loadstring(game:HttpGet(
                "https://github.com/exxtremestuffs/SimpleSpySource/raw/master/SimpleSpy.lua"
            ))()
        end)
    end,
})

SettTab:CreateSection("ℹ️ Tentang Script")
SettTab:CreateParagraph({
    Title   = "Info",
    Content = "Versi     : " .. CFG.Version .. "\n" ..
              "UI Lib    : Rayfield (sirius.menu)\n" ..
              "CycleDelay: " .. CFG.CycleDelay .. " detik\n" ..
              "TwnSpeed  : " .. CFG.TweenSpeed .. "\n" ..
              "Route JT  : " .. #CFG.Route .. " titik\n" ..
              "AntiAFK   : Aktif (VirtualInputManager)",
})

-- ================================================================
-- [10] INIT
-- ================================================================

-- Anti-AFK aktif dari awal
StartAntiAFK()

-- Cek apakah benar-benar di map Jawa Timur
task.spawn(function()
    local ok, info = pcall(function()
        return MktSvc:GetProductInfo(game.PlaceId)
    end)
    if ok and info then
        local name = info.Name or ""
        if name:find("Timur") or name:find("Car Driving") or name:find("CDID") then
            Notif("✅ Map OK", "Terdeteksi: " .. name, 5, "check")
        else
            getgenv().GS.OnFarming = false
            Notif("⚠️ Bukan Jawa Timur!", "Auto-Farm dinonaktifkan.\nAktifkan manual jika diperlukan.", 7, "alert")
        end
    end
end)

-- Auto-resume farming dari config tersimpan
task.spawn(function()
    task.wait(3)
    if getgenv().GS.OnFarming then
        getgenv().SS.StartMoney  = GetMoney()
        getgenv().SS.FarmStart   = os.time()
        getgenv().SS.LastWebhook = 0
        Notif("Auto-Resume", "Config ditemukan — farming dilanjutkan!", 5, "play")
        SetStatus("♻️ Auto-resume dari config tersimpan...")
        task.spawn(TruckFarm)
    end
end)

print(string.format("[CDID Rayfield] Loaded v%s | CycleDelay=%.1f | TwnSpeed=%.1f",
    CFG.Version, CFG.CycleDelay, CFG.TweenSpeed))
