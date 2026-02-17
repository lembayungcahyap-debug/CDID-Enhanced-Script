--[[
╔══════════════════════════════════════════════════════════════════════════╗
║         CDID Script — Jawa Timur Edition (Rayfield Build)              ║
║         UI Library : Rayfield (sirius.menu/rayfield)                   ║
║         Version    : 2.0.0-RF                                          ║
║                                                                          ║
║  STRUKTUR KODE                                                           ║
║  [1] CONFIG          — Semua nilai yang bisa dikustomisasi              ║
║  [2] SETTINGS MGR    — Load/Save config lokal                          ║
║  [3] SERVICES        — Cache Roblox services                           ║
║  [4] HELPERS         — Fungsi utiliti (FireEvent, Tween, Money)        ║
║  [5] ANTI-AFK        — Cegah Idle Kick                                 ║
║  [6] DISCORD WEBHOOK — Smart log ke Discord                            ║
║  [7] FARMING ENGINE  — Truck Farm Jawa Timur + Side Jobs               ║
║  [8] UNLOCK SHOPS    — Buka semua dealer/toko remote                   ║
║  [9] UI BUILDER      — Semua elemen Rayfield                           ║
║  [10] INIT           — Startup & background tasks                      ║
╚══════════════════════════════════════════════════════════════════════════╝
]]

-- ════════════════════════════════════════════════════════
-- [1] CONFIG — Edit nilai di sini sebelum execute
-- ════════════════════════════════════════════════════════

local CONFIG = {
    -- Performa
    CycleDelay        = 0.2,        -- Detik antar setiap aksi loop
    TweenSpeed        = 49.5,       -- Kecepatan tween kendaraan
    DelayBeforeRejoin = 0.5,        -- Jeda sebelum rejoin (detik)
    CountdownSeconds  = 20,         -- Countdown sebelum teleport

    -- Target Earning (0 = tidak ada batas)
    TargetEarning     = 500000,

    -- Discord Webhook
    WebhookURL        = "",         -- Isi URL webhook Discord kamu di sini
    WebhookMinInterval = 300,       -- 5 menit
    WebhookMaxInterval = 600,       -- 10 menit

    -- Map
    TargetMap         = "Jawa Timur",

    -- Rute Jawa Timur — tambah titik sesuai kebutuhan
    JawaTimurRoute = {
        { x = -50889.66, y = 1017.87, z = -86514.80, label = "Delivery Point A (Surabaya)" },
        { x = -48200.00, y = 1020.00, z = -84000.00, label = "Checkpoint B (Malang)"       },
        { x = -51500.00, y = 1015.00, z = -88000.00, label = "Delivery Point C (Jember)"   },
    },

    -- Keyword waypoint Jawa Timur (untuk validasi)
    WaypointKeywords  = { "Timur", "Surabaya", "Malang", "Jember", "Banyuwangi", "Pasuruan" },

    -- UI
    Title    = "CDID Jawa Timur",
    Subtitle = "Auto-Farm Edition v2.0",
    Version  = "2.0.0-RF",
}

-- ════════════════════════════════════════════════════════
-- [2] SETTINGS MANAGER
-- ════════════════════════════════════════════════════════

local SettingsManager = {
    BaseFolder   = "CDID_JT",
    SubFolder    = "config",
    FileName     = "settings_v2",
    SaveCooldown = 1,
    LastSave     = 0,
}

-- State global
getgenv().S = getgenv().S or {
    OnFarming        = false,
    StopFarm         = false,
    InfiniteJump     = false,
    CountdownNotif   = false,
    HideUI           = false,
    TargetEarning    = CONFIG.TargetEarning,
    WebhookURL       = CONFIG.WebhookURL,
    DelayBeforeRejoin = CONFIG.DelayBeforeRejoin,
    SelectedJob      = nil,
    SpoofedName      = nil,
    WaveText         = false,
}

getgenv().Session = getgenv().Session or {
    StartMoney       = 0,
    FarmStartTime    = 0,
    LastWebhookTime  = 0,
    Earned           = 0,
}

function SettingsManager:Init()
    self.HS = game:GetService("HttpService")
    local base = self.BaseFolder
    local sub  = base .. "\\" .. self.SubFolder
    self.Path  = sub .. "\\" .. self.FileName .. ".json"
    pcall(function()
        if not isfolder(base) then makefolder(base) end
        if not isfolder(sub)  then makefolder(sub)  end
    end)
    if not self:Load() then pcall(function() self:Save(true) end) end
end

function SettingsManager:Save(force)
    if not writefile then return end
    local now = os.time()
    if not force and (now - self.LastSave) < self.SaveCooldown then return end
    pcall(function()
        writefile(self.Path, self.HS:JSONEncode({ v = CONFIG.Version, s = getgenv().S }))
        self.LastSave = now
    end)
end

function SettingsManager:Load()
    if not (readfile and isfile) then return false end
    local ok = pcall(function()
        if isfile(self.Path) then
            local d = self.HS:JSONDecode(readfile(self.Path))
            if d and d.s then
                for k, v in pairs(d.s) do
                    if getgenv().S[k] ~= nil then getgenv().S[k] = v end
                end
            end
        end
    end)
    return ok
end

SettingsManager:Init()

-- ════════════════════════════════════════════════════════
-- [3] SERVICES CACHE
-- ════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local UIS              = game:GetService("UserInputService")
local VIM              = game:GetService("VirtualInputService") or game:GetService("VirtualInputManager")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local MarketService    = game:GetService("MarketplaceService")
local GuiService       = game:GetService("GuiService")

local LP               = Players.LocalPlayer

-- Tunggu NetworkContainer dengan timeout
local Network, RemoteEvents, RemoteFunctions
task.spawn(function()
    Network        = RS:WaitForChild("NetworkContainer", 30)
    RemoteEvents   = Network and Network:FindFirstChild("RemoteEvents")
    RemoteFunctions = Network and Network:FindFirstChild("RemoteFunctions")
end)

-- ════════════════════════════════════════════════════════
-- [4] HELPERS
-- ════════════════════════════════════════════════════════

-- Safe FireServer — tidak crash kalau Remote tidak ada
local function FireEvent(name, ...)
    local args = { ... }
    pcall(function()
        if not RemoteEvents then return end
        local ev = RemoteEvents:FindFirstChild(name)
        if ev then ev:FireServer(table.unpack(args)) end
    end)
end

-- Safe InvokeServer
local function InvokeFunc(name, ...)
    local args = { ... }
    local ok, result = pcall(function()
        if not RemoteFunctions then return nil end
        local fn = RemoteFunctions:FindFirstChild(name)
        if fn then return fn:InvokeServer(table.unpack(args)) end
    end)
    return ok and result or nil
end

-- Tween HumanoidRootPart ke posisi
local function TweenChar(cf, dur)
    dur = dur or (1 / CONFIG.TweenSpeed * 50)
    pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = cf }):Play()
        end
    end)
end

-- Dapatkan uang dari GUI (fallback 0 kalau GUI belum ada)
local function GetMoney()
    local ok, v = pcall(function()
        local txt = LP.PlayerGui.Main.Container.Hub.CashFrame.Frame.TextLabel.Text
        return tonumber(txt:gsub("[^%d]", "")) or 0
    end)
    return ok and v or 0
end

-- Format angka: 1234567 → "1.234.567"
local function Fmt(n)
    if not n then return "0" end
    return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

-- Progress bar ASCII
local function ProgressBar(cur, tgt, w)
    w = w or 18
    if not tgt or tgt <= 0 then return "[ No Limit ]", 0 end
    local p   = math.min(cur / tgt, 1)
    local f   = math.floor(p * w)
    local bar = string.rep("█", f) .. string.rep("░", w - f)
    return string.format("[%s] %.1f%%", bar, p * 100), p * 100
end

-- Validasi apakah pemain sedang di dalam kendaraan
local function IsInVehicle()
    local ok, result = pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end)
    return ok and result
end

-- ════════════════════════════════════════════════════════
-- [5] ANTI-AFK
-- ════════════════════════════════════════════════════════

local _afkConn = nil
local function StartAntiAFK()
    if _afkConn then pcall(function() _afkConn:Disconnect() end) end
    local keys = { "W", "A", "S", "D" }
    _afkConn = LP.Idled:Connect(function()
        pcall(function()
            local k = keys[math.random(1, #keys)]
            VIM:SendKeyEvent(true,  k, false, game)
            task.wait(math.random() * 0.2 + 0.05)
            VIM:SendKeyEvent(false, k, false, game)
            VIM:SendMouseMoveEvent(math.random(-30, 30), math.random(-30, 30), game)
        end)
    end)
    LP.CharacterRemoving:Once(function()
        if _afkConn then pcall(function() _afkConn:Disconnect() end) end
        task.wait(3)
        StartAntiAFK() -- Re-connect setelah respawn
    end)
end

-- ════════════════════════════════════════════════════════
-- [6] DISCORD WEBHOOK — Smart Reporting
-- ════════════════════════════════════════════════════════

local function SendWebhook(isTargetReached)
    local url = getgenv().S.WebhookURL or ""
    if url == "" then return end

    -- Guard: hanya kirim saat farming aktif atau target reached
    if not getgenv().S.OnFarming and not isTargetReached then return end

    local now = os.time()
    -- Debounce kecuali target reached
    if not isTargetReached then
        local minI = CONFIG.WebhookMinInterval
        if (now - getgenv().Session.LastWebhookTime) < minI then return end
    end
    getgenv().Session.LastWebhookTime = now

    local currentMoney = GetMoney()
    local earned       = math.max(0, currentMoney - getgenv().Session.StartMoney)
    getgenv().Session.Earned = earned

    local target   = getgenv().S.TargetEarning or 0
    local bar, pct = ProgressBar(earned, target)
    local elapsed  = math.floor((now - getgenv().Session.FarmStartTime) / 60)
    local status   = isTargetReached and "✅ TARGET REACHED" or "🟢 Farming Aktif"
    local color    = isTargetReached and 5832543 or 3066993

    local payload = {
        embeds = {{
            title = isTargetReached
                and "✅ TARGET EARNING TERCAPAI!"
                or  "📊 CDID Farm Report — Jawa Timur",
            color = color,
            description = string.format(
                isTargetReached
                    and "**%s** (`%d`) telah mencapai target earning sesi ini!"
                    or  "Laporan otomatis farming CDID untuk **%s** (`%d`)",
                LP.Name, LP.UserId
            ),
            fields = {
                { name = "👤 Player",         value = LP.Name,                    inline = true },
                { name = "🆔 UserID",          value = tostring(LP.UserId),         inline = true },
                { name = "🗺️ Map",             value = CONFIG.TargetMap,           inline = true },
                { name = "⚡ Status",           value = status,                     inline = true },
                { name = "⏱️ Durasi Sesi",     value = elapsed .. " menit",        inline = true },
                { name = "💰 Uang Sekarang",   value = "Rp " .. Fmt(currentMoney), inline = true },
                { name = "📈 Earned Sesi",     value = "Rp " .. Fmt(earned),       inline = true },
                { name = "🎯 Target",
                  value = target > 0 and "Rp " .. Fmt(target) or "Tidak Ada",
                  inline = true },
                { name = "📊 Progress",
                  value = "```\n" .. bar .. "\n```",
                  inline = false },
            },
            footer = {
                text = "CDID Jawa Timur v" .. CONFIG.Version ..
                       " | " .. os.date("%d/%m/%Y %H:%M")
            },
        }}
    }

    pcall(function()
        -- Kompatibel dengan syn.request, http.request, maupun request
        local requestFn = (syn and syn.request)
                       or (http and http.request)
                       or (typeof(request) == "function" and request)
        if not requestFn then
            warn("[Webhook] Tidak ada fungsi HTTP request tersedia.")
            return
        end
        requestFn({
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(payload),
        })
    end)
end

-- Background webhook timer (acak 5–10 menit)
task.spawn(function()
    while task.wait(60) do
        if getgenv().S.OnFarming then
            local interval = math.random(CONFIG.WebhookMinInterval, CONFIG.WebhookMaxInterval)
            if (os.time() - getgenv().Session.LastWebhookTime) >= interval then
                SendWebhook(false)
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════
-- [7] FARMING ENGINE
-- ════════════════════════════════════════════════════════

-- Referensi ke label status UI (forward declare, diisi saat UI terbuat)
local UIStatusLabel   = nil
local UIMoneyLabel    = nil

local function UpdateStatus(txt)
    pcall(function()
        if UIStatusLabel then UIStatusLabel:Set(txt) end
    end)
end

-- ── 7a. Stop semua farming ───────────────────────

local function StopAllFarming(sendAlert)
    getgenv().S.OnFarming = false
    getgenv().S.StopFarm  = true
    SettingsManager:Save()
    -- Matikan mesin via remote (jika ada)
    pcall(function() FireEvent("Engine", "Off") end)
    UpdateStatus("⏹️ Farming dihentikan.")
    if sendAlert then
        task.spawn(function() SendWebhook(true) end)
    end
    print("[CDID] StopAllFarming called.")
end

-- ── 7b. Cek target earning ────────────────────────

local function CheckTarget()
    local tgt = getgenv().S.TargetEarning or 0
    if tgt <= 0 then return false end
    local earned = GetMoney() - getgenv().Session.StartMoney
    if earned >= tgt then
        StopAllFarming(true)
        return true
    end
    return false
end

-- ── 7c. Safe teleport kendaraan ──────────────────
-- Validasi pemain di kendaraan SEBELUM teleport

local function SafeTeleportCar(car, destCF)
    -- Validation check: pastikan pemain masih di kendaraan
    if not IsInVehicle() then
        warn("[SafeTeleportCar] Pemain tidak di kendaraan. Teleport dibatalkan.")
        return false
    end
    if not car or not car.PrimaryPart then
        warn("[SafeTeleportCar] Kendaraan tidak valid.")
        return false
    end
    pcall(function()
        RunService:Set3dRenderingEnabled(false)
        task.wait(0.25)
        car:PivotTo(destCF)
        task.wait(0.25)
        RunService:Set3dRenderingEnabled(true)
    end)
    return true
end

-- ── 7d. Helper: cek keyword waypoint ─────────────

local function IsJawaTimurWaypoint(text)
    if not text then return false end
    for _, kw in ipairs(CONFIG.WaypointKeywords) do
        if text:find(kw) then return true end
    end
    return false
end

-- ── 7e. Truck Farm — Jawa Timur ───────────────────

local function TruckFarmJawaTimur()
    while task.wait(CONFIG.CycleDelay) do
        if not getgenv().S.OnFarming then break end
        if CheckTarget() then break end

        local cycleOk, cycleErr = pcall(function()

            -- STEP 1: Ambil job Truck
            FireEvent("Job", "Truck")
            UpdateStatus("📋 Mengambil job Truck...")
            task.wait(0.8)

            -- STEP 2: Validasi waypoint tersedia
            local wpFolder  = workspace.Etc and workspace.Etc:FindFirstChild("Waypoint")
            local waypoint  = wpFolder and wpFolder:FindFirstChild("Waypoint")

            if not waypoint then
                for _ = 1, 12 do
                    task.wait(0.5)
                    FireEvent("Job", "Truck")
                    wpFolder = workspace.Etc and workspace.Etc:FindFirstChild("Waypoint")
                    waypoint = wpFolder and wpFolder:FindFirstChild("Waypoint")
                    if waypoint then break end
                end
            end
            if not waypoint then
                warn("[TruckFarm] Waypoint tidak ditemukan. Skip cycle.")
                UpdateStatus("⚠️ Waypoint tidak ditemukan, retry...")
                return
            end

            -- STEP 3: Pindah ke area spawn truck
            local spawnCF = CFrame.new(-21782.94, 1042.03, -26786.96)
            TweenChar(spawnCF, 1.0)
            UpdateStatus("🚗 Menuju area spawn truck...")
            task.wait(1.5)

            -- STEP 4: Pastikan waypoint adalah tujuan Jawa Timur
            local wBillboard = waypoint:FindFirstChildWhichIsA("BillboardGui", true)
            local wLabel     = wBillboard and wBillboard:FindFirstChildWhichIsA("TextLabel", true)
            local labelText  = wLabel and wLabel.Text or ""

            local attempt = 0
            while not IsJawaTimurWaypoint(labelText) and getgenv().S.OnFarming do
                attempt = attempt + 1
                if attempt > 20 then
                    warn("[TruckFarm] Waypoint Jawa Timur tidak tersedia setelah 20 percobaan.")
                    UpdateStatus("⚠️ Waypoint JawaTimur tidak muncul, skip cycle...")
                    return
                end
                LP.Character.HumanoidRootPart.Anchored = true
                FireEvent("Job", "Truck")
                pcall(fireproximityprompt, workspace.Etc.Job.Truck.Starter.Prompt)
                LP.Character.HumanoidRootPart.Anchored = false
                task.wait(0.8)
                labelText = wLabel and wLabel.Text or ""
            end
            if not getgenv().S.OnFarming then return end

            LP.Character.HumanoidRootPart.Anchored = false
            UpdateStatus("✅ Waypoint Jawa Timur: " .. labelText)

            -- STEP 5: Spawn kendaraan (tekan F)
            UpdateStatus("🔑 Spawn kendaraan...")
            VIM:SendKeyEvent(true,  "F", false, game)
            task.wait(0.25)
            VIM:SendKeyEvent(false, "F", false, game)
            task.wait(4)

            local function FindCar()
                local v = workspace:FindFirstChild("Vehicles")
                return v and v:FindFirstChild(LP.Name .. "sCar")
            end

            local car
            for i = 1, 15 do
                car = FindCar()
                if car then break end
                VIM:SendKeyEvent(true,  "F", false, game)
                task.wait(0.15)
                VIM:SendKeyEvent(false, "F", false, game)
                task.wait(0.8)
            end

            if not car then
                warn("[TruckFarm] Gagal spawn kendaraan setelah 15 percobaan.")
                UpdateStatus("❌ Gagal spawn kendaraan, retry...")
                return
            end

            -- STEP 6: Duduk di DriveSeat
            UpdateStatus("🪑 Duduk di kendaraan...")
            local driveSeat = car:FindFirstChild("DriveSeat")
            if not driveSeat then
                warn("[TruckFarm] DriveSeat tidak ditemukan.")
                return
            end

            pcall(function() driveSeat:Sit(LP.Character.Humanoid) end)
            task.wait(1.2)

            -- Validasi sudah duduk
            local seated = false
            for _ = 1, 10 do
                if IsInVehicle() then seated = true; break end
                pcall(function() driveSeat:Sit(LP.Character.Humanoid) end)
                task.wait(0.4)
            end

            if not seated then
                warn("[TruckFarm] Gagal duduk setelah 10 percobaan.")
                UpdateStatus("❌ Gagal duduk, retry cycle...")
                return
            end

            -- STEP 7: Countdown teleport
            for i = CONFIG.CountdownSeconds, 0, -1 do
                if not getgenv().S.OnFarming then return end
                if CheckTarget() then return end
                UpdateStatus(string.format("⏳ Teleport dalam %d detik...", i))
                task.wait(1)
            end

            -- STEP 8: Teleport kendaraan ke Delivery Point Jawa Timur (random)
            local route = CONFIG.JawaTimurRoute
            local dest  = route[math.random(1, #route)]
            local destCF = CFrame.new(
                dest.x, dest.y, dest.z,
                0.866007268, 0, 0.500031412,
                0, 1, 0,
                -0.500031412, 0, 0.866007268
            )

            UpdateStatus("🚀 Teleport ke " .. dest.label .. "...")
            local teleOk = SafeTeleportCar(car, destCF)
            if not teleOk then
                UpdateStatus("⚠️ Teleport gagal — validasi tidak lulus.")
                return
            end
            task.wait(0.4)

            -- STEP 9: Fire job lagi & rejoin
            FireEvent("Job", "Truck")
            UpdateStatus("🔄 Rejoin server...")
            task.wait(getgenv().S.DelayBeforeRejoin or CONFIG.DelayBeforeRejoin)

            pcall(function()
                TeleportService:Teleport(game.PlaceId, LP)
            end)
            task.wait(90) -- tunggu teleport
        end)

        if not cycleOk then
            warn("[TruckFarm] Cycle error:", cycleErr)
            UpdateStatus("⚠️ Error cycle, retry dalam 3 detik...")
            task.wait(3)
        end
    end
    UpdateStatus("⏹️ Farming loop selesai.")
end

-- ── 7f. Side Jobs ─────────────────────────────────

local function QuestOffice()
    for _ = 1, 5 do
        if getgenv().S.StopFarm then break end
        pcall(function()
            local gui    = LP.PlayerGui:FindFirstChild("Job")
            if not gui then return end
            local frame  = gui.Components.Container.Office.Frame
            local quest  = frame.Question.Text
            local submit = frame.SubmitButton
            local box    = frame.TextBox

            local parts  = quest:split(" ")
            local n1, op, n2 = tonumber(parts[1]), parts[2], tonumber(parts[3])
            if not (n1 and op and n2) then return end

            local ans    = op == "+" and (n1 + n2) or (n1 - n2)
            local ansStr = tostring(math.floor(ans))
            box.Text     = ansStr

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
    getgenv().S.StopFarm = false
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
        until getgenv().S.StopFarm

    elseif jobName == "Barista" then
        FireEvent("Job", "JanjiJiwa")
        task.spawn(function()
            while task.wait(CONFIG.CycleDelay) and not getgenv().S.StopFarm do
                pcall(function()
                    local starter = workspace.Etc.Job.JanjiJiwa.Starter.Prompt
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

-- ════════════════════════════════════════════════════════
-- [8] UNLOCK ALL SHOPS
-- ════════════════════════════════════════════════════════

local function UnlockAllShops()
    local opened = 0
    -- Buka semua dealer via proximity prompt
    pcall(function()
        for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
            local p = d:FindFirstChild("Prompt")
            if p then
                fireproximityprompt(p)
                opened = opened + 1
                task.wait(0.25)
            end
        end
    end)
    -- Coba via RemoteEvent
    local remoteShops = { "KiosMarket", "Minimarket", "SpeedShop", "TuningShop", "FuelStation" }
    for _, s in ipairs(remoteShops) do
        pcall(FireEvent, "OpenShop", s)
        task.wait(0.15)
    end
    return opened
end

-- ════════════════════════════════════════════════════════
-- [9] UI BUILDER — Rayfield Library
-- ════════════════════════════════════════════════════════

-- Tunggu game loaded
repeat task.wait(0.1) until game:IsLoaded() and LP and LP.Character

-- Load Rayfield (dengan fallback URL)
local Rayfield
local ok_rf, err_rf = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not ok_rf or not Rayfield then
    -- Fallback URL
    pcall(function()
        Rayfield = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/shlexware/Rayfield/main/source"
        ))()
    end)
end

if not Rayfield then
    error("[CDID] FATAL: Gagal memuat Rayfield UI Library!\n" .. tostring(err_rf))
end

-- Buat Window utama
local Window = Rayfield:CreateWindow({
    Name             = CONFIG.Title,
    LoadingTitle     = CONFIG.Title,
    LoadingSubtitle  = CONFIG.Subtitle,
    ConfigurationSaving = {
        Enabled  = true,
        FileName = "CDID_JT_Config",
    },
    Discord = {
        Enabled = false,
    },
    KeySystem = false,
})

-- Helper Notify
local function Notify(title, msg, dur, icon)
    pcall(function()
        Rayfield:Notify({
            Title       = title or CONFIG.Title,
            Content     = msg   or "",
            Duration    = dur   or 5,
            Image       = icon  or "info",
        })
    end)
end

-- ╔══════════════════════════════╗
-- ║  TAB 1: HOME                ║
-- ╚══════════════════════════════╝

local HomeTab = Window:CreateTab("🏠 Home", "home")

-- Section: Player Info
local secInfo = HomeTab:CreateSection("Player Info")

HomeTab:CreateLabel("👤 Player: " .. LP.Name .. " | 🆔 " .. LP.UserId)
HomeTab:CreateLabel("🗺️ Map Target: " .. CONFIG.TargetMap)
HomeTab:CreateLabel("📦 Script v" .. CONFIG.Version)

HomeTab:CreateDivider()
HomeTab:CreateSection("Karakter")

HomeTab:CreateSlider({
    Name    = "Walkspeed",
    Range   = { 2, 250 },
    Increment = 1,
    Suffix  = " stud/s",
    CurrentValue = 16,
    Flag    = "WalkSpeed",
    Callback = function(v)
        pcall(function() LP.Character.Humanoid.WalkSpeed = v end)
    end,
})

HomeTab:CreateSlider({
    Name    = "Jump Power",
    Range   = { 2, 200 },
    Increment = 1,
    Suffix  = "",
    CurrentValue = 50,
    Flag    = "JumpPower",
    Callback = function(v)
        pcall(function() LP.Character.Humanoid.JumpHeight = v end)
    end,
})

HomeTab:CreateToggle({
    Name    = "Infinite Jump",
    CurrentValue = false,
    Flag    = "InfJump",
    Callback = function(v)
        getgenv().S.InfiniteJump = v
    end,
})

UIS.JumpRequest:Connect(function()
    if getgenv().S.InfiniteJump then
        pcall(function()
            LP.Character:FindFirstChildOfClass("Humanoid"):ChangeState("Jumping")
        end)
    end
end)

HomeTab:CreateToggle({
    Name    = "No Clip",
    CurrentValue = false,
    Flag    = "NoClip",
    Callback = function(v)
        RunService.Stepped:Connect(function()
            if v and LP.Character then
                for _, p in pairs(LP.Character:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    end,
})

HomeTab:CreateToggle({
    Name    = "Click Teleport (CTRL + Klik)",
    CurrentValue = false,
    Flag    = "ClickTP",
    Callback = function(v)
        UIS.InputBegan:Connect(function(inp)
            if v and UIS:IsKeyDown(Enum.KeyCode.LeftControl)
                and inp.UserInputType == Enum.UserInputType.MouseButton1 then
                pcall(function()
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(
                        LP:GetMouse().Hit.Position + Vector3.new(0, 5, 0)
                    )
                end)
            end
        end)
    end,
})

-- ╔══════════════════════════════╗
-- ║  TAB 2: FARMING             ║
-- ╚══════════════════════════════╝

local FarmTab = Window:CreateTab("🚛 Farming", "truck")

-- Status display (gunakan CreateLabel dan update teks via variable)
FarmTab:CreateSection("📊 Status Real-Time")

-- Rayfield tidak punya built-in Update untuk Label,
-- jadi kita gunakan wrapper sederhana.
local _statusText = "Belum dimulai."
local _moneyText  = "Rp 0"

local statusParagraph = FarmTab:CreateParagraph({
    Title   = "Status Farming",
    Content = _statusText,
})
local moneyParagraph = FarmTab:CreateParagraph({
    Title   = "Uang & Progress",
    Content = _moneyText,
})

-- Assign ke UIStatusLabel supaya UpdateStatus() bisa memperbarui
UIStatusLabel = {
    Set = function(_, txt)
        pcall(function() statusParagraph:Set({ Title = "Status Farming", Content = txt }) end)
    end
}

-- Update money setiap 2 detik
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            local money  = GetMoney()
            local earned = math.max(0, money - getgenv().Session.StartMoney)
            local bar, _ = ProgressBar(earned, getgenv().S.TargetEarning)
            moneyParagraph:Set({
                Title   = "Uang & Progress",
                Content = string.format(
                    "💰 Rp %s\n📈 Earned: Rp %s\n%s",
                    Fmt(money), Fmt(earned), bar
                ),
            })
        end)
    end
end)

FarmTab:CreateDivider()
FarmTab:CreateSection("⚙️ Konfigurasi")

FarmTab:CreateInput({
    Name        = "🎯 Target Earning (Rp)",
    PlaceholderText = tostring(getgenv().S.TargetEarning),
    RemoveTextAfterFocusLost = false,
    Flag        = "TargetEarning",
    Callback    = function(v)
        local n = tonumber(v)
        if n then
            getgenv().S.TargetEarning = n
            SettingsManager:Save()
            Notify("Target", "Target diubah ke Rp " .. Fmt(n), 4, "check")
        end
    end,
})

FarmTab:CreateInput({
    Name        = "⏱️ Delay Sebelum Rejoin (detik)",
    PlaceholderText = tostring(getgenv().S.DelayBeforeRejoin),
    RemoveTextAfterFocusLost = false,
    Flag        = "DelayRejoin",
    Callback    = function(v)
        local n = tonumber(v)
        if n then
            getgenv().S.DelayBeforeRejoin = n
            SettingsManager:Save()
        end
    end,
})

FarmTab:CreateToggle({
    Name         = "🔔 Countdown Notification",
    CurrentValue = getgenv().S.CountdownNotif,
    Flag         = "CdNotif",
    Callback     = function(v)
        getgenv().S.CountdownNotif = v
        SettingsManager:Save()
    end,
})

FarmTab:CreateToggle({
    Name         = "🙈 Sembunyikan UI Saat Farming",
    CurrentValue = false,
    Flag         = "HideUI",
    Callback     = function(v)
        getgenv().S.HideUI = v
        -- Rayfield minimize
        if v then
            pcall(function() Rayfield:Destroy() end)
        end
    end,
})

FarmTab:CreateDivider()
FarmTab:CreateSection("🚛 Auto-Farm Jawa Timur")

FarmTab:CreateToggle({
    Name         = "▶️ Mulai Truck Farm (Jawa Timur)",
    CurrentValue = false,
    Flag         = "TruckFarm",
    Callback     = function(v)
        getgenv().S.OnFarming = v
        getgenv().S.StopFarm  = not v
        SettingsManager:Save()

        if v then
            getgenv().Session.StartMoney      = GetMoney()
            getgenv().Session.FarmStartTime   = os.time()
            getgenv().Session.LastWebhookTime = 0
            Notify("Farming", "Auto-Farm Jawa Timur dimulai!\nTarget: Rp " .. Fmt(getgenv().S.TargetEarning), 5, "play")
            task.spawn(TruckFarmJawaTimur)
        else
            StopAllFarming(false)
            Notify("Farming", "Auto-Farm dihentikan.", 4, "stop")
        end
    end,
})

-- ╔══════════════════════════════╗
-- ║  TAB 3: SIDE JOBS           ║
-- ╚══════════════════════════════╝

local JobTab = Window:CreateTab("💼 Side Jobs", "briefcase")

JobTab:CreateSection("Pilih Pekerjaan")

local selectedJob = "Office Worker"
JobTab:CreateDropdown({
    Name    = "Pilih Job",
    Options = { "Office Worker", "Barista" },
    CurrentOption = { "Office Worker" },
    Flag    = "SelJob",
    Callback = function(opt)
        selectedJob = opt
        getgenv().S.SelectedJob = opt
        Notify("Job", "Job dipilih: " .. opt, 3, "info")
    end,
})

JobTab:CreateToggle({
    Name         = "▶️ Mulai Side Job Farm",
    CurrentValue = false,
    Flag         = "SideJobToggle",
    Callback     = function(v)
        if v then
            if not selectedJob then
                Notify("Error", "Pilih job terlebih dahulu!", 4, "alert")
                return
            end
            getgenv().S.StopFarm = false
            task.spawn(function() SideFarm(selectedJob) end)
            Notify("Side Job", "Memulai " .. selectedJob, 4, "play")
        else
            getgenv().S.StopFarm = true
            SettingsManager:Save()
            Notify("Side Job", "Side job dihentikan.", 4, "stop")
        end
    end,
})

-- ╔══════════════════════════════╗
-- ║  TAB 4: MAIN TOOLS          ║
-- ╚══════════════════════════════╝

local MainTab = Window:CreateTab("🔧 Tools", "wrench")

-- Vehicle Sniper
MainTab:CreateSection("🎯 Vehicle Sniper")

local limitedStock = RS:FindFirstChild("LimitedStock")
local vNames = {}
if limitedStock then
    for _, c in ipairs(limitedStock:GetChildren()) do
        table.insert(vNames, c.Name)
    end
end
if #vNames == 0 then vNames = { "(tidak ada limited stock)" } end

local selectedVehicle = vNames[1]
MainTab:CreateDropdown({
    Name    = "Pilih Kendaraan",
    Options = vNames,
    CurrentOption = { vNames[1] },
    Flag    = "SelVehicle",
    Callback = function(opt) selectedVehicle = opt end,
})

MainTab:CreateButton({
    Name     = "🛒 Beli Kendaraan Dipilih",
    Callback = function()
        if selectedVehicle then
            InvokeFunc("Dealership", "Buy", selectedVehicle)
            Notify("Vehicle", "Mencoba beli: " .. selectedVehicle, 4, "cart")
        end
    end,
})

MainTab:CreateButton({
    Name     = "🛒 Beli SEMUA Kendaraan",
    Callback = function()
        if limitedStock then
            for _, c in ipairs(limitedStock:GetChildren()) do
                InvokeFunc("Dealership", "Buy", c.Name)
                task.wait(0.3)
            end
            Notify("Vehicle", "Semua kendaraan dibeli!", 4, "check")
        end
    end,
})

-- Dealer & Shops
MainTab:CreateSection("🏪 Dealer & Toko")

local dealerNames   = {}
local dealerPrompts = {}
pcall(function()
    for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
        table.insert(dealerNames, d.Name)
        dealerPrompts[d.Name] = d:FindFirstChild("Prompt")
    end
end)
if #dealerNames == 0 then dealerNames = { "(tidak ada dealer)" } end

local selectedDealer = dealerNames[1]
MainTab:CreateDropdown({
    Name    = "Pilih Dealer",
    Options = dealerNames,
    CurrentOption = { dealerNames[1] },
    Flag    = "SelDealer",
    Callback = function(opt) selectedDealer = opt end,
})

MainTab:CreateButton({
    Name     = "🚪 Buka GUI Dealer",
    Callback = function()
        if selectedDealer then
            local p = dealerPrompts[selectedDealer]
            if p then
                pcall(fireproximityprompt, p)
                Notify("Dealer", "Membuka " .. selectedDealer, 3, "store")
            else
                Notify("Dealer", "Prompt tidak ditemukan.", 4, "alert")
            end
        end
    end,
})

MainTab:CreateButton({
    Name     = "🔓 Unlock Semua Toko",
    Callback = function()
        local count = UnlockAllShops()
        Notify("Shops", "Dibuka: " .. count .. " dealer/toko!", 5, "check")
    end,
})

-- Box Misc
MainTab:CreateSection("📦 Box")

MainTab:CreateButton({ Name = "Claim Box",    Callback = function() FireEvent("Box", "Claim")                   end })
MainTab:CreateButton({ Name = "Gamepass Box", Callback = function() FireEvent("Box", "Buy", "Gamepass Box")     end })
MainTab:CreateButton({ Name = "Limited Box",  Callback = function() FireEvent("Box", "Buy", "Limited Box")      end })

-- Car Slot
MainTab:CreateSection("🚗 Car Slot")
MainTab:CreateButton({
    Name     = "⬆️ Upgrade Slot",
    Callback = function() FireEvent("UpgradeStats", "CarSlot") end,
})

-- ╔══════════════════════════════╗
-- ║  TAB 5: DISCORD WEBHOOK     ║
-- ╚══════════════════════════════╝

local WebhookTab = Window:CreateTab("📡 Webhook", "bell")

WebhookTab:CreateSection("🔔 Discord Webhook Config")

WebhookTab:CreateParagraph({
    Title   = "Cara Pakai",
    Content = "1. Buat Webhook di server Discord kamu\n2. Copy URL webhook\n3. Paste di input di bawah\n4. Klik Save\n5. Log dikirim otomatis setiap 5-10 menit saat farming aktif",
})

WebhookTab:CreateInput({
    Name        = "Webhook URL",
    PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false,
    Flag        = "WebhookURL",
    Callback    = function(v)
        getgenv().S.WebhookURL = v
        SettingsManager:Save()
        Notify("Webhook", "URL disimpan!", 4, "check")
    end,
})

WebhookTab:CreateButton({
    Name     = "📤 Test Kirim Webhook",
    Callback = function()
        local backup = getgenv().S.OnFarming
        getgenv().S.OnFarming              = true
        getgenv().Session.StartMoney        = GetMoney() - 99999
        getgenv().Session.FarmStartTime     = os.time() - 300
        getgenv().Session.LastWebhookTime   = 0
        SendWebhook(false)
        getgenv().S.OnFarming = backup
        Notify("Webhook", "Test dikirim! Cek Discord kamu.", 5, "bell")
    end,
})

WebhookTab:CreateButton({
    Name     = "✅ Test Alert Target Reached",
    Callback = function()
        getgenv().Session.LastWebhookTime = 0
        SendWebhook(true)
        Notify("Webhook", "Alert TARGET REACHED dikirim!", 5, "check")
    end,
})

WebhookTab:CreateSection("📋 Info Embed")
WebhookTab:CreateParagraph({
    Title   = "Data yang Dikirim",
    Content = "✅ Username & UserID\n✅ Status Farming (Aktif / Target Reached)\n✅ Uang Saat Ini\n✅ Earned Sesi Ini\n✅ Progress Bar % ke Target\n✅ Durasi Sesi (menit)\n✅ Timestamp",
})
WebhookTab:CreateParagraph({
    Title   = "Interval",
    Content = "Min: " .. CONFIG.WebhookMinInterval/60 .. " menit\n" ..
              "Max: " .. CONFIG.WebhookMaxInterval/60 .. " menit\n" ..
              "(Acak, anti-spam aktif)",
})

-- ╔══════════════════════════════╗
-- ║  TAB 6: SETTINGS            ║
-- ╚══════════════════════════════╝

local SettTab = Window:CreateTab("⚙️ Settings", "settings")

SettTab:CreateSection("🔐 Private Server")

SettTab:CreateButton({
    Name     = "📋 Buat Private Code",
    Callback = function()
        FireEvent("PrivateServer", "Create")
        Notify("PS", "Membuat private code...", 4, "info")
    end,
})

SettTab:CreateButton({
    Name     = "🔗 Join PS (Jawa Timur)",
    Callback = function()
        pcall(function()
            local lbl = LP.PlayerGui.Hub.Container.Window.PrivateServer.ServerLabel
            if lbl and lbl.ContentText ~= "None" then
                FireEvent("PrivateServer", "Join", lbl.ContentText, "JawaTimur")
                Notify("PS", "Joining: " .. lbl.ContentText, 5, "link")
            else
                Notify("PS", "Private code tidak ditemukan. Buat dulu!", 5, "alert")
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

SettTab:CreateSection("ℹ️ Info")
SettTab:CreateParagraph({
    Title   = "Tentang Script",
    Content = "CDID Jawa Timur Edition\nVersi: " .. CONFIG.Version ..
              "\nUI Library: Rayfield\nCycle Delay: " .. CONFIG.CycleDelay .. "s" ..
              "\nTween Speed: " .. CONFIG.TweenSpeed,
})

-- ════════════════════════════════════════════════════════
-- [10] INIT — Startup
-- ════════════════════════════════════════════════════════

-- Anti-AFK aktif
StartAntiAFK()

-- Cek map
task.spawn(function()
    local ok, info = pcall(function()
        return MarketService:GetProductInfo(game.PlaceId)
    end)
    if ok and info then
        local name = info.Name or ""
        if name:find("Timur") or name:find("Car Driving") then
            Notify("✅ Map OK", "Terdeteksi: " .. name, 5, "check")
        else
            getgenv().S.OnFarming = false
            Notify("⚠️ Warning", "Kamu tidak di Jawa Timur!\nAuto-Farm dinonaktifkan.", 6, "alert")
        end
    end
end)

-- Auto-resume jika config menyimpan OnFarming = true
task.spawn(function()
    task.wait(3)
    if getgenv().S.OnFarming then
        getgenv().Session.StartMoney      = GetMoney()
        getgenv().Session.FarmStartTime   = os.time()
        getgenv().Session.LastWebhookTime = 0
        Notify("Auto-Resume", "Config ditemukan — melanjutkan farming!", 5, "play")
        UpdateStatus("♻️ Auto-resume dari config...")
        task.spawn(TruckFarmJawaTimur)
    end
end)

print("[CDID JawaTimur Rayfield] Loaded v" .. CONFIG.Version)
