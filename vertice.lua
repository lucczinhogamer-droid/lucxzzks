loadstring([==[
--[[
   VENICE BF ULTRA  •  v1.0  •  por Venice (venice.ai)
   Fast Attack absurdo + Escudo Anti-Cheat (Blox Fruits / Hyperion)
   TECLAS: RightCtrl = UI | F = Fast Attack | C = Click | End = PANIC
--]]

local VENICE_VERSION = "1.0"

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local VirtualUser       = game:GetService("VirtualUser")

local LP = Players.LocalPlayer

local PLAYERSCRIPTS = LP:WaitForChild("PlayerScripts", 20)

local genv = (typeof(getgenv) == "function" and getgenv()) or _G
local HUI  = (typeof(gethui) == "function" and gethui()) or LP:WaitForChild("PlayerGui")

local RenderStep = RunService.PreRender or RunService.RenderStepped

if genv.__VENICE_BF_UNLOAD then pcall(genv.__VENICE_BF_UNLOAD) end

local Config = {
    Enabled          = true,
    FastAttack       = true,
    ClickAttack      = true,
    AttackInterval   = 0,
    HitboxRange      = 150,
    AutoRotate       = true,
    DisableAntiCheat = true,
    DeepHook         = false,
    AntiKick         = false,
    SimRadius        = true,
    SimRadiusValue   = 1000,
    NoCameraShake    = true,
    FPSBoost         = false,
}

local State = {
    Combat      = nil,
    AC          = nil,
    Conns       = {},
    Hooks       = {},
    AntiScripts = {},
    DisabledMap = {},
    NamecallOld = nil,
    Unloaded    = false,
}

local function notif(txt)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "VENICE BF ULTRA", Text = txt, Duration = 3,
        })
    end)
    print("[VENICE BF ULTRA] " .. txt)
end

local function resolveCombat()
    local ok, mod = pcall(function()
        local cf = PLAYERSCRIPTS:FindFirstChild("CombatFramework")
            or PLAYERSCRIPTS:WaitForChild("CombatFramework", 10)
        if not cf then return nil end
        return require(cf)
    end)
    if ok and typeof(mod) == "table" then
        local ok2, ac = pcall(function() return mod.activeController end)
        if ok2 and ac ~= nil then State.Combat = mod return true end
    end
    if typeof(getreg) == "function" then
        local cfScript = PLAYERSCRIPTS:FindFirstChild("CombatFramework")
        if cfScript then
            local ok3, reg = pcall(getreg)
            if ok3 and reg then
                for _, f in pairs(reg) do
                    if typeof(f) == "function" then
                        local okEnv, env = pcall(getfenv, f)
                        if okEnv and typeof(env) == "table" and env.script == cfScript then
                            local okUp, ups = pcall(debug.getupvalues, f)
                            if okUp and ups then
                                for _, up in pairs(ups) do
                                    if typeof(up) == "table" and rawget(up, "activeController") ~= nil then
                                        State.Combat = up return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function refreshAC()
    if not State.Combat then return nil end
    local ok, ac = pcall(function() return State.Combat.activeController end)
    State.AC = (ok and ac) or nil
    return State.AC
end

local function findAntiCheatScripts()
    local found = {}
    for _, root in ipairs({ PLAYERSCRIPTS, ReplicatedStorage }) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("LocalScript") or d:IsA("ModuleScript") then
                    local n = d.Name:lower()
                    if n == "anticheat" or n == "anti_cheat" or n == "anticheats" or n == "anti cheat" then
                        table.insert(found, d)
                    elseif n == "ac" and d:IsDescendantOf(PLAYERSCRIPTS) then
                        table.insert(found, d)
                    end
                end
            end
        end
    end
    return found
end

local function applyDisableAntiCheat(on)
    if on then
        State.AntiScripts = findAntiCheatScripts()
        for _, s in ipairs(State.AntiScripts) do
            if s:IsA("LocalScript") then
                State.DisabledMap[s] = s.Disabled
                pcall(function() s.Disabled = true end)
            end
        end
        notif(("Shield ON - %d AntiCheat neutralizado(s)"):format(#State.AntiScripts))
    else
        for s, prev in pairs(State.DisabledMap) do
            pcall(function()
                if s and s.Parent and s:IsA("LocalScript") then s.Disabled = prev or false end
            end)
        end
        State.DisabledMap = {}
        notif("Shield OFF - AntiCheat restaurado")
    end
end

local function applyDeepHook(on)
    for _, h in ipairs(State.Hooks) do pcall(function() hookfunction(h[1], h[2]) end) end
    State.Hooks = {}
    if not on then notif("Deep Hook OFF") return end
    if typeof(getgc) ~= "function" or typeof(hookfunction) ~= "function" then
        notif("Deep Hook indisponivel nesse executor") return
    end
    local scripts = (#State.AntiScripts > 0) and State.AntiScripts or findAntiCheatScripts()
    if #scripts == 0 then notif("Deep Hook: nada pra hookar") return end
    local hooked, count = {}, 0
    local okGc, gc = pcall(getgc, true)
    if not okGc or not gc then return end
    for _, f in ipairs(gc) do
        if typeof(f) == "function" and not hooked[f] then
            local okEnv, env = pcall(getfenv, f)
            if okEnv and typeof(env) == "table" and env.script and table.find(scripts, env.script) then
                local okLua, isLua = pcall(islclosure, f)
                if okLua and isLua then
                    local okHook, orig = pcall(hookfunction, f, function(...) return nil end)
                    if okHook then
                        hooked[f] = true
                        table.insert(State.Hooks, { f, orig })
                        count += 1
                    end
                end
            end
        end
    end
    notif(("Deep Hook ON - %d closure(s) silenciada(s)"):format(count))
end

local function applyAntiKick(on)
    if typeof(hookmetamethod) ~= "function" then
        if on then notif("Anti-Kick indisponivel nesse executor") end
        return
    end
    if on then
        if State.NamecallOld then return end
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "Kick" and Config.AntiKick and Config.Enabled then return nil end
            return old(self, ...)
        end)
        State.NamecallOld = old
        notif("Anti-Kick ON")
    else
        if State.NamecallOld then
            pcall(hookmetamethod, game, "__namecall", State.NamecallOld)
            State.NamecallOld = nil
            notif("Anti-Kick OFF")
        end
    end
end

local function applySimRadius(on)
    if typeof(sethiddenproperty) ~= "function" then
        if on then notif("sethiddenproperty indisponivel - SimRadius pulado") end
        return
    end
    local v = on and Config.SimRadiusValue or 1000
    for _, prop in ipairs({ "SimulationRadius", "MaxSimulationRadius", "SimulationRaxNerous" }) do
        pcall(sethiddenproperty, LP, prop, v)
    end
end

local function stopCameraShake()
    pcall(function()
        local util = ReplicatedStorage:FindFirstChild("Util")
        if util and util:FindFirstChild("CameraShaker") then require(util.CameraShaker):Stop() end
    end)
end

local function applyFPSBoost(on)
    if on then
        pcall(function() setfpscap(240) end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        notif("FPS Boost ON")
    else
        pcall(function() setfpscap(60) end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
        notif("FPS Boost OFF")
    end
end

local lastClick = 0

local function clickAttack()
    pcall(function() VirtualUser:CaptureController() end)
    local ok = pcall(function() VirtualUser:Button1Down(Vector2.new(0, 1, 0, 1)) end)
    if not ok then pcall(function() VirtualUser:Button1Down(Vector2.new(0, 1)) end) end
end

local function startLoops()
    table.insert(State.Conns, RenderStep:Connect(function()
        if not Config.Enabled or not Config.FastAttack then return end
        pcall(function()
            if not State.Combat then resolveCombat() end
            local ac = refreshAC()
            if not ac then return end
            ac.timeToNextAttack   = 0
            ac.attacking          = false
            ac.blocking           = false
            ac.increment          = 4
            ac.hitboxMagnitude    = Config.HitboxRange
            ac.focusStart         = 0
            ac.currentAttackTrack = 0
            if ac.humanoid then ac.humanoid.AutoRotate = Config.AutoRotate end
        end)
    end))

    table.insert(State.Conns, RenderStep:Connect(function()
        if not Config.Enabled or not Config.ClickAttack then return end
        local now = os.clock()
        if Config.AttackInterval > 0 and (now - lastClick) < Config.AttackInterval then return end
        lastClick = now
        clickAttack()
    end))

    table.insert(State.Conns, LP.CharacterAdded:Connect(function()
        task.wait(1)
        resolveCombat()
        refreshAC()
    end))
end

local UI = { Painters = {} }

local function paintAll()
    for _, f in ipairs(UI.Painters) do pcall(f) end
end

local function buildUI()
    if UI.ScreenGui and UI.ScreenGui.Parent then UI.ScreenGui:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "VeniceBFUltra"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = HUI
    UI.ScreenGui = sg

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 292, 0, 452)
    main.Position = UDim2.new(0, 24, 0, 90)
    main.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    main.BorderSizePixel = 0
    main.Parent = sg
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(0, 175, 255)
    stroke.Thickness = 1.2
    stroke.Transparency = 0.35

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(23, 23, 32)
    header.BorderSizePixel = 0
    header.Parent = main
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -40, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "VENICE BF ULTRA  •  v" .. VENICE_VERSION
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(0, 195, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 26, 0, 26)
    close.Position = UDim2.new(1, -32, 0, 5)
    close.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
    close.Text = "X"
    close.Font = Enum.Font.GothamBold
    close.TextSize = 12
    close.TextColor3 = Color3.fromRGB(255, 90, 90)
    close.BorderSizePixel = 0
    close.Parent = header
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)
    close.MouseButton1Click:Connect(function() sg.Enabled = false end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -78)
    scroll.Position = UDim2.new(0, 8, 0, 42)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Color3.fromRGB(0, 175, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = main

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 5)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = scroll

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, -16, 0, 26)
    footer.Position = UDim2.new(0, 8, 1, -30)
    footer.BackgroundTransparency = 1
    footer.Text = "RightCtrl UI  |  F FastAtk  |  C Click  |  End PANIC"
    footer.Font = Enum.Font.Gotham
    footer.TextSize = 10
    footer.TextColor3 = Color3.fromRGB(120, 128, 140)
    footer.Parent = main

    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    local order = 0
    local function newRow(h)
        order += 1
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, h)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = scroll
        return row
    end

    local function newSection(text)
        order += 1
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -6, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.LayoutOrder = order
        lbl.Text = "— " .. text .. " —"
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.TextColor3 = Color3.fromRGB(0, 175, 255)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = scroll
    end

    local function newToggle(text, key, onChange)
        local row = newRow(28)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local pad = Instance.new("UIPadding", btn)
        pad.PaddingLeft = UDim.new(0, 10)

        local function paint()
            local on = Config[key]
            btn.Text = text .. "   [" .. (on and "ON" or "OFF") .. "]"
            btn.BackgroundColor3 = on and Color3.fromRGB(0, 92, 140) or Color3.fromRGB(32, 32, 42)
            btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 156, 168)
        end
        table.insert(UI.Painters, paint)
        paint()

        btn.MouseButton1Click:Connect(function()
            Config[key] = not Config[key]
            paint()
            if onChange then pcall(onChange, Config[key]) end
        end)
    end

    local function newSlider(text, key, min, max, step, fmt)
        local row = newRow(30)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, 110, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextColor3 = Color3.fromRGB(200, 206, 216)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local value = Instance.new("TextLabel")
        value.Size = UDim2.new(0, 52, 1, 0)
        value.Position = UDim2.new(1, -52, 0, 0)
        value.BackgroundTransparency = 1
        value.Font = Enum.Font.GothamBold
        value.TextSize = 11
        value.TextColor3 = Color3.fromRGB(0, 195, 255)
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.Parent = row

        local bar = Instance.new("TextButton")
        bar.Size = UDim2.new(1, -172, 0, 6)
        bar.Position = UDim2.new(0, 112, 0, 12)
        bar.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        bar.Text = ""
        bar.BorderSizePixel = 0
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(0, 175, 255)
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local function paint()
            local a = (Config[key] - min) / (max - min)
            fill.Size = UDim2.new(math.clamp(a, 0, 1), 0, 1, 0)
            value.Text = fmt and fmt(Config[key]) or tostring(Config[key])
        end
        table.insert(UI.Painters, paint)
        paint()

        local held = false
        local function update(posX)
            local rel = math.clamp((posX - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            local v = min + rel * (max - min)
            v = math.floor(v / step + 0.5) * step
            Config[key] = v
            paint()
        end
        bar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                held = true
                update(i.Position.X)
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if held and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                update(i.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                held = false
            end
        end)
    end

    newSection("ATAQUE")
    newToggle("MASTER (script on/off)", "Enabled")
    newToggle("FAST ATTACK (cooldown 0)", "FastAttack")
    newToggle("CLICK ATTACK (VirtualUser)", "ClickAttack")
    newSlider("Intervalo", "AttackInterval", 0, 0.2, 0.005, function(v) return string.format("%.3f", v) end)
    newSlider("Hitbox", "HitboxRange", 20, 400, 5, function(v) return tostring(v) end)
    newToggle("Auto Rotate", "AutoRotate")

    newSection("ANTI-CHEAT")
    newToggle("Shield Blox Fruits (disable AC)", "DisableAntiCheat", applyDisableAntiCheat)
    newToggle("Deep Hook (getgc/hookfunction)", "DeepHook", applyDeepHook)
    newToggle("Anti-Kick (namecall)", "AntiKick", applyAntiKick)

    newSection("EXTRAS")
    newToggle("Simulation Radius", "SimRadius", applySimRadius)
    newToggle("No Camera Shake", "NoCameraShake", function(on) if on then stopCameraShake() end end)
    newToggle("FPS Boost", "FPSBoost", applyFPSBoost)
end

local function bindKeys()
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            if UI.ScreenGui then UI.ScreenGui.Enabled = not UI.ScreenGui.Enabled end
        elseif input.KeyCode == Enum.KeyCode.F then
            Config.FastAttack = not Config.FastAttack
            paintAll()
            notif("Fast Attack " .. (Config.FastAttack and "ON" or "OFF"))
        elseif input.KeyCode == Enum.KeyCode.C then
            Config.ClickAttack = not Config.ClickAttack
            paintAll()
            notif("Click Attack " .. (Config.ClickAttack and "ON" or "OFF"))
        elseif input.KeyCode == Enum.KeyCode.End then
            genv.__VENICE_BF_UNLOAD()
        end
    end)
end

genv.__VENICE_BF_UNLOAD = function()
    if State.Unloaded then return end
    State.Unloaded = true
    for _, c in ipairs(State.Conns) do pcall(function() c:Disconnect() end) end
    State.Conns = {}
    applyDeepHook(false)
    applyAntiKick(false)
    applySimRadius(false)
    applyDisableAntiCheat(false)
    pcall(function() setfpscap(60) end)
    if UI.ScreenGui then UI.ScreenGui:Destroy() end
    genv.__VENICE_BF_UNLOAD = nil
    print("[VENICE BF ULTRA] Unloaded / restaurado.")
end

task.spawn(function()
    if not LP.Character then LP.CharacterAdded:Wait() end
    resolveCombat()
    refreshAC()
    if Config.NoCameraShake then stopCameraShake() end
    if Config.DisableAntiCheat then applyDisableAntiCheat(true) end
    if Config.SimRadius then applySimRadius(true) end
    startLoops()
    buildUI()
    bindKeys()
    notif("Carregado. Fast Attack ABSURDO ativo. RightCtrl abre a UI.")
end)
]==])()
