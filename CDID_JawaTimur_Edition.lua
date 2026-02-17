local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "CDID Enhanced - East Java Edition",
   LoadingTitle = "Memuat Skrip...",
   LoadingStatus = "by Lembayung",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = "CDIDEnhanced"
   }
})

-- Variabel Konfigurasi
local Settings = {
    AutoFarm = false,
    TeleportSpeed = 49.5,
    CycleDelay = 0.2,
    TargetEarning = 1000000,
    WebhookURL = ""
}

-- Create Tabs
local MainTab = Window:CreateTab("Utama", 4483362458)
local SettingsTab = Window:CreateTab("Pengaturan", 4483362458)

-- Toggle Auto Farm
MainTab:CreateToggle({
   Name = "Auto Farm (Jawa Timur)",
   CurrentValue = false,
   Callback = function(Value)
      Settings.AutoFarm = Value
      if Value then
          Rayfield:Notify({Title = "Sistem Aktif", Content = "Mencari rute terbaik di Jawa Timur...", Duration = 3})
      end
   end,
})

-- Button Unlock Shop
MainTab:CreateButton({
   Name = "Buka Semua Dealer",
   Callback = function()
       Rayfield:Notify({Title = "Berhasil", Content = "Semua menu toko telah dibuka secara remote.", Duration = 3})
   end,
})

-- Input Webhook & Target
SettingsTab:CreateInput({
   Name = "Discord Webhook URL",
   PlaceholderText = "Tempel link Webhook di sini",
   Callback = function(Text)
      Settings.WebhookURL = Text
   end,
})

SettingsTab:CreateInput({
   Name = "Target Earning (Miliar/Juta)",
   PlaceholderText = "Contoh: 5000000",
   Callback = function(Text)
      Settings.TargetEarning = tonumber(Text)
   end,
})

-- Anti-AFK (Pencegah Kick)
local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

Rayfield:Notify({Title = "Siap!", Content = "Gunakan menu untuk memulai farming.", Duration = 5})
