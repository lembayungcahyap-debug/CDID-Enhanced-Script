--[[
╔══════════════════════════════════════════════════════════════════════╗
║        CDID — Jawa Timur Edition  |  Rayfield UI  |  v4.0          ║
║                                                                      ║
║  CARA PAKAI (Plug & Play):                                          ║
║  1. Isi CFG.WebhookURL dengan URL webhook Discord kamu              ║
║  2. Isi CFG.TargetEarning dengan jumlah uang target per sesi        ║
║  3. Untuk koordinat JawaTimurPoints: jalankan script, masuk game,   ║
║     lalu di tab Settings klik "📍 Print My Position" — posisi       ║
║     karaktermu akan tercetak di console. Kumpulkan 10-15 titik      ║
║     di jalan utama JT, lalu paste ke tabel JawaTimurPoints di bawah ║
║  4. Execute di executor (Xeno/Velocity/Delta)                       ║
╚══════════════════════════════════════════════════════════════════════╝
]]

-- ====================================================================
-- [1] KONFIGURASI — Edit bagian ini sesuai kebutuhanmu
-- ====================================================================

local CFG = {

    -- ── Performa ───────────────────────────────────────────────────
    TeleportSpeed  = 49.5,   -- Kecepatan tween kendaraan
    CycleDelay     = 0.2,    -- Jeda antar aksi dalam loop (detik)
    DelayRejoin    = 0.5,    -- Jeda sebelum rejoin server (detik)
    CountdownSec   = 20,     -- Countdown sebelum teleport kendaraan

    -- ── Target Earning ─────────────────────────────────────────────
    -- Farming otomatis berhenti saat uang earned >= nilai ini
    -- Set ke 0 jika tidak ingin ada batas
    TargetEarning  = 1000000,

    -- ── Discord Webhook ────────────────────────────────────────────
    -- Tempel URL webhook Discord kamu di sini
    WebhookURL     = "",
    -- Log dikirim setiap N detik saat farming aktif (300 = 5 menit)
    WebhookInterval = 300,

    -- ── Map ────────────────────────────────────────────────────────
    MapName        = "Jawa Timur",
    Version        = "4.0",

    -- ── Rute Farming Jawa Timur ────────────────────────────────────
    --
    --  CARA AMBIL KOORDINAT (30 detik):
    --  1. Masuk ke Map Jawa Timur di CDID
    --  2. Execute script ini
    --  3. Di tab Settings, klik tombol "📍 Print My Position"
    --  4. Jalan ke titik yang kamu mau (perempatan, jalan tol, dsb)
    --  5. Klik tombol itu lagi — koordinat muncul di console/output
    --  6. Copy paste ke tabel di bawah ini
    --
    --  Titik di bawah adalah koordinat referensi dari codebase asli
    --  + estimasi jalan utama Jawa Timur berdasarkan skala map.
    --  Verifikasi dan sesuaikan dengan kondisi map saat ini.
    --
    JawaTimurPoints = {
        -- Koordinat dari source code asli (terverifikasi dari codebase)
        { x = -50889.66, y = 1017.87, z = -86514.80 }, -- [1] Delivery Point A (Surabaya area)
        { x = -48200.00, y = 1020.00, z = -84000.00 }, -- [2] Checkpoint B (Malang area)
        { x = -51500.00, y = 1015.00, z = -88000.00 }, -- [3] Delivery Point C (Jember area)

        -- Titik tambahan — perkiraan berdasarkan skala peta JT CDID
        -- WAJIB diverifikasi in-game dengan "Print My Position"
        { x = -49500.00, y = 1018.00, z = -85000.00 }, -- [4] Jalan Tol A (estimasi)
        { x = -50000.00, y = 1016.00, z = -87000.00 }, -- [5] Jalan Tol B (estimasi)
        { x = -47500.00, y = 1021.00, z = -83000.00 }, -- [6] Kota Malang  (estimasi)
        { x = -52000.00, y = 1014.00, z = -89000.00 }, -- [7] Pelabuhan Jember (estimasi)
        { x = -53000.00, y = 1013.00, z = -87500.00 }, -- [8] Banyuwangi area (estimasi)
        { x = -48800.00, y = 1019.00, z = -86000.00 }, -- [9] Ruko JT tengah (estimasi)
        { x = -50200.00, y = 1017.00, z = -85500.00 }, -- [10] Persimpangan utama (estimasi)
        { x = -51000.00, y = 1016.00, z = -86800.00 }, -- [11] Rest area JT  (estimasi)
        { x = -49000.00, y = 1020.00, z = -84500.00 }, -- [12] Pasar JT      (estimasi)
        { x = -47800.00, y = 1022.00, z = -82500.00 }, -- [13] Terminal Malang (estimasi)
        { x = -52500.00, y = 1014.00, z = -88500.00 }, -- [14] Pantai selatan (estimasi)
        { x = -50500.00, y = 1017.00, z = -86200.00 }, -- [15] SPBU utama JT (estimasi)
    },

    -- Keyword untuk validasi waypoint adalah tujuan Jawa Timur
    WaypointKeywords = {
        "Timur", "Surabaya", "Malang", "Jember",
        "Banyuwangi", "Pasuruan", "Kediri", "Mojokerto", "Gresik",
    },

    -- Area spawn truck (dekat PT. Shad — dari source asli)
    TruckSpawnPos  = Vector3.new(-21782.94, 1042.03, -26786.96),
}

-- ====================================================================
-- [2] SETTINGS MANAGER — Auto-save/load config ke file lokal
-- ====================================================================

local SM = {
    Dir  = "CDID_JT4",
    File = "CDID_JT4\\config.json",
    HS   = game:GetService("HttpService"),
    LastSave = 0,
    Cooldown = 1,
}

-- State global (persistent antar cycle & rejoin)
getgenv().GS = getgenv().GS or {
    OnFarming     = false,
    StopFarm      = false,
    InfJump       = false,
    TargetEarning = CFG.TargetEarning,
    WebhookURL    = CFG.WebhookURL,
    DelayRejoin   = CFG.DelayRejoin,
    SelectedJob   = "Office Worker",
    RouteIndex    = 1,   -- posisi terakhir di rute
}

-- Stats sesi (reset tiap kali farming dimulai ulang)
getgenv().SS = getgenv().SS or {
    StartMoney   = 0,
    FarmStart    = 0,
    LastWebhook  = 0,
    CycleCount   = 0,
}

function SM:Save(force)
    if not writefile then return end
    local now = os.time()
    if not force and (now - self.LastSave) < self.Cooldown then return end
    pcall(function()
        if not isfolder(self.Dir) then makefolder(self.Dir) end
        writefile(self.File, self.HS:JSONEncode({ v = CFG.Version, s = getgenv().GS }))
        self.LastSave = now
    end)
end

function SM:Load()
    if not (readfile and isfile) then return end
    pcall(function()
        if isfile(self.File) then
            local d = self.HS:JSONDecode(readfile(self.File))
            if d and d.s then
                for k, v in pairs(d.s) do
                    if getgenv().GS[k] ~= nil then getgenv().GS[k] = v end
                end
            end
        end
    end)
end

SM:Load()

-- ====================================================================
-- [3] SERVICES — Cache semua Roblox service
-- ====================================================================

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local TwnSvc    = game:GetService("TweenService")
local RunSvc    = game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local TelSvc    = game:GetService("TeleportService")
local HttpSvc   = game:GetService("HttpService")
local MktSvc    = game:GetService("MarketplaceService")
local GuiSvc    = game:GetService("GuiService")
local VIM       = game:GetService("VirtualInputManager")

local LP        = Players.LocalPlayer

-- Cache RemoteEvents & RemoteFunctions (non-blocking)
local NetEv, NetFn
task.spawn(function()
    local ok = pcall(function()
        local nc = RS:WaitForChild("NetworkContainer", 25)
        if nc then
            NetEv = nc:FindFirstChild("RemoteEvents")
            NetFn = nc:FindFirstChild("RemoteFunctions")
        end
    end)
    if not ok then warn("[CDID] NetworkContainer timeout.") end
end)

-- ====================================================================
-- [4] HELPERS — Fungsi utiliti
-- ====================================================================

-- Safe FireServer
local function Fire(name, ...)
    local args = { ... }
    pcall(function()
        if not NetEv then return end
        local ev = NetEv:FindFirstChild(name)
        if ev then ev:FireServer(table.unpack(args)) end
    end)
end

-- Safe InvokeServer
local function Invoke(name, ...)
    local args = { ... }
    local ok, r = pcall(function()
        if not NetFn then return nil end
        local fn = NetFn:FindFirstChild(name)
        if fn then return fn:InvokeServer(table.unpack(args)) end
    end)
    return ok and r or nil
end

-- Tween HumanoidRootPart karakter ke CFrame
local function TweenChar(cf, dur)
    dur = dur or (1 / CFG.TeleportSpeed * 50)
    pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        TwnSvc:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = cf }):Play()
    end)
end

-- Warp instan karakter (tanpa tween)
local function WarpChar(pos)
    pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = CFrame.new(pos) end
    end)
end

-- Ambil uang dari GUI — fallback 0 kalau GUI belum ready
local function GetMoney()
    local ok, v = pcall(function()
        local t = LP.PlayerGui.Main.Container.Hub.CashFrame.Frame.TextLabel.Text
        return tonumber(t:gsub("[^%d]", "")) or 0
    end)
    return (ok and v) or 0
end

-- Format angka ribuan: 1234567 → "1.234.567"
local function Fmt(n)
    if not n then return "0" end
    return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

-- Progress bar ASCII: [████░░░░░░] 45.0%
local function PBar(cur, tgt, w)
    w = w or 18
    if not tgt or tgt <= 0 then return "[ ∞ No Limit ]", 0 end
    local p = math.min(cur / tgt, 1)
    local f = math.floor(p * w)
    local bar = string.rep("█", f) .. string.rep("░", w - f)
    return string.format("[%s] %.1f%%", bar, p * 100), p * 100
end

-- Cek apakah pemain sedang duduk di kendaraan
local function InVehicle()
    local ok, r = pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end)
    return ok and r
end

-- Cek apakah teks waypoint adalah tujuan Jawa Timur
local function IsJTWaypoint(txt)
    if not txt or txt == "" then return false end
    for _, kw in ipairs(CFG.WaypointKeywords) do
        if txt:find(kw, 1, true) then return true end
    end
    return false
end

-- Ambil titik rute berikutnya (circular)
local function NextRoutePoint()
    local idx = getgenv().GS.RouteIndex or 1
    local pt  = CFG.JawaTimurPoints[idx]
    getgenv().GS.RouteIndex = (idx % #CFG.JawaTimurPoints) + 1
    return pt
end

-- ====================================================================
-- [5] ANTI-AFK — Cegah Idle Kick
-- ====================================================================

local _afkConn

local function StartAntiAFK()
    if _afkConn then pcall(function() _afkConn:Disconnect() end) end

    _afkConn = LP.Idled:Connect(function()
        pcall(function()
            -- Simulasi gerakan random agar tidak terdeteksi sebagai idle
            local keys = { "W", "A", "S", "D" }
            local k = keys[math.random(1, #keys)]
            VIM:SendKeyEvent(true,  k, false, game)
            task.wait(math.random() * 0.15 + 0.05)
            VIM:SendKeyEvent(false, k, false, game)
            VIM:SendMouseMoveEvent(
                math.random(-25, 25),
                math.random(-25, 25),
                game
            )
        end)
    end)

    -- Auto reconnect setelah respawn
    LP.CharacterAdded:Once(function()
        task.wait(1.5)
        StartAntiAFK()
    end)

    print("[CDID] AntiAFK aktif.")
end

-- ====================================================================
-- [6] DISCORD WEBHOOK — Smart log setiap 5 menit
-- ====================================================================

local function SendWebhook(isTargetReached)
    local url = getgenv().GS.WebhookURL or ""
    if url == "" then return end

    -- Hanya kirim saat farming aktif atau saat target reached
    if not getgenv().GS.OnFarming and not isTargetReached then return end

    local now = os.time()

    -- Debounce interval (kecuali alert target reached yang langsung kirim)
    if not isTargetReached then
        if (now - getgenv().SS.LastWebhook) < CFG.WebhookInterval then return end
    end
    getgenv().SS.LastWebhook = now

    -- Hitung data sesi
    local money   = GetMoney()
    local earned  = math.max(0, money - getgenv().SS.StartMoney)
    local tgt     = getgenv().GS.TargetEarning or 0
    local bar, _  = PBar(earned, tgt)
    local elapsed = math.floor((now - getgenv().SS.FarmStart) / 60)
    local cycles  = getgenv().SS.CycleCount or 0
    local status  = isTargetReached and "✅ TARGET REACHED" or "🟢 Farming Aktif"
    local color   = isTargetReached and 5832543 or 3066993 -- hijau / biru

    local embed = {
        embeds = {{
            title = isTargetReached
                and "✅ TARGET EARNING TERCAPAI!"
                or  "📊 CDID Farm Report — Jawa Timur",
            color = color,
            description = string.format("Laporan otomatis untuk **%s**", LP.Name),
            fields = {
                {
                    name   = "👤 Pemain",
                    value  = string.format("%s (`%d`)", LP.Name, LP.UserId),
                    inline = true,
                },
                {
                    name   = "🗺️ Map",
                    value  = CFG.MapName,
                    inline = true,
                },
                {
                    name   = "⚡ Status",
                    value  = status,
                    inline = true,
                },
                {
                    name   = "💰 Uang Sekarang",
                    value  = "Rp " .. Fmt(money),
                    inline = true,
                },
                {
                    name   = "📈 Earned Sesi",
                    value  = "Rp " .. Fmt(earned),
                    inline = true,
                },
                {
                    name   = "🎯 Target",
                    value  = tgt > 0 and "Rp " .. Fmt(tgt) or "Tidak Ada",
                    inline = true,
                },
                {
                    name   = "⏱️ Durasi Sesi",
                    value  = elapsed .. " menit  |  " .. cycles .. " cycle",
                    inline = true,
                },
                {
                    name   = "📊 Progress",
                    value  = "```\n" .. bar .. "\n```",
                    inline = false,
                },
            },
            footer = {
                text = "CDID JT v" .. CFG.Version ..
                       "  |  " .. os.date("%d/%m/%Y %H:%M:%S"),
            },
        }}
    }

    pcall(function()
        -- Kompatibel dengan syn.request, http.request, maupun request biasa
        local reqFn = (syn and syn.request)
                   or (http and http.request)
                   or (typeof(request) == "function" and request)
        if not reqFn then
            warn("[CDID Webhook] Tidak ada fungsi HTTP request.")
            return
        end
        reqFn({
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpSvc:JSONEncode(embed),
        })
    end)
end

-- Background timer webhook (cek setiap 30 detik, kirim kalau sudah waktunya)
task.spawn(function()
    while task.wait(30) do
        if getgenv().GS.OnFarming then
            pcall(SendWebhook, false)
        end
    end
end)

-- ====================================================================
-- [7] FARMING ENGINE
-- ====================================================================

-- Referensi ke fungsi update UI status (diisi setelah UI dibuat)
local _setStatus = function(txt) print("[CDID Status]", txt) end
local _setParagraph = function(_, _) end

local function SetStatus(txt)
    pcall(_setStatus, txt)
end

-- ── 7a. Stop farming ──────────────────────────────────────────

local function StopFarming(sendAlert)
    getgenv().GS.OnFarming = false
    getgenv().GS.StopFarm  = true
    SM:Save()
    pcall(function() Fire("Engine", "Off") end)
    SetStatus("⏹️ Farming dihentikan.")
    print("[CDID] Farming dihentikan.")
    if sendAlert then
        task.spawn(function()
            task.wait(0.5)
            pcall(SendWebhook, true)
        end)
    end
end

-- ── 7b. Cek apakah target earning sudah tercapai ──────────────

local function CheckTarget()
    local tgt = getgenv().GS.TargetEarning or 0
    if tgt <= 0 then return false end
    local earned = GetMoney() - getgenv().SS.StartMoney
    if earned >= tgt then
        StopFarming(true)
        return true
    end
    return false
end

-- ── 7c. Teleport kendaraan dengan validasi ────────────────────

local function TeleportCar(car, destCF)
    -- VALIDASI: pemain harus di dalam kendaraan
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

-- ── 7d. MAIN LOOP: Auto-Farm Truck Jawa Timur ─────────────────

local function TruckFarmLoop()
    print("[CDID] TruckFarm Jawa Timur dimulai.")

    while task.wait(CFG.CycleDelay) do

        -- Guard utama
        if not getgenv().GS.OnFarming then break end
        if CheckTarget() then break end

        local cycleOk, cycleErr = pcall(function()

            getgenv().SS.CycleCount = (getgenv().SS.CycleCount or 0) + 1
            SetStatus("📋 Cycle #" .. getgenv().SS.CycleCount .. " — Mengambil job Truck...")

            -- STEP 1: Ambil job Truck
            Fire("Job", "Truck")
            task.wait(0.8)

            -- STEP 2: Cari waypoint
            local wpFolder = workspace.Etc and workspace.Etc:FindFirstChild("Waypoint")
            local waypoint = wpFolder and wpFolder:FindFirstChild("Waypoint")

            if not waypoint then
                -- Coba paksa spawn waypoint dengan re-fire job
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
                warn("[TruckFarm] Waypoint nil.")
                return
            end

            -- STEP 3: Tween karakter ke area spawn truck
            SetStatus("🚗 Menuju area spawn truck...")
            TweenChar(CFrame.new(CFG.TruckSpawnPos), 1.0)
            task.wait(1.5)

            -- STEP 4: Validasi waypoint = Jawa Timur
            local bb      = waypoint:FindFirstChildWhichIsA("BillboardGui", true)
            local wlbl    = bb and bb:FindFirstChildWhichIsA("TextLabel", true)
            local wtext   = wlbl and wlbl.Text or ""
            local attempt = 0

            while not IsJTWaypoint(wtext) and getgenv().GS.OnFarming do
                attempt = attempt + 1
                if attempt > 30 then
                    SetStatus("⚠️ Waypoint JT tidak muncul — skip cycle.")
                    return
                end
                -- Anchor sementara agar tidak jatuh saat spam prompt
                pcall(function()
                    LP.Character.HumanoidRootPart.Anchored = true
                end)
                Fire("Job", "Truck")
                pcall(fireproximityprompt, workspace.Etc.Job.Truck.Starter.Prompt)
                task.wait(0.7)
                pcall(function()
                    LP.Character.HumanoidRootPart.Anchored = false
                end)
                wtext = wlbl and wlbl.Text or ""
            end

            if not getgenv().GS.OnFarming then return end
            pcall(function() LP.Character.HumanoidRootPart.Anchored = false end)
            SetStatus("✅ Waypoint OK: " .. wtext)

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
            for i = 1, 18 do
                car = FindCar()
                if car then break end
                PressF()
                task.wait(0.8)
                if i > 5 then
                    -- Kalau masih belum muncul, coba tween ke posisi spawn lagi
                    TweenChar(CFrame.new(CFG.TruckSpawnPos), 0.5)
                end
            end

            if not car then
                SetStatus("❌ Gagal spawn kendaraan — retry cycle.")
                return
            end

            -- STEP 6: Duduk di DriveSeat
            SetStatus("🪑 Duduk di kendaraan...")
            local driveSeat = car:FindFirstChild("DriveSeat")
            if not driveSeat then
                warn("[TruckFarm] DriveSeat tidak ditemukan.")
                return
            end

            pcall(function() driveSeat:Sit(LP.Character.Humanoid) end)
            task.wait(1.2)

            -- Retry duduk kalau belum berhasil
            for _ = 1, 12 do
                if InVehicle() then break end
                pcall(function() driveSeat:Sit(LP.Character.Humanoid) end)
                task.wait(0.4)
            end

            if not InVehicle() then
                SetStatus("❌ Gagal duduk di kendaraan — retry cycle.")
                return
            end

            -- STEP 7: Countdown sebelum teleport
            for i = CFG.CountdownSec, 0, -1 do
                if not getgenv().GS.OnFarming then return end
                if CheckTarget() then return end
                SetStatus(string.format("⏳ Teleport dalam %d detik...", i))
                task.wait(1)
            end

            -- STEP 8: Teleport kendaraan ke titik delivery Jawa Timur
            --         Rute melingkar (menggunakan NextRoutePoint)
            local pt     = NextRoutePoint()
            local destCF = CFrame.new(
                pt.x, pt.y, pt.z,
                0.866007268, 0,            0.500031412,
                0,           1,            0,
                -0.500031412, 0,           0.866007268
            )

            SetStatus(string.format("🚀 Teleport ke [%d] (%.0f, %.0f, %.0f)...",
                getgenv().GS.RouteIndex, pt.x, pt.y, pt.z))

            local teleOk = TeleportCar(car, destCF)
            if not teleOk then
                SetStatus("⚠️ Teleport gagal validasi — retry cycle.")
                return
            end
            task.wait(0.4)

            -- STEP 9: Fire job lagi agar progress terhitung, lalu rejoin
            Fire("Job", "Truck")
            task.wait(getgenv().GS.DelayRejoin or CFG.DelayRejoin)

            SetStatus("🔄 Rejoin server...")
            pcall(function()
                TelSvc:Teleport(game.PlaceId, LP)
            end)

            -- Tunggu teleport (biasanya < 10 detik, 90 detik buat safety)
            task.wait(90)
        end)

        -- Tangkap error cycle agar loop tidak berhenti total
        if not cycleOk then
            warn("[TruckFarm] Cycle error:", cycleErr)
            SetStatus("⚠️ Error: " .. tostring(cycleErr):sub(1, 70))
            task.wait(3) -- Cooldown sebelum retry
        end
    end

    SetStatus("⏹️ Truck farm loop selesai.")
    print("[CDID] TruckFarm loop keluar.")
end

-- ── 7e. Auto-Farm menggunakan rute JawaTimurPoints + TweenService ─

--  Mode alternatif: jalan di rute tanpa rejoin, cocok untuk grinding
--  jenis lain (misalnya paket, angkutan kota, dsb.)

local function RouteWalkLoop()
    print("[CDID] RouteWalk Jawa Timur dimulai.")

    while task.wait(CFG.CycleDelay) do
        if not getgenv().GS.OnFarming then break end
        if CheckTarget() then break end

        local ok, err = pcall(function()
            local pt  = NextRoutePoint()
            local dur = 1 / CFG.TeleportSpeed * 50
            SetStatus(string.format("🗺️ Route [%d/%d] → (%.0f, %.0f, %.0f)",
                getgenv().GS.RouteIndex, #CFG.JawaTimurPoints, pt.x, pt.y, pt.z))

            TweenChar(CFrame.new(pt.x, pt.y, pt.z), dur)
            task.wait(dur + 0.1)
        end)

        if not ok then
            warn("[RouteWalk] Error:", err)
            task.wait(2)
        end
    end

    SetStatus("⏹️ Route walk selesai.")
end

-- ── 7f. Side Jobs ─────────────────────────────────────────────

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

            local parts = quest:split(" ")
            local n1 = tonumber(parts[1])
            local op = parts[2]
            local n2 = tonumber(parts[3])
            if not (n1 and op and n2) then return end

            local ans    = op == "+" and (n1 + n2) or (n1 - n2)
            local ansStr = tostring(math.floor(ans))
            box.Text     = ansStr
            repeat task.wait(CFG.CycleDelay) until box.Text == ansStr

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
                    fireproximityprompt(workspace.Etc.Job.JanjiJiwa.Starter.Prompt)
                    WarpChar(Vector3.new(-13716.35, 1052.89, -17997.70))
                    task.wait(15)
                    if LP.Backpack:FindFirstChild("Coffee") then
                        WarpChar(Vector3.new(-13723.75, 1052.89, -17994.23))
                        Fire("JanjiJiwa", "Delivery")
                    end
                    WarpChar(Vector3.new(-13716.35, 1052.89, -17997.70))
                end)
            end
        end)
    end
end

-- ====================================================================
-- [8] UNLOCK ALL SHOPS
-- ====================================================================

local function UnlockShops()
    local count = 0

    -- Buka semua dealer via ProximityPrompt
    pcall(function()
        for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
            local p = d:FindFirstChild("Prompt")
            if p then
                fireproximityprompt(p)
                count = count + 1
                task.wait(0.2)
            end
        end
    end)

    -- Coba via RemoteEvent untuk toko yang tidak punya prompt fisik
    local extraShops = {
        "KiosMarket", "Minimarket", "SpeedShop",
        "TuningShop", "FuelStation", "GasStation",
    }
    for _, s in ipairs(extraShops) do
        pcall(Fire, "OpenShop", s)
        task.wait(0.15)
    end

    return count
end

-- ====================================================================
-- [9] UI — RAYFIELD
-- ====================================================================

-- Tunggu game & karakter benar-benar siap
repeat task.wait(0.1)
until  game:IsLoaded()
   and LP
   and LP.Character
   and LP.Character:FindFirstChild("HumanoidRootPart")

-- ── Load Rayfield dengan dual fallback ────────────────────────

local Rayfield
local RF_URLS = {
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
}

for _, url in ipairs(RF_URLS) do
    if Rayfield then break end
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if ok and lib then
        Rayfield = lib
        print("[CDID] Rayfield dimuat dari:", url)
    else
        warn("[CDID] Gagal load Rayfield dari:", url, lib)
        task.wait(1)
    end
end

-- Fallback terakhir: tampilkan error screen agar tidak silent fail
if not Rayfield then
    local sg   = Instance.new("ScreenGui")
    sg.Name    = "CDIDError"
    sg.ResetOnSpawn = false
    sg.Parent  = LP.PlayerGui

    local bg   = Instance.new("Frame", sg)
    bg.Size    = UDim2.fromOffset(460, 100)
    bg.Position = UDim2.fromScale(0.5, 0.08)
    bg.AnchorPoint = Vector2.new(0.5, 0)
    bg.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
    bg.BorderSizePixel = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel", bg)
    lbl.Size  = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Text  = "❌  CDID: Gagal memuat Rayfield UI!\n" ..
                "Cek koneksi internet & pastikan HTTP Requests aktif di executor."
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.TextScaled = true
    lbl.Font  = Enum.Font.GothamBold

    error("[CDID] FATAL: Rayfield tidak dapat dimuat.", 2)
end

-- ── Buat Window Utama ──────────────────────────────────────────

local Window = Rayfield:CreateWindow({
    Name             = "CDID — " .. CFG.MapName,
    LoadingTitle     = "CDID Auto-Farm",
    LoadingSubtitle  = "Jawa Timur Edition v" .. CFG.Version,
    ConfigurationSaving = {
        Enabled  = true,
        FileName = "CDID_JT4_RayfieldCfg",
    },
    Discord = { Enabled = false },
    KeySystem = false,
})

-- Helper notifikasi Rayfield
local function Notif(title, msg, dur, img)
    pcall(function()
        Rayfield:Notify({
            Title    = title or "CDID",
            Content  = msg   or "",
            Duration = dur   or 5,
            Image    = img   or "info",
        })
    end)
end

-- ╔══════════════════════════════════════════════╗
-- ║  TAB 1 — HOME                               ║
-- ╚══════════════════════════════════════════════╝

local HomeTab = Window:CreateTab("🏠 Home", "home")

HomeTab:CreateSection("Info Pemain")
HomeTab:CreateLabel("👤 " .. LP.Name .. "   |   🆔 " .. tostring(LP.UserId))
HomeTab:CreateLabel("🗺️ Map: " .. CFG.MapName .. "   |   📦 Script v" .. CFG.Version)

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
    Range        = { 2, 250 },
    Increment    = 1,
    Suffix       = "",
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
    Name         = "Click Teleport  (CTRL + Klik)",
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

-- ╔══════════════════════════════════════════════╗
-- ║  TAB 2 — FARMING                            ║
-- ╚══════════════════════════════════════════════╝

local FarmTab = Window:CreateTab("🚛 Farming", "truck")

FarmTab:CreateSection("📊 Status Real-Time")

-- Paragraph status — diupdate oleh _setStatus
local statusPara = FarmTab:CreateParagraph({
    Title   = "Status",
    Content = "Belum dimulai.",
})

local moneyPara = FarmTab:CreateParagraph({
    Title   = "Uang & Progress",
    Content = "Rp 0  |  0%",
})

-- Bind _setStatus ke paragraph
_setStatus = function(txt)
    pcall(function()
        statusPara:Set({ Title = "Status", Content = txt })
    end)
end

-- Update money paragraph setiap 2 detik
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            local money  = GetMoney()
            local earned = math.max(0, money - getgenv().SS.StartMoney)
            local bar, _ = PBar(earned, getgenv().GS.TargetEarning)
            moneyPara:Set({
                Title   = "Uang & Progress",
                Content = "💰 Rp " .. Fmt(money) ..
                          "  |  📈 Earned: Rp " .. Fmt(earned) ..
                          "\n" .. bar,
            })
        end)
    end
end)

FarmTab:CreateDivider()
FarmTab:CreateSection("⚙️ Konfigurasi")

FarmTab:CreateInput({
    Name            = "🎯 Target Earning  (Rp — 0 = tidak ada batas)",
    PlaceholderText = tostring(getgenv().GS.TargetEarning),
    RemoveTextAfterFocusLost = false,
    Flag            = "TargetInput",
    Callback = function(v)
        local n = tonumber(v)
        if n then
            getgenv().GS.TargetEarning = n
            SM:Save()
            Notif("Target", "Diubah ke Rp " .. Fmt(n), 4, "check")
        end
    end,
})

FarmTab:CreateInput({
    Name            = "⏱️ Delay Sebelum Rejoin  (detik)",
    PlaceholderText = tostring(getgenv().GS.DelayRejoin),
    RemoveTextAfterFocusLost = false,
    Flag            = "DelayInput",
    Callback = function(v)
        local n = tonumber(v)
        if n and n >= 0 then
            getgenv().GS.DelayRejoin = n
            SM:Save()
        end
    end,
})

FarmTab:CreateDivider()
FarmTab:CreateSection("🚛 Auto-Farm Jawa Timur")

FarmTab:CreateParagraph({
    Title   = "ℹ️ Parameter Aktif",
    Content = "TeleportSpeed : " .. CFG.TeleportSpeed ..
              "\nCycleDelay   : " .. CFG.CycleDelay .. " detik" ..
              "\nCountdown    : " .. CFG.CountdownSec .. " detik" ..
              "\nTotal Titik  : " .. #CFG.JawaTimurPoints .. " waypoint",
})

FarmTab:CreateToggle({
    Name         = "▶️  Truck Farm (Jawa Timur)  — MAIN MODE",
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
            getgenv().SS.CycleCount  = 0
            getgenv().GS.RouteIndex  = 1
            Notif("Farming", "▶️ Truck Farm dimulai!\nTarget: Rp " ..
                  Fmt(getgenv().GS.TargetEarning), 5, "play")
            task.spawn(TruckFarmLoop)
        else
            StopFarming(false)
            Notif("Farming", "⏹️ Farming dihentikan.", 4, "stop")
        end
    end,
})

FarmTab:CreateToggle({
    Name         = "🗺️  Route Walk (Jawa Timur)  — TWEEN MODE",
    CurrentValue = false,
    Flag         = "RouteWalkToggle",
    Callback = function(v)
        getgenv().GS.OnFarming = v
        getgenv().GS.StopFarm  = not v
        SM:Save()

        if v then
            getgenv().SS.StartMoney  = GetMoney()
            getgenv().SS.FarmStart   = os.time()
            getgenv().SS.LastWebhook = 0
            getgenv().GS.RouteIndex  = 1
            Notif("Route Walk", "🗺️ Route Walk Jawa Timur dimulai!", 5, "play")
            task.spawn(RouteWalkLoop)
        else
            StopFarming(false)
            Notif("Route Walk", "⏹️ Dihentikan.", 4, "stop")
        end
    end,
})

-- ╔══════════════════════════════════════════════╗
-- ║  TAB 3 — SIDE JOBS                          ║
-- ╚══════════════════════════════════════════════╝

local JobTab = Window:CreateTab("💼 Side Jobs", "briefcase")

JobTab:CreateSection("Pilih Pekerjaan")

local _selJob = getgenv().GS.SelectedJob or "Office Worker"

JobTab:CreateDropdown({
    Name          = "Job",
    Options       = { "Office Worker", "Barista" },
    CurrentOption = { _selJob },
    Flag          = "JobDD",
    Callback = function(opt)
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
    Callback = function(v)
        if v then
            task.spawn(function() SideFarm(_selJob) end)
            Notif("Side Job", "Mulai: " .. _selJob, 4, "play")
        else
            getgenv().GS.StopFarm = true
            SM:Save()
            Notif("Side Job", "Dihentikan.", 4, "stop")
        end
    end,
})

-- ╔══════════════════════════════════════════════╗
-- ║  TAB 4 — TOOLS                              ║
-- ╚══════════════════════════════════════════════╝

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
if #vList == 0 then vList = { "(tidak ada limited stock)" } end

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
        Notif("Vehicle Sniper", "Membeli: " .. _selVehicle, 4, "cart")
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
            Notif("Vehicle Sniper", "Semua kendaraan dibeli!", 4, "check")
        else
            Notif("Vehicle Sniper", "Tidak ada limited stock.", 4, "alert")
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
if #dNames == 0 then dNames = { "(tidak ada dealer)" } end

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
            Notif("Dealer", "Membuka: " .. tostring(_selDealer), 3, "store")
        else
            Notif("Dealer", "Prompt tidak ditemukan.", 4, "alert")
        end
    end,
})

ToolTab:CreateButton({
    Name     = "🔓 Unlock SEMUA Toko & Dealer",
    Callback = function()
        local n = UnlockShops()
        Notif("Shops", "Dibuka: " .. n .. " toko/dealer!", 5, "check")
    end,
})

-- Box
ToolTab:CreateSection("📦 Box")
ToolTab:CreateButton({
    Name     = "Claim Box",
    Callback = function() Fire("Box", "Claim") end,
})
ToolTab:CreateButton({
    Name     = "Gamepass Box",
    Callback = function() Fire("Box", "Buy", "Gamepass Box") end,
})
ToolTab:CreateButton({
    Name     = "Limited Box",
    Callback = function() Fire("Box", "Buy", "Limited Box") end,
})

-- Car Slot
ToolTab:CreateSection("🚗 Car Slot")
ToolTab:CreateButton({
    Name     = "⬆️ Upgrade Slot",
    Callback = function() Fire("UpgradeStats", "CarSlot") end,
})

-- ╔══════════════════════════════════════════════╗
-- ║  TAB 5 — DISCORD WEBHOOK                    ║
-- ╚══════════════════════════════════════════════╝

local WHTab = Window:CreateTab("📡 Webhook", "bell")

WHTab:CreateSection("🔔 Discord Config")

WHTab:CreateParagraph({
    Title   = "Cara Setup Webhook",
    Content = "1. Buka server Discord → klik ⚙️ Edit Channel\n" ..
              "2. Integrations → Webhooks → New Webhook\n" ..
              "3. Copy Webhook URL\n" ..
              "4. Paste di input di bawah → tekan Enter\n" ..
              "5. Log otomatis dikirim setiap " ..
              tostring(CFG.WebhookInterval/60) .. " menit saat farming aktif",
})

WHTab:CreateInput({
    Name            = "Webhook URL",
    PlaceholderText = "https://discord.com/api/webhooks/ID/TOKEN",
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
        getgenv().GS.OnFarming   = true
        getgenv().SS.StartMoney  = GetMoney() - 77777
        getgenv().SS.FarmStart   = os.time() - 180
        getgenv().SS.LastWebhook = 0
        pcall(SendWebhook, false)
        getgenv().GS.OnFarming = bk
        Notif("Webhook", "📤 Test dikirim — cek Discord!", 5, "bell")
    end,
})

WHTab:CreateButton({
    Name     = "✅ Test Alert TARGET REACHED",
    Callback = function()
        getgenv().SS.StartMoney  = GetMoney() - (getgenv().GS.TargetEarning or 1000000)
        getgenv().SS.FarmStart   = os.time() - 3600
        getgenv().SS.LastWebhook = 0
        pcall(SendWebhook, true)
        Notif("Webhook", "✅ Alert TARGET REACHED dikirim!", 5, "check")
    end,
})

WHTab:CreateSection("📋 Data yang Dikirim")
WHTab:CreateParagraph({
    Title   = "Isi Embed Discord",
    Content = "✅ Nama Pemain & UserID\n" ..
              "✅ Status Farming (Aktif / Target Reached)\n" ..
              "✅ 💰 Uang Sekarang\n" ..
              "✅ 📈 Earned Sesi Ini\n" ..
              "✅ 🎯 Target Earning\n" ..
              "✅ 📊 Progress Bar %\n" ..
              "✅ ⏱️ Durasi & Jumlah Cycle\n" ..
              "✅ 🕐 Timestamp",
})

-- ╔══════════════════════════════════════════════╗
-- ║  TAB 6 — SETTINGS                           ║
-- ╚══════════════════════════════════════════════╝

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
    Name     = "🔗 Join PS — Jawa Timur",
    Callback = function()
        pcall(function()
            local lbl = LP.PlayerGui.Hub.Container.Window.PrivateServer.ServerLabel
            if lbl and lbl.ContentText ~= "None" and lbl.ContentText ~= "" then
                Fire("PrivateServer", "Join", lbl.ContentText, "JawaTimur")
                Notif("PS", "Joining: " .. lbl.ContentText, 5, "link")
            else
                Notif("PS", "Buat private code dulu!", 5, "alert")
            end
        end)
    end,
})

SettTab:CreateSection("📍 Koordinat Helper")

SettTab:CreateParagraph({
    Title   = "Cara Ambil Koordinat In-Game",
    Content = "1. Masuk ke Map Jawa Timur\n" ..
              "2. Jalan ke titik yang kamu mau (persimpangan, SPBU, dst)\n" ..
              "3. Klik tombol 'Print My Position' di bawah\n" ..
              "4. Buka Output/Console di executor\n" ..
              "5. Copy koordinat X, Y, Z ke tabel JawaTimurPoints di kode",
})

SettTab:CreateButton({
    Name     = "📍 Print My Position",
    Callback = function()
        pcall(function()
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local p = hrp.Position
                local msg = string.format(
                    "[CDID Koordinat] X=%.2f, Y=%.2f, Z=%.2f\n" ..
                    'Tambahkan ke JawaTimurPoints:\n{ x = %.2f, y = %.2f, z = %.2f },',
                    p.X, p.Y, p.Z, p.X, p.Y, p.Z
                )
                print(msg)
                Notif("Position", string.format("X: %.1f | Y: %.1f | Z: %.1f\n(Lihat console untuk format kode)", p.X, p.Y, p.Z), 8, "mappin")
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
    Title   = "Info Script",
    Content = "Versi          : " .. CFG.Version .. "\n" ..
              "UI Library     : Rayfield (sirius.menu/rayfield)\n" ..
              "TeleportSpeed  : " .. CFG.TeleportSpeed .. "\n" ..
              "CycleDelay     : " .. CFG.CycleDelay .. " detik\n" ..
              "Route Points   : " .. #CFG.JawaTimurPoints .. " titik\n" ..
              "Anti-AFK       : ✅ Aktif (VirtualInputManager)\n" ..
              "Webhook        : setiap " .. CFG.WebhookInterval/60 .. " menit",
})

-- ====================================================================
-- [10] INIT — Startup tasks
-- ====================================================================

-- Anti-AFK aktif dari awal
StartAntiAFK()

-- Cek map saat startup
task.spawn(function()
    local ok, info = pcall(function()
        return MktSvc:GetProductInfo(game.PlaceId)
    end)
    if ok and info then
        local name = info.Name or ""
        local isJT = name:find("Timur", 1, true)
                  or name:find("Car Driving", 1, true)
                  or name:find("CDID", 1, true)
        if isJT then
            Notif("✅ Map OK", "Terdeteksi: " .. name, 5, "check")
        else
            getgenv().GS.OnFarming = false
            Notif("⚠️ Bukan Jawa Timur!", "Auto-Farm dinonaktifkan.\nAktifkan manual jika perlu.", 7, "alert")
        end
    end
end)

-- Auto-resume farming dari config tersimpan
task.spawn(function()
    task.wait(3.5)
    if getgenv().GS.OnFarming then
        getgenv().SS.StartMoney  = GetMoney()
        getgenv().SS.FarmStart   = os.time()
        getgenv().SS.LastWebhook = 0
        getgenv().SS.CycleCount  = 0
        Notif("Auto-Resume", "♻️ Config ditemukan — farming dilanjutkan!", 5, "play")
        SetStatus("♻️ Auto-resume dari config...")
        task.spawn(TruckFarmLoop)
    end
end)

print(string.format(
    "[CDID] Loaded v%s | TeleportSpeed=%.1f | CycleDelay=%.1f | Route=%d pts",
    CFG.Version, CFG.TeleportSpeed, CFG.CycleDelay, #CFG.JawaTimurPoints
))
