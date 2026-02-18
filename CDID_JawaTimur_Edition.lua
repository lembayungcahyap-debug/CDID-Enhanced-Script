--[[
╔══════════════════════════════════════════════════════════════════════╗
║   CDID — Jawa Timur Edition  |  Rayfield UI  |  v5.0-WAYPOINT      ║
║                                                                      ║
║   FITUR UTAMA v5:                                                    ║
║   • 7 Waypoint Transit matematis antara Pickup → Delivery           ║
║   • SafeY offset (+3 stud) agar kendaraan tidak terbenam tanah      ║
║   • pcall di setiap perpindahan titik                               ║
║   • TweenService dengan kecepatan 49.5 stud/detik                  ║
║   • Anti-AFK + Coordinate Recorder                                  ║
║   • Discord Webhook smart reporting                                  ║
║   • Target Earning auto-stop                                         ║
║                                                                      ║
║   STRUKTUR                                                           ║
║   [1]  CONFIG       — Parameter & tabel rute                        ║
║   [2]  SETTINGS MGR — Simpan/muat config lokal                      ║
║   [3]  SERVICES     — Cache Roblox services                         ║
║   [4]  HELPERS      — Utiliti umum                                  ║
║   [5]  ANTI-AFK     — Cegah idle kick                              ║
║   [6]  WEBHOOK      — Discord log otomatis                          ║
║   [7]  FARMING      — Loop utama Truck Farm                         ║
║   [8]  SHOPS        — Unlock semua dealer/toko                      ║
║   [9]  UI RAYFIELD  — Semua tab & elemen                           ║
║   [10] INIT         — Startup tasks                                 ║
╚══════════════════════════════════════════════════════════════════════╝
]]

-- ════════════════════════════════════════════════════════════════════
-- [1] CONFIG
-- ════════════════════════════════════════════════════════════════════

local CFG = {

    -- ── Parameter Performa ──────────────────────────────────────────
    CycleDelay    = 0.2,    -- detik antar aksi dalam loop
    TeleportSpeed = 49.5,   -- stud/detik untuk kalkulasi durasi Tween
    WaitAtPoint   = 0.5,    -- task.wait di tiap titik (server sync)
    DelayRejoin   = 0.5,    -- jeda sebelum TeleportService rejoin
    CountdownSec  = 12,     -- countdown sebelum rute dimulai

    -- ── SafeY: offset ketinggian ────────────────────────────────────
    --   Ditambahkan ke setiap titik Y agar kendaraan tidak
    --   menancap ke dalam tanah/aspal saat PivotTo
    SafeY         = 3,

    -- ── Target Earning ──────────────────────────────────────────────
    TargetEarning = 500000,   -- 0 = tidak ada batas

    -- ── Discord Webhook ─────────────────────────────────────────────
    WebhookURL    = "",        -- ← ISI URL WEBHOOK DISCORD KAMU
    WHIntervalMin = 300,       -- 5 menit
    WHIntervalMax = 600,       -- 10 menit

    -- ── Identitas ───────────────────────────────────────────────────
    MapName  = "Jawa Timur",
    Version  = "5.0-WAYPOINT",
    Title    = "CDID Jawa Timur",
    Sub      = "Auto-Farm v5  |  7-Waypoint Transit",

    -- ════════════════════════════════════════════════════════════════
    --   TABEL RUTE TRUCK JAWA TIMUR
    --   ─────────────────────────────────────────────────────────────
    --   Titik dasar dari pengguna:
    --     Pickup A : Vector3( 34937.21,  135.64, -54576.89)
    --     Pickup B : Vector3( 35160.49,  135.64, -54682.41)
    --     Delivery : Vector3( -7845.77,  387.62,  46864.57)
    --
    --   Waypoint transit dihitung secara MATEMATIS dengan interpolasi
    --   linear antara Pickup B dan Delivery, kemudian ketinggian Y
    --   dinaikkan secara bertahap untuk melewati dataran tinggi
    --   di tengah map Jawa Timur (estimasi puncak ~450 stud).
    --
    --   SafeY (+3) ditambahkan otomatis di fungsi TweenCar,
    --   sehingga nilai Y di tabel ini adalah posisi "target bersih".
    --
    --   Rumus interpolasi:
    --     pos(t) = PB + t * (D - PB),   t ∈ [0, 1]
    --     t_values = {1/8, 2/8, 3/8, 4/8, 5/8, 6/8, 7/8}
    --
    --   Hasil interpolasi XZ:
    --     Pickup B  : ( 35160.49, -54682.41)
    --     Delivery  : ( -7845.77,  46864.57)
    --     Delta XZ  : (-43006.26, 101546.98)
    --
    --   Kurva Y (naik-turun melewati puncak di t=0.5):
    --     t=1/8  → Y=180  (mulai naik dari daratan rendah)
    --     t=2/8  → Y=280  (naik mendekati perbukitan)
    --     t=3/8  → Y=400  (mendekati area pegunungan)
    --     t=4/8  → Y=450  (puncak — titik tengah rute)
    --     t=5/8  → Y=420  (mulai turun dari pegunungan)
    --     t=6/8  → Y=350  (dataran menengah sisi barat)
    --     t=7/8  → Y=390  (mendekati elevasi Delivery 387.62)
    -- ════════════════════════════════════════════════════════════════

    TruckRoute = {

        -- ── Titik 1: Pickup A ──────────────────────────────────────
        {
            label  = "📦 Pickup A — Gudang Utama",
            pos    = Vector3.new(34937.21, 135.64, -54576.89),
            action = "pickup",
        },

        -- ── Titik 2: Pickup B ──────────────────────────────────────
        {
            label  = "📦 Pickup B — Gudang Cadangan",
            pos    = Vector3.new(35160.49, 135.64, -54682.41),
            action = "pickup",
        },

        -- ── Titik 3: Transit 1/7 ── t=1/8 ─────────────────────────
        --   X = 35160.49 + (1/8) * (-43006.26) = 29784.71
        --   Z = -54682.41 + (1/8) * (101546.98) = -41489.54
        --   Y = 180 (naik dari 135 menuju perbukitan)
        {
            label  = "🛣️  Transit 1/7 — Lereng Timur",
            pos    = Vector3.new(29784.71, 180.00, -41489.54),
            action = "transit",
        },

        -- ── Titik 4: Transit 2/7 ── t=2/8 ─────────────────────────
        --   X = 35160.49 + (2/8) * (-43006.26) = 24408.94
        --   Z = -54682.41 + (2/8) * (101546.98) = -28296.66
        --   Y = 280 (perbukitan mulai terasa)
        {
            label  = "🛣️  Transit 2/7 — Perbukitan Tengah",
            pos    = Vector3.new(24408.94, 280.00, -28296.66),
            action = "transit",
        },

        -- ── Titik 5: Transit 3/7 ── t=3/8 ─────────────────────────
        --   X = 35160.49 + (3/8) * (-43006.26) = 19033.16
        --   Z = -54682.41 + (3/8) * (101546.98) = -15103.79
        --   Y = 400 (mendekati pegunungan utama)
        {
            label  = "🛣️  Transit 3/7 — Kaki Pegunungan",
            pos    = Vector3.new(19033.16, 400.00, -15103.79),
            action = "transit",
        },

        -- ── Titik 6: Transit 4/7 ── t=4/8 (PUNCAK) ───────────────
        --   X = 35160.49 + (4/8) * (-43006.26) = 13657.36
        --   Z = -54682.41 + (4/8) * (101546.98) =  -1910.92
        --   Y = 450 (titik tertinggi — melewati puncak)
        {
            label  = "⛰️  Transit 4/7 — PUNCAK LINTASAN",
            pos    = Vector3.new(13657.36, 450.00, -1910.92),
            action = "transit",
        },

        -- ── Titik 7: Transit 5/7 ── t=5/8 ─────────────────────────
        --   X = 35160.49 + (5/8) * (-43006.26) =  8281.57
        --   Z = -54682.41 + (5/8) * (101546.98) =  11281.95
        --   Y = 420 (turun dari puncak, masih tinggi)
        {
            label  = "🛣️  Transit 5/7 — Turunan Barat",
            pos    = Vector3.new(8281.57, 420.00, 11281.95),
            action = "transit",
        },

        -- ── Titik 8: Transit 6/7 ── t=6/8 ─────────────────────────
        --   X = 35160.49 + (6/8) * (-43006.26) =  2905.79
        --   Z = -54682.41 + (6/8) * (101546.98) =  24474.83
        --   Y = 350 (dataran menengah sisi barat)
        {
            label  = "🛣️  Transit 6/7 — Dataran Barat Tengah",
            pos    = Vector3.new(2905.79, 350.00, 24474.83),
            action = "transit",
        },

        -- ── Titik 9: Transit 7/7 ── t=7/8 ─────────────────────────
        --   X = 35160.49 + (7/8) * (-43006.26) = -2470.00
        --   Z = -54682.41 + (7/8) * (101546.98) =  37667.70
        --   Y = 390 (mendekati elevasi titik delivery 387.62)
        {
            label  = "🛣️  Transit 7/7 — Prapengiriman",
            pos    = Vector3.new(-2470.00, 390.00, 37667.70),
            action = "transit",
        },

        -- ── Titik 10: Delivery ─────────────────────────────────────
        {
            label  = "🏁 Delivery — Tujuan Akhir",
            pos    = Vector3.new(-7845.77, 387.62, 46864.57),
            action = "deliver",
        },
    },

    -- Keyword waypoint valid Jawa Timur
    WaypointKeywords = {
        "Timur", "Surabaya", "Malang", "Jember",
        "Banyuwangi", "Pasuruan", "Kediri", "Mojokerto",
    },
}

-- ════════════════════════════════════════════════════════════════════
-- [2] SETTINGS MANAGER
-- ════════════════════════════════════════════════════════════════════

local SM = {
    Dir      = "CDID_JT5",
    File     = "CDID_JT5\\cfg.json",
    LastSave = 0,
    Cooldown = 1,
}

getgenv().GS = getgenv().GS or {
    OnFarming     = false,
    StopFarm      = false,
    InfJump       = false,
    CdNotif       = false,
    TargetEarning = CFG.TargetEarning,
    WebhookURL    = CFG.WebhookURL,
    DelayRejoin   = CFG.DelayRejoin,
    SelectedJob   = "Office Worker",
}

getgenv().SS = getgenv().SS or {
    StartMoney  = 0,
    FarmStart   = 0,
    LastWebhook = 0,
}

function SM:Init()
    self.HS = game:GetService("HttpService")
    pcall(function()
        if not isfolder(self.Dir) then makefolder(self.Dir) end
    end)
    if not self:Load() then self:Save(true) end
end

function SM:Save(force)
    if not writefile then return end
    local now = os.time()
    if not force and (now - self.LastSave) < self.Cooldown then return end
    pcall(function()
        writefile(
            self.File,
            self.HS:JSONEncode({ v = CFG.Version, s = getgenv().GS })
        )
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
                    if getgenv().GS[k] ~= nil then
                        getgenv().GS[k] = v
                    end
                end
            end
        end
    end)
    return ok
end

SM:Init()

-- ════════════════════════════════════════════════════════════════════
-- [3] SERVICES
-- ════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local TwnSvc  = game:GetService("TweenService")
local RunSvc  = game:GetService("RunService")
local UIS     = game:GetService("UserInputService")
local TelSvc  = game:GetService("TeleportService")
local HttpSvc = game:GetService("HttpService")
local MktSvc  = game:GetService("MarketplaceService")
local GuiSvc  = game:GetService("GuiService")
local VIM     = game:GetService("VirtualInputManager")

local LP      = Players.LocalPlayer

-- Network (diisi setelah game load)
local NetEvents, NetFuncs

local function CacheNetwork()
    pcall(function()
        local nc = RS:WaitForChild("NetworkContainer", 25)
        if nc then
            NetEvents = nc:FindFirstChild("RemoteEvents")
            NetFuncs  = nc:FindFirstChild("RemoteFunctions")
        end
    end)
end

-- ════════════════════════════════════════════════════════════════════
-- [4] HELPERS
-- ════════════════════════════════════════════════════════════════════

-- Safe FireServer
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

-- Hitung durasi tween dari jarak dan TeleportSpeed
local function TweenDur(from, to)
    local dist = (Vector3.new(from.X, 0, from.Z) - Vector3.new(to.X, 0, to.Z)).Magnitude
    return math.clamp(dist / CFG.TeleportSpeed, 0.5, 8.0)
end

-- Tween karakter ke posisi
local function TweenChar(targetPos)
    pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local dur = TweenDur(hrp.Position, targetPos)
        TwnSvc:Create(
            hrp,
            TweenInfo.new(dur, Enum.EasingStyle.Linear),
            { CFrame = CFrame.new(targetPos) }
        ):Play()
        task.wait(dur + CFG.WaitAtPoint)
    end)
end

-- ── TweenCar: Teleport kendaraan dengan SafeY offset ────────────
--   SafeY ditambahkan ke Y tujuan agar kendaraan tidak menancap
--   ke dalam tanah setelah PivotTo.
--   Semua error ditangkap dengan pcall agar tidak crash.
local function TweenCar(car, targetPos)
    local ok, err = pcall(function()
        -- Validasi model kendaraan
        if not car then
            warn("[TweenCar] car nil")
            return false
        end
        if not car.PrimaryPart then
            warn("[TweenCar] PrimaryPart nil")
            return false
        end

        -- Terapkan SafeY offset
        local safePos = Vector3.new(
            targetPos.X,
            targetPos.Y + CFG.SafeY,
            targetPos.Z
        )

        -- Rotasi kendaraan tetap dipertahankan dari posisi saat ini
        local currentCF  = car.PrimaryPart.CFrame
        local rotation   = currentCF - currentCF.Position   -- ambil komponen rotasi
        local destCF     = CFrame.new(safePos) * rotation

        -- Matikan 3D render sebentar (mengurangi visual glitch)
        RunSvc:Set3dRenderingEnabled(false)
        task.wait(0.15)

        car:PivotTo(destCF)

        task.wait(0.15)
        RunSvc:Set3dRenderingEnabled(true)

        -- Tunggu server sync
        task.wait(CFG.WaitAtPoint)
        return true
    end)

    if not ok then
        warn("[TweenCar] Error:", err)
        -- Pastikan rendering kembali normal meski error
        pcall(function() RunSvc:Set3dRenderingEnabled(true) end)
        return false
    end
    return true
end

-- Cek apakah pemain di dalam kendaraan
local function InVehicle()
    local ok, r = pcall(function()
        local hum = LP.Character
                 and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end)
    return ok and r
end

-- Cari kendaraan milik pemain
local function FindCar()
    local v = workspace:FindFirstChild("Vehicles")
    return v and v:FindFirstChild(LP.Name .. "sCar")
end

-- Baca uang dari GUI
local function GetMoney()
    local ok, v = pcall(function()
        local t = LP.PlayerGui.Main.Container.Hub
                    .CashFrame.Frame.TextLabel.Text
        return tonumber(t:gsub("[^%d]", "")) or 0
    end)
    return (ok and v) or 0
end

-- Format angka: 1234567 → "1.234.567"
local function Fmt(n)
    if not n then return "0" end
    return tostring(math.floor(n))
           :reverse()
           :gsub("(%d%d%d)", "%1.")
           :reverse()
           :gsub("^%.", "")
end

-- Progress bar ASCII
local function PBar(cur, tgt, w)
    w = w or 18
    if not tgt or tgt <= 0 then return "[ ∞ Tidak Ada Batas ]", 0 end
    local p = math.min(cur / tgt, 1)
    local f = math.floor(p * w)
    return string.format(
        "[%s%s] %.1f%%",
        string.rep("█", f),
        string.rep("░", w - f),
        p * 100
    ), p * 100
end

-- Cek keyword waypoint Jawa Timur
local function IsJTWaypoint(txt)
    if not txt then return false end
    for _, kw in ipairs(CFG.WaypointKeywords) do
        if txt:find(kw) then return true end
    end
    return false
end

-- Rekam koordinat posisi saat ini
local function RecordCoord()
    local ok, result = pcall(function()
        local hrp = LP.Character
                 and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return "Karakter tidak ditemukan." end
        local p = hrp.Position
        return string.format(
            "Vector3.new(%.2f, %.2f, %.2f)",
            p.X, p.Y, p.Z
        )
    end)
    return ok and result or "Error saat rekam koordinat."
end

-- ════════════════════════════════════════════════════════════════════
-- [5] ANTI-AFK
-- ════════════════════════════════════════════════════════════════════

local _afkConn

local function StartAntiAFK()
    if _afkConn then
        pcall(function() _afkConn:Disconnect() end)
    end

    _afkConn = LP.Idled:Connect(function()
        pcall(function()
            local keys = { "W", "A", "S", "D" }
            local k    = keys[math.random(1, #keys)]
            VIM:SendKeyEvent(true,  k, false, game)
            task.wait(math.random() * 0.2 + 0.05)
            VIM:SendKeyEvent(false, k, false, game)
            VIM:SendMouseMoveEvent(
                math.random(-40, 40),
                math.random(-40, 40),
                game
            )
        end)
    end)

    -- Reconnect setelah respawn
    LP.CharacterAdded:Once(function()
        task.wait(2)
        StartAntiAFK()
    end)
end

-- ════════════════════════════════════════════════════════════════════
-- [6] DISCORD WEBHOOK
-- ════════════════════════════════════════════════════════════════════

local function SendWebhook(isTargetReached)
    local url = getgenv().GS.WebhookURL or ""
    if url == "" then return end
    if not getgenv().GS.OnFarming and not isTargetReached then return end

    local now = os.time()
    if not isTargetReached then
        if (now - getgenv().SS.LastWebhook) < CFG.WHIntervalMin then return end
    end
    getgenv().SS.LastWebhook = now

    local money   = GetMoney()
    local earned  = math.max(0, money - getgenv().SS.StartMoney)
    local tgt     = getgenv().GS.TargetEarning or 0
    local bar, _  = PBar(earned, tgt)
    local elapsed = math.floor((now - getgenv().SS.FarmStart) / 60)
    local status  = isTargetReached and "✅ TARGET REACHED" or "🟢 Farming Aktif"
    local color   = isTargetReached and 5832543 or 3066993

    local payload = {
        embeds = {{
            title = isTargetReached
                and "✅ TARGET EARNING TERCAPAI!"
                or  "📊 CDID Farm Log — Jawa Timur",
            color = color,
            description = string.format("**%s**  (`%d`)", LP.Name, LP.UserId),
            fields = {
                { name = "⚡ Status",      value = status,             inline = true  },
                { name = "🗺️ Map",         value = CFG.MapName,        inline = true  },
                { name = "⏱️ Durasi",      value = elapsed.." menit",  inline = true  },
                { name = "💰 Uang",        value = "Rp "..Fmt(money),  inline = true  },
                { name = "📈 Earned",      value = "Rp "..Fmt(earned), inline = true  },
                { name = "🎯 Target",
                  value = tgt > 0 and "Rp "..Fmt(tgt) or "Tidak Ada",
                  inline = true },
                { name = "📊 Progress",
                  value = "```\n"..bar.."\n```",
                  inline = false },
            },
            footer = {
                text = "CDID v"..CFG.Version.."  |  "..os.date("%d/%m %H:%M")
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

-- Background webhook timer
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

-- ════════════════════════════════════════════════════════════════════
-- [7] FARMING ENGINE
-- ════════════════════════════════════════════════════════════════════

-- Forward-declare (diisi setelah UI terbuat)
local _setStatus = function(_) end
local _setStep   = function(_) end

local function SetStatus(txt)
    pcall(_setStatus, txt)
    print("[CDID]", txt)
end

local function SetStep(txt)
    pcall(_setStep, txt)
end

-- ── 7a. Stop semua farming ────────────────────────────────────────

local function StopAll(sendAlert)
    getgenv().GS.OnFarming = false
    getgenv().GS.StopFarm  = true
    SM:Save()
    pcall(function() Fire("Engine", "Off") end)
    SetStatus("⏹️ Farming dihentikan.")
    if sendAlert then
        task.spawn(function() pcall(SendWebhook, true) end)
    end
end

-- ── 7b. Cek target earning ────────────────────────────────────────

local function CheckTarget()
    local tgt = getgenv().GS.TargetEarning or 0
    if tgt <= 0 then return false end
    if (GetMoney() - getgenv().SS.StartMoney) >= tgt then
        StopAll(true)
        return true
    end
    return false
end

-- ── 7c. Spawn kendaraan & duduk ───────────────────────────────────

local function SpawnAndSit()
    local function PressF()
        VIM:SendKeyEvent(true,  "F", false, game)
        task.wait(0.2)
        VIM:SendKeyEvent(false, "F", false, game)
    end

    SetStatus("🔑 Spawn kendaraan...")
    PressF()
    task.wait(4)

    local car
    for _ = 1, 15 do
        car = FindCar()
        if car then break end
        PressF()
        task.wait(0.8)
    end

    if not car then
        warn("[SpawnAndSit] Kendaraan tidak muncul setelah 15 percobaan.")
        return nil
    end

    local seat = car:FindFirstChild("DriveSeat")
    if not seat then
        warn("[SpawnAndSit] DriveSeat nil.")
        return nil
    end

    SetStatus("🪑 Duduk di kendaraan...")
    pcall(function() seat:Sit(LP.Character.Humanoid) end)
    task.wait(1.2)

    for _ = 1, 12 do
        if InVehicle() then break end
        pcall(function() seat:Sit(LP.Character.Humanoid) end)
        task.wait(0.4)
    end

    if not InVehicle() then
        warn("[SpawnAndSit] Gagal duduk setelah 12 percobaan.")
        return nil
    end

    return car
end

-- ── 7d. LOOP UTAMA: Truck Farm ────────────────────────────────────

local function TruckFarm()
    while task.wait(CFG.CycleDelay) do
        if not getgenv().GS.OnFarming then break end
        if CheckTarget() then break end

        -- Setiap cycle dibungkus pcall — crash satu cycle ≠ crash script
        local cycleOk, cycleErr = pcall(function()

            -- STEP 1: Ambil job Truck ─────────────────────────────
            SetStatus("📋 Mengambil job Truck...")
            Fire("Job", "Truck")
            task.wait(0.8)

            -- STEP 2: Validasi waypoint Jawa Timur ────────────────
            local wpFolder = workspace.Etc
                          and workspace.Etc:FindFirstChild("Waypoint")
            local waypoint = wpFolder
                          and wpFolder:FindFirstChild("Waypoint")

            if not waypoint then
                for _ = 1, 15 do
                    task.wait(0.5)
                    Fire("Job", "Truck")
                    wpFolder = workspace.Etc
                            and workspace.Etc:FindFirstChild("Waypoint")
                    waypoint = wpFolder
                            and wpFolder:FindFirstChild("Waypoint")
                    if waypoint then break end
                end
            end

            if not waypoint then
                SetStatus("⚠️ Waypoint tidak ada — skip cycle.")
                return
            end

            local billboard = waypoint:FindFirstChildWhichIsA("BillboardGui", true)
            local wLabel    = billboard
                           and billboard:FindFirstChildWhichIsA("TextLabel", true)
            local labelText = wLabel and wLabel.Text or ""

            local attempt = 0
            while not IsJTWaypoint(labelText) and getgenv().GS.OnFarming do
                attempt = attempt + 1
                if attempt > 25 then
                    SetStatus("⚠️ Waypoint JT tidak muncul — skip cycle.")
                    return
                end
                pcall(function()
                    LP.Character.HumanoidRootPart.Anchored = true
                end)
                Fire("Job", "Truck")
                pcall(fireproximityprompt,
                    workspace.Etc.Job.Truck.Starter.Prompt)
                task.wait(0.8)
                pcall(function()
                    LP.Character.HumanoidRootPart.Anchored = false
                end)
                labelText = wLabel and wLabel.Text or ""
            end

            if not getgenv().GS.OnFarming then return end
            pcall(function()
                LP.Character.HumanoidRootPart.Anchored = false
            end)
            SetStatus("✅ Waypoint valid: " .. labelText)

            -- STEP 3: Spawn & duduk di kendaraan ──────────────────
            local car = SpawnAndSit()
            if not car then
                SetStatus("❌ Kendaraan gagal siap — retry cycle.")
                return
            end

            -- STEP 4: Countdown ────────────────────────────────────
            for i = CFG.CountdownSec, 1, -1 do
                if not getgenv().GS.OnFarming then return end
                if CheckTarget() then return end
                SetStatus(string.format("⏳ Rute mulai dalam %ds...", i))
                task.wait(1)
            end

            -- STEP 5: Jalankan rute waypoint ──────────────────────
            --
            --   Setiap perpindahan titik dibungkus pcall tersendiri.
            --   Jika lag/kendaraan hilang di satu titik, titik
            --   berikutnya tetap dicoba (tidak langsung return).
            --
            local totalPoints = #CFG.TruckRoute
            local failCount   = 0

            for idx, point in ipairs(CFG.TruckRoute) do
                if not getgenv().GS.OnFarming then break end
                if CheckTarget() then break end

                SetStatus(string.format(
                    "🚛 [%d/%d] %s",
                    idx, totalPoints, point.label
                ))
                SetStep(string.format(
                    "Titik %d/%d  |  Y=%d  |  Aksi: %s",
                    idx, totalPoints,
                    math.floor(point.pos.Y + CFG.SafeY),
                    point.action
                ))

                -- Cek kendaraan masih ada sebelum teleport
                local currentCar = FindCar()
                if not currentCar then
                    -- Coba spawn ulang sekali
                    SetStatus("⚠️ Kendaraan hilang — spawn ulang...")
                    currentCar = SpawnAndSit()
                    if not currentCar then
                        failCount = failCount + 1
                        warn(string.format(
                            "[TruckFarm] Kendaraan hilang di titik %d, skip titik ini.", idx
                        ))
                        -- Tidak langsung return — coba titik berikutnya
                        task.wait(1)
                        goto continue
                    end
                    car = currentCar
                end

                -- Cek apakah pemain masih duduk
                if not InVehicle() then
                    SetStatus("⚠️ Pemain keluar kendaraan — coba duduk ulang...")
                    local seat = car and car:FindFirstChild("DriveSeat")
                    if seat then
                        pcall(function() seat:Sit(LP.Character.Humanoid) end)
                        task.wait(0.8)
                    end
                    if not InVehicle() then
                        failCount = failCount + 1
                        warn(string.format(
                            "[TruckFarm] Tidak bisa duduk di titik %d, skip.", idx
                        ))
                        task.wait(1)
                        goto continue
                    end
                end

                -- Teleport kendaraan ke titik ini (pcall internal di TweenCar)
                local teleOk = TweenCar(car, point.pos)
                if not teleOk then
                    failCount = failCount + 1
                    warn(string.format(
                        "[TruckFarm] TweenCar gagal di titik %d, lanjut ke berikutnya.", idx
                    ))
                end

                -- Aksi spesifik per tipe titik
                if point.action == "pickup" then
                    -- Cari ProximityPrompt dalam radius 25 stud
                    pcall(function()
                        local safePos = Vector3.new(
                            point.pos.X, point.pos.Y + CFG.SafeY, point.pos.Z
                        )
                        local parts = workspace:GetPartBoundsInBox(
                            CFrame.new(safePos),
                            Vector3.new(25, 12, 25)
                        )
                        for _, obj in ipairs(parts) do
                            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                                    or (obj.Parent and
                                        obj.Parent:FindFirstChildOfClass("ProximityPrompt"))
                            if pp then
                                fireproximityprompt(pp)
                                task.wait(0.3)
                            end
                        end
                    end)
                    SetStatus("📦 Pickup selesai: " .. point.label)

                elseif point.action == "transit" then
                    -- Tidak perlu aksi khusus, hanya lewat
                    SetStatus("🛣️  Melewati " .. point.label)

                elseif point.action == "deliver" then
                    -- Fire job + cari prompt delivery
                    Fire("Job", "Truck")
                    pcall(function()
                        local safePos = Vector3.new(
                            point.pos.X, point.pos.Y + CFG.SafeY, point.pos.Z
                        )
                        local parts = workspace:GetPartBoundsInBox(
                            CFrame.new(safePos),
                            Vector3.new(35, 15, 35)
                        )
                        for _, obj in ipairs(parts) do
                            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                                    or (obj.Parent and
                                        obj.Parent:FindFirstChildOfClass("ProximityPrompt"))
                            if pp then
                                fireproximityprompt(pp)
                                task.wait(0.3)
                            end
                        end
                    end)
                    SetStatus("🏁 Delivery selesai! Menunggu reward...")
                    task.wait(2)
                end

                ::continue::
                task.wait(CFG.CycleDelay)
            end

            -- STEP 6: Laporan siklus selesai ──────────────────────
            if failCount > 0 then
                SetStatus(string.format(
                    "⚠️ Siklus selesai dengan %d titik gagal. Rejoin...",
                    failCount
                ))
            else
                SetStatus("✅ Rute selesai! Rejoin server...")
            end

            -- STEP 7: Rejoin ───────────────────────────────────────
            Fire("Job", "Truck")
            task.wait(getgenv().GS.DelayRejoin or CFG.DelayRejoin)
            pcall(function()
                TelSvc:Teleport(game.PlaceId, LP)
            end)
            task.wait(90)
        end)

        if not cycleOk then
            warn("[TruckFarm] Cycle-level error:", cycleErr)
            SetStatus("⚠️ Cycle error — retry 3 detik...")
            pcall(function() RunSvc:Set3dRenderingEnabled(true) end)
            task.wait(3)
        end
    end

    SetStatus("⏹️ Truck farm loop selesai.")
end

-- ── 7e. Side Jobs ─────────────────────────────────────────────────

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
            local ans = op == "+" and (n1 + n2) or (n1 - n2)
            local str = tostring(math.floor(ans))
            box.Text = str
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
            LP.Character.HumanoidRootPart.CFrame =
                CFrame.new(-38581, 1039, -62763)
        end)
        task.wait(1)
        for _ = 1, 8 do
            pcall(fireproximityprompt,
                workspace.Etc.Job.Office.Starter.Prompt)
        end
        repeat
            task.wait(CFG.CycleDelay)
            QuestOffice()
        until getgenv().GS.StopFarm

    elseif jobName == "Barista" then
        Fire("Job", "JanjiJiwa")
        task.spawn(function()
            local pickup  = Vector3.new(-13716.35, 1052.89, -17997.70)
            local dropoff = Vector3.new(-13723.75, 1052.89, -17994.23)
            while task.wait(CFG.CycleDelay) and not getgenv().GS.StopFarm do
                pcall(function()
                    fireproximityprompt(
                        workspace.Etc.Job.JanjiJiwa.Starter.Prompt)
                    LP.Character.HumanoidRootPart.CFrame =
                        CFrame.new(pickup)
                    task.wait(15)
                    if LP.Backpack:FindFirstChild("Coffee") then
                        LP.Character.HumanoidRootPart.CFrame =
                            CFrame.new(dropoff)
                        Fire("JanjiJiwa", "Delivery")
                    end
                    LP.Character.HumanoidRootPart.CFrame =
                        CFrame.new(pickup)
                end)
            end
        end)
    end
end

-- ════════════════════════════════════════════════════════════════════
-- [8] UNLOCK SHOPS
-- ════════════════════════════════════════════════════════════════════

local function UnlockShops()
    local n = 0
    pcall(function()
        for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
            local p = d:FindFirstChild("Prompt")
            if p then
                fireproximityprompt(p)
                n = n + 1
                task.wait(0.2)
            end
        end
    end)
    for _, s in ipairs({
        "KiosMarket", "Minimarket", "SpeedShop", "TuningShop", "FuelStation"
    }) do
        pcall(Fire, "OpenShop", s)
        task.wait(0.15)
    end
    return n
end

-- ════════════════════════════════════════════════════════════════════
-- [9] UI — RAYFIELD
-- ════════════════════════════════════════════════════════════════════

-- Tunggu game & karakter fully loaded
repeat task.wait(0.1)
until game:IsLoaded()
   and LP
   and LP.Character
   and LP.Character:FindFirstChild("HumanoidRootPart")

-- ── Load Rayfield ─────────────────────────────────────────────────
local Rayfield
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
        print("[CDID] Rayfield loaded:", url)
        break
    end
    warn("[CDID] Gagal dari:", url)
    task.wait(1)
end

-- Fallback error screen
if not Rayfield then
    pcall(function()
        local sg = Instance.new("ScreenGui", LP.PlayerGui)
        sg.Name = "CDIDErr"
        sg.ResetOnSpawn = false
        local fr = Instance.new("Frame", sg)
        fr.Size = UDim2.fromOffset(440, 90)
        fr.Position = UDim2.fromScale(0.5, 0.05)
        fr.AnchorPoint = Vector2.new(0.5, 0)
        fr.BackgroundColor3 = Color3.fromRGB(170, 30, 30)
        Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 8)
        local lbl = Instance.new("TextLabel", fr)
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Text = "❌ CDID: Gagal load Rayfield!\nAktifkan HTTP Request di executor."
        lbl.TextColor3 = Color3.new(1, 1, 1)
        lbl.TextScaled = true
        lbl.Font = Enum.Font.GothamBold
    end)
    error("[CDID] FATAL — Rayfield tidak dapat dimuat dari semua URL.")
end

CacheNetwork()

-- ── Buat Window ───────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name             = CFG.Title,
    LoadingTitle     = CFG.Title,
    LoadingSubtitle  = CFG.Sub,
    ConfigurationSaving = {
        Enabled  = true,
        FileName = "CDID_JT5",
    },
    Discord   = { Enabled = false },
    KeySystem = false,
})

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
HomeTab:CreateLabel("👤 " .. LP.Name .. "   🆔 " .. tostring(LP.UserId))
HomeTab:CreateLabel("🗺️ " .. CFG.MapName ..
                    "   ⚡ " .. CFG.TeleportSpeed .. " stud/s" ..
                    "   🛡️ SafeY +" .. CFG.SafeY)

HomeTab:CreateDivider()
HomeTab:CreateSection("Karakter")

HomeTab:CreateSlider({
    Name         = "Walk Speed",
    Range        = { 2, 250 },
    Increment    = 1,
    Suffix       = " stud/s",
    CurrentValue = 16,
    Flag         = "WalkSpeed",
    Callback     = function(v)
        pcall(function() LP.Character.Humanoid.WalkSpeed = v end)
    end,
})

HomeTab:CreateSlider({
    Name         = "Jump Power",
    Range        = { 2, 200 },
    Increment    = 1,
    CurrentValue = 50,
    Flag         = "JumpPower",
    Callback     = function(v)
        pcall(function() LP.Character.Humanoid.JumpHeight = v end)
    end,
})

HomeTab:CreateToggle({
    Name         = "Infinite Jump",
    CurrentValue = false,
    Flag         = "InfJump",
    Callback     = function(v) getgenv().GS.InfJump = v end,
})

UIS.JumpRequest:Connect(function()
    if getgenv().GS.InfJump then
        pcall(function()
            LP.Character:FindFirstChildOfClass("Humanoid")
                        :ChangeState("Jumping")
        end)
    end
end)

HomeTab:CreateToggle({
    Name         = "No Clip",
    CurrentValue = false,
    Flag         = "NoClip",
    Callback     = function(v)
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
    Callback     = function(v)
        UIS.InputBegan:Connect(function(inp)
            if not v then return end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl)
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

-- ╔══════════════════════════════════════╗
-- ║  TAB 2 — FARMING                    ║
-- ╚══════════════════════════════════════╝

local FarmTab = Window:CreateTab("🚛 Farming", "truck")

FarmTab:CreateSection("📊 Status Real-Time")

local statusPara = FarmTab:CreateParagraph({
    Title   = "Status",
    Content = "Belum dimulai.",
})
local stepPara = FarmTab:CreateParagraph({
    Title   = "Titik Aktif",
    Content = "—",
})
local moneyPara = FarmTab:CreateParagraph({
    Title   = "Uang & Progress",
    Content = "Rp 0",
})

-- Hubungkan updater
_setStatus = function(txt)
    pcall(function()
        statusPara:Set({ Title = "Status", Content = txt })
    end)
end
_setStep = function(txt)
    pcall(function()
        stepPara:Set({ Title = "Titik Aktif", Content = txt })
    end)
end

-- Refresh uang setiap 2 detik
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
FarmTab:CreateSection("📍 Rute Aktif  (" .. #CFG.TruckRoute .. " titik)")

-- Tampilkan ringkasan rute
local routeLines = {}
for i, pt in ipairs(CFG.TruckRoute) do
    table.insert(routeLines, string.format(
        "[%d] %s\n     Y-target: %d (+%d SafeY = %d)",
        i, pt.label,
        math.floor(pt.pos.Y),
        CFG.SafeY,
        math.floor(pt.pos.Y + CFG.SafeY)
    ))
end
FarmTab:CreateParagraph({
    Title   = "Daftar Titik",
    Content = table.concat(routeLines, "\n\n"),
})

FarmTab:CreateDivider()
FarmTab:CreateSection("⚙️ Konfigurasi")

FarmTab:CreateInput({
    Name            = "🎯 Target Earning  (Rp, 0 = tidak ada batas)",
    PlaceholderText = tostring(getgenv().GS.TargetEarning),
    RemoveTextAfterFocusLost = false,
    Flag            = "TargetInput",
    Callback        = function(v)
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
    Callback        = function(v)
        local n = tonumber(v)
        if n then getgenv().GS.DelayRejoin = n; SM:Save() end
    end,
})

FarmTab:CreateDivider()
FarmTab:CreateSection("▶️ Kontrol")

FarmTab:CreateToggle({
    Name         = "🚛  Mulai Truck Farm  (Jawa Timur — 10 Titik)",
    CurrentValue = false,
    Flag         = "TruckToggle",
    Callback     = function(v)
        getgenv().GS.OnFarming = v
        getgenv().GS.StopFarm  = not v
        SM:Save()

        if v then
            getgenv().SS.StartMoney  = GetMoney()
            getgenv().SS.FarmStart   = os.time()
            getgenv().SS.LastWebhook = 0
            Notif(
                "Farming",
                "▶️ Truck Farm Jawa Timur dimulai!\n" ..
                "10 titik  |  SafeY+" .. CFG.SafeY ..
                "  |  Target: Rp " .. Fmt(getgenv().GS.TargetEarning),
                6, "play"
            )
            task.spawn(TruckFarm)
        else
            StopAll(false)
            Notif("Farming", "⏹️ Farming dihentikan.", 4, "stop")
        end
    end,
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 3 — SIDE JOBS                  ║
-- ╚══════════════════════════════════════╝

local JobTab = Window:CreateTab("💼 Side Jobs", "briefcase")

JobTab:CreateSection("Pilih Pekerjaan")

local _selJob = getgenv().GS.SelectedJob or "Office Worker"
JobTab:CreateDropdown({
    Name          = "Job",
    Options       = { "Office Worker", "Barista" },
    CurrentOption = { _selJob },
    Flag          = "JobDD",
    Callback      = function(opt)
        _selJob = opt
        getgenv().GS.SelectedJob = opt
        SM:Save()
        Notif("Job", "Dipilih: " .. opt, 3, "info")
    end,
})

JobTab:CreateToggle({
    Name         = "▶️  Mulai Side Job",
    CurrentValue = false,
    Flag         = "SideJobToggle",
    Callback     = function(v)
        if v then
            getgenv().GS.StopFarm = false
            task.spawn(function() SideFarm(_selJob) end)
            Notif("Side Job", "Mulai: " .. _selJob, 4, "play")
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
    Callback      = function(opt) _selVehicle = opt end,
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
    Callback      = function(opt) _selDealer = opt end,
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

-- Box Misc
ToolTab:CreateSection("📦 Box")
ToolTab:CreateButton({ Name = "Claim Box",
    Callback = function() Fire("Box", "Claim") end })
ToolTab:CreateButton({ Name = "Gamepass Box",
    Callback = function() Fire("Box", "Buy", "Gamepass Box") end })
ToolTab:CreateButton({ Name = "Limited Box",
    Callback = function() Fire("Box", "Buy", "Limited Box") end })

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
    Content = "1. Discord → Edit Channel → Integrations → Webhooks\n" ..
              "2. Buat webhook baru → Copy URL\n" ..
              "3. Paste di input bawah → tekan Enter\n" ..
              "4. Log otomatis setiap 5–10 menit saat farming",
})
WHTab:CreateInput({
    Name            = "Webhook URL",
    PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false,
    Flag            = "WHInput",
    Callback        = function(v)
        getgenv().GS.WebhookURL = v
        SM:Save()
        Notif("Webhook", "✅ URL disimpan!", 4, "check")
    end,
})
WHTab:CreateButton({
    Name     = "📤 Test Kirim Webhook",
    Callback = function()
        local bk = getgenv().GS.OnFarming
        getgenv().GS.OnFarming   = true
        getgenv().SS.StartMoney  = GetMoney() - 55555
        getgenv().SS.FarmStart   = os.time() - 240
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
    Title   = "Konten Log Discord",
    Content = "✅ Username & UserID\n" ..
              "✅ Status (Aktif / Target Reached)\n" ..
              "✅ Uang Saat Ini  &  Earned Sesi\n" ..
              "✅ Progress Bar % ke Target\n" ..
              "✅ Durasi Sesi  (menit)\n" ..
              "✅ Timestamp",
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 6 — DEVELOPER                  ║
-- ╚══════════════════════════════════════╝

local DevTab = Window:CreateTab("🛠️ Developer", "code")

DevTab:CreateSection("📍 Coordinate Recorder")
DevTab:CreateParagraph({
    Title   = "Cara Pakai",
    Content = "1. Pindah karakter ke posisi yang ingin direkam\n" ..
              "2. Klik 'Ambil Koordinat'\n" ..
              "3. Koordinat tampil di label & disalin ke clipboard\n" ..
              "4. Paste ke tabel CFG.TruckRoute",
})

local coordLabel = DevTab:CreateLabel("📍 Koordinat: (belum direkam)")

DevTab:CreateButton({
    Name     = "📍 Ambil Koordinat Sekarang",
    Callback = function()
        local coord = RecordCoord()
        pcall(function() coordLabel:Set("📍 " .. coord) end)
        pcall(function()
            if setclipboard then
                setclipboard(coord)
                Notif("Coord Recorder", "✅ Disalin!\n" .. coord, 7, "copy")
            else
                Notif("Coord Recorder", coord, 8, "info")
            end
        end)
        print("[CoordRecorder]", coord)
    end,
})

DevTab:CreateSection("🗺️ Rute Saat Ini  (" .. #CFG.TruckRoute .. " titik)")
for i, pt in ipairs(CFG.TruckRoute) do
    DevTab:CreateLabel(string.format(
        "[%d] %s\n     pos=(%.1f, %.1f→%.1f, %.1f)  action=%s",
        i, pt.label,
        pt.pos.X,
        pt.pos.Y, pt.pos.Y + CFG.SafeY,
        pt.pos.Z,
        pt.action
    ))
end

DevTab:CreateDivider()
DevTab:CreateSection("🔧 Tools")
DevTab:CreateButton({
    Name     = "Dex Explorer",
    Callback = function()
        pcall(function()
            loadstring(game:HttpGet(
                "https://raw.githubusercontent.com/infyiff/backup/main/dex.lua"
            ))()
        end)
    end,
})
DevTab:CreateButton({
    Name     = "Simple Spy",
    Callback = function()
        pcall(function()
            loadstring(game:HttpGet(
                "https://github.com/exxtremestuffs/SimpleSpySource/raw/master/SimpleSpy.lua"
            ))()
        end)
    end,
})

-- ╔══════════════════════════════════════╗
-- ║  TAB 7 — SETTINGS                   ║
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
    Name     = "🔗 Join PS (Jawa Timur)",
    Callback = function()
        pcall(function()
            local lbl = LP.PlayerGui.Hub.Container
                            .Window.PrivateServer.ServerLabel
            if lbl and lbl.ContentText ~= "None" then
                Fire("PrivateServer", "Join", lbl.ContentText, "JawaTimur")
                Notif("PS", "Joining: " .. lbl.ContentText, 5, "link")
            else
                Notif("PS", "Buat private code dulu!", 5, "alert")
            end
        end)
    end,
})

SettTab:CreateSection("ℹ️ Tentang Script")
SettTab:CreateParagraph({
    Title   = "Info",
    Content = "Versi          : " .. CFG.Version         .. "\n" ..
              "UI Library     : Rayfield (sirius.menu)\n" ..
              "CycleDelay     : " .. CFG.CycleDelay      .. " detik\n" ..
              "TeleportSpeed  : " .. CFG.TeleportSpeed   .. " stud/s\n" ..
              "SafeY Offset   : +" .. CFG.SafeY          .. " stud\n" ..
              "WaitAtPoint    : " .. CFG.WaitAtPoint     .. " detik\n" ..
              "CountdownSec   : " .. CFG.CountdownSec    .. " detik\n" ..
              "Rute JT        : " .. #CFG.TruckRoute     .. " titik\n" ..
              "Anti-AFK       : VirtualInputManager\n" ..
              "Error Handling : pcall per titik & per cycle",
})

-- ════════════════════════════════════════════════════════════════════
-- [10] INIT
-- ════════════════════════════════════════════════════════════════════

StartAntiAFK()

-- Validasi map
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
            Notif(
                "⚠️ Bukan Jawa Timur!",
                "Map: " .. name .. "\nAuto-Farm dinonaktifkan.",
                7, "alert"
            )
        end
    end
end)

-- Auto-resume dari config tersimpan
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

print(string.format(
    "[CDID v%s] Ready | Speed=%.1f | SafeY=+%d | Route=%d titik",
    CFG.Version, CFG.TeleportSpeed, CFG.SafeY, #CFG.TruckRoute
))
