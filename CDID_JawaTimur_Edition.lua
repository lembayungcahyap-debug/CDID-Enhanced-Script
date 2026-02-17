local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "CDID Enhanced - East Java Edition",
   LoadingTitle = "Mengaktifkan Sistem Jawa Timur...",
   LoadingStatus = "by Lembayung",
   ConfigurationSaving = { Enabled = true, FolderName = "CDIDEnhanced" }
})

-- // SETTINGS & VARIABLES //
local Settings = {
    AutoFarm = false,
    TeleportSpeed = 49.5,
    CycleDelay = 0.2,
    TargetEarning = 1000000,
    WebhookURL = ""
}

local CurrentMoney = game:GetService("Players").LocalPlayer.leaderstats.Money -- Sesuaikan dengan nama leaderstats CDID

-- // KOORDINAT JAWA TIMUR (Contoh Rute Populer) //
local JawaTimurPoints = {
    Vector3.new(123, 10, 456), -- Titik A (Contoh)
    Vector3.new(789, 10, 101), -- Titik B (Contoh)
    -- Claude akan mengisi ini lebih detail jika kamu minta refactor rute spesifik
}

-- // FUNCTIONS //
local function SendWebhook(msg)
    if Settings.WebhookURL ~= "" then
        local data = { ["content"] = msg }
        local response = syn and syn.request or http_request or request
        response({ Url = Settings.WebhookURL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = game:GetService("HttpService"):JSONEncode(data) })
    end
end

local function StartFarm()
    spawn(function()
        while Settings.AutoFarm do
            task.wait(Settings.CycleDelay)
            local vehicle = game:GetService("Players").LocalPlayer.Character:FindFirstChild("HumanoidRootPart") -- Cek jika di dalam mobil
            if vehicle then
                for _, point in pairs(JawaTimurPoints) do
                    if not Settings.AutoFarm then break end
                    -- Logic Teleport/Tween
                    local tween = game:GetService("TweenService"):Create(vehicle, TweenInfo.new((vehicle.Position - point).Magnitude/Settings.TeleportSpeed, Enum.EasingStyle.Linear), {CFrame = CFrame.new(point)})
                    tween:Play()
                    tween.Completed:Wait()
                    
                    -- Cek Target
                    if CurrentMoney.Value >= Settings.TargetEarning then
                        Settings.AutoFarm = false
                        Rayfield:Notify({Title = "TARGET REACHED!", Content = "Uang sudah cukup, farming berhenti.", Duration = 5})
                        SendWebhook("✅ Target Tercapai: " .. CurrentMoney.Value)
                        break
                    end
                end
            end
        end
    end)
end

-- // UI TABS //
local MainTab = Window:CreateTab("Auto Farm", 4483362458)

MainTab:CreateToggle({
   Name = "Auto Farm (Jawa Timur)",
   CurrentValue = false,
   Callback = function(Value)
      Settings.AutoFarm = Value
      if Value then StartFarm() end
   end,
})

MainTab:CreateInput({
   Name = "Target Earning",
   PlaceholderText = "Input Angka...",
   Callback = function(Text) Settings.TargetEarning = tonumber(Text) end,
})

local ConfigTab = Window:CreateTab("Settings/Webhook", 4483362458)

ConfigTab:CreateInput({
   Name = "Discord Webhook",
   PlaceholderText = "Paste Link Webhook...",
   Callback = function(Text) Settings.WebhookURL = Text end,
})

-- Anti-AFK
local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

Rayfield:Notify({Title = "Ready!", Content = "Skrip Berhasil Dimuat", Duration = 3})
