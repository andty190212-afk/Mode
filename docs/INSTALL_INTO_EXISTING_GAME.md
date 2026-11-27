# Установка обновления в уже опубликованную игру (без «Publish As»)

1. Откройте вашу опубликованную игру в Studio (на сайте **Edit in Studio**).
2. **File → Import Roblox Model** → выберите `RIT_Install.rbxm`. В Workspace появится папка `RIT_Install`.
3. **View → Command Bar** (строка команд внизу).
4. Вставьте ОДНУ строку и нажмите Enter:

```lua
local f=workspace:FindFirstChild("RIT_Install",true) assert(f,"RIT_Install not found") for _,src in ipairs(f:GetChildren()) do if src:IsA("Folder") then local dst=src.Name=="StarterPlayerScripts" and game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts") or game:GetService(src.Name) for _,c in ipairs(src:GetChildren()) do local old=dst:FindFirstChild(c.Name) while old do old:Destroy() old=dst:FindFirstChild(c.Name) end c.Parent=dst end end end f:Destroy() print("Restaurant Island Tycoon installed")
```

5. В Output должно появиться `Restaurant Island Tycoon installed`.
6. **File → Publish** (обычная публикация).
7. Creator Hub → ваша игра → **⋯ → Restart Servers**.
