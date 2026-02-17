--[[
╔══════════════════════════════════════════════════════════════════════╗
║   CDID — Jawa Timur Edition  |  Rayfield UI  |  v4.0               ║
║   Koordinat akurat dari in-game                                     ║
║                                                                      ║
║   STRUKTUR                                                           ║
║   [1]  CONFIG          — Koordinat & parameter utama                ║
║   [2]  SETTINGS MGR    — Simpan/muat config lokal                   ║
║   [3]  SERVICES        — Cache Roblox services                      ║
║   [4]  HELPERS         — Utiliti umum                               ║
║   [5]  ANTI-AFK        — Cegah Idle Kick                            ║
║   [6]  DISCORD WEBHOOK — Log otomatis ke Discord                    ║
║   [7]  FARMING ENGINE  — Loop utama Truck Farm + Side Jobs          ║
║   [8]  UNLOCK SHOPS    — Buka semua Dealer/Toko                     ║
║   [9]  UI — RAYFIELD   — Semua tab & elemen                        ║
║   [10] INIT            — Startup tasks                              ║
╚══════════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════════
-- [1] CONFIG
-- ═══════════════════════════════════════════════════════════════════

local CFG = {
    -- ── Parameter Performa ─────────────────────────────────────────
    CycleDelay       = 0.2,   -- detik antar setiap aksi dalam loop
    TeleportSpeed    = 49.5,  -- kecepatan TweenService (stud/detik)
    WaitAtPoint      = 0.5,   -- task.wait di setiap titik (server sync)
    DelayRejoin      = 0.5,   -- jeda sebelum rejoin
    CountdownSec     = 15,    -- countdown sebelum teleport kendaraan

    -- ── Target Earning ─────────────────────────────────────────────
    TargetEarning    = 500000,  -- 0 = tidak ada batas

    -- ── Discord Webhook ────────────────────────────────────────────
    WebhookURL       = "",    -- ← ISI URL WEBHOOK DISCORD KAMU
    WHIntervalMin    = 300,   -- 5 menit
    WHIntervalMax    = 600,   -- 10 menit

    -- ── Identitas Map ──────────────────────────────────────────────
    MapName          = "Jawa Timur",
    Version          = "4.0",

    -- ── RUTE TRUCK JAWA TIMUR (Koordinat Akurat dari In-Game) ──────
    --
    --   Urutan eksekusi setiap siklus:
    --   [1] Pickup A  →  [2] Pickup B  →  [3] Delivery
    --
    TruckRoute = {
        {
            label  = "📦 Pickup A — Gudang Utama",
            pos    = Vector3.new(34937.21, 135.64, -54576.89),
            action = "pickup",   -- "pickup" = ambil muatan
        },
        {
            label  = "📦 Pickup B — Gudang Cadangan",
            pos    = Vector3.new(35160.49, 135.64, -54682.41),
            action = "pickup",
        },
        {
            label  = "🏁 Delivery — Tujuan Akhir",
            pos    = Vector3.new(-7845.77, 387.62, 46864.57),
            action = "deliver",  -- "deliver" = selesaikan pengiriman
        },
    },

    -- ── Keyword validasi waypoint Jawa Timur ──────────────────────
    WaypointKeywords = {
        "Timur", "Surabaya", "Malang", "Jember",
        "Banyuwangi", "Pasuruan", "Kediri", "Mojokerto",
    },

    -- ── UI ────────────────────────────────────────────────────────
    Title   = "CDID Jawa Timur",
    Sub     = "Auto-Farm v4.0  |  Koordinat Akurat",
}

-- ═══════════════════════════════════════════════════════════════════
-- [2] SETTINGS MANAGER
-- ═══════════════════════════════════════════════════════════════════

local SM = {
    Dir  = "CDID_JT4",
    File = "CDID_JT4\\cfg.json",
    LastSave = 0,
    Cooldown = 1,
}

-- State global (persistent antar cycle & rejoin)
getgenv().GS = getgenv().GS or {
    OnFarming    = false,
    StopFarm     = false,
    InfJump      = false,
    CdNotif      = false,
    TargetEarning = CFG.TargetEarning,
    WebhookURL   = CFG.WebhookURL,
    DelayRejoin  = CFG.DelayRejoin,
    SelectedJob  = "Office Worker",
}

-- Session stats (reset tiap farming dimulai)
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

-- ═══════════════════════════════════════════════════════════════════
-- [3] SERVICES
-- ═══════════════════════════════════════════════════════════════════

local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local TwnSvc   = game:GetService("TweenService")
local RunSvc   = game:GetService("RunService")
local UIS      = game:GetService("UserInputService")
local TelSvc   = game:GetService("TeleportService")
local HttpSvc  = game:GetService("HttpService")
local MktSvc   = game:GetService("MarketplaceService")
local GuiSvc   = game:GetService("GuiService")
local VIM      = game:GetService("VirtualInputManager")

local LP       = Players.LocalPlayer

-- Network cache (diisi setelah game load)
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

-- ═══════════════════════════════════════════════════════════════════
-- [4] HELPERS
-- ═══════════════════════════════════════════════════════════════════

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

-- ── Hitung durasi Tween berdasarkan jarak & TeleportSpeed ────────
local function TweenDuration(from, to)
    local dist = (from - to).Magnitude
    -- TeleportSpeed = stud/detik → durasi = jarak / kecepatan
    return math.max(0.5, dist / CFG.TeleportSpeed)
end

-- ── Tween karakter ke posisi ──────────────────────────────────────
local function TweenChar(targetPos)
    local ok, err = pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local dur = TweenDuration(hrp.Position, targetPos)
        local cf  = CFrame.new(targetPos)
        TwnSvc:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = cf }):Play()
        task.wait(dur + CFG.WaitAtPoint)
    end)
    if not ok then warn("[TweenChar] Error:", err) end
end

-- ── Tween kendaraan ke posisi ─────────────────────────────────────
--   PENTING: pcall dipakai agar tidak crash kalau pemain keluar kendaraan
local function TweenCar(car, targetPos, targetCF)
    local ok, err = pcall(function()
        if not (car and car.PrimaryPart) then
            warn("[TweenCar] Car atau PrimaryPart nil.")
            return false
        end

        local fromPos = car.PrimaryPart.Position
        local dur     = TweenDuration(fromPos, targetPos)
        local destCF  = targetCF or CFrame.new(targetPos)

        -- Matikan rendering sebentar untuk efisiensi & hindari deteksi visual
        RunSvc:Set3dRenderingEnabled(false)
        task.wait(0.1)
        car:PivotTo(destCF)
        task.wait(0.1)
        RunSvc:Set3dRenderingEnabled(true)

        task.wait(CFG.WaitAtPoint) -- tunggu server sync
        return true
    end)
    if not ok then warn("[TweenCar] Error:", err) end
    return ok
end

-- ── Cek apakah pemain di dalam kendaraan ─────────────────────────
local function InVehicle()
    local ok, r = pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end)
    return ok and r
end

-- ── Cari kendaraan milik pemain di Workspace ─────────────────────
local function FindCar()
    local v = workspace:FindFirstChild("Vehicles")
    return v and v:FindFirstChild(LP.Name .. "sCar")
end

-- ── Baca uang dari GUI ────────────────────────────────────────────
local function GetMoney()
    local ok, v = pcall(function()
        local t = LP.PlayerGui.Main.Container.Hub.CashFrame.Frame.TextLabel.Text
        return tonumber(t:gsub("[^%d]", "")) or 0
    end)
    return (ok and v) or 0
end

-- ── Format angka dengan titik ribuan ─────────────────────────────
local function Fmt(n)
    if not n then return "0" end
    return tostring(math.floor(n)):reverse()
           :gsub("(%d%d%d)", "%1.")
           :reverse()
           :gsub("^%.", "")
end

-- ── Progress bar ASCII ────────────────────────────────────────────
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

-- ── Cek keyword waypoint Jawa Timur ──────────────────────────────
local function IsJTWaypoint(txt)
    if not txt then return false end
    for _, kw in ipairs(CFG.WaypointKeywords) do
        if txt:find(kw) then return true end
    end
    return false
end

-- ── Rekam koordinat saat ini ──────────────────────────────────────
local function RecordCoord()
    local ok, result = pcall(function()
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return "Karakter tidak ditemukan." end
        local p = hrp.Position
        return string.format(
            "Vector3.new(%.2f, %.2f, %.2f)",
            p.X, p.Y, p.Z
        )
    end)
    return ok and result or "Error saat rekam koordinat."
end

-- ═══════════════════════════════════════════════════════════════════
-- [5] ANTI-AFK
-- ═══════════════════════════════════════════════════════════════════

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
            VIM:SendMouseMoveEvent(
                math.random(-40, 40),
                math.random(-40, 40),
                game
            )
        end)
    end)

    -- Reconnect otomatis setelah respawn
    LP.CharacterAdded:Once(function()
        task.wait(2)
        StartAntiAFK()
    end)

    print("[AntiAFK] Aktif ✓")
end

-- ═══════════════════════════════════════════════════════════════════
-- [6] DISCORD WEBHOOK
-- ═══════════════════════════════════════════════════════════════════

local function SendWebhook(isTargetReached)
    local url = getgenv().GS.WebhookURL or ""
    if url == "" then return end

    -- Hanya kirim saat farming aktif atau target tercapai
    if not getgenv().GS.OnFarming and not isTargetReached then return end

    local now = os.time()

    -- Debounce (skip kecuali target reached)
    if not isTargetReached then
        if (now - getgenv().SS.LastWebhook) < CFG.WHIntervalMin then return end
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
                or  "📊 CDID Farm Log — Jawa Timur",
            color = color,
            description = string.format("**%s**  (`%d`)", LP.Name, LP.UserId),
            fields = {
                { name = "⚡ Status",        value = status,             inline = true  },
                { name = "🗺️ Map",           value = CFG.MapName,        inline = true  },
                { name = "⏱️ Durasi",        value = elapsed.." menit",  inline = true  },
                { name = "💰 Uang",          value = "Rp "..Fmt(money),  inline = true  },
                { name = "📈 Earned",        value = "Rp "..Fmt(earned), inline = true  },
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

-- ═══════════════════════════════════════════════════════════════════
-- [7] FARMING ENGINE
-- ═══════════════════════════════════════════════════════════════════

-- Forward-declare updater UI (diisi setelah UI terbuat)
local _setStatus = function(_) end

local function SetStatus(txt)
    pcall(_setStatus, txt)
    print("[CDID Status]", txt)
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

-- ── 7c. Spawn & duduk di kendaraan ───────────────────────────────

local function SpawnAndSit()
    -- Tekan F untuk spawn
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
        warn("[SpawnAndSit] Kendaraan tidak ditemukan setelah 15 percobaan.")
        return nil
    end

    -- Duduk di DriveSeat
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

-- ── 7d. LOOP UTAMA: Truck Farm Jawa Timur ────────────────────────
--
--   Alur setiap siklus:
--   1. Ambil job Truck
--   2. Validasi waypoint Jawa Timur
--   3. Spawn & duduk di kendaraan
--   4. Countdown
--   5. Loop rute: Pickup A → Pickup B → Delivery
--   6. Rejoin
--

local function TruckFarmJawaTimur()
    while task.wait(CFG.CycleDelay) do
        if not getgenv().GS.OnFarming then break end
        if CheckTarget() then break end

        local cycleOk, cycleErr = pcall(function()

            -- STEP 1: Ambil job Truck
            SetStatus("📋 Mengambil job Truck...")
            Fire("Job", "Truck")
            task.wait(0.8)

            -- STEP 2: Cari waypoint Jawa Timur
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
                return
            end

            -- Ambil TextLabel dari BillboardGui waypoint
            local billboard = waypoint:FindFirstChildWhichIsA("BillboardGui", true)
            local wLabel    = billboard and billboard:FindFirstChildWhichIsA("TextLabel", true)
            local labelText = wLabel and wLabel.Text or ""

            -- Paksa waypoint Jawa Timur jika belum sesuai
            local attempt = 0
            while not IsJTWaypoint(labelText) and getgenv().GS.OnFarming do
                attempt = attempt + 1
                if attempt > 25 then
                    SetStatus("⚠️ Waypoint JT tidak muncul setelah 25x — skip cycle.")
                    return
                end

                pcall(function()
                    LP.Character.HumanoidRootPart.Anchored = true
                end)
                Fire("Job", "Truck")
                pcall(fireproximityprompt, workspace.Etc.Job.Truck.Starter.Prompt)
                task.wait(0.8)
                pcall(function()
                    LP.Character.HumanoidRootPart.Anchored = false
                end)

                labelText = wLabel and wLabel.Text or ""
            end

            if not getgenv().GS.OnFarming then return end
            pcall(function() LP.Character.HumanoidRootPart.Anchored = false end)
            SetStatus("✅ Waypoint: " .. labelText)

            -- STEP 3: Spawn & duduk di kendaraan
            local car = SpawnAndSit()
            if not car then
                SetStatus("❌ Gagal siapkan kendaraan — retry cycle.")
                return
            end

            -- STEP 4: Countdown sebelum mulai rute
            for i = CFG.CountdownSec, 1, -1 do
                if not getgenv().GS.OnFarming then return end
                if CheckTarget() then return end
                SetStatus(string.format("⏳ Mulai rute dalam %d detik...", i))
                task.wait(1)
            end

            -- STEP 5: Jalankan rute Pickup → Delivery
            -- ────────────────────────────────────────────────────────
            --   Titik 1: Pickup A  (34937.21, 135.64, -54576.89)
            --   Titik 2: Pickup B  (35160.49, 135.64, -54682.41)
            --   Titik 3: Delivery  (-7845.77, 387.62,  46864.57)
            -- ────────────────────────────────────────────────────────

            for idx, point in ipairs(CFG.TruckRoute) do
                if not getgenv().GS.OnFarming then return end
                if CheckTarget() then return end

                SetStatus(string.format(
                    "🚛 [%d/%d] Menuju %s...",
                    idx, #CFG.TruckRoute, point.label
                ))

                -- Validasi: pemain harus masih di kendaraan
                if not InVehicle() then
                    SetStatus("⚠️ Pemain keluar kendaraan — batal rute.")
                    warn("[TruckFarm] Pemain tidak di kendaraan saat rute ke titik " .. idx)
                    return
                end

                -- Hitung CFrame tujuan (pertahankan rotasi kendaraan saat ini)
                local destCF = CFrame.new(point.pos)
                if car.PrimaryPart then
                    -- Gunakan rotasi asli kendaraan agar lebih natural
                    destCF = CFrame.new(point.pos) * (car.PrimaryPart.CFrame - car.PrimaryPart.CFrame.Position)
                end

                -- Teleport kendaraan ke titik tujuan dengan pcall
                local teleOk = TweenCar(car, point.pos, destCF)
                if not teleOk then
                    SetStatus("⚠️ Teleport gagal di titik " .. idx .. " — skip ke titik berikut.")
                end

                -- Aksi di titik ini
                if point.action == "pickup" then
                    -- Simulasikan interaksi ambil barang
                    pcall(function()
                        -- Cari ProximityPrompt di sekitar
                        for _, obj in ipairs(workspace:GetPartBoundsInBox(
                            CFrame.new(point.pos),
                            Vector3.new(20, 10, 20)
                        )) do
                            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                                    or obj.Parent:FindFirstChildOfClass("ProximityPrompt")
                            if pp then
                                fireproximityprompt(pp)
                                task.wait(0.3)
                            end
                        end
                    end)
                    SetStatus("📦 Barang diambil di " .. point.label)

                elseif point.action == "deliver" then
                    -- Selesaikan pengiriman via RemoteEvent
                    Fire("Job", "Truck")
                    pcall(function()
                        -- Cari ProximityPrompt delivery
                        for _, obj in ipairs(workspace:GetPartBoundsInBox(
                            CFrame.new(point.pos),
                            Vector3.new(30, 15, 30)
                        )) do
                            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                                    or obj.Parent:FindFirstChildOfClass("ProximityPrompt")
                            if pp then
                                fireproximityprompt(pp)
                                task.wait(0.3)
                            end
                        end
                    end)
                    SetStatus("🏁 Pengiriman selesai! Tunggu reward...")
                    task.wait(1.5) -- tunggu server proses reward
                end

                task.wait(CFG.WaitAtPoint)
            end

            -- STEP 6: Rejoin untuk reset job & hindari deteksi
            SetStatus("🔄 Rute selesai — Rejoin server...")
            Fire("Job", "Truck")
            task.wait(getgenv().GS.DelayRejoin or CFG.DelayRejoin)

            pcall(function()
                TelSvc:Teleport(game.PlaceId, LP)
            end)
            task.wait(90)
        end)

        if not cycleOk then
            warn("[TruckFarm] Cycle error:", cycleErr)
            SetStatus("⚠️ Error: " .. tostring(cycleErr):sub(1, 70))
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
            box.Text  = str

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
            local pickup   = Vector3.new(-13716.35, 1052.89, -17997.70)
            local dropoff  = Vector3.new(-13723.75, 1052.89, -17994.23)
            while task.wait(CFG.CycleDelay) and not getgenv().GS.StopFarm do
                pcall(function()
                    local starter = workspace.Etc.Job.JanjiJiwa.Starter.Prompt
                    fireproximityprompt(starter)
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(pickup)
                    task.wait(15)
                    if LP.Backpack:FindFirstChild("Coffee") then
                        LP.Character.HumanoidRootPart.CFrame = CFrame.new(dropoff)
                        Fire("JanjiJiwa", "Delivery")
                    end
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(pickup)
                end)
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- [8] UNLOCK SHOPS
-- ═══════════════════════════════════════════════════════════════════

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
    for _, s in ipairs({ "KiosMarket","Minimarket","SpeedShop","TuningShop","FuelStation" }) do
        pcall(Fire, "OpenShop", s)
        task.wait(0.15)
    end
    return n
end

-- ═══════════════════════════════════════════════════════════════════
-- [9] UI — RAYFIELD
-- ═══════════════════════════════════════════════════════════════════

-- Tunggu game & karakter fully loaded
repeat task.wait(0.1)
until game:IsLoaded()
   and LP
   and LP.Character
   and LP.Character:FindFirstChild("HumanoidRootPart")

-- ── Load Rayfield dengan dual fallback ───────────────────────────

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
        print("[CDID] Rayfield loaded dari:", url)
        break
    end
    warn("[CDID] Gagal load dari:", url)
    task.wait(1)
end

-- Fallback error UI jika Rayfield tidak bisa dimuat sama sekali
if not Rayfield then
    pcall(function()
        local sg  = Instance.new("ScreenGui", LP.PlayerGui)
        sg.Name   = "CDIDErr"
        sg.ResetOnSpawn = false
        local fr  = Instance.new("Frame", sg)
        fr.Size   = UDim2.fromOffset(420, 90)
        fr.Position = UDim2.fromScale(0.5, 0.05)
        fr.AnchorPoint = Vector2.new(0.5, 0)
        fr.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
        Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 8)
        local lbl = Instance.new("TextLabel", fr)
        lbl.Size  = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Text  = "❌ CDID: Gagal load Rayfield!\nPastikan HTTP Request aktif di executor."
        lbl.TextColor3 = Color3.new(1,1,1)
        lbl.TextScaled = true
        lbl.Font  = Enum.Font.GothamBold
    end)
    error("[CDID] FATAL — Rayfield tidak dapat dimuat.")
end

-- Cache network setelah Rayfield berhasil dimuat
CacheNetwork()

-- ── Buat Window utama ─────────────────────────────────────────────

local Window = Rayfield:CreateWindow({
    Name             = CFG.Title,
    LoadingTitle     = CFG.Title,
    LoadingSubtitle  = CFG.Sub,
    ConfigurationSaving = {
        Enabled  = true,
        FileName = "CDID_JT4",
    },
    Discord  = { Enabled = false },
    KeySystem = false,
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

-- ╔════════════════════════════════════╗
-- ║  TAB 1 — HOME                     ║
-- ╚════════════════════════════════════╝

local HomeTab = Window:CreateTab("🏠 Home", "home")

HomeTab:CreateSection("Info Pemain")
HomeTab:CreateLabel("👤 " .. LP.Name .. "   🆔 " .. tostring(LP.UserId))
HomeTab:CreateLabel("🗺️ Map: " .. CFG.MapName .. "   📦 v" .. CFG.Version)
HomeTab:CreateLabel("⚡ CycleDelay: " .. CFG.CycleDelay .. "s  |  TeleportSpeed: " .. CFG.TeleportSpeed)

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
            LP.Character:FindFirstChildOfClass("Humanoid"):ChangeState("Jumping")
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
                    LP.Character.HumanoidRootPart.CFrame =
                        CFrame.new(LP:GetMouse().Hit.Position + Vector3.new(0, 5, 0))
                end)
            end
        end)
    end,
})

-- ╔════════════════════════════════════╗
-- ║  TAB 2 — FARMING                  ║
-- ╚════════════════════════════════════╝

local FarmTab = Window:CreateTab("🚛 Farming", "truck")

FarmTab:CreateSection("📊 Status Real-Time")

local statusPara = FarmTab:CreateParagraph({
    Title   = "Status",
    Content = "Belum dimulai.",
})

local moneyPara = FarmTab:CreateParagraph({
    Title   = "Uang & Progress",
    Content = "Rp 0",
})

-- Hubungkan updater ke paragraph
_setStatus = function(txt)
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
FarmTab:CreateSection("📍 Rute Jawa Timur")

FarmTab:CreateParagraph({
    Title   = "Rute Aktif",
    Content = "1️⃣  Pickup A  — (34937.21, 135.64, -54576.89)\n" ..
              "2️⃣  Pickup B  — (35160.49, 135.64, -54682.41)\n" ..
              "3️⃣  Delivery  — (-7845.77, 387.62,  46864.57)",
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

FarmTab:CreateToggle({
    Name         = "🔔 Countdown Notification",
    CurrentValue = getgenv().GS.CdNotif,
    Flag         = "CdNotif",
    Callback     = function(v)
        getgenv().GS.CdNotif = v
        SM:Save()
    end,
})

FarmTab:CreateDivider()
FarmTab:CreateSection("▶️ Kontrol Farming")

FarmTab:CreateToggle({
    Name         = "🚛  Mulai Truck Farm  (Jawa Timur)",
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
                "▶️ Auto-Farm Jawa Timur dimulai!\nTarget: Rp " .. Fmt(getgenv().GS.TargetEarning),
                5, "play"
            )
            task.spawn(TruckFarmJawaTimur)
        else
            StopAll(false)
            Notif("Farming", "⏹️ Auto-Farm dihentikan.", 4, "stop")
        end
    end,
})

-- ╔════════════════════════════════════╗
-- ║  TAB 3 — SIDE JOBS                ║
-- ╚════════════════════════════════════╝

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

-- ╔════════════════════════════════════╗
-- ║  TAB 4 — TOOLS                    ║
-- ╚════════════════════════════════════╝

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
ToolTab:CreateButton({ Name = "Claim Box",    Callback = function() Fire("Box", "Claim") end })
ToolTab:CreateButton({ Name = "Gamepass Box", Callback = function() Fire("Box", "Buy", "Gamepass Box") end })
ToolTab:CreateButton({ Name = "Limited Box",  Callback = function() Fire("Box", "Buy", "Limited Box") end })

-- Car Slot
ToolTab:CreateSection("🚗 Car Slot")
ToolTab:CreateButton({
    Name     = "⬆️ Upgrade Slot",
    Callback = function() Fire("UpgradeStats", "CarSlot") end,
})

-- ╔════════════════════════════════════╗
-- ║  TAB 5 — WEBHOOK                  ║
-- ╚════════════════════════════════════╝

local WHTab = Window:CreateTab("📡 Webhook", "bell")

WHTab:CreateSection("🔔 Discord Config")

WHTab:CreateParagraph({
    Title   = "Cara Setup Webhook",
    Content = "1. Buka server Discord → Edit Channel\n" ..
              "2. Integrations → Webhooks → Buat Baru\n" ..
              "3. Copy URL → Paste di input bawah\n" ..
              "4. Log dikirim otomatis setiap 5–10 menit",
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
        getgenv().SS.StartMoney  = GetMoney() - 77777
        getgenv().SS.FarmStart   = os.time() - 180
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

WHTab:CreateSection("📋 Konten Log")
WHTab:CreateParagraph({
    Title   = "Data Embed Discord",
    Content = "✅ Username & UserID\n" ..
              "✅ Status (Aktif / Target Reached)\n" ..
              "✅ Uang Saat Ini\n" ..
              "✅ Earned Sesi Ini\n" ..
              "✅ Progress Bar % ke Target\n" ..
              "✅ Durasi Sesi  (menit)\n" ..
              "✅ Timestamp  (tanggal & jam)",
})
WHTab:CreateParagraph({
    Title   = "Anti-Spam",
    Content = "Interval acak " .. CFG.WHIntervalMin/60 ..
              "–" .. CFG.WHIntervalMax/60 ..
              " menit\nDebounce aktif antar pengiriman",
})

-- ╔════════════════════════════════════╗
-- ║  TAB 6 — DEVELOPER                ║
-- ╚════════════════════════════════════╝

local DevTab = Window:CreateTab("🛠️ Developer", "code")

DevTab:CreateSection("📍 Coordinate Recorder")

DevTab:CreateParagraph({
    Title   = "Cara Pakai",
    Content = "1. Pindahkan karakter ke posisi yang ingin direkam\n" ..
              "2. Klik 'Ambil Koordinat'\n" ..
              "3. Koordinat muncul di bawah dan di Output\n" ..
              "4. Copy untuk ditambahkan ke CFG.TruckRoute",
})

-- Label yang diupdate saat rekam koordinat
local coordLabel = DevTab:CreateLabel("📍 Koordinat: (belum direkam)")

DevTab:CreateButton({
    Name     = "📍 Ambil Koordinat Sekarang",
    Callback = function()
        local coord = RecordCoord()
        -- Update label
        pcall(function()
            coordLabel:Set("📍 " .. coord)
        end)
        -- Simpan ke clipboard jika executor mendukung
        pcall(function()
            if setclipboard then
                setclipboard(coord)
                Notif("Coord", "Disalin ke clipboard!\n" .. coord, 6, "copy")
            else
                Notif("Coord", coord, 7, "info")
            end
        end)
        print("[CoordRecorder]", coord)
    end,
})

DevTab:CreateSection("🗺️ Rute Saat Ini")

for i, point in ipairs(CFG.TruckRoute) do
    DevTab:CreateLabel(string.format(
        "[%d] %s\n     (%.2f, %.2f, %.2f)",
        i, point.label,
        point.pos.X, point.pos.Y, point.pos.Z
    ))
end

DevTab:CreateDivider()
DevTab:CreateSection("🔧 Tools Tambahan")

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

-- ╔════════════════════════════════════╗
-- ║  TAB 7 — SETTINGS                 ║
-- ╚════════════════════════════════════╝

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

SettTab:CreateSection("ℹ️ Tentang Script")
SettTab:CreateParagraph({
    Title   = "Info",
    Content = "Versi          : " .. CFG.Version .. "\n" ..
              "UI Library     : Rayfield (sirius.menu)\n" ..
              "CycleDelay     : " .. CFG.CycleDelay .. " detik\n" ..
              "TeleportSpeed  : " .. CFG.TeleportSpeed .. " stud/s\n" ..
              "WaitAtPoint    : " .. CFG.WaitAtPoint .. " detik\n" ..
              "CountdownSec   : " .. CFG.CountdownSec .. " detik\n" ..
              "Rute JT        : " .. #CFG.TruckRoute .. " titik\n" ..
              "Anti-AFK       : Aktif (VirtualInputManager)",
})

-- ═══════════════════════════════════════════════════════════════════
-- [10] INIT — Startup Tasks
-- ═══════════════════════════════════════════════════════════════════

-- Anti-AFK langsung aktif
StartAntiAFK()

-- Validasi map
task.spawn(function()
    local ok, info = pcall(function()
        return MktSvc:GetProductInfo(game.PlaceId)
    end)
    if ok and info then
        local name = info.Name or ""
        local isJT = name:find("Timur") or name:find("Car Driving") or name:find("CDID")
        if isJT then
            Notif("✅ Map OK", "Terdeteksi: " .. name, 5, "check")
        else
            getgenv().GS.OnFarming = false
            Notif(
                "⚠️ Bukan Jawa Timur!",
                "Nama map: " .. name .. "\nAuto-Farm dinonaktifkan.",
                7, "alert"
            )
        end
    end
end)

-- Auto-resume jika config tersimpan OnFarming = true
task.spawn(function()
    task.wait(3)
    if getgenv().GS.OnFarming then
        getgenv().SS.StartMoney  = GetMoney()
        getgenv().SS.FarmStart   = os.time()
        getgenv().SS.LastWebhook = 0
        Notif("Auto-Resume", "Config ditemukan — farming dilanjutkan!", 5, "play")
        SetStatus("♻️ Auto-resume dari config tersimpan...")
        task.spawn(TruckFarmJawaTimur)
    end
end)

print(string.format(
    "[CDID v%s] Loaded | CycleDelay=%.1f | TeleportSpeed=%.1f | Route=%d titik",
    CFG.Version, CFG.CycleDelay, CFG.TeleportSpeed, #CFG.TruckRoute
))
